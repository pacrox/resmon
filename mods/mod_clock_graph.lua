-- Custom module: per-core CPU clock frequency history plus GPU core clock,
-- scrolling right-to-left, same rendering style as CPU Cores Graph: each
-- visible core gets its own unique shade -- as many blue shades as visible
-- cores, no repeats -- assigned by how close that core's own average (over
-- the visible window) sits to the average of every CPU core shown: the
-- closest to the group average is palest, the farthest is darkest, evenly
-- spread in between. Cores are drawn darkest-first so the palest CPU curve
-- ends up on top of the other CPU lines. The GPU line (fixed pale magenta)
-- is always drawn last of all, on top of every CPU line regardless of
-- value. Vertical position (level) uses the shared axis, spanning the lower
-- of all cores'/the GPU's minimum frequency to the higher of their maximum,
-- both read from the fetchers' data -- only color is per-core-relative.
--
-- Data source: fetcher "CPU_Clock" (fetchers/CPU_Clock.lua), plus fetcher
-- "GPU_Clock_AMD" (fetchers/GPU_Clock_AMD.lua) if listed as a second dependency in
-- this module's own config entry -- its presence in `fetcher={...}` is what
-- turns the GPU line on, no separate option needed.

local ffi_bit = require("bit")
local sChar = require("sextant_chars")

local entry, cache = ...

local GPU_ID = "gpu" -- sentinel key, distinct from any numeric core id
local GPU_COLOR = { r = 255, g = 150, b = 255 } -- pale magenta, fixed

local time_interval = (entry and entry.interval) or 30 -- seconds shown on the X axis window (config "interval", default 30), ticked every 10s

-- monochrome value gradient endpoints, dark navy to pale sky blue, same hue
-- throughout, only brightness varies. The gradient is rebuilt each redraw
-- with exactly one entry per currently visible core (see build_grid).
local GRAPH_DARK = { r = 20, g = 50, b = 110 }   -- darkest, navy
local GRAPH_LIGHT = { r = 180, g = 215, b = 255 } -- palest, sky blue

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

-- raw sysfs readings are noisy tick to tick; smoothing before plotting
-- keeps the curve reading as a smooth line, same as the other graphs.
local SMOOTHING_ALPHA = 0.35

local MAX_HISTORY = 2000
local smoothed = {} -- smoothed[id] = last exponential-moving-average value
local history = {} -- history[id] = { {t=, v=}, ... }, sorted by t ascending

