-- ============================================================================
-- CUSTOM FETCHER SKELETON -- copy this file as a starting point for a new
-- custom fetcher, then follow the inline comments.
-- ============================================================================
--
-- A fetcher reads ONE data source (a /proc or /sys file, an external
-- command, a persistent subprocess pipe, ...) on its own schedule and makes
-- the result available to every module that lists it in `fetcher = {...}`.
-- One fetcher, one data source: never fetch what nobody displays, never
-- duplicate a fetch that multiple modules could share.
--
-- WHERE THIS FILE GOES: rename it to "<YourFetcherName>.lua" (must match
-- info.name below EXACTLY, case-sensitive -- this is also the name used to
-- reference it from a module's `fetcher = {...}` list or a config.lua
-- fetchers={...} entry) and drop it into <fetchers-dir> -- by default
-- ~/.config/resmon/addons/fetchers, or wherever --fetchers-dir points.
--
-- QUICK DEV LOOP -- no install needed while iterating:
--   resmon --include <dir-with-this-file> <YourFetcherName> -i   info/metadata
--   resmon --include <dir-with-this-file> <YourFetcherName> -h   configurable options
--   resmon --include <dir-with-this-file> <YourFetcherName> -s   one-shot real sample
--   resmon --include <dir-with-this-file> <YourFetcherName> -d   live real demo
-- `--include` is additive and takes priority over an already-installed
-- fetcher of the same name, so you can iterate in place before copying the
-- finished file into <fetchers-dir>.
--
-- See fetchers/CPU_Temp_AMD.lua (simple, single sysfs read) and
-- fetchers/GPU_Top_AMD.lua (persistent subprocess pipe, reads its own
-- config entry to size the subprocess's polling rate) for real examples.

-- "opts": this fetcher's user-configurable options. Each entry is
-- { default_value, "human-readable description shown by -h/-i" }. Must be
-- present even if empty ({}) -- required by resmon's addon contract. A
-- config.lua fetchers={...} entry (or `-o '{...}'` on the standalone CLI)
-- can override any of these per-instance; read overrides back via
-- `(entry and entry.<key>) or opts.<key>[1]` (see `entry` below).
local opts = {
	refresh = { 1.0, "Fetch refresh rate in seconds" },
	-- example: add more options the same way
	-- threshold = { 80, "Some other configurable value" },
}

-- Every fetcher chunk receives exactly ONE vararg: its own config entry
-- (either a config.lua fetchers={...} table, or a synthetic one the
-- standalone CLI builds from -o/--options). Most fetchers never need to
-- read it -- refresh pacing is handled entirely by core.lua's scheduler via
-- `default_delay`/`fixed_delay` below. Only read `entry` yourself if the
-- fetch logic itself needs an option value at LOAD time -- e.g. sizing an
-- external process's own polling interval to match, the way
-- fetchers/GPU_Top_AMD.lua does:
--   local entry = ...
--   local refresh = (entry and entry.refresh) or opts.refresh[1]
local entry = ...

-- fetch(): called by the scheduler at most once every "default_delay"
-- seconds (or "-r/--refresh" seconds, in the standalone CLI's -d mode).
-- Must return (data, status[, err_string]):
--   data   -- a flat table of values; keys may also hold nested tables or
--             opaque strings (see mods/gpu.lua's fetcher for a JSON-string
--             example) -- whatever shape the consuming module(s) expect.
--             Reserved keys matching ^_[A-Z_]+$ (e.g. _ERROR) are written
--             by core.lua itself -- never set them from here.
--   status -- 0 = ok (data merged into the shared cache); 1 = error (the
--             consuming module(s) just keep showing their last-good data,
--             err_string is shown by the standalone CLI's -d/-s modes)
local function fetch()
	-- ... read your data source here ...
	-- local raw = ReadProcFile("/proc/something") -- FFI-based, see core.lua
	-- if not raw then return {}, 1, "failed to read /proc/something" end
	return { example_value = 0 }, 0
end

return {
	fetch = fetch,
	default_delay = opts.refresh[1], -- single source of truth for the default
	-- fixed_delay = true, -- uncomment if this fetcher's rate should NEVER
	--                         be overridable per-instance (e.g. a slow,
	--                         expensive read like the base CPU_Average's 60s)

	opts = opts,

	-- OPTIONAL: normalizes a value in -s/-d output as "value (NN%)", keyed
	-- identically to fetch()'s returned data keys. Omit entirely if not
	-- applicable to this data.
	-- ranges = { example_value = { 0, 100 } },

	info = {
		type = "fetcher", -- literal string, must be exactly "fetcher"
		name = "MyFetcher", -- MUST match this file's name (without .lua),
		--                     case-sensitive -- also what a module's
		--                     fetcher={...} list or a config.lua
		--                     fetchers={...} entry references it by
		long_name = "My Fetcher", -- shown by -h/-i and in --list
		author = "your name",
		release = "v1.0",
		date = "YYYY-MM-DD",
		short_descr = "One-line summary, shown by --list and the no-mode CLI.",
		description = [[Longer description, shown by -i/--info. It is
word-wrapped automatically to the live terminal width -- write it as a
single flowing paragraph, no need to hand-wrap the line breaks yourself.]],
		data_type = "What this fetcher's data represents, for -i/--info docs.",
		hardware = "any", -- or e.g. "AMD GPU" / "NVIDIA GPU", shown by -i
		-- OPTIONAL: checked live by -i/--info, printed as [VALID]/[FAULT].
		-- "target" starting with "/" is checked via a readability check
		-- (file/sysfs path); anything else is checked via `command -v`
		-- (external program must be on PATH). Omit if this fetcher has no
		-- external dependency worth checking.
		dependencies = {
			{ target = "/path/to/whatever", descr = "What this path is for." },
		},
	},
}

-- vim: filetype=lua foldmethod=marker foldmarker=>{,>}
