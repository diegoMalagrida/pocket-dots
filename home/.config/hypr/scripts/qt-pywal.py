#!/usr/bin/env python3
"""Genera la paleta de las aplicaciones Qt a partir de la de pywal.

El escritorio va con QT_QPA_PLATFORMTHEME=qt6ct (ver environment.d), y VLC
-la unica app Qt5- con qt5ct desde el envoltorio ~/.local/bin/vlc. Los dos
temas de plataforma leen su paleta de un fichero, y ese fichero lo escribe
esto.

Antes el escritorio iba con el tema gtk3 y solo hacia falta para Qt5. El
motivo de cambiar: con gtk3, Qt6 SI heredaba los colores (su plugin qgtk3 lee
widgets GTK reales) pero solo al abrir la ventana, asi que las que ya estaban
abiertas se quedaban con la paleta vieja hasta reiniciarlas. Qt5 nunca los
heredo: su qgtk3 aporta dialogos, fuentes y hints, jamas colores -medido con
un binario Qt5 minimo, con gtk3 y sin gtk3 daba lo mismo-, y por eso VLC salia
blanco (#efefef sobre #ffffff) en medio de un escritorio de pywal.

Las salidas son tres:

  1. El esquema de qt5ct (~/.config/qt5ct/colors/pywal.conf), para VLC.
  2. El de qt6ct, para el resto del escritorio Qt.
  3. Las secciones de color de ~/.config/kdeglobals, que es lo que leen las
     apps de KDE Frameworks cuando piden colores por su cuenta (KColorScheme).
     Ahi habia un esquema lila estatico, 'MaterialYouDark', heredado de los
     metapaquetes viejos, que no tenia nada que ver con el fondo.

De cada uno de los dos *ct solo se escribe lo suyo si esta instalado; si
falta, no se crea basura que nadie lee.
"""

import colorsys
import json
import os
import re
import shutil
import sys
from datetime import date

CACHE = os.path.expanduser("~/.cache/wal/colors.json")
CONFIG = os.path.expanduser("~/.config")
BACKUPS = os.path.expanduser(f"~/.config-rice-backups/{date.today().isoformat()}")


# --- utilidades de color -----------------------------------------------------

def rgb(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) / 255 for i in (0, 2, 4))


def hexa(t):
    return "#" + "".join(f"{max(0, min(255, round(c * 255))):02x}" for c in t)


def lum(h):
    """Luminancia relativa (WCAG), para decidir claro/oscuro y contrastes."""
    def lin(c):
        return c / 12.92 if c <= 0.03928 else ((c + 0.055) / 1.055) ** 2.4
    r, g, b = rgb(h)
    return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)


def contrast(a, b):
    la, lb = lum(a), lum(b)
    hi, lo = max(la, lb), min(la, lb)
    return (hi + 0.05) / (lo + 0.05)


def shade(h, amount):
    """Aclara (amount>0) u oscurece (amount<0) moviendo la L de HLS.

    Se hace en HLS y no mezclando con blanco/negro para no lavar el tinte: los
    fondos de pywal suelen ser casi negros con un tinte de la imagen, y ese
    tinte es justo lo que hace que la ventana parezca del mismo mundo que el
    escritorio.
    """
    r, g, b = rgb(h)
    hh, ll, ss = colorsys.rgb_to_hls(r, g, b)
    ll = max(0.0, min(1.0, ll + amount))
    return hexa(colorsys.hls_to_rgb(hh, ll, ss))


def mix(a, b, t):
    """Mezcla lineal: t=0 devuelve a, t=1 devuelve b."""
    ra, ga, ba = rgb(a)
    rb, gb, bb = rgb(b)
    return hexa((ra + (rb - ra) * t, ga + (gb - ga) * t, ba + (bb - ba) * t))


def legible(fondo, *candidatos):
    """El candidato que mas contraste da sobre 'fondo'."""
    return max(candidatos, key=lambda c: contrast(fondo, c))


def semantico(base, fondo, tono, sat_min=0.45):
    """Un color de aviso (error, exito, atencion) con el tinte de la paleta.

    Los tres semanticos no pueden salir de pywal tal cual: con un fondo azul,
    color1 sale azul y un mensaje de error en azul no avisa de nada. Se coge la
    luz y la saturacion de la paleta -para que siga siendo de esta casa- pero se
    fuerza el tono al que la gente ya sabe leer, y se sube la luz hasta que se
    lea sobre el fondo.
    """
    r, g, b = rgb(base)
    _, ll, ss = colorsys.rgb_to_hls(r, g, b)
    ss = max(ss, sat_min)
    ll = min(max(ll, 0.45), 0.75) if lum(fondo) < 0.5 else min(max(ll, 0.30), 0.50)
    color = hexa(colorsys.hls_to_rgb(tono, ll, ss))
    paso = 0.04 if lum(fondo) < 0.5 else -0.04
    while contrast(fondo, color) < 3.5 and 0.05 < ll < 0.95:
        ll += paso
        color = hexa(colorsys.hls_to_rgb(tono, ll, ss))
    return color


