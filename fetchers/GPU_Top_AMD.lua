-- Custom fetcher: shared `amdgpu_top -J` stream, feeding both GPU display
-- modules (mod_gpu, mod_gpu_graph) from a single persistent process instead
-- of one each.
--
-- amdgpu_top takes ~1.1s to start producing output (device probing), so it
-- is spawned ONCE as a long-running process in NDJSON streaming mode (-s
-- <ms>, one complete JSON object per line) instead of being re-spawned every
-- tick. Ordinary Lua closure state (gpu_pipe) is enough to keep it alive
-- across fetch() calls -- no special core-level init hook is needed. The
-- child is left running: when resmon exits, the OS closes the pipe's read
-- end, and the child gets SIGPIPE on its next write and dies on its own.
--
-- NOTE: the very first line read from a freshly (re)spawned pipe always
-- reports every GRBM/GRBM2 sub-block as 0 -- amdgpu_top gates performance
-- counter sampling behind an "is the GPU idle" check computed from the
-- previous fdinfo interval, which doesn't exist yet on the first sample.
-- Non-issue in practice since the pipe is opened once and read every tick.

local opts = { -- >{
	refresh = { 0.5, "Fetch refresh rate in seconds (also sizes amdgpu_top's own -s sampling interval)" },
} -- >}

-- entry.refresh (from this fetcher's config entry) sizes amdgpu_top's own
-- -s <ms> sampling interval, so the subprocess's production rate actually
-- matches how often the scheduler calls fetch() -- falls back to opts.refresh
-- if unset.
local entry = ...
local REFRESH_MS = math.max(math.floor(((entry and entry.refresh) or opts.refresh[1]) * 1000), 100)

local gpu_pipe = nil
local pipe_failed = false

local function get_pipe() -- >{
	if gpu_pipe or pipe_failed then return gpu_pipe end
	gpu_pipe = io.popen("amdgpu_top -J -s " .. REFRESH_MS .. " 2>/dev/null")
	if not gpu_pipe then pipe_failed = true end
	return gpu_pipe
end -- >}

local function read_snapshot() -- >{
	local pipe = get_pipe()
	if not pipe then return nil end
	local line = pipe:read("*l")
	if not line or line == "" then
		pipe:close()
		gpu_pipe = nil -- allow a respawn attempt on the next tick
		return nil
	end
	return line
end -- >}

-- returns the substring of the JSON object nested under `key`, for looking
-- up a field name that is not unique at the top level (e.g. "GFX" also
-- appears under clock/voltage sensors elsewhere in the payload)
local function extract_object(json, key) -- >{
	local escaped_key = key:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")
	local key_start = json:find('"' .. escaped_key .. '"%s*:%s*{')
	if not key_start then return nil end
	local brace_start = json:find("{", key_start)
	local depth, in_str, escape = 0, false, false
	for i = brace_start, #json do
		local c = json:sub(i, i)
		if in_str then
			if escape then
				escape = false
			elseif c == "\\" then
				escape = true
			elseif c == '"' then
				in_str = false
			end
		else
			if c == '"' then
				in_str = true
			elseif c == "{" then
				depth = depth + 1
			elseif c == "}" then
				depth = depth - 1
				if depth == 0 then return json:sub(brace_start, i) end
			end
		end
	end
	return nil
end -- >}

local function fetch() -- >{
	local snap = read_snapshot()
	if not snap then return {}, 1, "amdgpu_top: no data" end
	return {
		raw = snap,
		totals = extract_object(snap, "Total fdinfo"),
		grbm = extract_object(snap, "GRBM"),
		grbm2 = extract_object(snap, "GRBM2"),
	}, 0
end -- >}

return { -- >{
	fetch = fetch,
	default_delay = REFRESH_MS / 1000,
	opts = opts,
	info = {
		type = "fetcher",
		name = "GPU_Top_AMD",
		data_type = "GPU engine/memory usage (amdgpu_top JSON)",
		long_name = "GPU Top (AMD)",
		author = "resmon",
		release = "v0.4.0",
		date = "2026-09-02",
		short_descr = "GPU engine and memory usage, from a shared amdgpu_top -J stream.",
		description = [[Spawns amdgpu_top -J once as a long-running NDJSON
stream and reads one snapshot per fetch(), shared by every module that
depends on this fetcher instead of one process per module.]],
		hardware = "AMD GPU",
		dependencies = {
			{ target = "amdgpu_top", descr = "External program providing GPU engine/memory JSON telemetry" },
		},
	},
} -- >}

-- vim: filetype=lua foldmethod=marker foldmarker=>{,>}
