#!/usr/bin/env bash
# Capture the game's own viewport to PNG files.
#
#   ./run_screenshot.sh [output-dir]    # defaults to ./screenshots
#
# Writes ground-level, lifted and high views. Needs a real window: a headless run has
# no rendering device, so nothing can be culled, lit, or seen.
#
# This is how visual bugs get found without a human squinting at the game. It caught the
# washed-out terrain palette that every headless test had passed over.
set -euo pipefail

GODOT="${GODOT:-/Applications/Godot_mono.app/Contents/MacOS/Godot}"
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT_DIR="${1:-$PROJECT_DIR/screenshots}"

if [[ ! -x "$GODOT" ]]; then
	echo "godot not found or not executable: $GODOT" >&2
	exit 127
fi

mkdir -p "$OUT_DIR"
exec "$GODOT" --path "$PROJECT_DIR" -- --screenshot "$OUT_DIR"
