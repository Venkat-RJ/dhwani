#!/bin/bash
# Clean reinstall for Lokaah Talky.
#
# Why this exists: Xcode builds the app ad-hoc, so its code hash changes every
# build. We re-sign each build with a STABLE self-signed cert ("Talky Self-Signed")
# so the code identity stays constant. That keeps the macOS Accessibility /
# Microphone / Speech grants valid across rebuilds -- grant once, never again.
#
# One-time setup of the cert (already done): generate a code-signing cert and
# import it into the login keychain as "Talky Self-Signed".
#
# Usage:  ./reinstall.sh          (assumes the app is already built)
#         ./reinstall.sh --build  (builds first, then reinstalls)

APP_NAME="Lokaah Talky.app"
BUNDLE_ID="com.lokaah.talky"
PROJECT="Lokaah Talky.xcodeproj"
SCHEME="Lokaah Talky"
DEST_DIR="/Applications"
SIGN_IDENTITY="Talky Self-Signed"
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"

if [ "${1:-}" = "--build" ]; then
    echo "> Building..."
    ( cd "$PROJECT_DIR" && xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration Debug build ) >/tmp/hermes_build.log 2>&1
    if ! grep -q "BUILD SUCCEEDED" /tmp/hermes_build.log; then
        echo "x Build failed -- see /tmp/hermes_build.log"; tail -20 /tmp/hermes_build.log; exit 1
    fi
    echo "  build ok"
fi

# Resolve the freshly built .app (the real product, not the Index.noindex copy).
SRC="$(find "$HOME/Library/Developer/Xcode/DerivedData" -type d -name "$APP_NAME" -path "*/Build/Products/Debug/*" 2>/dev/null | grep -v "Index.noindex" | head -1)"
if [ -z "$SRC" ] || [ ! -d "$SRC" ]; then
    echo "x Couldn't find a built '$APP_NAME'. Run with --build first."; exit 1
fi
echo "> Source: $SRC"

echo "> Quitting running instances..."
pkill -9 -f "$APP_NAME/Contents/MacOS" 2>/dev/null
sleep 1

echo "> Removing old install..."
rm -rf "$DEST_DIR/$APP_NAME" 2>/dev/null
if [ -d "$DEST_DIR/$APP_NAME" ]; then
    echo "  (need elevated rights for $DEST_DIR -- falling back to ~/Applications)"
    DEST_DIR="$HOME/Applications"
    mkdir -p "$DEST_DIR"
    rm -rf "$DEST_DIR/$APP_NAME"
fi

echo "> Installing fresh copy to $DEST_DIR..."
cp -R "$SRC" "$DEST_DIR/"
if [ ! -d "$DEST_DIR/$APP_NAME" ]; then
    echo "x Copy failed"; exit 1
fi

echo "> Re-signing with stable identity ($SIGN_IDENTITY)..."
if security find-certificate -c "$SIGN_IDENTITY" >/dev/null 2>&1; then
    codesign --force --deep --sign "$SIGN_IDENTITY" "$DEST_DIR/$APP_NAME" 2>/tmp/talky_codesign.log \
        && echo "  signed (Accessibility grant will persist across rebuilds)" \
        || { echo "  x codesign failed:"; tail -3 /tmp/talky_codesign.log; }
else
    echo "  ! cert '$SIGN_IDENTITY' not found in keychain -- app stays ad-hoc (grants will reset)."
fi

echo "> Launching..."
open "$DEST_DIR/$APP_NAME"
sleep 2
COUNT="$(pgrep -f "$APP_NAME/Contents/MacOS" | wc -l | tr -d ' ')"
echo "OK Reinstalled to $DEST_DIR/$APP_NAME  (running instances: $COUNT)"
echo "   First dictation re-prompts for Microphone/Speech; first paste re-prompts for Accessibility."
