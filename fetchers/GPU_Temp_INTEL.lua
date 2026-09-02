-- Custom fetcher (INTEL): integrated GPU temperature.
--
-- UNTESTED, and likely UNAVAILABLE on most systems -- released without any
-- guarantee it works correctly. Unlike AMD (where amdgpu always exposes its
-- own hwmon temp1_input), an Intel integrated GPU typically shares the CPU
-- package's thermal sensor rather than exposing a separate one; only
-- newer kernels (i915 hwmon support landed around 6.2) register a
-- dedicated "i915" hwmon node at all, and even then not necessarily with a
-- temperature reading (it may only expose power/energy). Meant as a
-- drop-in Intel-architecture replacement for GPU_Temp_AMD: same return
-- shape, so any module depending on it works unchanged -- just replace
-- "GPU_Temp_AMD" with "GPU_Temp_INTEL" in that module's fetcher={...}. If
-- this fetcher never succeeds on your system, there simply may be no
-- separate iGPU sensor to read; a module like mod_temp_graph will just
-- keep showing stale/no data for that line, which it already handles
-- gracefully (see the shared fetcher-error contract in core.lua).

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

local TEMP_PATH = find_hwmon_temp_path("i915")

local function fetch() -- >{
	if not TEMP_PATH then return {}, 1, "i915 hwmon temp path not found (likely unavailable on integrated Intel GPUs)" end
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
		name = "GPU_Temp_INTEL",
		data_type = "GPU temperature (Celsius)",
		long_name = "GPU Temperature (Intel)",
		author = "resmon",
		release = "v0.4.0",
		date = "2026-09-02",
		short_descr = "Integrated GPU temperature, if the kernel exposes one.",
		description = [[UNTESTED, and likely unavailable on most systems: an
Intel iGPU typically shares the CPU package's thermal sensor rather than
exposing its own. Reads the i915 hwmon node's temp1_input where present
(kernel 6.2+).]],
		hardware = "Intel iGPU",
		dependencies = {
			{ target = "/sys/class/hwmon", descr = "Scanned for a hwmon node named 'i915' (kernel 6.2+ only)" },
		},
	},
} -- >}

-- vim: filetype=lua foldmethod=marker foldmarker=>{,>}
