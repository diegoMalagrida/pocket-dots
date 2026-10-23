#!/usr/bin/env bash
# Screenshot notification with an "Editar" (Edit) action: clicking the
# notification (in the notch or in the control centre) opens the picture in
# satty.
#
# MIND how it works: notify-send with -A implies --wait, i.e. it stays alive
# waiting for you to click. That is why whoever takes the screenshot launches it
# in the background. And that is why it carries a timeout: our notification
# server (quickshell) does NOT expire them by itself — they stay in the history
# until you dismiss them —, so without it a process would be left waiting for
# ever. Ten minutes of margin: if you are going to edit the screenshot, you do
# it within that time.
set -uo pipefail
#
# The notifications go through tr_() so they follow the rice's language (lang.sh
# reads the same language.conf as hyprlock, so the lock screen and these
# notifications cannot drift apart). If lang.sh were missing, the `||` leaves a
# tr_ that returns the Spanish: never any extra text, and never a blank one.
. "$HOME/.config/hypr/scripts/lang.sh" 2>/dev/null || tr_() { printf '%s' "$1"; }


img="${1:-}"
[ -s "$img" ] || exit 0

# The body says it can be clicked: otherwise nobody discovers the action is
# there. The full path does not fit (it splits the notification into three
# lines), so only the file name.
act=$(timeout 600 notify-send -a "$(tr_ Captura Screenshot)" -i "$img" -A "edit=$(tr_ 'Editar' 'Edit')" \
        "$(tr_ 'Captura de pantalla' 'Screenshot')" "$(tr_ 'Copiada al portapapeles · pulsa para editar' 'Copied to the clipboard · click to edit')" 2>/dev/null) || exit 0

[ "$act" = "edit" ] && exec "$HOME/.config/hypr/scripts/screenshot-edit.sh" "$img"
