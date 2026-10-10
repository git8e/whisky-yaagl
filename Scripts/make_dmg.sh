#!/bin/bash
#
# Builds a distributable DMG for whisky-yaagl with the classic
# drag-to-Applications layout: the app on the left, an Applications shortcut on
# the right, an arrow background and a volume icon.
#
# Requires a built .app (run `make app` first, or pass a path). The Finder
# layout step is best-effort: if the terminal is not allowed to control Finder,
# or Finder is not running, the DMG is still produced (without the pretty
# background).
#
# Usage: Scripts/make_dmg.sh [path-to.app] [version]
#        (defaults: build/whisky-yaagl.app and "1.0")

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="${1:-$ROOT/build/whisky-yaagl.app}"
VERSION="${2:-1.0}"
APP_BUNDLE="$(basename "$APP")"          # e.g. whisky-yaagl.app
APP_NAME="${APP_BUNDLE%.app}"            # e.g. whisky-yaagl (for file names)
BUILD="$ROOT/build"
STAGE="$BUILD/dmg-staging"
RW_DMG="$BUILD/$APP_NAME-rw.dmg"
DMG="$BUILD/$APP_NAME-$VERSION.dmg"
BG="$BUILD/dmg-background.tiff"
VOLNAME="Whisky YAAGL"

if [ ! -d "$APP" ]; then
    echo "error: $APP not found. Run 'make app' first." >&2
    exit 1
fi

mkdir -p "$BUILD"

echo "==> Drawing DMG background"
swift "$ROOT/Scripts/make_dmg_background.swift" "$BG" >/dev/null

echo "==> Staging DMG contents"
rm -rf "$STAGE"
mkdir -p "$STAGE/.background"
ditto "$APP" "$STAGE/$APP_BUNDLE"
ln -s /Applications "$STAGE/Applications"
cp "$BG" "$STAGE/.background/background.tiff"

# Custom volume icon: reuse the app's own compiled icon when available.
if [ -f "$APP/Contents/Resources/AppIcon.icns" ]; then
    cp "$APP/Contents/Resources/AppIcon.icns" "$STAGE/.VolumeIcon.icns"
else
    echo "warning: $APP/Contents/Resources/AppIcon.icns not found; volume icon skipped." >&2
fi

rm -f "$DMG" "$RW_DMG"

echo "==> Creating writable image"
hdiutil create -srcfolder "$STAGE" -volname "$VOLNAME" -fs HFS+ -format UDRW -ov "$RW_DMG" >/dev/null

MOUNTED=0
MOUNT=""
cleanup() {
    if [ "$MOUNTED" = "1" ] && [ -n "$MOUNT" ]; then
        hdiutil detach "$MOUNT" >/dev/null 2>&1 || hdiutil detach "$MOUNT" -force >/dev/null 2>&1 || true
        MOUNTED=0
    fi
}
trap cleanup EXIT

# Runs a command with a timeout (macOS ships no `timeout`), so a Finder
# automation permission prompt can never hang the build.
run_with_timeout() {
    local secs="$1"; shift
    "$@" &
    local pid=$!
    local waited=0
    while kill -0 "$pid" 2>/dev/null; do
        if [ "$waited" -ge "$secs" ]; then
            kill -TERM "$pid" 2>/dev/null || true
            sleep 1
            kill -KILL "$pid" 2>/dev/null || true
            return 124
        fi
        sleep 1
        waited=$((waited + 1))
    done
    wait "$pid"
}

echo "==> Mounting image"
# Mount at the default /Volumes/<name> so the volume-relative background
# reference in .DS_Store resolves for everyone who opens the finished DMG.
hdiutil detach "/Volumes/$VOLNAME" >/dev/null 2>&1 || true
ATTACH_OUT="$(hdiutil attach "$RW_DMG" -nobrowse -readwrite)"
MOUNT="$(printf '%s\n' "$ATTACH_OUT" | awk '/Apple_HFS/{print substr($0, index($0,$3))}' | tail -1)"
if [ -z "$MOUNT" ] || [ ! -d "$MOUNT" ]; then
    echo "error: could not mount $RW_DMG" >&2
    exit 1
fi
MOUNTED=1

APPLESCRIPT="$(mktemp)"
cat > "$APPLESCRIPT" <<APPLESCRIPT
tell application "Finder"
    tell disk "$VOLNAME"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {100, 100, 760, 548}
        set viewOptions to the icon view options of container window
        set arrangement of viewOptions to not arranged
        set icon size of viewOptions to 120
        set background picture of viewOptions to file ".background:background.tiff"
        set position of item "$APP_BUNDLE" of container window to {165, 205}
        set position of item "Applications" of container window to {495, 205}
        update without registering applications
        delay 1
    end tell
end tell
APPLESCRIPT

echo "==> Applying Finder layout (background, icon positions)"
# Setting a DMG background through Finder is occasionally flaky (Finder may
# drop the background alias before it has flushed .DS_Store), so verify the
# result and retry a few times.
layout_ok=0
for attempt in 1 2 3; do
    if run_with_timeout 20 osascript "$APPLESCRIPT" >/dev/null 2>&1; then
        sync
        sleep 1
        if strings "$MOUNT/.DS_Store" 2>/dev/null | grep -q "background.tiff"; then
            layout_ok=1
            break
        fi
    fi
    echo "    layout attempt $attempt did not stick, retrying…"
    sleep 1
done
rm -f "$APPLESCRIPT"

if [ "$layout_ok" != "1" ]; then
    echo "warning: could not apply the Finder background/icon layout (DMG is still usable)." >&2
fi

# Custom volume icon (needs SetFile from the Xcode command line tools).
SetFile -a C "$MOUNT" >/dev/null 2>&1 || true

sync
sleep 1
cleanup
trap - EXIT

# Wait for the mount point to be released; otherwise hdiutil convert can fail
# with "Resource temporarily unavailable" (a leftover diskimages helper may
# still hold the writable image).
for _ in 1 2 3 4 5 6 7 8 9 10; do
    [ -d "/Volumes/$VOLNAME" ] || break
    sleep 1
done

echo "==> Compressing to $DMG"
convert_ok=0
for attempt in 1 2 3 4 5; do
    if hdiutil convert "$RW_DMG" -format UDZO -imagekey zlib-level=9 -o "$DMG" >/dev/null 2>&1; then
        convert_ok=1
        break
    fi
    echo "    convert attempt $attempt failed, retrying…"
    hdiutil detach "/Volumes/$VOLNAME" >/dev/null 2>&1 || true
    sleep 3
done
if [ "$convert_ok" != "1" ]; then
    echo "error: hdiutil convert failed: $RW_DMG" >&2
    exit 1
fi

rm -f "$RW_DMG"
rm -rf "$STAGE" "$BG"

echo "==> Done: $DMG"
