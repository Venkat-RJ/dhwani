#!/bin/bash
# Build a local app bundle with standalone Command Line Tools.
# Usage: ./build-local.sh [--output-dir DIRECTORY] [--adhoc] [--release]
# No installation, launch, stable signing key or notarization happens here.
set -euo pipefail
umask 077

talky_root="$(cd "$(dirname "$0")" && pwd)"
talky_output="$talky_root/build/local"
talky_developer_dir="${TALKY_DEVELOPER_DIR:-/Library/Developer/CommandLineTools}"
talky_adhoc=0
talky_optimization="-Onone"
talky_configuration="Debug"
while [ "$#" -gt 0 ]; do
    case "$1" in
        --output-dir)
            [ "$#" -ge 2 ] || { echo "--output-dir requires a directory." >&2; exit 2; }
            talky_output="$2"
            shift 2
            ;;
        --adhoc)
            talky_adhoc=1
            shift
            ;;
        --release)
            talky_optimization="-O"
            talky_configuration="Release"
            shift
            ;;
        *)
            echo "Usage: $0 [--output-dir DIRECTORY] [--adhoc] [--release]" >&2
            exit 2
            ;;
    esac
done
[ -d "$talky_developer_dir" ] || {
    echo "Standalone Command Line Tools are missing at $talky_developer_dir." >&2
    exit 1
}
mkdir -p "$talky_output"
talky_output="$(cd "$talky_output" && pwd)"
talky_app="$talky_output/Lokaah Talky.app"
if [ -L "$talky_app" ]; then
    echo "Refusing to replace a symlinked output bundle: $talky_app" >&2
    exit 1
fi
talky_stage="$(mktemp -d "$talky_output/.talky-build.XXXXXX")"
talky_replacing=0
cleanup() {
    local status=$?
    trap - EXIT INT TERM HUP
    set +e
    if [ "$status" -ne 0 ] && [ "$talky_replacing" -eq 1 ]; then
        if [ ! -e "$talky_stage/Lokaah Talky.app" ]; then
            rm -rf "$talky_app"
        fi
        if [ -e "$talky_stage/previous.app" ]; then
            if ! mv "$talky_stage/previous.app" "$talky_app"; then
                echo "Previous build preserved at $talky_stage/previous.app" >&2
                exit "$status"
            fi
        fi
    fi
    rm -rf "$talky_stage"
    exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP

talky_bundle="$talky_stage/Lokaah Talky.app"
mkdir -p "$talky_bundle/Contents/MacOS" "$talky_bundle/Contents/Resources" "$talky_stage/module-cache"
# Snapshot the source so concurrent edits cannot change a build in progress.
cp "$talky_root/Lokaah Talky/LokaahTalkyApp.swift" "$talky_stage/LokaahTalkyApp.swift"
talky_source_hash="$(shasum -a 256 "$talky_stage/LokaahTalkyApp.swift" | cut -d ' ' -f 1)"
talky_sdk="$(DEVELOPER_DIR="$talky_developer_dir" xcrun --sdk macosx --show-sdk-path)"
echo "Building Apple Silicon app for macOS 14+ with $talky_developer_dir"
DEVELOPER_DIR="$talky_developer_dir" xcrun swiftc \
    "$talky_optimization" -parse-as-library -swift-version 5 -module-name LokaahTalky \
    -default-isolation MainActor \
    -enable-upcoming-feature NonisolatedNonsendingByDefault \
    -enable-upcoming-feature InferIsolatedConformances \
    -enable-upcoming-feature MemberImportVisibility \
    -target arm64-apple-macosx14.0 -sdk "$talky_sdk" \
    -module-cache-path "$talky_stage/module-cache" \
    -Xlinker -no_adhoc_codesign \
    "$talky_stage/LokaahTalkyApp.swift" -o "$talky_bundle/Contents/MacOS/Lokaah Talky"

mkdir "$talky_stage/AppIcon.iconset"
cp "$talky_root/Lokaah Talky/Assets.xcassets/AppIcon.appiconset/"*.png "$talky_stage/AppIcon.iconset/"
iconutil --convert icns "$talky_stage/AppIcon.iconset" --output "$talky_bundle/Contents/Resources/AppIcon.icns"
cat > "$talky_bundle/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleDevelopmentRegion</key><string>en</string>
<key>CFBundleExecutable</key><string>Lokaah Talky</string>
<key>CFBundleIconFile</key><string>AppIcon.icns</string>
<key>CFBundleIdentifier</key><string>com.lokaah.talky</string>
<key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
<key>CFBundleName</key><string>Lokaah Talky</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.1.0</string>
<key>CFBundleVersion</key><string>2</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
<key>NSPrincipalClass</key><string>NSApplication</string>
<key>NSMicrophoneUsageDescription</key><string>Lokaah Talky uses your microphone for on-device dictation.</string>
<key>NSSpeechRecognitionUsageDescription</key><string>Lokaah Talky uses on-device speech recognition to convert your voice to text.</string>
<key>TalkyBuildMethod</key><string>local-clt</string>
<key>TalkyBuildConfiguration</key><string>$talky_configuration</string>
<key>TalkySourceSHA256</key><string>$talky_source_hash</string>
</dict></plist>
PLIST
plutil -lint "$talky_bundle/Contents/Info.plist"
if [ "$talky_adhoc" -eq 1 ]; then
    codesign --force --deep --sign - "$talky_bundle"
    codesign --verify --deep --strict "$talky_bundle"
fi
talky_replacing=1
if [ -e "$talky_app" ]; then
    mv "$talky_app" "$talky_stage/previous.app"
fi
mv "$talky_bundle" "$talky_app"
echo "Built: $talky_app"
echo "Source SHA256: $talky_source_hash"
if [ "$talky_adhoc" -eq 1 ]; then
    echo "Ad-hoc signed for local testing. This build is not notarized."
else
    echo "Unsigned. Rebuild with --adhoc for local launch, or sign with your stable identity."
fi
