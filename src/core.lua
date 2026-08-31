local ffi = require("ffi")
local sChar = require("sextant_chars")

-- FFI declarations >{
ffi.cdef[[
	typedef unsigned char cc_t;
	typedef unsigned int speed_t;
	typedef unsigned int tcflag_t;

	struct termios {
		tcflag_t c_iflag;
		tcflag_t c_oflag;
		tcflag_t c_cflag;
		tcflag_t c_lflag;
		cc_t c_line;
		cc_t c_cc[32];
		speed_t c_ispeed;
		speed_t c_ospeed;
	};

	struct winsize {
		unsigned short ws_row;
		unsigned short ws_col;
		unsigned short ws_xpixel;
		unsigned short ws_ypixel;
	};

	struct timespec {
		long tv_sec;
		long tv_nsec;
	};

	struct dirent {
		unsigned long d_ino;
		long d_off;
		unsigned short d_reclen;
		unsigned char d_type;
		char d_name[256];
	};

	typedef struct __dirstream DIR;

	int tcgetattr(int fd, struct termios *termios_p);
	int tcsetattr(int fd, int optional_actions, const struct termios *termios_p);
	void cfmakeraw(struct termios *termios_p);
	int ioctl(int fd, unsigned long request, ...);
	int nanosleep(const struct timespec *req, struct timespec *rem);
	int clock_gettime(int clk_id, struct timespec *tp);
	ssize_t read(int fd, void *buf, size_t count);
	int isatty(int fd);
	int open(const char *pathname, int flags);
	int close(int fd);
	DIR *opendir(const char *name);
	struct dirent *readdir(DIR *dirp);
	int closedir(DIR *dirp);
]] -- >}

local libc = ffi.C

local STDIN = 0
local STDOUT = 1
local TCSANOW = 0
local CLOCK_MONOTONIC = 1
local TIOCGWINSZ = 0x5413
local VMIN = 6
local VTIME = 5
local O_RDONLY = 0

local HIDE_CURSOR = "\27[?25l"
local SHOW_CURSOR = "\27[?25h"
local CLEAR_SCREEN = "\27[2J"
local RESET = "\27[0m"
local ENTER_ALT_SCREEN = "\27[?1049h"
local LEAVE_ALT_SCREEN = "\27[?1049l"

