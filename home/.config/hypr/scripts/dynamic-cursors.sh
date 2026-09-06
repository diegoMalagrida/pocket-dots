#!/usr/bin/env bash
# dynamic-cursors.sh — shake to find: agitar el ratón agranda el cursor para
# encontrarlo, como en macOS. Carga el plugin hypr-dynamic-cursors (compilado
# a mano en ~/.local/share/hypr-dynamic-cursors contra el commit que su
# hyprpm.toml pina para la versión EXACTA de Hyprland) y lo deja SOLO con el
# shake: mode none apaga las físicas del cursor (estirar/rotar), que aquí no
# se quieren.
#
# Si Hyprland/aquamarine se actualizan, el .so deja de casar con el compositor
# vivo ("version mismatch"): entonces este script busca el pin del commit del
# Hyprland EN EJECUCIÓN, recompila y reintenta, avisando por notificación.
# Ojo: si la sesión es más vieja que el paquete instalado (actualizar sin
# reiniciar sesión), no hay pin que valga — tocará esperar al siguiente login.

# El zoom sale NÍTIDO si hay un tema hyprcursor (SVG) instalado en
# ~/.local/share/icons con el mismo nombre que tu tema de cursor -- aquí,
# Bibata-Modern-Ice, de las releases de rtgiskard/bibata_cursor. No se
# versiona: son 340 KB de binarios de terceros. Sin él no se rompe nada, el
# plugin agranda el bitmap del XCursor y se ve algo más blando.
REPO="$HOME/.local/share/hypr-dynamic-cursors"
SO="$REPO/out/dynamic-cursors.so"

[ -d "$REPO" ] || exit 0

cargar() { hyprctl plugin load "$SO" 2>&1; }

cargado() { hyprctl plugin list 2>/dev/null | grep -q dynamic-cursors; }

aplicar_config() {
    # La config del plugin VIVE EN hyprland.lua (bloque pcall "Shake to
    # find"), no aqui: cada reload resetea las opciones del plugin a defaults
    # (mode=tilt), asi que tiene que reaplicarse en cada re-evaluacion del
    # .lua. Este reload es el que hace efectivo ese bloque tras cargar el
    # plugin (en el parseo del arranque las claves aun no existian).
    hyprctl reload >/dev/null 2>&1
}

pin_para_hyprland_vivo() {
    local hl
    hl=$(hyprctl -j version 2>/dev/null | jq -r '.commit')
    [ -n "$hl" ] || return 1
    local pin
    pin=$(sed -n "s/.*\"$hl\", \"\([0-9a-f]\{40\}\)\".*/\1/p" "$REPO/hyprpm.toml" | head -1)
    if [ -z "$pin" ]; then
        # El hyprpm.toml local aún no conoce esta versión: traer el de main.
        git -C "$REPO" fetch -q origin main 2>/dev/null &&
            git -C "$REPO" checkout -q origin/main -- hyprpm.toml 2>/dev/null
        pin=$(sed -n "s/.*\"$hl\", \"\([0-9a-f]\{40\}\)\".*/\1/p" "$REPO/hyprpm.toml" | head -1)
    fi
    [ -n "$pin" ] && printf '%s' "$pin"
}

compilar() {
    local pin
    pin=$(pin_para_hyprland_vivo) || return 1
    [ -n "$pin" ] || return 1
    git -C "$REPO" fetch -q origin "$pin" 2>/dev/null
    # -f: descarta el parche local viejo antes de saltar de commit.
    git -C "$REPO" checkout -q -f "$pin" 2>/dev/null || return 1
    # El toml del pin no trae su propio pin (se añade después en main):
    # dejarlo siempre al día para la próxima búsqueda.
    git -C "$REPO" checkout -q origin/main -- hyprpm.toml 2>/dev/null || true
    # Re-aplica el PARCHE local en highres.cpp: el zoom del shake debe
    # cargar el tema SVG aunque cursor:enable_hyprcursor esté apagado
    # (apagado a propósito: el cursor NORMAL es el XCursor de siempre).
    # Si upstream cambia esa línea, el sed no casa y se compila SIN
    # parche (zoom borroso pero funcional) — mejor que no compilar.
    sed -i 's/ || !\*PUSEHYPRCURSOR//' "$REPO/src/highres.cpp" 2>/dev/null || true
    make -s -C "$REPO" all >/dev/null 2>&1
}

# Recién clonado: packages/git-repos.txt trae el repo, pero no el .so, que hay
# que compilar contra la versión de Hyprland de ESTA máquina. Solo pasa una vez.
if [ ! -f "$SO" ]; then
    notify-send -u low "Shake to find" "Compilando dynamic-cursors por primera vez…" 2>/dev/null || true
    compilar || true
fi

salida=$(cargar)
case "$salida" in
*"version mismatch"*)
    notify-send -u low "Shake to find" "Recompilando dynamic-cursors para este Hyprland…" 2>/dev/null || true
    compilar && salida=$(cargar)
    ;;
esac

if cargado; then
    aplicar_config
else
    notify-send -u normal "Shake to find" "dynamic-cursors no pudo cargarse: ${salida:0:120}" 2>/dev/null || true
fi
