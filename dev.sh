#!/usr/bin/env bash
# Run this mod from source against a Home: Equestria checkout.
#
#   ./dev.sh [game arguments...]
#
# The mod is expected at <game>/mods/sit_anywhere/. Set EQ_PROJECT_ROOT to another checkout.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${EQ_PROJECT_ROOT:-$(cd "$ROOT/../.." && pwd)}"

if [ ! -f "$PROJECT_ROOT/project.godot" ]; then
	echo "No game project at $PROJECT_ROOT; set EQ_PROJECT_ROOT." >&2
	exit 1
fi
if ! command -v python3 >/dev/null 2>&1; then
	echo "python3 is needed to read mod.json." >&2
	exit 1
fi
if ! command -v godot >/dev/null 2>&1; then
	echo "Godot not found on PATH (need 4.5.x)." >&2
	exit 1
fi

ID="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1], encoding="utf-8"))["id"])' "$ROOT/mod.json")"
exec godot --xr-mode off --path "$PROJECT_ROOT" -- --mod-src "$ID" "$@"
