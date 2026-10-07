#!/bin/bash
# Creates a private release candidate. Does not install, launch, or publish it.
set -euo pipefail
umask 077
talky_scripts="$(cd "$(dirname "$0")" && pwd)"
exec python3 -I "$talky_scripts/release_tool.py" prepare "$@"
