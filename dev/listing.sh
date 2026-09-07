#!/usr/bin/env bash
# Render the marketplace still, preview.webp, from dev/listing/listing.html.
# The page embeds real screenshots: dev/listing/bar.png (the icon in the bar),
# launcher.png (hint mode), and options.png (the Options screen). Retake those
# and rerun this when the UI changes.
# Needs chromium, ImageMagick, Noto Sans, Noto Color Emoji, and JetBrainsMono Nerd Font.
set -euo pipefail
src="$(cd "$(dirname "$0")/.." && pwd)"
work=$(mktemp -d /tmp/bookmark-listing.XXXXXX)
trap 'rm -rf "$work"' EXIT
chromium --headless=new --disable-gpu --hide-scrollbars --window-size=2000,1000 \
  --screenshot="$work/listing.png" "file://$src/dev/listing/listing.html" >/dev/null 2>&1
magick "$work/listing.png" -quality 90 -define webp:method=6 "${BOOKMARK_LISTING_OUTPUT:-$src}/preview.webp"
echo "Wrote ${BOOKMARK_LISTING_OUTPUT:-$src}/preview.webp"
