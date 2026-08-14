#!/bin/bash
# Build and install on a connected iPhone, without Xcode.
#
# Xcode's Team dropdown has been showing only "Personal Team" and "None" even
# though the paid team is fine — the command line authenticates differently and
# has worked every time. This is the reliable path.
#
#   ./scripts/install-on-phone.sh          # build, install, launch
#   ./scripts/install-on-phone.sh --no-run # install only
set -euo pipefail
cd "$(dirname "$0")/.."

BUNDLE=com.jadeni77.OurApp
DERIVED=build-device

# The device UDID, from the connected-devices section only. Plain grep rather
# than awk: macOS awk lacks the 3-argument match() this originally used, and
# failed the whole script under `set -e`.
UDID=$(xcrun xctrace list devices 2>/dev/null \
  | sed -n '/^== Devices ==/,/^== Devices Offline ==/p' \
  | grep -oE '\(00[0-9A-F]{6}-[0-9A-F]{16}\)' | head -1 | tr -d '()')

if [ -z "${UDID:-}" ]; then
  echo "No iPhone found. Plug it in, unlock it, and trust this Mac."
  exit 1
fi
echo "Device: $UDID"

echo "Building…"
if ! xcodebuild -project OurApp.xcodeproj -scheme OurApp \
      -destination "platform=iOS,id=$UDID" -allowProvisioningUpdates \
      -derivedDataPath "$DERIVED" build > /private/tmp/phone-build.log 2>&1; then
  echo "Build failed. Signing errors, most likely:"
  grep -iE "error:" /private/tmp/phone-build.log | head -5
  exit 1
fi

APP="$DERIVED/Build/Products/Debug-iphoneos/OurApp.app"
xcrun devicectl device install app --device "$UDID" "$APP" >/dev/null
echo "Installed."

if [ "${1:-}" != "--no-run" ]; then
  xcrun devicectl device process launch --device "$UDID" "$BUNDLE" >/dev/null 2>&1 || {
    echo "Installed, but couldn't launch — is the phone locked?"; exit 0; }
  sleep 3
  # Checked, not assumed: devicectl reports a launch it *dispatched*, not one
  # that survived. An earlier session reported "running" for an app that had
  # already crashed.
  if [ "$(xcrun devicectl device info processes --device "$UDID" 2>/dev/null | grep -ci ourapp)" -gt 0 ]; then
    echo "Running on your phone."
  else
    echo "Launched but not running — it crashed on startup. Check with:"
    echo "  xcrun devicectl device process launch --device $UDID --console $BUNDLE"
  fi
fi
rm -rf "$DERIVED"
