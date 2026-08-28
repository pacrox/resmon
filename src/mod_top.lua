-- Base module: top processes (PID, USER, %CPU, %MEM, TIME+, COMMAND)

local refresh_rate = 1.5

local procs_color = { -- >{
	{ r = 60, g = 60, b = 60 },
	{ r = 150, g = 110, b = 40 },
	{ r = 180, g = 50, b = 50 },
} -- >}

local procs_text_color = { r = 220, g = 220, b = 220 }

local BOLD = "\27[1m"
local BOLD_OFF = "\27[22m"

local COL_PID, COL_USER, COL_CPU, COL_MEM, COL_TIME = 8, 11, 7, 7, 10

-- assumed clock ticks per second (sysconf(_SC_CLK_TCK)); standard on Linux x86_64
local CLK_TCK = 100

local prev_samples = {}
local uid_cache = nil

local function pad(s, w) -- >{
	s = tostring(s)
	if #s > w then return s:sub(1, w) end
	return s .. string.rep(" ", w - #s)
end -- >}

local function username_for_uid(uid) -- >{
	if not uid_cache then
		uid_cache = {}
		local f = io.open("/etc/passwd", "r")
		if f then
			for line in f:lines() do
				local name, u = line:match("^([^:]*):[^:]*:([^:]*):")
				if name and tonumber(u) then
					uid_cache[tonumber(u)] = name
				end
			end
			f:close()
		end
	end
	return uid_cache[uid] or tostring(uid)
end -- >}

local function split_ws(s) -- >{
	local t = {}
	for w in s:gmatch("%S+") do t[#t + 1] = w end
	return t
end -- >}

local function read_process(pid, mem_total_kb, now) -- >{
	local stat = ReadProcFile("/proc/" .. pid .. "/stat")
	if not stat then return nil end
	local comm, rest = stat:match("^%d+%s+%((.*)%)%s(.*)$")
	if not rest then return nil end
	local fields = split_ws(rest)
	local utime = tonumber(fields[12])
	local stime = tonumber(fields[13])
	if not utime or not stime then return nil end
	local total_ticks = utime + stime

	local status = ReadProcFile("/proc/" .. pid .. "/status")
	local vmrss = status and tonumber(status:match("VmRSS:%s*(%d+)")) or 0
	local uid = status and tonumber(status:match("Uid:%s*(%d+)")) or 0

	local cpu_pct = 0
	local prev = prev_samples[pid]
	prev_samples[pid] = { total = total_ticks, time = now }
	if prev then
		local dt = now - prev.time
		local dticks = total_ticks - prev.total
		if dt > 0 and dticks >= 0 then
			cpu_pct = (dticks / CLK_TCK) / dt * 100
		end
	end

	local mem_pct = (mem_total_kb > 0) and (vmrss / mem_total_kb * 100) or 0
	local total_seconds = math.floor(total_ticks / CLK_TCK)
	local time_str = string.format("%d:%02d", math.floor(total_seconds / 60), total_seconds % 60)

	return {
		pid = pid,
		user = username_for_uid(uid),
		cpu_pct = cpu_pct,
		mem_pct = mem_pct,
		time_str = time_str,
		command = comm,
	}
end -- >}

local function redraw(pane) -- >{
	local now = MonotonicNow()
	local meminfo = ReadProcFile("/proc/meminfo")
	local mem_total_kb = meminfo and tonumber(meminfo:match("MemTotal:%s*(%d+)")) or 0

	local procs = {}
	for _, pid in ipairs(ListProcPids()) do
		local p = read_process(pid, mem_total_kb, now)
		if p then procs[#procs + 1] = p end
	end
	table.sort(procs, function(a, b) return a.cpu_pct > b.cpu_pct end)

	local cmd_w = math.max(pane.w - (COL_PID + COL_USER + COL_CPU + COL_MEM + COL_TIME), 0)

	local header = pad("PID", COL_PID) .. pad("USER", COL_USER)
		.. BOLD .. pad("%CPU", COL_CPU) .. pad("%MEM", COL_MEM) .. BOLD_OFF
		.. pad("TIME+", COL_TIME) .. BOLD .. pad("COMMAND", cmd_w) .. BOLD_OFF
	WriteAt(pane.x, pane.y, header)

	local rows_available = pane.h - 1
	for i = 1, math.min(rows_available, #procs) do
		local p = procs[i]
		local line = pad(p.pid, COL_PID) .. pad(p.user, COL_USER)
			.. BOLD .. pad(string.format("%.1f", p.cpu_pct), COL_CPU)
			.. pad(string.format("%.1f", p.mem_pct), COL_MEM) .. BOLD_OFF
			.. pad(p.time_str, COL_TIME) .. BOLD .. pad(p.command, cmd_w) .. BOLD_OFF
		local bg = BandColor(p.cpu_pct, 0, 100, procs_color)
		WriteAt(pane.x, pane.y + i, line, procs_text_color, bg)
	end
end -- >}

return { -- >{
	title = "TOP Processes",
	min_w = 40,
	min_h = 4,
	default_delay = refresh_rate,
	redraw = redraw,
} -- >}

-- vim: filetype=lua foldmethod=marker foldmarker=>{,>}
