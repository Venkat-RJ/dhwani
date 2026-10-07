#!/bin/bash
# Requires completed acceptance evidence for the exact candidate. Does not publish it.
set -euo pipefail
umask 077
talky_scripts="$(cd "$(dirname "$0")" && pwd)"
exec python3 -I "$talky_scripts/release_tool.py" verify "$@"
