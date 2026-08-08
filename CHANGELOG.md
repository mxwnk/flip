# Changelog

The release pipeline lifts the section matching the tag out of this file and
publishes it as the release notes, so what is written here is what people read.

## 1.4.0

**Flip has a command line.** `flip list` prints every window it knows as JSON,
`flip focus <id>` brings one forward, `flip arrange left-half` moves the focused
one, and `flip switch`, `flip pause` and `flip resume` do what they say. Homebrew
puts it on your PATH; a disk image install gets it with `make link`.

It drives the running application over a socket rather than reaching into
accessibility itself, so it sees exactly the windows the switcher sees rather
than a second opinion. The window-title search Flip does not have is now a
pipeline: `flip list | jq` and `flip focus`.

Opening the switcher from a script left it with no way out, because nothing was
holding a modifier to release. **Return now commits the selection** — bare or
with the leader held, so `⌃⌥↩` still fills the window behind the grid.

**A fresh install now ships one shortcut instead of fourteen.** The old seed was
one person's habits — a file manager most people have never installed, a
particular Chrome web app, three editors — and every key it claimed was one a new
user had to find and clear before it was theirs. What is left is `⌥ F` for the
Finder: enough to show what application keys are, on the one application every
Mac certainly has. An existing `bindings.json` is untouched.

## 1.3.0

**The wheel steps through the grid.** Hovering already picked a tile and
clicking already took it; scrolling was the one thing a hand on the mouse could
not do. A notch is one window, the way it is in any list, and it follows the
scrolling direction set on the machine rather than deciding for itself. A
trackpad has to travel about a tile's width to earn a step, so a flick browses
rather than bolting to the end.

**Five fixes from a full read of the source.**

A tap that failed to start had no way back. The port is created on its own
thread, so a failure arrived after startup had already recorded the tap as
running — no hotkey worked until the next launch, and the menu bar went on
saying everything was fine. It now reports back, retries, and says so in the
menu when it cannot.

The safety timer that closes an overlay nobody let go of was re-armed on every
narrowing, leaving the first one in the runloop. Half a minute later it could
close a session it had nothing to do with. It now belongs to the session, which
is what it was always measuring.

Choosing an application with `⌘Tab` when macOS reported no frontmost application
gave up without telling the router, which went on swallowing arrows and escape
until the modifier came back up. Every other giving-up path already reported.

Thumbnails were captured twice whenever two requests overlapped — reliably with
the overlay delay set to Immediately — because a capture in flight was invisible
to the check for what still needed one. The captures are also ordered around the
tile that ends up selected now, rather than the one selected before the grid had
stepped.

A window closed by quitting its application left its remembered position behind,
and window IDs get reused.

**The shortcut editor warns when your leader is already spoken for.** Window
actions are matched before application shortcuts, so choosing `⌃⌥` as the leader
left bindings on `u i j k` and Return permanently unreachable, with nothing
saying why.

**The settings window stays in front.** Flip runs as an accessory application —
no Dock icon, never the active one — and macOS will not reliably bring such an
application's window forward. The window did open; it landed behind whatever was
in front and looked as though the menu item had done nothing. It now floats above
ordinary windows, and well below the switcher's own level, so the grid still draws
over it.

**The display moves are settable.** They share the arrow keys with the halves, so
they have always needed a modifier of their own — and which one is a matter of
what else is bound on the machine. Settings › Windows now offers `⇧⌥` as before,
or `⌃⌥⌘`, all three at once. It switches rather than adds: whichever you do not
pick stops working, so nothing is bound twice behind your back.

The halves and quarters stay fixed, and the settings window now says why rather
than only that they cannot be changed.

**A keyboard along the bottom of the settings window**, with the keys of whichever
tab you are on lit up. `⌃⌥⌘⇧` mean nothing until you can see which physical key
each one is, and the settings window was full of them — so the modifiers carry the
word as well as the symbol, in the positions your thumbs already know.

