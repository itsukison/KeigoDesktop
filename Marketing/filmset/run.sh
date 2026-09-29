#!/bin/bash
# Open the film set in a chromeless, fullscreen Chrome window.
#
#   ./run.sh                 light theme, empty composer
#   ./run.sh genz            the line already in the box (for framing)
#   ./run.sh dark-guide-hud  dark theme + 9:16 crop guide + HUD
#   ./run.sh ja              the Japanese set (slack-ja.html)
#   ./run.sh ja genz         both
#
# --app kills the address bar, which is the one thing that would give the mockup
# away: a file:///Users/itsuki/... path on screen ends the illusion instantly.
# The throwaway profile keeps bookmarks bars, extensions and profile pills out of
# the frame; it also means the first launch has no restore-tabs bubble.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# first argument may name the language: ./run.sh ja genz
FILE="slack.html"
if [ "${1:-}" = "ja" ]; then FILE="slack-ja.html"; shift; fi
if [ "${1:-}" = "en" ]; then shift; fi

PAGE="file://$HERE/$FILE${1:+#$1}"
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"

[ -x "$CHROME" ] || { echo "Chrome not found at $CHROME"; exit 1; }

exec "$CHROME" \
  --app="$PAGE" \
  --start-fullscreen \
  --user-data-dir="/tmp/keigobutton-filmset-profile" \
  --no-first-run \
  --no-default-browser-check \
  --disable-features=Translate,MediaRouter \
  --hide-crash-restore-bubble \
  >/dev/null 2>&1
