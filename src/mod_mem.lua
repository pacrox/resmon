-- Base module: MEM usage (percentage of RAM in use)

local _, cache = ...

local opts = {} -- no configurable options today; empty table still required

local bar_color = { -- >{
	{ r = 134, g = 190, b = 67 },  -- #86be43
	{ r = 230, g = 200, b = 60 },
	{ r = 220, g = 70, b = 70 },
} -- >}

local LABEL = "RAM"
local LABEL_W = 6 -- blank + up to 4 chars of label + blank, before the Y axis

local function pad(s, w) -- >{
	s = tostring(s)
	if #s > w then return s:sub(1, w) end
	return s .. string.rep(" ", w - #s)
end -- >}

local function redraw(pane) -- >{
	local pct = (cache[1] and cache[1].percent) or 0
	local axis_x = pane.x + LABEL_W
	local bar_x = axis_x + 1
	local bar_w = math.max(pane.w - LABEL_W - 1, 0)

	local has_axis = pane.h > 3
	local bar_h = has_axis and math.max(pane.h - 2, 1) or pane.h

	local bar_pane = { x = bar_x, y = pane.y, w = bar_w, h = bar_h }
	Bar(bar_pane, pct, 0, 100, "horizontal", bar_color)
	WriteAt(pane.x, pane.y + math.floor(bar_h / 2), " " .. pad(LABEL, 4))

	if has_axis then
		local xticks = Pow2Ticks(0, 100, math.max(1, math.floor(bar_w / 8)))
		Axis(
			{ x = axis_x, y = pane.y, w = bar_w, h = bar_h },
			{ min = 0, max = 100 },
			{ min = 0, max = 1 },
			{ x = xticks, y = {} }
		)
	end
end -- >}

return { -- >{
	title = "MEM Usage",
	min_w = 20,
	min_h = 4,
	redraw = redraw,
	opts = opts,
	info = {
		type = "module",
		name = "mem",
		long_name = "Memory Usage",
		author = "resmon",
		release = "v0.4.0",
		date = "2026-09-02",
		short_descr = "RAM usage percentage as a horizontal bar.",
		description = [[Draws the current RAM usage percentage as a single
horizontal bar with an optional 0-100 axis, space permitting.]],
		dependencies = { "RAM usage percentage" },
	},
	sample = {
		{ percent = { 0, 100 } },
	},
} -- >}

-- vim: filetype=lua foldmethod=marker foldmarker=>{,>}
