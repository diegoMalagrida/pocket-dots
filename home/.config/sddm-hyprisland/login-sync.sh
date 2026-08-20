#!/usr/bin/env bash
# Sincroniza el login (tema hyprisland de SDDM) con el wallpaper actual.
#
# Copia DOS cosas, y las dos importan: el fondo y el acento que pywal generó
# para hyprlock. Así la pantalla de arranque y el bloqueo del notch no solo se
# parecen, sino que cambian a la vez y con el mismo color.
#
# CORRE COMO TU USUARIO. No hay servicio de root detrás, y eso es el motivo de
# que este fichero exista. Antes lo hacía /usr/local/bin/sddm-wallpaper-sync.sh
# lanzado por un .path de sistema: root leía la RUTA escrita en
# ~/.cache/wal/wal -un fichero que cualquier proceso tuyo puede reescribir- y
# se la pasaba a ImageMagick. Es decir, root abría un fichero elegido por un
# proceso sin privilegios, con delegados de ImageMagick habilitados (la
# policy.xml de Arch no restringe ninguno) y dejando el resultado en 0644. Un
# proceso corriendo como tú podía sacar por ahí ficheros que solo root puede
# leer. Ahora el trabajo lo hace tu usuario y el único sitio compartido es
# $SHARED, que root posee pero tu grupo puede escribir; lo peor que cabe
# escribir ahí es un JPEG que luego carga Qt como usuario `sddm`.
#
# Lo llama set-wallpaper.sh, que es el único camino por el que cambia el fondo
# (el selector de Quickshell y awww-start.sh pasan también por él).
#
# Uso:  login-sync.sh [imagen]
#       Sin argumento coge el wallpaper que apunta ~/.cache/wal/wal.
set -uo pipefail

SHARED=/var/lib/sddm-hyprisland
WAL_FILE="$HOME/.cache/wal/wal"
LOCK_COLORS="$HOME/.cache/wal/colors-hyprlock.conf"

# Si el tema no está instalado, este directorio no existe y no hay nada que
# sincronizar. Salir con 0: esto es un extra estético, no puede tumbar el
# cambio de fondo de quien nos llama.
[ -d "$SHARED" ] && [ -w "$SHARED" ] || exit 0

# --- fondo ---------------------------------------------------------------
IMG="${1:-}"
if [ -z "$IMG" ] && [ -r "$WAL_FILE" ]; then
    IMG="$(cat "$WAL_FILE")"
fi

if [ -n "$IMG" ] && [ -f "$IMG" ]; then
    dest="$SHARED/current.jpg"
    tmp="$SHARED/.current.jpg.tmp"
    # Se re-encoda a JPEG porque el wallpaper de origen puede ser png o webp.
    #
    # El prefijo JPEG: no es adorno. ImageMagick elige el formato de salida por
    # la EXTENSIÓN, y aquí se escribe primero a un temporal acabado en .tmp, así
    # que sin él la conversión no ocurre: el fondo salía PNG de 1,1 MB dentro de
    # un fichero llamado current.jpg. Con el prefijo, 282 KB de JPEG de verdad.
    #
    # Sin ImageMagick vale el cp: el greeter carga con Qt, que mira el contenido
    # y no la extensión, así que un png llamado .jpg también se ve.
    if command -v magick >/dev/null 2>&1; then
        magick "$IMG" "JPEG:$tmp" 2>/dev/null || cp -f -- "$IMG" "$tmp"
    else
        cp -f -- "$IMG" "$tmp"
    fi
    # Renombre atómico: el greeter nunca ve un fichero a medio escribir.
    if [ -s "$tmp" ]; then
        chmod 644 "$tmp" && mv -f -- "$tmp" "$dest"
    else
        rm -f -- "$tmp"
    fi
fi

# --- acento --------------------------------------------------------------
# Fuente de verdad única: el mismo fichero que lee hyprlock. Si algún día
# cambias la plantilla ~/.config/wal/templates/colors-hyprlock.conf, el login
# sigue el cambio sin tocar nada más.
if [ -r "$LOCK_COLORS" ]; then
    acc="$(grep -oP '^\$accent\s*=\s*rgba\(\K[0-9a-fA-F]{6}' "$LOCK_COLORS" | head -1)"
    if [ -n "${acc:-}" ]; then
        tmp="$SHARED/.accent.tmp"
        printf '#%s\n' "$acc" >"$tmp" &&
            chmod 644 "$tmp" &&
            mv -f -- "$tmp" "$SHARED/accent"
    fi
fi

exit 0
