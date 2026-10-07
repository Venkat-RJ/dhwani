#!/bin/bash
# Prepare a private unnotarized beta. No installation or publication.
set -euo pipefail
umask 077
talky_scripts="$(cd "$(dirname "$0")" && pwd)"
exec python3 -I "$talky_scripts/beta_release.py" prepare "$@"
