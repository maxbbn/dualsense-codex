#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
test_dir="$(mktemp -d "${TMPDIR:-/tmp}/dualsense-tests.XXXXXX")"
trap 'rm -rf "$test_dir"' EXIT
mkdir -p "$test_dir/module-cache"
swift_target="$(uname -m)-apple-macosx12.0"
xcrun swiftc -target "$swift_target" -swift-version 5 -module-cache-path "$test_dir/module-cache" \
  Sources/HoldState.swift Sources/TriggerGesture.swift Sources/StickNavigation.swift \
  Sources/ConversationGeometry.swift Tests/main.swift -o "$test_dir/state-tests"
"$test_dir/state-tests"
xcrun swiftc -target "$swift_target" -swift-version 5 -module-cache-path "$test_dir/module-cache" \
  Sources/notify-hook.swift -o "$test_dir/notify-tests"
"$test_dir/notify-tests" --self-test
python3 -m unittest discover -s Tests -p 'test_*.py'
