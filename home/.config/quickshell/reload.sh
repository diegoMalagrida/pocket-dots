#!/usr/bin/env bash
# Recarga limpia de Quickshell (barra + notch + sidebar + overview + wallpaper).
# Normalmente NO hace falta: quickshell vigila sus .qml y recarga en caliente.
# Esto es la red de seguridad cuando algo se queda colgado.

# UN reload cada vez. Pulsar Super+G varias veces seguidas abria varias barras:
# cada copia del script mataba a qs, dormia 0.4s a ojo y arrancaba el suyo, asi
# que los tres pkill se gastaban al principio -- cuando aun no habia nada que
# matar -- y los tres qs nacian despues, sin estorbarse. El cerrojo descarta las
# pulsaciones que lleguen con un reload en marcha, que es lo que quieres: no
# tiene sentido encolar recargas.
exec 9>"${XDG_RUNTIME_DIR:-/tmp}/quickshell-reload.lock"
flock -n 9 || exit 0

pkill -x qs 2>/dev/null

# Esperar a que muera DE VERDAD en vez de confiar en un sleep fijo: si tarda mas
# de lo previsto, el viejo y el nuevo acaban solapados.
for _ in {1..50}; do
    pgrep -x qs >/dev/null || break
    sleep 0.1
done
pgrep -x qs >/dev/null && pkill -9 -x qs 2>/dev/null

# Levantar por systemd, NO con 'setsid -f qs'. Un qs suelto no cuelga de
# quickshell.service, asi que se queda sin la supervision de la unidad: si
# segfaultea (paso el 2026-08-05), nadie lo levanta y te quedas sin barra ni
# notch. Ademas el pkill de arriba manda SIGTERM, que systemd cuenta como
# salida limpia, asi que con Restart=on-failure tampoco lo reinicia: la primera
# pulsacion de Super+G dejaba el shell huerfano hasta el siguiente login.
#
# El pkill previo sigue haciendo falta: con --no-duplicate, si sobrevive
# cualquier qs de fuera de la unidad, el que arranca systemd se retira solo.
#
# La unidad tiene StartLimitBurst=5 en 60s para no reintentar en bucle con la
# config QML rota. Machacando Super+G se llega a ese tope y el restart falla,
# asi que se limpia el contador y se reintenta antes de rendirse.
if ! systemctl --user restart quickshell.service 2>/dev/null; then
    systemctl --user reset-failed quickshell.service 2>/dev/null
    if ! systemctl --user restart quickshell.service 2>/dev/null; then
        # Sin systemd de usuario (o unidad rota): al menos deja el shell en pie.
        #
        # 9>&- NO es decorativo: los descriptores se heredan, asi que sin esto qs
        # se queda agarrado al cerrojo mientras viva y el siguiente Super+G se
        # encuentra el flock ocupado y no hace nada. El atajo dejaba de
        # funcionar tras la primera vez.
        setsid -f qs -n >/dev/null 2>&1 </dev/null 9>&-
    fi
fi

# El cerrojo se suelta al salir, asi que no salgas hasta que el nuevo qs este en
# pie: si no, una segunda pulsacion entraria a matarlo a medio arrancar.
for _ in {1..30}; do
    pgrep -x qs >/dev/null && break
    sleep 0.1
done
