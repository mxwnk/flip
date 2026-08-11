<p align="center">
  <img src="docs/icon.png" width="120" alt="">
</p>

<h1 align="center">Flip</h1>

<p align="center">
  A window switcher for macOS that gets out of the way.<br>
  Hold Option, tap Tab. Let go before you can see it and it never draws at all.
</p>

<p align="center">
  <a href="https://mxwnk.github.io/flip/"><strong>mxwnk.github.io/flip</strong></a>
</p>

<p align="center">
  <a href="https://github.com/mxwnk/flip/releases/latest"><img src="https://img.shields.io/github/v/release/mxwnk/flip?color=0a84ff&label=release" alt="Latest release"></a>
  <img src="https://img.shields.io/badge/macOS-14%2B-lightgrey" alt="macOS 14 or newer">
  <a href="LICENSE"><img src="https://img.shields.io/github/license/mxwnk/flip?color=lightgrey" alt="MIT licence"></a>
</p>

<p align="center">
  <img src="docs/demo.gif" width="820" alt="Switching windows, jumping to an application, and moving a window across the screen">
</p>

## Install

```sh
brew install --cask mxwnk/tap/flip
```

Or take the disk image from the [latest
release](https://github.com/mxwnk/flip/releases/latest) and drag Flip into
Applications.

Needs macOS 14 or newer.

## What it does

- **Switches windows, not applications.** Every window on the space, most recently
  used first, so two documents in the same app are two entries.
- **Stays out of the way.** Let go inside 150 ms and it switches without drawing
  anything at all.
- **One key per application.** `⌥ F` reaches the Finder out of the box; `⌥ S` for
  Spotify and `⌥ T` for the terminal are yours to add.
- **Moves and resizes windows** from the keyboard — halves, quarters, filling, and
  across to the other display.
- **Keyboard or mouse.** Hover or scroll to pick, click to confirm, if your hand
  is already there.
- **Brings minimised windows back.** Choosing one lifts it out of the Dock.
- **Closes windows from the grid.** `⌥⌫` on the one you were about to go and
  close anyway.

## Switching windows

| | |
| --- | --- |
| `⌥ Tab` | every window on the current space, most recently used first |
| `⌘ Tab` | the windows of whichever application is in front |
| `⌥ F` | jump straight to the Finder — one key per application, the rest yours to choose |
| `⌥` held, then a key | narrow the open grid to that application |
| arrows, `esc` | move the selection, or give up |
| `⌥⌫` | close the selected window; the grid stays up for the next one |
| the mouse | hover to select, wheel to step, click to confirm; click beside the grid to give up |
| let go of `⌥` | focus what is selected, out of the Dock if it was minimised |

Add `⇧` to any of those to go backwards.

<p align="center">
  <img src="docs/overlay.png" width="820" alt="The Flip overlay: a grid of window thumbnails, one selected">
</p>

## Moving windows

| | |
| --- | --- |
| `⌃⌥←` `⌃⌥→` | left or right half |
| `⌃⌥↑` `⌃⌥↓` | top or bottom half |
| `⌃⌥U` `⌃⌥I` `⌃⌥J` `⌃⌥K` | the four quarters |
| `⌃⌥↩` | fill the screen, or put it back if it already fills |
| `⇧⌥←` `⇧⌥→` | previous or next display, keeping the window's place on it |

Everything stops at the menu bar and the Dock. Filling is a toggle: press it on a
window that already fills and it goes back where it was.

The display moves take the same arrows as the halves, so they need a modifier of
their own — `⇧⌥` to begin with, or `⌃⌥⌘` if that suits your other shortcuts
better. Settings › Windows. The halves and quarters are fixed: every remaining
modifier is already spoken for with the arrow keys.

## Settings

**Settings…** in the menu bar, or `⌘,`. Every change applies as you make it.

- **General** — start at login, the two hotkeys, which display the grid opens on,
  how long Option must be held before it does, thumbnails or plain icons, windows
  from every space, and the update check.
- **Shortcuts** — one key per application. The editor warns when a key would
  shadow a character you need to type.
- **Windows** — the keys above, listed so you can find them without this page.
- **Excluded** — applications kept out of the grid. A key bound directly to one
  still reaches it.

Along the bottom sits a picture of your keyboard with the keys of whichever tab
you are on lit up, and the modifiers spelled out — `⌃` is labelled *control*, `⌥`
is *option*. The letters come from the layout you type on and the shape from the
keyboard you type on, which are not the same question: a German layout on an ANSI
board has no key between the left shift and Z, and Flip asks macOS which it is.
Where command sits in the bottom row is the one thing macOS cannot answer, so
there is a small switch under the picture for it.

**Pause** in the menu bar hands `⌘ Tab` back to macOS for as long as a screen
share lasts.

## From the command line

Homebrew puts a `flip` command on your PATH; with the disk image, `make link`
does the same.

```sh
flip list                    # every window Flip knows, as JSON
flip focus 27461             # bring one forward
flip arrange left-half       # move the focused window
flip switch                  # open the switcher
flip pause                   # hand ⌘Tab back to macOS, then `flip resume`
```

It drives the running application over a socket rather than doing the work
itself, so it sees exactly the windows the switcher sees. That makes the missing
title search a script:

```sh
flip focus "$(flip list | jq 'map(select(.title | test("invoice"; "i")))[0].id')"
```

## Questions

**Why does a window switcher want Screen Recording?** Only for the thumbnails.
Turn them off in Settings and Flip shows application icons instead — and stops
asking for it.

**macOS says the disk image "cannot be opened because Apple cannot check it for
malicious software".** Flip is signed with its own certificate rather than
notarised through Apple's paid programme, and macOS quarantines anything a browser
downloads. Homebrew clears that for you — this only happens with the disk image.
Either:

1. Double-click the disk image and dismiss the warning.
2. Open **System Settings › Privacy & Security** and scroll down to *Security*.
3. Next to *"Flip-x.y.z.dmg" was blocked to protect your Mac*, click **Open
   Anyway**, then confirm.

Or clear it in one line, which also spares the copied app the same warning on its
first launch:

```sh
xattr -d com.apple.quarantine ~/Downloads/Flip-*.dmg
```

Control-clicking and choosing Open no longer works for this on macOS 26.

**Do I have to grant the permissions again after every update?** No. The signature
is pinned to the same certificate on every release, and the pipeline refuses to
publish one where it has drifted.

**Where do my settings live?** As readable JSON in `~/Library/Application
Support/Flip/`. Edits to `bindings.json` are picked up while Flip runs; changes to
`settings.json` need a restart.

**Something is wrong and I want to report it.** **Copy Diagnostics** in the menu
puts the version, both permissions, every setting and Flip's recent log on the
clipboard — enough for an issue without opening a terminal.

## Contributing

Open work and known gaps live in
[issues](https://github.com/mxwnk/flip/issues). Building, testing and releasing
are in [docs/development.md](docs/development.md); what changed in each release is
in [CHANGELOG.md](CHANGELOG.md).

## License

MIT. See [LICENSE](LICENSE).
