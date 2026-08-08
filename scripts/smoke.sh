#!/usr/bin/env bash
#
# Everything about Flip that only a running Mac can answer. The unit tests cover
# the arithmetic; this covers the border with macOS, which is where every real
# bug in this project has been.
#
#   make smoke
#
# Nobody may touch the keyboard or the mouse while it runs: the switcher is held
# open by a modifier, and one real keystroke releases it. Takes about twenty
# seconds.
#
# It works on a Finder window of its own rather than anything of yours, restores
# the clipboard, and leaves the settings as it found them.
#
# Almost none of those twenty seconds is work — it is waiting for macOS. So nothing
# here sleeps for a fixed interval if it can watch for the thing it is waiting
# on instead: `await` blocks until Flip logs a decision, `awaitax` until a window
# has actually moved, `awaitwindow` until a panel exists. A poll costs the real
# case where a sleep costs the worst case, which makes the suite both quicker and
# harder to make flaky — the ceilings below are deliberately generous, because
# reaching one is now a failure rather than the normal course of events.

set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(dirname "$HERE")"
OUT="$ROOT/build/smoke"
DRIVER="$OUT/driver"
LOG="$OUT/flip.log"
SUPPORT="$HOME/Library/Application Support/Flip"
SETTINGS_BACKUP="$OUT/settings.json.backup"
CLIPBOARD_BACKUP="$OUT/clipboard.backup"

PASSED=0
FAILED=0
STARTED=$(date +%s)

