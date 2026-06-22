#!/usr/bin/env bash

set -euo pipefail

configuration="${1:-release}"
case "$configuration" in
  debug|release) ;;
  *)
    echo "Usage: $0 [debug|release]" >&2
    exit 64
    ;;
esac

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
product_name="Mac Mouse Gesture"
executable_name="spaces-gesture-probe"
app_dir="$project_root/.build/app/$product_name.app"
contents_dir="$app_dir/Contents"

cd "$project_root"
swift build --configuration "$configuration" --product "$executable_name"
bin_dir="$(swift build --configuration "$configuration" --show-bin-path)"

rm -rf "$app_dir"
mkdir -p "$contents_dir/MacOS" "$contents_dir/Resources"
cp "$bin_dir/$executable_name" "$contents_dir/MacOS/$executable_name"

cat > "$contents_dir/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "https://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>spaces-gesture-probe</string>
  <key>CFBundleIdentifier</key>
  <string>dev.sumetph.SpacesGestureProbe</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>Mac Mouse Gesture</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>LSUIElement</key>
  <true/>
</dict>
</plist>
PLIST

plutil -lint "$contents_dir/Info.plist" >/dev/null

# Ad-hoc signing makes the bundle launchable without requiring a Developer ID.
# Set CODE_SIGN_IDENTITY to use a persistent local or distribution identity.
codesign --force --sign "${CODE_SIGN_IDENTITY:--}" "$app_dir"

echo "Built: $app_dir"
