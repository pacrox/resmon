local ffi = require("ffi")
local sChar = require("sextant_chars")
Write = require("block_fonts") -- global: public draw API for custom modules, see block_fonts.lua
FakeFetcher = require("fake_fetcher") -- global: standalone-CLI fake-data generator, see fake_fetcher.lua

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
local VERSION = "0.4.0"

-- path-override flags, accepted both by the normal app and by the
-- standalone addon CLI, in any position relative to an addon_name token
-- (extracted centrally by extract_path_opts(), see main())
local PATH_FLAGS = {
	["-c"] = "config_file",
	["--config-dir"] = "config_dir",
	["--config-file"] = "config_file",
	["--fetchers-dir"] = "fetchers_dir",
	["--modules-dir"] = "modules_dir",
	["--include"] = "include_dir",
}

local USAGE_LABEL_W = 26 -- widest label is "-c, --config-file <file>" (24 chars) + 2-space gap

local function print_usage()
	io.write("Usage: resmon [options]\n")
	io.write("       resmon <addon_name> [options]   Run a single addon standalone (see -h/-i/-s/-d on the addon itself)\n\n")
	io.write("Options:\n")
	local function opt(label, descr)
		io.write(string.format("  %-" .. USAGE_LABEL_W .. "s%s\n", label, descr))
	end
	local function cont(descr)
		io.write(string.rep(" ", 2 + USAGE_LABEL_W) .. descr .. "\n")
	end
	opt("--config-dir <dir>", "Override the default config dir (~/.config/resmon); implies")
	cont("<dir>/addons/{fetchers,mods} unless overridden below")
	opt("-c, --config-file <file>", "Read this config file instead of <config-dir>/config.lua")
	cont("(does not affect where fetchers/mods are searched)")
	opt("--fetchers-dir <dir>", "Override the fetchers dir (default: <config-dir>/addons/fetchers)")
	opt("--modules-dir <dir>", "Override the custom modules dir (default: <config-dir>/addons/mods)")
	opt("--include <path>", "Additively search this flat dir first (fetchers and modules mixed);")
	cont("a relative <path> resolves against the current working dir")
	opt("--list", "List every installed fetcher and module, with a short description")
	opt("-h, --help", "Show this help message and exit")
	opt("-v, --version", "Show version and exit")
end

-- pulls the PATH_FLAGS out of `args` wherever they appear, since they're
-- accepted on either side of a standalone addon_name token (or with no
-- addon_name at all, for the normal app); returns the collected opts table
-- plus the remaining tokens with those consumed
local function extract_path_opts(args)
	local opts, rest = {}, {}
	local i = 1
	while i <= #args do
		local tok = args[i]
		local key = PATH_FLAGS[tok]
		if key then
			local value = args[i + 1]
			if not value then
				io.stderr:write("resmon: missing value for " .. tok .. "\n")
				os.exit(1)
			end
			opts[key] = value
			i = i + 1
		else
			rest[#rest + 1] = tok
		end
		i = i + 1
	end
	return opts, rest
end

-- normal-app-mode flags only (-h/-v); path flags are already stripped out of
-- `rest` by extract_path_opts() before this runs
local function parse_args(rest)
	for _, flag in ipairs(rest) do
		if flag == "-h" or flag == "--help" then
			print_usage()
			os.exit(0)
		elseif flag == "-v" or flag == "--version" then
			io.write("resmon " .. VERSION .. "\n")
			os.exit(0)
		else
			io.stderr:write("resmon: unknown option '" .. flag .. "'\n")
			os.exit(1)
		end
	end
end

-- opts.include_dir (from --include, may be nil) is returned as-is, never
-- joined onto config_dir: a relative --include path resolves against the
-- process's own CWD, same as any relative path Lua's loadfile receives,
-- since core.lua never chdir()s
local function resolve_paths(opts)
	local home = os.getenv("HOME") or ""
	local config_dir = opts.config_dir or (home .. "/.config/resmon")
	local config_file = opts.config_file or (config_dir .. "/config.lua")
	local fetchers_dir = opts.fetchers_dir or (config_dir .. "/addons/fetchers")
	local modules_dir = opts.modules_dir or (config_dir .. "/addons/mods")
	return config_file, fetchers_dir, modules_dir, opts.include_dir
end
-- >}

-- config, fetcher and module loading >{

-- special-tag usable in a module's fetcher={...} config list to mean "no
-- fetcher at this slot" without introducing a hole (keeps the list
-- ipairs-safe); resolve_module translates NONE into an actual nil in the
-- cache array it builds, so a multi-fetcher module must read `cache` with
-- an explicit `for i=1,#entry.fetcher do`, never `ipairs(cache)`
NONE = "NONE"

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
			if fname ~= NONE and not names[fname] then
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
			for _, fname in ipairs(e.fetcher or {}) do
				if fname ~= NONE then used[fname] = true end
			end
		end
	end
	for _, fe in ipairs(cfg_fetchers) do
		if not used[fe.name] then fe.not_used = true end
	end