pass() { PASSED=$((PASSED + 1)); printf '  \033[32m✓\033[0m %s\n' "$1"; }
fail() { FAILED=$((FAILED + 1)); printf '  \033[31m✗\033[0m %s\n' "$1"; [ $# -gt 1 ] && printf '      %s\n' "$2"; }

check() {   # description  expected  actual
    if [ "$2" = "$3" ]; then pass "$1"; else fail "$1" "expected '$2', got '$3'"; fi
}

# The log is the only window into what Flip decided. One stream runs for the
# whole suite and each step marks how far in it has already read, so a line from
# an earlier step still cannot be mistaken for this one's — and the 1.5 seconds
# an attach costs is paid once rather than fourteen times. Restarting it per step
# also dropped whatever Flip logged during the gap, which this cannot.
MARK=0
export SMOKE_LOG="$LOG"

start_log() {
    pkill -f "log stream.*dev.mxwnk.Flip" 2>/dev/null
    : > "$LOG"
    log stream --level debug --style compact --predicate 'subsystem == "dev.mxwnk.Flip"' \
        >> "$LOG" 2>&1 &
    LOGGER=$!
}
stop_log() { kill "${LOGGER:-}" 2>/dev/null; wait "${LOGGER:-}" 2>/dev/null; }

mark()   { MARK=$(wc -c < "$LOG" | tr -d ' '); export SMOKE_MARK="$MARK"; }
since()  { tail -c "+$((MARK + 1))" "$LOG" 2>/dev/null; }
logged() { since | grep -qE "$1"; }

restore() {
    stop_log
    [ -f "$SETTINGS_BACKUP" ] && cp "$SETTINGS_BACKUP" "$SUPPORT/settings.json"
    [ -f "$CLIPBOARD_BACKUP" ] && pbcopy < "$CLIPBOARD_BACKUP"
    osascript -e 'tell application "Finder" to close every window' >/dev/null 2>&1
    echo
    printf 'Took %ss. ' "$(( $(date +%s) - STARTED ))"
    if [ "$FAILED" -eq 0 ]; then
        printf '\033[32m%s checks passed.\033[0m Screenshots in build/smoke.\n' "$PASSED"
    else
        printf '\033[31m%s of %s checks failed.\033[0m Screenshots in build/smoke.\n' \
            "$FAILED" "$((PASSED + FAILED))"
    fi
    exit $([ "$FAILED" -eq 0 ] && echo 0 || echo 1)
}
trap restore EXIT

mkdir -p "$OUT"
cp "$SUPPORT/settings.json" "$SETTINGS_BACKUP" 2>/dev/null
pbpaste > "$CLIPBOARD_BACKUP" 2>/dev/null

# Started before the driver is built rather than after, so the second the
# compiler spends is also the second the stream needs to attach. Flip is not
# started until both are ready, so nothing it says at launch can be missed.
start_log

echo "==> Building the driver"
swiftc -O "$HERE/smoke/driver.swift" -o "$DRIVER" || { echo "driver would not build"; exit 1; }

# The stream needs about a second and a half to attach, and nothing Flip says
# before it does is captured. Compiling the driver covers most of that, so only
# the remainder is waited out — once, rather than before every step.
#
# There is nothing to watch for instead: `log` prints its column header with the
# first event rather than on attaching, so on an idle subsystem the header never
# arrives and waiting for it hangs. Measured the other way round, though: once
# the stream is up, a line Flip writes reaches the file inside 650 ms, which is
# what makes polling for one worth doing everywhere below.
sleep 0.6

echo "==> Installing and starting Flip"
mark
# `run` depends on `install`, which stops any running copy first — so this is one
# install and one start, where it used to be three of each.
(cd "$ROOT" && make run >/dev/null) || { echo "install failed"; exit 1; }

# A pipeline into read runs in a subshell and loses the variable, so the here
# string is not a stylistic choice.
shoot() {
    read -r id _ <<<"$("$DRIVER" awaitwindow Flip 500 2000)"
    [ -n "${id:-}" ] && screencapture -x -o -l "$id" "$OUT/$1.png" 2>/dev/null
}
overlay_id() { "$DRIVER" window Flip 500 | cut -d' ' -f1; }

# Retried rather than slept at: the menu has to have rendered before the item can
# be found, and how long that takes is not knowable in advance.
click_menu_item() {   # name
    local n=0
    while [ "$n" -lt 25 ]; do
        osascript -e "tell application \"System Events\" to tell process \"Flip\" to click menu item \"$1\" of menu 1 of menu bar item 1 of menu bar 1" >/dev/null 2>&1 && return 0
        sleep 0.15
        n=$((n + 1))
    done
    return 1
}

open_menu() {
    osascript -e 'tell application "System Events" to tell process "Flip" to click menu bar item 1 of menu bar 1' >/dev/null 2>&1
}

# ---------------------------------------------------------------- it is running

echo
echo "Startup"
"$DRIVER" await "event tap running" 25000
check "Flip is running" "1" "$(pgrep -f 'Flip.app/Contents/MacOS/Flip' | wc -l | tr -d ' ')"

# The rest of the launch lines are already there by now, so these cost nothing.
"$DRIVER" await "watching [0-9]+ applications" 5000
logged "accessibility: granted"    && pass "Accessibility is granted"    || fail "Accessibility is granted"
logged "screen recording: granted" && pass "Screen Recording is granted" || fail "Screen Recording is granted"
logged "event tap running"         && pass "The event tap started"       || fail "The event tap started"
logged "watching [0-9]+ applications" && pass "The window store is watching applications" \
    || fail "The window store is watching applications"

# ------------------------------------------------------------------- the switcher

echo
echo "Switching"
mark
"$DRIVER" hold option wait 300 key tab await "overlay shown" 4000
shoot overlay
logged "opened to [0-9]+ windows" && pass "The grid opens" || fail "The grid opens"
logged "overlay shown"            && pass "The overlay is drawn" || fail "The overlay is drawn"
[ -n "$(overlay_id)" ] && pass "The panel is on screen" || fail "The panel is on screen"
"$DRIVER" release await "focusing " 3000
logged "focusing "                && pass "Releasing the leader focuses a window" \
    || fail "Releasing the leader focuses a window"

# Escape must not switch, and "did not happen" cannot be polled for — so this one
# keeps a real wait, long enough that a focus would have been logged by now.
mark
"$DRIVER" hold option wait 300 key tab await "overlay shown" 4000 key escape wait 500 release wait 500
logged "opened to [0-9]+ windows" && pass "Escape: the grid opened first" || fail "Escape: the grid opened first"
if logged "focusing "; then fail "Escape gives up without switching"; else pass "Escape gives up without switching"; fi

# A release inside the delay must switch without ever drawing the panel. The
# grace after the focus lands is what makes the negative worth asserting: by then
# the overlay was due 400 ms ago and never came.
mark
"$DRIVER" hold option wait 200 key tab wait 60 release await "focusing " 3000 wait 400
logged "focusing " && pass "A quick tap switches" || fail "A quick tap switches"
if logged "overlay shown"; then fail "A quick tap draws nothing"; else pass "A quick tap draws nothing"; fi

# ----------------------------------------------------------------------- the mouse

echo
echo "Mouse"
mark
"$DRIVER" hold option wait 300 key tab await "overlay shown" 4000
read -r _ px py pw ph <<<"$("$DRIVER" awaitwindow Flip 500 2000)"
COUNT=$(since | grep -oE "opened to [0-9]+ windows" | tail -1 | grep -oE "[0-9]+")
if [ -n "${pw:-}" ] && [ -n "${COUNT:-}" ]; then
    read -r tx ty <<<"$("$DRIVER" tile 0 "$COUNT" "$px" "$py" "$pw" "$ph")"
    "$DRIVER" move "$tx" "$ty" wait 300 click "$tx" "$ty" await "focusing " 3000
    logged "focusing " && pass "Clicking a tile commits it" || fail "Clicking a tile commits it"
else
    fail "Clicking a tile commits it" "no panel to click"
fi
"$DRIVER" release wait 200

# ---------------------------------------------------------------------- raising

# AltTab's most reported bug is selecting a window whose application then never
# comes forward, and Electron applications are the usual culprits. Flip logs what
# it meant to focus, so this compares intent against what actually happened and
# needs no idea of the grid's order beforehand.
echo
echo "Raising"
mark
"$DRIVER" hold option wait 300 key tab await "overlay shown" 4000 key escape release wait 300
COUNT=$(since | grep -oE "opened to [0-9]+ windows" | tail -1 | grep -oE "[0-9]+")

RAISE_MISMATCH=0
RAISE_TRIED=0
if [ -n "${COUNT:-}" ] && [ "$COUNT" -ge 2 ]; then
    for _ in $(seq 1 "$COUNT"); do
        mark
        # Always the least recently used tile, so committing it rotates the walk
        # through every application. COUNT-2 presses, because the grid opens on
        # index 1 and moving wraps: COUNT-1 would land back on the one just taken.
        # Moving the selection is in-process state with no window server in the
        # way, so the pause between presses only has to outlast the event tap.
        ARGS=(hold option wait 300 key tab await "opened to [0-9]+ windows" 4000)
        for _ in $(seq 3 "$COUNT"); do ARGS+=(key right wait 80); done
        ARGS+=(release await "focusing " 4000)
        "$DRIVER" "${ARGS[@]}"

        INTENDED=$(since | grep -oE "focusing [^—]+ —" | tail -1 | sed 's/^focusing //; s/ —$//' | xargs)
        [ -z "$INTENDED" ] && continue
        RAISE_TRIED=$((RAISE_TRIED + 1))
        # Waits for the application to arrive rather than assuming a fixed moment
        # is late enough. A timeout here is the failure it always was.
        if [ "$("$DRIVER" awaitfront "$INTENDED" 3000)" != "yes" ]; then
            RAISE_MISMATCH=$((RAISE_MISMATCH + 1))
            printf '      %s was chosen but did not come forward\n' "$INTENDED"
        fi
    done
fi
check "Every window chosen comes to the front ($RAISE_TRIED tried)" "0" "$RAISE_MISMATCH"

# ------------------------------------------------------------------ window actions

echo
echo "Window actions"
open ~ >/dev/null 2>&1
# Measured through accessibility: with Stage Manager on, the window server
# reports a parked window as a 200 point miniature and the arrangement cannot be
# measured at all. Flip writes the geometry through accessibility anyway.
#
# Each step waits for the width to actually change rather than for a moment by
# which it ought to have.
#
# Waiting for the window is the window server's job, not accessibility's: with no
# Finder window open, accessibility still answers — with the desktop, 5120 points
# wide — so anything watching for "a window exists" would be satisfied before one
# did. The window server leaves the desktop out and says nothing until the real
# window is there.
"$DRIVER" awaitwindow Finder 300 10000 >/dev/null

# The half move is the one step here that cannot be watched for, so it is the one
# step that still sleeps. Watching would mean watching the width, and the left
# half and the right half are the same width — a window already sitting on one of
# them changes nothing measurable by moving to the other. It only sets the
# baseline anyway; the two that carry the check follow.
"$DRIVER" chord control+option left wait 400
read -r _ _ half_w _ <<<"$("$DRIVER" axwindow Finder)"
"$DRIVER" chord control+option return
read -r _ _ full_w _ <<<"$("$DRIVER" awaitax Finder gt "${half_w:-0}" 4000)"
"$DRIVER" chord control+option return
read -r _ _ back_w _ <<<"$("$DRIVER" awaitax Finder lt "${full_w:-0}" 4000)"

if [ -n "${half_w:-}" ] && [ -n "${full_w:-}" ] && [ "$full_w" -gt "$half_w" ]; then
    pass "Filling the screen widens the window"
else
    fail "Filling the screen widens the window" "half ${half_w:-?}, full ${full_w:-?}"
fi
check "Filling again puts it back" "${half_w:-}" "${back_w:-}"

# -------------------------------------------------------------------- the menu bar

echo
echo "Menu bar"
ITEMS=$(osascript -e 'tell application "System Events" to tell process "Flip" to get name of menu items of menu 1 of menu bar item 1 of menu bar 1' 2>/dev/null)
osascript -e 'tell application "System Events" to key code 53' >/dev/null 2>&1
for item in "Settings…" "About Flip" "Copy Diagnostics" "Quit Flip" "Pause"; do
    case "$ITEMS" in
        *"$item"*) pass "The menu offers $item" ;;
        *) fail "The menu offers $item" "menu was: $ITEMS" ;;
    esac
