-- Custom module: GPU parameters (3D/LLM engine usage plus every GRBM/GRBM2
-- performance-counter sub-block), scrolling history graph, same rendering
-- style as CPU Cores Graph: each visible parameter gets its own unique
-- shade -- as many shades as visible parameters, no repeats -- assigned by
-- how close that parameter's own average (over the visible window) sits to
-- the average of every parameter shown: the closest to the group average is
-- palest, the farthest is darkest, evenly spread in between. Parameters are
-- drawn darkest-first so the palest curve always ends up on top where lines
-- overlap. Same #FFD068 hue throughout instead of CPU Cores Graph's green.
--
-- Data source: fetcher "GPU_Top" (fetchers/GPU_Top.lua, shared with mod_gpu
-- -- one `amdgpu_top -J` process instead of two).

local ffi_bit = require("bit")
local sChar = require("sextant_chars")

local _, cache = ...

local time_interval = 30 -- seconds shown on the X axis window, ticked every 10s

-- monochrome value gradient endpoints, dark to #FFD068, same hue
-- throughout, only brightness varies. The gradient is rebuilt each redraw
-- with exactly one entry per currently visible parameter (see build_grid).
local GRAPH_DARK = { r = 127, g = 88, b = 0 }    -- darkest, same hue as #FFD068
local GRAPH_LIGHT = { r = 255, g = 208, b = 104 } -- #FFD068

local function lerp_color(a, b, t) -- >{
	return {
		r = math.floor(a.r + (b.r - a.r) * t + 0.5),
		g = math.floor(a.g + (b.g - a.g) * t + 0.5),
		b = math.floor(a.b + (b.b - a.b) * t + 0.5),
	}
end -- >}

local function build_gradient(dark, light, size) -- >{
	if size <= 1 then return { light } end
	local t = {}
	for i = 0, size - 1 do
		t[i + 1] = lerp_color(dark, light, i / (size - 1))
	end
	return t
end -- >}

local function extract_field(json, key) -- >{
	local escaped_key = key:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")
	local pattern = '"' .. escaped_key .. '"%s*:%s*{%s*"unit"%s*:%s*"[^"]*"%s*,%s*"value"%s*:%s*([%-%d%.eE]+)'
	return tonumber(json:match(pattern))
end -- >}

-- one tracked GPU parameter per entry; "fetch" receives the already-scoped
-- "GRBM"/"GRBM2"/"Total fdinfo" sub-objects (nil if absent from a snapshot)
-- so field names never need to be re-disambiguated against the full JSON.
-- `id` only needs to be a stable, unique key into `history`/`smoothed` --
-- shade assignment no longer depends on it (see build_grid).
local params = { -- >{
	{ id = 1, label = "Depth Block", fetch = function(json, ctx)
		return ctx.grbm and extract_field(ctx.grbm, "Depth Block")
	end },
	{ id = 2, label = "Color Block", fetch = function(json, ctx)
		return ctx.grbm and extract_field(ctx.grbm, "Color Block")
	end },
	{ id = 3, label = "Geometry Engine", fetch = function(json, ctx)
		return ctx.grbm and extract_field(ctx.grbm, "Geometry Engine")
	end },
	{ id = 4, label = "Graphics Pipe", fetch = function(json, ctx)
		return ctx.grbm and extract_field(ctx.grbm, "Graphics Pipe")
	end },
	{ id = 5, label = "Primitive Assembly", fetch = function(json, ctx)
		return ctx.grbm and extract_field(ctx.grbm, "Primitive Assembly")
	end },
	{ id = 6, label = "Shader Export", fetch = function(json, ctx)
		return ctx.grbm and extract_field(ctx.grbm, "Shader Export")
	end },
	{ id = 7, label = "Shader Processor Interpolator", fetch = function(json, ctx)
		return ctx.grbm and extract_field(ctx.grbm, "Shader Processor Interpolator")
	end },
	{ id = 8, label = "Texture Pipe", fetch = function(json, ctx)
		return ctx.grbm and extract_field(ctx.grbm, "Texture Pipe")
	end },
	{ id = 9, label = "Command Processor - Compute", fetch = function(json, ctx)
		return ctx.grbm2 and extract_field(ctx.grbm2, "Command Processor -  Compute")
	end },
	{ id = 10, label = "Command Processor - Fetcher", fetch = function(json, ctx)
		return ctx.grbm2 and extract_field(ctx.grbm2, "Command Processor -  Fetcher")
	end },
	{ id = 11, label = "Command Processor - Graphics", fetch = function(json, ctx)
		return ctx.grbm2 and extract_field(ctx.grbm2, "Command Processor - Graphics")
	end },
	{ id = 12, label = "Efficiency Arbiter", fetch = function(json, ctx)
		return ctx.grbm2 and extract_field(ctx.grbm2, "Efficiency Arbiter")
	end },
	{ id = 13, label = "Render Backend Memory Interface", fetch = function(json, ctx)
		return ctx.grbm2 and extract_field(ctx.grbm2, "Render Backend Memory Interface")
	end },
	{ id = 14, label = "RunList Controller", fetch = function(json, ctx)
		return ctx.grbm2 and extract_field(ctx.grbm2, "RunList Controller")
	end },
	{ id = 15, label = "SDMA", fetch = function(json, ctx)
		return ctx.grbm2 and extract_field(ctx.grbm2, "SDMA")
	end },
	{ id = 16, label = "Texture Cache per Pipe", fetch = function(json, ctx)
		return ctx.grbm2 and extract_field(ctx.grbm2, "Texture Cache per Pipe")
	end },
	{ id = 17, label = "Unified Translation Cache Level-2", fetch = function(json, ctx)
		return ctx.grbm2 and extract_field(ctx.grbm2, "Unified Translation Cache Level-2")
	end },
	{ id = 18, label = "LLM", fetch = function(json, ctx)
		return ctx.totals and extract_field(ctx.totals, "Compute")
	end },
	{ id = 19, label = "3D", fetch = function(json, ctx)
		return ctx.totals and extract_field(ctx.totals, "GFX")
	end },
} -- >}

