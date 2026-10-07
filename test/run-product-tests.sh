#!/bin/bash
set -euo pipefail
talky_root=$(cd "$(dirname "$0")/.." && pwd)
talky_temp=$(mktemp -d "${TMPDIR:-/tmp}/talky-product-tests.XXXXXX")
trap 'rm -rf "$talky_temp"' EXIT
printf 'import Foundation\nimport Darwin\nimport CoreGraphics\n' > "$talky_temp/ProductCore.swift"
awk '
    /^\/\/ MARK: - Product core BEGIN$/ { copying = 1; found = 1; next }
    /^\/\/ MARK: - Product core END$/ { copying = 0; ended = 1; next }
    copying { print }
    END { if (!found || !ended) exit 1 }
' "$talky_root/Dhwani/DhwaniApp.swift" >> "$talky_temp/ProductCore.swift"
if [[ -d /Library/Developer/CommandLineTools ]]; then
    export DEVELOPER_DIR="${DEVELOPER_DIR:-/Library/Developer/CommandLineTools}"
fi
xcrun swiftc -parse-as-library "$talky_temp/ProductCore.swift" "$talky_root/test/ProductCoreTests.swift" -o "$talky_temp/product-core-tests"
"$talky_temp/product-core-tests"
