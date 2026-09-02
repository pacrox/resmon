#!/usr/bin/env bash
# resmon installer — run from inside the extracted release archive.
#
# Expects, alongside this script:
#   resmon                        (the prebuilt binary)
#   config/config.lua             (ready-to-use starter config)
#   config/addons/fetchers/*.lua
#   config/addons/mods/*.lua
#   config/fetcher_addon_sample.lua
#   config/module_addon_sample.lua
#   config/ADDON-AUTHORING.md
#
# Installs the binary to $PREFIX/resmon (default: ~/.local/bin) and sets up
# ~/.config/resmon/ with the bundled fetchers, modules, addon-authoring
# samples, and a starter config.
#
# Automatic upgrade handling is only supported from resmon 0.3.0 (the
# release before custom modules dropped their "mod_" filename prefix): if
# an existing ~/.config/resmon is found and `resmon` on $PATH reports
# 0.3.0, the old "mod_"-prefixed module files are removed and config.lua is
# edited in place to reference the new names (backed up first, to
# config.lua.bak). Pass --upgrade to skip the confirmation prompt (the
# warning and file list are still printed either way). Any other previously
# installed version is left alone file-wise, but config.lua is still backed
# up and replaced with the standard starter config, since there's no known
# rename map for it.

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PREFIX="${PREFIX:-$HOME/.local/bin}"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/resmon"

UPGRADE=0
for arg in "$@"; do
	[ "$arg" = "--upgrade" ] && UPGRADE=1
done

if [ ! -f "$SCRIPT_DIR/resmon" ]; then
	echo "error: resmon binary not found next to this script ($SCRIPT_DIR/resmon)" >&2
	exit 1
fi

NEW_VERSION="$("$SCRIPT_DIR/resmon" -v 2>/dev/null | awk '{print $2}' || true)"

# custom modules that dropped their "mod_" filename prefix between 0.3.0
# and 0.4.0 -- the only rename this installer knows how to migrate
OLD_MOD_NAMES="mod_clock_avg_graph mod_clock_graph mod_cpu_avg_value mod_cpu_cores mod_cpu_cores_graph mod_cpu_pulse mod_gpu mod_gpu_graph mod_temp_graph"

MIGRATE_030=0
UNKNOWN_OLD=0
STALE_FILES=()

if [ -d "$CONFIG_DIR" ]; then
	OLD_RESMON="$(command -v resmon 2>/dev/null || true)"
	OLD_VERSION=""
	if [ -n "$OLD_RESMON" ]; then
		OLD_VERSION="$("$OLD_RESMON" -v 2>/dev/null | awk '{print $2}' || true)"
	fi

	if [ "$OLD_VERSION" = "0.3.0" ]; then
		MIGRATE_030=1
	elif [ "$OLD_VERSION" != "$NEW_VERSION" ]; then
		UNKNOWN_OLD=1
	fi
	# else: same version already installed -- plain refresh, no warning
fi

if [ "$MIGRATE_030" -eq 1 ]; then
	echo "Found an existing resmon 0.3.0 installation ($CONFIG_DIR)."
	for name in $OLD_MOD_NAMES; do
		f="$CONFIG_DIR/addons/mods/$name.lua"
		[ -f "$f" ] && STALE_FILES+=("$f")
	done
	if [ "${#STALE_FILES[@]}" -gt 0 ]; then
		echo "These files will be deleted:"
		for f in "${STALE_FILES[@]}"; do echo "  $f"; done
	fi
	if [ "$UPGRADE" -ne 1 ]; then
		read -r -p "Continue? [Y/n] " reply
		case "$reply" in
			[nN]*) echo "aborted."; exit 1 ;;
		esac
	fi
fi

if [ "$UNKNOWN_OLD" -eq 1 ]; then
	echo "warning: an existing resmon install was found at $CONFIG_DIR, but its"
	echo "version could not be confirmed as 0.3.0 -- automatic addon-renaming"
	echo "upgrade is only supported from 0.3.0. No addon files will be deleted,"
	echo "but config.lua will be backed up to config.lua.bak and replaced with"
	echo "the standard starter config."
	read -r -p "Continue? [Y/n] " reply
	case "$reply" in
		[nN]*) echo "aborted."; exit 1 ;;
	esac
fi

mkdir -p "$PREFIX"
cp "$SCRIPT_DIR/resmon" "$PREFIX/resmon"
chmod +x "$PREFIX/resmon"

mkdir -p "$CONFIG_DIR/addons/fetchers" "$CONFIG_DIR/addons/mods"
cp "$SCRIPT_DIR"/config/addons/fetchers/*.lua "$CONFIG_DIR/addons/fetchers/"
cp "$SCRIPT_DIR"/config/addons/mods/*.lua "$CONFIG_DIR/addons/mods/"
cp "$SCRIPT_DIR/config/fetcher_addon_sample.lua" "$SCRIPT_DIR/config/module_addon_sample.lua" \
	"$SCRIPT_DIR/config/ADDON-AUTHORING.md" "$CONFIG_DIR/"

if [ "$MIGRATE_030" -eq 1 ] && [ "${#STALE_FILES[@]}" -gt 0 ]; then
	for f in "${STALE_FILES[@]}"; do rm -f "$f"; done
fi

if [ -f "$CONFIG_DIR/config.lua" ]; then
	cp "$CONFIG_DIR/config.lua" "$CONFIG_DIR/config.lua.bak"
	if [ "$MIGRATE_030" -eq 1 ]; then
		for name in $OLD_MOD_NAMES; do
			new_name="${name#mod_}"
			sed -i "s/\"$name\"/\"$new_name\"/g" "$CONFIG_DIR/config.lua"
		done
		echo "config.lua updated for the new addon names (previous copy: config.lua.bak)"
	elif [ "$UNKNOWN_OLD" -eq 1 ]; then
		cp "$SCRIPT_DIR/config/config.lua" "$CONFIG_DIR/config.lua"
		echo "config.lua replaced with the standard one (previous copy: config.lua.bak)"
	else
		echo "existing config found, left untouched: $CONFIG_DIR/config.lua"
	fi
else
	cp "$SCRIPT_DIR/config/config.lua" "$CONFIG_DIR/config.lua"
	echo "starter config installed: $CONFIG_DIR/config.lua"
fi

echo
echo "resmon installed to $PREFIX/resmon"

case ":$PATH:" in
	*":$PREFIX:"*) ;;
	*)
		echo
		echo "warning: $PREFIX is not on your \$PATH."
		echo "add this to your shell rc file:"
		echo "  export PATH=\"$PREFIX:\$PATH\""
		;;
esac

echo
echo "run it with: resmon"
