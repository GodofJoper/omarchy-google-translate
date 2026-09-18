import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import "HotkeyModel.js" as HK

// Registers the translator's Hyprland keybinding and keeps it working across
// config reloads and restarts.
//
// Hyprland in Lua mode has no working runtime-only binding path (binds added
// through `hyprctl eval` never dispatch), so the binding is managed the same
// way Omarchy's own plugins do it: configure-hotkey.sh idempotently upserts
// a single `o.bind(...)` line into ~/.config/hypr/bindings.lua (timestamped
// backup per change) and runs `hyprctl reload`. Only the line whose
// description is "Google Translate" is ever touched.
//
// The preferred key and the on/off switch live in a small plugin-owned
// settings file: ~/.config/omarchy/google-translate.settings.json
Scope {
  id: service

  readonly property string pluginId: "godofjoper.translate"
  readonly property string home: Quickshell.env("HOME")
  readonly property string omarchyPath: Quickshell.env("OMARCHY_PATH") || "/usr/share/omarchy"
  readonly property string settingsPath: home + "/.config/omarchy/google-translate.settings.json"
  readonly property string script: home + "/.config/omarchy/plugins/" + pluginId + "/configure-hotkey.sh"

  property string hotkey: HK.DEFAULT_HOTKEY   // the key the user wants
  property bool enabled: true
  property string noticed: ""                 // last fallback we notified about
  property string active: ""                  // the key we asked to register ("")
  property string preferredOwner: ""          // what holds `hotkey` when we fell back
  property var binds: []                      // last parse of `hyprctl binds`
  property bool ready: false                  // settings read and first scan finished
  property int applyAttempts: 0
  property bool settingsLoaded: false

  readonly property string summary: HK.summary(active, hotkey, preferredOwner, enabled)
  readonly property string prettyActive: active ? HK.pretty(active) : ""

  function pretty(combo) { return HK.pretty(combo) }
  function statusOf(combo) { return HK.status(binds, combo) }

  // Register on load, unbind when the plugin goes away.
  Component.onCompleted: settingsFile.reload()
  Component.onDestruction: {
    Quickshell.execDetached(["bash", script, "unset"])
  }

  function applySettings(text) {
    var s = HK.parseSettings(text)
    hotkey = s.hotkey
    enabled = s.enabled
    noticed = s.noticed
    settingsLoaded = true
    scan()
  }

  function save() {
    settingsFile.setText(HK.serializeSettings({ hotkey: hotkey, enabled: enabled, noticed: noticed }))
  }

  // Re-reads `hyprctl binds`. Safe to call any time; reconciles when done.
  function scan() {
    if (bindsProc.running) { bindsProc.rerun = true; return }
    bindsProc.running = true
  }

  // Reach the state the user wants: keep exactly one live "Google Translate"
  // bind on `want` ("" = none). Idempotent: once the live binds already match,
  // nothing is re-requested.
  function sync() {
    if (!settingsLoaded) return
    var want = ""
    if (enabled) {
      var r = HK.resolve(binds, hotkey)
      preferredOwner = r.fallback ? r.preferredOwner : ""
      noticeIfNeeded(r)
      want = r.target
    } else {
      preferredOwner = ""
    }
    // For want !== "" the binding must be exactly on that combo; for "" there
    // must be no Google Translate binding at all.
    var landed = want ? (HK.status(binds, want).state === "ours") : (HK.ourCombos(binds).length === 0)
    if (landed) {
      active = want
      applyAttempts = 0
      return
    }
    if (active === want && applyAttempts > 0) {
      // We already asked for this state and it has not landed yet.
      // The script write + reload is asynchronous, so sit back while a
      // verification scan is pending.
      if (bindsProc.running || verifyTimer.running) return
      if (applyAttempts >= 2) {
        console.warn("Google Translate: could not register hotkey \u201C" + (want || "none") + "\u201D")
        active = ""
        applyAttempts = 0
        return
      }
      applyAttempts++
      verifyTimer.restart()
      return
    }
    active = want
    applyAttempts++
    runScript(want)
    verifyTimer.restart()
  }

  // configure-hotkey.sh is idempotent: when the config already carries the
  // requested binding it changes nothing and skips the reload.
  function runScript(target) {
    var args = ["bash", script, target ? "set" : "unset"]
    if (target) args.push(target)
    Quickshell.execDetached(args)
  }

  // Tell the user once when their preferred key was taken and we used
  // another, or when nothing was free. Remembered in the settings file so it
  // does not repeat at every login.
  function noticeIfNeeded(r) {
    if (!r.fallback) { if (noticed) { noticed = ""; save() }; return }
    if (r.preferred + " -> " + r.target === noticed) return
    noticed = r.preferred + " -> " + r.target
    save()
    var body
    if (r.target)
      body = "Opens with " + HK.pretty(r.target) + ". " + HK.pretty(r.preferred) + " was already used" + (r.preferredOwner ? " for \u201C" + r.preferredOwner + "\u201D" : "") + ". Change it with: omarchy-shell shell call " + pluginId + " setHotkey SUPER + T"
    else
      body = HK.pretty(r.preferred) + " and every fallback key are taken. Change it with: omarchy-shell shell call " + pluginId + " setHotkey SUPER + T"
    Quickshell.execDetached([omarchyPath + "/bin/omarchy-notification-send", "Google Translate", body])
  }

  // "" on success, otherwise a message for the user. A key something else
  // already holds is refused rather than silently falling back, so the CLI
  // and the overlay agree.
  function setHotkey(combo) {
    var p = HK.parseCombo(combo)
    if (p.error) return p.error
    var st = HK.status(binds, p.combo)
    if (st.state === "taken") return HK.pretty(p.combo) + " is already used for \u201C" + st.owner + "\u201D"
    hotkey = p.combo
    enabled = true
    noticed = ""
    save()
    scan()
    return ""
  }

  function setEnabled(value) {
    enabled = value === true
    if (enabled) noticed = ""
    save()
    active = ""
    applyAttempts = 0
    scan()
  }

  FileView {
    id: settingsFile
    path: service.settingsPath
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onLoaded: service.applySettings(text())
    onLoadFailed: service.applySettings("")
    onFileChanged: reload()
  }

  Process {
    id: bindsProc
    property bool rerun: false
    command: ["hyprctl", "binds"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        service.binds = HK.parseBinds(text)
        service.sync()
        if (bindsProc.rerun) { bindsProc.rerun = false; Qt.callLater(service.scan) }
      }
    }
  }

  // Confirms the binding landed after configure-hotkey.sh + reload. If it
  // did, the next sync is a no-op.
  Timer {
    id: verifyTimer
    interval: 900
    repeat: false
    onTriggered: service.scan()
  }

  // A config reload rebuilds Hyprland's binds from the Lua config and can
  // drop hand-edited lines, so re-check whenever the config reloads.
  Timer {
    id: reloadTimer
    interval: 600
    repeat: false
    onTriggered: service.scan()
  }

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (event && String(event.name) === "configreloaded") reloadTimer.restart()
    }
  }
}