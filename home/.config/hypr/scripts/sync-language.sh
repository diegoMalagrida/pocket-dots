#!/usr/bin/env bash
# sync-language.sh — so the desktop has ONE language, and only one.
#
# THE PROBLEM IT SOLVES (2026-09-14): the language lives in three places and
# only one of them was updated when you changed it from Ajustes (Settings).
#
#   1. ~/.config/quickshell-rice.json   .language     <- written by Ajustes
#   2. ~/.config/hypr/language.conf     $uiLang       <- hyprlock and the scripts
#                                                        (via scripts/lang.sh)
#   3. the SDDM theme's theme.conf      language      <- the login screen
#
# NOBODY regenerated (2) live: the installer copied language.es.conf or
# language.en.conf over language.conf and there it stayed. Result measured that
# day: the shell in English, and the lock screen, the login and the scripts'
# notifications in Spanish. Exactly the "half-translated apps" the rice's
# language rule wants to avoid.
#
# This script carries (1) over to (2). (3) lives in /usr/share and belongs to
# root, so it is not touched: if it is out of step, it warns with the exact
# command.
#
# It fires by itself, via ~/.config/systemd/user/sync-language.path, every time
# quickshell-rice.json changes. It can also be called by hand.
#
# Usage: sync-language.sh [--quiet]

set -uo pipefail

. "$HOME/.config/hypr/scripts/lang.sh" 2>/dev/null || tr_() { printf '%s' "$1"; }

CONF_DIR="${XDG_CONFIG_HOME:-$HOME/.config}"
RICE_JSON="$CONF_DIR/quickshell-rice.json"
HYPR_DIR="$CONF_DIR/hypr"
DESTINO="$HYPR_DIR/language.conf"
SDDM_THEME="/usr/share/sddm/themes/hyprisland/theme.conf"

QUIET=0
[ "${1:-}" = "--quiet" ] && QUIET=1
decir() { [ "$QUIET" = "1" ] || printf '%s\n' "$*"; }

[ -r "$RICE_JSON" ] || { decir "$(tr_ "no puedo leer $RICE_JSON" "Cannot read $RICE_JSON")"; exit 0; }

# Spanish is the original: if the JSON cannot be read, lacks the key or says
# anything else, it falls back to "es". Same criterion as lang.sh: never any
# extra text, and never a blank one.
LANG_RICE="$(jq -r '.language // "es"' "$RICE_JSON" 2>/dev/null)"
RICE_LANG="$LANG_RICE"
case "$LANG_RICE" in
    es|en) ;;
    *) decir "$(tr_ "idioma no reconocido en el JSON: '$LANG_RICE' (me quedo en es)" "Unrecognised language in the JSON: '$LANG_RICE' (using es)")"; LANG_RICE=es ;;
esac

ORIGEN="$HYPR_DIR/language.$LANG_RICE.conf"
[ -r "$ORIGEN" ] || { decir "$(tr_ "falta $ORIGEN, no toco nada" "$ORIGEN is missing; leaving everything unchanged")"; exit 1; }

# --- (2) hyprlock and the scripts -----------------------------------------
if cmp -s "$ORIGEN" "$DESTINO"; then
    decir "$(tr_ "hyprlock y los scripts ya estan en '$LANG_RICE'." "hyprlock and the scripts already use '$LANG_RICE'.")"
else
    # Atomic copy: hyprlock may be reading it right now. Writing in place would
    # leave a window with the file half-written and the lock screen without text.
    TMP="$(mktemp "$DESTINO.XXXXXX")" || exit 1
    if cp "$ORIGEN" "$TMP" && mv -f "$TMP" "$DESTINO"; then
        chmod 644 "$DESTINO"
        decir "$(tr_ "language.conf -> '$LANG_RICE' (hyprlock y los scripts al dia)." "language.conf -> '$LANG_RICE' (hyprlock and scripts up to date).")"
        # hyprlock reads the file with `source` WHEN IT OPENS, so nothing needs
        # restarting: the next lock already comes up in the new language.
    else
        rm -f "$TMP"
        decir "$(tr_ "no pude escribir $DESTINO" "Could not write $DESTINO")"
        exit 1
    fi
fi

# --- (3) the login screen, which belongs to root ---------------------------
if [ -r "$SDDM_THEME" ]; then
    LANG_SDDM="$(sed -n 's/^[[:space:]]*language[[:space:]]*=[[:space:]]*\([a-z][a-z]\).*/\1/p' "$SDDM_THEME" | head -1)"
    if [ -n "$LANG_SDDM" ] && [ "$LANG_SDDM" != "$LANG_RICE" ]; then
        decir ""
        decir "$(tr_ "La pantalla de LOGIN sigue en '$LANG_SDDM'. Vive en /usr/share y es de root," "The LOGIN screen still uses '$LANG_SDDM'. It lives in /usr/share and belongs to root,")"
        decir "$(tr_ "asi que hay que ponerla a mano:" "so it must be changed manually:")"
        decir "  sudo sed -i 's/^language=.*/language=$LANG_RICE/' $SDDM_THEME"
        decir "  sudo sed -i 's/^language=.*/language=$LANG_RICE/' $CONF_DIR/sddm-hyprisland/theme.conf"
        # Visible notification only if there is a graphical session and notify-send is available.
        if [ "$QUIET" = "1" ] && command -v notify-send >/dev/null 2>&1; then
            if [ "$LANG_RICE" = "en" ]; then
                notify-send -a "Rice" "Login language" "The login screen is still in Spanish. Run sync-language.sh to see how to change it."
            else
                notify-send -a "Rice" "Idioma del login" "La pantalla de login sigue en ingles. Ejecuta sync-language.sh para ver como cambiarla."
            fi
        fi
    fi
fi
