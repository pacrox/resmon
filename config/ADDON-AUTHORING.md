# Writing a custom addon

resmon has two kinds of addon: **fetchers** (read one data source) and
**modules** (draw one pane from one or more fetchers' data). Both are
plain `.lua` files, loaded at startup with no recompilation. This doc is a
quick map of the contract; `fetcher_addon_sample.lua` and
`module_addon_sample.lua` in this same directory are ready-to-copy,
line-by-line commented skeletons — start from one of them, not from
scratch.

## Fetcher vs module

- A **fetcher** reads one data source (`/proc`, `/sys`, an external
  command...) on its own schedule and returns a flat table of values.
  One fetcher, one data source — never duplicate a fetch that multiple
  modules could share.
- A **module** draws one pane. It never touches `/proc`/`/sys` or spawns
  processes itself — it only reads the shared cache of whichever
  fetcher(s) it lists in its config entry's `fetcher = {...}`.

## The contract, in short

Both kinds return a plain Lua table with:

- `info` — metadata table: `type` (`"fetcher"`/`"module"`, literal),
  `name`, `long_name`, `author`, `release`, `date`, `short_descr`,
  `description`, plus kind-specific fields (`data_type`/`hardware` for a
  fetcher; both may also carry `dependencies` — for a fetcher, a list of
  `{target, descr}` checked live by `-i/--info`; for a module, a plain
  docs-only list of strings).
- `opts` — this addon's configurable options, `{ key = {default, "descr"} }`.
  Must be present even if empty (`{}`). A `config.lua` entry (or `-o
  '{...}'` on the standalone CLI) overrides a key's default; read the
  override back via `(entry and entry.key) or opts.key[1]`.
- Kind-specific:
  - Fetcher: `fetch = function() ... end` returning `(data, status[, err])`,
    plus `default_delay` (seconds) and, optionally, `fixed_delay = true`
    (refresh never overridable) and `ranges` (normalizes a value as
    `value (NN%)` in `-s`/`-d` output).
  - Module: `title`, `min_w`, `min_h`, `redraw = function(pane) ... end`,
    and `sample` (a fake-data template, one entry per `fetcher = {...}`
    slot, used by the standalone CLI's `-s`/`-d` and by any unattached
    slot — **required**, not optional).

`name` should match the file's own name (without `.lua`) — for a fetcher
this is enforced by how it's looked up; for a module it's just convention,
but `--list`/`-i` show `info.name`, so a mismatch is confusing.

See the two sample files for the exact shape of every field, including the
`entry`/`cache` varargs each chunk receives and the `sample` template
grammar (scalar ranges, per-core arrays, static literals).

## Iterating without installing

Drop your file(s) in a scratch directory and point `--include` at it —
this shadows an already-installed addon of the same name, so you can
develop and re-test in place:

```sh
resmon --include ./my-addon MyFetcher -i    # info/metadata
resmon --include ./my-addon MyFetcher -s    # one-shot sample
resmon --include ./my-addon MyFetcher -d    # live demo
```

For a module, `-s`/`-d` render with fake data (from `sample`) by default;
add `-f <FetcherName>` to attach a real fetcher instead (`NONE` for a slot
that should stay empty).

## Installing for real

Once it works, copy the file into `~/.config/resmon/addons/fetchers/` (a
fetcher) or `~/.config/resmon/addons/mods/` (a module) — or their `-dir`
equivalent if you use `--fetchers-dir`/`--modules-dir` — and reference it
from `config.lua`:

```lua
fetchers = { { name = "MyFetcher", refresh = 1.0 } },
modules  = { { name = "my_pane", mod = "my_module", fetcher = { "MyFetcher" } } },
```

See the project's main README (Configuration section) for the full
`config.lua` schema, and any file under `fetchers/`/`mods/` for real,
working examples of every field described above.
