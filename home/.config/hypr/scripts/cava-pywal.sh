#!/usr/bin/env bash
# Genera en cache un config de cava con degradado pywal y recarga cava si corre.
BASE="$HOME/.config/cava/config"
OUT="$HOME/.cache/wal/cava.conf"
J="$HOME/.cache/wal/colors.json"
[ -f "$J" ] || exit 0
[ -f "$BASE" ] || exit 0
mkdir -p "${OUT%/*}"
BLOCK=$(mktemp) || exit 0
TMP=$(mktemp "${OUT}.tmp.XXXXXX") || { rm -f "$BLOCK"; exit 0; }
trap 'rm -f "$BLOCK" "$TMP"' EXIT
{
  echo "# >>> pywal (auto, no editar)"
  echo "gradient = 1"
  python3 -c "
import json
c=json.load(open('$J'))['colors']
seq=['color6','color6','color4','color4','color5','color3','color1','color7']
for i,k in enumerate(seq,1): print(f\"gradient_color_{i} = '{c[k]}'\")
"
  echo "# <<< pywal"
} > "$BLOCK"
awk -v f="$BLOCK" '
  BEGIN { while ((getline l < f) > 0) block = block l ORS }
  /^# >>> pywal/ { skip = 1; next }
  /^# <<< pywal/ { skip = 0; next }
  skip { next }
  { print }
  /^\[color\]$/ { printf "%s", block }
' "$BASE" > "$TMP" && mv "$TMP" "$OUT"
pkill -USR1 -x cava 2>/dev/null || true
