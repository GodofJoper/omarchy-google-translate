#!/bin/bash
# Captures the current selection BEFORE the overlay grabs keyboard focus
# (focus steal makes the source app release the primary selection), then
# toggles the translator overlay.
#
# Priority: primary selection (highlighted text) -> clipboard -> empty.

set -o pipefail

STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/omarchy"
mkdir -p "$STATE_DIR"
OUT="$STATE_DIR/translate-selection.txt"

TEXT=""
TEXT="$(timeout 3 wl-paste --primary --type text --no-newline 2>/dev/null)"
if [ -z "$TEXT" ]; then
  TEXT="$(timeout 3 wl-paste --type text --no-newline 2>/dev/null)"
fi

printf '%s' "$TEXT" > "$OUT"

exec omarchy-shell shell toggle godofjoper.translate