end

-- every addon (fetcher or module; base or custom; loaded via the normal
-- config-driven scheduler or via the standalone `resmon <addon>` CLI) must
-- pass this same shape gate before it is used for anything -- see
-- _CLAUDE/Resmon0_4_0-HelpDoc-3.md for the full info/opts/sample contract
local function valid_module(mod)
	return type(mod) == "table"
		and type(mod.title) == "string"
		and type(mod.min_w) == "number"
		and type(mod.min_h) == "number"
		and type(mod.redraw) == "function"
		and type(mod.info) == "table"
		and type(mod.info.name) == "string"
		and type(mod.info.long_name) == "string"
		and mod.info.type == "module"
		and type(mod.opts) == "table"
		and type(mod.sample) == "table"
end

local function valid_fetcher(f)
	return type(f) == "table"
		and type(f.fetch) == "function"
		and type(f.default_delay) == "number"
		and type(f.info) == "table"
		and type(f.info.name) == "string"
		and type(f.info.long_name) == "string"
		and f.info.type == "fetcher"
		and type(f.opts) == "table"
end

-- the config entry is passed through as the chunk's varargs (`...`), same as
-- for display modules, so a fetcher wrapping an external process (e.g.
-- GPU_Top_AMD spawning amdgpu_top) can size its own polling interval from
-- entry.refresh instead of hardcoding one independently of the scheduler.
-- `include_dir` (from --include, additive, may be nil) is tried FIRST, ahead
-- of both base and normal custom lookup, so a same-named addon under
-- development shadows the installed one -- applies uniformly to the
-- config-driven scheduler and the standalone CLI, since both funnel through
-- this same function.
local function resolve_fetcher(entry, fetchers_dir, include_dir)
	if include_dir then
		local chunk = loadfile(include_dir .. "/" .. entry.name .. ".lua")
		if chunk then
			local ok, f = pcall(chunk, entry)
			if not ok then return nil, f end
			return f
		end
	end
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

-- pure loader: resolves entry.mod to a chunk (base preload, --include, or
-- custom loadfile) and runs it with the caller-supplied `cache` array as its
-- second vararg -- the config-driven scheduler path (resolve_module, below)
-- builds `cache` from fetch_cache; the standalone CLI path (run_addon_cli)
-- builds its own (fake data, or -f-attached real fetchers), sharing this
-- same load. `include_dir` shadows both base and normal custom lookup, same
-- rationale as resolve_fetcher above.
local function resolve_module_chunk(entry, modules_dir, cache, include_dir)
	if include_dir then
		local chunk = loadfile(include_dir .. "/" .. entry.mod .. ".lua")
		if chunk then
			local ok, mod = pcall(chunk, entry, cache)
			if not ok then return nil, mod end
			return mod
		end
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

-- builds the module's cache array (direct references into fetch_cache[name].data,
-- ordered per entry.fetcher, NONE translated to a hole) then delegates to
-- resolve_module_chunk
local function resolve_module(entry, modules_dir, fetch_cache, include_dir)
	local cache = {}
	for i, fname in ipairs(entry.fetcher or {}) do
		if fname == NONE then
			cache[i] = nil
		else
			local fc = fetch_cache[fname]
			if not fc then return nil, "unknown or unloaded fetcher '" .. tostring(fname) .. "'" end
			cache[i] = fc.data
		end
	end
	return resolve_module_chunk(entry, modules_dir, cache, include_dir)
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

local function fatal(msg)
	io.stderr:write("resmon: " .. tostring(msg) .. "\n")
	os.exit(1)
end

