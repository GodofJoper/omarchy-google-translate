#!/bin/bash
# Shows or hides the Google Translate icon in the Omarchy bar.
#
# The bar is drawn from the widget entries in the user's shell.json, so the
# icon is one of those entries: this script adds it, removes it, or reports
# where it is, and touches nothing else in the file. Running it twice does
# what running it once did, the file is written atomically next to a
# timestamped backup, and the shell is asked to reload afterwards.
#
# Only the bar entry is managed. The hotkey and the overlay are left exactly as
# they are, so hiding the icon is not the same as turning the plugin off.
#
#   bar-icon.sh enable [left|center|right]   show the icon (default: the
#                                           section the manifest asks for)
#   bar-icon.sh disable                     hide the icon
#   bar-icon.sh toggle [left|center|right]   flip it
#   bar-icon.sh status                      where the icon is, if anywhere
set -euo pipefail

PLUGIN_DIR="$(cd "$(dirname "$0")" && pwd)"
MANIFEST="$PLUGIN_DIR/manifest.json"
# Not XDG_CONFIG_HOME: that is the path the shell itself reads, hard-coded.
CONFIG="$HOME/.config/omarchy/shell.json"

fail() {
  echo "bar-icon: $*" >&2
  exit 1
}

usage() {
  echo "usage: bar-icon.sh [enable [left|center|right] | disable | toggle [left|center|right] | status]" >&2
}

ACTION="${1:-status}"
SECTION="${2:-}"

case "$ACTION" in
  enable | disable | toggle | status) ;;
  -h | --help)
    usage
    exit 0
    ;;
  *)
    usage
    exit 2
    ;;
esac

