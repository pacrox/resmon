-- Custom fetcher: GPU core clock frequency, from the amdgpu hwmon node

local opts = { -- >{
	refresh = { 0.5, "Fetch refresh rate in seconds" },
} -- >}

-- hwmon device index isn't stable across systems, only the driver name is;
-- resolved once at fetcher load by scanning hwmon0..hwmon31 for a name match.
local function find_hwmon_path(driver_name) -- >{
	for i = 0, 31 do
		local base = "/sys/class/hwmon/hwmon" .. i
		local name = ReadProcFile(base .. "/name")
		if name and name:match("^" .. driver_name .. "%s*$") then
			return base
		end
	end
	return nil
end -- >}

local gpu_hwmon = find_hwmon_path("amdgpu")
local GPU_CUR_PATH = gpu_hwmon and (gpu_hwmon .. "/freq1_input")
local GPU_DPM_PATH = gpu_hwmon and (gpu_hwmon .. "/device/pp_dpm_sclk")

local function read_hz_as_ghz(path) -- >{
	local raw = path and ReadProcFile(path)
	local hz = raw and tonumber(raw:match("%d+"))
	return hz and (hz / 1e9) or nil
end -- >}

-- parses "N: <freq>Mhz [*]" lines from pp_dpm_sclk, returning the lowest and
-- highest listed DPM level in GHz -- there is no cpuinfo_min/max_freq
-- equivalent for amdgpu, so the DPM table is the only source for the GPU's
-- actual supported clock range.
local function read_gpu_range() -- >{
	local raw = GPU_DPM_PATH and ReadProcFile(GPU_DPM_PATH)
	if not raw then return nil, nil end
	local min_mhz, max_mhz = nil, nil
	for mhz in raw:gmatch("(%d+)Mhz") do
		local v = tonumber(mhz)
		if not min_mhz or v < min_mhz then min_mhz = v end
		if not max_mhz or v > max_mhz then max_mhz = v end
	end
	if not min_mhz then return nil, nil end
	return min_mhz / 1000, max_mhz / 1000
end -- >}

-- computed once at fetcher load since the hardware range never changes at
-- runtime
local gpu_min, gpu_max = read_gpu_range()
gpu_min = gpu_min or 0.6
gpu_max = gpu_max or 3

local function fetch() -- >{
	local v = read_hz_as_ghz(GPU_CUR_PATH)
	if not v then return {}, 1, "failed to read GPU clock" end
	return { ghz = v, min = gpu_min, max = gpu_max }, 0
end -- >}

return { -- >{
	fetch = fetch,
	default_delay = opts.refresh[1],
	opts = opts,
	info = {
		type = "fetcher",
		name = "GPU_Clock_AMD",
		data_type = "GPU clock frequency (GHz)",
		long_name = "GPU Clock Frequency (AMD)",
		author = "resmon",
		release = "v0.4.0",
		date = "2026-09-02",
		short_descr = "GPU core clock frequency, in GHz.",
		description = [[Reads the amdgpu hwmon node's freq1_input, plus the
supported clock range from pp_dpm_sclk, computed once at load time.]],
		hardware = "AMD GPU",
		dependencies = {
			{ target = "/sys/class/hwmon", descr = "Scanned for a hwmon node named 'amdgpu'" },
		},
	},
} -- >}

-- vim: filetype=lua foldmethod=marker foldmarker=>{,>}
