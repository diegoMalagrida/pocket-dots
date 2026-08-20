#!/usr/bin/env bash
# cliphist-tool.sh — el puente entre cliphist y el modo "#" del lanzador.
#
# Sustituye a ~/.config/rofi/cliphist-menu.sh + cliphist-paste.sh. La diferencia
# no es solo que ahora pinta QML: aquel par de scripts ERA el menú (rofi elegía y
# el script copiaba), y este solo sirve datos. Quien elige es LauncherPanel.
#
# Órdenes:
#   list            una línea por entrada:  id \t kind \t miniatura \t etiqueta
#                   kind = text | image ; miniatura = ruta png o "-"
#   copy   <id>     deja esa entrada en el portapapeles (texto O imagen)
#   delete <id>     la borra del historial
#
# Por qué TSV y no JSON: el portapapeles guarda texto arbitrario —comillas,
# barras, líneas sueltas— y escapar todo eso a mano en bash es justo donde se
# rompen estas cosas. Aquí la etiqueta se limpia de tabuladores y saltos y ya no
# hay ningún carácter que pueda mentir sobre dónde acaba un campo.
set -uo pipefail

cache="${XDG_CACHE_HOME:-$HOME/.cache}/cliphist/thumbs"

# Cuántas entradas se sirven. cliphist guarda hasta 750; pintarlas todas costaría
# una miniatura por cada imagen del último mes para una lista por la que nadie
# baja. 150 es historial de sobra y el JSON… el TSV cabe en un suspiro.
LIMIT=150

# Más ancho que el defecto (100) a propósito: la búsqueda del lanzador solo puede
# encontrar lo que está EN la vista previa, así que recortar aquí es recortar el
# buscador. 200 caracteres se siguen elidiendo en pantalla, pero ya se pueden
# buscar.
PREVIEW=200

# OJO: aquí NO se llama a grep, sed ni tr aunque sea lo natural en un script.
# Son 150 líneas, y un fork por línea y por campo son ~600 procesos: medido, esa
# versión tardaba 0,56 s con las miniaturas ya cacheadas. El lanzador la ejecuta
# cada vez que se abre en modo "#", así que ese medio segundo se vería. Con
# coincidencia de patrones de bash (=~, ${var//}) baja a centésimas.
list() {
    mkdir -p "$cache"
    # Se lee entero a un array en vez de `cliphist list | head -n LIMIT | while`.
    # Con la tubería, head cierra el grifo al llegar al límite, cliphist muere de
    # SIGPIPE y el script termina en 141 por culpa de pipefail: un fallo de
    # mentira que tarde o temprano acaba interpretándose como un fallo de verdad.
    # Son 750 líneas como mucho, o sea nada.
    local lines=()
    mapfile -t lines < <(cliphist -preview-width "$PREVIEW" list)
    local line id preview thumb label clean
    for line in "${lines[@]:0:$LIMIT}"; do
        id="${line%%$'\t'*}"
        preview="${line#*$'\t'}"

        if [[ $preview == *"binary data"* && $preview =~ (png|jpeg|jpg|gif|bmp|webp|tiff) ]]; then
            thumb="$cache/$id.png"
            # Cacheada por id: la primera vez cuesta un magick, las siguientes no
            # cuesta nada. El id de cliphist nunca se reutiliza, así que una
            # miniatura cacheada no puede corresponder a otra imagen.
            [ -s "$thumb" ] || cliphist decode "$id" 2>/dev/null \
                | magick - -thumbnail 200x200 "$thumb" 2>/dev/null
            [ -s "$thumb" ] || thumb="-"

            label="Imagen"
            [[ $preview =~ ([0-9]+)x([0-9]+) ]] && label="$label  ${BASH_REMATCH[1]}×${BASH_REMATCH[2]}"
            [[ $preview =~ ([0-9.]+)[[:space:]]?([KMG]iB) ]] && label="$label  ·  ${BASH_REMATCH[1]} ${BASH_REMATCH[2]}"

            printf '%s\timage\t%s\t%s\n' "$id" "$thumb" "$label"
        else
            # Tabuladores y retornos fuera: son los dos únicos caracteres que
            # podrían partir la línea por donde no toca.
            clean=${preview//$'\t'/ }
            printf '%s\ttext\t-\t%s\n' "$id" "${clean//$'\r'/ }"
        fi
    done
}

case "${1:-list}" in
    list)
        list
        ;;
    copy)
        [ -n "${2:-}" ] || exit 1
        # wl-copy hereda el tipo MIME de lo que le llega, así que una imagen se
        # pega como imagen y no como su representación en texto.
        cliphist decode "$2" | wl-copy
        ;;
    delete)
        [ -n "${2:-}" ] || exit 1
        # `cliphist delete` quiere la LÍNEA entera por la entrada estándar, no el
        # id suelto: se la buscamos en la lista para no reconstruirla a mano.
        cliphist list | grep -m1 -P "^$2\t" | cliphist delete
        ;;
    *)
        echo "uso: cliphist-tool.sh list|copy <id>|delete <id>" >&2
        exit 2
        ;;
esac
