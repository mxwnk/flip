#!/usr/bin/env bash
#
# Stages a reproducible scene, performs the choreography, and puts everything
# back. Run it once without --record to watch the sequence before committing it
# to a file.
#
#   scripts/demo.sh [scene] [--record]
#
# Staging does two things: every other application is excluded, so no private
# window wanders into frame, and the demonstration applications are opened by
# the script, so every take is the same take.
#
# Hands off the keyboard: a real keystroke releases the modifier mid-sequence.

set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(dirname "$HERE")"
SUPPORT="$HOME/Library/Application Support/Flip"
BACKUP="$(mktemp -d)"

APPS=("Pages" "Numbers" "Safari" "Calculator")

# Two temporary bindings: the jump scene presses the first, the arrange scene
# the second, so it lands on a window worth resizing.
JUMP_KEY="c"
JUMP_BUNDLE="com.apple.calculator"
ARRANGE_KEY="s"
ARRANGE_BUNDLE="com.apple.Safari"

SCENE=""
RECORD=false
for argument in "$@"; do
    case "$argument" in
        --record) RECORD=true ;;
        *) SCENE="$argument" ;;
    esac
done

restore() {
    echo "==> Restoring your configuration"
    [ -f "$BACKUP/settings.json" ] && cp "$BACKUP/settings.json" "$SUPPORT/settings.json"
    [ -f "$BACKUP/bindings.json" ] && cp "$BACKUP/bindings.json" "$SUPPORT/bindings.json"
    rm -rf "$BACKUP"

    osascript -e 'tell application "System Events" to tell process "Flip" to click menu item "Quit Flip" of menu 1 of menu bar item 1 of menu bar 1' >/dev/null 2>&1 || true
    sleep 2
    (cd "$ROOT" && make run >/dev/null 2>&1) || true
    sleep 3

    python3 - "$SUPPORT" <<'PY'
import json, sys
support = sys.argv[1]
settings = json.load(open(f"{support}/settings.json"))
bindings = json.load(open(f"{support}/bindings.json"))
print(f"    exclusions: {settings['excludedBundleIDs']}")
print(f"    bindings:   {len(bindings)}")
PY
}
trap restore EXIT

echo "==> Backing up"
cp "$SUPPORT/settings.json" "$BACKUP/settings.json"
cp "$SUPPORT/bindings.json" "$BACKUP/bindings.json"

echo "==> Opening the demonstration applications"
for app in "${APPS[@]}"; do open -a "$app"; done
sleep 3

echo "==> Staging: everything else excluded, one binding added"
osascript -e 'tell application "System Events" to tell process "Flip" to click menu item "Quit Flip" of menu 1 of menu bar item 1 of menu bar 1' >/dev/null 2>&1 || true
sleep 2

python3 - "$SUPPORT" "$JUMP_KEY" "$JUMP_BUNDLE" "$ARRANGE_KEY" "$ARRANGE_BUNDLE" "${APPS[@]}" <<'PY'
import json, subprocess, sys

support = sys.argv[1]
temporary = [(sys.argv[2], sys.argv[3]), (sys.argv[4], sys.argv[5])]
names = set(sys.argv[6:])

listing = subprocess.run(["swift", "-e", '''
import AppKit
for a in NSWorkspace.shared.runningApplications where a.activationPolicy == .regular {
    if let b = a.bundleIdentifier, let n = a.localizedName { print("\\(n)\\t\\(b)") }
}'''], capture_output=True, text=True).stdout.splitlines()

keep, excluded = set(), set()
for line in listing:
    name, _, identifier = line.partition("\t")
    (keep if name in names else excluded).add(identifier)

settings = json.load(open(f"{support}/settings.json"))
settings["excludedBundleIDs"] = sorted(excluded)
json.dump(settings, open(f"{support}/settings.json", "w"), indent=2, sort_keys=True)

bindings = json.load(open(f"{support}/bindings.json"))
taken = {key for key, _ in temporary}
bindings = [b for b in bindings if b["key"] not in taken]
bindings += [{"bundleID": bundle, "key": key, "usesLeader": True}
             for key, bundle in temporary]
json.dump(bindings, open(f"{support}/bindings.json", "w"), indent=2, sort_keys=True)

print(f"    showing {len(keep)} applications, hiding {len(excluded)}")
PY

(cd "$ROOT" && make run >/dev/null 2>&1)
sleep 4

# Only worth recording if every application put a window up: Pages and Numbers
# open onto a template chooser, which is not a window worth filming.
echo "==> Checking each application has a window"
python3 - "${APPS[@]}" <<'PY'
import subprocess, sys

wanted = sys.argv[1:]
listing = subprocess.run(["swift", "-e", """
import CoreGraphics
let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
let all = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] ?? []
for w in all where (w[kCGWindowLayer as String] as? Int) == 0 {
    if let owner = w[kCGWindowOwnerName as String] as? String { print(owner) }
}"""], capture_output=True, text=True).stdout.split()

for name in wanted:
    print(f"    {name}: {'window' if name in listing else 'NO WINDOW'}")
missing = [n for n in wanted if n not in listing]
if missing:
    print(f"    Open a document in {', '.join(missing)} first.")
PY

if $RECORD; then
    OUTPUT="$ROOT/build/demo.mov"
    mkdir -p "$ROOT/build"
    rm -f "$OUTPUT"
    echo "==> Recording to $OUTPUT"
    screencapture -v -V 22 "$OUTPUT" &
    RECORDER=$!
    sleep 1
fi

echo "==> Performing — hands off the keyboard"
swift "$HERE/demo-choreography.swift" ${SCENE:+"$SCENE"}

if $RECORD; then
    wait $RECORDER 2>/dev/null || true
    echo "==> Recorded. Turn it into a GIF with:"
    echo "    ffmpeg -i build/demo.mov -vf 'fps=15,scale=1200:-1:flags=lanczos,split[a][b];[a]palettegen[p];[b][p]paletteuse' -loop 0 docs/demo.gif"
fi
