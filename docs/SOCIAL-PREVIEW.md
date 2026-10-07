# Social sharing preview

The website uses `assets/og-dhwani-v1.jpg` for Open Graph and large-image social cards.
It is a 1200 by 630 pixel JPEG.
The image names the app, describes voice typing, and identifies the early beta.
It uses the selected app icon without changing its artwork.

The editable layout is `assets/brand/social-card.html`.
Serve the `assets/` directory locally, open `/brand/social-card.html`, and capture the card at a 1200 by 630 CSS pixel viewport.
The reviewed export was rendered with the macOS system font in the Codex browser.
Check the exported JPEG dimensions before replacing the published image.

The image URL includes a version so a new design can use a new URL.
When changing the filename, update `site/index.html` and `scripts/build-site.sh` together.
Only the exported JPEG is included in the Pages artifact.

Metadata includes the image type, dimensions, and descriptive alt text, following the [Open Graph image properties](https://ogp.me/#structured).
Actual preview layouts and refresh timing depend on the sharing platform.
