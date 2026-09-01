#!/bin/bash
# Capture what the app is doing when it freezes.
#
#   ./scripts/capture-freeze.sh            # a booted simulator
#   ./scripts/capture-freeze.sh --phone    # the connected iPhone
#
# Reproduce the freeze while it runs, wait ~10s, then press Ctrl-C.
# It writes /private/tmp/ourapp-freeze.log and prints a spindump of the
# main thread, which shows exactly what it is stuck in.
set -uo pipefail
cd "$(dirname "$0")/.."
BUNDLE=com.jadeni77.OurApp
LOG=/private/tmp/ourapp-freeze.log
rm -f "$LOG"

if [ "${1:-}" = "--phone" ]; then
  UDID=$(xcrun xctrace list devices 2>/dev/null \
    | sed -n '/^== Devices ==/,/^== Devices Offline ==/p' \
    | grep -oE '\(00[0-9A-F]{6}-[0-9A-F]{16}\)' | head -1 | tr -d '()')
  [ -n "$UDID" ] || { echo "No iPhone found."; exit 1; }
  echo "Recording from your phone. Reproduce the freeze, then Ctrl-C."
  xcrun devicectl device process launch --device "$UDID" --console "$BUNDLE" 2>&1 | tee "$LOG"
  exit 0
fi

echo "Recording from the booted simulator. Reproduce the freeze, then Ctrl-C."
xcrun simctl launch --console-pty booted "$BUNDLE" 2>&1 | tee "$LOG" &
LAUNCH=$!
# A stuck main thread shows up in a sample far more clearly than in logs:
# logs tell you what happened last, a sample tells you where it *is*.
sleep 12
PID=$(xcrun simctl spawn booted launchctl list 2>/dev/null | grep jadeni77 | awk '{print $1}')
if [ -n "${PID:-}" ] && [ "$PID" != "-" ]; then
  echo; echo "=== sampling the app (5s) ==="
  sample "$PID" 5 -file /private/tmp/ourapp-sample.txt >/dev/null 2>&1 \
    && grep -A 40 "Thread.*main\|1000 Thread" /private/tmp/ourapp-sample.txt | head -45
fi
wait $LAUNCH 2>/dev/null
