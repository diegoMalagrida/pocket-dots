#!/usr/bin/env bash
# set-face.sh — sets the portrait shown by the lock screen and the login.
#
# Both read the same file, /usr/share/sddm/faces/<user>.face.icon: it is the
# FacesDir that /etc/sddm.conf already declares (with EnableAvatars=true) and
# the only place that works for both, because the greeter runs as its own
# user and cannot get into a 0700 $HOME.
#
#   set-face.sh photo.jpg    uses that image
#   set-face.sh --camara     takes it with the webcam
#   set-face.sh --quitar     deletes it and the usual padlock comes back
#
# The image is cropped to the central square and saved at 256x256. Writing to
# /usr/share needs sudo; the rest runs as you.

set -euo pipefail

. "$HOME/.config/hypr/scripts/lang.sh" 2>/dev/null || tr_() { printf '%s' "$1"; }

FACES=/usr/share/sddm/faces
DEST="$FACES/${USER}.face.icon"
CAM=${CAM:-/dev/video0}

die() { printf '%s\n' "$*" >&2; exit 1; }

# A SINGLE TRAP, AND IT IS NOT A QUIRK.
#
# There used to be two `trap ... EXIT` here: one for the camera directory and
# another for the output png. In bash the second does NOT chain onto the first:
# it REPLACES it. So the directory with the 60 frames at 1280x720 -47 MB- was
# never deleted. And /tmp is tmpfs: that is 47 MB of RAM for every --camara, on
# the machine that already froze once from running out of memory.
#
# Both variables are declared empty before the trap so limpiar() can run even
# if the script dies before creating them. The `return 0` at the end is
# mandatory with `set -e`: a failing [ -n ] would return 1 and the trap would
# change the script's exit code.
tmp=""
out=""
limpiar() {
    [ -n "$tmp" ] && rm -rf "$tmp"
    [ -n "$out" ] && rm -f "$out"
    return 0
}
trap limpiar EXIT

case "${1:-}" in
    --quitar)
        sudo rm -f "$DEST"
        echo "$(tr_ "retrato quitado; el bloqueo vuelve a ensenar el candado" "Portrait removed; the lock screen shows the padlock again")"
        exit 0
        ;;
    --camara)
        tmp=$(mktemp -d)
        [ -e "$CAM" ] || die "$(tr_ "no hay camara en $CAM" "No camera at $CAM")"
        echo "$(tr_ "mirando a la camara… (se tiran los primeros fotogramas para que ajuste la luz)" "Capturing from the camera… (discarding the first frames while exposure adjusts)")"
        # -input_format mjpeg is not optional: with the default raw format this
        # camera delivers black frames and the photo comes out as a black
        # square, without a single error.
        ffmpeg -hide_banner -loglevel error \
               -f v4l2 -input_format mjpeg -video_size 1280x720 -i "$CAM" \
               -frames:v 60 -fps_mode passthrough "$tmp/shot%02d.png"
        src=$(ls "$tmp"/shot*.png | tail -1)
        ;;
    "")
        die "$(tr_ "uso: set-face.sh <imagen> | --camara | --quitar" "usage: set-face.sh <image> | --camara | --quitar")"
        ;;
    *)
        src=$1
        [ -f "$src" ] || die "$(tr_ "no existe: $src" "Does not exist: $src")"
        ;;
esac

out=$(mktemp --suffix=.png)

# Central square, 256x256, no metadata.
magick "$src" -auto-orient \
    -gravity center -resize 256x256^ -extent 256x256 \
    -strip "$out"

sudo install -Dm644 -o root -g root "$out" "$DEST"
echo "$(tr_ "retrato puesto en $DEST" "Portrait saved to $DEST")"
echo "$(tr_ "el bloqueo lo coge al vuelo; el login, en el proximo arranque" "The lock screen picks it up immediately; the login screen on the next boot")"
