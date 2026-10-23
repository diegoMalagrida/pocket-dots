#!/usr/bin/env bash
# Generates the btop theme from the pywal palette.
#
# Two things have to be done by hand, and that is why this is a script and not
# a pywal template (pywal 3.3 only substitutes text, it has no .lighten()):
#   1) btop needs all 42 keys. It fills the missing ones from ITS default theme
#      and colours foreign to the palette sneak in.
#   2) Each metric must use a different HUE from the palette. With a single one
#      the screen looks flat and the boxes cannot be told apart.
OUT="$HOME/.cache/wal/colors-btop.theme"
J="$HOME/.cache/wal/colors.json"
[ -f "$J" ] || exit 0
mkdir -p "${OUT%/*}"
TMP=$(mktemp "${OUT}.tmp.XXXXXX") || exit 0
trap 'rm -f "$TMP"' EXIT

python3 - "$J" > "$TMP" <<'PY' || exit 0
import colorsys, json, sys

DANGER = "#fb4934"   # the system's danger red
DANGER_MIX = 0.55

c = json.load(open(sys.argv[1]))
pal, sp = c["colors"], c["special"]
bg, fg = sp["background"], sp["foreground"]


def hls(h):
    h = h.lstrip("#")
    r, g, b = (int(h[i:i + 2], 16) / 255 for i in (0, 2, 4))
    return colorsys.rgb_to_hls(r, g, b)


def hexof(h, l, s):
    r, g, b = colorsys.hls_to_rgb(h % 1.0, min(max(l, 0), 1), min(max(s, 0), 1))
    return "#%02x%02x%02x" % (round(r * 255), round(g * 255), round(b * 255))


def mix(c1, c2, t):
    r1, g1, b1 = colorsys.hls_to_rgb(*hls(c1))
    r2, g2, b2 = colorsys.hls_to_rgb(*hls(c2))
    return "#%02x%02x%02x" % tuple(
        round((a + (b_ - a) * t) * 255)
        for a, b_ in ((r1, r2), (g1, g2), (b1, b2))
    )


bh, bl, bs = hls(bg)
dark = bl < 0.5

# --- pick well-separated hues from the palette ------------------------------
# Only colours with some saturation count; a grey gives no useful hue.
cands = []
for i in range(1, 7):
    h, l, s = hls(pal[f"color{i}"])
    if s >= 0.12:
        cands.append((h, s))

if not cands:                      # grey palette: a single neutral hue
    fh, _, fs = hls(fg)
    cands = [(fh, max(fs, 0.15))]


def hue_gap(a, b):
    d = abs(a - b) % 1.0
    return min(d, 1.0 - d)


def pick(n):
    """n hues as far apart as possible; if there are not enough, they repeat in order."""
    chosen = [max(cands, key=lambda t: t[1])]      # starts with the most vivid
    while len(chosen) < n and len(chosen) < len(cands):
        far = max(cands, key=lambda t: min(hue_gap(t[0], ch[0]) for ch in chosen))
        if far in chosen:
            break
        chosen.append(far)
    while len(chosen) < n:                          # fewer hues than metrics
        chosen.append(chosen[len(chosen) % max(len(chosen), 1)])
    return chosen[:n]


# cpu / mem / net / proc: each with its own hue
(h_cpu, s_cpu), (h_mem, s_mem), (h_net, s_net), (h_proc, s_proc) = pick(4)
SAT = lambda s: min(max(s, 0.30), 0.80)


def ramp(hue, sat, lo, hi, danger=False):
    """3 stops, monotonic lightness: low value -> dim, high -> stands out."""
    if not dark:
        lo, hi = 1 - lo, 1 - hi
    st = [hexof(hue, lo, sat * 0.9), hexof(hue, (lo + hi) / 2, sat),
          hexof(hue, hi, sat)]
    if danger:
        st[1] = mix(st[1], DANGER, DANGER_MIX * 0.4)
        st[2] = mix(st[2], DANGER, DANGER_MIX)
    return st


