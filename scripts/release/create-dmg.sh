#!/bin/bash

set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "usage: $0 /path/to/KeigoButton.app /path/to/KeigoButton.dmg" >&2
  exit 64
fi

APP_PATH="$1"
OUTPUT_PATH="$2"
APP_NAME="$(basename "$APP_PATH")"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BACKGROUND_PATH="$SCRIPT_DIR/dmg-background.png"

[[ -d "$APP_PATH" ]] || { echo "application not found: $APP_PATH" >&2; exit 1; }
[[ "$APP_NAME" == "KeigoButton.app" ]] || {
  echo "expected KeigoButton.app, got $APP_NAME" >&2
  exit 1
}
[[ -f "$BACKGROUND_PATH" ]] || { echo "background not found: $BACKGROUND_PATH" >&2; exit 1; }

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/keigobutton-dmg.XXXXXX")"
STAGING_DIR="$WORK_DIR/staging"
MOUNT_DIR="$WORK_DIR/mount"
RW_DMG="$WORK_DIR/KeigoButton-rw.dmg"
MOUNTED=false

cleanup() {
  if [[ "$MOUNTED" == true ]]; then
    hdiutil detach "$MOUNT_DIR" -quiet || true
  fi
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

mkdir -p "$STAGING_DIR/.background" "$MOUNT_DIR" "$(dirname "$OUTPUT_PATH")"
ditto "$APP_PATH" "$STAGING_DIR/$APP_NAME"
ln -s /Applications "$STAGING_DIR/Applications"
cp "$BACKGROUND_PATH" "$STAGING_DIR/.background/background.png"

hdiutil create \
  -volname "敬語ボタン" \
  -srcfolder "$STAGING_DIR" \
  -format UDRW \
  -fs HFS+ \
  -ov \
  "$RW_DMG" >/dev/null

hdiutil attach "$RW_DMG" \
  -readwrite \
  -noverify \
  -noautoopen \
  -mountpoint "$MOUNT_DIR" >/dev/null
MOUNTED=true

osascript <<APPLESCRIPT
set mountPath to "$MOUNT_DIR"
set mountedFolder to POSIX file mountPath as alias

tell application "Finder"
  open mountedFolder
  set installerWindow to container window of mountedFolder
  set current view of installerWindow to icon view
  set toolbar visible of installerWindow to false
  set statusbar visible of installerWindow to false
  set pathbar visible of installerWindow to false
  set sidebar width of installerWindow to 0
  set bounds of installerWindow to {120, 120, 840, 560}

  set viewOptions to icon view options of installerWindow
  set arrangement of viewOptions to not arranged
  set icon size of viewOptions to 120
  set text size of viewOptions to 13
  set background picture of viewOptions to file ".background:background.png" of mountedFolder

  set position of item "KeigoButton.app" of mountedFolder to {190, 245}
  set position of item "Applications" of mountedFolder to {530, 245}

  update mountedFolder without registering applications
  delay 2
  close installerWindow
end tell
APPLESCRIPT

sync
hdiutil detach "$MOUNT_DIR" -quiet
MOUNTED=false

rm -f "$OUTPUT_PATH"
hdiutil convert "$RW_DMG" \
  -format UDZO \
  -imagekey zlib-level=9 \
  -ov \
  -o "$OUTPUT_PATH" >/dev/null

echo "Created styled installer: $OUTPUT_PATH"