Three questions go into drawing it, and they are not the same one. The letters
come from the keyboard layout, so a German one shows Z and ß where an American
shows Y and a hyphen. The shape comes from the hardware, which macOS reports
separately — a German layout is typed on plenty of ANSI boards, and those have no
key between the left shift and Z and no key beside the return.

The third is where command sits in the bottom row, and that one macOS genuinely
cannot answer: the modifier remapping it exposes says what each key *does*, not
where it *is*, and a board like the Nuphy Air75 reports Apple's own vendor
identifier while carrying the Windows arrangement — control, command, option. So
it is a small switch under the picture, and nothing else depends on it.

## 1.2.0

Nothing in the application itself changed — this release is about everything
around it. The binary is byte for byte the one in 1.1.0.

**The install command is shorter.** The tap moved to the name personal taps
usually carry, so it reads `brew install --cask mxwnk/tap/flip` rather than
stuttering. An existing install keeps working; `brew upgrade --cask flip` was
already short and still is.

**The disk image says which version it is installing** — the backdrop is redrawn
for every release with the number stamped in — and it warns about the permission
dialog before it appears rather than after. A permission nobody was expecting is
the moment an unsigned application starts to look like malware.

**"Apple cannot check it for malicious software" now has an answer.** Downloading
the disk image by hand runs into Gatekeeper, and the workaround every guide on the
internet repeats — Control-click, Open — stopped working on macOS 26. The readme
and the site both spell out the three clicks that do work, and the one line that
skips them. Homebrew has always cleared this for you; this is for everyone who
takes the disk image instead.

**Flip has a page:** [mxwnk.github.io/flip](https://mxwnk.github.io/flip/). It
leads with the measurements, because everyone claims to be fast and nobody shows
the number.

The readme is half its old length and now about using Flip rather than building
it; that moved to `docs/development.md`.

## 1.1.0

**Pick the display the grid opens on.** On a desk with two monitors the switcher
could open on the one you were not looking at, and for a moment it read as though
the key had done nothing. Settings › General now offers three answers: the display
holding the active window, as before; the main display, always; or every display
at once, the same grid on each. A panel per screen is built at launch the way the
first one always was, so showing three costs no more than showing one — measured,
not assumed.

**Stage Manager no longer ruins previews.** With Stage Manager on, macOS parks a
window as a shrunken, tilted miniature at the edge of the screen and reports that
miniature as the window itself — 200 points wide where the window is 2497. Flip
was dutifully capturing it, which is how a tile ended up with a smear where a
preview should be. Accessibility keeps reporting the real size throughout, so the
two disagreeing is now the tell: the miniature is skipped, the previous capture
stands, and a window Flip has never seen full size keeps its icon.

**Down from the end of a short row goes somewhere.** With seven windows in rows of
four and three, pressing down on the last tile of the top row used to do nothing
at all — the column it wanted did not exist below, and the old code stepped past
the row entirely. It now lands on the last tile of that row.

**Icons fill their tile.** With thumbnails turned off, the stand-in icon was a
fixed 64 points inside a tile built to hold a window, and looked lost in it. It is
sized to the tile now, and shrinks with it once enough windows are open to squeeze
the columns. Minimised windows and captures that have not landed yet get the same
treatment.

Under the hood: `make smoke` — two dozen checks that drive the keyboard and the
mouse through a running copy and read back what Flip decided. It covers the border
with macOS, which is where every real bug in this project has been.

## 1.0.1

The disk image got a window instead of a file listing: a backdrop, the two icons
placed with an arrow between them, and Flip's own icon on the volume.

## 1.0.0

First release. Hold Option and tap Tab for every window on the current space, most
recently used first; let go inside 150 ms and it switches without ever drawing
anything. One key per application. Halves, quarters, filling and moving between
displays from the keyboard. Mouse selection in the grid, windows from every space,
an update check that only ever tells you.
