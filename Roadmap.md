# Roadmap

Ordered roughly by what would be missed first. Each entry notes the catch, because
the catch is usually the reason something is not done yet.

## Configuration

- [x] **Settings window.** Leader modifier, application-switcher modifier, start at
      login, thumbnails or icons, exclusions. Sorting is still open, under
      switcher behaviour. Before this, all of it was
      compile-time in `Configuration.swift`. Shortcuts became one tab of it rather
      than its own window.
- [x] **Start-at-login toggle.** Moved from `make autostart` to `SMAppService`: the
      agent ships in the bundle and the app registers it. Registering starts a
      second copy immediately, so it also needed a single-instance guard — and one
      that picks a winner, since "is anyone else running" makes both copies leave.
- [x] **Thumbnails or icons per preference.** Icons make the overlay instant and
      drop the Screen Recording requirement entirely — worth offering, not just as
      a fallback.
- [x] **Watch `bindings.json`.** Needed a file watch *and* re-arming: watching the
      directory misses in-place overwrites, watching the file alone is stranded by
      an atomic save. Own writes are filtered by comparing content, or it loops.
- [x] **Exclude applications.** Some applications are never worth switching to and
      only make the grid wider.

## Moving windows

- [x] **Halves, fill, and moving between displays.** Fixed keys for now, matching
      what Rectangle's alternate set uses, so there is nothing to relearn.
- [ ] **Configurable keys for the window actions.** The modifier is hard-coded;
      it belongs in Settings next to the switcher's.
- [ ] **Quarters, addressed with letters rather than arrows.** Four corners need
      four keys, and arrows only offer two axes. Either `h j k l` in the vim sense,
      or the `u i j k` block Rectangle uses, whose physical layout already forms the
      2×2 the action describes. `⌃⌥` with letters is free — the leader is Option on
      its own.
- [ ] **Thirds, centre, and restore.** The rest of the usual set, once quarters
      have settled which key scheme wins.

## Switcher behaviour

- [x] **Minimised windows in Alt-Tab.** Listed with the application icon and a
      badge, since a window in the Dock cannot be captured. Committing one
      restores it.

- [ ] **Mouse: hover to select, click to confirm.** The panel sets
      `ignoresMouseEvents = true` today, so this is a deliberate reversal rather
      than an addition. Careful with the non-activating panel: clicking must not
      make Flip the active application.
- [ ] **Close a window or quit an application from the overlay.** Select and press
      W or Q. The natural companion to a switcher, and the accessibility calls are
      already in place.
- [x] **No overlay for a quick tap.** The selection is made immediately and only
      drawing waits, so a release inside the delay commits without the panel ever
      appearing. Configurable in Settings › General; 150 ms by default.
- [ ] **Jump by number.** 1–9 selects the nth tile directly while the overlay is up.
- [ ] **A switch for windows on every space.** Off keeps today's behaviour; on
      lists everything Flip knows about. Two things make this more than a filter
      change. Minimised windows already bypass the space check, because they are
      absent from the window server's on-screen listing and there is nothing to
      compare them against — so the current behaviour is inconsistent rather than
      strict. And doing it properly, in either direction, needs the private
      SkyLight call for a window's space, the way AltTab and yabai do it.
- [ ] **Per-monitor filtering.** The overlay follows the active monitor, but lists
      windows from both. Deliberate — but it should be a choice.
- [ ] **Sort order as a setting.** Most recently used today. Alphabetical is the
      obvious alternative: it makes the grid something you read rather than cycle,
      and a window keeps its place between openings, which MRU deliberately does
      not. The store already carries `focusOrder`, so this is a comparator and a
      picker.

## Quality

- [x] **Unit tests.** 30 of them, over `OverlayLayout`, `BindingStore`, `Settings`,
      `AppBinding` and `Modifiers` — the logic that does not need a running Mac.
      They found one bug immediately: synthesised `Codable` requires every key, so
      adding a setting made existing files unreadable and reset them.
- [ ] **Fullscreen spaces.** Untested. A full-screen application is its own space
      and the overlay's `fullScreenAuxiliary` behaviour has never been exercised.
- [ ] **Minimised windows that no longer exist.** If an application swallows the
      destroyed notification, a minimised entry can outlive its window. The
      on-screen list cannot catch it, because minimised windows are not in it.
- [ ] **The 8–11 ms outliers.** Opening the overlay is usually 2–4 ms but sometimes
      three times that, from SwiftUI re-layout when the window count changes.
- [x] **Pause Flip.** Disables the tap at the port, so events never reach Flip and
      the Dock gets Cmd-Tab back. Not persisted: pausing is for the length of a
      screen share, and a switcher that silently does nothing after a restart would
      be worse than one that resumed.
- [ ] **Diagnostics.** A menu item that copies versions, grants, binding count and
      recent log lines, so a problem can be reported without a terminal.

## Showing it off

- [~] **A GIF of Flip in use, for the readme.** `scripts/demo.sh` stages the scene,
      performs the sequence and restores everything; the recording and the keystroke
      overlay are still to be added.
  - **Keystrokes on screen: KeyCastr** (`brew install --cask keycastr`), open
    source and the standard choice on macOS. One catch to verify: it watches
    through an event tap of its own, and Flip swallows its bound keys before
    passing them on. Whichever tap was inserted last sees the event first, so
    KeyCastr has to be started *after* Flip or it will show nothing for exactly the
    keys the recording is about.
  - **Recording:** `screencapture -v -R<x,y,w,h> -V<seconds>` records a region for
    a fixed duration with no interaction, which is what makes the whole thing
    scriptable. `ffmpeg` is already installed; `gifski` produces a noticeably
    better palette if the result looks banded.
  - **Staging:** the same trick the screenshot used — exclude every application but
    the demo ones, so nothing private can wander into frame — and then use Flip's
    own window actions to place them, so the scene is reproducible rather than
    arranged by hand.
  - **Known pitfalls:** holds must outlast the 150 ms overlay delay or the grid
    never draws; a 5K recording needs scaling to something a readme can carry; and
    nobody may touch the keyboard while it runs, since a real keystroke releases
    the modifier and ends the take.

## Project

- [x] **LICENSE.** MIT.
- [x] **Application icon.** Drawn by `scripts/make-icon.swift` and committed as
      `Resources/Flip.icns`, so CI packages the same icon without redrawing it.
      The motif is the overlay's own: two offset window tiles, the front one
      carrying the same blue selection ring.
- [ ] **Documentation.** The Readme carries everything today and is getting long;
      an architecture note explaining the threading model would save the most
      rereading.
- [x] **`CLAUDE.md` / `AGENTS.md`.** Conventions and the invariants that break
      silently. `CLAUDE.md` is one `@AGENTS.md` import, the way alt-tab-macos does
      it, so there is only ever one copy.
- [ ] **German localisation.** The interface is English on a German machine.
- [ ] **Update check.** The release pipeline exists; the app does not know about it.
      Polling the GitHub releases API and offering the new disk image is small, and
      the stable designated requirement means an update keeps its privacy grants.
- [ ] **Notarisation.** The blocker for installing on any Mac but this one. Needs an
      Apple Developer ID, then one more step in the pipeline.
- [x] **Pushes trigger the pipeline.** Fixed in the account's Actions settings;
      a push now builds and runs the tests without a manual dispatch.
