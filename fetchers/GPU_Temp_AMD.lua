-- Custom fetcher: GPU temperature, from hwmon sysfs (amdgpu)

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
	default_delay = 0.5,
} -- >}

-- vim: filetype=lua foldmethod=marker foldmarker=>{,>}
