#!/usr/bin/env bash
#
# Packages build/Flip-<version>.dmg with a background, placed icons and a volume
# icon.
#
#   scripts/make-dmg.sh <version> <identity>
#   scripts/make-dmg.sh <version> <identity> --layout
#
# The window layout lives in a `.DS_Store` that only Finder can write, and
# driving Finder needs a desktop session — which a build runner does not reliably
# have. So the layout is produced once with --layout and committed, the same way
# the application icon is committed rather than drawn during a build. Everything
# else here is hdiutil and cp, which are happy headless.

set -euo pipefail

VERSION="$1"
IDENTITY="$2"
LAYOUT="${3:-}"

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(dirname "$HERE")"
NAME="Flip"
VOLUME="/Volumes/$NAME"
STAGING="$ROOT/build/dmg"
WRITABLE="$ROOT/build/rw.dmg"
OUTPUT="$ROOT/build/$NAME-$VERSION.dmg"
LAYOUT_FILE="$ROOT/resources/dmg/DS_Store"

# Has to agree with scripts/make-dmg-background.swift, or the arrow drawn on the
# backdrop points somewhere the icons are not.
WINDOW_WIDTH=660
WINDOW_HEIGHT=400
# Finder measures the window, not the area the backdrop gets: the title bar takes
# 31 points off the top and the status bar 28 off the bottom. Measured, because
# guessing them clips the line along the bottom edge of the image.
WINDOW_CHROME=59
ICON_SIZE=112
APP_X=170
APP_Y=205
LINK_X=490
LINK_Y=205

cleanup() {
    hdiutil detach "$VOLUME" -quiet 2>/dev/null || true
    rm -rf "$STAGING" "$WRITABLE"
}
trap cleanup EXIT

# An earlier image of the same name may still be attached — the released one, if
# somebody opened it to look. Mounting over it lands the writable copy somewhere
# else and every step after that works on the wrong, read-only volume.
hdiutil detach "$VOLUME" -quiet 2>/dev/null || true

echo "==> Staging"
rm -rf "$STAGING"
mkdir -p "$STAGING/.background"
cp -R "$ROOT/build/$NAME.app" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
cp "$ROOT/resources/dmg-background.tiff" "$STAGING/.background/background.tiff"
cp "$ROOT/resources/$NAME.icns" "$STAGING/.VolumeIcon.icns"

if [ "$LAYOUT" != "--layout" ]; then
    test -f "$LAYOUT_FILE" || { echo "no layout at $LAYOUT_FILE; run with --layout once"; exit 1; }
    cp "$LAYOUT_FILE" "$STAGING/.DS_Store"
fi

echo "==> Writable image"
rm -f "$WRITABLE"
# Room to spare: Finder rewrites .DS_Store in place and a tight image fails.
SIZE=$(( $(du -sm "$STAGING" | cut -f1) + 30 ))
hdiutil create -volname "$NAME" -srcfolder "$STAGING" -fs HFS+ \
    -format UDRW -size "${SIZE}m" -quiet "$WRITABLE"
hdiutil attach "$WRITABLE" -quiet -nobrowse -noautoopen

# Marks the volume as carrying its own icon; without it .VolumeIcon.icns is an
# ordinary file that nothing looks at. SetFile ships with the command line tools,
# and a build runner without them should still produce a usable disk image — the
# icon is decoration, not the point.
SetFile -a C "$VOLUME" || echo "    no SetFile; the volume keeps the generic icon"

if [ "$LAYOUT" = "--layout" ]; then
    echo "==> Arranging the window through Finder"
    osascript <<APPLESCRIPT
tell application "Finder"
    tell disk "$NAME"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set the bounds of container window to {200, 120, $((200 + WINDOW_WIDTH)), $((120 + WINDOW_HEIGHT + WINDOW_CHROME))}
        set options to the icon view options of container window
        set arrangement of options to not arranged
        set icon size of options to $ICON_SIZE
        set text size of options to 12
        set background picture of options to file ".background:background.tiff"
        set position of item "$NAME.app" of container window to {$APP_X, $APP_Y}
        set position of item "Applications" of container window to {$LINK_X, $LINK_Y}
        update without registering applications
        close
    end tell
end tell
APPLESCRIPT
    # Finder writes .DS_Store lazily; give it a moment before taking a copy.
    sleep 3
    sync
    mkdir -p "$(dirname "$LAYOUT_FILE")"
    cp "$VOLUME/.DS_Store" "$LAYOUT_FILE"
    echo "==> Layout captured to ${LAYOUT_FILE#"$ROOT"/}"
fi

hdiutil detach "$VOLUME" -quiet

echo "==> Compressing"
rm -f "$OUTPUT"
hdiutil convert "$WRITABLE" -format UDZO -quiet -o "$OUTPUT"
codesign --force --sign "$IDENTITY" "$OUTPUT"

echo "==> Packaged ${OUTPUT#"$ROOT"/}"
