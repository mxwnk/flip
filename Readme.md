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

Step two of six. Keys are routed and applications can be reached; the switcher
commands are logged rather than drawn, because there are no windows to draw yet.

- [x] **1 — Signing and permissions.** Stable identity so TCC survives rebuilds.
- [x] **2 — Event tap and key router.** Replaces `apps.lua`.
- [ ] **3 — Window store.** `AXObserver` driven, MRU ordered.
- [ ] **4 — Overlay panel.** Icons only; replaces `switcher/`.
- [ ] **5 — Thumbnails.** ScreenCaptureKit, captured in parallel.
- [ ] **6 — Edge cases.** Multi-monitor, minimised windows, fullscreen spaces.

### Running alongside Hammerspoon

Two event taps grabbing the same keys would fight, so while the Lua switcher is
still installed Flip listens one modifier over: the leader is `Ctrl-Alt` and the
application switcher is `Ctrl-Cmd-Tab`. Set `coexistWithHammerspoon` to false in
`Configuration.swift` to take the real bindings over; that is the whole handover.

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
make install    # build, bundle, sign, copy to ~/Applications
make run        # install and launch
make logs       # follow along
make autostart  # start at login
```

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
