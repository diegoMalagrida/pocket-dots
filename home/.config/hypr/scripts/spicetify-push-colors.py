#!/usr/bin/env python3
# Pushes the pywal palette into the ALREADY OPEN Spotify window, live.
#
# Why this exists: 'spicetify apply' recompiles to disk but does not touch the
# running Spotify, and 'spicetify watch' does a FULL RELOAD of xpui (a 1-2s flash
# and you lose your scroll position). On top of that, spicetify's maintainer
# admits that path often fails on Linux (spicetify/cli#1091: "We send a valid
# javascript via DevTools websocket [...] On Linux it mostly fails").
#
# Here we go one level down: to the same DevTools WebSocket, but instead of
# asking for a reload we only rewrite the --spice-* CSS variables. The repaint
# is immediate and neither the scroll position nor the UI state is lost.
#
# Requires Spotify to have been launched with --remote-debugging-port (the
# override ~/.local/share/applications/spotify.desktop adds it).
#
# Exit: 0 if the colours were applied; !=0 if that was not possible (Spotify
# closed, no port, etc.) so the caller can decide whether the usual restart is
# needed.
#
# Usage: spicetify-push-colors.py [path/to/color.ini] [--puerto N] [--seccion pywal]
import base64, json, os, re, socket, struct, sys, urllib.request


def tr(es, en):
    try:
        import json
        from pathlib import Path
        with (Path.home() / ".config/quickshell-rice.json").open(encoding="utf-8") as f:
            return en if json.load(f).get("language") == "en" else es
    except (OSError, ValueError, AttributeError):
        return es


PUERTO = 9333
SECCION = "pywal"
INI = os.path.expanduser("~/.config/spicetify/Themes/termspot/color.ini")

args = sys.argv[1:]
i = 0
posicional = []
while i < len(args):
    if args[i] == "--puerto":
        PUERTO = int(args[i + 1]); i += 2
    elif args[i] == "--seccion":
        SECCION = args[i + 1]; i += 2
    else:
        posicional.append(args[i]); i += 1
if posicional:
    INI = posicional[0]


def morir(msg, codigo=1):
    sys.stderr.write("spicetify-push-colors: %s\n" % msg)
    sys.exit(codigo)


# ---- 1. read the section from color.ini -------------------------------------
# By hand and not with configparser: termspot's color.ini carries 20 sections
# and ';' comments, and here we only want one.
def leer_seccion(ruta, seccion):
    try:
        texto = open(ruta).read()
    except OSError as e:
        morir(tr("no puedo leer %s: %s", "Cannot read %s: %s") % (ruta, e))
    m = re.search(r"^\[%s\][^\[]*" % re.escape(seccion), texto, re.M)
    if not m:
        morir(tr("no hay seccion [%s] en %s", "No section [%s] in %s") % (seccion, ruta))
    colores = {}
    for linea in m.group(0).splitlines()[1:]:
        linea = linea.strip()
        if not linea or linea.startswith(";") or "=" not in linea:
            continue
        k, _, v = linea.partition("=")
        v = v.strip().lstrip("#").upper()
        if re.fullmatch(r"[0-9A-F]{6}", v):
            colores[k.strip()] = v
    if not colores:
        morir(tr("la seccion [%s] no tiene colores validos", "Section [%s] has no valid colours") % seccion)
    return colores


# ---- 2. minimal WebSocket client (RFC 6455) ---------------------------------
# There is no websocat nor the 'websockets' module on the system, and sending
# four messages is not worth a dependency: the handshake and the framing are
# short. Client frames are ALWAYS masked; the server's are not.
class WS:
    def __init__(self, url, origin, timeout=4):
        if not url.startswith("ws://"):
            raise ValueError(tr("url no ws://: %s", "URL does not use ws://: %s") % url)
        hostport, _, path = url[5:].partition("/")
        host, _, puerto = hostport.partition(":")
        self.s = socket.create_connection((host, int(puerto or 80)), timeout=timeout)
        self.s.settimeout(timeout)
        clave = base64.b64encode(os.urandom(16)).decode()
        self.s.sendall(
            (
                "GET /%s HTTP/1.1\r\n"
                "Host: %s\r\n"
                "Upgrade: websocket\r\n"
                "Connection: Upgrade\r\n"
                "Sec-WebSocket-Key: %s\r\n"
                "Sec-WebSocket-Version: 13\r\n"
                # Chromium 111+ requires the Origin to be listed in --remote-allow-origins
                "Origin: %s\r\n"
                "\r\n" % (path, hostport, clave, origin)
            ).encode()
        )
        buf = b""
        while b"\r\n\r\n" not in buf:
            trozo = self.s.recv(4096)
            if not trozo:
                raise RuntimeError(tr("el servidor cerro durante el handshake",
                                      "The server closed the connection during the handshake"))
            buf += trozo
        cabeceras, _, resto = buf.partition(b"\r\n\r\n")
        primera = cabeceras.split(b"\r\n")[0].decode(errors="replace")
        if "101" not in primera:
            raise RuntimeError(tr("handshake rechazado: %s", "Handshake rejected: %s") % primera)
        self.buf = resto

    def _leer(self, n):
        while len(self.buf) < n:
            trozo = self.s.recv(65536)
            if not trozo:
                raise RuntimeError(tr("conexion cerrada", "Connection closed"))
            self.buf += trozo
        out, self.buf = self.buf[:n], self.buf[n:]
        return out

    def enviar(self, texto):
        datos = texto.encode()
        n = len(datos)
        cab = bytearray([0x81])  # FIN + text opcode
        if n < 126:
            cab.append(0x80 | n)
        elif n < 1 << 16:
            cab.append(0x80 | 126); cab += struct.pack(">H", n)
        else:
            cab.append(0x80 | 127); cab += struct.pack(">Q", n)
        mascara = os.urandom(4)
        cab += mascara
        self.s.sendall(bytes(cab) + bytes(b ^ mascara[i % 4] for i, b in enumerate(datos)))

    def recibir(self):
        while True:
            b0, b1 = self._leer(2)
            opcode = b0 & 0x0F
            n = b1 & 0x7F
            if n == 126:
                n = struct.unpack(">H", self._leer(2))[0]
            elif n == 127:
                n = struct.unpack(">Q", self._leer(8))[0]
            carga = self._leer(n) if n else b""
            if b1 & 0x80:  # the server should not mask, but just in case
                mascara, carga = carga[:4], carga[4:]
                carga = bytes(c ^ mascara[i % 4] for i, c in enumerate(carga))
            if opcode == 0x9:  # ping -> pong
                self.enviar("")
                continue
            if opcode == 0x8:
                raise RuntimeError(tr("el servidor cerro la conexion", "The server closed the connection"))
            if opcode in (0x1, 0x2):
                return carga.decode(errors="replace")

    def cerrar(self):
        try:
            self.s.close()
        except OSError:
            pass


