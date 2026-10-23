#!/bin/bash
# Installs the hyprisland theme as SDDM's login screen.
#
# Idempotent: you can run it again after editing
# ~/.config/sddm-hyprisland/Main.qml to republish the changes. It keeps a copy
# of whatever it replaces.
#
# To undo: see uninstall.sh (it leaves SDDM as it was, with `silent`).
set -euo pipefail

SRC=/home/diego/.config/sddm-hyprisland
THEME=/usr/share/sddm/themes/hyprisland
SHARED=/var/lib/sddm-hyprisland
STAMP="$(date +%Y%m%d-%H%M%S)"

if [[ $EUID -ne 0 ]]; then
  echo "This script requires root: sudo $0" >&2
  exit 1
fi

# Who is going to keep the wallpaper up to date. With sudo it is SUDO_USER; if
# someone logs in as real root there is nobody to give the permission to, and
# a warning is shown at the end.
USUARIO="${SUDO_USER:-}"

# --- 1. the theme --------------------------------------------------------
install -d -m 755 "$THEME" "$THEME/backgrounds"
install -m 644 "$SRC/Main.qml"          "$THEME/Main.qml"
install -m 644 "$SRC/metadata.desktop"  "$THEME/metadata.desktop"
# The wallpaper that travels with the theme is the QML's fallback: what you see
# if the wallpaper has not been changed yet since it was installed.
if [[ -f "$SRC/backgrounds/current.jpg" ]]; then
  install -m 644 "$SRC/backgrounds/current.jpg" "$THEME/backgrounds/current.jpg"
fi
# theme.conf is copied ALWAYS, and not only the first time as it used to be.
#
# That looked prudent -"if it already exists, it carries pywal's live accent,
# do not overwrite it"- but it meant that no new theme key ever reached the
# system. On 6 September 2026 the installed theme.conf was still the one from
# 21 August and it lacked `language`, which the theme already read. The accent
# is not lost by copying: step 5 seeds it again a few lines below with the
# value from $SHARED/accent, which is the live one.
install -m 644 "$SRC/theme.conf" "$THEME/theme.conf"

# --- 2. the shared place -------------------------------------------------
#
# Here is the reason this directory exists. The greeter runs as the `sddm`
# user, which cannot get into /home/<you> (0700), so the wallpaper has to live
# outside. The PREVIOUS way of solving it was a root service that went to
# fetch it from ~/.cache/wal: root opening a path written by an unprivileged
# process, and handing it to ImageMagick. That has been removed.
#
# Now root owns the directory but your group writes to it, and the one who
# copies is your user (login-sync.sh). The greeter only reads. Nobody gains
# privileges along the way: the most that can be put there is a JPEG.
install -d -m 755 "$SHARED"
if [[ -n "$USUARIO" ]]; then
  grupo="$(id -gn "$USUARIO")"
  chown "root:$grupo" "$SHARED"
  chmod 2775 "$SHARED"   # setgid: whatever is created inside inherits the group
fi

# --- 3. migration: out with the root service -----------------------------
# Earlier installs left a system unit and a script in /usr/local/bin. They
# are retired here so that updating the theme is enough.
if [[ -e /etc/systemd/system/sddm-wallpaper-sync.path ]]; then
  systemctl disable --now sddm-wallpaper-sync.path 2>/dev/null || true
  systemctl stop sddm-wallpaper-sync.service 2>/dev/null || true
  rm -f /etc/systemd/system/sddm-wallpaper-sync.path \
        /etc/systemd/system/sddm-wallpaper-sync.service
  echo "Removed the old synchroniser that ran as root."
fi
if [[ -f /usr/local/bin/sddm-wallpaper-sync.sh ]]; then
  mv -f /usr/local/bin/sddm-wallpaper-sync.sh \
        "/usr/local/bin/sddm-wallpaper-sync.sh.retirado-$STAMP"
fi

# --- 4. tell SDDM to use the theme ---------------------------------------
install -d -m 755 /etc/sddm.conf.d
install -m 644 "$SRC/99-hyprisland.conf" /etc/sddm.conf.d/99-hyprisland.conf

