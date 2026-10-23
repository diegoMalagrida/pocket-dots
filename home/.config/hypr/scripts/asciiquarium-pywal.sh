#!/usr/bin/env bash
# Caches the aquarium's ANSI palette derived from the wallpaper and pushes it to
# the running instances, without restarting them.
#
# WHY THIS IS NEEDED, IF ASCIIQUARIUM ALREADY INHERITS KITTY'S COLOURS. It does
# inherit them: it paints with Curses names ('cyan', 'GREEN', 'RED'...), which
# are the terminal's 16 ANSI colours, and kitty already includes
# colors-kitty.conf. The problem is that pywal's palette COLLAPSES: measured on
# art-sukhoi, color2/3/4/5 were the same blue under four names (#34799f #3987ac
# #3781a7 #3e9fbc). With that the fish, the seaweed, the dolphins and the
# bubbles all come out in the same hue and the aquarium looks monochrome -- it
# inherits the background but loses the drawing.
#
# Here they are spread out: it takes the image's dominant HUE (same criterion as
# spicetify-colors.py, which already knows that pywal palettes come out grey)
# and opens the 16 slots into an ANALOGOUS family around it, with a complement
# for whatever has to stand out. The whole aquarium turns with the wallpaper,
# but inside there is still contrast between the creatures.
#
# LIVE VIA OSC 4, NOT BY RESTARTING. The sequence ESC]4;N;#RRGGBB redefines one
# of the terminal's ANSI colours, and whatever is already painted repaints
# itself. It is written to the process's /dev/pts, not through kitty's remote
# control, so that it also works if the aquarium runs in another terminal. Mind:
# this is writing to the terminal's OUTPUT, not injecting input -- nothing to do
# with TIOCSTI.
#
# THE ORDER IN set-wallpaper.sh MATTERS: this call has to come AFTER the
# 'pkill -SIGUSR1 -x kitty', because on a config reload kitty reapplies the
# colours from colors-kitty.conf and wipes out whatever we set via OSC.
set -uo pipefail

J="$HOME/.cache/wal/colors.json"
OUT="$HOME/.cache/wal/asciiquarium.osc"
[ -f "$J" ] || exit 0
mkdir -p "${OUT%/*}"

TMP=$(mktemp "${OUT}.tmp.XXXXXX") || exit 0
trap 'rm -f "$TMP"' EXIT

python3 -c "
import json, colorsys

d = json.load(open('$J'))
c, sp = d['colors'], d['special']

def h2rgb(h):
    h = h.lstrip('#')
    return tuple(int(h[i:i+2], 16) / 255 for i in (0, 2, 4))

def H(r, g, b):
    return '#%02X%02X%02X' % (round(r*255), round(g*255), round(b*255))

cols = [c['color%d' % i] for i in range(16)]
sat  = lambda h: colorsys.rgb_to_hls(*h2rgb(h))[2]
best = max(cols[1:7] + cols[9:15], key=sat)
hue  = colorsys.rgb_to_hls(*h2rgb(best))[0]

# HLS's 'L' is not the brightness the eye sees: a blue at L=0.50 looks much
# darker than a yellow at the same L. Turning the hue bare, the slots that land
# on blue or violet came out almost black against the background -- measured
# with art-sukhoi, the seaweed ended up at #3E2DD2, invisible. So L is not
# fixed: the one giving the requested relative luminance is SEARCHED for
# (WCAG's, the same Colors.qml uses to guarantee its 3:1), and so every
# creature weighs the same on screen wherever the hue lands.
def lum(rgb):
    f = lambda ch: ch/12.92 if ch <= 0.03928 else ((ch + 0.055)/1.055) ** 2.4
    r, g, b = (f(x) for x in rgb)
    return 0.2126*r + 0.7152*g + 0.0722*b

def mk(deg, target, s):
    h = (hue + deg/360.0) % 1.0
    lo, hi = 0.0, 1.0
    for _ in range(24):                      # bisection: lum grows with L
        mid = (lo + hi) / 2
        if lum(colorsys.hls_to_rgb(h, mid, s)) < target:
            lo = mid
        else:
            hi = mid
    return H(*colorsys.hls_to_rgb(h, (lo + hi) / 2, s))

