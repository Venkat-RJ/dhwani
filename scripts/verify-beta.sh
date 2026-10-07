#!/bin/bash
# Require completed acceptance of the exact unnotarized beta archive.
set -euo pipefail
umask 077
talky_scripts="$(cd "$(dirname "$0")" && pwd)"
exec python3 -I "$talky_scripts/beta_release.py" verify "$@"
