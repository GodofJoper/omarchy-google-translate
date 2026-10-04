import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "HotkeyModel.js" as HK

// Bar icon for the translator: click it with text selected and the overlay
// opens on that selection, exactly like the hotkey does. Right-click takes the
// icon back off the bar.
//
// The icon is a bar entry like any other, so `bar-icon.sh enable|disable` (or
// the plugin's setBarIconEnabled) owns it — this file is only ever built while
// that entry is in the bar layout.
BarWidget {
  id: root
  moduleName: "godofjoper.translate"

  readonly property string pluginId: "godofjoper.translate"
  readonly property string pluginDir: (Quickshell.env("HOME") || "") + "/.config/omarchy/plugins/" + pluginId
  readonly property string settingsPath: (Quickshell.env("HOME") || "") + "/.config/omarchy/google-translate.settings.json"

  // The key the user asked for, for the tooltip. The overlay holds the key
  // that is actually bound, which can differ when the preferred one was
  // already taken when this was written.
  property string hotkey: HK.DEFAULT_HOTKEY
  property bool hotkeyEnabled: true

  readonly property string tooltip: hotkeyEnabled
    ? "Google Translate · " + HK.pretty(hotkey)
    : "Google Translate · hotkey off"

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Component.onCompleted: settingsFile.reload()

  function applySettings(text) {
    var s = HK.parseSettings(text)
    root.hotkey = s.hotkey
    root.hotkeyEnabled = s.enabled
  }

  // capture.sh takes the selection before the overlay grabs the keyboard, then
  // toggles the overlay — the same path the hotkey runs, clicked instead.
  function translate() {
    if (!bar) return
    bar.run("bash " + Util.shellQuote(pluginDir + "/capture.sh"))
  }

  function hideIcon() {
    if (!bar) return
    bar.run("bash " + Util.shellQuote(pluginDir + "/bar-icon.sh") + " disable")
  }

  FileView {
    id: settingsFile
    path: root.settingsPath
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onLoaded: root.applySettings(text())
    onLoadFailed: root.applySettings("")
    onFileChanged: reload()
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "\uf0e6" // nf-fa-globe; flat and legible at bar size, unlike U+F0279
    tooltipText: root.tooltip

    onPressed: function(b) {
      if (b === Qt.RightButton) root.hideIcon()
      else root.translate()
    }
  }
}
