# Changelog

The release pipeline lifts the section matching the tag out of this file and
publishes it as the release notes, so what is written here is what people read.

## 1.2.0

The disk image says which version it is installing, and warns you about the
permission dialog before it appears rather than after. A permission nobody was
expecting is the moment an unsigned application starts to look like malware.

Flip also has a page now: [mxwnk.github.io/flip](https://mxwnk.github.io/flip/).

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
