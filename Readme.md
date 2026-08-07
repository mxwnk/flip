<p align="center">
  <img src="docs/icon.png" width="120" alt="">
</p>

<h1 align="center">Flip</h1>

<p align="center">
  A window switcher for macOS that gets out of the way.<br>
  Hold Option, tap Tab. Let go before you can see it and it never draws at all.
</p>

<p align="center">
  <img src="docs/demo.gif" width="820" alt="Switching windows, jumping to an application, and moving a window across the screen">
</p>

## Install

```sh
brew install --cask mxwnk/flip/flip
```

Or download the disk image from the [latest
release](https://github.com/mxwnk/flip/releases/latest) and drag Flip into
Applications.

Flip is signed with its own certificate rather than notarised. Homebrew takes care
of that; with the disk image, macOS blocks the first launch and you have to allow
Flip once under System Settings › Privacy & Security.

Needs macOS 14 or newer. Flip asks for Accessibility on first run, and for Screen
Recording only if you want thumbnails rather than icons.

## Switching windows

| | |
| --- | --- |
| `⌥ Tab` | every window on the current space, most recently used first |
| `⌘ Tab` | the windows of whichever application is in front |
| `⌥ S` | jump straight to Spotify — one key per application, yours to choose |
| `⌥` held, then a key | narrow the open grid to that application |
| arrows, `esc` | move the selection, or give up |
| the mouse | hover to select, click to confirm; click beside the grid to give up |
| let go of `⌥` | focus what is selected, out of the Dock if it was minimised |

Add `⇧` to any of those to go backwards. Let go within 150 ms and Flip switches
without ever drawing the grid.

The mouse only takes over once you actually move it, so a grid that opens under a
resting pointer still does what the keyboard told it to.

By default the grid holds the space you are on. Settings › General widens it to
every space; choosing a window there switches to it. Flip learns a space's windows
the first time you visit it, because accessibility only ever admits to the windows
in front of you.

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

Everything is measured against the visible frame, so filling the screen stops at
the menu bar and the Dock. Filling is a toggle: press it on a window that already
fills and it goes back where it was, and on a window in macOS's own full screen it
leaves full screen.

The corners are `u i j k` rather than the vim keys because those four sit as a
square on a German keyboard too, which `y u h j` does not.

## Settings

**Settings…** in the menu bar, or `⌘,`. Every change applies as you make it.

- **General** — whether Flip starts at login, the two hotkeys, how long Option
  must be held before the grid appears, thumbnails or plain icons, whether to list
  windows from every space, and whether to check for updates.
- **Shortcuts** — one key per application. The editor warns when a key would
  shadow a character you need to type.
- **Windows** — the keys above, listed so they can be found without this file.
- **Excluded** — applications kept out of the grid. A key bound directly to one
  still reaches it.

Flip asks GitHub once a day whether a newer release exists and says so in the
menu. It never downloads or installs anything — updating is `brew upgrade --cask
flip`, or the disk image from the release it points at. That is the only request
Flip ever makes, and it can be turned off.

**Pause** hands `⌘ Tab` back to macOS for as long as a screen share lasts.
**About Flip** has the version and the licence, and **Copy Diagnostics** puts the
version, both grants, every setting and Flip's recent log on the clipboard — enough
to report a problem without opening a terminal.

Everything is readable JSON in `~/Library/Application Support/Flip/`, and edits
made by hand are picked up while Flip runs.

## Why it is quick

Nothing is asked for at the moment you press the key.

The window list is not queried but **maintained** — `AXObserver` notifications keep
it current on a thread of its own, so opening the grid costs one lock and one
window server call. The **event tap owns a thread and a runloop**, because macOS
quietly disables a tap whose callback misses its deadline. The **panel is built
once at launch** and only ordered in and out, and thumbnails are captured ahead of
time: at startup, and then for each window as it loses focus, which is when its
contents are final and nobody is waiting.

Measured with five windows open on a two-monitor machine:

| | |
| --- | --- |
| Opening the grid, thumbnails already there | **1.5–6 ms** |
| Resolving the window list | ~1 ms, no accessibility calls |
| One capture | 67 ms for the first, ~8 ms for each after |

## Building it yourself

```sh
make cert       # once, interactive: creates the signing identity
make run        # build, sign, install to ~/Applications, launch
make test       # 78 unit tests
make logs       # follow along; almost everything interesting is logged
```

SwiftPM compiles and the Makefile assembles the bundle, so Xcode is needed only
for the tests. Nothing is ever started straight from a shell: that would make the
terminal the responsible process for TCC and attribute the privacy grants to it
rather than to Flip.

`make cert` is not ceremony. TCC keys a privacy grant to the app's designated
requirement, and for an ad-hoc signature that requirement contains a hash that
changes on every build — Accessibility and Screen Recording would have to be
granted again after every install. Signing against a certificate pins the
requirement to the bundle identifier instead. `make verify` checks it against
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
`HOMEBREW_TAP_DEPLOY_KEY`, which can write to the tap and to nothing else. Without
it the release still goes out and the cask stays where it was, with a warning in
the run.

## Contributing

Conventions and the invariants that break silently are in
[AGENTS.md](AGENTS.md).

## License

MIT. See [LICENSE](LICENSE).
