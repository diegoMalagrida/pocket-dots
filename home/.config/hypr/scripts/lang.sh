# lang.sh — el idioma de los avisos de los scripts de Hyprland.
#
# No se ejecuta: se carga con `source` desde los demas scripts.
#
#   . "$HOME/.config/hypr/scripts/lang.sh" 2>/dev/null || tr_() { printf '%s' "$1"; }
#   notify-send "$(tr_ 'Luz nocturna' 'Night light')" "$(tr_ 'Activada' 'On')"
#
# El castellano es el original y va SIEMPRE primero; si falta el fichero de
# idioma, si la linea no esta o si dice cualquier otra cosa, sale el castellano.
# Ese es el modo de fallo que interesa: texto de mas nunca, texto en blanco
# jamas.
#
# La fuente de verdad es ~/.config/hypr/language.conf, la MISMA que carga
# hyprlock, para que la pantalla de bloqueo y estos avisos no se separen.
# $RICE_LANG en el entorno gana, que va bien para probar sin tocar nada:
#   RICE_LANG=en ~/.config/hypr/scripts/hyprsunset-toggle.sh

if [ -z "${RICE_LANG:-}" ]; then
    RICE_LANG=es
    _rice_lang_conf="${XDG_CONFIG_HOME:-$HOME/.config}/hypr/language.conf"
    if [ -r "$_rice_lang_conf" ]; then
        # Sin grep ni sed: son dos lineas de fichero y esto lo cargan scripts
        # que se disparan con una tecla.
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

# tr_ CASTELLANO INGLES
tr_() {
    if [ "$RICE_LANG" = en ]; then printf '%s' "$2"; else printf '%s' "$1"; fi
}