# --- paleta ------------------------------------------------------------------

def construir(wal):
    c = wal["colors"]
    esp = wal["special"]
    bg, fg = esp["background"], esp["foreground"]
    accent = c["color4"]
    oscuro = lum(bg) < 0.5
    # Signo del relieve: sobre fondo oscuro las superficies suben, sobre fondo
    # claro bajan. Sin esto, un wallpaper claro dejaria los botones invisibles.
    s = 1 if oscuro else -1

    p = {}
    p["window"] = bg
    p["windowtext"] = fg
    # Las vistas (listas, cajas de texto) se hunden un pelin respecto a la
    # ventana; los botones suben. Es el mismo relieve que usa Fusion.
    p["base"] = shade(bg, -0.030 * s)
    p["alternatebase"] = shade(bg, 0.035 * s)
    p["text"] = fg
    p["button"] = shade(bg, 0.055 * s)
    p["buttontext"] = fg
    p["brighttext"] = c["color15"]
    p["light"] = shade(p["button"], 0.10 * s)
    p["midlight"] = shade(p["button"], 0.05 * s)
    p["mid"] = shade(p["button"], -0.05 * s)
    p["dark"] = shade(p["button"], -0.10 * s)
    p["shadow"] = shade(bg, -0.06 * s)
    p["highlight"] = accent
    # El texto seleccionado se elige por contraste medido, no a ojo: con
    # acentos oscuros (un azul de noche) el fondo de pywal encima no se leia.
    p["highlightedtext"] = legible(accent, bg, fg, c["color15"], c["color0"])
    if contrast(accent, p["highlightedtext"]) < 4.5:
        # Si la paleta no da ningun color legible sobre el acento, blanco o
        # negro: una seleccion que no se lee es peor que un color de fuera.
        p["highlightedtext"] = legible(accent, "#ffffff", "#000000")
    p["link"] = c["color6"] if contrast(bg, c["color6"]) >= 3.5 else shade(accent, 0.15 * s)
    p["linkvisited"] = c["color5"] if contrast(bg, c["color5"]) >= 3.5 else shade(c["color5"], 0.15 * s)
    p["tooltipbase"] = shade(bg, 0.08 * s)
    p["tooltiptext"] = fg
    p["placeholder"] = mix(fg, bg, 0.55)
    p["accent"] = accent
    # Deshabilitado: no un gris cualquiera, sino el propio texto acercado al
    # fondo, que es lo que hace que se lea como "apagado" y no como "roto".
    p["disabledtext"] = mix(fg, bg, 0.62)
    p["border"] = shade(bg, 0.14 * s)
    return p


# --- salida 1: esquema de color de qt5ct / qt6ct ------------------------------

# Orden de QPalette::ColorRole tal y como lo serializa qt5ct/qt6ct: una lista
# de colores separados por comas, por indice de rol. Los tres grupos (activo,
# deshabilitado, inactivo) llevan la lista entera.
ROLES = [
    "windowtext", "button", "light", "midlight", "dark", "mid", "text",
    "brighttext", "buttontext", "base", "window", "shadow", "highlight",
    "highlightedtext", "link", "linkvisited", "alternatebase", "norole",
    "tooltipbase", "tooltiptext", "placeholder", "accent",
]


def lista_colores(p, grupo):
    fuera = []
    for rol in ROLES:
        if rol == "norole":
            fuera.append(p["window"])
            continue
        v = p[rol]
        if grupo == "disabled" and rol in ("windowtext", "text", "buttontext", "brighttext"):
            v = p["disabledtext"]
        if grupo == "disabled" and rol == "highlight":
            v = p["button"]
        if grupo == "inactive" and rol == "highlight":
            v = mix(p["highlight"], p["window"], 0.35)
        fuera.append(v)
    # qt5ct/qt6ct esperan #AARRGGBB
    return ", ".join("#ff" + v.lstrip("#").lower() for v in fuera)


