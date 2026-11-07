#!/usr/bin/env bash
# Build one standalone mod pack from this repository.
#
#   ./build.sh                     -> dist/sit_anywhere-1.1.0.pck
#   ./build.sh --out FILE.pck      -> FILE.pck
#
# Requires Godot 4.5.x and python3 on PATH. Only the runtime files selected by .pckignore enter
# the pack. The script stages them in a throwaway Godot project, imports them and packs them.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT=""

while [ "$#" -gt 0 ]; do
	case "$1" in
		--out)
			if [ "$#" -lt 2 ]; then echo "--out needs a file path." >&2; exit 1; fi
			OUT="$2"
			shift 2
			;;
		-h|--help)
			sed -n '2,8p' "$0"
			exit 0
			;;
		*)
			echo "Unknown argument: $1" >&2
			exit 1
			;;
	esac
done

if ! command -v godot >/dev/null 2>&1; then
	echo "Godot not found on PATH (need the Godot 4.5 executable)." >&2
	exit 1
fi
if ! command -v python3 >/dev/null 2>&1; then
	echo "python3 is needed to read mod.json." >&2
	exit 1
fi
if [ ! -f "$ROOT/mod.json" ] || [ ! -f "$ROOT/.pckignore" ]; then
	echo "Expected mod.json and .pckignore beside build.sh." >&2
	exit 1
fi

ID="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1], encoding="utf-8"))["id"])' "$ROOT/mod.json")"
VERSION="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1], encoding="utf-8"))["version"])' "$ROOT/mod.json")"
if ! [[ "$ID" =~ ^[a-z0-9_]{1,40}$ ]]; then
	echo "mod.json id is not a valid mod id: $ID" >&2
	exit 1
fi
if [ -z "$VERSION" ]; then
	echo "mod.json version is empty." >&2
	exit 1
fi

if [ -z "$OUT" ]; then OUT="$ROOT/dist/$ID-$VERSION.pck"; fi
mkdir -p "$(dirname "$OUT")"

STAGE="$(mktemp -d)"
cleanup() { rm -rf "$STAGE"; }
trap cleanup EXIT

MOD="$STAGE/mods/$ID"
mkdir -p "$MOD"
tar -C "$ROOT" --exclude-from="$ROOT/.pckignore" -cf - . | tar -C "$MOD" -xf -

cat > "$STAGE/project.godot" <<EOF
config_version=5

[application]

config/name="$ID build"
EOF

echo "Importing resources..."
godot --headless --xr-mode off --path "$STAGE" --import

cp "$ROOT/tools/pack.gd" "$STAGE/pack.gd"
godot --headless --xr-mode off --path "$STAGE" --script res://pack.gd -- --out "$OUT"

echo "Copy $OUT into the game's mods folder and enable it in Settings -> Mods."
