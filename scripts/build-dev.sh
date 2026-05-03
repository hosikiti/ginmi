#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Ginmi"
PRODUCT_NAME="${PRODUCT_NAME:-Ginmi-dev}"
VERSION="${VERSION:-0.0.0-dev}"
BUNDLE_ID="${BUNDLE_ID:-com.keio.ginmi.dev}"
BUILD_DIR="$ROOT_DIR/.build"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$PRODUCT_NAME.app"
CACHE_ROOT="$BUILD_DIR/dev-packaging-cache"
ICON_SOURCE="$ROOT_DIR/Sources/Ginmi/Resources/ginmi-icon.png"
ICONSET_DIR="$CACHE_ROOT/Ginmi.iconset"
APP_ICON_FILE="$APP_NAME.icns"
ICON_PLIST_ENTRY=""
RESOURCE_BUNDLES_FILE="$CACHE_ROOT/resource-bundles.txt"

mkdir -p "$DIST_DIR"
mkdir -p "$CACHE_ROOT/clang-module-cache" "$CACHE_ROOT/swiftpm-module-cache" "$CACHE_ROOT/xdg-cache"

export CLANG_MODULE_CACHE_PATH="$CACHE_ROOT/clang-module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$CACHE_ROOT/swiftpm-module-cache"
export XDG_CACHE_HOME="$CACHE_ROOT/xdg-cache"

echo "==> Building debug binary"
swift build --disable-sandbox --package-path "$ROOT_DIR"

BIN_DIR="$(swift build --disable-sandbox --show-bin-path --package-path "$ROOT_DIR")"
EXECUTABLE_PATH="$BIN_DIR/$APP_NAME"
find "$BIN_DIR" -maxdepth 1 -type d -name '*.bundle' | sort > "$RESOURCE_BUNDLES_FILE"

if [[ ! -x "$EXECUTABLE_PATH" ]]; then
  echo "error: executable not found at $EXECUTABLE_PATH" >&2
  exit 1
fi

echo "==> Assembling dev app bundle"
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"

cp "$EXECUTABLE_PATH" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
chmod +x "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

while IFS= read -r bundle_path; do
  cp -R "$bundle_path" "$APP_BUNDLE/Contents/Resources/"
done < "$RESOURCE_BUNDLES_FILE"

if [[ -f "$ICON_SOURCE" ]] && command -v sips >/dev/null 2>&1 && command -v iconutil >/dev/null 2>&1; then
  echo "==> Generating app icon"
  rm -rf "$ICONSET_DIR"
  mkdir -p "$ICONSET_DIR"

  sips -z 16 16 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_16x16.png" >/dev/null
  sips -z 32 32 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_16x16@2x.png" >/dev/null
  sips -z 32 32 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_32x32.png" >/dev/null
  sips -z 64 64 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_32x32@2x.png" >/dev/null
  sips -z 128 128 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_128x128.png" >/dev/null
  sips -z 256 256 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_128x128@2x.png" >/dev/null
  sips -z 256 256 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_256x256.png" >/dev/null
  sips -z 512 512 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_256x256@2x.png" >/dev/null
  sips -z 512 512 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_512x512.png" >/dev/null
  sips -z 1024 1024 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_512x512@2x.png" >/dev/null

  if iconutil -c icns "$ICONSET_DIR" -o "$APP_BUNDLE/Contents/Resources/$APP_ICON_FILE"; then
    ICON_PLIST_ENTRY="  <key>CFBundleIconFile</key>
  <string>$APP_ICON_FILE</string>"
  else
    echo "warning: could not generate .icns; app will still use bundled PNG icons at runtime" >&2
  fi
fi

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
${ICON_PLIST_ENTRY}
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
  echo "==> Ad-hoc signing dev app bundle"
  codesign --force --deep --sign - "$APP_BUNDLE"
fi

echo
echo "Dev app bundle: $APP_BUNDLE"