done

echo "==> Copying diagnostics"
printf 'smoke-marker' | pbcopy
# The menu ignores a click unless the process is frontmost first. Learned the
# hard way: without this the item is found but never activates.
osascript -e 'tell application "System Events" to tell process "Flip" to set frontmost to true' >/dev/null 2>&1
open_menu
click_menu_item "Copy Diagnostics"
# Polled rather than slept at, so the usual case costs a tenth of a second.
COPIED=""
for _ in $(seq 1 30); do
    case "$(pbpaste)" in *"Accessibility:"*) COPIED=yes; break ;; esac
    sleep 0.1
done
[ -n "$COPIED" ] && pass "Copy Diagnostics fills the clipboard" \
    || fail "Copy Diagnostics fills the clipboard" "clipboard was: $(pbpaste | head -1)"

# --------------------------------------------------------------------- the settings

echo
echo "Settings"
open_menu
click_menu_item "Settings…"
read -r sid _ _ sw sh <<<"$("$DRIVER" awaitwindow Flip 500 8000)"
if [ -n "${sw:-}" ] && [ "$sw" -ge 500 ]; then
    pass "The settings window opens"
    screencapture -x -o -l "$sid" "$OUT/settings.png" 2>/dev/null
else
    fail "The settings window opens" "found ${sw:-no} window"
fi
osascript -e 'tell application "System Events" to tell process "Flip" to click button 1 of window 1' >/dev/null 2>&1
