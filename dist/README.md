# resmon

A lightweight terminal resource monitor: CPU, RAM, per-core usage, clock
frequency, temperatures and (on AMD/Intel) GPU stats, laid out in whatever
combination of panes you want.

## Install

```sh
./install.sh
```

This copies the `resmon` binary to `~/.local/bin/resmon`, and sets up
`~/.config/resmon/` with the bundled fetchers/modules plus a starter
`config.lua`. If `~/.local/bin` isn't already on your `$PATH`, the script
tells you what to add to your shell rc file.

Re-running `install.sh` later (e.g. after upgrading to a newer release)
refreshes the binary and the bundled fetchers/modules, but never overwrites
an existing `config.lua` — your own configuration is safe.

## Run

```sh
resmon
```

Keys: `Q` / `ESC` — quit. `P` — pause/resume data fetching (frame stays drawn).

## Configuring

Your config lives at `~/.config/resmon/config.lua`. The starter file installed
for you is a full-featured layout exercising every bundled module (per-core
usage, clock frequency, temperature and GPU graphs, load average, RAM,
process list) — open it and adjust `orientation`, remove entries you don't
want, or change a `weight` to resize a pane.

The starter config assumes an **AMD** system (CPU + integrated GPU). If your
machine is **Intel** instead, open `config.lua` and change every fetcher name
ending in `_AMD` to `_INTEL` (both in the `fetchers` list and in any module's
`fetcher = {...}` list that references it) — the Intel fetchers are drop-in
replacements, but haven't been verified on real Intel hardware, so treat them
as best-effort.

If a fetcher's data source isn't available on your system (e.g. no matching
temperature sensor, or the underlying tool isn't installed), the modules that
depend on it just show stale/no data instead of crashing resmon.

## Terminal recommendations

resmon itself uses little CPU, but rendering 24-bit color over a dense grid
puts the load on your terminal emulator instead. GPU-accelerated terminals
with a minimal renderer (e.g. `alacritty`) handle this comfortably; heavier
ones cost noticeably more per frame at the same window size.

## Uninstall

```sh
rm ~/.local/bin/resmon
rm -rf ~/.config/resmon
```

(Skip the second line if you'd rather keep your `config.lua` around.)

## Desktop screenshots

resmon at a dense, small-font, full-screen density:

```sh
alacritty -o window.dimensions.columns=68 -o window.dimensions.lines=178 -o font.size=5
```

<table>
<tr>
<td><img src="../images/desktop1.png" width="100%"></td>
<td><img src="../images/desktop2.png" width="100%"></td>
</tr>
<tr>
<td><img src="../images/desktop3.png" width="100%"></td>
<td><img src="../images/desktop4.png" width="100%"></td>
</tr>
</table>
