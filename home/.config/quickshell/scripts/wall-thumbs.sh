#!/usr/bin/env bash
# wall-thumbs.sh — mantiene ~/.cache/wallpaper-thumbs sincronizado con
# ~/Pictures/wallpapers para que el picker no tenga que descomprimir los
# originales (hasta 6 MB cada uno) solo para pintar una carta.
#
# Cada miniatura se llama <fichero original>.jpg — p. ej. "dl-1785759993.png.jpg".
# Conservar la extensión original dentro del nombre permite al picker recuperar
# la ruta real quitando el ".jpg" final, sin ambigüedad entre un .png y un .jpg
# que se llamen igual, y mantiene el mismo orden alfabético que los originales.
set -u

SRC="${1:-$HOME/Pictures/wallpapers}"
DST="${2:-$HOME/.cache/wallpaper-thumbs}"
# La carta hero del coverflow pinta la imagen a 874x406 px. El '^' de ImageMagick
# escala por COBERTURA (ambos lados quedan >= al mínimo, no <=), así que ninguna
# miniatura se queda corta y hay que ampliarla: un 4:3 a "x500" salía a 667 px de
# ancho y se veía blanda. El pequeño margen absorbe futuros retoques de la carta.
GEOM="900x420^"
JOBS=4

command -v magick >/dev/null 2>&1 || exit 0
[ -d "$SRC" ] || exit 0
mkdir -p "$DST" || exit 0

# 1) Generar las que falten o se hayan quedado desfasadas.
while IFS= read -r -d '' img; do
    out="$DST/$(basename "$img").jpg"
    # -nt: solo se regenera si el original es más nuevo que su miniatura.
    if [ -s "$out" ] && [ ! "$img" -nt "$out" ]; then
        continue
    fi
    # Escribir a temporal y renombrar: el picker vigila esta carpeta y, si magick
    # volcase directamente sobre "$out", Qt puede leer el fichero a medias y la
    # carta queda rota con "Unsupported image format". El rename sí es atómico.
    ( magick "$img" -auto-orient -thumbnail "$GEOM" -strip -quality 85 "$out.tmp" 2>/dev/null \
        && mv -f -- "$out.tmp" "$out" || rm -f -- "$out.tmp" ) &
    while [ "$(jobs -rp | wc -l)" -ge "$JOBS" ]; do wait -n; done
done < <(find "$SRC" -maxdepth 1 -type f \
    \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' \) -print0)
wait

# 2) Restos de una ejecución interrumpida.
find "$DST" -maxdepth 1 -type f -name '*.jpg.tmp' -delete 2>/dev/null

# 3) Tirar las huérfanas: wallpaper borrado o renombrado -> fuera del picker.
while IFS= read -r -d '' thumb; do
    base="$(basename "$thumb")"
    [ -f "$SRC/${base%.jpg}" ] || rm -f -- "$thumb"
done < <(find "$DST" -maxdepth 1 -type f -name '*.jpg' -print0)

exit 0
