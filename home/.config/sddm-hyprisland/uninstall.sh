#!/bin/bash
# Returns SDDM to its previous theme and removes everything install.sh put in.
set -euo pipefail

THEME=/usr/share/sddm/themes/hyprisland
SHARED=/var/lib/sddm-hyprisland

if [[ $EUID -ne 0 ]]; then
  echo "This script requires root: sudo $0" >&2
  exit 1
fi

rm -f /etc/sddm.conf.d/99-hyprisland.conf
rm -rf "$SHARED"

# install.sh commented out in /etc/sddm.conf the keys that overrode the drop-in
# (Current, GreeterEnvironment, InputMethod) and left a dated copy. The oldest
# one is restored, which is the file exactly as it was BEFORE this theme
# touched anything: the later ones already carry the previous one's edits.
copia="$(ls -1 /etc/sddm.conf.hyprisland-*.bak 2>/dev/null | head -1)"
if [[ -n "$copia" ]]; then
  cp -a "$copia" /etc/sddm.conf
  echo "Restored /etc/sddm.conf from $copia"
fi

# In case anything is left from the days when a root service did this. It is
# not restored: it had the flaw that prompted the redesign -root opening a path
# written by an unprivileged process- and it is not worth reviving for a
# wallpaper.
if [[ -e /etc/systemd/system/sddm-wallpaper-sync.path ]]; then
  systemctl disable --now sddm-wallpaper-sync.path 2>/dev/null || true
  rm -f /etc/systemd/system/sddm-wallpaper-sync.path \
        /etc/systemd/system/sddm-wallpaper-sync.service
fi
rm -f /usr/local/bin/sddm-wallpaper-sync.sh
systemctl daemon-reload || true

echo 'SDDM is back to its default theme. The hyprisland theme remains in'
echo "$THEME if you want to restore it: sudo ~/.config/sddm-hyprisland/install.sh"
echo
echo 'If you return to the `silent` theme, its wallpaper will no longer update automatically:'
echo 'it will keep the wallpaper it already had.'
