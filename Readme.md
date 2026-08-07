# Flip

A window and application switcher for macOS. Agent app, no Dock icon, driven by
a keyboard event tap.

Alt is the leader key:

| Keys | Effect |
| --- | --- |
| `Alt-Tab` | cycle every window on the current space |
| `Cmd-Tab` | cycle the windows of the frontmost application |
| `Alt-<letter>` | jump to a bound application, e.g. `Alt-S` for Spotify |
| `Alt` held, `<letter>` | narrow the open overlay to that application |
| release `Alt` | focus the selection |

## Status

Working and in daily use. Hotkeys, shortcuts and exclusions are configurable from
the menu bar; the rest is in [Roadmap.md](Roadmap.md).

- [x] Signed with a stable identity, so TCC grants survive an update
- [x] Event tap and key router, including Cmd-Tab ahead of the Dock
- [x] Window model driven by `AXObserver`, most-recently-used order
- [x] Overlay panel with thumbnails, on whichever screen is active
- [x] Menu bar item, settings window, signed disk image
- [ ] Minimised windows and fullscreen spaces still to check

### Numbers

Measured on a two-monitor machine with five windows open:

| | |
| --- | --- |
| Opening the overlay, thumbnails present | **1.5–6 ms** |
| Resolving the window list | ~1 ms, no accessibility calls |
| One thumbnail capture | 67 ms for the first, then ~8 ms each |
| Five captures from cold | ~170 ms, none of it on the main thread |

The capture numbers only matter when the cache is cold, which it rarely is: it is
warmed at startup and then for each window as it loses focus — the moment its
contents are final and nobody is waiting. By the time the overlay opens the
images are already there, which is the first row.

## Design

Three decisions carry most of the behaviour:

- **The window model is maintained, not queried.** `AXObserver` notifications
  keep it current on a thread of its own, with a 0.5 s messaging timeout per
  application, so an unresponsive app degrades into a missing window rather than
  a frozen switcher. Opening the switcher costs one lock and one window server
  call.
- **The event tap owns a thread and a runloop.** macOS quietly disables a tap
  whose callback misses its deadline, and the main thread is where rendering and
  window server round trips live. The callback itself is a keycode comparison.
- **The overlay panel is built once and kept.** Showing it is an `orderFront`,
  hiding it an `orderOut`; nothing is allocated on the hot path.

## Requirements

macOS 14 or newer, and the Swift toolchain from the Command Line Tools. Xcode is
not needed — SwiftPM compiles, the Makefile assembles the bundle.

## Build

```sh
make cert       # once, interactive: creates the signing identity
make run        # build, install, launch
make logs       # follow along
make verify     # check the designated requirement has not drifted
```

Starting at login is a switch in Settings › General, not a Makefile target. The
launch agent ships inside the app bundle and the app registers it through
`SMAppService`, which puts it under System Settings › Login Items and resolves the
executable against the bundle, so moving Flip cannot leave an agent pointing at
nothing. Its `KeepAlive` is deliberately `SuccessfulExit: false` rather than
`true`: a crash should bring Flip back, quitting on purpose should not.

Nothing is ever started straight from a shell. Launching the binary from a
terminal makes the terminal the responsible process for TCC, and the privacy
grants get attributed to it rather than to Flip, which is why `make run` goes
through `open`.

The menu bar item is the only visible surface: it reports both privacy grants,
offers the privacy pane when one is missing, opens Settings, and quits. Its icon turns into a warning triangle when a grant goes away, which is
worth having — a switcher that has lost Accessibility is indistinguishable from a
broken keyboard.

## Settings

**Settings…** in the menu bar, or ⌘, — three tabs, and every change applies as you
make it. There is nothing to save.

**General** carries the two hotkeys, whether tiles show thumbnails or only icons,
and whether Flip starts at login. Turning thumbnails off drops the Screen
Recording requirement entirely rather than merely hiding the images.

**Excluded** keeps applications out of the window list. A key bound directly to one
still reaches it: naming an application is an explicit request, and refusing that
would be surprising.

**Shortcuts** edits the application bindings. They live in `~/Library/Application Support/Flip/bindings.json`, seeded from
`DefaultBindings` on first run and readable enough to keep with your dotfiles:

```json
{ "bundleID": "com.spotify.client", "key": "s", "usesLeader": true }
```

`usesLeader: false` means the key reaches the application with no modifier at
all — that is how F1 gets to Ghostty, and it takes F1 away from every other
application. Keys that no character can type, the function keys, can only be
written by name and only in the file.

Edits made by hand are picked up while Flip runs. Watching for them needs both a
file watch and a directory watch in effect: an editor that overwrites in place
leaves the directory untouched, while an atomic save replaces the inode and
strands a file watch — so the file is watched and the watch is rebuilt whenever it
is replaced. Settings are not watched; they are only read at launch.

### The warning about shadowed characters

A binding swallows its key globally, so binding one that Option already uses
takes that character away everywhere. Warning about "this key produces a
character" would be useless — on a German layout every alphanumeric key does, 40
out of 40, but they produce ç, €, ƒ, © and other things nobody types.

The nine that matter are the ones whose Option layer is printable ASCII: on this
layout `[ ] { } | @ ~ ' .`, which is exactly the set a programmer needs. Those
are what the editor warns about, and only those.

## Installing on another Mac

```sh
make dmg        # build/Flip-<version>.dmg
```

Gatekeeper will not like it. The bundle is signed with the self-signed identity
from `make cert`, which is trusted only on the machine that created it, and it is
not notarised — so on any other Mac it opens only via right-click > Open, once.
Distributing it properly means an Apple Developer ID and notarisation.


## Releasing

Every push builds. Pushing a `v*` tag additionally signs, packages and publishes
a GitHub release with the disk image attached:

```sh
git tag v0.2.0 && git push origin v0.2.0
```

The pipeline signs with the same certificate as a local build, held as the
repository secrets `SIGNING_CERTIFICATE_P12` (base64 of the `.p12`) and
`SIGNING_CERTIFICATE_PASSWORD`. That is what makes an update an update rather
than a new application as far as TCC is concerned — and `make verify` asserts it
before anything is packaged, comparing the bundle's designated requirement
against `Resources/designated-requirement.txt`. A drifted requirement fails the
release instead of silently revoking everyone's privacy grants.

Worth knowing about that key: anything able to use it can sign as
`dev.mxwnk.Flip`, and macOS will hand that signature Flip's Accessibility grant.
Keep the secrets to this repository. If they ever leak, `make uncert`, a fresh
`make cert`, an updated `designated-requirement.txt` and one round of re-granting
in System Settings is the whole recovery.

## The signing identity

`make cert` creates a self-signed certificate and trusts it for code signing.
This is not ceremony. TCC keys a privacy grant to the app's designated
requirement, and for an ad-hoc signature that requirement contains the code
directory hash — which changes on every build. Accessibility and Screen
Recording would have to be granted again after each `make install`.

Signing against a certificate pins the requirement to the bundle identifier and
the certificate instead. Check that it holds:

```sh
make verify     # prints the designated requirement; must not change on rebuild
```

The certificate is trusted only for code signing, and the key is scoped to
`codesign` rather than imported with `-A`: anything signed as `dev.mxwnk.Flip`
would inherit Flip's Accessibility grant.

## License

MIT. See [LICENSE](LICENSE).
