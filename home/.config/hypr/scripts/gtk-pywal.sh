#!/usr/bin/env bash
# Hace que las aplicaciones GTK YA ABIERTAS cojan la paleta nueva, sin cerrarlas.
#
# El problema: ~/.config/gtk-3.0/gtk.css y gtk-4.0/gtk.css no llevan colores,
# llevan un @import de ~/.cache/wal/colors-gtk.css. Cuando pywal reescribe ese
# fichero, GTK ni se entera: el import se resolvio una vez, al arrancar la
# aplicacion. Medido con pavucontrol delante -no se movio ni cambiando la
# paleta, ni haciendo touch de los dos gtk.css, ni cambiando gtk-theme-name.
#
# Lo que si funciona es el portal de apariencia. libadwaita y GTK escuchan
# org.freedesktop.appearance del portal xdg-desktop-portal, y cuando les llega
# un cambio de color-scheme reconstruyen su cascada de estilos entera - y al
# reconstruirla vuelven a leer el gtk.css del usuario, o sea el @import con los
# colores nuevos. Asi que se les da un tiron del color-scheme y se devuelve
# enseguida al que estaba. Medido: pavucontrol pasa de #0B1018 a #0D0F11, que
# son exactamente los dos fondos de pywal.
#
# El precio son 0,15 s de tema claro en las aplicaciones GTK que esten abiertas
# (y en Chrome, que tambien escucha el portal). Es el minimo que funciona: por
# debajo, el portal no llega a propagar los dos cambios. Si algun dia molesta
# mas de lo que aporta, se quita la llamada de set-wallpaper.sh y las
# aplicaciones simplemente cogeran el color al abrirse, como antes.
set -uo pipefail

ESQUEMA="org.gnome.desktop.interface color-scheme"

actual=$(gsettings get ${ESQUEMA} 2>/dev/null) || exit 0
actual=${actual//\'/}
[ -n "$actual" ] || exit 0

case "$actual" in
  prefer-dark) otro=prefer-light ;;
  *)           otro=prefer-dark  ;;
esac

# Pase lo que pase se vuelve al esquema que tenia: dejarlo en claro seria peor
# que no haber hecho nada.
restaurar() { gsettings set ${ESQUEMA} "$actual" 2>/dev/null || true; }
trap restaurar EXIT INT TERM

gsettings set ${ESQUEMA} "$otro" 2>/dev/null || exit 0
sleep 0.15
