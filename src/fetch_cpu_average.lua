-- Base fetcher: CPU load average (1/5/15 minutes), from /proc/loadavg

local function fetch() -- >{
	local raw = ReadProcFile("/proc/loadavg")
	if not raw then return {}, 1, "failed to read /proc/loadavg" end
	local one, five, fifteen = raw:match("^(%S+)%s+(%S+)%s+(%S+)")
	if not one then return {}, 1, "unexpected /proc/loadavg format" end
	return { one = tonumber(one) or 0, five = tonumber(five) or 0, fifteen = tonumber(fifteen) or 0 }, 0
end -- >}

return { -- >{
	fetch = fetch,
	default_delay = 60,
	fixed_delay = true,
} -- >}

-- vim: filetype=lua foldmethod=marker foldmarker=>{,>}