-- raw values are noisy tick to tick; smoothing before plotting keeps the
-- curve reading as a smooth line instead of a jagged skyline, same as
-- CPU Cores Graph.
local SMOOTHING_ALPHA = 0.35

local MAX_HISTORY = 2000
local smoothed = {} -- smoothed[id] = last exponential-moving-average value
local history = {} -- history[id] = { {t=, v=}, ... }, sorted by t ascending

local function clamp01(v) -- >{
	if v < 0 then return 0 end
	if v > 100 then return 100 end
	return v
end -- >}

local function push_sample(id, v, t) -- >{
	local h = history[id]
	if not h then
		h = {}
		history[id] = h
	end
	h[#h + 1] = { t = t, v = v }
	if #h > MAX_HISTORY * 1.5 then
		local trimmed = {}
		for i = #h - MAX_HISTORY + 1, #h do trimmed[#trimmed + 1] = h[i] end
		history[id] = trimmed
	end
end -- >}

-- returns the value of the last sample at or before target_t, or nil if
-- target_t predates the oldest recorded sample (not enough history yet)
local function value_at_time(h, target_t) -- >{
	local n = #h
	if n == 0 or target_t < h[1].t then return nil end
	local lo, hi = 1, n
	while lo < hi do
		local mid = math.floor((lo + hi + 1) / 2)
		if h[mid].t <= target_t then lo = mid else hi = mid - 1 end
	end
	return h[lo].v
end -- >}

local function x_tick_labels() -- >{
	local labels = {}
	local seconds_ago = time_interval
	while seconds_ago > 0 do
		labels[#labels + 1] = "-" .. seconds_ago .. "s"
		seconds_ago = seconds_ago - 10
	end
	labels[#labels + 1] = "now"
	return labels
end -- >}

-- marks a single sub-cell (slot = half-cell column index, level = sub-row
-- from the bottom) in the shared grid. Parameters are drawn darkest-first
-- (see build_grid), so a later (paler) curve simply overwrites an earlier
-- (darker) one wherever they land on the same cell.
local function mark_point(grid, vres, slot, level, color) -- >{
	local global_row = vres - 1 - level
	local row = math.floor(global_row / 3)
	local p = global_row % 3
	local col = math.floor(slot / 2)
	local sub_c = slot % 2
	local bitpos = p * 2 + sub_c
	local cell = grid[row][col]
	cell.mask = ffi_bit.bor(cell.mask, ffi_bit.lshift(1, bitpos))
	cell.color = color
end -- >}

-- joins two consecutive samples (one half-cell column apart) with a
-- diagonal line rather than a solid vertical block: since the two points
-- are exactly 1 column apart, a proper line between them only ever touches
-- those 2 columns, splitting the intervening rows so the ones closer to
-- the previous sample use its column and the ones closer to the new
-- sample use the new column -- the standard steep-line Bresenham case.
local function mark_diagonal(grid, vres, prev_slot, prev_level, slot, level, color) -- >{
	local steps = math.abs(level - prev_level)
	if steps == 0 then
		mark_point(grid, vres, slot, level, color)
		return
	end
	local dir = (level > prev_level) and 1 or -1
	for i = 0, steps do
		local l = prev_level + dir * i
		local s = (i / steps < 0.5) and prev_slot or slot
		mark_point(grid, vres, s, l, color)
	end
end -- >}

local function build_grid(graph_w, graph_h, now) -- >{
	local grid = {}
	for row = 0, graph_h - 1 do
		grid[row] = {}
		for col = 0, graph_w - 1 do grid[row][col] = { mask = 0, color = nil } end
	end

	local sample_cols = graph_w * 2
	local vres = graph_h * 3

	-- one pass: collect each parameter's visible-window samples and its own
	-- average, plus a running sum/count over every parameter's samples
	-- pooled together for the group average
	local visible, param_mean = {}, {}
	local pool_sum, pool_n = 0, 0
	for _, param in ipairs(params) do
		local h = history[param.id]
		if h then
			local samples, sum, n = {}, 0, 0
			for slot = 0, sample_cols - 1 do
				local seconds_ago = time_interval * (1 - slot / sample_cols)
				local v = value_at_time(h, now - seconds_ago)
				if v ~= nil then
					samples[#samples + 1] = { slot = slot, v = v }
					sum = sum + v
					n = n + 1
				end
			end
			if n > 0 then
				visible[param.id] = samples
				param_mean[param.id] = sum / n
				pool_sum = pool_sum + sum
				pool_n = pool_n + n
			end
		end
	end
	if pool_n == 0 then return grid end
	local group_mean = pool_sum / pool_n

	-- rank parameters by distance from the group average, farthest first --
	-- this is both the palette assignment order (darkest to palest) and the
	-- draw order (darkest drawn first, palest drawn last so it stays on top)
	local ranked = {}
	for id in pairs(visible) do ranked[#ranked + 1] = id end
	table.sort(ranked, function(a, b)
		local da = math.abs(param_mean[a] - group_mean)
		local db = math.abs(param_mean[b] - group_mean)
		if da == db then return a < b end -- stable tie-break, avoids flicker
		return da > db
	end)

	local palette = build_gradient(GRAPH_DARK, GRAPH_LIGHT, #ranked)

	for rank, id in ipairs(ranked) do
		local color = palette[rank]
		local prev_slot, prev_level = nil, nil
		for _, s in ipairs(visible[id]) do
			local level_frac = clamp01(s.v / 100)
			local level = math.floor(level_frac * (vres - 1) + 0.5)
			if prev_slot ~= nil and s.slot == prev_slot + 1 then
				mark_diagonal(grid, vres, prev_slot, prev_level, s.slot, level, color)
			else
				mark_point(grid, vres, s.slot, level, color)
			end
			prev_slot, prev_level = s.slot, level
		end
	end

	return grid
end -- >}

local function redraw(pane) -- >{
	local now = MonotonicNow()
	local data = cache[1]
	if data and data.raw then
		for _, param in ipairs(params) do
			local v = param.fetch(data.raw, data)
			if v ~= nil then
				-- fdinfo/perf-counter percentages can briefly exceed 100
				-- (rounding, multi-queue overlap); clamp here so it never
				-- propagates into an out-of-range grid row in build_grid
				v = clamp01(v)
				local prev = smoothed[param.id]
				local ema = prev and (SMOOTHING_ALPHA * v + (1 - SMOOTHING_ALPHA) * prev) or v
				smoothed[param.id] = ema
				push_sample(param.id, ema, now)
			end
		end
	end

	if pane.w <= 0 or pane.h <= 0 then return end

	local AXIS_W = 6
	local axis_x = pane.x + AXIS_W
	local graph_w = math.max(pane.w - AXIS_W - 1, 0)
	local graph_h = math.max(pane.h - 2, 1)

	local yticks = Pow2Ticks(0, 100, math.max(1, math.floor(graph_h / 4)))
	Axis(
		{ x = axis_x, y = pane.y, w = graph_w, h = graph_h },
		{ min = -time_interval, max = 0 },
		{ min = 0, max = 100 },
		{ x = x_tick_labels(), y = yticks }
	)

	local grid = build_grid(graph_w, graph_h, now)
	for row = 0, graph_h - 1 do
		local run_col = 0
		local run_color = grid[row][0].color
		local run_chars = { sChar[grid[row][0].mask] }
		for col = 1, graph_w - 1 do
			local cell = grid[row][col]
			if cell.color == run_color then
				run_chars[#run_chars + 1] = sChar[cell.mask]
			else
				WriteAt(axis_x + 1 + run_col, pane.y + row, table.concat(run_chars), run_color)
				run_col = col
				run_color = cell.color
				run_chars = { sChar[cell.mask] }
			end
		end
		WriteAt(axis_x + 1 + run_col, pane.y + row, table.concat(run_chars), run_color)
	end
end -- >}

return { -- >{
	title = "GPU Graph",
	min_w = 20,
	min_h = 8,
	redraw = redraw,
} -- >}

-- vim: filetype=lua foldmethod=marker foldmarker=>{,>}
