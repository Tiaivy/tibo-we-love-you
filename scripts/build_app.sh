#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
APP_NAME="TiboWeLoveYou.app"
APP_DIR="$PROJECT_DIR/dist/$APP_NAME"
BUILD_DIR="$PROJECT_DIR/.build/release"
ZIP_PATH="$PROJECT_DIR/dist/TiboWeLoveYou-macOS.zip"

cd "$PROJECT_DIR"

swift test --disable-sandbox
swift build --disable-sandbox -c release --product TiboResetCoin

if [[ -d "$APP_DIR" ]]; then
    rm -r "$APP_DIR"
fi

mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"
cp "$BUILD_DIR/TiboResetCoin" "$APP_DIR/Contents/MacOS/TiboResetCoin"
cp "$PROJECT_DIR/App/Info.plist" "$APP_DIR/Contents/Info.plist"
cp \
    "$PROJECT_DIR/App/Assets/TiboWeLoveYou.icns" \
    "$APP_DIR/Contents/Resources/TiboWeLoveYou.icns"
cp \
    "$PROJECT_DIR/Sources/TiboResetCoin/Resources/TiboButtonPhoto.png" \
    "$APP_DIR/Contents/Resources/TiboButtonPhoto.png"
cp \
    "$PROJECT_DIR/Sources/TiboResetCoin/Resources/CheckStatusEmoji.jpg" \
    "$APP_DIR/Contents/Resources/CheckStatusEmoji.jpg"

if [[ -n "${TIBO_RESET_FEED_URL:-}" ]]; then
    /usr/libexec/PlistBuddy \
        -c "Set :TiboResetFeedURL $TIBO_RESET_FEED_URL" \
        "$APP_DIR/Contents/Info.plist"
fi

codesign --force --deep --sign - "$APP_DIR"

if [[ -f "$ZIP_PATH" ]]; then
    rm "$ZIP_PATH"
fi
ditto -c -k --norsrc --noextattr --noqtn --noacl --keepParent "$APP_DIR" "$ZIP_PATH"

echo "$APP_DIR"
echo "$ZIP_PATH"
