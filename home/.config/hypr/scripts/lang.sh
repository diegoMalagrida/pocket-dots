# lang.sh — the language of the Hyprland scripts' notifications.
#
# It is not executed: the other scripts load it with `source`.
#
#   . "$HOME/.config/hypr/scripts/lang.sh" 2>/dev/null || tr_() { printf '%s' "$1"; }
#   notify-send "$(tr_ 'Luz nocturna' 'Night light')" "$(tr_ 'Activada' 'On')"
#
# Spanish is the original and ALWAYS goes first; if the language file is
# missing, if the line is not there or if it says anything else, Spanish comes
# out. That is the failure mode we want: never extra text, and never, ever
# blank text.
#
# The source of truth is ~/.config/hypr/language.conf, the SAME file hyprlock
# loads, so the lock screen and these notifications do not drift apart.
# $RICE_LANG in the environment wins, which is handy for testing without
# touching anything:
#   RICE_LANG=en ~/.config/hypr/scripts/hyprsunset-toggle.sh

if [ -z "${RICE_LANG:-}" ]; then
    RICE_LANG=es
    _rice_lang_conf="${XDG_CONFIG_HOME:-$HOME/.config}/hypr/language.conf"
    if [ -r "$_rice_lang_conf" ]; then
        # No grep or sed: the file is two lines long, and this is loaded by
        # scripts fired from a key press.
        while IFS= read -r _rice_lang_line || [ -n "$_rice_lang_line" ]; do
            case "$_rice_lang_line" in
                '$uiLang'*=*)
                    _rice_lang_value="${_rice_lang_line#*=}"
                    _rice_lang_value="${_rice_lang_value// /}"
                    _rice_lang_value="${_rice_lang_value//$'\t'/}"
                    [ -n "$_rice_lang_value" ] && RICE_LANG="$_rice_lang_value"
                    ;;
            esac
        done < "$_rice_lang_conf"
    fi
    unset _rice_lang_conf _rice_lang_line _rice_lang_value
fi

# tr_ SPANISH ENGLISH
tr_() {
    if [ "$RICE_LANG" = en ]; then printf '%s' "$2"; else printf '%s' "$1"; fi
}
