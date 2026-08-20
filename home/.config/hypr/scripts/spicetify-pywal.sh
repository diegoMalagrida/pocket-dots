#!/usr/bin/env bash
# Re-tematiza Spotify (spicetify) con la paleta de pywal. Lo llama set-wallpaper.sh.
#
# Usa el tema 'termspot' (github.com/fdeox/termspot): TUI de fósforo CRT. Su
# color.ini trae 19 esquemas propios, así que spicetify-colors.py solo
# inserta/actualiza el bloque [pywal] con un acento vivo derivado del tono
# dominante del fondo, y deja el resto del fichero como está.
#
# Cómo llega el color al Spotify que ya está abierto:
#
#   1. En caliente (lo normal). spicetify-push-colors.py entra por el WebSocket
#      de DevTools y reescribe las variables --spice-* de documentElement. Es
#      instantáneo y no se nota: ni reinicio, ni recarga, ni se pierde el scroll.
#      Necesita que Spotify se lanzara con --remote-debugging-port (lo ponen el
#      .desktop de ~/.local/share/applications y spicetify-restart-spotify.sh).
#
#   2. Reiniciando (plan B). Solo si el push falla: Spotify cerrado sin más, o
#      abierto desde antes de que existiera el puerto. Es lo que hacíamos siempre.
#
# Por qué no 'spicetify watch': hace una recarga COMPLETA del xpui (destello de
# 1-2 s y vuelves al principio del scroll), deja un proceso vivo, y el propio
# mantenedor dice que en Linux falla a menudo (spicetify/cli#1091). Ojo, el
# motivo por el que 'watch' no detecta cambios en #2384 NO aplica aquí: aquel
# usuario tenía ${xrdb:...} en el color.ini y el fichero nunca cambiaba; el
# nuestro se reescribe con hex reales.
set -u

command -v spicetify >/dev/null 2>&1 || exit 0

SCRIPTS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GEN="$SCRIPTS/spicetify-colors.py"
PUSH="$SCRIPTS/spicetify-push-colors.py"
THEME_DIR="$HOME/.config/spicetify/Themes/termspot"
[ -r "$HOME/.cache/wal/colors.json" ] || exit 0
mkdir -p "$THEME_DIR"

# Regenerar el color.ini (acento vivo) desde la paleta pywal actual + recompilar a
# disco. El refresh no toca la ventana abierta, pero deja el color correcto para
# el siguiente arranque.
python3 "$GEN" "$THEME_DIR/color.ini" 2>/dev/null || exit 0
spicetify refresh >/dev/null 2>&1 || true

pgrep -x spotify >/dev/null 2>&1 || exit 0

# --- 1. intento en caliente ---------------------------------------------------
if python3 "$PUSH" "$THEME_DIR/color.ini" >/dev/null 2>&1; then
  exit 0
fi

# --- 2. plan B: reiniciar, devolviéndolo a SU workspace y sin robarte el foco --
if pgrep -x spotify >/dev/null 2>&1; then
  WS="$(hyprctl clients -j 2>/dev/null | python3 -c "
import json,sys
try: cs=json.load(sys.stdin)
except Exception: sys.exit()
for c in cs:
    if c.get('class')=='Spotify':
        w=c.get('workspace',{}).get('id')
        if w is not None: print(w)
        break" 2>/dev/null)"
  setsid -f "$SCRIPTS/spicetify-restart-spotify.sh" "$WS" >/dev/null 2>&1 &
fi
