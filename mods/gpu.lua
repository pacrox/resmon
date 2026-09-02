-- Custom module: GPU resource usage bars.
-- Data source: fetcher "GPU_Top_AMD" (fetchers/GPU_Top_AMD.lua, shared with
-- mod_gpu_graph -- one `amdgpu_top -J` process instead of two).
--
-- NOTE: the raw GRBM/GRBM2 performance-counter percentages (Graphics Pipe,
-- Shader Export, ...) read back as 0 on systems where the kernel's
-- perf_event_paranoid sysctl blocks unprivileged perf-counter access -- this
-- is a system permission restriction, not something resmon can work around.
-- "Total fdinfo" (per-process GPU engine usage, summed across all processes)
-- is populated regardless, since it comes from DRM/GEM fdinfo accounting,
-- not perf counters -- it is used here instead, and doubles as the
-- process-level GFX/LLM engine breakdown.

local _, cache = ...

local opts = {} -- no configurable options today; empty table still required

local function extract_field(json, key) -- >{
	local escaped_key = key:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")
	local pattern = '"' .. escaped_key .. '"%s*:%s*{%s*"unit"%s*:%s*"[^"]*"%s*,%s*"value"%s*:%s*([%-%d%.eE]+)'
	return tonumber(json:match(pattern))
end -- >}

local function usage_percent(json, used_key, total_key) -- >{
	local used = extract_field(json, used_key)
	local total = extract_field(json, total_key)
	if not used or not total or total == 0 then return nil end
	return used / total * 100
end -- >}

local bars_color = { -- >{
	{ r = 134, g = 190, b = 67 },  -- green, #86be43
	{ r = 230, g = 200, b = 60 },  -- yellow
	{ r = 230, g = 140, b = 40 },  -- orange
	{ r = 220, g = 70, b = 70 },   -- red
} -- >}

-- GFX/LLM/VID are single fixed colors (not value-banded, unlike VRAM/GTT
-- below): passing a plain {r,g,b} table instead of a color array makes
-- BandColor() return it unchanged regardless of value.
local COLOR_GFX = { r = 230, g = 140, b = 40 } -- orange
local COLOR_LLM = { r = 70, g = 150, b = 255 } -- blue
local COLOR_VID = { r = 60, g = 200, b = 200 } -- cyan

-- "totals" is the fetcher's pre-scoped "Total fdinfo" object (summed GPU
-- engine usage across all processes); "raw" is the full snapshot, needed for
-- VRAM/GTT which live outside "Total fdinfo".
local resource_list = { -- >{
	{ label = "GFX", color = COLOR_GFX, fetch = function(raw, totals)
		return totals and extract_field(totals, "GFX")
	end },
	{ label = "LLM", color = COLOR_LLM, fetch = function(raw, totals)
		return totals and extract_field(totals, "Compute")
	end },
	{ label = "VID", color = COLOR_VID, fetch = function(raw, totals)
		return totals and extract_field(totals, "Media")
	end },
	{ label = "VRAM", color = bars_color, fetch = function(raw)
		return usage_percent(raw, "Total VRAM Usage", "Total VRAM")
	end },
	{ label = "GTT", color = bars_color, fetch = function(raw)
		return usage_percent(raw, "Total GTT Usage", "Total GTT")
	end },
} -- >}

local LABEL_W = 6 -- blank + up to 4 chars of label + blank, before the Y axis

local function pad(s, w) -- >{
	s = tostring(s)
	if #s > w then return s:sub(1, w) end
	return s .. string.rep(" ", w - #s)
end -- >}

local function redraw(pane) -- >{
	local data = cache[1] or {}
	local raw, totals = data.raw, data.totals
	if not raw then
		WriteAt(pane.x, pane.y, "amdgpu_top: no data")
		return
	end

	local axis_x = pane.x + LABEL_W
	local bar_x = axis_x + 1
	local bar_w = math.max(pane.w - LABEL_W - 1, 0)

	local has_axis = pane.h > #resource_list + 1
	local content_h = has_axis and math.max(pane.h - 2, #resource_list) or pane.h
	local base_block_h = math.max(1, math.floor(content_h / #resource_list))

	local bars_h = 0
	for i = 1, #resource_list do
		local res = resource_list[i]
		local value = res.fetch(raw, totals) or 0
		local block_h = (i == #resource_list) and (content_h - bars_h) or base_block_h
		local y = pane.y + bars_h
		WriteAt(pane.x, y + math.floor(block_h / 2), " " .. pad(res.label:upper(), 4))
		local bar_pane = { x = bar_x, y = y, w = bar_w, h = block_h }
		Bar(bar_pane, value, 0, 100, "horizontal", res.color)
		bars_h = bars_h + block_h
	end

	if has_axis then
		local xticks = Pow2Ticks(0, 100, math.max(1, math.floor(bar_w / 8)))
		Axis(
			{ x = axis_x, y = pane.y, w = bar_w, h = bars_h },
			{ min = 0, max = 100 },
			{ min = 0, max = 1 },
			{ x = xticks, y = {} }
		)
	end
end -- >}

return { -- >{
	title = "GPU Monitor",
	min_w = 30,
	min_h = 6,
	redraw = redraw,
	opts = opts,
	info = {
		type = "module",
		name = "gpu",
		long_name = "GPU Monitor",
		author = "resmon",
		release = "v0.4.0",
		date = "2026-09-02",
		short_descr = "GPU engine and memory usage as horizontal bars.",
		description = [[Draws GFX/LLM/VID engine usage and VRAM/GTT memory
usage as horizontal bars.]],
		dependencies = { "GPU engine/memory usage (amdgpu_top JSON)" },
	},
	-- fake snapshot: the real data is opaque regex-parsed JSON text, not a
	-- flat set of noised leaves, so the numeric fields are noised via
	-- fake_fetcher's template/args leaf (each %d/%.1f substituted from an
	-- independently-seeded noise generator) and spliced into the same JSON
	-- shape redraw() already knows how to parse, so it drifts like real data
	sample = {
		{
			raw = {
				template = '{"Total VRAM Usage":{"unit":"MiB","value":%d},"Total VRAM":{"unit":"MiB","value":8192},"Total GTT Usage":{"unit":"MiB","value":%d},"Total GTT":{"unit":"MiB","value":8192}}',
				args = { { 0, 8192 }, { 0, 8192 } },
			},
			totals = {
				template = '{"GFX":{"unit":"%%","value":%.1f},"Compute":{"unit":"%%","value":%.1f},"Media":{"unit":"%%","value":%.1f}}',
				args = { { 0, 100 }, { 0, 100 }, { 0, 100 } },
			},
		},
	},
} -- >}

-- vim: filetype=lua foldmethod=marker foldmarker=>{,>}
