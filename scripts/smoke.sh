#!/usr/bin/env bash
#
# Everything about Flip that only a running Mac can answer. The unit tests cover
# the arithmetic; this covers the border with macOS, which is where every real
# bug in this project has been.
#
#   make smoke
#
# Hands off the keyboard and mouse for the ~20s it runs: one real keystroke
# releases the modifier holding the switcher open. Uses a Finder window of its
# own, restores the clipboard and the settings.
#
# Nothing sleeps for a fixed interval if it can watch for the thing instead —
# hence `await`, `awaitax`, `awaitwindow`. Their ceilings are generous because
# reaching one is a failure, not the normal course.

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

# The log is the only window into what Flip decided. One stream for the whole
# suite, one byte mark per step, so an earlier step's line cannot be mistaken for
# this one's. Restarting it per step cost 1.5s each time and lost whatever Flip
# logged in the gap.
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

# Before the build, so the compiler's second is also the stream's attach time.
# Flip starts only once both are ready, so no launch line is missed.
start_log

echo "==> Building the driver"
swiftc -O "$HERE/smoke/driver.swift" -o "$DRIVER" || { echo "driver would not build"; exit 1; }

# The rest of the ~1.5s attach. Not watchable: `log` prints its header with the
# first event, so on an idle subsystem waiting for it hangs. Once up, a line
# reaches the file inside 650ms — which is what makes the polling below work.
sleep 0.6

echo "==> Installing and starting Flip"
mark
# `run` depends on `install`, which stops any running copy: one of each, not three.
(cd "$ROOT" && make run >/dev/null) || { echo "install failed"; exit 1; }

# A pipeline into read runs in a subshell and loses the variable, hence the here string.
shoot() {
    read -r id _ <<<"$("$DRIVER" awaitwindow Flip 500 2000)"
    [ -n "${id:-}" ] && screencapture -x -o -l "$id" "$OUT/$1.png" 2>/dev/null
}
overlay_id() { "$DRIVER" window Flip 500 | cut -d' ' -f1; }

# Retried, not slept at: how long the menu takes to render is not knowable.
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

# Already there by now, so this costs nothing.
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

# "Did not happen" cannot be polled for, so this one keeps a real wait.
mark
"$DRIVER" hold option wait 300 key tab await "overlay shown" 4000 key escape wait 500 release wait 500
logged "opened to [0-9]+ windows" && pass "Escape: the grid opened first" || fail "Escape: the grid opened first"
if logged "focusing "; then fail "Escape gives up without switching"; else pass "Escape gives up without switching"; fi

# A release inside the delay switches without drawing. The grace after the focus
# is what makes the negative worth asserting: the overlay was due 400ms ago.
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

# AltTab's most reported bug: a chosen window whose application never comes
# forward. Flip logs what it meant to focus, so intent is compared against what
# happened — no need to know the grid's order beforehand.
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
        # The least recently used tile, so committing it walks every application.
        # COUNT-2 presses: the grid opens on index 1 and moving wraps, so COUNT-1
        # lands back on the one just taken. Selection is in-process state, so the
        # pause only has to outlast the event tap.
        ARGS=(hold option wait 300 key tab await "opened to [0-9]+ windows" 4000)
        for _ in $(seq 3 "$COUNT"); do ARGS+=(key right wait 80); done
        ARGS+=(release await "focusing " 4000)
        "$DRIVER" "${ARGS[@]}"

        INTENDED=$(since | grep -oE "focusing [^—]+ —" | tail -1 | sed 's/^focusing //; s/ —$//' | xargs)
        [ -z "$INTENDED" ] && continue
        RAISE_TRIED=$((RAISE_TRIED + 1))
        # Waits for the application rather than assuming a moment is late enough.
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
# Measured through accessibility: with Stage Manager on, the window server calls
# a parked window a 200 point miniature. But waiting for one is the window
# server's job — accessibility answers with the desktop when none is open.
"$DRIVER" awaitwindow Finder 300 10000 >/dev/null

# The one step that still sleeps: left and right half are the same width, so a
# window already on one changes nothing measurable by moving to the other. It
# only sets the baseline; the two steps that carry the check follow.
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
# The menu ignores a click unless the process is frontmost: without this the
# item is found but never activates.
osascript -e 'tell application "System Events" to tell process "Flip" to set frontmost to true' >/dev/null 2>&1
open_menu
click_menu_item "Copy Diagnostics"
# Polled, so the usual case costs a tenth of a second.
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
