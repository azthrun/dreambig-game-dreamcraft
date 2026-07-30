#!/usr/bin/env bash
# Measure the frame-rate budget by walking the player across the island.
#
#   ./run_perf.sh    # exits 0 if the budget is met, 1 if not
#
# Needs a real window: frame rate cannot be measured headlessly, since there is no
# rendering device. Override the engine location with GODOT=/path/to/godot.
#
# Results and methodology: docs/performance.md
set -euo pipefail

GODOT="${GODOT:-/Applications/Godot_mono.app/Contents/MacOS/Godot}"
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ ! -x "$GODOT" ]]; then
	echo "godot not found or not executable: $GODOT" >&2
	exit 127
fi

exec "$GODOT" --path "$PROJECT_DIR" -- --perf
