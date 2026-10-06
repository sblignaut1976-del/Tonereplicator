#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ "$(uname -s)" != Darwin ]]; then
    echo "The native app requires a Mac with Xcode 16+ / Swift 6 and macOS 14+. Use make test for the portable core." >&2
    exit 1
fi
# Temporary compatibility workaround: XCBuild failed to initialize on the user's Mac.
# Native is deprecated in newer SwiftPM; revalidate the default system before removal.
swift test --build-system native
swift build --build-system native -c release
bin_dir="$(swift build --build-system native -c release --show-bin-path)"
app="build/Tone Replicator.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin_dir/ToneReplicator" "$app/Contents/MacOS/ToneReplicator"
cp scripts/Info.plist "$app/Contents/Info.plist"
# Local development signing only. Distribution signing/notarization is a later milestone.
codesign --force --sign - "$app"
codesign --verify --strict "$app"
echo "Built $app. Open this bundle to test microphone permission and routing."
