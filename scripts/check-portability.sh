#!/bin/bash
# P39: FarshoreKit must build with nothing else in the workspace.
#
# This IS the extractability test. A package cannot import an app target, so if
# it compiles alone, every forbidden dependency on OurApp is already absent —
# no grep, no review note, no rule anybody has to remember.
#
# Run before opening any PR that touches the package. CI runs it too, but only
# post-merge (P10's macOS-minutes trade-off), so locally is where it protects you.
set -euo pipefail
HERE="$(dirname "$0")"

echo "Building FarshoreKit alone (iOS)…"
cd "$HERE/../Packages/FarshoreKit"
set -o pipefail
xcodebuild build \
  -scheme FarshoreKit \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO \
  | tail -30
cd - > /dev/null

echo "Running FarshoreKit's own tests…"
"$HERE/farshore-test.sh"
echo "Portability check passed."
