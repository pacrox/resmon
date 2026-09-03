# resmon — Change Log

## v0.4.0

**Added**

- Standalone addon CLI: `resmon <addon_name> [-i|-h|-s|-d]` inspects,
  samples, or live-demos any fetcher or module on its own, without a
  config file; modes are cumulative, an optional `fetch.`/`mod.` prefix
  disambiguates a name shared by both kinds.
- Every fetcher/module now carries `info`/`opts` metadata (plus `ranges`
  for fetchers, `sample` fake-data templates for modules), validated by a
  shared, tightened contract check.
- `src/fake_fetcher.lua`: seeded noise generator driving `-s`/`-d` fake
  data from each module's `sample` template; history-graph modules get
  their rolling window pre-filled before a static `-s` render.
- `NONE` sentinel for a `fetcher = {...}` slot that should stay
  intentionally empty.
- `--list` (enumerate every installed fetcher/module), `--include <path>`
  (additive dev/test directory, takes priority on a name collision),
  `-o`/`--options <{lua-table}>` (CLI-side config override), `-r`/`--refresh`
  extended to also pace a module's fake-data tick.
- Global path flags (`--config-dir`/`-c`/`--config-file`/`--fetchers-dir`/
  `--modules-dir`) now recognized anywhere on the command line.
- `config/fetcher_addon_sample.lua`, `config/module_addon_sample.lua`,
  `config/ADDON-AUTHORING.md`: ready-to-copy addon skeletons and a
  walkthrough, installed by both `make install-config` and the release
  tarball's `install.sh`.
- `dist/install.sh`: detects an existing install and its version;
  automatically migrates a 0.3.0 config/addons to the new naming, or
  backs up and resets `config.lua` for anything older/unrecognized;
  `--upgrade` skips the confirmation prompt.

**Fixed**

- `prefill_module_history` no longer re-polls a real (`-f`-attached)
  fetcher during its synthetic history replay — was hanging on
  pipe-based fetchers and corrupting delta-based ones.
- `-d` on a module now actually respects its refresh rate, gated per
  cache slot instead of ticking unconditionally.
- `-d`/`-s` on a fetcher now render nested-table values and
  embedded-JSON string fields legibly instead of skipping/dumping them
  raw.
- `-s` pane width now correctly reaches half the terminal width instead
  of being capped too low.
- `-s` history prefill now respects an `-o`-overridden `interval`
  instead of always using the addon's static default.

**Changed**

- Custom module filenames and config `mod = "..."` values dropped the
  redundant `mod_` prefix (`mods/clock_graph.lua`, `mod = "clock_graph"`);
  fetcher naming is unchanged.
- Standalone-CLI and `--help`/`--list` output reformatted: a single
  banner/trailing-blank-line per invocation, terminal-width-aware
  word-wrapped tables, right-aligned `-i`/`--info` metadata,
  `[VALID]`/`[FAULT]` dependency markers.
- README overhauled throughout (new Standalone addon CLI section + demo
  GIF, Built-in Monitors table, Contributing points at the
  addon-authoring samples).

## v0.3.0

**Added**

- Fetcher/module architecture split: data fetching is now a first-class,
  deduplicated concept — one fetch per data source, shared and cached by
  every module that depends on it, each on its own refresh schedule
  (replaces every module fetching independently, e.g. three separate
  `/proc/stat` readers, two `amdgpu_top` processes).
- 3 base fetchers (`CPU_Average`, `MEM`, `TOP`) compiled in; 6 custom
  fetchers (`CPU_Cores`, `GPU_Top`, `CPU_Clock`, `GPU_Clock`, `CPU_Temp`,
  `GPU_Temp`) under a new `fetchers/` dir.
- Vendor-locked fetchers gained an `_AMD` suffix plus untested `_INTEL`
  drop-in counterparts (`CPU_Temp_INTEL`, `GPU_Clock_INTEL`,
  `GPU_Temp_INTEL`, `GPU_Top_INTEL`).
- `interval` config field on every scrolling-history graph module
  (X-axis time window, default 30s; previously hardcoded per module).
- New config-dir layout (`addons/fetchers`, `addons/mods`),
  `--fetchers-dir` CLI flag.
- Full and horizontal example configs; Contributing section in the
  README.
- `mod_clock_avg_graph`: average-CPU-clock variant of the clock graph
  (single line instead of one per core).

**Changed**

- Scrolling graph lines (CPU Cores Graph, GPU Graph, CLOCK Frequency
  Graph) now colored by distance from the group average instead of a
  fixed per-id shade.
- `show_gpu` option removed from the clock graphs — the GPU line is now
  toggled purely by whether `GPU_Clock` is listed as a dependency.
- `mod_clock_graph` now tracks every CPU core's frequency individually
  (one blue shade per core) instead of only core 0, ahead of the
  `show_gpu` removal above.
- Custom modules can now define their own config fields beyond the
  generic `refresh`/`weight` ones (the config entry is passed through as
  Lua varargs).

## v0.2.0

**Added**

- README, MIT license plus the symbolic protest statement,
  MANIFESTO.md, screenshots, demo GIF.
- CPU Pulse module (mirrored per-core bars, gradient coloring,
  interpolated fill columns for edge-to-edge symmetry).
- CLOCK Frequency Graph module (CPU + GPU core clock history via
  cpufreq/hwmon sysfs, dynamic min/max range).

**Fixed**

- Arrow/function keys no longer misread as ESC (were force-quitting the
  app); a follow-up fix stopped ordinary same-poll multi-byte keypresses
  from being dropped too.

**Changed**

- Pane frame restyle (normal border, brand color, bold titles); unified
  6-column left-margin convention across bar/graph modules; GPU Monitor
  label/coloring tweaks.

## v0.1.0

Initial release: C host + LuaJIT core runtime, base modules (CPU load,
RAM, process list), and the first custom modules (CPU Cores, CPU Cores
Graph, GPU Monitor, GPU Graph, TEMP Graph).
