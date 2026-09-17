#!/bin/bash
# Builds MarkdownReader.app. No Xcode required - swiftc via the Command Line
# Tools plus a hand-assembled bundle.
#
#   ./Packaging/build-app.sh              build the .app into ./dist
#   ./Packaging/build-app.sh --install    also copy it to /Applications
#   ./Packaging/build-app.sh --dmg        also produce dist/MarkdownReader.dmg
set -euo pipefail

APP_NAME="Markdown Reader"
EXECUTABLE="MarkdownReader"
BUNDLE_ID="com.local.markdownreader"
VERSION="1.1"
BUILD="5"
MIN_MACOS="26.0"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

DIST="$ROOT/dist"
APP="$DIST/$APP_NAME.app"
CONTENTS="$APP/Contents"

DO_INSTALL=0
DO_DMG=0
for arg in "$@"; do
  case "$arg" in
    --install) DO_INSTALL=1 ;;
    --dmg) DO_DMG=1 ;;
    *) echo "unknown option: $arg" >&2; exit 2 ;;
  esac
done

# Build against the stable Tahoe SDK when beta Command Line Tools are selected.
# READER_SDK can override this for another installed toolchain.
READER_SDK="${READER_SDK:-/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk}"
if [ ! -d "$READER_SDK" ]; then READER_SDK="$(xcrun --sdk macosx --show-sdk-path)"; fi
export CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-$ROOT/.build/ModuleCache}"
echo "==> Compiling (release)"
swift build --build-system native -c release --sdk "$READER_SDK"
BINARY="$(swift build --build-system native -c release --sdk "$READER_SDK" --show-bin-path)/$EXECUTABLE"
[ -x "$BINARY" ] || { echo "no binary at $BINARY" >&2; exit 1; }

echo "==> Assembling bundle"
rm -rf "$APP"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"
cp "$BINARY" "$CONTENTS/MacOS/$EXECUTABLE"

echo "==> Icon"
# Icon Composer document -> Assets.car (light/dark/tinted variants) + legacy .icns.
# Layers are regenerated from the same geometry as makeicon.swift.
swift -sdk "$READER_SDK" "$ROOT/Packaging/makeiconsvg.swift" "$ROOT/Packaging/AppIcon.icon/Assets"
ICON_OUT="$(mktemp -d)"
xcrun actool "$ROOT/Packaging/AppIcon.icon" --compile "$ICON_OUT" --platform macosx --minimum-deployment-target "$MIN_MACOS" \
  --app-icon AppIcon --output-partial-info-plist "$ICON_OUT/partial.plist" --output-format human-readable-text 2>&1 \
  | grep -Ei "error|warning" || true
cp "$ICON_OUT/Assets.car" "$ICON_OUT/AppIcon.icns" "$CONTENTS/Resources/"
rm -rf "$ICON_OUT"

echo "==> Info.plist"
cat > "$CONTENTS/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>$APP_NAME</string>
    <key>CFBundleDisplayName</key><string>$APP_NAME</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundleExecutable</key><string>$EXECUTABLE</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$BUILD</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleIconName</key><string>AppIcon</string>
    <key>LSMinimumSystemVersion</key><string>$MIN_MACOS</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.productivity</string>
    <key>CFBundleDocumentTypes</key>
    <array>
        <dict>
            <key>CFBundleTypeName</key><string>Markdown Document</string>
            <key>CFBundleTypeRole</key><string>Editor</string>
            <key>LSHandlerRank</key><string>Alternate</string>
            <key>LSItemContentTypes</key>
            <array>
                <string>net.daringfireball.markdown</string>
                <string>public.plain-text</string>
            </array>
        </dict>
    </array>
</dict>
</plist>
PLIST
plutil -lint "$CONTENTS/Info.plist" >/dev/null

printf 'APPL????' > "$CONTENTS/PkgInfo"

echo "==> Signing (ad-hoc)"
# Ad-hoc is enough for a locally built app: nothing downloaded it, so it never
# carries the quarantine flag Gatekeeper reacts to.
codesign --force --sign - --timestamp=none "$APP" >/dev/null 2>&1
codesign --verify --deep --strict "$APP" && echo "    signature ok"

echo "==> Built $APP"
du -sh "$APP" | awk '{print "    size: " $1}'

if [ "$DO_INSTALL" -eq 1 ]; then
  echo "==> Installing to /Applications"
  rm -rf "/Applications/$APP_NAME.app"
  cp -R "$APP" "/Applications/$APP_NAME.app"
  echo "    /Applications/$APP_NAME.app"
fi

if [ "$DO_DMG" -eq 1 ]; then
  echo "==> Building dmg"
  STAGE="$(mktemp -d)/dmg"
  mkdir -p "$STAGE"
  cp -R "$APP" "$STAGE/"
  ln -s /Applications "$STAGE/Applications"
  rm -f "$DIST/MarkdownReader.dmg"
  hdiutil create -volname "$APP_NAME" -srcfolder "$STAGE" -ov -format UDZO \
    -quiet "$DIST/MarkdownReader.dmg"
  echo "    $DIST/MarkdownReader.dmg"
fi