-- output buffering: accumulate the whole tick, flush once >{
local output_buf = {}

local function emit(s)
	output_buf[#output_buf + 1] = s
end

local function flush_output()
	if #output_buf > 0 then
		io.write(table.concat(output_buf))
		output_buf = {}
		io.flush()
	end
end

local function goto_rc(row, col)
	return "\27[" .. row .. ";" .. col .. "H"
end
-- >}

-- color helpers >{
local function clamp(v, lo, hi)
	if v < lo then return lo end
	if v > hi then return hi end
	return v
end

local function normalize_color(c)
	if type(c) == "string" then
		local hex = c:match("^#?(%x%x%x%x%x%x)$")
		if not hex then return nil end
		return tonumber(hex:sub(1, 2), 16), tonumber(hex:sub(3, 4), 16), tonumber(hex:sub(5, 6), 16)
	elseif type(c) == "table" then
		local r = c.r or c[1]
		local g = c.g or c[2]
		local b = c.b or c[3]
		if r and g and b then return r, g, b end
	end
	return nil
end

local function fg_seq(c)
	local r, g, b = normalize_color(c)
	if not r then return "" end
	return string.format("\27[38;2;%d;%d;%dm", r, g, b)
end

local function bg_seq(c)
	local r, g, b = normalize_color(c)
	if not r then return "" end
	return string.format("\27[48;2;%d;%d;%dm", r, g, b)
end

local function is_color_array(c)
	if type(c) ~= "table" then return false end
	local first = c[1]
	if first == nil then return false end
	return type(first) == "table" or type(first) == "string"
end

function BandColor(value, min, max, colors)
	if colors == nil then return nil end
	if not is_color_array(colors) then return colors end
	local n = #colors
	if n == 0 then return nil end
	local frac = clamp((value - min) / (max - min), 0, 1)
	local idx = math.floor(frac * n) + 1
	if idx > n then idx = n end
	return colors[idx]
end
-- >}

-- public draw API: Frame >{
local FRAME_CHARS = {
	normal = { tl = "\u{250C}", tr = "\u{2510}", bl = "\u{2514}", br = "\u{2518}", h = "\u{2500}", v = "\u{2502}" },
	bold   = { tl = "\u{250F}", tr = "\u{2513}", bl = "\u{2517}", br = "\u{251B}", h = "\u{2501}", v = "\u{2503}" },
	double = { tl = "\u{2554}", tr = "\u{2557}", bl = "\u{255A}", br = "\u{255D}", h = "\u{2550}", v = "\u{2551}" },
}

local FRAME_COLOR = { r = 0x6c, g = 0x70, b = 0x86 }
local BOLD = "\27[1m"
local BOLD_OFF = "\27[22m"

function Frame(pane, title, border_style)
	local ch = FRAME_CHARS[border_style] or FRAME_CHARS.normal
	local w, h = pane.w, pane.h
	if w < 2 or h < 2 then return end

	local color = fg_seq(FRAME_COLOR)

	local inner = w - 2
	local label = ""
	if title and title ~= "" then
		label = " " .. title .. " "
		if #label > inner then label = label:sub(1, inner) end
	end
	local LABEL_OFFSET = 4 -- label text starts 5 chars from the corner
	local pre_n = math.max(math.min(LABEL_OFFSET, inner - #label), 0)
	local fill_n = math.max(inner - pre_n - #label, 0)
	local pre = string.rep(ch.h, pre_n)
	local fill = string.rep(ch.h, fill_n)
	local label_styled = (label ~= "") and (BOLD .. label .. BOLD_OFF) or label
	emit(goto_rc(pane.y + 1, pane.x + 1) .. color .. ch.tl .. pre .. label_styled .. fill .. ch.tr .. RESET)

	for row = 1, h - 2 do
		emit(goto_rc(pane.y + 1 + row, pane.x + 1) .. color .. ch.v .. RESET)
		emit(goto_rc(pane.y + 1 + row, pane.x + w) .. color .. ch.v .. RESET)
	end

	emit(goto_rc(pane.y + h, pane.x + 1) .. color .. ch.bl .. string.rep(ch.h, math.max(inner, 0)) .. ch.br .. RESET)
end
-- >}

-- public draw API: Bar >{
local V_EIGHTHS = { "\u{2581}", "\u{2582}", "\u{2583}", "\u{2584}", "\u{2585}", "\u{2586}", "\u{2587}" }
local H_EIGHTHS = { "\u{258F}", "\u{258E}", "\u{258D}", "\u{258C}", "\u{258B}", "\u{258A}", "\u{2589}" }
local FULL_BLOCK = "\u{2588}"
local EMPTY = " "

function Bar(pane, value, min, max, orientation, colors)
	orientation = orientation or "vertical"
	local color = BandColor(value, min, max, colors)
	local prefix = color and fg_seq(color) or ""
	local suffix = color and RESET or ""

	if pane.w <= 0 or pane.h <= 0 then return end

	if orientation == "horizontal" then
		local total_eighths = math.floor(clamp((value - min) / (max - min), 0, 1) * pane.w * 8 + 0.5)
		local full_cols = math.min(math.floor(total_eighths / 8), pane.w)
		local remainder = total_eighths - full_cols * 8
		local line = {}
		for _ = 1, full_cols do line[#line + 1] = FULL_BLOCK end
		if remainder > 0 and full_cols < pane.w then
			line[#line + 1] = H_EIGHTHS[remainder]
			full_cols = full_cols + 1
		end
		for _ = full_cols + 1, pane.w do line[#line + 1] = EMPTY end
		local row_str = prefix .. table.concat(line) .. suffix
		for row = 0, pane.h - 1 do
			emit(goto_rc(pane.y + 1 + row, pane.x + 1) .. row_str)
		end
	else
		local total_eighths = math.floor(clamp((value - min) / (max - min), 0, 1) * pane.h * 8 + 0.5)
		local full_rows = math.min(math.floor(total_eighths / 8), pane.h)
		local remainder = total_eighths - full_rows * 8
		for row = 0, pane.h - 1 do
			local ch
			if row < full_rows then
				ch = FULL_BLOCK
			elseif row == full_rows and remainder > 0 then
				ch = V_EIGHTHS[remainder]
			else
				ch = EMPTY
			end
			local screen_row = pane.y + (pane.h - row)
			emit(goto_rc(screen_row, pane.x + 1) .. prefix .. string.rep(ch, pane.w) .. suffix)
		end
	end
end
-- >}

-- public draw API: Graph (sextant blocks, 2x3 sub-cell resolution) >{
function Graph(pane, history_data, orientation, color)
	orientation = orientation or "horizontal"
	if pane.w <= 0 or pane.h <= 0 then return end

	local values = (history_data and history_data.values) or {}
	local min = (history_data and history_data.min) or 0
	local max = (history_data and history_data.max) or 100
	local prefix = color and fg_seq(color) or ""
	local suffix = color and RESET or ""
	local n = #values

	if orientation == "horizontal" then
		local sample_cols = pane.w * 2
		local vres = pane.h * 3
		local function sample_at(slot)
			local idx = n - (sample_cols - slot)
			if idx < 1 then return nil end
			return values[idx]
		end
		for row = 0, pane.h - 1 do
			local line = {}
			for col = 0, pane.w - 1 do
				local mask = 0
				for c = 0, 1 do
					local v = sample_at(col * 2 + c + 1)
					if v ~= nil then
						local frac = clamp((v - min) / (max - min), 0, 1)
						local level = math.floor(frac * vres + 0.5)
						for p = 0, 2 do
							local global_row = row * 3 + p
							local from_bottom = vres - 1 - global_row
							if from_bottom < level then
								mask = mask + 2 ^ (p * 2 + c)
							end
						end
					end
				end
				line[#line + 1] = sChar[mask]
			end
			emit(goto_rc(pane.y + 1 + row, pane.x + 1) .. prefix .. table.concat(line) .. suffix)
		end
	else
		local sample_rows = pane.h * 3
		local vres = pane.w * 2
		local function sample_at(slot)
			local idx = n - (sample_rows - slot)
			if idx < 1 then return nil end
			return values[idx]
		end
		for row = 0, pane.h - 1 do
			local mask_col = {}
			for col = 0, pane.w - 1 do mask_col[col] = 0 end
			for p = 0, 2 do
				local v = sample_at(row * 3 + p + 1)
				if v ~= nil then
					local frac = clamp((v - min) / (max - min), 0, 1)
					local level = math.floor(frac * vres + 0.5)
					for col = 0, pane.w - 1 do
						for c = 0, 1 do
							if col * 2 + c < level then
								mask_col[col] = mask_col[col] + 2 ^ (p * 2 + c)
							end
						end
					end
				end
			end
			local line = {}
			for col = 0, pane.w - 1 do line[#line + 1] = sChar[mask_col[col]] end
			emit(goto_rc(pane.y + 1 + row, pane.x + 1) .. prefix .. table.concat(line) .. suffix)
		end
	end
end
-- >}

-- public draw API: Axis >{
local function auto_ticks(min, max, count)
	count = math.max(count, 2)
	local ticks = {}
	for i = 0, count - 1 do
		local v = min + (max - min) * i / (count - 1)
		ticks[#ticks + 1] = (v == math.floor(v)) and tostring(math.floor(v)) or string.format("%.1f", v)
	end
	return ticks
end

-- generates evenly spaced, integer tick labels (including min) dividing
-- [min,max] into a power-of-two number of parts (2, 4, 8, ...) -- the
-- largest power of two that still fits within `budget` ticks. Non-exact
-- values are floored, e.g. 8 parts of 0-100 -> 0,12,25,37,50,62,75,87,100.
function Pow2Ticks(min, max, budget)
	local divisions = 1
	while divisions * 2 <= budget do divisions = divisions * 2 end
	divisions = math.max(divisions, 2)
	local ticks = {}
	for i = 0, divisions do
		local v = min + (max - min) * i / divisions
		ticks[#ticks + 1] = tostring(math.floor(v))
	end
	return ticks
end

function Axis(pane, scale_x, scale_y, labels)
	labels = labels or {}

	if scale_y then
		for row = 0, pane.h - 1 do
			emit(goto_rc(pane.y + 1 + row, pane.x + 1) .. "\u{2502}")
		end
		local yticks = labels.y or auto_ticks(scale_y.min, scale_y.max, math.max(2, math.floor(pane.h / 4)))
		local nticks = math.max(#yticks - 1, 1)
		local last_row = math.huge
		for i, text in ipairs(yticks) do
			local row = pane.h - 1 - math.floor((i - 1) * (pane.h - 1) / nticks)
			if last_row - row >= 1 then
				local col = pane.x - #text - 1
				if col >= 0 then
					emit(goto_rc(pane.y + 1 + row, col + 1) .. text)
				end
				last_row = row
			end
		end
	end

	if scale_x then
		emit(goto_rc(pane.y + pane.h + 1, pane.x + 1) .. string.rep("\u{2500}", pane.w))
		local xticks = labels.x or auto_ticks(scale_x.min, scale_x.max, math.max(2, math.floor(pane.w / 8)))
		local nticks = math.max(#xticks - 1, 1)
		local last_end = -math.huge
		for i, text in ipairs(xticks) do
			local col = math.floor((i - 1) * (pane.w - 1) / nticks)
			if col + #text > pane.w then col = math.max(pane.w - #text, 0) end
			if col > last_end then
				emit(goto_rc(pane.y + pane.h + 2, pane.x + 1 + col) .. text)
				last_end = col + #text
			end
		end
	end
end
-- >}

-- public draw API: WriteAt (plain text/labels at an absolute pane-relative position) >{
function WriteAt(x, y, str, fg, bg)
	local prefix = (fg and fg_seq(fg) or "") .. (bg and bg_seq(bg) or "")
	local suffix = (fg or bg) and RESET or ""
	emit(goto_rc(y + 1, x + 1) .. prefix .. str .. suffix)
end
-- >}

-- proc filesystem helpers, shared by base and custom modules >{
function ReadProcFile(path)
	local fd = libc.open(path, O_RDONLY)
	if fd < 0 then return nil end
	local bufsize = 8192
	local buf = ffi.new("char[?]", bufsize)
	local chunks = {}
	while true do
		local n = libc.read(fd, buf, bufsize)
		if n <= 0 then break end
		chunks[#chunks + 1] = ffi.string(buf, n)
		if n < bufsize then break end
	end
	libc.close(fd)
	if #chunks == 0 then return nil end
	return table.concat(chunks)
end

function ListProcPids()
	local pids = {}
	local dir = libc.opendir("/proc")
	if dir == nil then return pids end
	while true do
		local entry = libc.readdir(dir)
		if entry == nil then break end
		local name = ffi.string(entry.d_name)
		if name:match("^%d+$") then
			pids[#pids + 1] = tonumber(name)
		end
	end
	libc.closedir(dir)
	return pids
end
-- >}

-- terminal raw mode >{
local orig_termios = ffi.new("struct termios")

local function enter_raw_mode()
	libc.tcgetattr(STDIN, orig_termios)
	local raw = ffi.new("struct termios")
	ffi.copy(raw, orig_termios, ffi.sizeof("struct termios"))
	libc.cfmakeraw(raw)
	raw.c_cc[VMIN] = 0
	raw.c_cc[VTIME] = 0
	libc.tcsetattr(STDIN, TCSANOW, raw)
end

local function leave_raw_mode()
	libc.tcsetattr(STDIN, TCSANOW, orig_termios)
end

local winsz = ffi.new("struct winsize")
local function get_term_size()
	libc.ioctl(STDOUT, TIOCGWINSZ, winsz)
	return winsz.ws_col, winsz.ws_row
end

local input_buf = ffi.new("char[16]")
local function read_key()
	local n = libc.read(STDIN, input_buf, 16)
	if not n or n <= 0 then return nil end
	-- with VMIN=0/VTIME=0 a single read() drains whatever is already queued,
	-- so a real multi-byte escape sequence (arrow/function/home/end keys)
	-- arrives as more than one byte, starting with ESC, in the same read;
	-- only a LONE ESC byte is treated as the ESC key itself, so a sequence
	-- led by ESC is ignored instead of being misread as a plain ESC keypress.
	-- A multi-byte read NOT led by ESC is just two ordinary keypresses that
	-- happened to land in the same poll (e.g. a fast key repeat) -- the
	-- first one is processed normally, same as before this ESC handling.
	if n > 1 and input_buf[0] == 27 then return nil end
	return input_buf[0]
end
-- >}

-- timing helpers >{
local ts_now = ffi.new("struct timespec")
function MonotonicNow()
	libc.clock_gettime(CLOCK_MONOTONIC, ts_now)
	return tonumber(ts_now.tv_sec) + tonumber(ts_now.tv_nsec) * 1e-9
end

local ts_sleep = ffi.new("struct timespec")
local function sleep_ms(ms)
	ts_sleep.tv_sec = math.floor(ms / 1000)
	ts_sleep.tv_nsec = (ms % 1000) * 1000000
	libc.nanosleep(ts_sleep, nil)
end
-- >}

-- CLI argument parsing >{
local VERSION = "0.3.0"

local function print_usage()
	io.write("Usage: resmon [options]\n\n")
	io.write("Options:\n")
	io.write("  --config-dir <path>     Override the default config dir (~/.config/resmon)\n")
	io.write("  --config-file <path>    Override the config file path (default: <config-dir>/config.lua)\n")
	io.write("  --fetchers-dir <path>   Override the fetchers dir (default: <config-dir>/addons/fetchers)\n")
	io.write("  --modules-dir <path>    Override the custom modules dir (default: <config-dir>/addons/mods)\n")
	io.write("  -h, --help              Show this help message and exit\n")
	io.write("  -v, --version           Show version and exit\n")
end

local function parse_args()
	local opts = {}
	local a = arg or {}
	local i = 1
	while i <= #a do
		local flag = a[i]
		if flag == "-h" or flag == "--help" then
			print_usage()
			os.exit(0)
		elseif flag == "-v" or flag == "--version" then
			io.write("resmon " .. VERSION .. "\n")
			os.exit(0)
		elseif flag == "--config-dir" or flag == "--config-file" or flag == "--fetchers-dir" or flag == "--modules-dir" then
			local value = a[i + 1]
			if not value then
				io.stderr:write("resmon: missing value for " .. flag .. "\n")
				os.exit(1)
			end
			if flag == "--config-dir" then opts.config_dir = value
			elseif flag == "--config-file" then opts.config_file = value
			elseif flag == "--fetchers-dir" then opts.fetchers_dir = value
			else opts.modules_dir = value end
			i = i + 1
		else
			io.stderr:write("resmon: unknown option '" .. flag .. "'\n")
			os.exit(1)
		end
		i = i + 1
	end
	return opts
end

local function resolve_paths(opts)
	local home = os.getenv("HOME") or ""
	local config_dir = opts.config_dir or (home .. "/.config/resmon")
	local config_file = opts.config_file or (config_dir .. "/config.lua")
	local fetchers_dir = opts.fetchers_dir or (config_dir .. "/addons/fetchers")
	local modules_dir = opts.modules_dir or (config_dir .. "/addons/mods")
	return config_file, fetchers_dir, modules_dir
end
-- >}

-- config, fetcher and module loading >{
local BASE_MODULES = { cpu = true, mem = true, top = true }
local BASE_FETCHERS = { CPU_Average = true, MEM = true, TOP = true }

local DEFAULT_CONFIG = {
	orientation = "vertical",
	fetchers = {
		{ name = "CPU_Average", refresh = 60 },
		{ name = "MEM", refresh = 1.5 },
		{ name = "TOP", refresh = 1.5 },
	},
	modules = {
		{ name = "cpu", mod = "cpu", fetcher = { "CPU_Average" } },
		{ name = "mem", mod = "mem", fetcher = { "MEM" } },
		{ name = "top", mod = "top", fetcher = { "TOP" } },
	},
}

local function load_config(config_file)
	local chunk = loadfile(config_file)
	if not chunk then return nil end
	local ok, cfg = pcall(chunk)
	if not ok or type(cfg) ~= "table" then return nil end
	return cfg
end

-- keeps only the first entry per `name`; later duplicates are dropped with a
-- warning -- applied identically to fetchers and modules, whose `name` must
-- both be config-unique (a module's `mod`/file id may repeat, its `name` may not)
local function dedup_by_name(list, kind)
	local seen, out = {}, {}
	for _, e in ipairs(list) do
		if seen[e.name] then
			io.stderr:write("resmon: duplicate " .. kind .. " name '" .. tostring(e.name) .. "', skipping\n")
		else
			seen[e.name] = true
			out[#out + 1] = e
		end
	end
	return out
end

-- marks entry._bad = true in place for any module whose fetcher={} list
-- references a name absent from the (deduped) declared fetchers, or whose
-- fetcher list is empty/missing -- every display module must depend on at
-- least one fetcher
local function mark_bad_modules(cfg_modules, cfg_fetchers)
	local names = {}
	for _, fe in ipairs(cfg_fetchers) do names[fe.name] = true end
	for _, e in ipairs(cfg_modules) do
		for _, fname in ipairs(e.fetcher or {}) do
			if not names[fname] then
				io.stderr:write("resmon: module '" .. tostring(e.name) .. "' references unknown fetcher '" .. tostring(fname) .. "', marking BAD\n")
				e._bad = true
			end
		end
		if not e._bad and #(e.fetcher or {}) == 0 then
			io.stderr:write("resmon: module '" .. tostring(e.name) .. "' declares no fetcher, marking BAD\n")
			e._bad = true
		end
	end
end

-- sets fe.not_used = true in place on any fetcher referenced by zero
-- surviving (non-BAD) modules -- these are never loaded or scheduled
local function mark_unused_fetchers(cfg_fetchers, cfg_modules)
	local used = {}
	for _, e in ipairs(cfg_modules) do
		if not e._bad then
			for _, fname in ipairs(e.fetcher or {}) do used[fname] = true end
		end
	end
	for _, fe in ipairs(cfg_fetchers) do
		if not used[fe.name] then fe.not_used = true end
	end
end

local function valid_module(mod)
	return type(mod) == "table"
		and type(mod.title) == "string"
		and type(mod.min_w) == "number"
		and type(mod.min_h) == "number"
		and type(mod.redraw) == "function"
end

local function valid_fetcher(f)
	return type(f) == "table"
		and type(f.fetch) == "function"
		and type(f.default_delay) == "number"
end

-- the config entry is passed through as the chunk's varargs (`...`), same as
-- for display modules, so a fetcher wrapping an external process (e.g.
-- GPU_Top_AMD spawning amdgpu_top) can size its own polling interval from
-- entry.refresh instead of hardcoding one independently of the scheduler
local function resolve_fetcher(entry, fetchers_dir)
	if BASE_FETCHERS[entry.name] then
		local loader = package.preload["fetch_" .. entry.name:lower()]
		if not loader then return nil, "missing base fetcher 'fetch_" .. entry.name:lower() .. "'" end
		local ok, f = pcall(loader, entry)
		if not ok then return nil, f end
		return f
	end
	local path = fetchers_dir .. "/" .. entry.name .. ".lua"
	local chunk, err = loadfile(path)
	if not chunk then return nil, err end
	local ok, f = pcall(chunk, entry)
	if not ok then return nil, f end
	return f
end

-- builds the module's cache array (direct references into fetch_cache[name].data,
-- ordered per entry.fetcher) then loads the module chunk, passing (entry, cache)
-- as its varargs; base modules are resolved by calling the preloaded chunk
-- directly rather than require() (which memoizes and would prevent loading
-- the same base module twice, under different instance names, with different
-- fetchers/config)
local function resolve_module(entry, modules_dir, fetch_cache)
	local cache = {}
	for i, fname in ipairs(entry.fetcher or {}) do
		local fc = fetch_cache[fname]
		if not fc then return nil, "unknown or unloaded fetcher '" .. tostring(fname) .. "'" end
		cache[i] = fc.data
	end
	if BASE_MODULES[entry.mod] then
		local loader = package.preload["mod_" .. entry.mod]
		if not loader then return nil, "missing base module 'mod_" .. entry.mod .. "'" end
		local ok, mod = pcall(loader, entry, cache)
		if not ok then return nil, mod end
		return mod
	end
	local path = modules_dir .. "/" .. entry.mod .. ".lua"
	local chunk, err = loadfile(path)
	if not chunk then return nil, err end
	-- the config entry and the module's own cache array are passed through as
	-- the chunk's varargs (`...`), so a module can read its own config fields
	-- and its fetched data alike
	local ok, mod = pcall(chunk, entry, cache)
	if not ok then return nil, mod end
	return mod
end
-- >}

-- layout engine >{
-- A negative "weight" means an exact line count along the stacking axis,
-- not a proportional share: it is subtracted from the total up front, and
-- the remaining space is split proportionally among the positive-weight
-- (or default-weight) entries. The last entry always absorbs whatever is
-- left over, so the layout fills the terminal exactly regardless of
-- rounding, matching the existing convention for positive weights.
local function compute_layout(term_w, term_h, orientation, entries)
	local n = #entries
	if n == 0 then return {} end

	local total_space = (orientation == "horizontal") and term_w or term_h
	local fixed_total = 0
	local weight_total = 0
	for _, e in ipairs(entries) do
		local w = e.weight or 1
		if w < 0 then
			fixed_total = fixed_total + (-w)
		else
			weight_total = weight_total + w
		end
	end
	if weight_total <= 0 then weight_total = 1 end
	local remaining = math.max(total_space - fixed_total, 0)

	local panes = {}
	local pos = 0
	for i, e in ipairs(entries) do
		local w = e.weight or 1
		local size
		if i == n then
			size = total_space - pos
		elseif w < 0 then
			size = -w
		else
			size = math.floor(remaining * w / weight_total)
		end
		if orientation == "horizontal" then
			panes[i] = { x = pos, y = 0, w = math.max(size, 0), h = term_h }
		else
			panes[i] = { x = 0, y = pos, w = term_w, h = math.max(size, 0) }
		end
		pos = pos + size
	end
	return panes
end
-- >}

-- bootstrap >{
local function fatal(msg)
	io.stderr:write("resmon: " .. tostring(msg) .. "\n")
	os.exit(1)
end

local function cleanup()
	leave_raw_mode()
	io.write(RESET .. SHOW_CURSOR .. LEAVE_ALT_SCREEN)
	io.flush()
end

local function main()
	local opts = parse_args()
	local config_file, fetchers_dir, modules_dir = resolve_paths(opts)

	if libc.isatty(STDIN) == 0 then
		fatal("stdin is not a terminal")
	end

	local cfg = load_config(config_file) or DEFAULT_CONFIG
	local orientation = cfg.orientation or "vertical"
	local cfg_fetchers = dedup_by_name(cfg.fetchers or DEFAULT_CONFIG.fetchers, "fetcher")
	local cfg_modules = dedup_by_name(cfg.modules or DEFAULT_CONFIG.modules, "module")

	mark_bad_modules(cfg_modules, cfg_fetchers)
	mark_unused_fetchers(cfg_fetchers, cfg_modules)

	local fetch_cache, loaded_fetchers = {}, {}
	for _, fe in ipairs(cfg_fetchers) do
		if not fe.not_used then
			local fetcher, err = resolve_fetcher(fe, fetchers_dir)
			if fetcher and valid_fetcher(fetcher) then
				fetch_cache[fe.name] = { data = {} }
				loaded_fetchers[#loaded_fetchers + 1] = { entry = fe, fetcher = fetcher }
			else
				io.stderr:write("resmon: skipping fetcher '" .. tostring(fe.name) .. "': " .. tostring(err or "invalid fetcher shape") .. "\n")
			end
		end
	end

	local entries, mods, mods_dict = {}, {}, {}
	for _, e in ipairs(cfg_modules) do
		if not e._bad then
			local mod, err = resolve_module(e, modules_dir, fetch_cache)
			if mod and valid_module(mod) then
				local idx = #entries + 1
				entries[idx] = e
				mods[idx] = mod
				mods_dict[e.name] = { mod = mod, index = idx }
			else
				io.stderr:write("resmon: skipping module '" .. tostring(e.name) .. "': " .. tostring(err or "invalid module shape") .. "\n")
			end
		end
	end

	if #mods == 0 then
		fatal("no valid modules to display")
	end

	-- one scheduler entry per loaded fetcher; `mods` lists the (surviving)
	-- module instance names that depend on it, resolved via mods_dict at
	-- dispatch time
	local scheduler = {}
	for _, lf in ipairs(loaded_fetchers) do
		local sched_mods = {}
		for _, e in ipairs(entries) do
			for _, fname in ipairs(e.fetcher or {}) do
				if fname == lf.entry.name then sched_mods[#sched_mods + 1] = e.name end
			end
		end
		local delay = lf.fetcher.default_delay
		if lf.entry.refresh and not lf.fetcher.fixed_delay then delay = lf.entry.refresh end
		scheduler[#scheduler + 1] = { name = lf.entry.name, fetch = lf.fetcher.fetch, default_delay = delay, last_run = 0, mods = sched_mods }
	end

	enter_raw_mode()
	io.write(ENTER_ALT_SCREEN .. CLEAR_SCREEN .. HIDE_CURSOR)
	io.flush()

	local last_w, last_h = 0, 0
	local panes = {}

	local function relayout()
		local w, h = get_term_size()
		last_w, last_h = w, h
		local outers = compute_layout(w, h, orientation, entries)
		panes = {}
		for i, outer in ipairs(outers) do
			panes[i] = {
				x = outer.x + 1,
				y = outer.y + 1,
				w = math.max(outer.w - 2, 0),
				h = math.max(outer.h - 2, 0),
			}
		end
		emit(CLEAR_SCREEN)
		for i, outer in ipairs(outers) do
			Frame(outer, mods[i].title, "normal")
		end
		flush_output()

		-- force every fetcher to refire on the next tick: the screen was just
		-- cleared, so stale "not due yet" content would otherwise show as
		-- blank; refiring every fetcher transitively re-buffers every module
		-- that depends on it
		for _, sched in ipairs(scheduler) do sched.last_run = 0 end
	end

	relayout()

	local paused = false
	local running = true

	while running do
		local key = read_key()
		if key == 27 or key == string.byte("q") or key == string.byte("Q") then
			running = false
		elseif key == string.byte("p") or key == string.byte("P") then
			paused = not paused
		end

		if running then
			local w, h = get_term_size()
			if w ~= last_w or h ~= last_h then
				relayout()
			end

			if not paused then
				local now = MonotonicNow()
				local buf = {}
				for _, sched in ipairs(scheduler) do
					if now - sched.last_run >= sched.default_delay then
						sched.last_run = now
						local data, status, err = sched.fetch()
						local cd = fetch_cache[sched.name].data
						if status == 0 then
							-- overwrite fields in place, never replace the table
							-- itself: modules hold a direct reference to `cd`
							for k, v in pairs(data) do cd[k] = v end
							cd._ERROR = nil
						else
							cd._ERROR = true
							if err then cd._ERROR_MSG = err end
						end
						for _, mname in ipairs(sched.mods) do buf[mname] = true end
					end
				end
				for mname in pairs(buf) do
					local rec = mods_dict[mname]
					if rec then rec.mod.redraw(panes[rec.index]) end
				end
				flush_output()
			end

			sleep_ms(30)
		end
	end

	cleanup()
end

main()
-- >}

-- vim: filetype=lua foldmethod=marker foldmarker=>{,>}
