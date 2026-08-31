-- Custom fetcher: per-core CPU usage percentage, from /proc/stat

local prev_times = nil

local function clamp01(v) -- >{
	if v < 0 then return 0 end
	if v > 100 then return 100 end
	return v
end -- >}

local function read_cpu_times() -- >{
	local raw = ReadProcFile("/proc/stat")
	local times = {}
	if not raw then return times end
	for line in raw:gmatch("[^\n]+") do
		local id, rest = line:match("^cpu(%d+)%s+(.*)$")
		if id then
			local total, idle, field = 0, 0, 0
			for n in rest:gmatch("%d+") do
				field = field + 1
				local v = tonumber(n)
				total = total + v
				if field == 4 or field == 5 then idle = idle + v end
			end
			times[tonumber(id)] = { total = total, idle = idle }
		end
	end
	return times
end -- >}

local function fetch() -- >{
	local cur = read_cpu_times()
	if next(cur) == nil then return {}, 1, "failed to read /proc/stat" end
	local pct = {}
	for id, t in pairs(cur) do
		local p = prev_times and prev_times[id]
		if p then
			local dtotal = t.total - p.total
			local didle = t.idle - p.idle
			pct[id] = (dtotal > 0) and clamp01((dtotal - didle) / dtotal * 100) or 0
		else
			pct[id] = 0
		end
	end
	prev_times = cur
	return { cores = pct }, 0
end -- >}

return { -- >{
	fetch = fetch,
	default_delay = 0.33,
} -- >}

-- vim: filetype=lua foldmethod=marker foldmarker=>{,>}