local function clamp(v, lo, hi) -- >{
	if v < lo then return lo end
	if v > hi then return hi end
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

-- same tick-spacing rule as core.lua's Pow2Ticks (largest power-of-two
-- division count that fits the budget), but formatted to one decimal place
-- since GHz values need sub-integer precision to be readable (unlike the
-- percentage/Celsius scales every other module's axis uses).
local function ghz_ticks(min, max, budget) -- >{
	local divisions = 1
	while divisions * 2 <= budget do divisions = divisions * 2 end
	divisions = math.max(divisions, 2)
	local ticks = {}
	for i = 0, divisions do
		local v = min + (max - min) * i / divisions
		ticks[#ticks + 1] = string.format("%.1f", v)
	end
	return ticks
end -- >}

-- marks a single sub-cell (slot = half-cell column index, level = sub-row
-- from the bottom) in the shared grid. CPU cores are drawn darkest-first
-- and the GPU line (if any) absolute last, so a later curve simply
-- overwrites an earlier one wherever they land on the same cell.
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

-- plots one line (a CPU core or the GPU) with a single fixed `color` for
-- all of its points, following the shared axis scale for vertical position
local function plot(grid, vres, sample_cols, now, scale_min, scale_max, id, color) -- >{
	local h = history[id]
	if not h then return end
	local prev_slot, prev_level = nil, nil
	for slot = 0, sample_cols - 1 do
		local seconds_ago = time_interval * (1 - slot / sample_cols)
		local v = value_at_time(h, now - seconds_ago)
		if v ~= nil then
			local level_frac = clamp((v - scale_min) / (scale_max - scale_min), 0, 1)
			local level = math.floor(level_frac * (vres - 1) + 0.5)
			if prev_slot ~= nil then
				mark_diagonal(grid, vres, prev_slot, prev_level, slot, level, color)
			else
				mark_point(grid, vres, slot, level, color)
			end
			prev_slot, prev_level = slot, level
		else
			prev_slot, prev_level = nil, nil
		end
	end
end -- >}

local function build_grid(graph_w, graph_h, now, scale_min, scale_max, cpu_ids, show_gpu) -- >{
	local grid = {}
	for row = 0, graph_h - 1 do
		grid[row] = {}
		for col = 0, graph_w - 1 do grid[row][col] = { mask = 0, color = nil } end
	end

	local sample_cols = graph_w * 2
	local vres = graph_h * 3

	-- one pass: each core's average over its own visible window, plus a
	-- running sum/count over every core's samples pooled together for the
	-- CPU group average (the GPU line never joins this pool -- it's always
	-- drawn last in a fixed color, see below)
	local core_mean = {}
	local pool_sum, pool_n = 0, 0
	for _, id in ipairs(cpu_ids) do
		local h = history[id]
		if h then
			local sum, n = 0, 0
			for slot = 0, sample_cols - 1 do
				local seconds_ago = time_interval * (1 - slot / sample_cols)
				local v = value_at_time(h, now - seconds_ago)
				if v ~= nil then
					sum = sum + v
					n = n + 1
				end
			end
			if n > 0 then
				core_mean[id] = sum / n
				pool_sum = pool_sum + sum
				pool_n = pool_n + n
			end
		end
	end

	if pool_n > 0 then
		local group_mean = pool_sum / pool_n

		-- rank cores by distance from the group average, farthest first --
		-- this is both the palette assignment order (darkest to palest) and
		-- the draw order (darkest drawn first, palest drawn last)
		local ranked = {}
		for id in pairs(core_mean) do ranked[#ranked + 1] = id end
		table.sort(ranked, function(a, b)
			local da = math.abs(core_mean[a] - group_mean)
			local db = math.abs(core_mean[b] - group_mean)
			if da == db then return a < b end -- stable tie-break, avoids flicker
			return da > db
		end)

		local palette = build_gradient(GRAPH_DARK, GRAPH_LIGHT, #ranked)
		for rank, id in ipairs(ranked) do
			plot(grid, vres, sample_cols, now, scale_min, scale_max, id, palette[rank])
		end
	end

	if show_gpu then
		plot(grid, vres, sample_cols, now, scale_min, scale_max, GPU_ID, GPU_COLOR) -- drawn last, always on top
	end

	return grid
end -- >}

local function redraw(pane) -- >{
	local now = MonotonicNow()
	local cpu_data = cache[1] or {}
	local gpu_data = cache[2]

	local scale_min = cpu_data.min or 0.6
	local scale_max = cpu_data.max or 5
	if gpu_data then
		scale_min = math.min(scale_min, gpu_data.min or 0.6)
		scale_max = math.max(scale_max, gpu_data.max or 3)
	end

	local cpu_ids = {}
	for id, v in pairs(cpu_data.cores or {}) do
		cpu_ids[#cpu_ids + 1] = id
		v = clamp(v, scale_min, scale_max)
		local prev = smoothed[id]
		local ema = prev and (SMOOTHING_ALPHA * v + (1 - SMOOTHING_ALPHA) * prev) or v
		smoothed[id] = ema
		push_sample(id, ema, now)
	end

	if gpu_data and gpu_data.ghz ~= nil then
		local v = clamp(gpu_data.ghz, scale_min, scale_max)
		local prev = smoothed[GPU_ID]
		local ema = prev and (SMOOTHING_ALPHA * v + (1 - SMOOTHING_ALPHA) * prev) or v
		smoothed[GPU_ID] = ema
		push_sample(GPU_ID, ema, now)
	end

	if pane.w <= 0 or pane.h <= 0 then return end

	local AXIS_W = 6
	local axis_x = pane.x + AXIS_W
	local graph_w = math.max(pane.w - AXIS_W - 1, 0)
	local graph_h = math.max(pane.h - 2, 1)

	local yticks = ghz_ticks(scale_min, scale_max, math.max(1, math.floor(graph_h / 4)))
	Axis(
		{ x = axis_x, y = pane.y, w = graph_w, h = graph_h },
		{ min = -time_interval, max = 0 },
		{ min = scale_min, max = scale_max },
		{ x = x_tick_labels(), y = yticks }
	)

	local grid = build_grid(graph_w, graph_h, now, scale_min, scale_max, cpu_ids, gpu_data ~= nil)
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
	title = "CLOCK Frequency Graph",
	min_w = 20,
	min_h = 8,
	redraw = redraw,
} -- >}

-- vim: filetype=lua foldmethod=marker foldmarker=>{,>}
