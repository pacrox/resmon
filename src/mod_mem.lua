-- Base module: MEM usage (percentage of RAM in use)

local refresh_rate = 1.5

local bar_color = { -- >{
	{ r = 134, g = 190, b = 67 },  -- #86be43
	{ r = 230, g = 200, b = 60 },
	{ r = 220, g = 70, b = 70 },
} -- >}

local LABEL = "RAM"
local LABEL_W = 4

local function read_mem_percent() -- >{
	local raw = ReadProcFile("/proc/meminfo")
	if not raw then return 0 end
	local total = tonumber(raw:match("MemTotal:%s*(%d+)"))
	local available = tonumber(raw:match("MemAvailable:%s*(%d+)"))
	if not total or total == 0 then return 0 end
	if not available then
		local free = tonumber(raw:match("MemFree:%s*(%d+)")) or 0
		local buffers = tonumber(raw:match("Buffers:%s*(%d+)")) or 0
		local cached = tonumber(raw:match("Cached:%s*(%d+)")) or 0
		available = free + buffers + cached
	end
	return (total - available) / total * 100
end -- >}

local function redraw(pane) -- >{
	local pct = read_mem_percent()
	local axis_x = pane.x + LABEL_W
	local bar_x = axis_x + 1
	local bar_w = math.max(pane.w - LABEL_W - 1, 0)

	local has_axis = pane.h > 3
	local bar_h = has_axis and math.max(pane.h - 2, 1) or pane.h

	local bar_pane = { x = bar_x, y = pane.y, w = bar_w, h = bar_h }
	Bar(bar_pane, pct, 0, 100, "horizontal", bar_color)
	WriteAt(pane.x, pane.y + math.floor(bar_h / 2), LABEL)

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
	default_delay = refresh_rate,
	redraw = redraw,
} -- >}

-- vim: filetype=lua foldmethod=marker foldmarker=>{,>}
