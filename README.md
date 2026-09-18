# Google Translate

An Omarchy overlay that translates selected text with a hotkey, powered by
Google Translate.

## Features

- Select any text and press the hotkey — the selection is translated instantly
- Falls back to the clipboard, or just type into the source pane
- Auto-detect language, source/target language switching and swap
- Both panes support text selection: copy the whole translation with `Enter`,
  or select a part and copy it with `Ctrl+C` (the output pane is read-only)

## Requirements

- Omarchy with the Quattro shell
- `python3` (any recent 3.x; uses the standard library only)
- `wl-clipboard` for capturing the current selection (`wl-paste`)
- Network access to `translate.google.com`

## Install

```sh
omarchy plugin add https://github.com/GodofJoper/omarchy-google-translate.git --enable
```

## Configure

The overlay is summoned with a hotkey, but a plugin never touches your
keybindings — add one line to `~/.config/hypr/bindings.lua`:

```lua
o.bind("SUPER + ALT + T", "Translate", "~/.config/omarchy/plugins/godofjoper.translate/capture.sh")
```

Then reload Hyprland with `hyprctl reload`.

The `capture.sh` script captures the current selection *before* the overlay
takes keyboard focus (the focus steal makes the source app release the primary
selection), then toggles the overlay. Priority: highlighted text → clipboard →
empty.

## Usage

Select text anywhere and press the hotkey. The overlay opens with the text
ready and translates it automatically. If nothing was selected, an empty source
field is ready for manual typing.

| Key | Action |
| --- | --- |
| `Esc` | Close |
| `Tab` | Swap source and target language |
| `Alt+↑` / `Alt+↓` | Change source language |
| `PgUp` / `PgDn` | Change target language |
| `↑` / `↓` | Move the cursor / extend selection; with an empty source field they cycle the target language |
| `Enter` | Copy the whole translation |
| `Ctrl+C` | Copy the selected text in the focused pane |
| `Ctrl+A`, `Ctrl+Shift+arrows`, mouse drag | Select text in either pane (the output pane is read-only) |

## Remove

```sh
omarchy plugin remove godofjoper.translate
```

Then remove the keybinding line from `bindings.lua`. The state file
`~/.local/state/omarchy/translate-selection.txt` (the last captured text) is left
behind and can be deleted.

## Privacy

The selected or pasted text is sent to `translate.google.com` to produce a
translation — the same as pasting it into Google Translate in a browser.
Nothing else leaves your machine: no account, no API key, no analytics.

This is an independent, unofficial project and is not affiliated with or
endorsed by Google.