LO, HI = (0.38, 0.86) if dark else (0.62, 0.14)
cpu = ramp(h_cpu, SAT(s_cpu), LO, HI)
temp = ramp(h_cpu, SAT(s_cpu), LO + 0.04, HI - 0.02, danger=True)
# RAM gets 4 sub-gradients: same hue, different saturations so that
# free/cached/available/used are not confused with one another.
free = ramp(h_mem, SAT(s_mem) * 0.55, LO - 0.02, HI - 0.10)
cached = ramp(h_mem, SAT(s_mem) * 0.75, LO, HI - 0.05)
avail = ramp(h_mem, SAT(s_mem) * 0.65, LO - 0.01, HI - 0.08)
used = ramp(h_mem, SAT(s_mem), LO + 0.04, HI, danger=True)
down = ramp(h_net, SAT(s_net) * 0.85, LO, HI - 0.03)
up = ramp(h_net, SAT(s_net), LO - 0.03, HI)
proc = ramp(h_proc, SAT(s_proc) * 0.8, LO + 0.04, HI, danger=True)

# Borders: each box in its own hue AND on its own lightness step. The step is
# essential: if the palette is almost monochrome (a single-colour wallpaper)
# the four hues come out the same and the boxes become indistinguishable.
BOX_LADDER = (0.34, 0.43, 0.52, 0.61) if dark else (0.66, 0.57, 0.48, 0.39)
box = lambda h, s, i: hexof(h, BOX_LADDER[i], SAT(s) * 0.75)

theme = {
    "main_bg": bg,
    "main_fg": fg,
    "title": fg,
    "hi_fg": hexof(h_cpu, 0.66 if dark else 0.40, SAT(s_cpu)),
    "selected_bg": hexof(h_cpu, 0.22 if dark else 0.82, SAT(s_cpu) * 0.45),
    "selected_fg": fg,
    "inactive_fg": hexof(bh, bl + (0.30 if dark else -0.30), bs * 0.5),
    "graph_text": hexof(bh, bl + (0.45 if dark else -0.45), bs * 0.4),
    "meter_bg": hexof(bh, bl + (0.10 if dark else -0.10), bs * 0.5),
    "proc_misc": hexof(h_proc, 0.66 if dark else 0.40, SAT(s_proc)),
    "cpu_box": box(h_cpu, s_cpu, 0),
    "mem_box": box(h_mem, s_mem, 1),
    "net_box": box(h_net, s_net, 2),
    "proc_box": box(h_proc, s_proc, 3),
    "div_line": hexof(bh, bl + (0.16 if dark else -0.16), bs * 0.4),
    "temp_start": temp[0], "temp_mid": temp[1], "temp_end": temp[2],
    "cpu_start": cpu[0], "cpu_mid": cpu[1], "cpu_end": cpu[2],
    "free_start": free[0], "free_mid": free[1], "free_end": free[2],
    "cached_start": cached[0], "cached_mid": cached[1], "cached_end": cached[2],
    "available_start": avail[0], "available_mid": avail[1], "available_end": avail[2],
    "used_start": used[0], "used_mid": used[1], "used_end": used[2],
    "download_start": down[0], "download_mid": down[1], "download_end": down[2],
    "upload_start": up[0], "upload_mid": up[1], "upload_end": up[2],
    "process_start": proc[0], "process_mid": proc[1], "process_end": proc[2],
}

print("# Generated by btop-pywal.sh (automatic, do not edit)")
for k, v in theme.items():
    print(f'theme[{k}]="{v}"')
PY

# Only a complete theme is published; if something failed, the previous one stays.
[ "$(grep -c '^theme\[' "$TMP")" -eq 42 ] && mv "$TMP" "$OUT" || exit 0

# --- tell the btops that are already open --------------------------------
# btop reads the theme at startup and does NOT watch the file, but it has a
# documented key, ctrl+R, that reloads the config and the theme from disk. We
# send it through kitty's remote control so it re-themes without closing.
command -v kitten >/dev/null 2>&1 || exit 0
pgrep -x btop >/dev/null 2>&1 || exit 0

for name in $(grep -ao '@kitty-[0-9]\+' /proc/net/unix 2>/dev/null | sort -u); do
  sock="unix:${name}"
  ids=$(kitten @ --to "$sock" ls 2>/dev/null | python3 -c '
import json, sys
try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(0)
for osw in data:
    for tab in osw.get("tabs", []):
        for w in tab.get("windows", []):
            for p in w.get("foreground_processes", []):
                if any("btop" in str(c) for c in p.get("cmdline", [])):
                    print(w["id"])
                    break
' 2>/dev/null)
  for id in $ids; do
    kitten @ --to "$sock" send-key --match "id:$id" ctrl+r >/dev/null 2>&1 || true
  done
done
exit 0
