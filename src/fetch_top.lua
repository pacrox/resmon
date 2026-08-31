-- Base fetcher: process list (PID/USER/%CPU/%MEM/TIME+/COMMAND), from /proc

-- assumed clock ticks per second (sysconf(_SC_CLK_TCK)); standard on Linux x86_64
local CLK_TCK = 100

local prev_samples = {}
local uid_cache = nil

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

local function fetch() -- >{
	local now = MonotonicNow()
	local meminfo = ReadProcFile("/proc/meminfo")
	local mem_total_kb = meminfo and tonumber(meminfo:match("MemTotal:%s*(%d+)")) or 0

	local procs = {}
	for _, pid in ipairs(ListProcPids()) do
		local p = read_process(pid, mem_total_kb, now)
		if p then procs[#procs + 1] = p end
	end

	return { procs = procs, mem_total_kb = mem_total_kb }, 0
end -- >}

return { -- >{
	fetch = fetch,
	default_delay = 1.5,
} -- >}

-- vim: filetype=lua foldmethod=marker foldmarker=>{,>}
