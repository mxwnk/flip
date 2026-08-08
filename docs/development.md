# Working on Flip

Conventions and the invariants that break silently are in
[AGENTS.md](../AGENTS.md).

```sh
make cert       # once, interactive: creates the signing identity
make run        # build, sign, install to ~/Applications, launch
make test       # 81 unit tests
make smoke      # 30 checks against a running copy, before a release
make logs       # follow along; almost everything interesting is logged
```

SwiftPM compiles and the Makefile assembles the bundle, so Xcode is needed only
for the tests. Nothing is ever started straight from a shell: that would make the
terminal the responsible process for TCC and attribute the privacy grants to it
rather than to Flip.

## Two kinds of test

`make test` covers the arithmetic — layout, key matching, window geometry,
settings decoding. It runs in CI on every push.

`make smoke` covers the border with macOS, which is where every real bug in this
project has been. It drives the keyboard and the mouse through synthetic events,
reads back what Flip decided from its own log, and measures windows it moved.
It needs Accessibility, Screen Recording, a desktop session and a machine nobody
is typing on, which is why it is a command you run before a release rather than a
step in the pipeline. Hands off the keyboard while it runs: a real keystroke
releases the modifier holding the switcher open.

## The signing identity

`make cert` creates a self-signed certificate and trusts it for code signing.
This is not ceremony. TCC keys a privacy grant to the app's designated
requirement, and for an ad-hoc signature that requirement contains a hash that
changes on every build — Accessibility and Screen Recording would have to be
granted again after every install.

Signing against a certificate pins the requirement to the bundle identifier
instead. `make verify` checks it against `resources/designated-requirement.txt`,
and the release pipeline refuses to package a build where it has drifted.

## Why it is quick

Nothing is asked for at the moment you press the key.

The window list is not queried but **maintained** — `AXObserver` notifications
keep it current on a thread of its own, so opening the grid costs one lock and one
window server call. The **event tap owns a thread and a runloop**, because macOS
quietly disables a tap whose callback misses its deadline. **Panels are built once
at launch**, one per screen, and only ordered in and out. Thumbnails are captured
ahead of time: at startup, and then for each window as it loses focus, which is
when its contents are final and nobody is waiting.

Measured with nine windows open on a two-monitor machine:

| | |
| --- | --- |
| Opening the grid, thumbnails already there | **6–10 ms** |
| Resolving the window list | ~1 ms, no accessibility calls |
| Warming every thumbnail at startup | ~200 ms for nine, in parallel |

## The site

`site/` is plain HTML and CSS with no build step, published to
[mxwnk.github.io/flip](https://mxwnk.github.io/flip/) by `.github/workflows/pages.yml`
whenever it or the pictures in `docs/` change. The pictures are copied in at
deploy time rather than kept twice in the tree. Its palette is `Theme.swift`
converted to hex, so the page and the overlay stay the same thing seen twice.

## The `flip` command

`src/FlipCLI` builds a second executable that ships inside the bundle at
`Contents/Helpers/flip` — not `Contents/MacOS/`, because macOS volumes are
case-insensitive by default and `flip` there is the same file as `Flip`.

It talks to the running application over a unix socket in Application Support.
The wire format lives in `src/FlipControl`, shared by both so it cannot drift;
`ControlTests` holds the arrangement names on the two sides to each other.

`make link` symlinks it into `/usr/local/bin`, `make unlink` removes it. The
Homebrew cask does the same with a `binary` stanza.

## Releasing

Every push builds and tests. Pushing a `v*` tag also signs, packages, publishes a
release with the disk image attached, and points the Homebrew cask at it:

```sh
git tag v1.1.0 && git push origin v1.1.0
```

Release notes come from the section in [CHANGELOG.md](../CHANGELOG.md) matching
the tag, so they are written and reviewed with the change rather than assembled
from commit subjects afterwards. A tag with no section still releases, with a
warning.

The cask lives in [mxwnk/homebrew-tap](https://github.com/mxwnk/homebrew-tap)
and is never edited by hand. Bumping it uses a deploy key held as
`HOMEBREW_TAP_DEPLOY_KEY`, which can write to the tap and to nothing else. Without
it the release still goes out and the cask stays where it was, with a warning in
the run.

The disk image window — backdrop, icon positions, volume icon — is assembled by
`scripts/make-dmg.sh`. Its layout lives in a `.DS_Store` that only Finder can
write, so it is produced once with `make dmg-layout` on a desktop and committed.
The backdrop itself is redrawn on every build, because the version is stamped into
it; the layout refers to it by name, so replacing its contents is free.
