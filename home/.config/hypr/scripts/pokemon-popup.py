import argparse, json, math, os, random, re, select, shutil, signal, struct, subprocess, sys, tempfile, termios, threading, time, tty
from PIL import Image, ImageDraw, ImageFont, ImageFilter
from pathlib import Path


def tr(es, en):
    try:
        import json
        from pathlib import Path
        with (Path.home() / ".config/quickshell-rice.json").open(encoding="utf-8") as f:
            return en if json.load(f).get("language") == "en" else es
    except (OSError, ValueError, AttributeError):
        return es


H = Path.home()
PAL = H / ".cache" / "pokepalette"
parser = argparse.ArgumentParser(description=tr("Pokédex adaptable para Super+O",
                                                "Adaptive Pokédex for Super+O"))
parser.add_argument("--pokemon", type=int)
parser.add_argument("--render", help=tr("Vista previa sin terminal: ANCHOxALTO",
                                        "Preview without a terminal: WIDTHxHEIGHT"))
parser.add_argument("--output", default="/tmp/pokedex-preview.png")
parser.add_argument("--timeout", type=float, default=18)
parser.add_argument("--silent", action="store_true")
args = parser.parse_args()
DESPEDIDA = 4  # seconds the card holds on once you look at another window
sprites = sorted((H / ".cache/pokeanim/.box").glob("*.gif"))
if not sprites:
    raise SystemExit(0)
gif = H / f".cache/pokeanim/.box/{args.pokemon}.gif" if args.pokemon else random.choice(sprites)
if not gif.exists():
    # Not every number has a sprite in the box (the team may carry one that is
    # missing). Say so and exit, instead of blowing up with a traceback.
    raise SystemExit(tr(f"pokemon-popup: no hay sprite para #{args.pokemon} en {gif.parent}",
                        f"pokemon-popup: no sprite for #{args.pokemon} in {gif.parent}"))
num = int(gif.stem)

# Querying the team costs ~150 ms of external process: let it happen while the
# data loads and the card is composed, not before work starts.
_equipo_crudo = []
def _pide_equipo():
    try:
        _equipo_crudo.append(json.loads(subprocess.run(
            ["poke-team", "estado"], capture_output=True, text=True, timeout=10).stdout))
    except Exception:
        _equipo_crudo.append(None)
_hilo_equipo = threading.Thread(target=_pide_equipo, daemon=True)
_hilo_equipo.start()

try:
    lang = json.loads((H / ".config" / "quickshell-rice.json").read_text()).get("language", "es")
except Exception:
    lang = "es"
if lang not in ("es", "en"):
    lang = "es"
T = {"es": {"nv": "Nv", "faltan": "a {n} aportes de evolucionar",
            "equipo": "en tu equipo", "lider": "tu líder", "oculta": "oculta",
            "debil": "DÉBIL", "inmune": "INMUNE", "habs": "HABILIDAD", "total": "TOTAL",
            "tamano": "TAMAÑO",
            "cortas": ["PS", "ATQ", "DEF", "VEL", "DFE", "ATE"],
            "regiones": ["Kanto", "Johto", "Hoenn", "Sinnoh", "Teselia", "Kalos",
                          "Alola", "Galar", "Paldea"]},
     "en": {"nv": "Lv", "faltan": "{n} contributions to evolve",
            "equipo": "in your team", "lider": "your leader", "oculta": "hidden",
            "debil": "WEAK", "inmune": "IMMUNE", "habs": "ABILITY", "total": "TOTAL",
            "tamano": "SIZE",
            "cortas": ["HP", "ATK", "DEF", "SPE", "SPD", "SPA"],
            "regiones": ["Kanto", "Johto", "Hoenn", "Sinnoh", "Unova", "Kalos",
                          "Alola", "Galar", "Paldea"]}}[lang]

def carga(nombre, defecto):
    try:
        return json.loads((PAL / nombre).read_text())
    except Exception:
        return defecto

tipos = carga("tipos.json", {})
evos = {int(k): v for k, v in carga("evoluciones.json", {}).items()}
dex = carga(f"dex/{num}.json", {})
habs_nombres = carga("habilidades.json", {})
dano = carga("tipos-dano.json", {})
try:
    wal = json.loads((H / ".cache/wal/colors.json").read_text())
except Exception:
    wal = {}
nombres = {}
try:
    # In English the PokéAPI ids ARE the names, once capitalised ("mr-mime" ->
    # "Mr-Mime"), the same rule as ShellState.pokeTitulo(); in Spanish, the file
    # poke-names downloads.
    for l in (PAL / ("nombres-es.tsv" if lang == "es" else "nombres.tsv")).read_text().splitlines():
        a, _, b = l.partition("\t")
        if a.isdigit():
            b = b.strip()
            nombres[int(a)] = b if lang == "es" else "-".join(w[:1].upper() + w[1:] for w in b.split("-"))
except Exception:
    pass

# The nature comes from the save in Spanish. In English it goes through the
# shell's own dictionary, read line by line the way tools/i18n-check.py reads
# it, so the 25 names are not copied a second time here.
dic_en = {}
if lang == "en":
    try:
        for l in (H / ".config/quickshell/translations-en.js").read_text().splitlines():
            m_ = re.match(r'^\s*"((?:[^"\\]|\\.)*)"\s*:\s*"((?:[^"\\]|\\.)*)"\s*,?\s*$', l)
            if m_:
                dic_en[m_.group(1)] = m_.group(2)
    except OSError:
        pass

def nom(n):
    return nombres.get(n, f"#{n}")

def rgb(hexcolor):
    h = hexcolor.lstrip("#")
    return tuple(int(h[i:i+2], 16) for i in (0, 2, 4))

def nombre_tipo(t):
    return tipos.get("es", {}).get(t, t) if lang == "es" else t.capitalize()

def color_tipo(t):
    return tipos.get("colores", {}).get(t, "#888888")

