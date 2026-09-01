-- Custom module: average CPU usage across all cores, as a single big number.
-- Data source: fetcher "CPU_Cores" (fetchers/fetch_cpu_cores.lua)
-- Demonstrates Write.big/Write.med (block_fonts.lua), core.lua's public
-- character-cell font API.

local entry, cache = ...

local bar_colors = { -- >{
	{ r = 134, g = 190, b = 67 },  -- green, #86be43
	{ r = 230, g = 200, b = 60 },  -- yellow
	{ r = 230, g = 140, b = 40 },  -- orange
	{ r = 220, g = 70, b = 70 },   -- red
} -- >}

-- "big" (block-char, 6x9 per glyph) or "med" (sextant, 3x3 per glyph)
local SIZE = (entry and entry.size) or "big"

local function redraw(pane) -- >{
	local cores = (cache[1] and cache[1].cores) or {}
	local sum, n = 0, 0
	for _, v in pairs(cores) do
		sum = sum + v
		n = n + 1
	end
	local avg = (n > 0) and (sum / n) or 0
	local text = string.format("%5.1f%%", avg)
	local color = BandColor(avg, 0, 100, bar_colors)

	local write, w, h
	if SIZE == "med" then
		write, w, h = Write.med, Write.width_med(text), Write.height_med
	else
		write, w, h = Write.big, Write.width_big(text), Write.height_big
	end

	local x = pane.x + math.max(math.floor((pane.w - w) / 2), 0)
	local y = pane.y + math.max(math.floor((pane.h - h) / 2), 0)
	local sub_pane = { x = x, y = y, w = pane.x + pane.w - x, h = pane.y + pane.h - y }

	write(sub_pane, text, color)
end -- >}

return { -- >{
	title = "CPU Avg",
	min_w = 10,
	min_h = 4,
	redraw = redraw,
} -- >}

-- vim: filetype=lua foldmethod=marker foldmarker=>{,>}
