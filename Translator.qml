import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import qs.Commons
import qs.Ui
import "." as Local

Item {
  id: root

  property string pluginBase: (Quickshell.env("HOME") || "/tmp") + "/.config/omarchy/plugins"
  property string pluginId: root.manifest && root.manifest.id ? root.manifest.id : "godofjoper.translate"
  property string pluginPath: pluginBase + "/" + pluginId
  property var shell: null
  property var manifest: null

  property bool opened: false
  property string inputText: ""
  property string translatedText: ""
  property string detectedLang: ""
  property bool translating: false
  property string errorMessage: ""
  property bool copyFlash: false

  readonly property int maxSelectionChars: 1048576
  readonly property int maxOutputChars: 1048576

  readonly property var commonLangs: [
    { code: "auto", name: "Auto" },
    { code: "en",    name: "English" },
    { code: "ru",    name: "Russian" },
    { code: "de",    name: "German" },
    { code: "fr",    name: "French" },
    { code: "es",    name: "Spanish" },
    { code: "ja",    name: "Japanese" },
    { code: "zh-CN", name: "Chinese" },
    { code: "ko",    name: "Korean" },
    { code: "pt",    name: "Portuguese" },
    { code: "it",    name: "Italian" },
    { code: "tr",    name: "Turkish" },
    { code: "ar",    name: "Arabic" },
    { code: "uk",    name: "Ukrainian" },
    { code: "pl",    name: "Polish" },
    { code: "nl",    name: "Dutch" },
    { code: "hi",    name: "Hindi" },
    { code: "th",    name: "Thai" },
    { code: "vi",    name: "Vietnamese" }
  ]

  property int sourceLangIndex: 0
  property int targetLangIndex: 2
  property string sourceLang: commonLangs[sourceLangIndex].code
  property string targetLang: commonLangs[targetLangIndex].code
  property bool languageMenuOpen: false
  property bool languageMenuIsSource: true

  property color background: Color.menu.background
  property color foreground: Color.menu.text
  property color border: Color.menu.border
  property var borderSpec: Border.surfaceSpec("menu", "border", border, Math.max(1, Style.space(2)))
  property color scrim: Color.menu.scrim
  property color selectedBackground: Color.menu.selectedBackground
  property color selectedText: Color.menu.selectedText
  readonly property int cornerRadius: Style.cornerRadius
  property string fontFamily: Style.font.menuFamily
  property int contentMargin: Style.spacing.panelPadding
  property int cardWidth: Math.min(Style.space(700), panel.width - Style.gapsOut * 2)
  property int cardHeight: Math.min(Style.space(500), panel.height - Style.gapsOut * 2)

  // Self-registers the default hotkey (SUPER + ALT + T) while the plugin is
  // loaded and unbinds it when the plugin is disabled or removed.
  Local.HotkeyService {
    id: hotkeyService
  }

  function open(payloadJson) {
    root.opened = true
    root.inputText = ""
    root.translatedText = ""
    root.errorMessage = ""
    root.copyFlash = false
    root.languageMenuOpen = false
    Qt.callLater(function() { inputEdit.forceActiveFocus() })
    selectionFile.reload()
  }

  function close() {
    root.opened = false
    root.languageMenuOpen = false
  }

  function dismiss() {
    close()
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide(root.pluginId)
  }

  function toggle() {
    if (root.opened) dismiss()
    else root.open("{}")
  }

  // IPC: omarchy-shell shell call godofjoper.translate setHotkey 'SUPER + SHIFT + G'
  function setHotkey(combo) {
    var err = hotkeyService.setHotkey(String(combo || ""))
    return err ? "error: " + err : "ok"
  }

  // IPC: omarchy-shell shell call godofjoper.translate setHotkeyEnabled false
  function setHotkeyEnabled(value) {
    hotkeyService.setEnabled(String(value) !== "false")
    return "ok"
  }

  // IPC: omarchy-shell shell call godofjoper.translate hotkeyStatus ''
  function hotkeyStatus() { return hotkeyService.summary }

  function cycleSourceLang(delta) {
    root.sourceLangIndex = (root.sourceLangIndex + delta + root.commonLangs.length) % root.commonLangs.length
    if (root.sourceLangIndex === root.targetLangIndex) {
      root.sourceLangIndex = (root.sourceLangIndex + delta + root.commonLangs.length) % root.commonLangs.length
    }
    triggerTranslation()
  }

  function cycleTargetLang(delta) {
    root.targetLangIndex = (root.targetLangIndex + delta + root.commonLangs.length) % root.commonLangs.length
    if (root.targetLangIndex === root.sourceLangIndex) {
      root.targetLangIndex = (root.targetLangIndex + delta + root.commonLangs.length) % root.commonLangs.length
    }
    triggerTranslation()
  }

  function swapLanguages() {
    if (root.sourceLang === "auto") return
    var tmpCode = root.sourceLang
    var tmpIndex = root.sourceLangIndex
    for (var i = 0; i < root.commonLangs.length; i++) {
      if (root.commonLangs[i].code === root.targetLang) {
        root.sourceLangIndex = i
        break
      }
    }
    for (var j = 0; j < root.commonLangs.length; j++) {
      if (root.commonLangs[j].code === tmpCode) {
        root.targetLangIndex = j
        break
      }
    }
    root.sourceLang = root.commonLangs[root.sourceLangIndex].code
    root.targetLang = root.commonLangs[root.targetLangIndex].code
    var oldTranslated = root.translatedText
    root.inputText = oldTranslated
    triggerTranslation()
  }

  function openLanguageMenu(isSource) {
    root.languageMenuIsSource = isSource
    root.languageMenuOpen = !root.languageMenuOpen || root.languageMenuIsSource !== isSource
  }

  function selectLanguage(code) {
    if (root.languageMenuIsSource) {
      for (var i = 0; i < root.commonLangs.length; i++) {
        if (root.commonLangs[i].code === code) {
          root.sourceLangIndex = i
          break
        }
      }
    } else {
      for (var j = 0; j < root.commonLangs.length; j++) {
        if (root.commonLangs[j].code === code) {
          root.targetLangIndex = j
          break
        }
      }
    }
    root.languageMenuOpen = false
    triggerTranslation()
  }

  function triggerTranslation() {
    root.sourceLang = root.commonLangs[root.sourceLangIndex].code
    root.targetLang = root.commonLangs[root.targetLangIndex].code
    if (!root.inputText || !root.inputText.trim()) {
      root.translatedText = ""
      root.errorMessage = ""
      return
    }
    translateDebounce.restart()
  }

  function copyTranslation() {
    if (!root.translatedText) return
    Quickshell.execDetached(["bash", "-c", "printf %s " + Util.shellQuote(root.translatedText) + " | wl-copy"])
    root.copyFlash = true
    copyFlashTimer.start()
  }

  onInputTextChanged: triggerTranslation()

  Timer {
    id: translateDebounce
    interval: 400
    repeat: false
    onTriggered: {
      if (!root.inputText || !root.inputText.trim()) {
        root.translating = false
        root.translatedText = ""
        root.errorMessage = ""
        return
      }
      if (root.inputText.length > root.maxSelectionChars) {
        root.translating = false
        root.translatedText = ""
        root.errorMessage = "Text too long"
        return
      }
      root.translating = true
      root.errorMessage = ""
      translateProc.lastOutput = ""
      translateProc.lastError = ""
      translateProc.outputTooLarge = false
      translateProc.stdinEnabled = true
      translateProc.pendingInput = root.inputText
      translateProc.command = [
        root.pluginPath + "/translate.py", "translate",
        "--from", root.sourceLang,
        "--to", root.targetLang
      ]
      translateProc.running = true
    }
  }

  Timer {
    id: copyFlashTimer
    interval: 800
    repeat: false
    onTriggered: root.copyFlash = false
  }

  FileView {
    id: selectionFile
    path: Quickshell.env("HOME") + "/.local/state/omarchy/translate-selection.txt"
    watchChanges: false
    atomicWrites: true
    printErrors: false
    onLoaded: {
      if (root.opened) {
        var text = text() || ""
        if (text.length <= root.maxSelectionChars) {
          root.inputText = text.trim()
        } else {
          root.inputText = ""
          root.errorMessage = "Selection too large"
        }
      }
    }
    onLoadFailed: {}
  }

  Process {
    id: translateProc
    property string lastOutput: ""
    property string lastError: ""
    property string pendingInput: ""
    property bool outputTooLarge: false
    property int maxOutputChars: 1048576
    stdinEnabled: false
    stdout: SplitParser {
      onRead: function(data) {
        if (!translateProc.outputTooLarge && translateProc.lastOutput.length < translateProc.maxOutputChars)
          translateProc.lastOutput += data
        else
          translateProc.outputTooLarge = true
      }
    }
    stderr: SplitParser {
      onRead: function(data) {
        if (translateProc.lastError.length < 4096) translateProc.lastError += data
      }
    }
    onStarted: translateProc.write(translateProc.pendingInput)
    onRunningChanged: {
      if (!running) {
        root.translating = false
        try {
          if (translateProc.outputTooLarge) {
            root.errorMessage = "Output too large"
            root.translatedText = ""
          } else {
            var result = JSON.parse(lastOutput)
            if (result.error) {
              root.errorMessage = result.error
              root.translatedText = ""
            } else {
              root.translatedText = result.translated || ""
              root.detectedLang = result.from_lang || ""
              root.errorMessage = ""
            }
          }
        } catch (e) {
          root.errorMessage = translateProc.lastError.trim() || "Parse error"
          root.translatedText = ""
        }
        lastOutput = ""
        lastError = ""
        outputTooLarge = false
      }
    }
  }

  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "omarchy-translate"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    Rectangle {
      anchors.fill: parent
      color: root.scrim
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.dismiss()
    }

    BorderSurface {
      id: card
      width: root.cardWidth
      height: root.cardHeight
      radius: root.cornerRadius
      anchors.centerIn: parent
      color: root.background
      borderSpec: root.borderSpec
      padding: root.contentMargin

      MouseArea { anchors.fill: parent; onClicked: {} }

      Item {
        id: keyCatcher
        anchors.fill: parent
        focus: false
      }

      Column {
        anchors.fill: parent
        anchors.topMargin: card.contentTopInset
        anchors.rightMargin: card.contentRightInset
        anchors.bottomMargin: card.contentBottomInset
        anchors.leftMargin: card.contentLeftInset
        spacing: Style.space(12)

        Row {
          width: parent.width
          spacing: Style.space(12)
          height: Style.space(36)

          property int gap: Style.space(12)
          property int swapWidth: Style.space(36)
          property bool swapVisible: root.sourceLang !== "auto"
          property real barWidth: (width - gap * (swapVisible ? 2 : 1) - (swapVisible ? swapWidth : 0)) / 2

          Rectangle {
            width: parent.barWidth
            height: parent.height
            radius: root.cornerRadius
            color: root.languageMenuOpen && root.languageMenuIsSource ? root.selectedBackground : Util.alpha(root.border, 0.15)

            Text {
              anchors.centerIn: parent
              text: root.sourceLang === "auto" ? "Auto Detect" : root.commonLangs[root.sourceLangIndex].name
              color: root.languageMenuOpen && root.languageMenuIsSource ? root.selectedText : root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              font.bold: !root.languageMenuOpen
              elide: Text.ElideRight
            }

            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: root.openLanguageMenu(true)
            }
          }

          Rectangle {
            width: parent.swapWidth
            height: parent.height
            radius: root.cornerRadius
            color: Util.alpha(root.border, 0.15)
            visible: parent.swapVisible

            Text {
              anchors.centerIn: parent
              text: "⇄"
              color: root.foreground
              font.pixelSize: Style.font.heading
            }

            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: root.swapLanguages()
            }
          }

          Rectangle {
            width: parent.barWidth
            height: parent.height
            radius: root.cornerRadius
            color: root.languageMenuOpen && !root.languageMenuIsSource ? root.selectedBackground : Util.alpha(root.border, 0.15)

            Text {
              anchors.centerIn: parent
              text: root.commonLangs[root.targetLangIndex].name
              color: root.languageMenuOpen && !root.languageMenuIsSource ? root.selectedText : root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              font.bold: !root.languageMenuOpen
              elide: Text.ElideRight
            }

            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: root.openLanguageMenu(false)
            }
          }
        }

        Item {
          width: parent.width
          height: parent.height - Style.space(36) - Style.space(12) - Style.space(32)
          visible: !root.languageMenuOpen

          Row {
            anchors.fill: parent
            spacing: Style.space(12)

            property int gap: Style.space(12)
            property int dividerWidth: Style.space(1)
            property real paneWidth: (width - gap * 2 - dividerWidth) / 2

            Rectangle {
              width: parent.paneWidth
              height: parent.height
              radius: root.cornerRadius
              color: Util.alpha(root.border, 0.08)
              border.width: 1
              border.color: Util.alpha(root.border, 0.2)

              Flickable {
                id: inputFlick
                anchors.fill: parent
                anchors.margins: Style.space(12)
                contentHeight: inputEdit.contentHeight
                clip: true
                flickableDirection: Flickable.VerticalFlick

                Text {
                  width: inputFlick.width
                  text: "Type or paste text…"
                  color: Util.alpha(root.foreground, 0.4)
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.title
                  wrapMode: Text.Wrap
                  textFormat: Text.PlainText
                  visible: !root.inputText
                }

                TextEdit {
                  id: inputEdit
                  z: 1
                  width: inputFlick.width
                  text: root.inputText
                  color: root.foreground
                  selectedTextColor: root.selectedText
                  selectionColor: root.selectedBackground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.title
                  wrapMode: TextEdit.Wrap
                  textFormat: TextEdit.PlainText
                  selectByMouse: true
                  selectByKeyboard: true
                  activeFocusOnTab: true
                  onTextChanged: root.inputText = text

                  Keys.priority: Keys.BeforeItem
                  Keys.onPressed: function(event) {
                    if (root.languageMenuOpen) {
                      if (event.key === Qt.Key_Escape) {
                        root.languageMenuOpen = false
                        event.accepted = true
                      } else if (event.key === Qt.Key_Up) {
                        langMenuList.decrementCurrentIndex()
                        event.accepted = true
                      } else if (event.key === Qt.Key_Down) {
                        langMenuList.incrementCurrentIndex()
                        event.accepted = true
                      } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                        var idx = langMenuList.currentIndex
                        if (idx >= 0 && idx < langMenuList.count) {
                          var lang = langMenuList.model.get(idx)
                          root.selectLanguage(lang.code)
                        }
                        event.accepted = true
                      }
                      return
                    }

                    if (event.key === Qt.Key_Escape) {
                      root.dismiss()
                      event.accepted = true
                    } else if (event.key === Qt.Key_Tab) {
                      root.swapLanguages()
                      event.accepted = true
                    } else if (event.key === Qt.Key_Up && (event.modifiers & Qt.AltModifier)) {
                      root.cycleSourceLang(-1)
                      event.accepted = true
                    } else if (event.key === Qt.Key_Down && (event.modifiers & Qt.AltModifier)) {
                      root.cycleSourceLang(1)
                      event.accepted = true
                    } else if ((event.key === Qt.Key_Up || event.key === Qt.Key_Down) &&
                               !(event.modifiers & (Qt.ShiftModifier | Qt.ControlModifier))) {
                      if (!root.inputText) {
                        if (event.key === Qt.Key_Up) root.cycleTargetLang(-1)
                        else root.cycleTargetLang(1)
                        event.accepted = true
                      }
                    } else if (event.key === Qt.Key_PageUp) {
                      root.cycleTargetLang(-1)
                      event.accepted = true
                    } else if (event.key === Qt.Key_PageDown) {
                      root.cycleTargetLang(1)
                      event.accepted = true
                    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                      root.copyTranslation()
                      event.accepted = true
                    }
                  }
                }
              }

              Rectangle {
                anchors.bottom: parent.bottom
                anchors.right: parent.right
                anchors.margins: Style.space(8)
                width: copyIndicator.width + Style.space(16)
                height: copyIndicator.height + Style.space(8)
                radius: root.cornerRadius
                color: root.copyFlash ? root.selectedBackground : "transparent"
                visible: root.copyFlash

                Text {
                  id: copyIndicator
                  anchors.centerIn: parent
                  text: "Copied!"
                  color: root.selectedText
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
              }
            }

            Rectangle {
              width: parent.dividerWidth
              height: parent.height
              color: Util.alpha(root.border, 0.2)
            }

            Rectangle {
              width: parent.paneWidth
              height: parent.height
              radius: root.cornerRadius
              color: Util.alpha(root.border, 0.08)
              border.width: 1
              border.color: Util.alpha(root.border, 0.2)

              Flickable {
                id: outputFlick
                anchors.fill: parent
                anchors.margins: Style.space(12)
                contentHeight: outputColumn.height
                clip: true
                flickableDirection: Flickable.VerticalFlick

                Column {
                  id: outputColumn
                  width: outputFlick.width
                  spacing: Style.space(8)

                  TextEdit {
                    id: outputEdit
                    width: parent.width
                    readOnly: true
                    text: {
                      if (root.translating) return "Translating…"
                      if (root.errorMessage) return "Error: " + root.errorMessage
                      if (root.translatedText) return root.translatedText
                      return "Translation will appear here"
                    }
                    color: {
                      if (root.errorMessage) return "#ff6b6b"
                      if (root.translatedText) return root.foreground
                      return Util.alpha(root.foreground, 0.4)
                    }
                    selectedTextColor: root.selectedText
                    selectionColor: root.selectedBackground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.title
                    wrapMode: TextEdit.Wrap
                    textFormat: TextEdit.PlainText
                    selectByMouse: true
                    selectByKeyboard: true

                    Keys.priority: Keys.BeforeItem
                    Keys.onPressed: function(event) {
                      if (root.languageMenuOpen) return
                      if (event.key === Qt.Key_Escape) {
                        root.dismiss()
                        event.accepted = true
                      } else if (event.key === Qt.Key_Tab) {
                        root.swapLanguages()
                        event.accepted = true
                      } else if (event.key === Qt.Key_Up && (event.modifiers & Qt.AltModifier)) {
                        root.cycleSourceLang(-1)
                        event.accepted = true
                      } else if (event.key === Qt.Key_Down && (event.modifiers & Qt.AltModifier)) {
                        root.cycleSourceLang(1)
                        event.accepted = true
                      } else if (event.key === Qt.Key_PageUp) {
                        root.cycleTargetLang(-1)
                        event.accepted = true
                      } else if (event.key === Qt.Key_PageDown) {
                        root.cycleTargetLang(1)
                        event.accepted = true
                      } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                        root.copyTranslation()
                        event.accepted = true
                      }
                    }
                  }

                  Text {
                    width: parent.width
                    visible: root.detectedLang && root.detectedLang !== root.sourceLang && root.sourceLang === "auto"
                    text: "Detected: " + (function() {
                      for (var i = 0; i < root.commonLangs.length; i++) {
                        if (root.commonLangs[i].code === root.detectedLang) return root.commonLangs[i].name
                      }
                      return root.detectedLang
                    })()
                    color: Util.alpha(root.foreground, 0.4)
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    textFormat: Text.PlainText
                  }
                }
              }
            }
          }
        }

        Rectangle {
          width: parent.width
          height: parent.height - Style.space(36) - Style.space(12) - Style.space(32)
          radius: root.cornerRadius
          color: Util.alpha(root.border, 0.08)
          border.width: 1
          border.color: Util.alpha(root.border, 0.2)
          visible: root.languageMenuOpen

          ListView {
            id: langMenuList
            anchors.fill: parent
            anchors.margins: Style.space(8)
            clip: true
            model: ListModel {}
            currentIndex: 0
            highlight: Rectangle {
              radius: root.cornerRadius
              color: root.selectedBackground
            }
            highlightMoveDuration: 0

            delegate: Rectangle {
              width: langMenuList.width
              height: Style.space(32)
              radius: root.cornerRadius
              color: "transparent"

              Text {
                anchors.left: parent.left
                anchors.leftMargin: Style.space(12)
                anchors.verticalCenter: parent.verticalCenter
                text: name
                color: index === langMenuList.currentIndex ? root.selectedText : root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
              }

              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onContainsMouseChanged: if (containsMouse) langMenuList.currentIndex = index
                onClicked: root.selectLanguage(code)
              }
            }
          }
        }

        Row {
          width: parent.width
          height: Style.space(32)
          spacing: Style.space(8)
          visible: !root.languageMenuOpen

          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "Open: " + (hotkeyService.prettyActive || "-") + "   Tab: swap  Alt+↑↓: source  PgUp/PgDn: target  Enter: copy all  Ctrl+C: copy sel  Esc: close"
            color: Util.alpha(root.foreground, 0.35)
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            textFormat: Text.PlainText
          }
        }
      }
    }

    Component.onCompleted: {
      var langs = root.commonLangs
      for (var i = 0; i < langs.length; i++) {
        langMenuList.model.append({ code: langs[i].code, name: langs[i].name })
      }
    }
  }
}
