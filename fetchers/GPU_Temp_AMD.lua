-- Custom fetcher: GPU temperature, from hwmon sysfs (amdgpu)

local opts = { -- >{
	refresh = { 0.5, "Fetch refresh rate in seconds" },
} -- >}

-- hwmon device index isn't stable across systems, only the driver name is;
-- resolved once at fetcher load by scanning hwmon0..hwmon31 for a name match.
local function find_hwmon_temp_path(driver_name) -- >{
	for i = 0, 31 do
		local base = "/sys/class/hwmon/hwmon" .. i
		local name = ReadProcFile(base .. "/name")
		if name and name:match("^" .. driver_name .. "%s*$") then
			return base .. "/temp1_input"
		end
	end
	return nil
end -- >}

local TEMP_PATH = find_hwmon_temp_path("amdgpu")

local function fetch() -- >{
	if not TEMP_PATH then return {}, 1, "amdgpu hwmon path not found" end
	local raw = ReadProcFile(TEMP_PATH)
	local milli = raw and tonumber(raw:match("%-?%d+"))
	if not milli then return {}, 1, "failed to read " .. TEMP_PATH end
	return { temp_c = milli / 1000 }, 0
end -- >}

return { -- >{
	fetch = fetch,
	default_delay = opts.refresh[1],
	opts = opts,
	ranges = { temp_c = { 20, 100 } },
	info = {
		type = "fetcher",
		name = "GPU_Temp_AMD",
		data_type = "GPU temperature (Celsius)",
		long_name = "GPU Temperature (AMD)",
		author = "resmon",
		release = "v0.4.0",
		date = "2026-09-02",
		short_descr = "GPU temperature, from the amdgpu hwmon driver.",
		description = [[Reads the amdgpu hwmon node's temp1_input.]],
		hardware = "AMD GPU",
		dependencies = {
			{ target = "/sys/class/hwmon", descr = "Scanned for a hwmon node named 'amdgpu'" },
		},
	},
} -- >}

-- vim: filetype=lua foldmethod=marker foldmarker=>{,>}
