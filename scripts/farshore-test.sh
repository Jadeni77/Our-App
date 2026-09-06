#!/bin/bash
# FarshoreKit's own tests, on an iOS Simulator.
#
# **Deliberately not `swift test`.** SwiftPM builds for the host, and this
# package imports UIKit — so `swift test` compiles for macOS and fails the
# moment the first UIKit file lands. A test command that cannot run is not a
# test command.
#
#   ./scripts/farshore-test.sh
#   ./scripts/farshore-test.sh -only-testing:FarshoreKitTests/SessionClockTests
set -euo pipefail
cd "$(dirname "$0")/../Packages/FarshoreKit"
set -o pipefail
xcodebuild test \
  -scheme FarshoreKit \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  CODE_SIGNING_ALLOWED=NO \
  "$@" | tail -30
