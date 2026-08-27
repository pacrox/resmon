-- Custom module: GPU resource usage bars, fetched from `amdgpu_top -J`.
-- This is the one deliberate exception to "prefer FFI over popen": amdgpu_top
-- is an external tool (per spec) and there is no libc/FFI path to its data.
--
-- NOTE: the raw GRBM/GRBM2 performance-counter percentages (Graphics Pipe,
-- Shader Export, ...) read back as 0 on systems where the kernel's
-- perf_event_paranoid sysctl blocks unprivileged perf-counter access -- this
-- is a system permission restriction, not something resmon can work around.
-- "Total fdinfo" (per-process GPU engine usage, summed across all processes)
-- is populated regardless, since it comes from DRM/GEM fdinfo accounting,
-- not perf counters -- it is used here instead, and doubles as the
-- process-level 3D/LLM engine breakdown.

local refresh_rate = 0.5

local function extract_field(json, key) -- >{
	local escaped_key = key:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")
	local pattern = '"' .. escaped_key .. '"%s*:%s*{%s*"unit"%s*:%s*"[^"]*"%s*,%s*"value"%s*:%s*([%-%d%.eE]+)'
	return tonumber(json:match(pattern))
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

local function usage_percent(json, used_key, total_key) -- >{
	local used = extract_field(json, used_key)
	local total = extract_field(json, total_key)
	if not used or not total or total == 0 then return nil end
	return used / total * 100
end -- >}

-- "totals" is the pre-scoped "Total fdinfo" object (summed GPU engine usage
-- across all processes); fetch(json, totals) lets a resource pick either
-- source without re-scanning the JSON for "Total fdinfo" every time.
local resource_list = { -- >{
	{ label = "3D", fetch = function(json, totals)
		return totals and extract_field(totals, "GFX")
	end },
	{ label = "LLM", fetch = function(json, totals)
		return totals and extract_field(totals, "Compute")
	end },
	{ label = "MEDIA", fetch = function(json, totals)
		return totals and extract_field(totals, "Media")
	end },
	{ label = "VRAM", fetch = function(json)
		return usage_percent(json, "Total VRAM Usage", "Total VRAM")
	end },
	{ label = "GTT", fetch = function(json)
		return usage_percent(json, "Total GTT Usage", "Total GTT")
	end },
} -- >}

local bars_color = { -- >{
	{ r = 134, g = 190, b = 67 },  -- green, #86be43
	{ r = 230, g = 200, b = 60 },  -- yellow
	{ r = 230, g = 140, b = 40 },  -- orange
	{ r = 220, g = 70, b = 70 },   -- red
} -- >}

local LABEL_W = 8

local function pad(s, w) -- >{
	s = tostring(s)
	if #s > w then return s:sub(1, w) end
	return s .. string.rep(" ", w - #s)
end -- >}

-- amdgpu_top takes ~1.1s to start producing output (device probing), so it is
-- spawned ONCE as a long-running process in NDJSON streaming mode (-s <ms>,
-- one complete JSON object per line) instead of being re-spawned every tick;
-- re-spawning per tick was paying that ~1.1s startup cost on every redraw,
-- which blocked the whole (single-threaded) main loop for that long each time.
-- The child is left running: when resmon exits, the OS closes the pipe's read
-- end, and the child gets SIGPIPE on its next write and dies on its own.
local gpu_pipe = nil
local pipe_failed = false

local function get_pipe() -- >{
	if gpu_pipe or pipe_failed then return gpu_pipe end
	local interval_ms = math.max(math.floor(refresh_rate * 1000), 100)
	gpu_pipe = io.popen("amdgpu_top -J -s " .. interval_ms .. " 2>/dev/null")
	if not gpu_pipe then pipe_failed = true end
	return gpu_pipe
end -- >}

local function fetch_snapshot() -- >{
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

local function redraw(pane) -- >{
	local snap = fetch_snapshot()
	if not snap then
		WriteAt(pane.x, pane.y, "amdgpu_top: no data")
		return
	end

	local totals = extract_object(snap, "Total fdinfo")

	local axis_x = pane.x + LABEL_W
	local bar_x = axis_x + 1
	local bar_w = math.max(pane.w - LABEL_W - 1, 0)

	local has_axis = pane.h > #resource_list + 1
	local content_h = has_axis and math.max(pane.h - 2, #resource_list) or pane.h
	local base_block_h = math.max(1, math.floor(content_h / #resource_list))

	local bars_h = 0
	for i = 1, #resource_list do
		local res = resource_list[i]
		local value = res.fetch(snap, totals) or 0
		local block_h = (i == #resource_list) and (content_h - bars_h) or base_block_h
		local y = pane.y + bars_h
		WriteAt(pane.x, y + math.floor(block_h / 2), pad(res.label:upper(), LABEL_W))
		local bar_pane = { x = bar_x, y = y, w = bar_w, h = block_h }
		Bar(bar_pane, value, 0, 100, "horizontal", bars_color)
		bars_h = bars_h + block_h
	end

	if has_axis then
		local xticks = Pow2Ticks(0, 100, math.max(1, math.floor(bar_w / 8)))
		Axis(
			{ x = axis_x, y = pane.y, w = bar_w, h = bars_h },
			{ min = 0, max = 100 },
			{ min = 0, max = 1 },
			{ x = xticks, y = {} }
		)
	end
end -- >}

return { -- >{
	title = "GPU Monitor",
	min_w = 30,
	min_h = 6,
	default_delay = refresh_rate,
	redraw = redraw,
} -- >}

-- vim: filetype=lua foldmethod=marker foldmarker=>{,>}
