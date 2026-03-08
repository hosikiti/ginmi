#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Ginmi"
PRODUCT_NAME="${PRODUCT_NAME:-$APP_NAME}"
VERSION="${VERSION:-0.1.0}"
BUNDLE_ID="${BUNDLE_ID:-com.keio.ginmi}"
BUILD_DIR="$ROOT_DIR/.build"
DIST_DIR="$ROOT_DIR/dist"
STAGING_ROOT="$BUILD_DIR/dmg-staging"
APP_BUNDLE="$DIST_DIR/$PRODUCT_NAME.app"
DMG_STAGING_DIR="$STAGING_ROOT/$PRODUCT_NAME"
DMG_PATH="$DIST_DIR/${PRODUCT_NAME}-${VERSION}.dmg"
CACHE_ROOT="$BUILD_DIR/packaging-cache"

mkdir -p "$DIST_DIR"
mkdir -p "$CACHE_ROOT/clang-module-cache" "$CACHE_ROOT/swiftpm-module-cache" "$CACHE_ROOT/xdg-cache"

export CLANG_MODULE_CACHE_PATH="$CACHE_ROOT/clang-module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$CACHE_ROOT/swiftpm-module-cache"
export XDG_CACHE_HOME="$CACHE_ROOT/xdg-cache"

echo "==> Building release binary"
swift build --disable-sandbox -c release --package-path "$ROOT_DIR"

BIN_DIR="$(swift build --disable-sandbox -c release --show-bin-path --package-path "$ROOT_DIR")"
EXECUTABLE_PATH="$BIN_DIR/$APP_NAME"
RESOURCE_BUNDLES=()
while IFS= read -r bundle_path; do
  RESOURCE_BUNDLES+=("$bundle_path")
done < <(find "$BIN_DIR" -maxdepth 1 -type d -name '*.bundle' | sort)

if [[ ! -x "$EXECUTABLE_PATH" ]]; then
  echo "error: executable not found at $EXECUTABLE_PATH" >&2
  exit 1
fi

echo "==> Assembling app bundle"
rm -rf "$APP_BUNDLE" "$DMG_STAGING_DIR" "$DMG_PATH"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"

cp "$EXECUTABLE_PATH" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
chmod +x "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

for bundle_path in "${RESOURCE_BUNDLES[@]}"; do
  cp -R "$bundle_path" "$APP_BUNDLE/Contents/Resources/"
done

cat > "$APP_BUNDLE/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "https://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleDisplayName</key>
  <string>${PRODUCT_NAME}</string>
  <key>CFBundleExecutable</key>
  <string>${APP_NAME}</string>
  <key>CFBundleIdentifier</key>
  <string>${BUNDLE_ID}</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>${PRODUCT_NAME}</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>${VERSION}</string>
  <key>CFBundleVersion</key>
  <string>${VERSION}</string>
  <key>LSApplicationCategoryType</key>
  <string>public.app-category.productivity</string>
  <key>LSMinimumSystemVersion</key>
  <string>15.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
EOF

if command -v codesign >/dev/null 2>&1; then
  echo "==> Ad-hoc signing app bundle"
  codesign --force --deep --sign - "$APP_BUNDLE"
fi

echo "==> Preparing DMG contents"
mkdir -p "$DMG_STAGING_DIR"
cp -R "$APP_BUNDLE" "$DMG_STAGING_DIR/"
ln -sfn /Applications "$DMG_STAGING_DIR/Applications"

echo "==> Creating DMG"
hdiutil create \
  -volname "$PRODUCT_NAME" \
  -srcfolder "$DMG_STAGING_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH" >/dev/null

echo
echo "App bundle: $APP_BUNDLE"
echo "DMG:        $DMG_PATH"
