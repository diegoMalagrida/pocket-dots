#!/bin/sh
#
# awww-start.sh -- levanta el daemon del fondo y garantiza que SIEMPRE queda un
# fondo puesto, tambien en el primer arranque de una maquina recien instalada.
#
# El fallo que motiva la segunda mitad de este script: Diego instalo el repo en
# una torre con Arch limpio, entro a Hyprland y se encontro la pantalla NEGRA
# con los colores del sistema correctos. La cadena era esta:
#
#   1. `install.sh` genera la paleta con `wal -i "$img" -n -q`. Ese `-n` le dice
#      a pywal justamente "genera la paleta pero NO pongas el fondo".
#   2. Aqui se llamaba solo a `awww restore`, que restaura *el ultimo fondo
#      mostrado*. En una maquina nueva no hay ninguno: ~/.cache/awww esta vacia.
#   3. Y `awww restore` devuelve 0 aunque no haya restaurado nada (comprobado:
#      con un HOME vacio sale con codigo 0), asi que el bucle de reintentos se
#      daba por satisfecho al primer intento y no habia ni un aviso.
#
# En el portatil no se vio nunca porque ahi ya habia un fondo puesto de antes.
#
# Ahora, despues del restore, se le PREGUNTA a awww que esta mostrando de
# verdad (`awww query` imprime "currently displaying: image: ..." o
# "... color: ..."), y solo si alguna salida se quedo sin imagen se pone un
# fondo por defecto. Esa condicion solo se cumple el primer dia: en cualquier
# arranque normal el restore funciona, la comprobacion sale bien y NO se
# re-tematiza nada -- que seria lento e inutil, porque set-wallpaper.sh
# regenera la paleta y recarga media docena de programas.

uid="$(/usr/bin/id -u)"

if ! /usr/bin/pgrep -u "$uid" -x awww-daemon >/dev/null 2>&1; then
    /usr/bin/awww-daemon >/dev/null 2>&1 &
fi

# Todo esto va en segundo plano para que el arranque de Hyprland no se quede
# esperando a que el socket del daemon exista.
(
    # Esperar al daemon. La sonda es `awww query`, no `awww restore`: query
    # falla de verdad mientras no hay socket ("Socket file ... not found") y no
    # toca nada, asi que es la comprobacion honesta de "ya esta arriba".
    listo=0
    intento=0
    while [ "$intento" -lt 50 ]; do
        if /usr/bin/awww query >/dev/null 2>&1; then
            listo=1
            break
        fi
        intento=$((intento + 1))
        /usr/bin/sleep 0.1
    done
    [ "$listo" = 1 ] || exit 0

    /usr/bin/awww restore >/dev/null 2>&1

    # ¿Se quedo alguna salida sin imagen? Se cuenta por lineas (una por monitor)
    # en vez de mirar solo la primera, para que un segundo monitor sin fondo
    # tambien lo reciba.
    salidas="$(/usr/bin/awww query 2>/dev/null | /usr/bin/wc -l)"
    con_fondo="$(/usr/bin/awww query 2>/dev/null | /usr/bin/grep -c 'currently displaying: image:')"
    [ "${salidas:-0}" -gt 0 ] || exit 0
    [ "${con_fondo:-0}" -lt "${salidas:-0}" ] || exit 0   # ya hay fondo: no tocar nada

    # Que fondo poner. Primero el que uso pywal la ultima vez (~/.cache/wal/wal
    # guarda su ruta): asi el fondo del primer arranque es EXACTAMENTE la imagen
    # de la que salio la paleta que ya esta en pantalla, y no hay un salto de
    # color raro. Si no existe o apunta a un fichero que ya no esta, se coge la
    # primera imagen de ~/Pictures/wallpapers con el mismo criterio que usa
    # install.sh (orden alfabetico), que es la misma que eligio el instalador.
    img=""
    if [ -r "$HOME/.cache/wal/wal" ]; then
        img="$(/usr/bin/head -n 1 "$HOME/.cache/wal/wal" 2>/dev/null)"
        [ -n "$img" ] && [ -f "$img" ] || img=""
    fi
    if [ -z "$img" ]; then
        img="$(/usr/bin/find "$HOME/Pictures/wallpapers" -maxdepth 1 -type f \
                 \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' \) 2>/dev/null \
               | /usr/bin/sort | /usr/bin/head -n 1)"
    fi
    [ -n "$img" ] && [ -f "$img" ] || exit 0

    # set-wallpaper.sh es el camino bueno: pone el fondo Y deja escritas las
    # cosas que `wal -i` del instalador no escribe (el enlace ~/.cache/wal/lockbg
    # que usa hyprlock, el bar-strip.txt que mira la barra, los temas derivados).
    # Necesita ~/.local/bin en el PATH y Hyprland no siempre lo hereda.
    if [ -x "$HOME/.config/hypr/set-wallpaper.sh" ]; then
        PATH="$HOME/.local/bin:/usr/local/bin:/usr/bin:$PATH"
        export PATH
        "$HOME/.config/hypr/set-wallpaper.sh" "$img" >/dev/null 2>&1
    else
        # Sin el script al menos que se vea algo.
        /usr/bin/awww img "$img" >/dev/null 2>&1
    fi
) >/dev/null 2>&1 &

exit 0
