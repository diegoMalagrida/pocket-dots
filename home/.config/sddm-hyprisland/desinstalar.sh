#!/bin/bash
# Vuelve SDDM a su tema anterior y retira todo lo que puso install.sh.
set -euo pipefail

THEME=/usr/share/sddm/themes/hyprisland
SHARED=/var/lib/sddm-hyprisland

if [[ $EUID -ne 0 ]]; then
  echo "Este script necesita root: sudo $0" >&2
  exit 1
fi

rm -f /etc/sddm.conf.d/99-hyprisland.conf
rm -rf "$SHARED"

# Por si queda algo de la epoca en que esto lo hacia un servicio de root. No se
# restaura: tenia el fallo que motivo el rediseno -root abriendo una ruta
# escrita por un proceso sin privilegios- y no merece la pena revivirlo por un
# fondo de pantalla.
if [[ -e /etc/systemd/system/sddm-wallpaper-sync.path ]]; then
  systemctl disable --now sddm-wallpaper-sync.path 2>/dev/null || true
  rm -f /etc/systemd/system/sddm-wallpaper-sync.path \
        /etc/systemd/system/sddm-wallpaper-sync.service
fi
rm -f /usr/local/bin/sddm-wallpaper-sync.sh
systemctl daemon-reload || true

echo 'SDDM vuelve a su tema por defecto. El tema hyprisland sigue en'
echo "$THEME por si lo quieres recuperar: sudo ~/.config/sddm-hyprisland/install.sh"
echo
echo 'Si vuelves al tema `silent`, su fondo ya no se actualiza solo: se quedara'
echo 'con el que tuviera puesto.'
