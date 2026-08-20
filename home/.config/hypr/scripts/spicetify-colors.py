#!/usr/bin/env python3
# Genera el esquema [pywal] de un tema de spicetify desde la paleta de pywal.
#
# Las paletas pywal de muchos fondos son grises (saturación ~0-20%), así que un
# acento "tal cual" no se aprecia. Aquí tomamos el TONO (hue) dominante del
# wallpaper y le subimos saturación/luz -> un acento vivo que cambia de color
# con cada fondo, pero mantiene el tono real de la imagen.
#
# El color.ini de 'termspot' trae 19 esquemas propios (Fdeox, Synthwave...), así
# que NO se sobrescribe el fichero: se inserta/reemplaza solo el bloque [pywal]
# y el resto queda intacto (así 'git pull' del tema no pierde nada nuestro ni al
# revés, y puedes probar los esquemas de fábrica con `spicetify config
# color_scheme Fdeox`).
#
# Uso: spicetify-colors.py [ruta_color.ini]
#      (por defecto ~/.config/spicetify/Themes/termspot/color.ini)
import json, sys, os, re, colorsys

HOME = os.path.expanduser("~")
SRC  = os.path.join(HOME, ".cache/wal/colors.json")
OUT  = sys.argv[1] if len(sys.argv) > 1 else \
       os.path.join(HOME, ".config/spicetify/Themes/termspot/color.ini")

try:
    d = json.load(open(SRC))
except Exception as e:
    sys.stderr.write("no colors.json: %s\n" % e)
    sys.exit(1)

sp, c = d["special"], d["colors"]

def h2rgb(h): h = h.lstrip("#"); return tuple(int(h[i:i+2], 16) / 255 for i in (0, 2, 4))
def H(r, g, b): return "%02X%02X%02X" % (round(r*255), round(g*255), round(b*255))
def strip(x): return x.lstrip("#").upper()

cols = [c["color%d" % i] for i in range(16)]
sat  = lambda h: colorsys.rgb_to_hls(*h2rgb(h))[2]
# tono dominante = color más saturado entre los cromáticos (evita negros/grises 0,7,8,15)
best = max(cols[1:7] + cols[9:15], key=sat)
hue  = colorsys.rgb_to_hls(*h2rgb(best))[0]

mk   = lambda l, s: H(*colorsys.hls_to_rgb(hue, l, s))
bl   = colorsys.rgb_to_hls(*h2rgb(sp["background"]))[1]
# Superficies: oscuras pero CON tono, que es lo que da el aire de fósforo. La
# rampa (0.06 / 0.12 / 0.26 sobre el fondo) y la saturación 0.24 replican la
# separación del esquema Fdeox de termspot, medida sobre sus propios valores.
tint = lambda l: mk(min(l, 0.30), 0.24)

accent  = mk(0.62, 0.72)   # play / activo / barra / seleccionado
accent2 = mk(0.72, 0.72)   # hover

body = f"""text               = {strip(sp['foreground'])}
subtext            = {strip(c['color8'])}
main               = {strip(sp['background'])}
accent             = {accent}
accent-active      = {accent2}
accent-inactive    = {strip(sp['background'])}
banner             = {accent}
border-active      = {accent}
border-inactive    = {tint(bl + 0.12)}
header             = {tint(bl + 0.26)}
highlight          = {tint(bl + 0.06)}
notification       = {accent}
notification-error = FF5C57
"""

section = "[pywal]\n; generado por spicetify-colors.py desde ~/.cache/wal/colors.json — no editar a mano\n" + body

os.makedirs(os.path.dirname(OUT), exist_ok=True)
old = open(OUT).read() if os.path.exists(OUT) else ""

# Reemplaza el bloque [pywal] existente (hasta el siguiente [seccion] o EOF).
# Si no lo hay, lo añade al final dejando los esquemas del tema intactos.
pat = re.compile(r"^\[pywal\][^\[]*", re.MULTILINE)
new = pat.sub(section, old, count=1) if pat.search(old) else \
      (old.rstrip("\n") + "\n\n" + section if old.strip() else section)

open(OUT, "w").write(new)
