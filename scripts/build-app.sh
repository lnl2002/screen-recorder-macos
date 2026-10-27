#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release
binary_dir="$(swift build -c release --show-bin-path)"
app_name="${1:-Screen Recorder}"
case "$app_name" in */*|..|.) echo "Pass an app name, not a path." >&2; exit 1;; esac
app_dir="$PWD/dist/$app_name.app"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
cp "$binary_dir/ScreenRecorder" "$app_dir/Contents/MacOS/ScreenRecorder"
cp scripts/Info.plist "$app_dir/Contents/Info.plist"
cp assets/AppIcon.icns "$app_dir/Contents/Resources/AppIcon.icns"
codesign --force --sign - --identifier com.lnl2002.screenrecorder "$app_dir"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$app_dir" "$PWD/dist/Screen-Recorder-macOS.zip"
printf 'App: %s\n' "$app_dir"
