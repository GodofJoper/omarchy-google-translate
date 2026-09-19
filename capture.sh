#!/bin/bash
# Captures the current selection BEFORE the overlay grabs keyboard focus
# (focus steal makes the source app release the primary selection), then
# toggles the translator overlay.
#
# Priority: primary selection (highlighted text) -> clipboard -> empty.
#
# The captured text is written to $STATE_DIR/translate-selection.txt with a
# strict byte cap, in a private directory (0700) as a private file (0600),
# atomically renamed over any previous entry (a pre-existing symlink is
# removed, never followed).

set -o pipefail

MAX_BYTES=1048576

STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/omarchy"
mkdir -p "$STATE_DIR"
chmod 700 "$STATE_DIR"
OUT="$STATE_DIR/translate-selection.txt"

capture_selection() {
  { timeout 3 wl-paste --primary --type text --no-newline 2>/dev/null || true; } \
    | head -c "$MAX_BYTES" \
    | iconv -f UTF-8 -t UTF-8 -c 2>/dev/null
}

TEXT="$(capture_selection || true)"
if [ -z "$TEXT" ]; then
  TEXT="$( { timeout 3 wl-paste --type text --no-newline 2>/dev/null || true; } \
    | head -c "$MAX_BYTES" \
    | iconv -f UTF-8 -t UTF-8 -c 2>/dev/null || true )"
fi

TMP="$(mktemp "$STATE_DIR/translate-selection.tmp.XXXXXX")" || exit 1
trap 'rm -f "$TMP"' EXIT
printf '%s' "$TEXT" > "$TMP"
chmod 600 "$TMP"
[ -L "$OUT" ] && rm -f "$OUT"
mv -f "$TMP" "$OUT"
chmod 600 "$OUT"
trap - EXIT

exec omarchy-shell shell toggle godofjoper.translate