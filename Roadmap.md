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

## Switcher behaviour

- [ ] **Mouse: hover to select, click to confirm.** The panel sets
      `ignoresMouseEvents = true` today, so this is a deliberate reversal rather
      than an addition. Careful with the non-activating panel: clicking must not
      make Flip the active application.
- [ ] **Close a window or quit an application from the overlay.** Select and press
      W or Q. The natural companion to a switcher, and the accessibility calls are
      already in place.
- [ ] **No overlay for a quick tap.** Show the grid only once the leader has been
      held for ~150 ms. A fast Alt-Tab then switches with no visual at all, which
      is how the muscle memory actually works.
- [ ] **Jump by number.** 1–9 selects the nth tile directly while the overlay is up.
- [ ] **Windows on other spaces.** Currently filtered out, which is right for
      Alt-Tab and wrong when you know the window exists somewhere. Worth a modifier
      or a setting rather than a change of default.
- [ ] **Per-monitor filtering.** The overlay follows the active monitor, but lists
      windows from both. Deliberate — but it should be a choice.
- [ ] **Sort order.** Most recently used today; spatial or alphabetical are
      defensible alternatives for a grid you read rather than cycle.

## Quality

- [ ] **Unit tests.** Worth being specific so the target is not theatre. Genuinely
      testable without a running Mac: `OverlayLayout` grid maths and its
      column-preserving row movement, `BindingStore` JSON round-trip and its issue
      detection, `Modifiers` exact matching, `AppBinding` decoding of older files.
      Not testable: anything behind the accessibility API or the window server.
- [ ] **Fullscreen spaces.** Untested. A full-screen application is its own space
      and the overlay's `fullScreenAuxiliary` behaviour has never been exercised.
- [ ] **Minimised windows that no longer exist.** If an application swallows the
      destroyed notification, a minimised entry can outlive its window. The
      on-screen list cannot catch it, because minimised windows are not in it.
- [ ] **The 8–11 ms outliers.** Opening the overlay is usually 2–4 ms but sometimes
      three times that, from SwiftUI re-layout when the window count changes.
- [ ] **Pause Flip.** A menu bar toggle that stops the router without quitting, for
      screen sharing, games, or anything else that wants Alt-Tab back for a while.
- [ ] **Diagnostics.** A menu item that copies versions, grants, binding count and
      recent log lines, so a problem can be reported without a terminal.

## Project

- [ ] **LICENSE.** Nothing yet, which means all rights reserved by default.
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
- [ ] **Pushes do not trigger the pipeline.** Only `workflow_dispatch` runs. The
      workflow, the repository settings and the push events all check out, so the
      cause is in the account's Actions settings.
