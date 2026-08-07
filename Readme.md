<p align="center">
  <img src="docs/icon.png" width="120" alt="">
</p>

<h1 align="center">Flip</h1>

<p align="center">
  A window switcher for macOS that gets out of the way.<br>
  Hold Option, tap Tab. Let go before you can see it and it never draws at all.
</p>

<p align="center">
  <img src="docs/overlay.png" width="820" alt="The Flip overlay: a grid of window thumbnails, one selected">
</p>

<p align="center">
  <img src="docs/demo.gif" width="820" alt="Switching windows, jumping to an application, and moving a window across the screen">
</p>

## Keys

| | |
| --- | --- |
| `⌥ Tab` | every window on the current space, most recently used first |
| `⌘ Tab` | the windows of whichever application is in front |
| `⌥ S` | jump straight to Spotify — one key per application, yours to choose |
| `⌥` held, then a key | narrow the open grid to that application |
| arrows, `esc` | move the selection, or give up |
| let go of `⌥` | focus what is selected, out of the Dock if it was minimised |

Add `⇧` to any of those to go backwards.

## Moving windows

| | |
| --- | --- |
| `⌃⌥←` `⌃⌥→` | left or right half |
| `⌃⌥↑` `⌃⌥↓` | top or bottom half |
| `⌃⌥U` `⌃⌥I` `⌃⌥J` `⌃⌥K` | the four quarters |
| `⌃⌥↩` | fill the screen |
| `⇧⌥←` `⇧⌥→` | previous or next display, keeping the window's place on it |

Everything is measured against the visible frame, so filling the screen stops at
the menu bar and the Dock.

Two modifiers is not fussiness: every single one is already spoken for with the
arrow keys. Option moves by word, Control switches spaces, fn is Home and End, and
Command is beginning and end of line in every text field there is.

Moving between displays takes `⇧⌥` and the arrows, which macOS otherwise uses to
extend a selection by word. A deliberate trade.

Corners take letters because four corners need four keys and arrows only offer two
axes. `u i j k` sit as a square on the keyboard; the obvious vim choice does not —
`y u / h j` looks square on a US layout but types `z u / h j` on a German one,
which would put the top left corner on the wrong key.

`fn` is ignored throughout. Apple keyboards set it for whole groups of keys — the
F-row and the arrows both carry it — so treating it as meaningful would mean no
binding on either ever matched a real keypress.

## Why it is quick

Nothing is asked for at the moment you press the key.

The window list is not queried but **maintained** — `AXObserver` notifications keep
it current on a thread of its own, with a half-second messaging timeout per
application, so an unresponsive app becomes a missing window rather than a frozen
switcher. Opening the grid costs one lock and one window server call.

The **event tap owns a thread and a runloop**. macOS quietly disables a tap whose
callback misses its deadline, and the main thread is where rendering and window
server round trips live. The callback itself compares a keycode.

The **panel is built once at launch** and only ordered in and out. Thumbnails are
captured through ScreenCaptureKit ahead of time — at startup, and then for each
window as it loses focus, which is when its contents are final and nobody is
waiting.

Measured with five windows open on a two-monitor machine:

| | |
| --- | --- |
| Opening the grid, thumbnails already there | **1.5–6 ms** |
| Resolving the window list | ~1 ms, no accessibility calls |
| One capture | 67 ms for the first, ~8 ms for each after |

## Settings

**Settings…** in the menu bar, or `⌘,`. Every change applies as you make it.

**General** — the two hotkeys, how long Option must be held before the grid
appears, thumbnails or plain icons, and whether Flip starts at login. Turning
thumbnails off removes the Screen Recording requirement entirely rather than
merely hiding the images.

**Shortcuts** — one key per application. The editor warns when a key would shadow
a character you need: on a German layout every alphanumeric key produces something
with Option, but only nine produce printable ASCII — `[ ] { } | @ ~ ' .` — and
those are the ones worth protecting.

**Windows** — the fixed keys for moving and resizing, listed so they can be found
without this file.

**Excluded** — applications kept out of the grid. A key bound directly to one
still reaches it.

Both live as readable JSON in `~/Library/Application Support/Flip/`, and edits
made by hand are picked up while Flip runs.

**Pause** in the menu bar disables the event tap itself, so macOS gets `⌘ Tab`
back for as long as a screen share lasts. It is not remembered across restarts.

## Install

```sh
brew install --cask mxwnk/flip/flip
```

Flip is signed with its own certificate rather than notarised, so Gatekeeper
would otherwise block the first launch. The cask clears the quarantine flag for
you; a disk image downloaded [from the
releases](https://github.com/mxwnk/flip/releases) has to be allowed by hand in
System Settings › Privacy & Security.

## Requirements

macOS 14 or newer. Flip needs Accessibility to read windows and install the tap,
and Screen Recording only for thumbnails.

## Build

```sh
make cert       # once, interactive: creates the signing identity
make run        # build, sign, install to ~/Applications, launch
make test       # 59 unit tests
make logs       # follow along; almost everything interesting is logged
```

SwiftPM compiles and the Makefile assembles the bundle, so Xcode is needed only
for the tests.

Nothing is ever started straight from a shell: that would make the terminal the
responsible process for TCC and attribute the privacy grants to it rather than to
Flip.

### The signing identity

`make cert` creates a self-signed certificate and trusts it for code signing.
This is not ceremony. TCC keys a privacy grant to the app's designated
requirement, and for an ad-hoc signature that requirement contains the code
directory hash — which changes on every build. Accessibility and Screen Recording
would have to be granted again after every install.

Signing against a certificate pins the requirement to the bundle identifier and
the certificate instead. `make verify` checks it against
`resources/designated-requirement.txt`, and the release pipeline refuses to
package a build where it has drifted.

## Releasing

Every push builds and tests. Pushing a `v*` tag also signs, packages, publishes a
release with the disk image attached, and points the Homebrew cask at it:

```sh
git tag v0.2.0 && git push origin v0.2.0
```

The cask lives in [mxwnk/homebrew-flip](https://github.com/mxwnk/homebrew-flip)
and is never edited by hand. Bumping it uses a deploy key held as
`HOMEBREW_TAP_DEPLOY_KEY`, which can write to the tap and to nothing else.
Without it the release still goes out and the cask stays where it was, with a
warning in the run.

## Roadmap

Open ideas and known gaps live in [Roadmap.md](Roadmap.md); conventions for
working on this in [AGENTS.md](AGENTS.md).

## License

MIT. See [LICENSE](LICENSE).
