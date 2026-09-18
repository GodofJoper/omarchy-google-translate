#!/bin/bash
# Manages the Google Translate overlay hotkey in ~/.config/hypr/bindings.lua
# (or the legacy bindings.conf). Runs `hyprctl reload` so the binding is live
# immediately, and leaves a timestamped backup next to the config on every
# change.
#
# The o.bind() line is recognised by its "Google Translate" description, the
# same marker the plugin recognises in `hyprctl binds`. The script only ever
# touches lines carrying that marker and never edits anything else in the
# user's config.
set -euo pipefail

PLUGIN_DIR="$(cd "$(dirname "$0")" && pwd)"
COMMAND="$PLUGIN_DIR/capture.sh"
DESC="Google Translate"
DEFAULT_COMBO="SUPER + ALT + T"

HYPR_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/hypr"
LUA="$HYPR_DIR/bindings.lua"
CONF="$HYPR_DIR/bindings.conf"

ACTION="${1:-set}"
COMBO="${2:-$DEFAULT_COMBO}"

case "$ACTION" in
  set|unset) ;;
  *) echo "usage: configure-hotkey.sh [set <combo>|unset]" >&2; exit 2 ;;
esac

if [[ ! -f $LUA && ! -f $CONF ]]; then
  echo "configure-hotkey: no bindings.lua or bindings.conf in $HYPR_DIR" >&2
  exit 1
fi

STAMP=$(date +%s)
changed=0
tmp=$(mktemp)
trap 'rm -f "${tmp:-}"' EXIT

if [[ -f $LUA ]]; then
  if [[ "$ACTION" == unset ]]; then
    grep -vE '"'"$DESC"'"' "$LUA" > "$tmp" || true
  else
    grep -vE '"'"$DESC"'"' "$LUA" > "$tmp" || true
    printf 'o.bind("%s", "%s", "%s")\n' "$COMBO" "$DESC" "$COMMAND" >> "$tmp"
  fi
  if ! cmp -s "$LUA" "$tmp"; then
    cp "$LUA" "$LUA.bak.google-translate.$STAMP"
    mv "$tmp" "$LUA"
    changed=1
  fi
elif [[ -f $CONF ]]; then
  if [[ "$ACTION" == unset ]]; then
    grep -vE "$DESC" "$CONF" > "$tmp" || true
  else
    combo_conf=$(printf '%s' "$COMBO" | sed 's/ + / /g')
    grep -vE "$DESC" "$CONF" > "$tmp" || true
    printf 'bindd = %s, Google Translate, exec, %s\n' "$combo_conf" "$COMMAND" >> "$tmp"
  fi
  if ! cmp -s "$CONF" "$tmp"; then
    cp "$CONF" "$CONF.bak.google-translate.$STAMP"
    mv "$tmp" "$CONF"
    changed=1
  fi
fi

if (( changed )); then
  hyprctl reload >/dev/null || true
fi

errors=$(hyprctl configerrors || true)
if [[ -n $errors ]]; then
  printf '%s\n' "$errors" >&2
  exit 1
fi

if [[ "$ACTION" == unset ]]; then
  echo "Google Translate hotkey removed"
else
  echo "Google Translate hotkey: $COMBO"
fi