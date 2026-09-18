.pragma library

// Pure-JS hotkey logic for Google Translate. No Qt dependencies so it can be
// unit-tested with node and imported from QML with `.import`.
//
// The plugin registers its own Hyprland keybinding through configure-hotkey.
// sh — an idempotent edit of ~/.config/hypr/bindings.lua plus a reload — so a
// fresh install works without the user touching any config. This file decides
// which key to use and reads `hyprctl binds` to see what is taken.

// Description stamped on every bind we register; it is how we recognise our
// own binds in `hyprctl binds` and never touch anyone else's.
var OWNER = "Google Translate"
var DEFAULT_HOTKEY = "SUPER + ALT + T"

// Tried in order when the preferred key is taken. SUPER + ALT + T stays first
// so a clean Omarchy install lands there. The others were checked against
// Omarchy's default bindings so nothing here is owned by Omarchy itself.
var CANDIDATES = [
  "SUPER + ALT + T",
  "SUPER + SHIFT + T",
  "SUPER + ALT + G"
]

// Hyprland modmask bits.
var MODS = { SUPER: 64, CTRL: 4, ALT: 8, SHIFT: 1 }
var MOD_ORDER = ["SUPER", "CTRL", "ALT", "SHIFT"]
var MOD_ALIASES = {
  SUPER: "SUPER", WIN: "SUPER", META: "SUPER", MOD4: "SUPER", CMD: "SUPER", LOGO: "SUPER",
  CTRL: "CTRL", CONTROL: "CTRL",
  ALT: "ALT", MOD1: "ALT", OPTION: "ALT",
  SHIFT: "SHIFT"
}
var KEY_ALIASES = { ENTER: "RETURN", ESC: "ESCAPE", DEL: "DELETE", PGUP: "PRIOR", PAGEUP: "PRIOR", PGDN: "NEXT", PAGEDOWN: "NEXT" }
var NAMED_KEYS = {
  SPACE: 1, RETURN: 1, TAB: 1, BACKSPACE: 1, DELETE: 1, INSERT: 1, HOME: 1, END: 1, PRIOR: 1, NEXT: 1,
  UP: 1, DOWN: 1, LEFT: 1, RIGHT: 1, ESCAPE: 1, PRINT: 1,
  COMMA: 1, PERIOD: 1, SLASH: 1, SEMICOLON: 1, APOSTROPHE: 1, MINUS: 1, EQUAL: 1, GRAVE: 1,
  BRACKETLEFT: 1, BRACKETRIGHT: 1, BACKSLASH: 1
}
var KEY_LABELS = { PRIOR: "PageUp", NEXT: "PageDown", GRAVE: "`", COMMA: ",", PERIOD: ".", SLASH: "/", SEMICOLON: ";", APOSTROPHE: "'", MINUS: "-", EQUAL: "=", BRACKETLEFT: "[", BRACKETRIGHT: "]", BACKSLASH: "\\" }

function trim(s) { return String(s === undefined || s === null ? "" : s).replace(/^\s+|\s+$/g, "") }

// "super+alt+b" → { mods: 72, key: "B", combo: "SUPER + ALT + B", error: "" }
function parseCombo(input) {
  var tokens = trim(input).split("+").map(trim).filter(function(t) { return t.length > 0 })
  if (tokens.length === 0) return { mods: 0, key: "", combo: "", error: "Type a combination like SUPER + ALT + T" }
  var mods = 0
  var key = ""
  for (var i = 0; i < tokens.length; i++) {
    var tok = tokens[i]
    var up = tok.toUpperCase()
    if (MOD_ALIASES[up]) { mods |= MODS[MOD_ALIASES[up]]; continue }
    if (key) return { mods: mods, key: "", combo: "", error: "Only one key can follow the modifiers" }
    var k = canonicalKey(tok)
    if (!k) return { mods: mods, key: "", combo: "", error: "\u201C" + tok + "\u201D is not a key name" }
    key = k
  }
  if (!key) return { mods: mods, key: "", combo: "", error: "Add a key after the modifiers, like SUPER + ALT + T" }
  var plain = /^[A-Z0-9]$/.test(key) || NAMED_KEYS[key] === 1
  if (mods === 0 && plain) return { mods: 0, key: key, combo: "", error: "Add a modifier such as SUPER, or typing that key anywhere would open the translator" }
  return { mods: mods, key: key, combo: formatCombo(mods, key), error: "" }
}

function canonicalKey(tok) {
  var up = tok.toUpperCase()
  if (KEY_ALIASES[up]) up = KEY_ALIASES[up]
  if (/^[A-Z0-9]$/.test(up)) return up
  if (/^F([1-9]|1[0-9]|2[0-4])$/.test(up)) return up
  if (NAMED_KEYS[up] === 1) return up
  if (/^code:\d+$/i.test(tok)) return tok.toLowerCase()
  if (/^XF86[A-Za-z0-9]+$/.test(tok)) return tok
  return ""
}

function formatCombo(mods, key) {
  var parts = []
  for (var i = 0; i < MOD_ORDER.length; i++)
    if (mods & MODS[MOD_ORDER[i]]) parts.push(MOD_ORDER[i])
  parts.push(key)
  return parts.join(" + ")
}