def num_idioma(x):
    t = f"{x:.1f}".rstrip("0").rstrip(".")
    return t.replace(".", ",") if lang == "es" else t

def region(n):
    for i, tope in enumerate([151, 251, 386, 493, 649, 721, 809, 905, 1025]):
        if n <= tope:
            return T["regiones"][i]
    return ""

mios = tipos.get("pokemon", {}).get(str(num), [])
stats = dex.get("stats") or []

def releva_al_anterior():
    """Pressing Super+O again means "show me another", not "open another window".

    Without this the cards piled up: three presses left three identical,
    centred kittys one on top of another, and closing the top one uncovered
    the next. The saved PID's command line is checked before sending it
    anything, because process numbers get reused and it would be very ugly
    to kill another tenant of the machine.
    """
    marca = Path(os.environ.get('XDG_RUNTIME_DIR') or '/tmp') / 'pokemon-popup.pid'
    try:
        anterior = int(marca.read_text())
        if anterior != os.getpid() and \
                b'pokemon-popup' in Path(f'/proc/{anterior}/cmdline').read_bytes():
            os.kill(anterior, signal.SIGTERM)
    except (OSError, ValueError):
        pass
    try:
        marca.write_text(str(os.getpid()))
    except OSError:
        pass


if not args.render:
    releva_al_anterior()