-- standalone addon CLI: `resmon <addon_name> [options]` >{

local function sorted_keys(t)
	local keys = {}
	for k in pairs(t) do keys[#keys + 1] = k end
	table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
	return keys
end

-- lists every file in `path` ending in `suffix`, with the suffix stripped
-- (same FFI opendir/readdir/closedir pattern as ListProcPids above); used
-- by --list to discover custom addon names without shelling out
local function list_dir(path, suffix)
	local names = {}
	local dir = libc.opendir(path)
	if dir == nil then return names end
	while true do
		local entry = libc.readdir(dir)
		if entry == nil then break end
		local name = ffi.string(entry.d_name)
		if #name > #suffix and name:sub(- #suffix) == suffix then
			names[#names + 1] = name:sub(1, #name - #suffix)
		end
	end
	libc.closedir(dir)
	return names
end

-- addon-specific flags only: path flags (--config-dir/-c etc.) are already
-- extracted centrally by extract_path_opts() before this ever runs, since
-- they're accepted on either side of the addon_name token
-- -i/-h/-s/-d are cumulative, not mutually exclusive: e.g. `-h -i -s -d`
-- runs all four modes in the order given -- -h/-i/-s just print to normal
-- stdout so their output sits in scrollback above the (alt-screen) -d demo,
-- readable once the user quits it
local function parse_addon_args(args)
	local aopts = { modes = {}, options = {} }
	local i = 1
	while i <= #args do
		local flag = args[i]
		if flag == "-i" or flag == "--info" then
			aopts.modes[#aopts.modes + 1] = "info"
		elseif flag == "-h" or flag == "--help" then
			aopts.modes[#aopts.modes + 1] = "help"
		elseif flag == "-s" or flag == "--sample" then
			aopts.modes[#aopts.modes + 1] = "sample"
		elseif flag == "-d" or flag == "--demo" then
			aopts.modes[#aopts.modes + 1] = "demo"
		elseif flag == "-x" or flag == "--width" then
			local value = args[i + 1]
			if not value then io.stderr:write("resmon: missing value for " .. flag .. "\n"); os.exit(1) end
			aopts.width = tonumber(value)
			i = i + 1
		elseif flag == "-y" or flag == "--height" then
			local value = args[i + 1]
			if not value then io.stderr:write("resmon: missing value for " .. flag .. "\n"); os.exit(1) end
			aopts.height = tonumber(value)
			i = i + 1
		elseif flag == "-r" or flag == "--refresh" then
			local value = args[i + 1]
			if not value then io.stderr:write("resmon: missing value for " .. flag .. "\n"); os.exit(1) end
			aopts.refresh = tonumber(value)
			i = i + 1
		elseif flag == "-f" or flag == "--fetcher" then
			-- consumes every following token up to the next flag: a variable-length
			-- list of fetcher names (or NONE), module-only
			aopts.fetchers = {}
			while args[i + 1] and args[i + 1]:sub(1, 1) ~= "-" do
				aopts.fetchers[#aopts.fetchers + 1] = args[i + 1]
				i = i + 1
			end
		elseif flag == "-o" or flag == "--options" then
			local value = args[i + 1]
			if not value then io.stderr:write("resmon: missing value for " .. flag .. "\n"); os.exit(1) end
			-- trusted local CLI input (the user's own machine), evaluated as a Lua
			-- table-constructor expression and merged onto the addon's synthetic
			-- entry exactly like a config.lua modules={{...}} entry would be
			local chunk, load_err = load("return " .. value)
			if not chunk then
				io.stderr:write("resmon: invalid -o/--options value: " .. tostring(load_err) .. "\n")
				os.exit(1)
			end
			local ok, tbl = pcall(chunk)
			if not ok or type(tbl) ~= "table" then
				io.stderr:write("resmon: -o/--options value must evaluate to a Lua table\n")
				os.exit(1)
			end
			aopts.options = tbl
			i = i + 1
		else
			io.stderr:write("resmon: unknown option '" .. flag .. "'\n")
			os.exit(1)
		end
		i = i + 1
	end
	return aopts
end

-- shallow-merges `options` (from -o/--options, may be nil) onto a fresh
-- synthetic entry table -- options win, since they're the explicit CLI
-- override; this is exactly the shape a config.lua modules={{...}} entry
-- already takes, so no addon-side changes are needed for -o to work
local function synth_entry(base, options)
	if options then
		for k, v in pairs(options) do base[k] = v end
	end
	return base
end

local function try_fetch(name, fetchers_dir, include_dir, options)
	local f, err = resolve_fetcher(synth_entry({ name = name }, options), fetchers_dir, include_dir)
	if f and valid_fetcher(f) then return f end
	return nil, err
end

local function try_mod(name, modules_dir, include_dir, options)
	local m, err = resolve_module_chunk(synth_entry({ mod = name }, options), modules_dir, {}, include_dir)
	if m and valid_module(m) then return m end
	return nil, err
end

-- resolves an addon_name (with or without an explicit fetch./mod. prefix) to
-- its kind, bare name and a probe-loaded addon table (loaded with a
-- throwaway cache -- only its info/opts/sample are meaningful, its redraw
-- closure is NOT usable, see run_module_sample/run_module_demo); a bare
-- name tries fetch.<name> first, then mod.<name>, first shape-valid match
-- wins
local function resolve_cli_addon(addon_name, fetchers_dir, modules_dir, include_dir, options)
	local fname = addon_name:match("^fetch%.(.+)$")
	if fname then
		local f, err = try_fetch(fname, fetchers_dir, include_dir, options)
		if f then return "fetch", fname, f, nil end
		return nil, nil, nil, err or "invalid fetcher shape"
	end
	local mname = addon_name:match("^mod%.(.+)$")
	if mname then
		local m, err = try_mod(mname, modules_dir, include_dir, options)
		if m then return "mod", mname, m, nil end
		return nil, nil, nil, err or "invalid module shape"
	end
	local f = try_fetch(addon_name, fetchers_dir, include_dir, options)
	if f then return "fetch", addon_name, f, nil end
	local m = try_mod(addon_name, modules_dir, include_dir, options)
	if m then return "mod", addon_name, m, nil end
	return nil, nil, nil, "no such addon 'fetch." .. addon_name .. "' or 'mod." .. addon_name .. "'"
end

local function print_opts_help(opts)
	local keys = sorted_keys(opts)
	if #keys == 0 then
		io.write("    (no configurable options)\n")
		return
	end
	for _, k in ipairs(keys) do
		local default, descr = opts[k][1], opts[k][2]
		io.write(string.format("    %-12s%-12s%s\n", k, tostring(default), descr or ""))
	end
end

-- -h/--help output: "Name:" block (addon.info.name/long_name) followed by
-- "Options:" (the addon's own configurable options, with defaults) -- not
-- the same thing as no-mode (print_addon_usage), which lists the CLI flags
-- this addon understands
local function print_addon_help(addon)
	io.write("Name:\n")
	io.write("    " .. addon.info.name .. "      " .. addon.info.long_name .. "\n\n")
	io.write("Options:\n")
	print_opts_help(addon.opts)
end

-- no-mode output: the addon's long_name plus the list of CLI flags IT
-- accepts -- distinct from -h/--help, which lists the addon's own
-- *configurable options* (opts), not the CLI flags
local function print_addon_usage(kind, addon)
	io.write(addon.info.long_name .. "\n\n")
	io.write("Options:\n")
	io.write("  -i, --info                       Show addon info/metadata\n")
	io.write("  -h, --help                       Show this addon's configurable options\n")
	io.write("  -s, --sample [-x <w>] [-y <h>]    One-shot static sample\n")
	io.write("  -d, --demo [-x <w>] [-y <h>]      Live-updating demo (P=pause, Q/ESC/CTRL-C=quit)\n")
	io.write("  -r, --refresh <value>             Set the refresh rate (real or fake-data tick rate)\n")
	io.write("  -o, --options <{lua-table}>       Merge these options onto the addon's config, like config.lua\n")
	if kind == "mod" then
		io.write("  -f, --fetcher <f> [<f> ...]      Use real fetcher(s) instead of fake data (NONE ok)\n")
	end
end

-- `target` is addon-author-authored data (from the addon's own info.dependencies),
-- not external user input: shelling out to `command -v` is safe here and gives
-- a real PATH+executable-bit check, simpler than a hand-rolled PATH scanner
local function check_dependency(target)
	if target:sub(1, 1) == "/" then
		local f = io.open(target, "r")
		if f then f:close(); return true end
		return false
	end
	local escaped = target:gsub("'", "'\\''")
	return os.execute("command -v '" .. escaped .. "' >/dev/null 2>&1") == 0
end

local function print_addon_info(kind, addon)
	local info = addon.info
	io.write(info.long_name .. " (" .. info.name .. ")\n")
	if info.short_descr then io.write(info.short_descr .. "\n") end
	io.write("\n")
	if info.description then io.write(info.description .. "\n\n") end
	io.write("Author:  " .. tostring(info.author) .. "\n")
	io.write("Release: " .. tostring(info.release) .. "\n")
	if info.date then io.write("Date:    " .. tostring(info.date) .. "\n") end
	if kind == "fetch" then
		if info.data_type then io.write("Data:    " .. info.data_type .. "\n") end
		if info.hardware then io.write("Hardware: " .. info.hardware .. "\n") end
		io.write("Refresh: " .. tostring(addon.default_delay) .. "s (default)\n")
	elseif info.dependencies then
		-- module info.dependencies is a list of data_type strings (docs-only),
		-- NOT the same semantic as a fetcher's info.dependencies below
		io.write("Depends on: " .. table.concat(info.dependencies, ", ") .. "\n")
	end
	io.write("\nOptions:\n")
	print_opts_help(addon.opts)
	if kind == "fetch" and info.dependencies then
		io.write("\nDependencies:\n")
		for _, dep in ipairs(info.dependencies) do
			local ok = check_dependency(dep.target)
			io.write("  [" .. (ok and "OK" or "MISSING") .. "] " .. dep.target .. " -- " .. tostring(dep.descr) .. "\n")
		end
	end
end

-- scans a string for the "key":{"unit":"U","value":V} leaf shape used
-- throughout amdgpu_top/intel_gpu_top-derived JSON (see GPU_Top_AMD/INTEL's
-- own extract_field/extract_object helpers, which read the exact same
-- shape) and returns { {key, value, unit}, ... } for every leaf found
-- anywhere in the string, regardless of nesting depth -- a single flat
-- gmatch pass, not a real JSON parser
local function format_json_leaves(str)
	local leaves = {}
	for k, unit, value in str:gmatch('"([^"]+)"%s*:%s*{%s*"unit"%s*:%s*"([^"]*)"%s*,%s*"value"%s*:%s*([%-%d%.eE]+)') do
		leaves[#leaves + 1] = { k, value, unit }
	end
	return leaves
end

-- a data value that is a JSON-looking string (raw payload text from a
-- fetcher like GPU_Top_AMD) is illegible dumped verbatim -- render its
-- recognized "key":{"unit":,"value":} leaves as plain "key: value unit"
-- lines instead; a string with no recognized leaves falls back to a short
-- opaque placeholder rather than a raw dump
local function format_string_value(v)
	if not v:match("^%s*{") then return nil end
	local leaves = format_json_leaves(v)
	if #leaves == 0 then return { ("(opaque data, %d bytes)"):format(#v) } end
	local lines = {}
	for _, leaf in ipairs(leaves) do
		local key, value, unit = leaf[1], leaf[2], leaf[3]
		lines[#lines + 1] = key .. ": " .. value .. (unit ~= "" and (" " .. unit) or "")
	end
	return lines
end

local function print_data_value(indent, k, v, ranges)
	if type(v) == "table" then
		io.write(indent .. tostring(k) .. ":\n")
		for _, sk in ipairs(sorted_keys(v)) do
			print_data_value(indent .. "  ", sk, v[sk], nil)
		end
		return
	end
	if type(v) == "string" then
		local lines = format_string_value(v)
		if lines then
			io.write(indent .. tostring(k) .. ":\n")
			for _, line in ipairs(lines) do
				io.write(indent .. "  " .. line .. "\n")
			end
			return
		end
	end
	local s = tostring(v)
	local r = ranges and ranges[k]
	if r and type(v) == "number" then
		local norm = math.max(0, math.min(100, (v - r[1]) / (r[2] - r[1]) * 100))
		s = s .. " (" .. string.format("%.0f", norm) .. "%)"
	end
	io.write(indent .. tostring(k) .. " = " .. s .. "\n")
end

-- delta-based fetchers (e.g. CPU_Cores) need a prior sample to diff against,
-- so a truly first fetch() would read as all-zero; discard one throwaway
-- call before keeping the result. Pipe-based fetchers (e.g. GPU_Top_AMD)
-- have their own multi-second warm-up latency which this does not attempt
-- to wait out -- their first -s sample may legitimately look idle/empty,
-- which is expected and documented, not a bug.
local function sample_fetch_once(fetcher)
	fetcher.fetch()
	sleep_ms(300)
	return fetcher.fetch()
end

local function run_fetcher_sample(fetcher)
	local data, status, err = sample_fetch_once(fetcher)
	if status ~= 0 then
		io.stderr:write("resmon: fetch failed: " .. tostring(err or "unknown error") .. "\n")
		os.exit(1)
	end
	for _, k in ipairs(sorted_keys(data)) do
		print_data_value("", k, data[k], fetcher.ranges)
	end
end

-- queries the terminal for the cursor's current absolute row via a DSR
-- (Device Status Report, \27[6n) query, so a static -s sample can use
-- WriteAt/Frame's absolute-position API without alt-screen, landing exactly
-- where the shell's own output left off instead of clobbering an arbitrary
-- row at the top of the visible screen (output must stay in scrollback).
local function query_cursor_row()
	enter_raw_mode()
	io.write("\27[6n")
	io.flush()
	local resp = ""
	local deadline = MonotonicNow() + 0.5
	while not resp:match("R") and MonotonicNow() < deadline do
		local n = libc.read(STDIN, input_buf, 16)
		if n and n > 0 then
			resp = resp .. ffi.string(input_buf, n)
		else
			sleep_ms(5)
		end
	end
	leave_raw_mode()
	local row = resp:match("%[(%d+);%d+R")
	return tonumber(row)
end

local function sample_pane_size(aopts, min_w, min_h)
	local term_w, term_h = get_term_size()
	local w = aopts.width or math.max(math.floor(term_w / 2), min_w)
	local h = aopts.height or math.max(math.min(12, term_h - 4), min_h)
	return w, h
end

-- fake-fills any cache slot not covered by -f (or every slot, if -f wasn't
-- given at all); an explicit NONE in the -f list leaves that slot genuinely
-- empty, matching the real app's semantics; a slot fetcher that fails to
-- resolve falls back to fake data rather than aborting the whole demo/sample
local function build_module_cache(sample, fetch_specs, fetchers_dir, include_dir)
	local cache, real_fetchers = {}, {}
	for i = 1, #sample do
		local fname = fetch_specs and fetch_specs[i]
		if fname == NONE then
			cache[i] = nil
		elseif fname then
			local f, err = resolve_fetcher({ name = fname }, fetchers_dir, include_dir)
			if f and valid_fetcher(f) then
				cache[i] = {}
				real_fetchers[i] = f
			else
				io.stderr:write("resmon: skipping fetcher '" .. fname .. "': " .. tostring(err or "invalid fetcher shape") .. "\n")
				cache[i] = {}
			end
		else
			cache[i] = {}
		end
	end
	return cache, real_fetchers
end

-- default pace (seconds) for regenerating a fake-data slot when no -r
-- override is given -- lets the standalone CLI's fake-data drift be
-- observed tick by tick instead of redrawing continuously
local FAKE_TICK_DEFAULT = 1.0

-- aopts.refresh (if given) overrides every slot uniformly; otherwise a
-- real-fetcher-backed slot uses that fetcher's own default_delay, a fake
-- slot uses FAKE_TICK_DEFAULT
local function slot_delays(sample, real_fetchers, aopts)
	local delays = {}
	for i = 1, #sample do
		delays[i] = aopts.refresh or (real_fetchers[i] and real_fetchers[i].default_delay) or FAKE_TICK_DEFAULT
	end
	return delays
end

-- ticks any (real or fake) slot whose own delay has elapsed since its last
-- update, tracked per-slot in `last_run` (mutated in place). poll_real=false
-- never re-invokes a real fetcher -- used only by prefill_module_history's
-- synthetic 120-tick replay, where re-polling a real fetcher would either
-- block for a very long time (a pipe-based fetcher, paced by its own
-- production rate) or corrupt a delta-based fetcher's reading (successive
-- calls with no real time gap between them read as ~0); a real slot's
-- cache just keeps whatever a single proper fetch already put there.
local function tick_module_cache(cache, sample, real_fetchers, fake, delays, last_run, now, poll_real)
	local fresh
	for i = 1, #sample do
		if cache[i] and now - (last_run[i] or 0) >= delays[i] then
			last_run[i] = now
			if real_fetchers[i] then
				if poll_real then
					local data, status = real_fetchers[i].fetch()
					if status == 0 then
						for k, v in pairs(data) do cache[i][k] = v end
					end
				end
			else
				fresh = fresh or fake.generate(sample)
				for k, v in pairs(fresh[i]) do cache[i][k] = v end
			end
		end
	end
end

-- loads a module twice: once with a throwaway cache just to learn its
-- `sample` shape (needed because some modules branch on cache[i]'s presence
-- at load time, e.g. mod.clock_graph's optional GPU line -- see
-- resolve_module's own cache-before-load ordering, which this mirrors),
-- then for real with a properly-sized cache built from that shape
local function load_module_for_demo(base_name, aopts, modules_dir, fetchers_dir, include_dir)
	local probe_entry = synth_entry({ mod = base_name }, aopts.options)
	local probe = resolve_module_chunk(probe_entry, modules_dir, {}, include_dir)
	if not probe or not valid_module(probe) then fatal("invalid module shape for 'mod." .. base_name .. "'") end

	local cache, real_fetchers = build_module_cache(probe.sample, aopts.fetchers, fetchers_dir, include_dir)
	local real_entry = synth_entry({ mod = base_name }, aopts.options)
	local mod = resolve_module_chunk(real_entry, modules_dir, cache, include_dir)
	if not mod or not valid_module(mod) then fatal("invalid module shape for 'mod." .. base_name .. "'") end

	return mod, cache, real_fetchers
end

-- history-based graph modules (any module with an `interval` opt) plot a
-- rolling time window built from many past redraw() calls -- a single
-- sample tick leaves that window almost entirely empty. Pre-fill it by
-- replaying fake ticks across a synthetic timeline, temporarily overriding
-- the global MonotonicNow so each replayed sample lands at the right point
-- in the module's own rolling window, then discard everything these warm-up
-- redraws emitted (their pane position is irrelevant, only the side effect
-- on the module's internal history matters). Harmless no-op for modules
-- with no rolling history: redraw() just re-renders the same latest value
-- FILL_TICKS times, last call wins.
local SAMPLE_FILL_TICKS = 120

local function prefill_module_history(mod, cache, real_fetchers, fake, w, h, aopts)
	local interval = (mod.opts.interval and mod.opts.interval[1]) or 30
	local delays = slot_delays(mod.sample, real_fetchers, aopts)
	local last_run = {}
	local real_now = MonotonicNow()
	local real_monotonic_now = MonotonicNow
	for i = 0, SAMPLE_FILL_TICKS - 1 do
		local fake_t = real_now - interval + interval * i / (SAMPLE_FILL_TICKS - 1)
		MonotonicNow = function() return fake_t end
		tick_module_cache(cache, mod.sample, real_fetchers, fake, delays, last_run, fake_t, false)
		mod.redraw({ x = 1, y = 1, w = w, h = h })
	end
	MonotonicNow = real_monotonic_now
	output_buf = {} -- discard the warm-up passes' redundant emitted output
end

local function run_module_sample(base_name, aopts, modules_dir, fetchers_dir, include_dir)
	if libc.isatty(STDIN) == 0 then fatal("stdin is not a terminal") end

	local mod, cache, real_fetchers = load_module_for_demo(base_name, aopts, modules_dir, fetchers_dir, include_dir)
	for i, f in pairs(real_fetchers) do
		local data, status = sample_fetch_once(f)
		if status == 0 then
			for k, v in pairs(data) do cache[i][k] = v end
		end
	end
	local fake = FakeFetcher.new()

	local w, h = sample_pane_size(aopts, mod.min_w, mod.min_h)
	prefill_module_history(mod, cache, real_fetchers, fake, w, h, aopts)

	local outer_h = h + 2

	io.write(string.rep("\n", outer_h + 1))
	io.write("\27[" .. (outer_h + 1) .. "A")
	io.flush()
	local anchor_row = query_cursor_row()
	if not anchor_row then
		fatal("terminal did not respond to a cursor-position query, cannot render sample")
	end

	local outer = { x = 0, y = anchor_row - 1, w = w + 2, h = outer_h }
	Frame(outer, mod.title, "normal")
	mod.redraw({ x = 1, y = anchor_row, w = w, h = h })
	flush_output()
	io.write("\27[" .. (anchor_row + outer_h) .. ";1H\n")
	io.flush()
end

local function run_module_demo(base_name, aopts, modules_dir, fetchers_dir, include_dir)
	if libc.isatty(STDIN) == 0 then fatal("stdin is not a terminal") end

	local mod, cache, real_fetchers = load_module_for_demo(base_name, aopts, modules_dir, fetchers_dir, include_dir)
	local fake = FakeFetcher.new()
	local delays = slot_delays(mod.sample, real_fetchers, aopts)
	local last_run = {}

	enter_raw_mode()
	io.write(ENTER_ALT_SCREEN .. CLEAR_SCREEN .. HIDE_CURSOR)
	io.flush()

	local function draw(w, h)
		emit(CLEAR_SCREEN)
		Frame({ x = 0, y = 0, w = w, h = h }, mod.title, "normal")
		mod.redraw({ x = 1, y = 1, w = math.max(w - 2, 0), h = math.max(h - 2, 0) })
		flush_output()
	end

	local term_w, term_h = get_term_size()
	local w = aopts.width or term_w
	local h = aopts.height or term_h
	draw(w, h)

	local paused, running = false, true
	while running do
		local key = read_key()
		if key == 27 or key == string.byte("q") or key == string.byte("Q") then
			running = false
		elseif key == string.byte("p") or key == string.byte("P") then
			paused = not paused
		end
		if running then
			if not aopts.width or not aopts.height then
				local nw, nh = get_term_size()
				if not aopts.width then w = nw end
				if not aopts.height then h = nh end
			end
			if not paused then
				tick_module_cache(cache, mod.sample, real_fetchers, fake, delays, last_run, MonotonicNow(), true)
				draw(w, h)
			end
			sleep_ms(30)
		end
	end

	leave_raw_mode()
	io.write(RESET .. SHOW_CURSOR .. LEAVE_ALT_SCREEN)
	io.flush()
end

-- WriteAt-based counterpart to print_data_value, used by the live -d
-- fetcher demo: recurses into nested tables (e.g. CPU_Cores'/CPU_Clock's
-- per-core map, otherwise silently invisible) and pretty-prints a
-- JSON-looking string value via format_string_value (e.g. GPU_Top_AMD's raw
-- payload fields), same rendering rules as -s, adapted to row-tracking
-- instead of io.write
local function write_data_value(x, row, indent, k, v, ranges)
	if type(v) == "table" then
		WriteAt(x, row, indent .. tostring(k) .. ":")
		row = row + 1
		for _, sk in ipairs(sorted_keys(v)) do
			row = write_data_value(x, row, indent .. "  ", sk, v[sk], nil)
		end
		return row
	end
	if type(v) == "string" then
		local lines = format_string_value(v)
		if lines then
			WriteAt(x, row, indent .. tostring(k) .. ":")
			row = row + 1
			for _, line in ipairs(lines) do
				WriteAt(x, row, indent .. "  " .. line)
				row = row + 1
			end
			return row
		end
	end
	local s = tostring(v)
	local r = ranges and ranges[k]
	if r and type(v) == "number" then
		local norm = math.max(0, math.min(100, (v - r[1]) / (r[2] - r[1]) * 100))
		s = s .. " (" .. string.format("%.0f", norm) .. "%)"
	end
	WriteAt(x, row, indent .. tostring(k) .. " = " .. s)
	return row + 1
end

local function run_fetcher_demo(fetcher, aopts)
	if libc.isatty(STDIN) == 0 then fatal("stdin is not a terminal") end

	local delay = aopts.refresh or fetcher.default_delay

	enter_raw_mode()
	io.write(ENTER_ALT_SCREEN .. CLEAR_SCREEN .. HIDE_CURSOR)
	io.flush()

	local paused, running, last_run = false, true, 0
	while running do
		local key = read_key()
		if key == 27 or key == string.byte("q") or key == string.byte("Q") then
			running = false
		elseif key == string.byte("p") or key == string.byte("P") then
			paused = not paused
		end
		if running then
			local now = MonotonicNow()
			if not paused and now - last_run >= delay then
				last_run = now
				local data, status, err = fetcher.fetch()
				emit(CLEAR_SCREEN)
				if status == 0 then
					local row = 0
					for _, k in ipairs(sorted_keys(data)) do
						row = write_data_value(0, row, "", k, data[k], fetcher.ranges)
					end
				else
					WriteAt(0, 0, "fetch error: " .. tostring(err or "unknown"))
				end
				flush_output()
			end
			sleep_ms(30)
		end
	end

	leave_raw_mode()
	io.write(RESET .. SHOW_CURSOR .. LEAVE_ALT_SCREEN)
	io.flush()
end

local function run_addon_cli(addon_name, rest_args, path_opts)
	local aopts = parse_addon_args(rest_args)
	local _, fetchers_dir, modules_dir, include_dir = resolve_paths(path_opts)
	local kind, base_name, addon, err = resolve_cli_addon(addon_name, fetchers_dir, modules_dir, include_dir, aopts.options)
	if not kind then fatal("unknown addon '" .. addon_name .. "': " .. tostring(err)) end

	if #aopts.modes == 0 then
		print_addon_usage(kind, addon)
		return
	end

	for _, mode in ipairs(aopts.modes) do
		if mode == "info" then
			print_addon_info(kind, addon)
		elseif mode == "help" then
			print_addon_help(addon)
		elseif mode == "sample" then
			if kind == "fetch" then run_fetcher_sample(addon)
			else run_module_sample(base_name, aopts, modules_dir, fetchers_dir, include_dir) end
		elseif mode == "demo" then
			if kind == "fetch" then run_fetcher_demo(addon, aopts)
			else run_module_demo(base_name, aopts, modules_dir, fetchers_dir, include_dir) end
		end
	end
end

-- `--list`: enumerates every installed fetcher and module (base + custom +
-- --include). `try(name)` is attempted for every candidate name regardless
-- of which "kind" section it's discovered under -- a name that legitimately
-- belongs to the other kind (or an --include-only name that isn't this
-- kind at all) just doesn't print, silently; a name discovered in the
-- kind's own authoritative dir (BASE_* or fetchers_dir/modules_dir) that
-- fails to load/validate DOES warn, since that's a real broken addon.
local function run_list(fetchers_dir, modules_dir, include_dir)
	local function print_section(title, base_set, dir, try)
		local names, authoritative = {}, {}
		for name in pairs(base_set) do
			if not authoritative[name] then authoritative[name] = true; names[#names + 1] = name end
		end
		for _, name in ipairs(list_dir(dir, ".lua")) do
			if not authoritative[name] then authoritative[name] = true; names[#names + 1] = name end
		end
		if include_dir then
			for _, name in ipairs(list_dir(include_dir, ".lua")) do
				if not authoritative[name] then names[#names + 1] = name end
			end
		end
		table.sort(names)

		io.write(title .. ":\n")
		local printed = {}
		for _, name in ipairs(names) do
			if not printed[name] then
				printed[name] = true
				local addon, err = try(name)
				if addon then
					io.write(string.format("  %-20s%s\n", addon.info.name, addon.info.short_descr or ""))
				elseif authoritative[name] then
					io.stderr:write("resmon: skipping '" .. name .. "': " .. tostring(err or "invalid shape") .. "\n")
				end
			end
		end
		io.write("\n")
	end

	print_section("Fetchers", BASE_FETCHERS, fetchers_dir, function(name)
		return try_fetch(name, fetchers_dir, include_dir)
	end)
	print_section("Modules", BASE_MODULES, modules_dir, function(name)
		return try_mod(name, modules_dir, include_dir)
	end)

	io.write("Use:\n")
	io.write("    resmon [<addon_type>.]<addon_name> [options]\n\n")
	io.write("to get further informations on the installed addons.\n")
end
-- >}

-- bootstrap >{

local function cleanup()
	leave_raw_mode()
	io.write(RESET .. SHOW_CURSOR .. LEAVE_ALT_SCREEN)
	io.flush()
end

local function main()
	local path_opts, rest = extract_path_opts(arg or {})

	-- `--list` is checked before the addon-name dispatch below (same
	-- priority tier as -h/-v, but needs fetchers_dir/modules_dir/include_dir
	-- first, which -h/-v don't) -- not a PATH_FLAGS entry since it takes no
	-- value
	for _, tok in ipairs(rest) do
		if tok == "--list" then
			local _, fetchers_dir, modules_dir, include_dir = resolve_paths(path_opts)
			run_list(fetchers_dir, modules_dir, include_dir)
			os.exit(0)
		end
	end

	-- `resmon <addon_name> [options]`: the first remaining non-flag token
	-- (path flags already stripped, wherever they appeared) switches the
	-- whole invocation to the standalone addon CLI instead of the normal
	-- config-driven app -- backward compatible, since every existing
	-- invocation either passes no args or starts with a flag
	local addon_idx = nil
	for i, tok in ipairs(rest) do
		if tok:sub(1, 1) ~= "-" then addon_idx = i; break end
	end
	if addon_idx then
		local addon_name = rest[addon_idx]
		local addon_rest = {}
		for i, tok in ipairs(rest) do
			if i ~= addon_idx then addon_rest[#addon_rest + 1] = tok end
		end
		run_addon_cli(addon_name, addon_rest, path_opts)
		return
	end

	parse_args(rest)
	local config_file, fetchers_dir, modules_dir, include_dir = resolve_paths(path_opts)

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
			local fetcher, err = resolve_fetcher(fe, fetchers_dir, include_dir)
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
			local mod, err = resolve_module(e, modules_dir, fetch_cache, include_dir)
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
