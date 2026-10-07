#!/bin/bash
# Build, stage and verify the app before replacing the installed copy.
# Usage: ./reinstall.sh [--build]
set -euo pipefail
umask 077

APP_NAME="Dhwani.app"
PROJECT="Dhwani.xcodeproj"
SCHEME="Dhwani"
SIGN_IDENTITY="Talky Self-Signed"
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
DERIVED="$PROJECT_DIR/build"
SRC="$DERIVED/Build/Products/Debug/$APP_NAME"
DEST_DIR="${TALKY_DEST_DIR:-/Applications}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/talky-reinstall.XXXXXX")"
STAGE_DIR=""
INSTALL_STARTED=0
INSTALLED=0
WAS_RUNNING=0

cleanup() {
    local status=$?
    trap - EXIT INT TERM HUP
    set +e
    if [ "$status" -ne 0 ] && [ -n "$STAGE_DIR" ]; then
        if [ "$INSTALLED" -eq 1 ] || { [ "$INSTALL_STARTED" -eq 1 ] && [ ! -e "$STAGE_DIR/$APP_NAME" ]; }; then
            rm -rf "$DEST_DIR/$APP_NAME"
        fi
        if [ -d "$STAGE_DIR/previous.app" ]; then
            if mv "$STAGE_DIR/previous.app" "$DEST_DIR/$APP_NAME"; then
                echo "Restored the previous installation." >&2
                if [ "$WAS_RUNNING" -eq 1 ]; then
                    open "$DEST_DIR/$APP_NAME" >/dev/null 2>&1
                fi
            else
                echo "Restore failed. Previous app preserved at $STAGE_DIR/previous.app" >&2
                rm -rf "$WORK_DIR"
                exit "$status"
            fi
        fi
    fi
    if [ -n "$STAGE_DIR" ]; then rm -rf "$STAGE_DIR"; fi
    rm -rf "$WORK_DIR"
    exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP

if [ "$#" -gt 1 ] || { [ "$#" -eq 1 ] && [ "$1" != "--build" ]; }; then
    echo "Usage: $0 [--build]" >&2
    exit 2
fi
if [ -e "$DEST_DIR/Lokaah Talky.app" ] || [ -L "$DEST_DIR/Lokaah Talky.app" ]; then
    echo "An older Lokaah Talky copy exists in $DEST_DIR. Finish recording, quit it, and move that app to Trash before installing Dhwani." >&2
    exit 1
fi
if [ "${1:-}" = "--build" ]; then
    echo "> Building..."
    if ! (cd "$PROJECT_DIR" && xcodebuild -project "$PROJECT" -scheme "$SCHEME" \
        -configuration Debug -derivedDataPath "$DERIVED" build) >"$WORK_DIR/build.log" 2>&1; then
        echo "Build failed. The installed app was not changed:" >&2
        tail -30 "$WORK_DIR/build.log" >&2
        exit 1
    fi
fi
if [ ! -f "$SRC/Contents/Info.plist" ] || [ ! -x "$SRC/Contents/MacOS/Dhwani" ]; then
    echo "No complete build at $SRC. Run ./reinstall.sh --build." >&2
    exit 1
fi
if ! security find-identity -p codesigning | grep -F "\"$SIGN_IDENTITY\"" >/dev/null; then
    echo "Signing identity '$SIGN_IDENTITY' is missing. Run ./setup-cert.sh first." >&2
    exit 1
fi

# Do not leave an old system installation alongside a new user installation.
if [ -z "${TALKY_DEST_DIR:-}" ] && [ ! -w "$DEST_DIR" ]; then
    if [ -e "$DEST_DIR/$APP_NAME" ]; then
        echo "Cannot replace $DEST_DIR/$APP_NAME. Choose a writable installation location." >&2
        exit 1
    fi
    DEST_DIR="$HOME/Applications"
fi
mkdir -p "$DEST_DIR"
if [ -L "$DEST_DIR/$APP_NAME" ]; then
    echo "Refusing to replace a symlinked app at $DEST_DIR/$APP_NAME." >&2
    exit 1
fi
STAGE_DIR="$(mktemp -d "$DEST_DIR/.talky-install.XXXXXX")"
STAGED_APP="$STAGE_DIR/$APP_NAME"
echo "> Staging $SRC..."
ditto "$SRC" "$STAGED_APP"
echo "> Signing with $SIGN_IDENTITY..."
codesign --force --deep --sign "$SIGN_IDENTITY" "$STAGED_APP"
codesign --verify --deep --strict "$STAGED_APP"

# Stage and signature failures leave the current app and process untouched.
PROCESS_PATTERN='Dhwani[.]app/Contents/MacOS/'
if pgrep -f "$PROCESS_PATTERN" >/dev/null; then
    WAS_RUNNING=1
    pkill -TERM -f "$PROCESS_PATTERN"
    for ((attempt=0; attempt<30; attempt++)); do
        if ! pgrep -f "$PROCESS_PATTERN" >/dev/null; then break; fi
        sleep 0.1
    done
    if pgrep -f "$PROCESS_PATTERN" >/dev/null; then
        echo "The running app did not quit. Installation cancelled." >&2
        exit 1
    fi
fi
INSTALL_STARTED=1
if [ -e "$DEST_DIR/$APP_NAME" ]; then
    mv "$DEST_DIR/$APP_NAME" "$STAGE_DIR/previous.app"
fi
mv "$STAGED_APP" "$DEST_DIR/$APP_NAME"
INSTALLED=1
echo "> Launching..."
open "$DEST_DIR/$APP_NAME"
sleep 2
if ! pgrep -f "$PROCESS_PATTERN" >/dev/null; then
    echo "The new app did not stay running. Installation failed." >&2
    exit 1
fi
echo "OK Installed and launched $DEST_DIR/$APP_NAME"