# the cry, quiet and with a mute switch (touch ~/.config/poke-equipo/mudo)
grito = H / ".cache" / "pokecries" / f"{num}.ogg"
if not args.render and not args.silent and grito.exists() and not (H / ".config/poke-equipo/mudo").exists():
    for rep in (["pw-play", "--volume", "0.2"], ["paplay"]):
        if shutil.which(rep[0]):
            subprocess.Popen(rep + [str(grito)],
                             stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            break

# ── derived data ──────────────────────────────────────────────────────────
padre = {}
for de, lista in evos.items():
    for e in lista:
        padre[e["a"]] = de
base = num
while base in padre:
    base = padre[base]

def alcanza(n, obj, prof=0):
    if n == obj:
        return True
    if prof > 8:
        return False
    return any(alcanza(e["a"], obj, prof + 1) for e in evos.get(n) or [])

cadena, pasos, aqui = [base], [], base
while True:
    sig = evos.get(aqui) or []
    if not sig:
        break
    if len(sig) > 1 and aqui == num:
        cadena.append(sig[0]["a"]); pasos.append(sig[0]); break
    paso = next((e for e in sig if alcanza(e["a"], num)), sig[0])
    cadena.append(paso["a"]); pasos.append(paso); aqui = paso["a"]
if len(cadena) == 1:
    cadena, pasos = [], []

mults = {}
if dano and mios:
    for atacante in dano:
        m = 1.0
        for mio in mios:
            rel = dano.get(mio, {})
            if atacante in rel.get("x0", []):
                m = 0.0
            elif atacante in rel.get("x2", []):
                m *= 2
            elif atacante in rel.get("x05", []):
                m *= 0.5
        mults[atacante] = m
debiles = sorted([(t, x) for t, x in mults.items() if x >= 2], key=lambda p: -p[1])
inmunes = [t for t, x in mults.items() if x == 0]

def naturaleza_sube():
    """Which stat this one's nature raises, if it is one of yours.

    Since HeartGold the games mark the raised and the lowered stat on the
    summary screen. Here poke-team only stores the raised one, so that is the
    one marked. Returns the index within the order the six figures are drawn in.
    """
    orden = {"Ataque": 1, "Defensa": 2, "Velocidad": 3,
             "Def. especial": 4, "At. especial": 5}
    try:
        eq = (_equipo_crudo[0] or {}).get("equipo", [])
        mio = next((m for m in eq if m.get("num") == num), None)
        return orden.get((mio or {}).get("naturaleza_sube"))
    except Exception:
        return None


_equipo_hecho = []
def equipo_info():
    """What the thread brought back about the team, resolved once and as late as possible."""
    if _equipo_hecho:
        return _equipo_hecho[0]
    info = None
    _hilo_equipo.join(10)
    try:
        est = _equipo_crudo[0]
        eq = est.get("equipo", [])
        mio_ = next((m_ for m_ in eq if m_.get("num") == num), None)
        if mio_:
            quien = T["lider"] if eq and eq[0] is mio_ else T["equipo"]
            info = [mio_.get("mote") or nom(num), f"{T['nv']} {mio_['nivel']}", quien]
            if mio_.get("naturaleza"):
                info.append(dic_en.get(mio_["naturaleza"], mio_["naturaleza"]))
            paso = next((e for e in evos.get(num, []) if e.get("como") == "nivel"), None)
            if paso and paso.get("nivel") and mio_["nivel"] < paso["nivel"]:
                falta = sum(40 + 20 * k for k in range(mio_["nivel"], paso["nivel"])) - mio_.get("xp", 0)
                racha = (est.get("github") or {}).get("racha", 0)
                rinde = est.get("xp_por_aporte", 12) * (1.0 + min(racha, 10) / 10) \
                        * mio_.get("naturaleza_mult", 1.0)
                info.append(T["faltan"].format(n=max(1, -(-int(falta) // max(1, int(rinde))))))
    except Exception:
        info = None
    _equipo_hecho.append(info)
    return info

# ── The design system is Quickshell's ─────────────────────────────────────
# These numbers do not belong here: they are the tokens from ~/.config/quickshell/
# Appearance.qml, the same ones the bar, the notch and Ajustes use. The Pokédex
# stops having a taste of its own and is built from the shell's pieces instead.
FS_XS, FS_S, FS_M, FS_L = 11, 12, 13, 16          # font sizes
RAD_S, RAD_M, RAD_L = 10, 14, 18                  # corner radii
GAP_S, GAP_M, GAP_L, PAD = 6, 10, 14, 16          # spacing

RUTA_A = Path('/usr/share/fonts/Adwaita/AdwaitaSans-Regular.ttf')
RUTA_MB = Path('/usr/share/fonts/TTF/JetBrainsMonoNerdFont-Bold.ttf')
RUTA_PKM = H / '.local/share/fonts/pokemon-font.ttf'


def font(path, size, peso='Regular'):
    """Adwaita Sans is variable: the titles' semibold comes from the same .ttf."""
    try:
        f = ImageFont.truetype(str(path), size)
    except OSError:
        return ImageFont.load_default(size=size)
    if peso != 'Regular':
        try:
            f.set_variation_by_name(peso)
        except Exception:
            pass
    return f


F_FILA = font(RUTA_A, FS_M)                    # a row's text
F_SEC = font(RUTA_A, FS_XS)                    # secondary text and the pills
F_SECCION = font(RUTA_A, FS_XS, 'SemiBold')    # section title, in the accent
F_NUM = font(RUTA_MB, FS_S)                    # figures, in monospace
F_PIE = font(RUTA_A, FS_S)                     # the hint in the window's footer

# Ajustes paints its text in pure white and secondary text in mid grey, and its
# cards are translucent white over whatever is beneath. Copied as it is.
BLANCO = (255, 255, 255)
GRIS = (0x8a, 0x8a, 0x8a)
try:
    wal_colores = wal.get('colors') or {}
except NameError:
    wal_colores = {}
ACCENT = rgb(wal_colores.get('color4', '#61afef'))   # Colors.accent = pywal's color4
FG = BLANCO
BG = rgb((wal.get('special') or {}).get('background', '#1a1512'))
MUTED = GRIS
DIM = GRIS
F_TEXT, F_SMALL, F_LABEL = F_FILA, F_SEC, F_SEC


def luz(color):
    return (0.2126 * color[0] + 0.7152 * color[1] + 0.0722 * color[2]) / 255


def legible(color, salto=0.40):
    """The type's colour, lifted just enough to show against this background.

    The eighteen type colours are fixed and some (dark, ghost, poison,
    fighting) start out almost as dark as a dark theme.
    """
    hacia = BLANCO if luz(BG) < 0.5 else BG
    for k in range(21):
        f = k / 20
        mezcla = tuple(round(a * (1 - f) + b * f) for a, b in zip(color, hacia))
        if abs(luz(mezcla) - luz(BG)) >= salto:
            return mezcla
    return hacia


TIPO = legible(rgb(color_tipo(mios[0]))) if mios else ACCENT
TYPE = TIPO


def color_stat(valor):
    """No traffic lights: grey sets the hierarchy, the bar carries the colour."""
    return GRIS if valor < 60 else BLANCO


def compose(width, height, con_tamano=True):
    """The card, in the vocabulary of Quickshell's Ajustes (Settings).

    None of this is a new choice: the section title in the accent at 11 px with
    its tracking, the radius-14 card filled with white at 4.5 % and its border
    at 7.5 %, the radius-10 rows with 12 px of air at the sides and the
    secondary text in mid grey are literally the tokens of Appearance.qml and
    the components of SettingsControls.qml. The Pokédex becomes one more tab of
    that panel, not something else with its own taste.
    """
    width = max(80, min(920, width))
    pad = PAD if width >= 420 else GAP_L
    left, right = pad, width - pad
    area = right - left
    canvas = Image.new('RGBA', (width, 2600))
    d = ImageDraw.Draw(canvas)

    def text(x, y, value, f=F_FILA, color=BLANCO, tracking=0):
        if tracking:
            for ch in value:
                d.text((round(x), round(y)), ch, font=f, fill=color)
                x += f.getlength(ch) + tracking
            return
        d.text((round(x), round(y)), value, font=f, fill=color)

    def ancho(value, f=F_FILA, tracking=0):
        return f.getlength(value) + tracking * max(0, len(value) - 1)

    def wrap(value, limite, f=F_FILA):
        lineas, linea = [], ''
        for palabra in value.split():
            prueba = (linea + ' ' + palabra).strip()
            if f.getlength(prueba) <= limite:
                linea = prueba
                continue
            if linea:
                lineas.append(linea)
            linea = ''
            for ch in palabra:
                if linea and f.getlength(linea + ch) > limite:
                    lineas.append(linea)
                    linea = ''
                linea += ch
        if linea:
            lineas.append(linea)
        return lineas

    def parrafo(value, x, y, w, f=F_FILA, color=GRIS, interlinea=19):
        for linea in wrap(value, w, f):
            text(x, y, linea, f, color)
            y += interlinea
        return y

    midiendo = False

    def medir(bloque):
        """How much room the block would take, without actually painting it.

        Text is diverted to a one-pixel canvas, but images have to be stopped
        separately (see 'pega'): compositing a sprite with alpha twice in the
        same place is not harmless, it leaves it more opaque than it should be.
        """
        nonlocal d, midiendo
        real_d, real_m = d, midiendo
        d, midiendo = ImageDraw.Draw(Image.new('RGBA', (1, 1))), True
        try:
            return bloque()
        finally:
            d, midiendo = real_d, real_m

    def pega(imagen, posicion):
        if not midiendo:
            canvas.alpha_composite(imagen, posicion)

    def titulo(x, y, value):
        """Section title: accent, 11 px, semibold and 0.6 tracking."""
        text(x, y, value.upper(), F_SECCION, ACCENT, 0.6)
        return y + 18

    def seccion(x, y, w, rotulo, cuerpo, alto_min=0):
        """Title in the accent and its content below, with nothing boxing it in.

        The typography and colours are still the shell's, but the cards were
        left out on purpose: boxing in six figures and three pills turned a
        creature's card into a settings panel. What separates one section from
        the next is the title and the air.
        """
        arriba = titulo(x, y, rotulo) + 4
        alto = max(alto_min, medir(lambda: cuerpo(x, arriba, w)) - arriba)
        cuerpo(x, arriba, w)
        return arriba + alto

    def pills(items, x, y, w):
        inicio, alto_fila = x, 26
        for etiqueta, color in items:
            for linea in wrap(etiqueta, max(8, w - 24), F_SEC):
                ancho_pill = math.ceil(F_SEC.getlength(linea)) + 22
                if x > inicio and x + ancho_pill > inicio + w:
                    x, y = inicio, y + alto_fila + 6
                d.rounded_rectangle((x, y, x + ancho_pill, y + alto_fila), radius=alto_fila // 2,
                                    fill=color + (34,), outline=color + (120,))
                text(x + 11, y + 5, linea, F_SEC, color)
                x += ancho_pill + 6
        return y + alto_fila

    # ── header: the creature and who it is ─────────────────────────────────
    # Three modes, decided by the usable width: wide (hero + three columns +
    # band), medium (hero + two columns) and narrow (everything stacked, with
    # the creature centred at the top).
    wide = area >= 780
    medio = 460 <= area < 780
    lado_a_lado = wide or medio
    ancho_escena = 220 if wide else 150 if medio else min(area, 200)
    alto_escena = 176 if wide else 150 if medio else 140
    ex = left if lado_a_lado else left + (area - ancho_escena) // 2
    hx = left + ancho_escena + GAP_L + 10 if lado_a_lado else left
    hw = right - hx if lado_a_lado else area
    escena_y = 4

    with Image.open(gif) as fuente:
        sprite_w, sprite_h = fuente.size
    escala = min(1.0, ancho_escena / sprite_w, alto_escena / sprite_h)
    sprite_w, sprite_h = max(1, round(sprite_w * escala)), max(1, round(sprite_h * escala))
    sx = ex + (ancho_escena - sprite_w) // 2
    sy = escena_y + (alto_escena - sprite_h) // 2
    resplandor = Image.new('RGBA', (ancho_escena, alto_escena))
    ImageDraw.Draw(resplandor).ellipse(
        (ancho_escena * .16, alto_escena * .22, ancho_escena * .84, alto_escena * .88),
        fill=TIPO + (56,))
    canvas.alpha_composite(resplandor.filter(ImageFilter.GaussianBlur(30)), (ex, escena_y))

    y = escena_y + (10 if wide else 2) if lado_a_lado else escena_y + alto_escena + GAP_M
    text(hx, y, f'#{num:03d}', F_NUM, GRIS)
    text(hx + F_NUM.getlength(f'#{num:03d}') + 12, y + 1, region(num).upper(), F_SEC, GRIS, 1.2)
    y += 24
    # The Game Boy font does NOT travel in the repo and may be missing: the
    # original project was published without a licence file, i.e. all rights
    # reserved (see the block in Appearance.qml). Without it, `font()` would
    # fall back to ImageFont.load_default, an 11 px bitmap, and here it is
    # asked for at 28 or 40: the name would come out blurry. The bold mono is
    # not the Game Boy one, but it reads.
    fuente_nombre = font(RUTA_PKM if RUTA_PKM.exists() else RUTA_MB,
                         40 if wide else 28, 'Regular')
    for linea in wrap(nom(num).upper(), hw, fuente_nombre):
        text(hx, y, linea, fuente_nombre, BLANCO)
        y += 46 if wide else 34
    genero = (dex.get('genero') or {}).get(lang) or ''
    medidas = f"{num_idioma(dex['m'])} m · {num_idioma(dex['kg'])} kg" if dex.get('m') else ''
    meta = ' · '.join(v for v in (genero, medidas) if v)
    if meta:
        y = parrafo(meta, hx, y + (12 if wide else 6), hw, F_SEC, GRIS, 18) + 8
    y = pills([(nombre_tipo(t), legible(rgb(color_tipo(t)))) for t in mios], hx, y, hw)

    descripcion = (dex.get('texto') or {}).get(lang) or (dex.get('texto') or {}).get('en')
    if descripcion and wide:
        # At full width the lines went past 90 characters and the eye lost its
        # place: the description is read at paragraph measure, not screen width.
        y = parrafo(descripcion, hx, y + 14, min(hw, 560), F_FILA, GRIS, 20)
    y = max(y, escena_y + alto_escena) + GAP_L
    if descripcion and not wide:
        y = parrafo(descripcion, left, y, area, F_FILA, GRIS, 20) + GAP_L

    def cuerpo_hexagono(x, yy, w):
        """The hexagon of the six figures, which is the face of a Pokédex.

        In wide mode it is the ONLY reading of the stats: abbreviation and
        figure at each vertex, like the games' summary screen. Having it next
        to the bars told the same thing twice with the same abbreviations, and
        that was half of what made the card look like a widget dashboard.

        Anti-aliasing is paid for only here: a 3x canvas of the whole card cost
        half a second per frame to draw 150 px of edges.
        """
        valores = [stats[i] for i in (0, 1, 2, 5, 4, 3)]
        radio = min(92, (w - 128) / 2)
        cx, cy = x + w / 2, yy + radio + 34
        margen = 8
        ox, oy = math.floor(cx - radio - margen), math.floor(cy - radio - margen)
        lado = math.ceil(2 * (radio + margen))
        capa = Image.new('RGBA', (lado * 3, lado * 3))
        ld = ImageDraw.Draw(capa)

        def punto(i, frac):
            angulo = math.radians(-90 + i * 60)
            return ((cx - ox + math.cos(angulo) * radio * frac) * 3,
                    (cy - oy + math.sin(angulo) * radio * frac) * 3)

        # The outline leads and the inner web follows: with all three rings at
        # the same weight, a small polygon read as an empty net.
        ld.polygon([punto(i, 1) for i in range(6)], outline=BLANCO + (44,), width=3)
        for frac in (1 / 3, 2 / 3):
            ld.polygon([punto(i, frac) for i in range(6)], outline=BLANCO + (20,), width=3)
        for i in range(6):
            ld.line((punto(i, 0), punto(i, 1)), fill=BLANCO + (16,), width=3)
        vertices = [punto(i, min(v, 160) / 160) for i, v in enumerate(valores)]
        ld.polygon(vertices, fill=TIPO + (74,), outline=TIPO + (255,), width=6)
        for px, py in vertices:
            ld.ellipse((px - 9, py - 9, px + 9, py + 9), fill=TIPO)
        pega(capa.resize((lado, lado), Image.Resampling.LANCZOS), (ox, oy))
        sube = equipo_info() and naturaleza_sube()
        for i, valor in enumerate(valores):
            angulo = math.radians(-90 + i * 60)
            px = cx + math.cos(angulo) * (radio + 15)
            py = cy + math.sin(angulo) * (radio + 15)
            etiqueta, cifra = T['cortas'][i] + ' ', str(valor)
            tw = F_SEC.getlength(etiqueta) + F_NUM.getlength(cifra)
            # Each label is anchored according to its vertex (above, below or
            # to the side): clamping against the edges made them jump about.
            if i == 0:
                px, py = px - tw / 2, py - 17
            elif i == 3:
                px, py = px - tw / 2, py + 5
            elif i in (1, 2):
                px, py = px + 3, py - 8
            else:
                px, py = px - tw - 3, py - 8
            text(px, py + 2, etiqueta, F_SEC, GRIS)
            text(px + F_SEC.getlength(etiqueta), py, cifra, F_NUM,
                 TIPO if i == sube else BLANCO)
        # The total is the sum of those six figures, so it goes with them.
        fila = cy + radio + 46
        cifra = str(sum(stats))
        tw = ancho(T['total'] + '  ', F_SEC, 0.6) + F_NUM.getlength(cifra)
        tx = x + (w - tw) / 2
        text(tx, fila + 2, T['total'] + '  ', F_SEC, GRIS, 0.6)
        text(tx + ancho(T['total'] + '  ', F_SEC, 0.6), fila, cifra, F_NUM, BLANCO)
        return fila + 24

    def cuerpo_barras(x, yy, w):
        """The six figures with their bars, to read exactly how much."""
        alto_fila = 28
        sube = equipo_info() and naturaleza_sube()
        for i, idx in enumerate((0, 1, 2, 5, 4, 3)):
            valor = stats[idx]
            fila = yy + i * alto_fila
            text(x, fila + 5, T['cortas'][i], F_FILA, GRIS)
            cifra = str(valor)
            text(x + w - ancho(cifra, F_NUM), fila + 4, cifra, F_NUM, color_stat(valor))
            if i == sube:
                # The one the nature raises, marked as on the games' summary
                # screen (there since HeartGold, in red and blue).
                text(x + w - ancho(cifra, F_NUM) - 14, fila + 4, '▲', F_NUM, TIPO)
            ini, fin = x + 46, x + w - 40
            if fin > ini:
                d.rounded_rectangle((ini, fila + 11, fin, fila + 15), radius=2, fill=BLANCO + (20,))
                d.rounded_rectangle((ini, fila + 11, ini + (fin - ini) * min(valor, 160) / 160,
                                     fila + 15), radius=2, fill=TIPO)
        fila = yy + 6 * alto_fila + 4
        d.line((x, fila, x + w, fila), fill=BLANCO + (16,))
        cifra = str(sum(stats))
        text(x, fila + 10, T['total'], F_SEC, GRIS, 0.6)
        text(x + w - ancho(cifra, F_NUM), fila + 9, cifra, F_NUM, BLANCO)
        return fila + 28

    def cuerpo_debiles(x, yy, w):
        return pills([(nombre_tipo(t) + (' ×4' if m == 4 else ''), legible(rgb(color_tipo(t))))
                      for t, m in debiles], x, yy, w)

    def cuerpo_inmunes(x, yy, w):
        return pills([(nombre_tipo(t), legible(rgb(color_tipo(t)))) for t in inmunes], x, yy, w)

    def cuerpo_tamano(x, yy, w):
        """The creature next to you, to scale, like the Pokédex since gen four.

        A figure in metres says nothing: "0,1 m" and "14,5 m" read just as fast
        and neither can be pictured. The games solved it by putting the trainer
        alongside, and it works because the reference is you.
        """
        alto_ref = 74
        metros = dex.get('m') or 0
        if not metros:
            return yy
        px_por_metro = alto_ref / max(1.7, metros)
        alto_persona = round(1.7 * px_por_metro)
        base = yy + alto_ref

        # The trainer: a plain pictogram, since here it is not the star.
        px = x + 22
        cabeza = alto_persona / 6.8
        hombro = base - alto_persona + cabeza * 1.25
        cadera = base - alto_persona * 0.46
        d.ellipse((px - cabeza / 2, base - alto_persona, px + cabeza / 2,
                   base - alto_persona + cabeza), fill=GRIS)
        d.rounded_rectangle((px - cabeza * 0.62, hombro, px + cabeza * 0.62, cadera),
                            radius=cabeza * 0.5, fill=GRIS)
        for lado in (-1, 1):
            d.rounded_rectangle((px + lado * cabeza * 0.12 - cabeza * 0.24, cadera,
                                 px + lado * cabeza * 0.12 + cabeza * 0.24, base),
                                radius=cabeza * 0.22, fill=GRIS)

        # The creature, one of its frames cropped and set at the same scale.
        alto_bicho = max(3, round(metros * px_por_metro))
        try:
            with Image.open(gif) as fuente:
                quieto = fuente.convert('RGBA')
            caja = quieto.getbbox()
            if caja:
                quieto = quieto.crop(caja)
            ancho_bicho = max(3, round(quieto.width * alto_bicho / quieto.height))
            quieto = quieto.resize((ancho_bicho, alto_bicho), Image.Resampling.NEAREST)
            pega(quieto, (round(x + 62), round(base - alto_bicho)))
        except OSError:
            ancho_bicho = 0
        # The ground line reaches as far as the scene does, not as far as the
        # column: a rule hovering over empty space looks like a mistake.
        fin = x + min(w, max(120, 62 + ancho_bicho + 34))
        d.line((x, base + 1, fin, base + 1), fill=BLANCO + (16,))
        text(x, base + 8, f"{num_idioma(1.7)} m", F_SEC, GRIS)
        etiqueta = f"{num_idioma(dex['m'])} m"
        text(x + 62, base + 8, etiqueta, F_SEC, BLANCO)
        return base + 28

    def cuerpo_habs(x, yy, w):
        for hab in dex.get('habilidades') or []:
            value = (habs_nombres.get(hab['clave']) or {}).get(lang) or hab['clave']
            text(x, yy, value, F_FILA, BLANCO)
            if hab.get('oculta'):
                text(x + ancho(value) + 8, yy + 1, T['oculta'], F_SEC, GRIS)
            yy += 22
        return yy + 2

    # Without boxes, what separates two sections is the gap: it has to be larger
    # than the one inside a section, or they read as one long list. Between one
    # band and the next, a hairline at 6 % like Card.qml's border.
    BANDA = 28
    rotulo_stats = 'STATS' if lang == 'en' else 'ESTADÍSTICAS'
    pilas = [(debiles, T['debil'], cuerpo_debiles),
             (inmunes, T['inmune'], cuerpo_inmunes),
             (dex.get('habilidades'), T['habs'], cuerpo_habs)]

    d.line((left, y, right, y), fill=BLANCO + (16,))
    y += 22
    arr = y
    if wide:
        # Three fixed columns with the same gutter: hexagon | battle | body.
        G = 32
        c1, c3 = 330, 236
        c2 = area - c1 - c3 - 2 * G
        x2, x3 = left + c1 + G, left + c1 + G + c2 + G
        y1 = seccion(left, arr, c1, rotulo_stats, cuerpo_hexagono) + BANDA \
            if len(stats) == 6 else arr
        y2 = arr
        for cond, rotulo, cuerpo in pilas:
            if cond:
                y2 = seccion(x2, y2, c2, rotulo, cuerpo) + BANDA
        y3 = arr
        if con_tamano and dex.get('m'):
            y3 = seccion(x3, y3, c3, T['tamano'], cuerpo_tamano) + BANDA
        y = max(y1, y2, y3)
    elif medio:
        G = 28
        c1 = round((area - G) * 0.52)
        x2 = left + c1 + G
        y1 = seccion(left, arr, c1, rotulo_stats, cuerpo_barras) + BANDA \
            if len(stats) == 6 else arr
        y2 = arr
        for cond, rotulo, cuerpo in pilas:
            if cond:
                y2 = seccion(x2, y2, right - x2, rotulo, cuerpo) + BANDA
        y = max(y1, y2)
    else:
        if len(stats) == 6:
            y = seccion(left, y, area, rotulo_stats, cuerpo_barras) + BANDA
        for cond, rotulo, cuerpo in pilas:
            if cond:
                y = seccion(left, y, area, rotulo, cuerpo) + BANDA

    # ── evolution and team, the last band ─────────────────────────────────
    equipo = equipo_info()

    def cuerpo_equipo(x, yy, w):
        text(x, yy, equipo[0], F_FILA, ACCENT)
        return parrafo(' · '.join([equipo[1]] + equipo[3:]), x, yy + 20, w, F_SEC, GRIS, 17)

    if cadena or equipo:
        y -= 4
        d.line((left, y, right, y), fill=BLANCO + (16,))
        y += 20
    if cadena:
        hueco = min(170, (area - 24) / len(cadena))

        def cuerpo_evo(x, yy, w):
            # The chain is centred in its band: flush left it left half the
            # card's width blank and the composition tipped that way.
            bx = x + max(0, (w - hueco * len(cadena)) / 2)
            alto_nombre = max(len(wrap(nom(n), hueco - 12, F_SEC)) for n in cadena) * 17
            for i, n in enumerate(cadena):
                centro = bx + hueco * (i + .5)
                try:
                    sp = Image.open(H / f'.cache/pokeanim/{n}.gif').convert('RGBA')
                    caja = sp.getbbox()
                    if caja:
                        sp = sp.crop(caja)
                    # max(1, ...): with a very narrow window, hueco - 26 drops to
                    # zero or below and PIL blows up with
                    #   ValueError: height and width must be > 0
                    # The Pokédex is resizable on purpose, so shrinking it must
                    # not kill the process with a traceback inside kitty.
                    sp.thumbnail((max(1, int(min(80, hueco - 26))), 66), Image.Resampling.NEAREST)
                    if n != num:
                        sp.putalpha(sp.getchannel('A').point(lambda v: v * 62 // 100))
                    pega(sp, (round(centro - sp.width / 2), round(yy + 66 - sp.height)))
                # ValueError as well as OSError: OSError only covers a missing or
                # corrupt file, not impossible sizes. A failure composing ONE
                # sprite of the evolution chain must not take the whole card
                # down with it.
                except (OSError, ValueError):
                    pass
                for j, linea in enumerate(wrap(nom(n), hueco - 12, F_SEC)):
                    text(centro - F_SEC.getlength(linea) / 2, yy + 74 + j * 17, linea, F_SEC,
                         BLANCO if n == num else GRIS)
                if i < len(pasos):
                    ax, ay = bx + hueco * (i + 1), yy + 38
                    d.line((ax - 10, ay, ax + 8, ay), fill=GRIS, width=1)
                    d.line((ax + 4, ay - 4, ax + 8, ay, ax + 4, ay + 4), fill=GRIS, width=1)
                    paso = pasos[i]
                    if paso.get('como') == 'nivel' and paso.get('nivel'):
                        v = f"{T['nv']} {paso['nivel']}"
                        text(ax - ancho(v, F_SEC) / 2, ay - 22, v, F_SEC, GRIS)
                    elif paso.get('como') == 'piedra':
                        d.polygon((ax, ay - 20, ax + 4, ay - 15, ax, ay - 10, ax - 4, ay - 15), fill=GRIS)
            return yy + 74 + alto_nombre

        arranque = y
        # The team goes beside the chain only if the window has room for it; in
        # narrow mode the two titles fought over the same line.
        al_lado = bool(equipo) and wide
        ancho_evo = area * 0.62 if al_lado else area
        y = seccion(left, arranque, ancho_evo, 'EVOLUCIÓN' if lang == 'es' else 'EVOLUTION',
                    cuerpo_evo)
        if al_lado:
            y = max(y, seccion(left + ancho_evo + GAP_L * 2, arranque,
                               area - ancho_evo - GAP_L * 2, equipo[2], cuerpo_equipo))
        elif equipo:
            y = seccion(left, y + BANDA, area, equipo[2], cuerpo_equipo)
    elif equipo:
        y = seccion(left, y, area, equipo[2], cuerpo_equipo)

    alto_ficha = y + 8
    # The size comparison is the first thing to go: if the card no longer fits
    # in its window, it is redone without it rather than letting it come out cut.
    if con_tamano and alto_ficha > height - 26:
        return compose(width, height, con_tamano=False)
    return canvas.crop((0, 0, width, alto_ficha)), (sx, sy, sprite_w, sprite_h)


def escala_sprite(sw, sh):
    """The GIF at another size, saved to disk so it is not paid for again.

    Rescaling 90 frames costs 165 ms of decoding and 456 ms of writing, and the
    creature does not change size between two presses: the second time this
    pokémon comes up in this window, it is already done.
    """
    destino = H / '.cache/pokeanim/.escalados' / f'{num}-{sw}x{sh}.gif'
    if destino.exists() and destino.stat().st_mtime >= gif.stat().st_mtime:
        return destino
    from PIL import ImageSequence
    frames, durations = [], []
    with Image.open(gif) as source:
        # A single pass: walking the sequence twice (once for the frames and
        # once for their durations) paid for the whole decode twice.
        for f in ImageSequence.Iterator(source):
            durations.append(f.info.get('duration', 100))
            frames.append(f.convert('RGBA').resize((sw, sh), Image.Resampling.NEAREST))
    destino.parent.mkdir(parents=True, exist_ok=True)
    provisional = destino.with_suffix('.parcial')
    frames[0].save(provisional, format='GIF', save_all=True, append_images=frames[1:],
                   duration=durations, loop=0, disposal=2)
    provisional.replace(destino)
    return destino


def viewport(card, sprite, width, height, offset=0, preview=False):
    # A reserved strip at the bottom stops icat from causing a scroll and wiping its graphics.
    footer = 26 if height >= 120 else 0
    available = max(1, height - footer)
    overflow = max(0, card.height - available)
    offset = min(max(0, offset), overflow)
    x = max(0, (width - card.width) // 2)
    # The footer is subtracted from the usable height, so centring against it
    # always left 26 px more air below than above. A short card (a creature
    # with no evolution or team) showed it as if it were stuck to the ceiling.
    y = max(0, (available - card.height) // 2 + footer // 2)
    frame = Image.new('RGBA', (width, height))
    frame.alpha_composite(card.crop((0, offset, card.width, min(card.height, offset + available))), (x, y))
    sx, sy, sw, sh = sprite
    position = (x + sx, y + sy - offset, sw, sh)
    if preview or position[1] < 0 or position[1] + sh > available:
        sp = Image.open(gif).convert('RGBA').resize((sw, sh), Image.Resampling.NEAREST)
        # Clipped composite: the creature's feet do not tread on the footer's hint.
        clipped = Image.new('RGBA', (width, available))
        clipped.alpha_composite(sp, position[:2])
        frame.alpha_composite(clipped)
    d = ImageDraw.Draw(frame)
    if footer:
        hint = ('↑↓ desplazar · Esc cerrar' if lang == 'es' else '↑↓ scroll · Esc close') if overflow else \
               ('Cualquier tecla para cerrar' if lang == 'es' else 'Press any key to close')
        # At 11 px Adwaita merged the spaces ("Pressany key"); one point more
        # and a touch of air between letters and the hint is a sentence again.
        paso_pie = [F_PIE.getlength(ch) + 0.4 for ch in hint]
        if sum(paso_pie) <= width - 16:
            hx_ = (width - sum(paso_pie)) / 2
            for ch, avance in zip(hint, paso_pie):
                d.text((round(hx_), height - 19), ch, font=F_PIE, fill=DIM)
                hx_ += avance
    if overflow and width >= 100:
        track_h = max(10, available - 24)
        thumb_h = max(14, track_h * available / card.height)
        top = 12 + (track_h - thumb_h) * offset / overflow
        d.rounded_rectangle((width - 5, top, width - 3, top + thumb_h), radius=1, fill=MUTED)
    return frame, position, offset, overflow


def geometry():
    rows, cols, xp, yp = struct.unpack('HHHH', __import__('fcntl').ioctl(1, termios.TIOCGWINSZ, b'\0' * 8))
    cols, rows = max(1, cols), max(1, rows)
    return cols, rows, xp or cols * 9, yp or rows * 20


def run():
    import re
    dirty = True
    changed_at = 0.0
    interrupted = False

    def resized(*_):
        nonlocal dirty, changed_at
        dirty = True
        changed_at = time.monotonic()

    def stop(*_):
        nonlocal interrupted
        interrupted = True

    signal.signal(signal.SIGWINCH, resized)
    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)
    old = termios.tcgetattr(0)
    offset, overflow = 0, 0
    deadline = time.monotonic() + args.timeout
    previous_size = None
    pending = b''
    with tempfile.TemporaryDirectory(prefix='pokedex-') as tmp:
        card_path = Path(tmp) / 'viewport.png'
        sprite_path = Path(tmp) / 'sprite.gif'
        last_sprite_size = None
        try:
            tty.setcbreak(0)
            sys.stdout.write('\033[?1049h\033[?25l\033[?1004h\033[?1000h\033[?1006h')
            sys.stdout.flush()
            while not interrupted:
                now = time.monotonic()
                if now >= deadline:
                    break
                # Tiling debounce: render once the size settles, without piling
                # up processes or rebuilding on every Hyprland frame.
                if dirty and now - changed_at >= .08:
                    size = geometry()
                    cols, rows, xp, yp = size
                    cw, ch = xp / cols, yp / rows
                    width, height = max(1, xp), max(1, int(yp - ch))
                    if size != previous_size:
                        fraction = offset / overflow if overflow else 0
                        card, sprite = compose(max(80, width - 16), height)
                        offset = round(fraction * max(0, card.height - max(1, height - 26)))
                        previous_size = size
                    frame, pos, offset, overflow = viewport(card, sprite, width, height, offset)
                    # A PNG that lives two milliseconds and never leaves /tmp:
                    # squeezing it to the maximum cost 60 ms of CPU per frame to
                    # save disk space nobody was going to use.
                    frame.save(card_path, compress_level=1)
                    options = ['kitten', 'icat', '--stdin=no', '--transfer-mode=file',
                               '--use-window-size', f'{cols},{rows},{xp},{yp}',
                               '--no-trailing-newline', '--fit=none', '--align=left']
                    sys.stdout.write('\033[?2026h\033_Ga=d,d=A,q=2\033\\\033[2J\033[H')
                    sys.stdout.flush()
                    subprocess.run(options + ['--image-id=41', str(card_path)], stdin=subprocess.DEVNULL,
                                   stderr=subprocess.DEVNULL, check=True, timeout=5)
                    sx, sy, sw, sh = pos
                    # Do not draw outside the visible area: scrolling must never
                    # scroll the terminal, nor place the GIF over the footer.
                    px, py = round(sx / cw), round(sy / ch)
                    if py >= 0 and py * ch + sh <= height - 26 and px * cw + sw <= width:
                        if last_sprite_size != (sw, sh):
                            with Image.open(gif) as source:
                                if source.size == (sw, sh):
                                    shutil.copyfile(gif, sprite_path)
                                else:
                                    escalado = escala_sprite(sw, sh)
                                    shutil.copyfile(escalado, sprite_path)
                            last_sprite_size = (sw, sh)
                        sys.stdout.write(f'\033[{py + 1};{px + 1}H')
                        sys.stdout.flush()
                        subprocess.run(options + ['--image-id=42', '--loop=-1',
                                                  '--place', f'{math.ceil(sw / cw)}x{math.ceil(sh / ch)}@{px}x{py}',
                                                  str(sprite_path)],
                                       stdin=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                                       check=True, timeout=5)
                    sys.stdout.write('\033[H\033[?2026l')
                    sys.stdout.flush()
                    # SIGWINCH may arrive while icat is working.
                    dirty = geometry() != size
                    if dirty:
                        changed_at = time.monotonic()
                    deadline = time.monotonic() + args.timeout
                ready, _, _ = select.select([0], [], [], .05)
                if not ready:
                    continue
                chunk = os.read(0, 4096)
                if not chunk:
                    break
                pending += chunk
                # Sequences may arrive split across reads.
                while pending:
                    if pending.startswith(b'\033'):
                        match = re.match(rb'\x1b\[(?:[0-9;<]*[A-Za-z~])', pending)
                        if not match:
                            if select.select([0], [], [], .025)[0]:
                                pending += os.read(0, 4096)
                                continue
                            return
                        key = match.group()
                        pending = pending[len(key):]
                    else:
                        key, pending = pending[:1], pending[1:]
                    if key == b'\033[O':
                        # On losing focus it goes away, because the timeout used
                        # to run only with the window in front: you moved on to
                        # something else and a kitty stayed alive for ever behind
                        # the tiling. A popup opened with a key does not survive
                        # you looking elsewhere, but it is given time to come back.
                        deadline = min(deadline, time.monotonic() + DESPEDIDA)
                        continue
                    if key == b'\033[I':
                        deadline = time.monotonic() + args.timeout
                        continue
                    delta = 0
                    if key in (b'\033[A', b'k'):
                        delta = -54
                    elif key in (b'\033[B', b'j'):
                        delta = 54
                    elif key == b'\033[5~':
                        delta = -max(54, height - 80)
                    elif key == b'\033[6~':
                        delta = max(54, height - 80)
                    elif key in (b'\033[H', b'\033[1~'):
                        delta = -overflow
                    elif key in (b'\033[F', b'\033[4~'):
                        delta = overflow
                    elif key.startswith(b'\033[<'):
                        button = int(key[3:].split(b';')[0])
                        if button & 64:
                            delta = 54 if button & 1 else -54
                        else:
                            deadline = time.monotonic() + args.timeout
                            continue
                    else:
                        return
                    new_offset = max(0, min(overflow, offset + delta))
                    dirty = dirty or new_offset != offset
                    offset = new_offset
                    deadline = time.monotonic() + args.timeout
        finally:
            sys.stdout.write('\033[?2026l\033_Ga=d,d=A,q=2\033\\\033[?1006l\033[?1000l\033[?1004l\033[?25h\033[?1049l')
            sys.stdout.flush()
            termios.tcsetattr(0, termios.TCSADRAIN, old)


if __name__ == '__main__':
    if args.render:
        width, height = map(int, args.render.lower().split('x'))
        card, sprite = compose(max(80, width - 16), height)
        frame, _, _, overflow = viewport(card, sprite, width, height, preview=True)
        backdrop = Image.new('RGBA', frame.size, BG)
        backdrop.alpha_composite(frame)
        backdrop.convert('RGB').save(args.output)
        print(json.dumps({'size': [width, height], 'content': list(card.size), 'scroll': overflow,
                          'output': args.output}))
    else:
        run()
