-- Base module: top processes (PID, USER, %CPU, %MEM, TIME+, COMMAND)

local _, cache = ...

local opts = {} -- no configurable options today; empty table still required

local procs_color = { -- >{
	{ r = 60, g = 60, b = 60 },
	{ r = 150, g = 110, b = 40 },
	{ r = 180, g = 50, b = 50 },
} -- >}

local procs_text_color = { r = 220, g = 220, b = 220 }

local BOLD = "\27[1m"
local BOLD_OFF = "\27[22m"

local COL_PID, COL_USER, COL_CPU, COL_MEM, COL_TIME = 8, 11, 7, 7, 10

local function pad(s, w) -- >{
	s = tostring(s)
	if #s > w then return s:sub(1, w) end
	return s .. string.rep(" ", w - #s)
end -- >}

local function redraw(pane) -- >{
	local data = cache[1] or {}
	-- copy before sorting: cache[1].procs is shared read-only state, the
	-- fetcher overwrites it wholesale next tick regardless
	local procs = {}
	for i, p in ipairs(data.procs or {}) do procs[i] = p end
	table.sort(procs, function(a, b) return a.cpu_pct > b.cpu_pct end)

	local cmd_w = math.max(pane.w - (COL_PID + COL_USER + COL_CPU + COL_MEM + COL_TIME), 0)

	local header = pad("PID", COL_PID) .. pad("USER", COL_USER)
		.. BOLD .. pad("%CPU", COL_CPU) .. pad("%MEM", COL_MEM) .. BOLD_OFF
		.. pad("TIME+", COL_TIME) .. BOLD .. pad("COMMAND", cmd_w) .. BOLD_OFF
	WriteAt(pane.x, pane.y, header)

	local rows_available = pane.h - 1
	for i = 1, math.min(rows_available, #procs) do
		local p = procs[i]
		local line = pad(p.pid, COL_PID) .. pad(p.user, COL_USER)
			.. BOLD .. pad(string.format("%.1f", p.cpu_pct), COL_CPU)
			.. pad(string.format("%.1f", p.mem_pct), COL_MEM) .. BOLD_OFF
			.. pad(p.time_str, COL_TIME) .. BOLD .. pad(p.command, cmd_w) .. BOLD_OFF
		local bg = BandColor(p.cpu_pct, 0, 100, procs_color)
		WriteAt(pane.x, pane.y + i, line, procs_text_color, bg)
	end
end -- >}

return { -- >{
	title = "TOP Processes",
	min_w = 40,
	min_h = 4,
	redraw = redraw,
	opts = opts,
	info = {
		type = "module",
		name = "top",
		long_name = "Top Processes",
		author = "resmon",
		release = "v0.4.0",
		date = "2026-09-02",
		short_descr = "Process table sorted by CPU usage.",
		description = [[Lists running processes (PID/USER/%CPU/%MEM/TIME+/
COMMAND), sorted by CPU usage descending, colored by CPU load band.]],
		dependencies = { "process list" },
	},
	-- fake process rows: "record"+"count" repeats the record template N times
	-- (each numeric leaf independently noised per row); a leaf that is an
	-- array of literals (not a {min,max} pair) cycles through those literals
	-- instead of generating noise -- see fake_fetcher.lua
	sample = {
		{
			procs = {
				count = 6,
				record = {
					pid = { 1234, 5820, 9981, 342, 7710, 2465 },
					user = { "root", "user", "daemon" },
					cpu_pct = { 0, 60 },
					mem_pct = { 0, 15 },
					time_str = "0:00",
					command = { "bash", "chrome", "resmon", "sshd", "systemd", "Xorg" },
				},
			},
			mem_total_kb = { 4000000, 32000000 },
		},
	},
} -- >}

-- vim: filetype=lua foldmethod=marker foldmarker=>{,>}
