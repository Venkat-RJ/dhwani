#!/bin/bash
set -euo pipefail

talky_root=$(cd "$(dirname "$0")/.." && pwd)
talky_source="${TALKY_TEST_SOURCE:-$talky_root/Lokaah Talky/LokaahTalkyApp.swift}"
talky_temp=$(mktemp -d "${TMPDIR:-/tmp}/talky-unit-tests.XXXXXX")
trap 'rm -rf "$talky_temp"' EXIT

# Compile the same lifecycle implementation used by the app, without starting
# the app, acquiring its microphone, or changing the installed build.
printf 'import Foundation\n' > "$talky_temp/RecognitionLifecycle.swift"
awk '
    /^\/\/ MARK: - Recognition lifecycle core BEGIN$/ { copying = 1; found = 1; next }
    /^\/\/ MARK: - Recognition lifecycle core END$/ { copying = 0; ended = 1; next }
    copying { print }
    END { if (!found || !ended) exit 1 }
' "$talky_source" >> "$talky_temp/RecognitionLifecycle.swift" || {
    echo "Recognition lifecycle markers are missing from $talky_source" >&2
    exit 1
}

if [[ -d /Library/Developer/CommandLineTools ]]; then
    talky_developer_dir="${DEVELOPER_DIR:-/Library/Developer/CommandLineTools}"
    DEVELOPER_DIR="$talky_developer_dir" xcrun swiftc -parse-as-library \
        "$talky_temp/RecognitionLifecycle.swift" \
        "$talky_root/test/RecognitionLifecycleTests.swift" \
        -o "$talky_temp/recognition-lifecycle-tests"
else
    xcrun swiftc -parse-as-library \
        "$talky_temp/RecognitionLifecycle.swift" \
        "$talky_root/test/RecognitionLifecycleTests.swift" \
        -o "$talky_temp/recognition-lifecycle-tests"
fi

"$talky_temp/recognition-lifecycle-tests"
