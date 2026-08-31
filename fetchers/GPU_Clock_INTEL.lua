-- Custom fetcher (INTEL): integrated GPU core clock frequency, from the
-- i915 sysfs interface (/sys/class/drm/cardN/gt_*_freq_mhz).
--
-- UNTESTED -- released without any guarantee it works correctly; no Intel
-- hardware was available to verify it against. `gt_cur_freq_mhz` /
-- `gt_min_freq_mhz` / `gt_max_freq_mhz` are the documented i915 driver
-- sysfs attributes for the integrated GPU's render clock, present since
-- long-standing kernel versions -- but exact availability/naming can still
-- vary across kernel versions and Intel GPU generations. Meant as a drop-in
-- Intel-architecture replacement for GPU_Clock_AMD: same return shape, so
-- any module depending on it works unchanged -- just replace
-- "GPU_Clock_AMD" with "GPU_Clock_INTEL" in that module's fetcher={...}.

-- card index isn't stable across systems (card0 may be an unrelated GPU on
-- multi-GPU systems); resolved once at fetcher load by probing for the
-- presence of the i915-specific gt_cur_freq_mhz attribute.
local function find_i915_card() -- >{
	for i = 0, 7 do
		local base = "/sys/class/drm/card" .. i
		if ReadProcFile(base .. "/gt_cur_freq_mhz") then
			return base
		end
	end
	return nil
end -- >}

local card = find_i915_card()
local CUR_PATH = card and (card .. "/gt_cur_freq_mhz")
local MIN_PATH = card and (card .. "/gt_min_freq_mhz")
local MAX_PATH = card and (card .. "/gt_max_freq_mhz")

local function read_mhz_as_ghz(path) -- >{
	local raw = path and ReadProcFile(path)
	local mhz = raw and tonumber(raw:match("%d+"))
	return mhz and (mhz / 1000) or nil
end -- >}

-- computed once at fetcher load since the hardware range never changes at
-- runtime; fallback values are a rough Intel iGPU ballpark, not measured
local gpu_min = read_mhz_as_ghz(MIN_PATH) or 0.3
local gpu_max = read_mhz_as_ghz(MAX_PATH) or 1.6

local function fetch() -- >{
	local v = read_mhz_as_ghz(CUR_PATH)
	if not v then return {}, 1, "failed to read Intel GPU clock" end
	return { ghz = v, min = gpu_min, max = gpu_max }, 0
end -- >}

return { -- >{
	fetch = fetch,
	default_delay = 0.5,
} -- >}

-- vim: filetype=lua foldmethod=marker foldmarker=>{,>}
