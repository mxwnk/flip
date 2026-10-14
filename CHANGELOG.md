# Changelog

The release pipeline publishes the section matching the tag as the release notes.

## 2.2.0

- 🌐 **Input source per app** – Flip switches the keyboard layout when an app comes to the front (Settings › Input Sources, `inputSources` in `config.json`)
- 🔒 **Secure Input explained** – when an app hides your keystrokes from Flip, a notice says why and turns green once it's fixed

## 2.1.0

- 🗂️ **Layouts** – place a whole set of windows with one key, from the menu bar or `flip layout <name>`
- 🧲 **Group windows by app** in the switcher; ⌘Tab still jumps back to your last window
- 🔐 **Secure input warning** – the menu bar names the app that hides your keystrokes from Flip
- 💥 A `flip` command that hung up early no longer shuts Flip down
- 🎯 Window actions move the window you are actually looking at
- 🐢 A hanging app no longer stalls Flip for seconds
- ✨ Thumbnails ready on first open, unreadable `config.json` edits are logged, less work per keystroke

## 2.0.0

- 📄 **One config file** – everything lives in `config.json`, grouped like the settings window, and hand edits apply live. Nothing carries over from 1.x
- ⌨️ All arrangement keys are in the file (`arrange.keys`)
- 🔤 Modifiers are written as arrays: `["option", "control"]`
- 📐 `flip arrange fill` is now `flip arrange maximize`
- 🔁 ⌘Tab opens the switcher, ⌥Tab narrows to the app in front (swap them back in Settings › Switcher)
- 🖥️ Moving to the next display follows how your displays are arranged
- ⌫ Closing a window works in both grids
- ✅ `flip permissions` reports both privacy grants

## 1.5.1

- 🛟 Flip starts even where a private accessibility symbol is missing, and says so
- 🔂 The login item no longer restarts a broken copy in a loop

## 1.5.0

- 🎛️ Choose the modifier for halves and quarters
- 🔑 App shortcuts get a leader of their own
- 🗄️ Settings has pages down the side, the switcher gets its own page
- ❌ Close a window from the grid with `⌥⌫`
- 🎙️ The shortcut editor records the key you press, F1–F12 included

## 1.4.0

- 💻 **Command line** – `flip list`, `focus`, `arrange`, `switch`, `pause`, `resume`
- ↩️ Return commits the selection
- 🌱 A fresh install ships one shortcut instead of fourteen

## 1.3.0

- 🖱️ Scroll through the grid
- 🐛 Five fixes from a full source review
- ⚠️ Warning when your leader is already taken
- 🔝 The settings window stays in front
- 🎚️ The display-move modifier is settable
- ⌨️ A keyboard picture in Settings shows which keys are in use

## 1.2.0

- 🍺 Shorter install: `brew install --cask mxwnk/tap/flip`
- 💿 The disk image shows its version
- 🛡️ How to get past Gatekeeper on macOS 26
- 🌍 Flip has a website: [mxwnk.github.io/flip](https://mxwnk.github.io/flip/)

## 1.1.0

- 🖥️ Choose the display the grid opens on
- 🪟 Stage Manager no longer ruins previews
- ⬇️ Down from the end of a short row goes somewhere
- 🖼️ Icons fill their tile

## 1.0.1

- 💿 A proper disk image window

## 1.0.0

- 🎉 First release: window switcher, one key per app, halves, quarters and display moves from the keyboard
