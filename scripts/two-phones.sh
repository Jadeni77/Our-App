#!/bin/bash
# Two simulators, one folder, watching records and photos replicate.
#
# Nothing here needs an Apple Developer account: the "cloud" is a directory on
# this Mac and `-fakeCloud` is a DEBUG-only launch argument (slice A/B).
#
#   ./scripts/two-phones.sh            # fresh start, phone A seeded
#   ./scripts/two-phones.sh --keep     # keep whatever is already in the cloud
#   ./scripts/two-phones.sh --lan      # Bonjour + TCP instead of a folder
#   ./scripts/two-phones.sh --coop     # two simulators, paired, ready for co-op
set -euo pipefail
cd "$(dirname "$0")/.."

CLOUD=${OURAPP_CLOUD:-/private/tmp/ourapp-cloud}
PHONE_A=${OURAPP_PHONE_A:-"iPhone 17 Pro"}
PHONE_B=${OURAPP_PHONE_B:-"iPhone 17"}
BUNDLE=com.jadeni77.OurApp

udid() { xcrun simctl list devices available | grep -m1 "^    $1 (" | sed -E 's/.*\(([-A-F0-9]+)\).*/\1/'; }
A=$(udid "$PHONE_A"); B=$(udid "$PHONE_B")
[ -n "$A" ] && [ -n "$B" ] || { echo "Couldn't find both simulators. Set OURAPP_PHONE_A / OURAPP_PHONE_B."; exit 1; }

MODE=${1:-}

# --coop: two simulators, paired with each other, ready to play. Pairing is
# what makes co-op possible at all — a match needs two participants, and a
# phone learns who its partner is only by pairing with them.
if [ "$MODE" = "--coop" ]; then
  TRACE=/private/tmp/ourapp-coop.log
  rm -f "$TRACE"; touch "$TRACE"
  echo "Building…"
  xcodebuild build -project OurApp.xcodeproj -scheme OurApp \
    -destination "platform=iOS Simulator,name=$PHONE_A" -derivedDataPath build \
    >/dev/null 2>&1 || { echo "Build failed — run it yourself to see why."; exit 1; }
  APP=build/Build/Products/Debug-iphonesimulator/OurApp.app

  for D in "$A" "$B"; do xcrun simctl boot "$D" 2>/dev/null || true; done
  open -a Simulator
  sleep 10
  for D in "$A" "$B"; do
    xcrun simctl uninstall "$D" $BUNDLE 2>/dev/null || true
    xcrun simctl install "$D" "$APP"
  done

  # A offers a code; B types it. Both end up knowing the other's author id,
  # which is what a co-op match needs and what pairing exists to establish.
  xcrun simctl launch "$A" $BUNDLE -localNetwork -pairOffer -syncTrace "$TRACE" >/dev/null
  sleep 8
  CODE=$(grep -o "offering code [0-9]*" "$TRACE" | tail -1 | awk '{print $3}')
  if [ -z "$CODE" ]; then echo "No pairing code appeared — check $TRACE"; exit 1; fi
  echo "Pairing code: $CODE"
  xcrun simctl launch "$B" $BUNDLE -localNetwork -pairWith "$CODE" -syncTrace "$TRACE" >/dev/null
  sleep 14

  if grep -q "pairWith: paired" "$TRACE"; then
    echo
    echo "Paired. On either simulator: Apps → Moonshot → Co-op → pick a level → Start."
    echo "Take a shot on one, then open the same level on the other to watch it."
    echo "A tick runs whenever Home is foregrounded, so switching windows syncs."
  else
    echo "Pairing didn't complete. Trace: $TRACE"
    tail -5 "$TRACE"
  fi
  exit 0
fi

if [ "$MODE" = "--lan" ]; then
  # A real socket between the two simulators. No shared folder is involved,
  # and it still needs no paid Apple team.
  TRANSPORT=(-localNetwork)
  echo "Transport: local network (Bonjour + TCP)"
else
  TRANSPORT=(-fakeCloud "$CLOUD")
  if [ "$MODE" != "--keep" ]; then rm -rf "$CLOUD"; fi
  mkdir -p "$CLOUD"
  echo "Transport: shared folder at $CLOUD"
fi

echo "Building…"
xcodebuild build -project OurApp.xcodeproj -scheme OurApp \
  -destination "platform=iOS Simulator,name=$PHONE_A" -derivedDataPath build \
  >/dev/null 2>&1 || { echo "Build failed — run it yourself to see why."; exit 1; }
APP=build/Build/Products/Debug-iphonesimulator/OurApp.app

for D in "$A" "$B"; do xcrun simctl boot "$D" 2>/dev/null || true; done
open -a Simulator            # so both windows are actually on screen
sleep 10
for D in "$A" "$B"; do
  xcrun simctl uninstall "$D" $BUNDLE 2>/dev/null || true
  xcrun simctl install "$D" "$APP"
done

# A is seeded and pushes; B starts empty and pulls.
xcrun simctl launch "$A" $BUNDLE -seedMemories "${TRANSPORT[@]}" >/dev/null
# Bonjour discovery isn't instant; the first tick waits for a peer rather than
# quietly finding none.
sleep 8
xcrun simctl launch "$B" $BUNDLE "${TRANSPORT[@]}" >/dev/null

echo
if [ "$MODE" != "--lan" ]; then
  echo "  records: $(ls "$CLOUD"/*.json 2>/dev/null | wc -l | tr -d ' ')   assets: $(ls "$CLOUD/assets" 2>/dev/null | wc -l | tr -d ' ')"
  echo
fi
echo "$PHONE_A has three memories. On $PHONE_B, open Memories — they're there."
echo "A tick runs whenever Home is foregrounded, so switching between the two"
echo "windows is itself the sync trigger. No timers, no background modes."