# And now the part without which everything above is COMPLETELY USELESS.
#
# In SDDM, /etc/sddm.conf is read AFTER /etc/sddm.conf.d/*.conf -the other way
# round from systemd-, so it is the main file that wins. This theme was
# installed from 11 August 2026 without ever being seen a single time: the
# drop-in set Current=hyprisland and /etc/sddm.conf put it back to `silent` an
# instant later. It was discovered on 6 September by reading the boot journal,
# which says it unambiguously:
#
#   sddm[526]: Starting X11 session: "/usr/bin/sddm-greeter-qt6
#              --theme /usr/share/sddm/themes/silent"
#
# There are three keys that override the drop-in: Current (the theme), and
# also GreeterEnvironment and InputMethod, which point to `silent`'s QML
# components and its virtual keyboard, none of which this island uses.
#
# They are COMMENTED OUT instead of deleted, with a dated backup alongside, for
# two reasons: uninstall.sh can put them back as they were, and whoever
# opens the file a year from now sees why they went.
if [[ -f /etc/sddm.conf ]]; then
  tocadas=()
  for clave in Current GreeterEnvironment InputMethod; do
    grep -qE "^[[:space:]]*$clave=" /etc/sddm.conf && tocadas+=("$clave")
  done
  if (( ${#tocadas[@]} )); then
    cp -a /etc/sddm.conf "/etc/sddm.conf.hyprisland-$STAMP.bak"
    for clave in "${tocadas[@]}"; do
      sed -i -E "s|^([[:space:]]*$clave=.*)\$|# hyprisland: esta linea pisaba a /etc/sddm.conf.d/99-hyprisland.conf\n#\1|" \
        /etc/sddm.conf
    done
    echo "Commented out ${tocadas[*]} in /etc/sddm.conf because they overrode the drop-in."
    echo "Backup of the previous config: /etc/sddm.conf.hyprisland-$STAMP.bak"
  fi
fi

# --- 5. first fill: current wallpaper and accent -------------------------
#
# AS THE USER, not as root: it is exactly the same path that will be used
# later on every wallpaper change, so if something does not work you see it
# here.
#
# It carries `|| true` on purpose. The theme IS already installed by now:
# copied, with the shared directory and SDDM's drop-in in place. What happens
# here is only applying it NOW instead of at the next wallpaper change, that
# is, a convenience. Without the guard, a systemctl that cannot talk to systemd
# -tested in a container: "System has not been booted with systemd as init
# system"- made the script exit with an error and the installer announced "the
# theme installer failed" when in fact everything was in its place.
systemctl daemon-reload || true
if [[ -n "$USUARIO" ]]; then
  sudo -u "$USUARIO" "$SRC/login-sync.sh" || true

  # Seed theme.conf with the current accent. The QML reads the live accent from
  # $SHARED/accent at startup, but it paints the island before that read
  # arrives: leaving the right value here, the colour is not seen to jump.
  if [[ -r "$SHARED/accent" ]]; then
    acc="$(grep -oE '^#[0-9a-fA-F]{6}$' "$SHARED/accent" || true)"
    if [[ -n "$acc" ]]; then
      sed -i "s/^accent=.*/accent=$acc/" "$THEME/theme.conf"
    fi
  fi
fi

echo
echo "Done. Theme installed in $THEME"
echo "Current accent:  $(grep '^accent=' "$THEME/theme.conf")"
echo "Wallpaper:      $(ls -la "$SHARED/current.jpg" 2>/dev/null || echo 'not yet; it will be set on the next wallpaper change')"
if [[ -z "$USUARIO" ]]; then
  echo
  echo "WARNING: started without sudo, so the user responsible for wallpaper updates is unknown."
  echo "Grant your user permission with:"
  echo "  sudo chown root:\$(id -gn) $SHARED && sudo chmod 2775 $SHARED"
fi
echo
echo "DO NOT restart sddm now: it would end your session. The theme will appear on the next boot."
