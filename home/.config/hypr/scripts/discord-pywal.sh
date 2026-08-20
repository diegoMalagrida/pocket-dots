#!/usr/bin/env bash
# Genera el QuickCSS de Discord (Vencord/Vesktop) desde la paleta de pywal.
#
# Discord no tiene tematizado nativo: la unica via es un mod de cliente. Este
# script escribe el CSS; Vencord vigila quickCSS.css y lo aplica EN CALIENTE,
# sin reiniciar Discord. Si Vencord aun no esta instalado, deja el fichero
# preparado y no hace nada mas (sale 0).
J="$HOME/.cache/wal/colors.json"
[ -f "$J" ] || exit 0

# Directorios de la familia Vencord. vesktop siempre, que es el cliente que
# hay instalado: asi el tema ya esta puesto en el primer arranque, sin tener
# que volver a lanzar nada. Los demas, solo si existen -- si se creasen a
# ciegas, cada cambio de fondo resucitaria carpetas de clientes que no estan.
DIRS=("$HOME/.config/vesktop")
for d in "$HOME/.config/Vencord" "$HOME/.config/equibop" "$HOME/.config/VencordDesktop"; do
  [ -d "$d" ] && DIRS+=("$d")
done

CSS=$(python3 - "$J" <<'PY'
import colorsys, json, sys

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


bh, bl, bs = hls(bg)
dark = bl < 0.5
# Acento = el colorN mas saturado (mismo criterio que btop-pywal.sh).
ah, al, as_ = max((hls(pal[f"color{i}"]) for i in range(1, 7)), key=lambda t: t[2])
if as_ < 0.08:
    ah, al, as_ = hls(fg)

step = 0.035 if dark else -0.035
# Escalera de fondos: Discord usa varios niveles de profundidad.
tiers = {
    "deepest": hexof(bh, max(bl - step, 0), bs),
    "tertiary": hexof(bh, max(bl - step * 0.5, 0), bs),
    "primary": bg,
    "secondary": hexof(bh, bl + step, bs),
    "floating": hexof(bh, bl + step * 1.6, bs),
    "hover": hexof(bh, bl + step * 2.2, bs),
}
def _lin(x):
    return x / 12.92 if x <= 0.03928 else ((x + 0.055) / 1.055) ** 2.4


def lum(h):
    h = h.lstrip("#")
    r, g, b = (_lin(int(h[i:i + 2], 16) / 255) for i in (0, 2, 4))
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def ratio(a, b):
    la, lb = sorted((lum(a), lum(b)), reverse=True)
    return (la + 0.05) / (lb + 0.05)


def readable(col, target):
    """Aclara (u oscurece) hasta que el color se lea sobre el fondo."""
    h, l, s = hls(col)
    for _ in range(60):
        if ratio(hexof(h, l, s), bg) >= target:
            break
        l = min(l + 0.02, 1.0) if dark else max(l - 0.02, 0.0)
    return hexof(h, l, s)


accent = readable(hexof(ah, 0.55 if dark else 0.45, max(as_, 0.35)), 3.0)
accent_hi = readable(hexof(ah, 0.65 if dark else 0.38, max(as_, 0.35)), 4.5)
# Los nombres de canal y las marcas de tiempo van en este color: si se queda
# al ras del minimo no se leen. 4.0 da margen.
muted = readable(hexof(bh, bl + (0.35 if dark else -0.35), bs * 0.6), 4.0)

v = {
    # --- fondos (nombres clasicos) ---
    "--background-primary": tiers["primary"],
    "--background-secondary": tiers["secondary"],
    "--background-secondary-alt": tiers["tertiary"],
    "--background-tertiary": tiers["tertiary"],
    "--background-floating": tiers["floating"],
    "--background-accent": accent,
    "--background-modifier-hover": tiers["hover"],
    "--background-modifier-selected": tiers["hover"],
    "--background-modifier-accent": tiers["floating"],
    "--channeltextarea-background": tiers["secondary"],
    "--activity-card-background": tiers["floating"],
    # --- fondos (nombres nuevos, Discord 2024+) ---
    "--bg-base-primary": tiers["primary"],
    "--bg-base-secondary": tiers["secondary"],
    "--bg-base-tertiary": tiers["tertiary"],
    "--bg-surface-overlay": tiers["floating"],
    "--bg-surface-raised": tiers["secondary"],
    # --- texto ---
    "--text-normal": fg,
    "--text-default": fg,
    "--text-muted": muted,
    "--text-secondary": muted,
    "--text-link": accent_hi,
    "--header-primary": fg,
    "--header-secondary": muted,
    "--channels-default": muted,
    "--interactive-normal": muted,
    "--interactive-hover": fg,
    "--interactive-active": fg,
    "--interactive-muted": hexof(bh, bl + (0.18 if dark else -0.18), bs * 0.5),
    # --- acento / marca ---
    "--brand-experiment": accent,
    "--brand-500": accent,
    "--brand-560": accent_hi,
    "--button-filled-brand-background": accent,
    "--control-brand-foreground": accent_hi,
    "--scrollbar-thin-thumb": accent,
    "--scrollbar-auto-thumb": accent,
    "--scrollbar-auto-track": tiers["primary"],
}

print("/* generado por discord-pywal.sh (auto, no editar) */")
print(":root, .theme-dark, .theme-light {")
for k, val in v.items():
    print(f"  {k}: {val} !important;")
print("}")
PY
) || exit 0

# Sin las variables clave no publicamos: mejor el tema anterior que uno roto.
case "$CSS" in
  *--background-primary*--brand-experiment*) : ;;
  *) exit 0 ;;
esac

for d in "${DIRS[@]}"; do
  mkdir -p "$d/settings" || continue
  TMP=$(mktemp "$d/settings/quickCSS.css.tmp.XXXXXX") || continue
  printf '%s\n' "$CSS" > "$TMP" && mv "$TMP" "$d/settings/quickCSS.css" || rm -f "$TMP"

  # QuickCSS debe estar activado o el fichero se ignora. Solo tocamos esa
  # clave, respetando el resto de ajustes que ya tenga.
  S="$d/settings/settings.json"
  [ -f "$S" ] || printf '{}\n' > "$S"
  if command -v jq >/dev/null 2>&1; then
    TMP=$(mktemp "$S.tmp.XXXXXX") || continue
    jq '.useQuickCss = true' "$S" > "$TMP" 2>/dev/null && mv "$TMP" "$S" || rm -f "$TMP"
  fi
done
exit 0