// "SUPER + ALT + T" → "Super+Alt+T", for tooltips and labels.
function pretty(combo) {
  var p = parseCombo(combo)
  if (p.error && !p.key) return String(combo || "")
  var parts = []
  for (var i = 0; i < MOD_ORDER.length; i++)
    if (p.mods & MODS[MOD_ORDER[i]]) parts.push(MOD_ORDER[i].charAt(0) + MOD_ORDER[i].slice(1).toLowerCase())
  var k = p.key
  if (KEY_LABELS[k]) k = KEY_LABELS[k]
  else if (NAMED_KEYS[k] === 1) k = k.charAt(0) + k.slice(1).toLowerCase()
  parts.push(k)
  return parts.join("+")
}

// Parses the plain-text output of `hyprctl binds` (the JSON form is broken in
// some Hyprland releases). Each block starts with the bind flavour on its own
// line and continues with tab-indented "field: value" lines.
function parseBinds(text) {
  var out = []
  var blocks = String(text || "").split(/\n\s*\n/)
  for (var i = 0; i < blocks.length; i++) {
    var lines = blocks[i].split("\n")
    var b = null
    for (var j = 0; j < lines.length; j++) {
      var line = lines[j]
      if (!line.trim()) continue
      var m = /^\s+([a-zA-Z]+):\s?(.*)$/.exec(line)
      if (m && b) { b[m[1]] = m[2] }
      else if (!/^\s/.test(line)) {
        if (b) out.push(finishBind(b))
        b = { kind: line.trim() }
      }
    }
    if (b) out.push(finishBind(b))
  }
  return out
}

function finishBind(b) {
  return {
    kind: b.kind || "",
    modmask: parseInt(b.modmask || "0", 10) || 0,
    submap: b.submap || "",
    key: b.key || "",
    keycode: parseInt(b.keycode || "0", 10) || 0,
    description: b.description || "",
    dispatcher: b.dispatcher || "",
    arg: b.arg || ""
  }
}

function isOurs(bind) { return bind.description === OWNER }

function bindsAt(binds, combo) {
  var p = parseCombo(combo)
  if (!p.combo) return []
  var code = /^code:(\d+)$/.exec(p.key)
  var out = []
  for (var i = 0; i < binds.length; i++) {
    var b = binds[i]
    if (b.submap) continue
    if (b.modmask !== p.mods) continue
    if (code ? b.keycode === parseInt(code[1], 10) : String(b.key).toUpperCase() === p.key) out.push(b)
  }
  return out
}

function ownerLabel(bind) {
  if (bind.description) return bind.description
  if (bind.dispatcher && bind.dispatcher !== "__lua") return bind.dispatcher + (bind.arg ? " " + bind.arg : "")
  return "another binding"
}

// { state: "free" | "ours" | "taken", owner: "" | "Browser" }
function status(binds, combo) {
  var at = bindsAt(binds || [], combo)
  var others = at.filter(function(b) { return !isOurs(b) })
  if (others.length) return { state: "taken", owner: ownerLabel(others[0]) }
  if (at.length) return { state: "ours", owner: "" }
  return { state: "free", owner: "" }
}

// Every combo currently holding one of our binds.
function ourCombos(binds) {
  var seen = {}
  var out = []
  for (var i = 0; i < (binds || []).length; i++) {
    var b = binds[i]
    if (!isOurs(b) || b.submap) continue
    var combo = formatCombo(b.modmask, b.keycode && !b.key ? "code:" + b.keycode : String(b.key).toUpperCase())
    if (!seen[combo]) { seen[combo] = true; out.push(combo) }
  }
  return out
}

// Picks the key to register: the preferred one, else the first free
// candidate. `preferredOwner` names what holds the preferred key when we had
// to fall back; `target` is "" when everything is taken.
function resolve(binds, preferred) {
  var p = parseCombo(preferred)
  var first = p.combo || DEFAULT_HOTKEY
  var list = [first]
  for (var i = 0; i < CANDIDATES.length; i++)
    if (list.indexOf(CANDIDATES[i]) === -1) list.push(CANDIDATES[i])
  var preferredOwner = ""
  for (var j = 0; j < list.length; j++) {
    var st = status(binds, list[j])
    if (st.state !== "taken") return { target: list[j], preferred: first, preferredOwner: preferredOwner, fallback: j > 0 }
    if (j === 0) preferredOwner = st.owner
  }
  return { target: "", preferred: first, preferredOwner: preferredOwner, fallback: true }
}

// Settings file: { "hotkey": "SUPER + ALT + T", "enabled": true, "noticed": "..." }
function parseSettings(text) {
  var out = { hotkey: DEFAULT_HOTKEY, enabled: true, noticed: "" }
  var raw = null
  try { raw = JSON.parse(String(text || "")) } catch (e) { raw = null }
  if (!raw || typeof raw !== "object") return out
  if (typeof raw.hotkey === "string") {
    var p = parseCombo(raw.hotkey)
    if (p.combo) out.hotkey = p.combo
  }
  if (raw.enabled === false || raw.enabled === "false") out.enabled = false
  if (typeof raw.noticed === "string") out.noticed = raw.noticed
  return out
}

function serializeSettings(s) {
  return JSON.stringify({ hotkey: s.hotkey, enabled: s.enabled !== false, noticed: s.noticed || "" }, null, 2) + "\n"
}

// One line for tooltips: what key opens the translator right now, and why it
// is not the preferred one when it is not.
function summary(active, preferred, preferredOwner, enabled) {
  if (!enabled) return "Hotkey off"
  if (!active) return "No free hotkey; open it via omarchy-shell shell toggle godofjoper.translate"
  if (active === preferred || !preferredOwner) return pretty(active)
  return pretty(active) + " (" + pretty(preferred) + " is used by " + preferredOwner + ")"
}