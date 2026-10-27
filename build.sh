#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
APP="$PWD/许家印桌宠.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
swiftc -module-cache-path /private/tmp/xujiayin-swift-cache -O Sources/main.swift Sources/SharedDance.swift -o "$APP/Contents/MacOS/XuPet" -framework AppKit -framework AVFoundation
cp Assets/bangyou.m4a Assets/beats-bangyou.json Assets/portrait-bangyou.png Assets/beats.json Assets/portrait.png Assets/portrait-playing.png Assets/audio.m4a "$APP/Contents/Resources/"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd"><plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>XuPet</string><key>CFBundleIdentifier</key><string>local.xujiayin.desktop-pet</string><key>CFBundleName</key><string>许家印桌宠</string><key>CFBundlePackageType</key><string>APPL</string><key>CFBundleShortVersionString</key><string>1.6</string><key>CFBundleVersion</key><string>1</string><key>LSUIElement</key><true/><key>NSHighResolutionCapable</key><true/><key>LSMinimumSystemVersion</key><string>13.0</string></dict></plist>
PLIST
codesign --force --sign - "$APP"
