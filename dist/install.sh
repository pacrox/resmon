#!/usr/bin/env bash
# resmon installer — run from inside the extracted release archive.
#
# Expects, alongside this script:
#   resmon                        (the prebuilt binary)
#   config/config.lua             (ready-to-use starter config)
#   config/addons/fetchers/*.lua
#   config/addons/mods/*.lua
#
# Installs the binary to $PREFIX/resmon (default: ~/.local/bin) and sets up
# ~/.config/resmon/ with the bundled fetchers, modules and a starter config.

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PREFIX="${PREFIX:-$HOME/.local/bin}"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/resmon"

if [ ! -f "$SCRIPT_DIR/resmon" ]; then
	echo "error: resmon binary not found next to this script ($SCRIPT_DIR/resmon)" >&2
	exit 1
fi

mkdir -p "$PREFIX"
cp "$SCRIPT_DIR/resmon" "$PREFIX/resmon"
chmod +x "$PREFIX/resmon"

mkdir -p "$CONFIG_DIR/addons/fetchers" "$CONFIG_DIR/addons/mods"
cp "$SCRIPT_DIR"/config/addons/fetchers/*.lua "$CONFIG_DIR/addons/fetchers/"
cp "$SCRIPT_DIR"/config/addons/mods/*.lua "$CONFIG_DIR/addons/mods/"

if [ -f "$CONFIG_DIR/config.lua" ]; then
	echo "existing config found, left untouched: $CONFIG_DIR/config.lua"
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
