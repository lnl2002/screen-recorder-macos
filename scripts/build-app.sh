#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release
binary_dir="$(swift build -c release --show-bin-path)"
app_dir="$PWD/dist/Screen Recorder.app"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
cp "$binary_dir/ScreenRecorder" "$app_dir/Contents/MacOS/ScreenRecorder"
cp scripts/Info.plist "$app_dir/Contents/Info.plist"
codesign --force --sign - --identifier com.lnl2002.screenrecorder "$app_dir"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$app_dir" "$PWD/dist/Screen-Recorder-macOS.zip"
printf 'App: %s\n' "$app_dir"
