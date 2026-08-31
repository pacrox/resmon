-- Custom fetcher: per-core CPU clock frequency, from cpufreq sysfs

-- core ids aren't guaranteed contiguous/starting at 0 in theory, but /proc/stat
-- is the same discovery source every per-core module uses, so this stays
-- consistent with them.
local function discover_cpu_ids() -- >{
	local ids = {}
	local raw = ReadProcFile("/proc/stat")
	if raw then
		for id in raw:gmatch("cpu(%d+)") do
			ids[#ids + 1] = tonumber(id)
		end
	end
	table.sort(ids)
	return ids
end -- >}

local cpu_ids = discover_cpu_ids()

local function cpu_cur_path(id) -- >{
	return "/sys/devices/system/cpu/cpu" .. id .. "/cpufreq/scaling_cur_freq"
end -- >}

local function cpu_min_path(id) -- >{
	return "/sys/devices/system/cpu/cpu" .. id .. "/cpufreq/cpuinfo_min_freq"
end -- >}

local function cpu_max_path(id) -- >{
	return "/sys/devices/system/cpu/cpu" .. id .. "/cpufreq/cpuinfo_max_freq"
end -- >}

local function read_khz_as_ghz(path) -- >{
	local raw = path and ReadProcFile(path)
	local khz = raw and tonumber(raw:match("%d+"))
	return khz and (khz / 1e6) or nil
end -- >}

-- global min/max across every core (not just one), so a heterogeneous CPU
-- (e.g. mixed performance/efficiency cores) is scaled correctly; computed
-- once at fetcher load since the hardware range never changes at runtime.
local cpu_min, cpu_max = nil, nil
for _, id in ipairs(cpu_ids) do
	local lo = read_khz_as_ghz(cpu_min_path(id))
	local hi = read_khz_as_ghz(cpu_max_path(id))
	if lo then cpu_min = cpu_min and math.min(cpu_min, lo) or lo end
	if hi then cpu_max = cpu_max and math.max(cpu_max, hi) or hi end
end
cpu_min = cpu_min or 0.6
cpu_max = cpu_max or 5

local function fetch() -- >{
	local cores = {}
	for _, id in ipairs(cpu_ids) do
		local v = read_khz_as_ghz(cpu_cur_path(id))
		if v then cores[id] = v end
	end
	if next(cores) == nil then return {}, 1, "failed to read cpufreq" end
	return { cores = cores, min = cpu_min, max = cpu_max }, 0
end -- >}

return { -- >{
	fetch = fetch,
	default_delay = 0.5,
} -- >}

-- vim: filetype=lua foldmethod=marker foldmarker=>{,>}
