#!/usr/bin/env bash
# wall-thumbs.sh — keeps ~/.cache/wallpaper-thumbs in sync with
# ~/Pictures/wallpapers so the picker does not have to decode the originals
# (up to 6 MB each) just to paint one card.
#
# Each thumbnail is named <original file>.jpg — e.g. "dl-1785759993.png.jpg".
# Keeping the original extension inside the name lets the picker recover the
# real path by dropping the trailing ".jpg", with no ambiguity between a .png
# and a .jpg with the same name, and keeps the same alphabetical order as the
# originals.
set -u

SRC="${1:-$HOME/Pictures/wallpapers}"
DST="${2:-$HOME/.cache/wallpaper-thumbs}"
# The coverflow hero card paints the image at 874x406 px. ImageMagick's '^'
# scales by COVERAGE (both sides end up >= the minimum, not <=), so no thumbnail
# falls short and has to be enlarged: a 4:3 at "x500" came out 667 px wide and
# looked soft. The small margin absorbs future tweaks to the card.
GEOM="900x420^"
JOBS=4

command -v magick >/dev/null 2>&1 || exit 0
[ -d "$SRC" ] || exit 0
mkdir -p "$DST" || exit 0

# 1) Generate the missing ones or the ones that have gone stale.
while IFS= read -r -d '' img; do
    out="$DST/$(basename "$img").jpg"
    # -nt: only regenerated if the original is newer than its thumbnail.
    if [ -s "$out" ] && [ ! "$img" -nt "$out" ]; then
        continue
    fi
    # Write to a temporary file and rename: the picker watches this folder and, if
    # magick dumped straight onto "$out", Qt can read the file half-written and the
    # card ends up broken with "Unsupported image format". The rename IS atomic.
    ( magick "$img" -auto-orient -thumbnail "$GEOM" -strip -quality 85 "$out.tmp" 2>/dev/null \
        && mv -f -- "$out.tmp" "$out" || rm -f -- "$out.tmp" ) &
    while [ "$(jobs -rp | wc -l)" -ge "$JOBS" ]; do wait -n; done
done < <(find "$SRC" -maxdepth 1 -type f \
    \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' \) -print0)
wait

# 2) Leftovers from an interrupted run.
find "$DST" -maxdepth 1 -type f -name '*.jpg.tmp' -delete 2>/dev/null

# 3) Throw out the orphans: wallpaper deleted or renamed -> out of the picker.
while IFS= read -r -d '' thumb; do
    base="$(basename "$thumb")"
    [ -f "$SRC/${base%.jpg}" ] || rm -f -- "$thumb"
done < <(find "$DST" -maxdepth 1 -type f -name '*.jpg' -print0)

exit 0
