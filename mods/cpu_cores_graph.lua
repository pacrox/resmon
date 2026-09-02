-- Custom module: per-core CPU usage history, all cores overlaid in one
-- shared 0-100 plot (not stacked), scrolling right-to-left. Each core gets
-- its own unique shade -- as many shades as visible cores, no repeats --
-- assigned by how close that core's own average (over the visible window)
-- sits to the average of every core shown: the closest to the group average
-- is palest, the farthest is darkest, evenly spread in between. Cores are
-- drawn darkest-first so the palest curve always ends up on top where lines
-- overlap.

local ffi_bit = require("bit")
local sChar = require("sextant_chars")

-- Data source: fetcher "CPU_Cores" (fetchers/fetch_cpu_cores.lua)

local entry, cache = ...

local opts = { -- >{
	interval = { 30, "Seconds shown on the X axis window" },
} -- >}

local time_interval = (entry and entry.interval) or opts.interval[1]

-- monochrome value gradient endpoints, dark green to pale green, same hue
-- throughout, only brightness varies. The gradient is rebuilt each redraw
-- with exactly one entry per currently visible core (see build_grid).
local GRAPH_DARK = { r = 39, g = 80, b = 44 }   -- darkest, 10% lighter than pure dark
local GRAPH_LIGHT = { r = 189, g = 230, b = 198 } -- palest, 10% darker than pure light

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

-- raw per-core %CPU is noisy sample to sample; smoothing it before plotting
-- keeps consecutive points closer together, so the diagonal joins between
-- them stay short and the curve reads as a smooth line instead of a jagged
-- skyline of steep steps. Lower alpha = smoother but slower to react.
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
-- from the bottom) in the shared grid. Cores are drawn darkest-first (see
-- build_grid), so a later (paler) curve simply overwrites an earlier
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

local function build_grid(ids, graph_w, graph_h, now) -- >{
	local grid = {}
	for row = 0, graph_h - 1 do
		grid[row] = {}
		for col = 0, graph_w - 1 do grid[row][col] = { mask = 0, color = nil } end
	end

	local sample_cols = graph_w * 2
	local vres = graph_h * 3

	-- one pass: collect each core's visible-window samples and its own
	-- average, plus a running sum/count over every core's samples pooled
	-- together for the group average
	local visible, core_mean = {}, {}
	local pool_sum, pool_n = 0, 0
	for _, id in ipairs(ids) do
		local h = history[id]
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
				visible[id] = samples
				core_mean[id] = sum / n
				pool_sum = pool_sum + sum
				pool_n = pool_n + n
			end
		end
	end
	if pool_n == 0 then return grid end
	local group_mean = pool_sum / pool_n

	-- rank cores by distance from the group average, farthest first -- this
	-- is both the palette assignment order (darkest to palest) and the draw
	-- order (darkest drawn first, palest drawn last so it stays on top)
	local ranked = {}
	for id in pairs(visible) do ranked[#ranked + 1] = id end
	table.sort(ranked, function(a, b)
		local da = math.abs(core_mean[a] - group_mean)
		local db = math.abs(core_mean[b] - group_mean)
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
	local pct = (cache[1] and cache[1].cores) or {}
	local ids = {}
	for id, v in pairs(pct) do
		ids[#ids + 1] = id
		local prev = smoothed[id]
		local ema = prev and (SMOOTHING_ALPHA * v + (1 - SMOOTHING_ALPHA) * prev) or v
		smoothed[id] = ema
		push_sample(id, ema, now)
	end
	table.sort(ids)
	if #ids == 0 or pane.w <= 0 or pane.h <= 0 then return end

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

	local grid = build_grid(ids, graph_w, graph_h, now)
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
	title = "CPU Cores Graph",
	min_w = 20,
	min_h = 8,
	redraw = redraw,
	opts = opts,
	info = {
		type = "module",
		name = "cpu_cores_graph",
		long_name = "CPU Cores Graph",
		author = "resmon",
		release = "v0.4.0",
		date = "2026-09-02",
		short_descr = "Per-core CPU usage history, all cores overlaid.",
		description = [[Plots every core's usage history on one shared 0-100
graph, each core colored by how far its average sits from the group
average, darkest-first so the palest curve stays on top.]],
		dependencies = { "per-core CPU usage percentage" },
	},
	sample = {
		{ cores = { { 0, 100 }, count = 8 } },
	},
} -- >}

-- vim: filetype=lua foldmethod=marker foldmarker=>{,>}
