-- Custom fetcher (INTEL): CPU temperature, from hwmon sysfs (coretemp).
--
-- UNTESTED -- released without any guarantee it works correctly; no Intel
-- hardware was available to verify it against. `coretemp` is the standard
-- Linux hwmon driver name for Intel CPU package/core temperature sensors
-- (the direct Intel counterpart to AMD's `k10temp`). Meant as a drop-in
-- Intel-architecture replacement for CPU_Temp_AMD: same return shape, so
-- any module depending on it works unchanged -- just replace
-- "CPU_Temp_AMD" with "CPU_Temp_INTEL" in that module's fetcher={...}.
--
-- coretemp exposes one temp*_input per core plus a package-wide one;
-- temp1_input is typically "Package id 0" (matching k10temp's Tctl being a
-- single package-wide reading), but this has not been confirmed to hold on
-- every Intel platform/kernel combination.

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

local TEMP_PATH = find_hwmon_temp_path("coretemp")

local function fetch() -- >{
	if not TEMP_PATH then return {}, 1, "coretemp hwmon path not found" end
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
