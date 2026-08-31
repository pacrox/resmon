-- Custom module: CPU and GPU temperature history, scrolling right-to-left,
-- same rendering style as CPU Cores Graph / GPU Graph (sextant resolution,
-- brightness wins on overlap) but with two fixed colors instead of a
-- monochrome palette: CPU in blue, GPU in magenta.
--
-- Data source: fetchers "CPU_Temp" and "GPU_Temp" (fetchers/CPU_Temp.lua,
-- fetchers/GPU_Temp.lua), each with potentially different refresh rates --
-- the params below are read from whichever cache slot has the latest data
-- each tick, independently.

local ffi_bit = require("bit")
local sChar = require("sextant_chars")

local _, cache = ...

local time_interval = 30 -- seconds shown on the X axis window, ticked every 10s

local TEMP_MIN, TEMP_MAX = 40, 100

local params = { -- >{
	{ id = 1, label = "CPU", color = { r = 70, g = 150, b = 255 } }, -- blue
	{ id = 2, label = "GPU", color = { r = 230, g = 90, b = 230 } }, -- magenta
} -- >}

-- raw sensor readings are noisy tick to tick; smoothing before plotting
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

local function brightness(c) -- >{
	return c.r + c.g + c.b
end -- >}

-- marks a single sub-cell (slot = half-cell column index, level = sub-row
-- from the bottom) in the shared grid.
local function mark_point(grid, vres, slot, level, color) -- >{
	local global_row = vres - 1 - level
	local row = math.floor(global_row / 3)
	local p = global_row % 3
	local col = math.floor(slot / 2)
	local sub_c = slot % 2
	local bitpos = p * 2 + sub_c
	local cell = grid[row][col]
	cell.mask = ffi_bit.bor(cell.mask, ffi_bit.lshift(1, bitpos))
	-- the brighter color always wins where the two lines overlap, regardless
	-- of which one reaches this cell first or last
	if not cell.color or brightness(color) > brightness(cell.color) then
		cell.color = color
	end
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

	for _, param in ipairs(params) do
		local h = history[param.id]
		if h then
			local prev_slot, prev_level = nil, nil
			for slot = 0, sample_cols - 1 do
				local seconds_ago = time_interval * (1 - slot / sample_cols)
				local v = value_at_time(h, now - seconds_ago)
				if v ~= nil then
					local frac = (v - TEMP_MIN) / (TEMP_MAX - TEMP_MIN)
					local level = math.floor(frac * (vres - 1) + 0.5)
					if prev_slot ~= nil then
						mark_diagonal(grid, vres, prev_slot, prev_level, slot, level, param.color)
					else
						mark_point(grid, vres, slot, level, param.color)
					end
					prev_slot, prev_level = slot, level
				else
					prev_slot, prev_level = nil, nil
				end
			end
		end
	end

	return grid
end -- >}

local function redraw(pane) -- >{
	local now = MonotonicNow()

	for i, param in ipairs(params) do
		local data = cache[i]
		local v = data and data.temp_c
		if v ~= nil then
			-- clamp into the fixed 20-110 display range right away so an
			-- out-of-range sensor glitch can never push a plotted point
			-- outside the grid
			v = clamp(v, TEMP_MIN, TEMP_MAX)
			local prev = smoothed[param.id]
			local ema = prev and (SMOOTHING_ALPHA * v + (1 - SMOOTHING_ALPHA) * prev) or v
			smoothed[param.id] = ema
			push_sample(param.id, ema, now)
		end
	end

	if pane.w <= 0 or pane.h <= 0 then return end

	local AXIS_W = 6
	local axis_x = pane.x + AXIS_W
	local graph_w = math.max(pane.w - AXIS_W - 1, 0)
	local graph_h = math.max(pane.h - 2, 1)

	local yticks = Pow2Ticks(TEMP_MIN, TEMP_MAX, math.max(1, math.floor(graph_h / 4)))
	Axis(
		{ x = axis_x, y = pane.y, w = graph_w, h = graph_h },
		{ min = -time_interval, max = 0 },
		{ min = TEMP_MIN, max = TEMP_MAX },
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
	title = "TEMP Graph",
	min_w = 20,
	min_h = 8,
	redraw = redraw,
} -- >}

-- vim: filetype=lua foldmethod=marker foldmarker=>{,>}
