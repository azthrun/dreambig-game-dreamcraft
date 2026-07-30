#!/usr/bin/env bash
# Run the Dreamcraft headless test suite.
#
#   ./run_tests.sh              # the normal suite; exits 0 when green
#   ./run_tests.sh --selftest   # the deliberately failing suite; exits 1
#
# Override the engine location with GODOT=/path/to/godot if needed.
set -euo pipefail

GODOT="${GODOT:-/Applications/Godot_mono.app/Contents/MacOS/Godot}"
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ ! -x "$GODOT" ]]; then
	echo "godot not found or not executable: $GODOT" >&2
	echo "set GODOT=/path/to/godot and retry" >&2
	exit 127
fi

# Shutdown-time RID/ObjectDB chatter is normal for a headless run that quits mid
# frame; it is not a test result, so keep it out of the report.
exec "$GODOT" --headless --path "$PROJECT_DIR" res://tests/run_tests.tscn -- "$@" \
	2> >(grep -vE "RID (of type|allocations)|leaked|ObjectDB instances|resources still in use|^ *at: " >&2)
