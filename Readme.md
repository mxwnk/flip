# Flip

A native window and application switcher for macOS, replacing the Hammerspoon
implementation in [macos-setup](https://github.com/mxwnk/macos-setup).

Alt is the leader key:

| Keys | Effect |
| --- | --- |
| `Alt-Tab` | cycle every window on the current space |
| `Cmd-Tab` | cycle the windows of the frontmost application |
| `Alt-<letter>` | jump to a bound application, e.g. `Alt-S` for Spotify |
| `Alt` held, `<letter>` | narrow the open overlay to that application |
| release `Alt` | focus the selection |

## Status

Step four of six. Flip is a working switcher: the overlay draws, the selection
moves, and releasing the leader focuses the window. Tiles show application icons
where the thumbnails will go.

- [x] **1 — Signing and permissions.** Stable identity so TCC survives rebuilds.
- [x] **2 — Event tap and key router.** Replaces `apps.lua`.
- [x] **3 — Window store.** `AXObserver` driven, MRU ordered.
- [x] **4 — Overlay panel.** Icons only; replaces `switcher/`.
- [x] **5 — Thumbnails.** ScreenCaptureKit, captured concurrently.
- [~] **6 — Edge cases.** Multi-monitor done; minimised windows and fullscreen
  spaces still to check.
- [x] **7 — Packaging.** Menu bar item and a signed `.dmg`.

### What the numbers actually say

Measured against the Lua switcher on the same machine, five windows open:

| | Lua | Flip |
| --- | --- | --- |
| Overlay open, thumbnails present | 11.5–14.7 ms, tiles still empty | **1.5–6 ms**, tiles filled |
| One capture | 14 ms, main thread | 67 ms first, then ~8 ms each |
| Five captures, cold | ~70 ms, main thread | ~170 ms, off it |

The cold column is worth being honest about: ScreenCaptureKit is *slower* than
`CGWindowListCreateImage` for a one-off capture, and enumerating shareable
content costs 60 ms on top. What it buys is that none of it happens on the main
thread, and that the marginal window costs 8 ms instead of 14.

That only matters because the cache is warmed ahead of time — at startup, and
then for each window as it loses focus, which is when its contents are final and
nobody is waiting. By the time the overlay opens the images are already there,
which is the column that counts.

Flip owns the real bindings as of step five. The Lua `switcher/` and `apps.lua`
are commented out in `macos-setup`, because two event taps grabbing Alt-Tab would
fight over it.

## Why not stay on Hammerspoon

Measured against the Lua implementation with four windows open, the overlay
itself was never the problem — it appeared in 12–15 ms, roughly one frame. Three
other things were:

- **Thumbnails cost 14 ms each**, taken serially on the main thread, one per
  runloop tick. Fifteen windows meant about 210 ms of half-empty grid competing
  with keystroke handling. Captured in parallel through ScreenCaptureKit and
  scaled on the GPU, the same work is roughly 20 ms and never touches the main
  thread.
- **A hung application froze everything.** Hammerspoon reads windows with
  synchronous accessibility calls on the main thread, where the default timeout
  is six seconds — and the Cmd-Tab event tap sits on that same runloop, so a
  busy app delayed the keyboard. Here every AX call runs on a background queue
  with a 0.5 s messaging timeout, and the event tap owns a thread and runloop of
  its own.
- **Every keystroke on the system was routed through the Lua VM** by the event
  tap that Cmd-Tab requires. A native callback comparing a keycode is about a
  microsecond.

## Requirements

macOS 14 or newer, and the Swift toolchain from the Command Line Tools. Xcode is
not needed — SwiftPM compiles, the Makefile assembles the bundle.

## Build

```sh
make cert       # once, interactive: creates the signing identity
make autostart  # build, install, and start at login
make logs       # follow along
make verify     # print the designated requirement
```

`make autostart` writes a launch agent to `~/Library/LaunchAgents` and loads it.
Its `KeepAlive` is deliberately `SuccessfulExit: false` rather than `true`: a
crash should bring Flip back, but quitting it on purpose should not be undone by
launchd. `make unautostart` removes it again.

Nothing is ever started straight from a shell. Launching the binary from a
terminal makes the terminal the responsible process for TCC, and the privacy
grants get attributed to it rather than to Flip — so `make run` goes through the
launch agent when one exists and `open -a` otherwise.

The menu bar item is the only visible surface: it reports both privacy grants,
offers the settings pane when one is missing, opens the shortcut editor, and
quits. Its icon turns into a warning triangle when a grant goes away, which is
worth having — a switcher that has lost Accessibility is indistinguishable from a
broken keyboard.

## Shortcuts

**Shortcuts…** in the menu bar edits the application bindings. Changes apply as
you make them; there is nothing to save.

They live in `~/Library/Application Support/Flip/bindings.json`, seeded from
`DefaultBindings` on first run and readable enough to keep with your dotfiles:

```json
{ "bundleID": "com.spotify.client", "key": "s", "usesLeader": true }
```

`usesLeader: false` means the key reaches the application with no modifier at
all — that is how F1 gets to Ghostty, and it takes F1 away from every other
application. Keys that no character can type, the function keys, can only be
written by name and only in the file.

Flip reads the file at launch and writes it on every edit, so it does not notice
changes made by hand while it is running.

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

There is no application icon yet, so the disk image shows the generic one.

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
