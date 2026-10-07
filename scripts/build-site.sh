#!/bin/bash
# Package only the public landing page and its reviewed assets.
set -euo pipefail
umask 022
talky_site_root="$(cd "$(dirname "$0")/.." && pwd)"
talky_site_output="$talky_site_root/build/site"
mkdir -p "$talky_site_output/assets"
cp "$talky_site_root/site/index.html" "$talky_site_root/site/styles.css" "$talky_site_output/"
cp "$talky_site_root/assets/icon.png" "$talky_site_root/assets/setup-current.jpg" "$talky_site_output/assets/"
touch "$talky_site_output/.nojekyll"
python3 - "$talky_site_output" <<'PY'
from pathlib import Path
import sys
root = Path(sys.argv[1])
expected = {"index.html", "styles.css", ".nojekyll", "assets/icon.png", "assets/setup-current.jpg"}
files = set()
for path in root.rglob("*"):
    if path.is_symlink():
        raise SystemExit("Site output contains a symlink; review it before publishing.")
    if path.is_file():
        files.add(str(path.relative_to(root)))
if files != expected:
    raise SystemExit("Site output contains missing or unexpected files; review it before publishing.")
print("Prepared public site: " + str(root))
PY
