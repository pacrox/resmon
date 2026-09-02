-- Custom module: per-core CPU usage, same data and rendering as CPU Cores,
-- but each core's bar is drawn twice in mirrored positions instead of once:
-- idlest-to-busiest outward from the center on one side, busiest-to-idlest
-- outward from the center on the other. The result is a symmetric
-- pulse/mountain shape with the highest usage at the center and the lowest
-- at both outer edges, instead of a single busiest-to-idlest ramp.

-- Data source: fetcher "CPU_Cores" (fetchers/fetch_cpu_cores.lua)

local _, cache = ...

local opts = {} -- no configurable options today; empty table still required

-- 25-shade gradient: green (0%) through yellow/orange (50%) to red (100%),
-- two linear segments joined at the midpoint. BandColor() (see core.lua)
-- picks one of these 25 entries by value, giving 25 discrete color steps
-- instead of the previous 4 flat bands.
local GRAD_LOW = { r = 134, g = 190, b = 67 }  -- green, #86be43
local GRAD_MID = { r = 230, g = 140, b = 40 }  -- yellow/orange
local GRAD_HIGH = { r = 220, g = 70, b = 70 }  -- red
local BARS_COLOR_COUNT = 25

local function lerp_color(a, b, t) -- >{
	return {
		r = math.floor(a.r + (b.r - a.r) * t + 0.5),
		g = math.floor(a.g + (b.g - a.g) * t + 0.5),
		b = math.floor(a.b + (b.b - a.b) * t + 0.5),
	}
end -- >}

local function build_bars_colors() -- >{
	local t = {}
	for i = 0, BARS_COLOR_COUNT - 1 do
		local frac = i / (BARS_COLOR_COUNT - 1)
		if frac <= 0.5 then
			t[i + 1] = lerp_color(GRAD_LOW, GRAD_MID, frac / 0.5)
		else
			t[i + 1] = lerp_color(GRAD_MID, GRAD_HIGH, (frac - 0.5) / 0.5)
		end
	end
	return t
end -- >}

local bars_colors = build_bars_colors()

local SCALE_MIN, SCALE_MAX = 0, 100

-- draws one column: a real core's bar, or a synthetic interpolated one
-- (width 1, value = average of its two neighbors) inserted to fill the
-- remainder of the pane width -- see the gap-insertion comment in redraw().
local function draw_column(pane, bar_h, x, w, v) -- >{
	if w <= 0 then return end
	local bar_pane = { x = x, y = pane.y, w = w, h = bar_h }
	Bar(bar_pane, v, SCALE_MIN, SCALE_MAX, "vertical", bars_colors)
end -- >}

local function redraw(pane) -- >{
	local pct = (cache[1] and cache[1].cores) or {}
	local cores = {}
	for id, v in pairs(pct) do cores[#cores + 1] = { id = id, v = v } end
	-- tie-break by id: table.sort is not stable, and cores tied on usage would
	-- otherwise swap columns at random between ticks, leaving stale label text
	-- behind (WriteAt does not clear the cell it previously occupied)
	table.sort(cores, function(a, b)
		if a.v == b.v then return a.id < b.id end
		return a.v > b.v
	end)

	local ncores = #cores
	if ncores == 0 or pane.w <= 0 or pane.h <= 0 then return end

	-- mirror the busiest-to-idlest ramp around the center: left half is the
	-- ramp reversed (idlest at the edge, busiest approaching the center),
	-- right half is the ramp as-is (busiest at the center, idlest at the
	-- edge) -- each core's value ends up rendered twice, once per half.
	local pulse = {}
	for i = ncores, 1, -1 do pulse[#pulse + 1] = cores[i] end
	for i = 1, ncores do pulse[#pulse + 1] = cores[i] end
	local npulse = #pulse

	local show_axis = pane.h > 5 and pane.w > 8
	local AXIS_W = 6
	local axis_x = show_axis and (pane.x + AXIS_W) or pane.x
	local bars_x = show_axis and (axis_x + 1) or pane.x
	local bars_w = math.max(pane.w - (bars_x - pane.x), 0)
	local bar_h = show_axis and math.max(pane.h - 2, 1) or pane.h

	if show_axis then
		local yticks = Pow2Ticks(SCALE_MIN, SCALE_MAX, math.max(1, math.floor(bar_h / 4)))
		Axis({ x = axis_x, y = pane.y, w = bars_w, h = bar_h }, nil, { min = SCALE_MIN, max = SCALE_MAX }, { y = yticks })
		WriteAt(axis_x, pane.y + bar_h, string.rep("\u{2500}", bars_w))
	end

	-- bars_w rarely divides evenly by npulse. Rather than stretching an
	-- existing core's bar to soak up the remainder (a flat-topped, blocky
	-- widening), the leftover width is used to insert new columns between
	-- adjacent pulse entries, each at the average height of its two
	-- neighbors -- a linear interpolation of the step between them, with an
	-- automatically blended color too since it goes through the same
	-- value-based gradient lookup as a real column. One inserted column per
	-- gap at most (remainder is always < npulse, and there are npulse-1
	-- gaps), starting at the single gap exactly in the center and moving
	-- outward in mirrored pairs from there.
	local base_w = math.floor(bars_w / npulse)
	local remainder = bars_w - base_w * npulse

	local gap_insert = {}
	if remainder > 0 then
		gap_insert[ncores] = true
		remainder = remainder - 1
	end
	local pair = 1
	while remainder > 0 do
		gap_insert[ncores - pair] = true
		remainder = remainder - 1
		if remainder > 0 then
			gap_insert[ncores + pair] = true
			remainder = remainder - 1
		end
		pair = pair + 1
	end

	local x = bars_x
	for i, core in ipairs(pulse) do
		draw_column(pane, bar_h, x, base_w, core.v)
		x = x + base_w
		if gap_insert[i] then
			local avg_v = (core.v + pulse[i + 1].v) / 2
			draw_column(pane, bar_h, x, 1, avg_v)
			x = x + 1
		end
	end
end -- >}

return { -- >{
	title = "CPU Pulse",
	min_w = 10,
	min_h = 6,
	redraw = redraw,
	opts = opts,
	info = {
		type = "module",
		name = "cpu_pulse",
		long_name = "CPU Pulse",
		author = "resmon",
		release = "v0.4.0",
		date = "2026-09-02",
		short_descr = "Mirrored per-core CPU usage bars forming a symmetric pulse shape.",
		description = [[Draws each core's usage twice, in mirrored ramps
outward from the center, so the busiest cores sit at the middle and the
idlest at both edges.]],
		dependencies = { "per-core CPU usage percentage" },
	},
	sample = {
		{ cores = { { 0, 100 }, count = 8 } },
	},
} -- >}

-- vim: filetype=lua foldmethod=marker foldmarker=>{,>}
