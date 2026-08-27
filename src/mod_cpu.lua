-- Base module: CPU load average (1/5/15 minutes)

local bar_colors = { -- >{
	{ r = 134, g = 190, b = 67 },  -- #86be43
	{ r = 230, g = 200, b = 60 },
	{ r = 220, g = 70, b = 70 },
} -- >}

local SCALE_MIN, SCALE_MAX = 0, 25
local LABELS = { "1m", "5m", "15m" }
local LABEL_W = 4
local VALUE_W = 6
local AXIS_H = 2 -- axis line + tick label row
local SEPARATORS = 2 -- blank row between each of the 3 bars

local function read_loadavg() -- >{
	local raw = ReadProcFile("/proc/loadavg")
	if not raw then return 0, 0, 0 end
	local one, five, fifteen = raw:match("^(%S+)%s+(%S+)%s+(%S+)")
	return tonumber(one) or 0, tonumber(five) or 0, tonumber(fifteen) or 0
end -- >}

local function redraw(pane) -- >{
	local values = { read_loadavg() }
	local bar_x = pane.x + LABEL_W
	local bar_w = math.max(pane.w - LABEL_W - VALUE_W, 0)

	local bars_h = math.max(pane.h - AXIS_H - SEPARATORS, 3)
	local base_block_h = math.max(1, math.floor(bars_h / 3))

	local used_h = 0
	for i = 1, 3 do
		local block_h = (i == 3) and (bars_h - used_h) or base_block_h
		local y = pane.y + used_h + (i - 1)
		local bar_pane = { x = bar_x, y = y, w = bar_w, h = block_h }
		Bar(bar_pane, values[i], SCALE_MIN, SCALE_MAX, "horizontal", bar_colors)

		local label_row = y + math.floor(block_h / 2)
		WriteAt(pane.x, label_row, LABELS[i])
		WriteAt(bar_x + bar_w + 1, label_row, string.format("%.2f", values[i]))
		used_h = used_h + block_h
	end

	local axis_y = pane.y + used_h + SEPARATORS
	Axis({ x = bar_x, y = axis_y, w = bar_w, h = 0 }, { min = SCALE_MIN, max = SCALE_MAX }, nil, nil)
end -- >}

return { -- >{
	title = "CPU Load",
	min_w = 24,
	min_h = 7,
	default_delay = 60,
	fixed_delay = true,
	redraw = redraw,
} -- >}

-- vim: filetype=lua foldmethod=marker foldmarker=>{,>}
