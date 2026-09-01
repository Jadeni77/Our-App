#!/bin/bash
# Fires the same silent push CloudKit sends, at a simulator.
#
# Why this exists: CloudKit's own push needs two Apple IDs and real delivery,
# but everything *after* delivery is ours — wake, sync, decide whether to say
# anything — and that half can be exercised here. It is the difference between
# "we never tested the handler" and "we tested all of it but the last hop".
#
#   ./scripts/push-test.sh                 # the booted iPhone 17 Pro
#   ./scripts/push-test.sh <device-udid>
set -e
DEVICE="${1:-DFCF290D-1777-426D-8BF6-28C790E83FA6}"
BUNDLE=com.jadeni77.OurApp
PAYLOAD=$(mktemp /tmp/ourapp-push-XXXX.json)

# `content-available: 1` and nothing else: this is exactly the shape a
# CKDatabaseSubscription with shouldSendContentAvailable sends. No alert, no
# sound — the receiving phone decides what, if anything, to say.
cat > "$PAYLOAD" <<'JSON'
{ "aps": { "content-available": 1 } }
JSON

xcrun simctl push "$DEVICE" "$BUNDLE" "$PAYLOAD" >/dev/null
rm -f "$PAYLOAD"
echo "Silent push delivered to $DEVICE."
echo "The app should sync and, if a turn is waiting for you, post a notification."
echo "A banner needs notification permission — tap Invite them once to be asked."
