-- Base fetcher: CPU load average (1/5/15 minutes), from /proc/loadavg

local opts = { -- >{
	refresh = { 60, "Fetch refresh rate in seconds" },
} -- >}

local function fetch() -- >{
	local raw = ReadProcFile("/proc/loadavg")
	if not raw then return {}, 1, "failed to read /proc/loadavg" end
	local one, five, fifteen = raw:match("^(%S+)%s+(%S+)%s+(%S+)")
	if not one then return {}, 1, "unexpected /proc/loadavg format" end
	return { one = tonumber(one) or 0, five = tonumber(five) or 0, fifteen = tonumber(fifteen) or 0 }, 0
end -- >}

return { -- >{
	fetch = fetch,
	default_delay = opts.refresh[1],
	fixed_delay = true,
	opts = opts,
	info = {
		type = "fetcher",
		name = "CPU_Average",
		data_type = "CPU load average",
		long_name = "CPU Load Average",
		author = "resmon",
		release = "v0.4.0",
		date = "2026-09-02",
		short_descr = "1/5/15-minute system load average.",
		description = [[Reads /proc/loadavg and reports the standard Linux
1/5/15-minute load average figures.]],
		hardware = "any",
		dependencies = {
			{ target = "/proc/loadavg", descr = "Linux load-average pseudo-file" },
		},
	},
} -- >}

-- vim: filetype=lua foldmethod=marker foldmarker=>{,>}
