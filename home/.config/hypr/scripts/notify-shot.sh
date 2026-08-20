#!/usr/bin/env bash
# Notificación de captura con acción "Editar": pulsar el aviso (en el notch o en
# el centro de control) abre la foto en satty.
#
# OJO al modo de funcionar: notify-send con -A implica --wait, o sea que se
# queda vivo esperando a que pulses. Por eso quien captura lo lanza al fondo.
# Y por eso lleva timeout: nuestro servidor de notificaciones (quickshell) NO
# las caduca solo — se quedan en el historial hasta que las descartas —, así
# que sin él quedaría un proceso esperando para siempre. Diez minutos de
# margen: si vas a editar la captura, la editas en ese rato.
set -uo pipefail

img="${1:-}"
[ -s "$img" ] || exit 0

# El cuerpo dice que se puede pulsar: si no, nadie descubre que la acción está
# ahí. La ruta completa no cabe (parte el aviso en tres líneas), así que solo el
# nombre del archivo.
act=$(timeout 600 notify-send -a "Captura" -i "$img" -A "edit=Editar" \
        "Captura de pantalla" "Copiada al portapapeles · pulsa para editar" 2>/dev/null) || exit 0

[ "$act" = "edit" ] && exec "$HOME/.config/hypr/scripts/screenshot-edit.sh" "$img"
