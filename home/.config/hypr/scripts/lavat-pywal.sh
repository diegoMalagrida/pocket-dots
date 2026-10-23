#!/usr/bin/env bash
# Caches lavat's colour flags derived from the wallpaper, and relaunches the
# running instances so they pick up the new palette.
#
# lavat WITHOUT -c paints with the terminal's foreground, i.e. pywal's grey: the
# lamp comes out in the text colour and looks as if it were not themed. Here it
# gets gradient mode (-g, truecolor) with two colours taken from the wallpaper.
#
# THE HUE IS DERIVED, NOT COPIED. Same reason as in spicetify-colors.py: pywal
# palettes come out grey (saturation ~0-20%) and a colour "as it is" barely
# shows; it takes the image's dominant HUE and raises saturation and lightness.
# The second colour is shifted 35 degrees so the gradient has some travel
# -- with two almost identical hues, lavat paints a flat blob.
#
# LIVE RECOLOURING: lavat has no reload signal and rereads nothing, so the only
# way is to restart it. It is sent SIGTERM and the ~/.local/bin/lavat wrapper
# relaunches it with the new flags: the wrapper tells them apart by exit code
# (143 = we killed it -> relaunch; 0 = the user pressed 'q' -> quit).
# That is why this script must NOT use SIGKILL: with -9 the code is 137 and the
# wrapper would take it for a legitimate exit.
set -uo pipefail

J="$HOME/.cache/wal/colors.json"
OUT="$HOME/.cache/wal/lavat.args"
[ -f "$J" ] || exit 0
mkdir -p "${OUT%/*}"

TMP=$(mktemp "${OUT}.tmp.XXXXXX") || exit 0
trap 'rm -f "$TMP"' EXIT

python3 -c "
import json, colorsys, sys

d = json.load(open('$J'))
c = d['colors']

def h2rgb(h):
    h = h.lstrip('#')
    return tuple(int(h[i:i+2], 16) / 255 for i in (0, 2, 4))

def H(r, g, b):
    return '%02X%02X%02X' % (round(r*255), round(g*255), round(b*255))

cols = [c['color%d' % i] for i in range(16)]
sat  = lambda h: colorsys.rgb_to_hls(*h2rgb(h))[2]
# The dominant hue among the chromatic ones: 0/7/8/15 are skipped, since they
# are the background, the text and their greys, and carry no useful hue.
best = max(cols[1:7] + cols[9:15], key=sat)
hue  = colorsys.rgb_to_hls(*h2rgb(best))[0]

mk = lambda h, l, s: H(*colorsys.hls_to_rgb(h % 1.0, l, s))

# Hot centre and shaded edge. lavat's gradient runs from -c to -k.
#
# THE TURN IS SHORT (18 degrees) BECAUSE THE SIGN DOES NOT MEAN THE SAME ON
# EVERY WALLPAPER. At 35 degrees the gradient looked fine over a blue one --
# blue to indigo -- but tried with the Vesuvius one it came out orange to OLIVE
# GREEN, which goes with neither the wallpaper nor itself. The range you really
# see in a lava lamp comes from the LIGHTNESS (0.62 -> 0.38), not the hue; 18
# degrees are enough for the gradient not to be flat and too few to fall into
# another colour family, whatever the wallpaper.
print(mk(hue,               0.62, 0.85))
print(mk(hue + 18.0/360.0,  0.38, 0.90))
" > "$TMP" 2>/dev/null || exit 0

# Two lines of 6 hex digits or nothing is touched: the previous palette is
# better than half-written flags, which would stop lavat from even starting.
mapfile -t COLS < "$TMP"
[ "${#COLS[@]}" -eq 2 ] || exit 0
case "${COLS[0]}${COLS[1]}" in
  [0-9A-F][0-9A-F][0-9A-F][0-9A-F][0-9A-F][0-9A-F][0-9A-F][0-9A-F][0-9A-F][0-9A-F][0-9A-F][0-9A-F]) ;;
  *) exit 0 ;;
esac

printf -- '-g -c %s -k %s\n' "${COLS[0]}" "${COLS[1]}" > "$TMP.args" || exit 0
mv -f "$TMP.args" "$OUT"

# Running instances: SIGTERM, and let the wrapper bring them back with the new palette.
pkill -TERM -x lavat 2>/dev/null || true
exit 0
