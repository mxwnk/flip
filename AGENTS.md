# Flip

A native window and application switcher. Agent app, no Dock icon, driven by a
CGEventTap. macOS 14+, built with SwiftPM; Xcode is needed only for the tests.

# Build

- `make run` builds, signs, installs to `~/Applications` and launches
- `make logs` streams the app's log; almost everything interesting is logged
- `make verify` checks the designated requirement has not drifted
- `make test` runs the unit tests. XCTest needs Xcode, so the target points
  `DEVELOPER_DIR` at it rather than changing `xcode-select`
- `make icon` redraws the app icon
- Never launch the binary from a shell. TCC would attribute the privacy grants to
  the terminal instead of to Flip.

# Invariants

These break silently. Nothing crashes, nothing logs, and the app looks fine.

- **The designated requirement must not change.** TCC keys Accessibility and
  Screen Recording to it, so a drift revokes them on every installed copy.
  `Resources/designated-requirement.txt` records it and CI fails on a mismatch.
- **No accessibility call on the hot path.** The window model is maintained by
  `AXObserver` notifications on `RunLoopThread`, with a 0.5 s messaging timeout
  per app. Opening the switcher must cost one lock and one window server call.
- **No AppKit off the main thread**, and no main-thread work in the event tap.
  The tap owns a thread and runloop of its own; missing its deadline makes macOS
  disable it.
- **State shared between the tap thread and main goes behind a lock.** Bindings,
  hotkey modifiers and overlay visibility already do.
- **`isFloatingPanel` rewrites the window level**, so set it before `.level`.
  Getting this backwards leaves the overlay below full-screen windows.
- **Only the oldest instance survives.** Registering the login item starts a
  second copy immediately, and two event taps race for every keystroke.

# Style

- Compact. Prefer splitting into small methods over grouping statements with
  blank lines.
- `guard` early, happy path underneath.
- English throughout, including comments.
- Few comments. Simple code gets none. Comment only what the code cannot show:
  macOS or private-API behaviour, measured timings, and why something that looks
  removable is not. Never narrate history or reverted approaches.
- Files are grouped by feature under `Sources/Flip/`.

# Verifying

Claims about behaviour need evidence, and this app is measurable:

- `make logs` reports open timings, thumbnail capture, binding counts, permissions
- The overlay's own window can be photographed: `screencapture -l <windowID>`
- Synthetic keystrokes via `CGEvent.post` drive the router, but only reliably
  while nobody is typing — a real keystroke closes the overlay mid-test

# Commits

One line, Conventional Commits, no body, no trailers.