def escribir_esquema(p, destino):
    os.makedirs(os.path.dirname(destino), exist_ok=True)
    texto = (
        "[ColorScheme]\n"
        "; generado por qt-pywal.py a partir de ~/.cache/wal/colors.json\n"
        "; se reescribe en cada cambio de fondo: no editar a mano\n"
        f"active_colors={lista_colores(p, 'active')}\n"
        f"disabled_colors={lista_colores(p, 'disabled')}\n"
        f"inactive_colors={lista_colores(p, 'inactive')}\n"
    )
    escribir_en_sitio(destino, texto)


def asegurar_conf_ct(carpeta, esquema):
    """Deja el qt5ct.conf/qt6ct.conf apuntando al esquema, sin pisar el resto.

    Si el usuario nunca ha abierto qt5ct, el fichero no existe y se crea con lo
    minimo. Si existe, solo se tocan las tres claves que hacen falta para que
    la paleta se aplique.
    """
    nombre = os.path.basename(carpeta)
    conf = os.path.join(carpeta, f"{nombre}.conf")
    claves = {
        "color_scheme_path": esquema,
        "custom_palette": "true",
        "style": "Fusion",
        "icon_theme": primer_tema_de_iconos(),
    }
    if not os.path.exists(conf):
        os.makedirs(carpeta, exist_ok=True)
        cuerpo = "[Appearance]\n" + "".join(f"{k}={v}\n" for k, v in claves.items())
        # Los dialogos de fichero siguen siendo los de GTK: es lo que usa el
        # resto del escritorio, y el unico trozo del tema gtk3 que interesaba
        # conservar al pasar a qt6ct.
        cuerpo += "standard_dialogs=gtk3\n"
        escribir_en_sitio(conf, cuerpo)
        return

    with open(conf, encoding="utf-8") as f:
        lineas = f.read().splitlines()
    salida, en_appearance, puestas = [], False, set()
    for linea in lineas:
        if linea.startswith("["):
            if en_appearance:
                # Detras de la ultima clave de la seccion, no detras del hueco
                # en blanco que la separa de la siguiente.
                while salida and not salida[-1].strip():
                    salida.pop()
                for k, v in claves.items():
                    if k not in puestas:
                        salida.append(f"{k}={v}")
                        puestas.add(k)
                salida.append("")
            en_appearance = linea.strip() == "[Appearance]"
        elif en_appearance:
            m = re.match(r"\s*([A-Za-z_]+)\s*=", linea)
            if m and m.group(1) in claves:
                k = m.group(1)
                salida.append(f"{k}={claves[k]}")
                puestas.add(k)
                continue
        salida.append(linea)
    if en_appearance:
        for k, v in claves.items():
            if k not in puestas:
                salida.append(f"{k}={v}")
    elif "[Appearance]" not in "\n".join(salida):
        salida.append("[Appearance]")
        salida += [f"{k}={v}" for k, v in claves.items()]
    # El .conf se toca EL ULTIMO y siempre, aunque no haya cambiado nada: es el
    # fichero que vigila el tema de plataforma, y ese toque es la senal de "vuelve
    # a leer los colores" para las aplicaciones que ya estan abiertas.
    escribir_en_sitio(conf, "\n".join(salida) + "\n")


# --- salida 2: kdeglobals ----------------------------------------------------

def grupos_kde(p):
    """Las secciones [Colors:*] y [WM] de kdeglobals con la paleta de pywal."""
    comun = {
        "DecorationFocus": p["highlight"],
        "DecorationHover": p["highlight"],
        "ForegroundActive": p["windowtext"],
        "ForegroundInactive": p["disabledtext"],
        "ForegroundLink": p["link"],
        "ForegroundNegative": p["negative"],
        "ForegroundNeutral": p["neutral"],
        "ForegroundNormal": p["windowtext"],
        "ForegroundPositive": p["positive"],
        "ForegroundVisited": p["linkvisited"],
    }

    def bloque(normal, alterno, extra=None):
        d = dict(comun)
        d["BackgroundNormal"] = normal
        d["BackgroundAlternate"] = alterno
        if extra:
            d.update(extra)
        return dict(sorted(d.items()))

    return {
        "Colors:Button": bloque(p["button"], p["alternatebase"]),
        "Colors:Complementary": bloque(p["base"], p["alternatebase"]),
        "Colors:Header": bloque(p["window"], p["alternatebase"]),
        "Colors:Header][Inactive": bloque(p["base"], p["alternatebase"]),
        "Colors:Selection": bloque(
            p["highlight"], p["highlight"],
            {
                "ForegroundActive": p["highlightedtext"],
                "ForegroundInactive": p["highlightedtext"],
                "ForegroundNormal": p["highlightedtext"],
                "ForegroundLink": p["highlightedtext"],
                "ForegroundVisited": p["highlightedtext"],
            },
        ),
        "Colors:Tooltip": bloque(p["tooltipbase"], p["alternatebase"]),
        "Colors:View": bloque(p["base"], p["alternatebase"]),
        "Colors:Window": bloque(p["window"], p["alternatebase"]),
    }


