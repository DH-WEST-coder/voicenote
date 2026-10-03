#!/bin/bash
# VoiceNote.app 빌드: SwiftPM release 빌드 → 번들 조립 → ad-hoc 서명
set -euo pipefail
cd "$(dirname "$0")"
swift build -c release
BIN="$(swift build -c release --show-bin-path)"
APP="build/VoiceNote.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/VoiceNote" "$APP/Contents/MacOS/VoiceNote"
cp Resources/Info.plist "$APP/Contents/Info.plist"
codesign --force -s - --entitlements Resources/VoiceNote.entitlements "$APP"
codesign --verify --verbose "$APP"
echo "OK: $(pwd)/$APP"
