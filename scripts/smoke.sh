#!/usr/bin/env bash
#
# Everything about Flip that only a running Mac can answer. The unit tests cover
# the arithmetic; this covers the border with macOS, which is where every real
# bug in this project has been.
#
#   make smoke
#
# Nobody may touch the keyboard or the mouse while it runs: the switcher is held
# open by a modifier, and one real keystroke releases it. Takes about a minute.
#
# It works on a Finder window of its own rather than anything of yours, restores
# the clipboard, and leaves the settings as it found them.

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

pass() { PASSED=$((PASSED + 1)); printf '  \033[32m✓\033[0m %s\n' "$1"; }
fail() { FAILED=$((FAILED + 1)); printf '  \033[31m✗\033[0m %s\n' "$1"; [ $# -gt 1 ] && printf '      %s\n' "$2"; }

check() {   # description  expected  actual
    if [ "$2" = "$3" ]; then pass "$1"; else fail "$1" "expected '$2', got '$3'"; fi
}

# The log is the only window into what Flip decided. Restarted per step so a line
# from an earlier one cannot be mistaken for this one's.
start_log() {
    pkill -f "log stream.*dev.mxwnk.Flip" 2>/dev/null
    : > "$LOG"
    log stream --level debug --style compact --predicate 'subsystem == "dev.mxwnk.Flip"' \
        >> "$LOG" 2>&1 &
    LOGGER=$!
    sleep 1.5
}
stop_log() { kill "$LOGGER" 2>/dev/null; wait "$LOGGER" 2>/dev/null; }
logged()   { grep -qE "$1" "$LOG"; }

restore() {
    stop_log
    [ -f "$SETTINGS_BACKUP" ] && cp "$SETTINGS_BACKUP" "$SUPPORT/settings.json"
    [ -f "$CLIPBOARD_BACKUP" ] && pbcopy < "$CLIPBOARD_BACKUP"
    osascript -e 'tell application "Finder" to close every window' >/dev/null 2>&1
    echo
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

echo "==> Building the driver"
swiftc -O "$HERE/smoke/driver.swift" -o "$DRIVER" || { echo "driver would not build"; exit 1; }

echo "==> Installing and starting Flip"
(cd "$ROOT" && make install >/dev/null && make run >/dev/null) || { echo "install failed"; exit 1; }
sleep 6

# A pipeline into read runs in a subshell and loses the variable, so the here
# string is not a stylistic choice.
shoot() {
    read -r id _ <<<"$("$DRIVER" window Flip 500)"
    [ -n "${id:-}" ] && screencapture -x -o -l "$id" "$OUT/$1.png" 2>/dev/null
}
overlay_id() { "$DRIVER" window Flip 500 | cut -d' ' -f1; }

# ---------------------------------------------------------------- it is running

echo
echo "Startup"
start_log
sleep 2
check "Flip is running" "1" "$(pgrep -f 'Flip.app/Contents/MacOS/Flip' | wc -l | tr -d ' ')"
stop_log

start_log
(cd "$ROOT" && make stop >/dev/null 2>&1; make run >/dev/null 2>&1)
sleep 7
logged "accessibility: granted"    && pass "Accessibility is granted"    || fail "Accessibility is granted"
logged "screen recording: granted" && pass "Screen Recording is granted" || fail "Screen Recording is granted"
logged "event tap running"         && pass "The event tap started"       || fail "The event tap started"
logged "watching [0-9]+ applications" && pass "The window store is watching applications" \
    || fail "The window store is watching applications"
stop_log

# ------------------------------------------------------------------- the switcher

echo
echo "Switching"
start_log
"$DRIVER" hold option wait 300 key tab wait 900
shoot overlay
logged "opened to [0-9]+ windows" && pass "The grid opens" || fail "The grid opens"
logged "overlay shown"            && pass "The overlay is drawn" || fail "The overlay is drawn"
[ -n "$(overlay_id)" ] && pass "The panel is on screen" || fail "The panel is on screen"
"$DRIVER" release wait 800
logged "focusing "                && pass "Releasing the leader focuses a window" \
    || fail "Releasing the leader focuses a window"
stop_log

start_log
"$DRIVER" hold option wait 300 key tab wait 900 key escape wait 600 release wait 400
logged "opened to [0-9]+ windows" && pass "Escape: the grid opened first" || fail "Escape: the grid opened first"
if logged "focusing "; then fail "Escape gives up without switching"; else pass "Escape gives up without switching"; fi
stop_log

# A release inside the delay must switch without ever drawing the panel.
start_log
"$DRIVER" hold option wait 200 key tab wait 60 release wait 800
logged "focusing " && pass "A quick tap switches" || fail "A quick tap switches"
if logged "overlay shown"; then fail "A quick tap draws nothing"; else pass "A quick tap draws nothing"; fi
stop_log

# ----------------------------------------------------------------------- the mouse

echo
echo "Mouse"
start_log
"$DRIVER" hold option wait 300 key tab wait 900
read -r _ px py pw ph <<<"$("$DRIVER" window Flip 500)"
COUNT=$(grep -oE "opened to [0-9]+ windows" "$LOG" | tail -1 | grep -oE "[0-9]+")
if [ -n "${pw:-}" ] && [ -n "${COUNT:-}" ]; then
    read -r tx ty <<<"$("$DRIVER" tile 0 "$COUNT" "$px" "$py" "$pw" "$ph")"
    "$DRIVER" move "$tx" "$ty" wait 500 click "$tx" "$ty" wait 800
    logged "focusing " && pass "Clicking a tile commits it" || fail "Clicking a tile commits it"
else
    fail "Clicking a tile commits it" "no panel to click"
fi
"$DRIVER" release wait 400
stop_log

# ------------------------------------------------------------------ window actions

echo
echo "Window actions"
open ~ >/dev/null 2>&1
sleep 3
# Measured through accessibility: with Stage Manager on, the window server
# reports a parked window as a 200 point miniature and the arrangement cannot be
# measured at all. Flip writes the geometry through accessibility anyway.
"$DRIVER" chord control+option left wait 1200
read -r _ _ half_w _ <<<"$("$DRIVER" axwindow Finder)"
"$DRIVER" chord control+option return wait 1200
read -r _ _ full_w _ <<<"$("$DRIVER" axwindow Finder)"
"$DRIVER" chord control+option return wait 1200
read -r _ _ back_w _ <<<"$("$DRIVER" axwindow Finder)"

if [ -n "${half_w:-}" ] && [ -n "${full_w:-}" ] && [ "$full_w" -gt "$half_w" ]; then
    pass "Filling the screen widens the window"
else
    fail "Filling the screen widens the window" "half ${half_w:-?}, full ${full_w:-?}"
fi
check "Filling again puts it back" "$half_w" "${back_w:-}"

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
sleep 0.8
osascript -e 'tell application "System Events" to tell process "Flip" to click menu bar item 1 of menu bar 1' >/dev/null 2>&1
sleep 1.2
osascript -e 'tell application "System Events" to tell process "Flip" to click menu item "Copy Diagnostics" of menu 1 of menu bar item 1 of menu bar 1' >/dev/null 2>&1
sleep 1.5
case "$(pbpaste)" in
    *"Accessibility:"*) pass "Copy Diagnostics fills the clipboard" ;;
    *) fail "Copy Diagnostics fills the clipboard" "clipboard was: $(pbpaste | head -1)" ;;
esac

# --------------------------------------------------------------------- the settings

echo
echo "Settings"
osascript -e 'tell application "System Events" to tell process "Flip" to click menu bar item 1 of menu bar 1' >/dev/null 2>&1
sleep 1.2
osascript -e 'tell application "System Events" to tell process "Flip" to click menu item "Settings…" of menu 1 of menu bar item 1 of menu bar 1' >/dev/null 2>&1
sleep 2.5
read -r sid _ _ sw sh <<<"$("$DRIVER" window Flip 400)"
if [ -n "${sw:-}" ] && [ "$sw" -ge 500 ]; then
    pass "The settings window opens"
    screencapture -x -o -l "$sid" "$OUT/settings.png" 2>/dev/null
else
    fail "The settings window opens" "found ${sw:-no} window"
fi
osascript -e 'tell application "System Events" to tell process "Flip" to click button 1 of window 1' >/dev/null 2>&1
