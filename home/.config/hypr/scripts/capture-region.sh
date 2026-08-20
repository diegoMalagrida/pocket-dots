#!/usr/bin/env bash
# Selección de región SOBRE LA PANTALLA CONGELADA. Escribe el PNG en stdout.
#
# EL PROBLEMA: slurp roba el foco, y todo lo que vive del foco se cierra antes
# de que llegues a disparar — el notch (Super+D), el lanzador, un menú
# contextual, un desplegable. Capturabas el escritorio vacío justo donde estaba
# lo que querías fotografiar.
#
# LA SOLUCIÓN: hyprpicker deja una COPIA de la pantalla por encima de todo. A
# partir de ese instante, lo que hay debajo puede cerrarse, moverse o morirse:
# lo que eliges y lo que se recorta es la foto, no el escritorio vivo. La
# captura pasa a ser una cosa independiente de lo que estuvieras haciendo.
#
# Además apunta qué panel del notch estaba abierto y lo vuelve a abrir al
# terminar (congelar manda el foco fuera, y eso cancela su grab), así que hacer
# una captura ya no te cierra el centro de control.
#
# Salida 1 si cancelas (ESC o clic sin arrastrar).
set -uo pipefail

freeze=""
panel=""

salir() {
    [ -n "$freeze" ] && kill "$freeze" 2>/dev/null
    freeze=""
    # Descongelar antes de restaurar: si no, el panel se abriría por debajo de
    # la foto y no lo verías reaparecer.
    [ -n "$panel" ] && qs ipc call notch restore "$panel" >/dev/null 2>&1
    return 0
}
trap salir EXIT INT TERM HUP

if command -v qs >/dev/null 2>&1; then
    panel=$(qs ipc call notch current 2>/dev/null | tr -d '"[:space:]')
fi

if command -v hyprpicker >/dev/null 2>&1; then
    # -r congela también los monitores inactivos; -z quita la lupa del
    # cuentagotas (aquí solo queremos el congelado, no elegir un color).
    # timeout es la red: si este script muere de mala manera (SIGKILL, y el
    # trap no llega a correr), hyprpicker se quedaria vivo y verias la pantalla
    # congelada para siempre. Asi se descongela sola a los 3 minutos.
    timeout 180 hyprpicker -r -z >/dev/null 2>&1 &
    freeze=$!
    # Que la capa congelada esté arriba ANTES de slurp; si no, la selección se
    # dibuja debajo y no ves lo que estás recortando.
    sleep 0.2
fi

geom=$(slurp) || exit 1
[ -n "$geom" ] || exit 1

grim -g "$geom" -
