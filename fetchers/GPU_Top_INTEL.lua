-- Custom fetcher (INTEL): shared `intel_gpu_top -J` stream, feeding both GPU
-- display modules (mod_gpu, mod_gpu_graph) the same way GPU_Top_AMD does.
--
-- UNTESTED, the most speculative of the four INTEL fetchers -- released
-- without any guarantee it works correctly. Written from documented
-- intel_gpu_top JSON field names, never verified against a real run on
-- Intel hardware; exact key names/nesting are known to have shifted across
-- igt-gpu-tools versions. Meant as a drop-in Intel-architecture replacement
-- for GPU_Top_AMD in fetcher={...}: same return shape (raw/totals/grbm/
-- grbm2), so mod_gpu.lua/mod_gpu_graph.lua work completely unchanged.
--
-- Intel's engine model has no AMD-style GRBM/GRBM2 performance-counter
-- blocks, so `grbm`/`grbm2` are always absent here -- the GRBM/GRBM2-
-- derived rows in mod_gpu_graph (Depth Block, Shader Export, etc.) will
-- simply show no data, which that module already handles gracefully.
-- `totals` is synthesized (not lifted verbatim from the JSON, unlike
-- GPU_Top_AMD) as a small JSON string carrying the same "GFX"/"Media" keys
-- mod_gpu.lua/mod_gpu_graph.lua already know how to read, mapped from
-- Intel's own engine categories: GFX <- "Render/3D" busy%, Media <-
-- "Video" + "VideoEnhance" busy% combined. Intel has no general-purpose
-- Compute engine exposed the same way as AMD's, so that key is left out
-- (reads as 0). VRAM/GTT bars in mod_gpu.lua will also read 0:
-- intel_gpu_top's JSON has no equivalent "Total VRAM/GTT Usage" fields.

local entry = ...
-- entry.refresh sizes intel_gpu_top's own -s <ms> sampling interval, same
-- rationale as GPU_Top_AMD
local REFRESH_MS = math.max(math.floor(((entry and entry.refresh) or 0.5) * 1000), 100)

local gpu_pipe = nil
local pipe_failed = false

local function get_pipe() -- >{
	if gpu_pipe or pipe_failed then return gpu_pipe end
	gpu_pipe = io.popen("intel_gpu_top -J -s " .. REFRESH_MS .. " 2>/dev/null")
	if not gpu_pipe then pipe_failed = true end
	return gpu_pipe
end -- >}

local function read_snapshot() -- >{
	local pipe = get_pipe()
	if not pipe then return nil end
	local line = pipe:read("*l")
	if not line or line == "" then
		pipe:close()
		gpu_pipe = nil -- allow a respawn attempt on the next tick
		return nil
	end
	return line
end -- >}

-- pulls a bare numeric "busy" percentage for an engine name that may or may
-- not carry a "/<index>" suffix (e.g. "Render/3D" vs "Render/3D/0")
local function engine_busy(json, engine_name) -- >{
	local escaped = engine_name:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")
	local pattern = '"' .. escaped .. '[^"]*"%s*:%s*{[^}]-"busy"%s*:%s*([%-%d%.eE]+)'
	return tonumber(json:match(pattern))
end -- >}

local function fetch() -- >{
	local snap = read_snapshot()
	if not snap then return {}, 1, "intel_gpu_top: no data" end

	local gfx = engine_busy(snap, "Render/3D") or 0
	local media = (engine_busy(snap, "Video") or 0) + (engine_busy(snap, "VideoEnhance") or 0)
	local totals = string.format(
		'{"GFX":{"unit":"%%","value":%.2f},"Media":{"unit":"%%","value":%.2f}}',
		gfx, media
	)

	return { raw = snap, totals = totals }, 0
end -- >}

return { -- >{
	fetch = fetch,
	default_delay = REFRESH_MS / 1000,
} -- >}

-- vim: filetype=lua foldmethod=marker foldmarker=>{,>}