if (( $# > 2 )); then
  usage
  exit 2
fi
if [[ -n $SECTION && ! $SECTION =~ ^(left|center|right)$ ]]; then
  fail "section must be left, center, or right"
fi
if [[ -n $SECTION && $ACTION != enable && $ACTION != toggle ]]; then
  usage
  exit 2
fi

# The layout lives in one JSON file and everything worth saying about it is
# decided by walking that file, so the walk is one small python worker. It
# prints key=value lines for the shell below; it never prints anything else.
result="$(python3 - "$MANIFEST" "$CONFIG" "$ACTION" "$SECTION" <<'PYTHON'
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time

manifest_path, config_path, action, section = sys.argv[1:5]
SECTIONS = ("left", "center", "right")
# Where the shell itself would drop a new widget, so the icon lands in the
# same spot as anything added with `omarchy plugin enable`.
ANCHORS = {"left": "omarchy.workspaces", "center": "omarchy.weather", "right": "omarchy.tray"}


def die(message):
    sys.stderr.write("bar-icon: %s\n" % message)
    raise SystemExit(1)


def read_json(path):
    try:
        with open(path, "r", encoding="utf-8") as handle:
            return json.load(handle)
    except (OSError, ValueError):
        return None


def load_manifest():
    manifest = read_json(manifest_path)
    if not isinstance(manifest, dict) or not manifest.get("id"):
        die("no readable manifest at " + manifest_path)
    return manifest


def load_config():
    config = read_json(config_path)
    if isinstance(config, dict) and config.get("version") == 1:
        return config
    if os.path.exists(config_path):
        die(config_path + " is not a version 1 shell config")
    # No user file yet: the shell is drawing its own defaults, so start from
    # those instead of handing it a bar with nothing in it.
    try:
        running = subprocess.run(
            ["omarchy-shell", "shell", "listShellConfig"],
            capture_output=True, text=True, timeout=10)
        config = json.loads(running.stdout or "")
    except (OSError, ValueError, subprocess.SubprocessError):
        config = None
    if not isinstance(config, dict) or config.get("version") != 1:
        config = {"version": 1}
    return config


def layout_of(config):
    bar = config.get("bar")
    if not isinstance(bar, dict):
        bar = {}
        config["bar"] = bar
    layout = bar.get("layout")
    if not isinstance(layout, dict):
        layout = {}
        bar["layout"] = layout
    for name in SECTIONS:
        if not isinstance(layout.get(name), list):
            layout[name] = []
    return layout


def placed(layout, plugin_id):
    """Every (section, index) currently holding the plugin's bar entry."""
    spots = []
    for name in SECTIONS:
        for index, entry in enumerate(layout[name]):
            if isinstance(entry, dict) and str(entry.get("id", "")) == plugin_id:
                spots.append((name, index))
    return spots


def insertion_point(layout, name):
    anchor = ANCHORS[name]
    for index, entry in enumerate(layout[name]):
        if isinstance(entry, dict) and str(entry.get("id", "")) == anchor:
            return index + 1
    return len(layout[name])


def where(name, index, layout):
    return "%s, position %d of %d" % (name, index + 1, len(layout[name]))


def save(config):
    """Write the config back atomically, keeping the file private and leaving a
    timestamped backup beside it like configure-hotkey.sh does."""
    directory = os.path.dirname(config_path)
    os.makedirs(directory, exist_ok=True)
    mode = 0o600
    if os.path.exists(config_path):
        mode = os.stat(config_path).st_mode & 0o777
        shutil.copy2(config_path, "%s.bak.google-translate.%d" % (config_path, int(time.time())))
    handle = tempfile.NamedTemporaryFile(
        mode="w", encoding="utf-8", dir=directory,
        prefix=".shell.json.", suffix=".tmp", delete=False)
    try:
        handle.write(json.dumps(config, indent=2, ensure_ascii=False) + "\n")
        handle.flush()
        os.fsync(handle.fileno())
        handle.close()
        os.chmod(handle.name, mode)
        os.replace(handle.name, config_path)
    except BaseException:
        os.unlink(handle.name)
        raise


manifest = load_manifest()
plugin_id = str(manifest["id"])
widget = manifest.get("barWidget")
widget = widget if isinstance(widget, dict) else {}
if not section:
    section = str(widget.get("defaultSection") or "right")
if section not in SECTIONS:
    section = "right"

config = load_config()
layout = layout_of(config)
spots = placed(layout, plugin_id)
changed = 0
rescan = 0

def report():
    if not spots:
        return "Google Translate icon: off"
    name, index = spots[0]
    return "Google Translate icon: on (" + where(name, index, layout) + ")"


if action == "status":
    message = report()
else:
    present = bool(spots)
    add = not present and action in ("enable", "toggle")
    if add:
        index = insertion_point(layout, section)
        layout[section].insert(index, {"id": plugin_id})
        changed = 1
        # A new entry needs the manifest read again before the bar can build it.
        rescan = 1
        message = "Google Translate icon: on (" + where(section, index, layout) + ")"
        save(config)
    elif present and action in ("disable", "toggle"):
        for name, index in reversed(spots):
            layout[name].pop(index)
        changed = 1
        message = "Google Translate icon: off (was in %s)" % ", ".join(
            sorted({name for name, _ in spots}))
        save(config)
    else:
        message = report()

sys.stdout.write("changed=%d\nrescan=%d\nmessage=%s\n" % (changed, rescan, message))
PYTHON
)" || exit 1

changed=0
rescan=0
message=""
while IFS='=' read -r key value; do
  case "$key" in
    changed) changed="$value" ;;
    rescan) rescan="$value" ;;
    message) message="$value" ;;
  esac
done <<< "$result"

echo "$message"

if (( changed )); then
  omarchy-shell shell reloadConfig >/dev/null 2>&1 || true
  if (( rescan )); then
    omarchy-shell shell rescanPlugins >/dev/null 2>&1 || true
  fi
  # Nobody is reading stdout when this runs from the bar, so say it there too.
  if [[ ! -t 1 ]]; then
    helper="${OMARCHY_PATH:-/usr/share/omarchy}/bin/omarchy-notification-send"
    if [[ -x $helper ]]; then
      "$helper" "Google Translate" "$message" >/dev/null 2>&1 || true
    fi
  fi
fi
