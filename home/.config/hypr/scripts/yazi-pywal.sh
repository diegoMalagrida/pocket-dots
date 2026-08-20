#!/usr/bin/env bash
# Genera el flavor en cache; el config solo contiene un enlace estable.
J="$HOME/.cache/wal/colors.json"; [ -f "$J" ] || exit 0
DIR="$HOME/.config/yazi/flavors/pywal.yazi"
CACHE="$HOME/.cache/wal/yazi-pywal.yazi"
OUT="$CACHE/flavor.toml"
mkdir -p "$DIR" "$CACHE"
ln -sfn "$OUT" "$DIR/flavor.toml"
python3 - "$J" "$OUT" <<'PY'
import json,os,sys
d=json.load(open(sys.argv[1])); c=d['colors']; sp=d['special']
r={'@BG@':sp['background'],'@FG@':sp['foreground']}
for i in range(16): r[f'@C{i}@']=c[f'color{i}']
tpl='''# pywal (auto, regenerado por yazi-pywal.sh)
[mgr]
cwd = { fg = "@C6@" }
hovered = { fg = "@BG@", bg = "@C4@" }
preview_hovered = { underline = true }
find_keyword = { fg = "@C3@", bold = true }
find_position = { fg = "@C5@", bg = "reset" }
marker_copied = { fg = "@C2@", bg = "@C2@" }
marker_cut = { fg = "@C1@", bg = "@C1@" }
marker_marked = { fg = "@C6@", bg = "@C6@" }
marker_selected = { fg = "@C4@", bg = "@C4@" }
tab_active = { fg = "@BG@", bg = "@C4@" }
tab_inactive = { fg = "@FG@", bg = "@C0@" }
border_symbol = "│"
border_style = { fg = "@C8@" }
[mode]
normal_main = { fg = "@BG@", bg = "@C4@", bold = true }
normal_alt = { fg = "@C4@", bg = "@C0@" }
select_main = { fg = "@BG@", bg = "@C2@", bold = true }
select_alt = { fg = "@C2@", bg = "@C0@" }
unset_main = { fg = "@BG@", bg = "@C5@", bold = true }
unset_alt = { fg = "@C5@", bg = "@C0@" }
[status]
sep_left = { open = "", close = "" }
sep_right = { open = "", close = "" }
[pick]
border = { fg = "@C4@" }
active = { fg = "@C5@", bold = true }
[input]
border = { fg = "@C4@" }
[cmp]
border = { fg = "@C4@" }
[tasks]
border = { fg = "@C4@" }
[which]
cand = { fg = "@C6@" }
[filetype]
rules = [
  { mime = "image/*", fg = "@C3@" },
  { mime = "video/*", fg = "@C5@" },
  { mime = "audio/*", fg = "@C5@" },
  { url = "*/", fg = "@C4@" },
]
'''
for k,v in r.items(): tpl=tpl.replace(k,v)
tmp=sys.argv[2]+'.tmp'
open(tmp,'w').write(tpl)
os.replace(tmp,sys.argv[2])
PY
