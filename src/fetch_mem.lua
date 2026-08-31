-- Base fetcher: MEM usage (percentage of RAM in use), from /proc/meminfo

local function fetch() -- >{
	local raw = ReadProcFile("/proc/meminfo")
	if not raw then return {}, 1, "failed to read /proc/meminfo" end
	local total = tonumber(raw:match("MemTotal:%s*(%d+)"))
	if not total or total == 0 then return {}, 1, "missing MemTotal" end
	local available = tonumber(raw:match("MemAvailable:%s*(%d+)"))
	if not available then
		local free = tonumber(raw:match("MemFree:%s*(%d+)")) or 0
		local buffers = tonumber(raw:match("Buffers:%s*(%d+)")) or 0
		local cached = tonumber(raw:match("Cached:%s*(%d+)")) or 0
		available = free + buffers + cached
	end
	return { percent = (total - available) / total * 100 }, 0
end -- >}

return { -- >{
	fetch = fetch,
	default_delay = 1.5,
} -- >}

-- vim: filetype=lua foldmethod=marker foldmarker=>{,>}