# Who uses each slot in asciiquarium (looked up in /usr/bin/asciiquarium):
#   1/9  red     the castle flags and fish
#   2/10 green   seaweed, the wave line and the monster
#   3/11 yellow  the castle and the big fish
#   4/12 blue    dolphins and the water
#   5/13 magenta fish
#   6/14 cyan    fish, bubbles and the shark
#   7/15 white   ship, swan and whale
# The hues fan out around the dominant one; red goes to the complementary,
# the one thing that has to jump out over the rest. The second number is no
# longer lightness, it is target LUMINANCE: 0.20 for the normal ones and 0.42
# for the bright ones, which over a pywal background (luminance ~0.015) give
# 3.8:1 and 7.2:1 of contrast.
#
# THE FAN IS KEPT TIGHT ON PURPOSE. The first version opened the hues up to
# 135 degrees and out came an orange, violet, magenta and pink aquarium: it
# turned with the wallpaper, yes, but it did not LOOK like the wallpaper, which
# was the point. Now the water, the fish and the seaweed fall within +-70
# degrees of the dominant hue -- an analogous family, tinted by the image --
# and the only one that jumps to the complementary is red, which in
# asciiquarium is the castle's little flags and four fish: an accent, not half
# the aquarium.
#
# And the sign of the turn matters. The seaweed (slot 2) goes to -60 and not to
# +40 because from a blue background the POSITIVE degrees land on violet: the
# first test on screen left the seaweed lavender, which reads oddly even though
# the colour comes from the image. The other way passes through cyan and green,
# which is how seaweed is expected to look. With a background of another hue the
# whole aquarium turns, but the relative order -- seaweed and bubbles on one
# side, the castle on the other -- holds.
NORM, BRIGHT = 0.20, 0.42
pal = {
     0: sp['background'],
     1: mk(180, NORM,   0.80),   2: mk(-60, NORM,   0.65),
     3: mk( 70, NORM,   0.75),   4: mk(  0, NORM,   0.70),
     5: mk( 40, NORM,   0.60),   6: mk(-30, NORM,   0.70),
     7: sp['foreground'],
     8: c['color8'],
     9: mk(180, BRIGHT, 0.90),  10: mk(-60, BRIGHT, 0.75),
    11: mk( 70, BRIGHT, 0.85),  12: mk(  0, BRIGHT, 0.80),
    13: mk( 40, BRIGHT, 0.70),  14: mk(-30, BRIGHT, 0.80),
    15: sp['foreground'],
}

# In one go: 16 pairs in a single OSC 4 sequence, terminated by BEL.
print('\033]4;' + ';'.join('%d;%s' % (k, v) for k, v in sorted(pal.items())) + '\a', end='')
" > "$TMP" 2>/dev/null || exit 0

[ -s "$TMP" ] || exit 0
mv -f "$TMP" "$OUT"

# Running instances: the palette is written to their own terminal. No
# restarting -- the aquarium keeps swimming and only changes colour.
#
# THE PATTERN IS ANCHORED WITH '^' ON PURPOSE, AND IT IS NOT FUSSINESS.
# asciiquarium runs as 'perl /usr/bin/asciiquarium' -- its 'comm' is perl, so
# 'pgrep -x asciiquarium' does not find it and 'pgrep -x perl' cannot tell one
# script from another. That leaves matching on the command line, and without an
# anchor that catches ANY process that happens to mention the path (an editor
# with the file open, a grep, this very script quoted in a shell). Each of those
# would get the palette written to its terminal and be left tinted without any
# aquarium at all. With '^' only whatever is really running it gets in.
PAL="$(cat "$OUT")"
for pid in $(pgrep -f '^(/usr/bin/)?perl /usr/bin/asciiquarium' 2>/dev/null); do
  t="$(ps -o tty= -p "$pid" 2>/dev/null | tr -d ' ')"
  case "$t" in
    ''|'?') continue ;;
  esac
  [ -w "/dev/$t" ] && printf '%s' "$PAL" > "/dev/$t" 2>/dev/null || true
done
exit 0