# ---- 3. find the xpui tab ---------------------------------------------------
def objetivo(puerto):
    try:
        with urllib.request.urlopen("http://127.0.0.1:%d/json" % puerto, timeout=3) as r:
            objetivos = json.load(r)
    except Exception as e:
        morir(tr("no hay puerto de depuracion en %d (%s). Spotify cerrado, o lanzado "
                 "sin --remote-debugging-port",
                 "No debugging port at %d (%s). Spotify is closed or was started without --remote-debugging-port") % (puerto, e), 2)
    paginas = [t for t in objetivos if t.get("type") == "page" and t.get("webSocketDebuggerUrl")]
    if not paginas:
        morir(tr("el puerto responde pero no hay ninguna pagina abierta",
                 "The port responds but no pages are open"), 3)
    # the main UI is xpui; if we cannot find it, the first page will do
    for t in paginas:
        if "xpui" in (t.get("url") or ""):
            return t
    return paginas[0]


# ---- 4. the JS that runs inside Spotify --------------------------------------
def construir_js(colores):
    # Besides the --spice-* ones, we recompute --termspot-mono-filter. The theme
    # derives it from the accent in its updateMonoFilter(), but only calls that
    # on a track change: without this the cover art would keep the previous tint
    # until the next track. The formula is the same as the theme's (theme.js).
    return """(() => {
  const c = %s;
  const el = document.documentElement;
  const rgb = h => [parseInt(h.slice(0,2),16), parseInt(h.slice(2,4),16), parseInt(h.slice(4,6),16)];
  for (const k in c) {
    el.style.setProperty('--spice-' + k, '#' + c[k]);
    el.style.setProperty('--spice-rgb-' + k, rgb(c[k]).join(','));
  }
  const a = c['accent-active'] || c['accent'];
  if (a) {
    const [r,g,b] = rgb(a);
    const max = Math.max(r,g,b), min = Math.min(r,g,b);
    let hue = 0;
    if (max !== min) {
      const d = max - min;
      if (max === r) hue = ((g-b)/d) %% 6;
      else if (max === g) hue = (b-r)/d + 2;
      else hue = (r-g)/d + 4;
      hue = Math.round(hue*60);
      if (hue < 0) hue += 360;
    }
    const sat = max === 0 ? 0 : (max-min)/max;
    el.style.setProperty('--termspot-mono-filter',
      'grayscale(1) sepia(1) hue-rotate(' + (hue-40) + 'deg) saturate(' +
      (0.6+sat).toFixed(2) + ') brightness(0.8)');
  }
  return Object.keys(c).length;
})()""" % json.dumps(colores)


# ---- 5. main -----------------------------------------------------------------
def main():
    colores = leer_seccion(INI, SECCION)
    t = objetivo(PUERTO)
    ws = WS(t["webSocketDebuggerUrl"], "http://127.0.0.1:%d" % PUERTO)
    try:
        ws.enviar(json.dumps({
            "id": 1,
            "method": "Runtime.evaluate",
            "params": {"expression": construir_js(colores), "returnByValue": True},
        }))
        # a stray event may arrive before our reply
        for _ in range(20):
            msg = json.loads(ws.recibir())
            if msg.get("id") == 1:
                break
        else:
            morir(tr("sin respuesta del evaluate", "No response from evaluate"), 4)
    finally:
        ws.cerrar()

    if "error" in msg:
        morir("CDP: %s" % msg["error"], 5)
    res = msg.get("result", {})
    if res.get("exceptionDetails"):
        morir("excepcion en Spotify: %s" % res["exceptionDetails"].get("text"), 6)
    print(tr("aplicados %s colores en caliente", "Applied %s colours live") % res.get("result", {}).get("value"))


if __name__ == "__main__":
    main()
