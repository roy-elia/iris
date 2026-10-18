#!/bin/zsh
# Builds a release binary and wraps it in dist/File Drop Utility.app (ad-hoc signed).
set -euo pipefail
cd "${0:a:h}/.."

swift build -c release
BIN="$(swift build -c release --show-bin-path)/FileDropUtility"
APP="dist/File Drop Utility.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/FileDropUtility"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>FileDropUtility</string>
  <key>CFBundleIdentifier</key><string>local.filedroputility</string>
  <key>CFBundleName</key><string>File Drop Utility</string>
  <key>CFBundleDisplayName</key><string>File Drop Utility</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP"
echo "Built $APP"
