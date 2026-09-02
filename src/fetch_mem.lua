-- Base fetcher: MEM usage (percentage of RAM in use), from /proc/meminfo

local opts = { -- >{
	refresh = { 1.5, "Fetch refresh rate in seconds" },
} -- >}

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
	default_delay = opts.refresh[1],
	opts = opts,
	ranges = { percent = { 0, 100 } },
	info = {
		type = "fetcher",
		name = "MEM",
		data_type = "RAM usage percentage",
		long_name = "Memory Usage",
		author = "resmon",
		release = "v0.4.0",
		date = "2026-09-02",
		short_descr = "Percentage of RAM currently in use.",
		description = [[Reads /proc/meminfo and reports the percentage of RAM
in use, preferring MemAvailable when the kernel exposes it, falling back to
MemFree+Buffers+Cached otherwise.]],
		hardware = "any",
		dependencies = {
			{ target = "/proc/meminfo", descr = "Linux memory-info pseudo-file" },
		},
	},
} -- >}

-- vim: filetype=lua foldmethod=marker foldmarker=>{,>}