def coma_rgb(h):
    return ",".join(str(round(c * 255)) for c in rgb(h))


ICONOS = [
    os.path.expanduser("~/.local/share/icons"),
    os.path.expanduser("~/.icons"),
    "/usr/share/icons",
]


def tema_de_iconos_existe(nombre):
    return any(os.path.isdir(os.path.join(d, nombre)) for d in ICONOS)


def primer_tema_de_iconos():
    """El tema de iconos para las apps Qt: el mismo que usa GTK.

    Se lee del settings.ini de GTK3 en vez de fijarlo aqui para que las dos
    mitades del escritorio ensenen el mismo icono. Con breeze-dark, un kdialog
    sacaba el circulo azul de KDE -un azul fijo, ajeno a pywal- donde el resto
    del escritorio ensena el de Adwaita.
    """
    ini = os.path.join(CONFIG, "gtk-3.0", "settings.ini")
    try:
        with open(ini, encoding="utf-8") as f:
            m = re.search(r"^gtk-icon-theme-name\s*=\s*(.+)$", f.read(), re.M)
        if m and tema_de_iconos_existe(m.group(1).strip()):
            return m.group(1).strip()
    except OSError:
        pass
    for nombre in ("Adwaita", "breeze-dark", "breeze"):
        if tema_de_iconos_existe(nombre):
            return nombre
    return "hicolor"


def actualizar_kdeglobals(p):
    ruta = os.path.join(CONFIG, "kdeglobals")
    previo = []
    if os.path.exists(ruta):
        with open(ruta, encoding="utf-8") as f:
            previo = f.read().splitlines()
        respaldo(ruta)

    nuevas = grupos_kde(p)
    # Se conserva todo lo que no sea color (fuentes, KFileDialog, iconos...) y
    # se sustituyen enteras las secciones de color, para no dejar mezclada la
    # paleta vieja con la nueva.
    fuera, seccion, saltando = [], None, False
    generales, kde = {}, {}
    for linea in previo:
        if linea.startswith("["):
            seccion = linea.strip().strip("[]").replace("][", "][")
            nombre = linea.strip()[1:-1]
            saltando = (
                nombre in nuevas
                or nombre.startswith("Colors:")
                or nombre == "WM"
                or nombre.startswith("ColorEffects:")
            )
            if not saltando:
                fuera.append(linea)
            continue
        if saltando:
            continue
        if seccion == "General":
            m = re.match(r"(ColorScheme|ColorSchemeHash|LastUsedCustomAccentColor)\s*=", linea)
            if m:
                generales[m.group(1)] = True
                continue
        if seccion == "KDE":
            m = re.match(r"(widgetStyle)\s*=", linea)
            if m:
                kde[m.group(1)] = True
                continue
        if seccion == "Icons":
            # El tema de iconos se reescribe siempre con el de GTK: apuntaba a
            # 'breeze-plus-dark', que se fue con los metapaquetes viejos y
            # dejaba a las apps de KDE sin iconos, y con breeze-dark ensenaban
            # el azul fijo de KDE donde el resto del escritorio ensena Adwaita.
            if re.match(r"Theme\s*=", linea):
                continue
        fuera.append(linea)

    texto = "\n".join(fuera).strip("\n")

    def anadir_a_seccion(txt, nombre, pares):
        """Mete claves dentro de una seccion existente, o la crea al final."""
        marca = f"[{nombre}]"
        if marca in txt:
            partes = txt.split(marca, 1)
            resto = partes[1].lstrip("\n")
            if resto.startswith("["):  # seccion vacia: que no se peguen
                resto = "\n" + resto
            return partes[0] + marca + "\n" + "".join(f"{k}={v}\n" for k, v in pares.items()) + resto
        return txt + f"\n\n{marca}\n" + "".join(f"{k}={v}\n" for k, v in pares.items())

    texto = anadir_a_seccion(texto, "General", {"ColorScheme": "Pywal"})
    texto = anadir_a_seccion(texto, "Icons", {"Theme": primer_tema_de_iconos()})
    # El estilo apuntaba a 'Darkly', que no esta instalado: cualquier app de KDE
    # caia en el estilo por defecto y con el la paleta de fabrica.
    texto = anadir_a_seccion(texto, "KDE", {"widgetStyle": "Fusion"})

    bloques = []
    for nombre, pares in nuevas.items():
        bloques.append(f"[{nombre}]\n" + "".join(f"{k}={v}\n" for k, v in pares.items()))
    # Los efectos de KDE para ventanas inactivas/deshabilitadas: se dejan como
    # estaban salvo el color base, que era el lila del esquema viejo.
    bloques.append(
        "[ColorEffects:Disabled]\n"
        "Color=" + p["window"] + "\n"
        "ColorAmount=0.5\nColorEffect=3\nContrastAmount=0\nContrastEffect=0\n"
        "IntensityAmount=0\nIntensityEffect=0\n"
    )
    bloques.append(
        "[ColorEffects:Inactive]\n"
        "ChangeSelectionColor=true\n"
        "Color=" + p["base"] + "\n"
        "ColorAmount=0.025\nColorEffect=0\nContrastAmount=0.1\nContrastEffect=0\n"
        "Enable=true\nIntensityAmount=0\nIntensityEffect=0\n"
    )
    # [WM] son los colores del marco de ventana; aqui las decora Hyprland, pero
    # alguna app de KDE los usa para su barra de titulo propia.
    bloques.append(
        "[WM]\n"
        f"activeBackground={coma_rgb(p['window'])}\n"
        f"activeBlend={coma_rgb(p['highlight'])}\n"
        f"activeForeground={coma_rgb(p['windowtext'])}\n"
        f"inactiveBackground={coma_rgb(p['base'])}\n"
        f"inactiveBlend={coma_rgb(p['border'])}\n"
        f"inactiveForeground={coma_rgb(p['disabledtext'])}\n"
    )

    texto = texto.rstrip("\n") + "\n\n" + "\n".join(bloques)
    # En el mismo inodo, y por dos motivos. Uno, que las apps de KDE abiertas
    # se enteren, igual que con los .conf de qt5ct/qt6ct. Y dos, el importante:
    # con install.sh --link, ~/.config/kdeglobals ES un enlace al repo, y
    # escribir con temporal + rename SUSTITUYE el enlace por un fichero suelto
    # -- el dotfile se queda desconectado y en silencio.
    escribir_en_sitio(ruta, texto)


