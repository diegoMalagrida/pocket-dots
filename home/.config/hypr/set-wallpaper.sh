#!/usr/bin/env bash
# set-wallpaper.sh <imagen> — cambia el fondo y re-tematiza TODO (pywal) en caliente.
set -uo pipefail
IMG="${1:-}"
[ -z "$IMG" ] && { echo "uso: set-wallpaper.sh <imagen>"; exit 1; }
[ -f "$IMG" ] || { echo "no existe: $IMG"; exit 1; }
IMG="$(realpath -- "$IMG")" || exit 1

# --saturate 0.5: sube la saturación de la paleta para colores más vivos (0.4 suave, 0.6 fuerte, quítalo para el original)
if ! wal -i "$IMG" --saturate 0.5 -n -q -s -t; then
  notify-send -u critical "Tema dinámico" "Pywal no pudo generar la paleta" 2>/dev/null || true
  exit 1
fi
ln -sfn -- "$IMG" "$HOME/.cache/wal/lockbg"  # fondo de bloqueo sigue al wallpaper

# El login (tema hyprisland de SDDM) sigue al wallpaper igual que el bloqueo.
# Corre como tú, no como root: ver el comentario de cabecera de login-sync.sh.
# En segundo plano porque re-encoda la imagen y no tiene por qué retrasar la
# transición del fondo, que es lo que se ve.
[ -x "$HOME/.config/sddm-hyprisland/login-sync.sh" ] &&
    "$HOME/.config/sddm-hyprisland/login-sync.sh" "$IMG" >/dev/null 2>&1 &

# Color REAL de la franja donde vive la barra. Hace falta porque la barra no
# tiene superficie propia: sus cuerpos se pintan directamente sobre el
# wallpaper, y para saber si se van a ver hay que medir contra lo que hay
# DETRAS. El `background` de pywal no sirve para eso: es un derivado oscurecido
# de la paleta, no un trozo de la imagen (medido con este mismo fondo: 0.011 de
# luminancia contra 0.087 de la franja de verdad, ocho veces mas oscura), asi
# que calcular contra el deja los cuerpos apagados justo donde el fondo es
# claro. Esto promedia el 5 % de arriba de la imagen y lo deja donde Colors.qml
# lo vigila. Si magick falla, el fichero queda vacio y Colors tira del
# background de pywal como antes.
magick "$IMG" -gravity north -crop '100%x5%+0+0' +repage -alpha off -resize 1x1! txt:- 2>/dev/null \
  | awk 'NR==2 && $3 ~ /^#[0-9A-Fa-f]{6}$/ {print $3}' > "$HOME/.cache/wal/bar-strip.txt" || true

# Spotify, LO PRIMERO de los recargados y en segundo plano.
#
# Estaba el último de la lista y se notaba: la barra y las terminales ya habían
# cambiado de color y Spotify seguía azul un segundo y medio largo. Medido sobre
# el vídeo del escritorio, cambiando el fondo con Spotify delante: el fondo
# entraba, la barra cambiaba, y el repintado de Spotify llegaba 1,3-1,7 s
# después. No es que sea lento -el push por DevTools tarda 0,07 s- es que le
# tocaba el último turno detrás de yazi, cava, btop y discord.
#
# Ahora sale aquí, con la paleta recién escrita y ANTES de que empiece la
# transición del fondo, y en segundo plano para no retrasarla. Así el fondo y la
# ventana más grande de la pantalla cambian a la vez, que es como se lee que el
# sistema entero es uno.
~/.config/hypr/scripts/spicetify-pywal.sh >/dev/null 2>&1 &

# El fondo es visual; un fallo de awww no invalida la paleta recién generada.
# apply estilo ilyamiro: transición aleatoria + desde el centro + 144fps + 1s
awww_transitions=(simple fade left right top bottom wipe grow center outer random wave)
awww_rt="${awww_transitions[RANDOM % ${#awww_transitions[@]}]}"
awww img "$IMG" --transition-type "$awww_rt" --transition-pos 0.5,0.5 --transition-fps 144 --transition-duration 1 >/dev/null 2>&1 || awww img "$IMG" >/dev/null 2>&1 || true

# Recargas de daemons vivos.
# Quickshell (barra + notch) NO necesita recarga: Colors.qml vigila
# ~/.cache/wal/colors.json y se recolorea solo.
pkill -SIGUSR1 -x kitty  2>/dev/null || true
hyprctl reload           >/dev/null 2>&1 || true
# swaync retirado el 2026-08-05: el servidor de notificaciones es el de Quickshell
~/.config/hypr/scripts/yazi-pywal.sh 2>/dev/null || true
~/.config/hypr/scripts/cava-pywal.sh 2>/dev/null || true
# VS Code retirado el 2026-08-11: el tematizado por pywal quedaba feo mirase
# como se mirase, y no hay forma de que un editor entero salga bonito a partir
# de cinco colores de un fondo de pantalla. Se queda con su tema de fabrica.
# El script esta guardado en ~/.audit-backups/2026-08-12/bak-files/.
~/.config/hypr/scripts/btop-pywal.sh 2>/dev/null || true
~/.config/hypr/scripts/discord-pywal.sh 2>/dev/null || true
# (spicetify ya se ha lanzado arriba, antes de la transición del fondo)
# Re-ordena los sprites de pokemon para la paleta nueva (~0.1 s) para que la
# proxima terminal ya saque los que pegan. Si falla, pokefetch tira del azar.
# (ruta absoluta: hyprland no siempre hereda ~/.local/bin en el PATH)
[ -x "$HOME/.local/bin/poke-theme" ] && "$HOME/.local/bin/poke-theme" rank -q >/dev/null 2>&1 &
# (rofi, btop, wlogout, hyprlock leen sus colores al abrirse -> sin recarga)
exit 0
