-- Custom module: per-core CPU usage, vertical bars sorted busiest-to-idlest (left-to-right)

local refresh_rate = 0.33

local bars_colors = { -- >{
	{ r = 134, g = 190, b = 67 },  -- green, #86be43
	{ r = 230, g = 200, b = 60 },  -- yellow
	{ r = 230, g = 140, b = 40 },  -- orange
	{ r = 220, g = 70, b = 70 },   -- red
} -- >}

local SCALE_MIN, SCALE_MAX = 0, 100
local prev_times = nil

local function clamp01(v) -- >{
	if v < 0 then return 0 end
	if v > 100 then return 100 end
	return v
end -- >}

local function read_cpu_times() -- >{
	local raw = ReadProcFile("/proc/stat")
	local times = {}
	if not raw then return times end
	for line in raw:gmatch("[^\n]+") do
		local id, rest = line:match("^cpu(%d+)%s+(.*)$")
		if id then
			local total, idle = 0, 0
			local field = 0
			for n in rest:gmatch("%d+") do
				field = field + 1
				local v = tonumber(n)
				total = total + v
				if field == 4 or field == 5 then idle = idle + v end
			end
			times[tonumber(id)] = { total = total, idle = idle }
		end
	end
	return times
end -- >}

local function core_usage_percents() -- >{
	local cur = read_cpu_times()
	local pct = {}
	for id, t in pairs(cur) do
		local p = prev_times and prev_times[id]
		if p then
			local dtotal = t.total - p.total
			local didle = t.idle - p.idle
			pct[id] = (dtotal > 0) and clamp01((dtotal - didle) / dtotal * 100) or 0
		else
			pct[id] = 0
		end
	end
	prev_times = cur
	return pct
end -- >}

local function redraw(pane) -- >{
	local pct = core_usage_percents()
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

	local col_w = math.max(1, math.floor(bars_w / ncores))

	for i, core in ipairs(cores) do
		local x = bars_x + (i - 1) * col_w
		if x >= bars_x + bars_w then break end
		local w = math.min(col_w, bars_x + bars_w - x)
		local bar_pane = { x = x, y = pane.y, w = w, h = bar_h }
		Bar(bar_pane, core.v, SCALE_MIN, SCALE_MAX, "vertical", bars_colors)
		if show_axis then
			local label = string.format("%.0f", core.v)
			local pad_left = math.max(math.floor((w - #label) / 2), 0)
			label = string.rep(" ", pad_left) .. label
			label = label .. string.rep(" ", math.max(w - #label, 0))
			WriteAt(x, pane.y + bar_h + 1, label)
		end
	end
end -- >}

return { -- >{
	title = "CPU Cores",
	min_w = 10,
	min_h = 6,
	default_delay = refresh_rate,
	redraw = redraw,
} -- >}

-- vim: filetype=lua foldmethod=marker foldmarker=>{,>}
