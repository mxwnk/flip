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
- [x] **Quarters on `⌃⌥` and `u i j k`.** Letters rather than arrows, because four
      corners need four keys. Not the vim four: `y u / h j` is only a square on a US
      layout, and types `z u / h j` on a German one.
- [x] **Filling is a toggle.** Pressing it on a window that already fills puts it
      back, which needs the previous frame remembered per window. Two catches: a
      terminal resizes in whole character cells and stops a few points short of the
      edges, so "already fills" needs a tolerance rather than an equality; and with
      nothing remembered — after a restart, or a window that opened filled — it
      falls back to sixty per cent centred, because refusing to move looks exactly
      like the bug. macOS's own full screen is handled separately: the frame cannot
      be written there at all, so the key clears `AXFullScreen` instead.
- [ ] **Thirds and centre.** The rest of the usual set, once quarters have settled
      which key scheme wins. Restore is done, as part of the fill toggle.

## Switcher behaviour

- [x] **Minimised windows in Alt-Tab.** Listed with the application icon and a
      badge, since a window in the Dock cannot be captured. Committing one
      restores it.

- [x] **Mouse: hover to select, click to confirm.** Hovering is handled in AppKit
      rather than with SwiftUI's `onHover`, whose tracking area is only live while
      its own application is active — and Flip never activates. It takes over only
      once the pointer has actually moved, so a grid opening under a resting
      pointer keeps the selection the keyboard just made, and so does every arrow
      key afterwards. A click beside the grid gives up rather than committing
      whatever happened to be under the ring.
- [ ] **Close a window or quit an application from the overlay.** Select and press
      W or Q. The natural companion to a switcher, and the accessibility calls are
      already in place.
- [x] **No overlay for a quick tap.** The selection is made immediately and only
      drawing waits, so a release inside the delay commits without the panel ever
      appearing. Configurable in Settings › General; 150 ms by default.
- [ ] **Jump by number.** 1–9 selects the nth tile directly while the overlay is up.
- [x] **A switch for windows on every space.** Settings › General. The private
      SkyLight call this entry used to demand turns out not to be needed: nothing
      here has to know *which* space a window is on, only that it exists, and the
      window server lists them all without `optionOnScreenOnly`.
      The real obstacle was elsewhere. Accessibility only enumerates the windows on
      the space in front of you — measured: Ghostty had one window through AX and
      six through the window server — so a filter alone had nothing to let through.
      What makes it work is that an element already held stays valid: raising one
      plus activating its application switches spaces on its own. So Flip rescans
      every watched application on `activeSpaceDidChangeNotification` and keeps
      what it finds, rather than trying to find windows on demand.
      The gap that remains: a space never visited in this run is still unknown.
- [ ] **Windows on spaces never visited.** The one case the rescan cannot reach.
      Discovery is easy — the window server lists them — but a window off-space has
      no accessibility element, so there is nothing to raise. Resolving one after
      activating its application, by matching the window id through the existing
      `_AXUIElementGetWindow` shim, is the thread to pull.
- [ ] **Per-monitor filtering.** The overlay follows the active monitor, but lists
      windows from both. Deliberate — but it should be a choice.
- [ ] **Sort order as a setting.** Most recently used today. Alphabetical is the
      obvious alternative: it makes the grid something you read rather than cycle,
      and a window keeps its place between openings, which MRU deliberately does
      not. The store already carries `focusOrder`, so this is a comparator and a
      picker.

## Quality

- [x] **Unit tests.** 78 of them, over `OverlayLayout`, `BindingStore`, `Settings`,
      `AppBinding`, `Modifiers` and `WindowArrangement` — the logic that does not
      need a running Mac, including the overlay's hit test.
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
- [x] **Diagnostics.** **Copy Diagnostics** in the menu puts version, bundle path,
      macOS build, both grants, every setting, the shortcut count and Flip's last
      ten minutes of log on the clipboard. Read through `OSLogStore` scoped to the
      current process, which needs no entitlement — `OSLogStore.local()` would want
      one Flip has no business holding. The bundle path is in there because a
      Homebrew install and a `make run` build answer to the same name.

## Showing it off

- [~] **A GIF of Flip in use, for the readme.** `scripts/demo.sh` stages the scene
      and performs the sequence; the recording is in `docs/demo.gif`. Still missing
      the keystroke overlay, so the film shows what happens but not what was
      pressed — which is half of what it is for.
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

- [x] **LICENSE.** MIT. The year is read out of `LICENSE` by the Makefile and
      written into `Info.plist`, so the about window cannot drift from the document
      that actually grants anything.
- [x] **About window.** Version, repository, licence and copyright. The local
      version now comes from the latest tag rather than a constant in the Makefile,
      because a diagnostic report claiming a version it is nowhere near is worse
      than no report.
- [x] **Application icon.** Drawn by `scripts/make-icon.swift` and committed as
      `resources/Flip.icns`, so CI packages the same icon without redrawing it.
      The motif is the overlay's own: two offset window tiles, the front one
      carrying the same blue selection ring.
- [ ] **Documentation.** The Readme carries everything today and is getting long;
      an architecture note explaining the threading model would save the most
      rereading.
- [x] **`CLAUDE.md` / `AGENTS.md`.** Conventions and the invariants that break
      silently. `CLAUDE.md` is one `@AGENTS.md` import, the way alt-tab-macos does
      it, so there is only ever one copy.
- [ ] **German localisation.** The interface is English on a German machine.
- [x] **Update check.** Once a day against the GitHub releases API, and the answer
      is one menu item. Deliberately no self-installing: Homebrew owns the copy it
      installed, and an application that replaced itself underneath would leave the
      cask stale and get downgraded by the next `brew upgrade` — the way around
      that is `auto_updates true`, which hands the whole job to the app forever.
      Not worth it for a check that takes eighty lines.
- [ ] **Installing the update too.** Everything needed is already here: the disk
      image is on the release, and the designated requirement is pinned and checked
      in CI, so a downloaded bundle can be verified against exactly the requirement
      TCC keys its grants to — no second signing key, which is most of what Sparkle
      would be for. What it costs is the Homebrew arrangement above and an
      application that replaces itself while running.
- [ ] **Notarisation.** The cask strips the quarantine flag, which is fine for a
      tap you chose to trust and not fine for anything wider — the official
      homebrew-cask will not take an app that needs it. Needs an Apple Developer
      ID, and re-signing changes the designated requirement, so every existing
      install loses Accessibility and Screen Recording once.
- [x] **Installable with Homebrew.** `brew install --cask mxwnk/flip/flip`, from
      [mxwnk/homebrew-flip](https://github.com/mxwnk/homebrew-flip). The release
      pipeline bumps the cask through a deploy key scoped to that repository.
- [x] **Pushes trigger the pipeline.** Fixed in the account's Actions settings;
      a push now builds and runs the tests without a manual dispatch.
