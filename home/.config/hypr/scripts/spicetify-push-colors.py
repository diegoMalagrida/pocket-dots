#!/usr/bin/env python3
# Empuja la paleta de pywal a la ventana de Spotify YA ABIERTA, en caliente.
#
# Por que existe esto: 'spicetify apply' recompila a disco pero no toca el Spotify
# abierto, y 'spicetify watch' hace una RECARGA COMPLETA del xpui (destello de 1-2s
# y pierdes el scroll). Ademas el mantenedor de spicetify reconoce que ese camino
# falla a menudo en Linux (spicetify/cli#1091: "We send a valid javascript via
# DevTools websocket [...] On Linux it mostly fails").
#
# Aqui vamos por debajo: al mismo WebSocket de DevTools, pero en vez de pedir una
# recarga solo reescribimos las variables CSS --spice-*. El repintado es inmediato
# y no se pierde ni el scroll ni el estado de la UI.
#
# Requiere que Spotify se haya lanzado con --remote-debugging-port (lo pone el
# override ~/.local/share/applications/spotify.desktop).
#
# Salida: 0 si los colores se aplicaron; !=0 si no se pudo (Spotify cerrado, sin
# puerto, etc.) para que quien llame decida si hace falta el reinicio de siempre.
#
# Uso: spicetify-push-colors.py [ruta_color.ini] [--puerto N] [--seccion pywal]
import base64, json, os, re, socket, struct, sys, urllib.request

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


# ---- 1. leer la seccion del color.ini ---------------------------------------
# A mano y no con configparser: el color.ini de termspot lleva 20 secciones y
# comentarios con ';', y aqui solo queremos una.
def leer_seccion(ruta, seccion):
    try:
        texto = open(ruta).read()
    except OSError as e:
        morir("no puedo leer %s: %s" % (ruta, e))
    m = re.search(r"^\[%s\][^\[]*" % re.escape(seccion), texto, re.M)
    if not m:
        morir("no hay seccion [%s] en %s" % (seccion, ruta))
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
        morir("la seccion [%s] no tiene colores validos" % seccion)
    return colores


# ---- 2. cliente WebSocket minimo (RFC 6455) ---------------------------------
# No hay websocat ni el modulo 'websockets' en el sistema, y para mandar cuatro
# mensajes no merece la pena una dependencia: el handshake y el enmarcado son
# cortos. Los frames de cliente van SIEMPRE enmascarados; los del servidor no.
class WS:
    def __init__(self, url, origin, timeout=4):
        if not url.startswith("ws://"):
            raise ValueError("url no ws://: %s" % url)
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
                # Chromium 111+ exige que el Origin este en --remote-allow-origins
                "Origin: %s\r\n"
                "\r\n" % (path, hostport, clave, origin)
            ).encode()
        )
        buf = b""
        while b"\r\n\r\n" not in buf:
            trozo = self.s.recv(4096)
            if not trozo:
                raise RuntimeError("el servidor cerro durante el handshake")
            buf += trozo
        cabeceras, _, resto = buf.partition(b"\r\n\r\n")
        primera = cabeceras.split(b"\r\n")[0].decode(errors="replace")
        if "101" not in primera:
            raise RuntimeError("handshake rechazado: %s" % primera)
        self.buf = resto

    def _leer(self, n):
        while len(self.buf) < n:
            trozo = self.s.recv(65536)
            if not trozo:
                raise RuntimeError("conexion cerrada")
            self.buf += trozo
        out, self.buf = self.buf[:n], self.buf[n:]
        return out

    def enviar(self, texto):
        datos = texto.encode()
        n = len(datos)
        cab = bytearray([0x81])  # FIN + opcode texto
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
            if b1 & 0x80:  # el servidor no deberia enmascarar, pero por si acaso
                mascara, carga = carga[:4], carga[4:]
                carga = bytes(c ^ mascara[i % 4] for i, c in enumerate(carga))
            if opcode == 0x9:  # ping -> pong
                self.enviar("")
                continue
            if opcode == 0x8:
                raise RuntimeError("el servidor cerro la conexion")
            if opcode in (0x1, 0x2):
                return carga.decode(errors="replace")

    def cerrar(self):
        try:
            self.s.close()
        except OSError:
            pass


# ---- 3. localizar la pestana del xpui ---------------------------------------
def objetivo(puerto):
    try:
        with urllib.request.urlopen("http://127.0.0.1:%d/json" % puerto, timeout=3) as r:
            objetivos = json.load(r)
    except Exception as e:
        morir("no hay puerto de depuracion en %d (%s). Spotify cerrado, o lanzado "
              "sin --remote-debugging-port" % (puerto, e), 2)
    paginas = [t for t in objetivos if t.get("type") == "page" and t.get("webSocketDebuggerUrl")]
    if not paginas:
        morir("el puerto responde pero no hay ninguna pagina abierta", 3)
    # la UI principal es xpui; si no la encontramos, la primera pagina sirve
    for t in paginas:
        if "xpui" in (t.get("url") or ""):
            return t
    return paginas[0]


# ---- 4. el JS que se ejecuta dentro de Spotify -------------------------------
def construir_js(colores):
    # Ademas de las --spice-*, recalculamos --termspot-mono-filter. El tema lo
    # deriva del acento en su updateMonoFilter(), pero solo lo llama al cambiar
    # de cancion: sin esto las caratulas se quedarian con el tinte anterior hasta
    # la siguiente. La formula es la misma que la suya (theme.js).
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
        # puede llegar algun evento suelto antes de nuestra respuesta
        for _ in range(20):
            msg = json.loads(ws.recibir())
            if msg.get("id") == 1:
                break
        else:
            morir("sin respuesta del evaluate", 4)
    finally:
        ws.cerrar()

    if "error" in msg:
        morir("CDP: %s" % msg["error"], 5)
    res = msg.get("result", {})
    if res.get("exceptionDetails"):
        morir("excepcion en Spotify: %s" % res["exceptionDetails"].get("text"), 6)
    print("aplicados %s colores en caliente" % res.get("result", {}).get("value"))


if __name__ == "__main__":
    main()