# --- fontaneria --------------------------------------------------------------

def respaldo(ruta):
    os.makedirs(BACKUPS, exist_ok=True)
    destino = os.path.join(BACKUPS, os.path.basename(ruta) + ".pre-qt-pywal")
    if not os.path.exists(destino):
        shutil.copy2(ruta, destino)


def escribir_en_sitio(ruta, texto, modo=0o644):
    """Escribe conservando el inodo, en vez de crear y renombrar.

    Es lo que hace que las aplicaciones Qt ya abiertas cambien de color sin
    reiniciarlas. El tema de plataforma de qt5ct/qt6ct vigila su fichero de
    configuracion con QFileSystemWatcher, y un QFileSystemWatcher sigue al
    INODO: en cuanto escribes con el truco habitual de fichero temporal +
    os.replace, el watch se queda mirando un fichero que ya no existe y no
    vuelve a avisar nunca. Medido con VLC delante: con escritura atomica el
    color no se movia; escribiendo en el mismo inodo cambia en tres segundos.
    """
    with open(ruta, "w", encoding="utf-8") as f:
        f.write(texto)
        f.flush()
        os.fsync(f.fileno())
    os.chmod(ruta, modo)


def main():
    try:
        with open(CACHE, encoding="utf-8") as f:
            wal = json.load(f)
    except (OSError, ValueError) as e:
        print(f"qt-pywal: no se pudo leer {CACHE}: {e}", file=sys.stderr)
        return 1

    p = construir(wal)
    c = wal["colors"]
    bg = wal["special"]["background"]
    # Error en rojo, exito en verde, aviso en ambar: el tono se fija, la luz y
    # la saturacion salen de la paleta del fondo.
    p["negative"] = semantico(c["color1"], bg, 0.00)
    p["positive"] = semantico(c["color2"], bg, 0.33)
    p["neutral"] = semantico(c["color3"], bg, 0.10)

    hechos = []
    for nombre in ("qt5ct", "qt6ct"):
        # Solo se genera para los que esten instalados: si no lo estan, sus
        # ficheros serian basura que nadie lee.
        if shutil.which(nombre) is None:
            continue
        carpeta = os.path.join(CONFIG, nombre)
        esquema = os.path.join(carpeta, "colors", "pywal.conf")
        escribir_esquema(p, esquema)
        asegurar_conf_ct(carpeta, esquema)
        hechos.append(nombre)

    actualizar_kdeglobals(p)
    hechos.append("kdeglobals")
    print("qt-pywal: " + ", ".join(hechos))
    return 0


if __name__ == "__main__":
    sys.exit(main())
