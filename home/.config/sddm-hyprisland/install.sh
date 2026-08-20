#!/bin/bash
# Instala el tema hyprisland como pantalla de login de SDDM.
#
# Idempotente: puedes relanzarlo tras editar ~/.config/sddm-hyprisland/Main.qml
# para volver a publicar los cambios. Guarda copia de lo que sustituye.
#
# Para deshacer: ver desinstalar.sh (deja SDDM como estaba, con `silent`).
set -euo pipefail

SRC=/home/diego/.config/sddm-hyprisland
THEME=/usr/share/sddm/themes/hyprisland
SHARED=/var/lib/sddm-hyprisland
STAMP="$(date +%Y%m%d-%H%M%S)"

if [[ $EUID -ne 0 ]]; then
  echo "Este script necesita root: sudo $0" >&2
  exit 1
fi

# Quien va a mantener el fondo al dia. Con sudo es SUDO_USER; si alguien entra
# como root de verdad no hay a quien darle el permiso y se avisa al final.
USUARIO="${SUDO_USER:-}"

# --- 1. el tema ----------------------------------------------------------
install -d -m 755 "$THEME" "$THEME/backgrounds"
install -m 644 "$SRC/Main.qml"          "$THEME/Main.qml"
install -m 644 "$SRC/metadata.desktop"  "$THEME/metadata.desktop"
# El fondo que viaja con el tema es el fallback del QML: lo que se ve si aun no
# se ha cambiado de wallpaper desde que se instalo.
if [[ -f "$SRC/backgrounds/current.jpg" ]]; then
  install -m 644 "$SRC/backgrounds/current.jpg" "$THEME/backgrounds/current.jpg"
fi
# theme.conf solo la primera vez: si ya existe lleva el acento vivo de pywal.
if [[ ! -f "$THEME/theme.conf" ]]; then
  install -m 644 "$SRC/theme.conf" "$THEME/theme.conf"
fi

# --- 2. el sitio compartido ----------------------------------------------
#
# Aqui esta el motivo de que este directorio exista. El greeter corre como el
# usuario `sddm`, que no puede entrar en /home/<tu> (0700), asi que el fondo
# tiene que vivir fuera. La forma ANTERIOR de resolverlo era un servicio de
# root que iba a buscarlo a ~/.cache/wal: root abriendo una ruta escrita por un
# proceso sin privilegios, y pasandosela a ImageMagick. Eso se ha quitado.
#
# Ahora el directorio lo posee root pero tu grupo escribe en el, y quien copia
# es tu usuario (login-sync.sh). El greeter solo lee. Nadie gana privilegios
# por el camino: lo mas que cabe poner ahi es un JPEG.
install -d -m 755 "$SHARED"
if [[ -n "$USUARIO" ]]; then
  grupo="$(id -gn "$USUARIO")"
  chown "root:$grupo" "$SHARED"
  chmod 2775 "$SHARED"   # setgid: lo que se cree dentro hereda el grupo
fi

# --- 3. migracion: fuera el servicio de root -----------------------------
# Instalaciones anteriores dejaron una unidad de sistema y un script en
# /usr/local/bin. Se retiran aqui para que actualizar el tema baste.
if [[ -e /etc/systemd/system/sddm-wallpaper-sync.path ]]; then
  systemctl disable --now sddm-wallpaper-sync.path 2>/dev/null || true
  systemctl stop sddm-wallpaper-sync.service 2>/dev/null || true
  rm -f /etc/systemd/system/sddm-wallpaper-sync.path \
        /etc/systemd/system/sddm-wallpaper-sync.service
  echo "Retirado el sincronizador antiguo, que corria como root."
fi
if [[ -f /usr/local/bin/sddm-wallpaper-sync.sh ]]; then
  mv -f /usr/local/bin/sddm-wallpaper-sync.sh \
        "/usr/local/bin/sddm-wallpaper-sync.sh.retirado-$STAMP"
fi

# --- 4. decirle a SDDM que use el tema -----------------------------------
install -d -m 755 /etc/sddm.conf.d
install -m 644 "$SRC/99-hyprisland.conf" /etc/sddm.conf.d/99-hyprisland.conf

# --- 5. primer llenado: fondo y acento actuales --------------------------
#
# COMO EL USUARIO, no como root: es exactamente el mismo camino que se usara
# despues en cada cambio de fondo, asi que si algo no funciona se ve aqui.
#
# Va con `|| true` a proposito. El tema YA esta instalado a estas alturas:
# copiado, con el directorio compartido y con el drop-in de SDDM puestos. Lo de
# aqui es solo aplicarlo AHORA en vez de al proximo cambio de wallpaper, o sea
# una comodidad. Sin la guarda, un systemctl que no puede hablar con systemd
# -probado en un contenedor: "System has not been booted with systemd as init
# system"- hacia salir al script con error y el instalador anunciaba "the theme
# installer failed" cuando en realidad estaba todo en su sitio.
systemctl daemon-reload || true
if [[ -n "$USUARIO" ]]; then
  sudo -u "$USUARIO" "$SRC/login-sync.sh" || true

  # Sembrar theme.conf con el acento de ahora. El QML lee el acento vivo de
  # $SHARED/accent al arrancar, pero pinta la isla antes de que llegue esa
  # lectura: dejando aqui el valor bueno no se ve el color dar un salto.
  if [[ -r "$SHARED/accent" ]]; then
    acc="$(grep -oE '^#[0-9a-fA-F]{6}$' "$SHARED/accent" || true)"
    if [[ -n "$acc" ]]; then
      sed -i "s/^accent=.*/accent=$acc/" "$THEME/theme.conf"
    fi
  fi
fi

echo
echo "Listo. Tema instalado en $THEME"
echo "Acento actual:  $(grep '^accent=' "$THEME/theme.conf")"
echo "Fondo:          $(ls -la "$SHARED/current.jpg" 2>/dev/null || echo 'aun no, se pondra al proximo cambio de wallpaper')"
if [[ -z "$USUARIO" ]]; then
  echo
  echo "OJO: lanzado sin sudo, asi que no se quien mantendra el fondo al dia."
  echo "Dale permiso a tu usuario con:"
  echo "  sudo chown root:\$(id -gn) $SHARED && sudo chmod 2775 $SHARED"
fi
echo
echo "NO reinicies sddm ahora: cerraria tu sesion. Se vera al proximo arranque."
