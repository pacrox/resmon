-- ============================================================================
-- CUSTOM MODULE SKELETON -- copy this file as a starting point for a new
-- display module, then follow the inline comments.
-- ============================================================================
--
-- A module draws one pane, reading its data from one or more fetchers'
-- shared cache -- it never fetches/parses raw data sources itself, that's a
-- fetcher's job (see config/fetcher_addon_sample.lua).
--
-- WHERE THIS FILE GOES: rename it to "<your_module_name>.lua" (by
-- convention matching info.name below -- see the naming note further down)
-- and drop it into <modules-dir> -- by default ~/.config/resmon/addons/mods,
-- or wherever --modules-dir points.
--
-- REFERENCING IT FROM config.lua: a modules={...} entry looks like
--   { name = "my_pane", mod = "your_module_name", fetcher = { "SomeFetcher" } }
-- "name" is this INSTANCE's unique id (you can list the same "mod" more than
-- once, with different "fetcher"/"weight"/options, each needs its own
-- "name"); "mod" is the filename (without .lua) -- this is the field that
-- actually locates the file, "info.name" below is just what --list/-i show,
-- but MUST match "mod"/the filename by convention or --list becomes
-- confusing. "fetcher" lists, in order, which fetcher(s) this instance
-- reads -- see mods/temp_graph.lua for a real 2-fetcher example, including
-- the `NONE` sentinel to intentionally leave one slot empty.
--
-- QUICK DEV LOOP -- no install needed while iterating:
--   resmon --include <dir-with-this-file> your_module_name -i        info/metadata
--   resmon --include <dir-with-this-file> your_module_name -h        configurable options
--   resmon --include <dir-with-this-file> your_module_name -s        one-shot fake-data sample
--   resmon --include <dir-with-this-file> your_module_name -d        live fake-data demo
--   resmon --include <dir-with-this-file> your_module_name -d -f SomeFetcher   live demo, real data
-- `--include` is additive and takes priority over an already-installed
-- module of the same name, so you can iterate in place before copying the
-- finished file into <modules-dir>.
--
-- See mods/cpu_pulse.lua (single fetcher) and mods/temp_graph.lua (two
-- independently-refreshing fetchers, NONE-able) for real examples.

-- Every module chunk receives exactly TWO varargs: its own config entry
-- (or a synthetic one from the standalone CLI) and `cache`, an array of
-- data tables, one per name in this instance's `fetcher = {...}` list, in
-- that same order. `cache[i]` is a live reference into the shared fetcher
-- cache -- read it fresh inside redraw(), never copy/cache it yourself.
-- A `NONE` slot in `fetcher={...}` means `cache[i]` stays nil forever, by
-- design -- always guard reads (`cache[i] and cache[i].some_field`).
local entry, cache = ...

-- "opts": this module's user-configurable options. Each entry is
-- { default_value, "human-readable description shown by -h/-i" }. Must be
-- present even if empty ({}) -- required by resmon's addon contract. A
-- config.lua modules={...} entry (or `-o '{...}'` on the standalone CLI)
-- can override any of these per-instance; read overrides back via
-- `(entry and entry.<key>) or opts.<key>[1]`, e.g.:
local opts = {
	-- example option -- delete if this module has none
	-- interval = { 30, "Seconds of history shown on the X axis" },
}

-- local my_option = (entry and entry.my_option) or opts.my_option[1]

-- redraw(pane): called every time at least one of this instance's fetchers
-- produces fresh data (config-driven scheduler), or every tick in the
-- standalone CLI's -d demo. `pane` is { x, y, w, h } -- the pane's inner
-- drawing area (borders already excluded). Read `cache[i]` for the current
-- fetcher slot(s)' data; draw with the shared primitives declared globally
-- by core.lua: WriteAt(x, y, text[, color]), Bar(pane, value, min, max,
-- "horizontal"|"vertical", color_or_color_array), Axis(pane, x_range,
-- y_range, {x=labels, y=labels}), Pow2Ticks(min, max, count),
-- BandColor(value, min, max, color_array) -- see any file under mods/ for
-- real usage of each.
local function redraw(pane)
	local data = cache[1]
	local value = data and data.example_value
	if value == nil then
		WriteAt(pane.x, pane.y, "no data")
		return
	end
	WriteAt(pane.x, pane.y, "example_value = " .. tostring(value))
end

return {
	title = "My Module", -- shown in the pane's Frame() border
	min_w = 10, -- minimum pane width this module can render into
	min_h = 3, -- minimum pane height this module can render into
	redraw = redraw,
	opts = opts,

	info = {
		type = "module", -- literal string, must be exactly "module"
		name = "your_module_name", -- by convention, matches this file's
		--                            name (without .lua) and the "mod"
		--                            field a config.lua entry would use
		long_name = "My Module", -- shown by -h/-i and in --list
		author = "your name",
		release = "v1.0",
		date = "YYYY-MM-DD",
		short_descr = "One-line summary, shown by --list and the no-mode CLI.",
		description = [[Longer description, shown by -i/--info. It is
word-wrapped automatically to the live terminal width -- write it as a
single flowing paragraph, no need to hand-wrap the line breaks yourself.]],
		-- OPTIONAL: docs-only list of what this module needs, shown by
		-- -i/--info as "Depends on: ..." -- NOT validity-checked (unlike a
		-- fetcher's info.dependencies), just free-form data_type strings.
		dependencies = { "Example data (from MyFetcher)" },
	},

	-- REQUIRED: fake-data template for the standalone CLI's -s/-d modes
	-- (and for -f "attach a real fetcher" whenever `entry.fetcher` gives it
	-- fewer names than `sample` has slots). One entry per fetcher slot, in
	-- the same order as `fetcher = {...}` would list them. Leaf shapes:
	--   { min, max }                  -- one noised scalar in [min, max]
	--   { {min,max}, count = N }      -- N independently-noised scalars,
	--                                    as a 1..N array (e.g. per-core data)
	--   "literal" / 42                -- static value, used as-is
	-- See src/fake_fetcher.lua's own header comment for the full grammar
	-- (record/template leaves too) if this module's real data is more
	-- complex than flat numeric fields (e.g. an embedded JSON string, see
	-- mods/gpu.lua).
	sample = {
		{ example_value = { 0, 100 } },
	},
}

-- vim: filetype=lua foldmethod=marker foldmarker=>{,>}
