#!/usr/bin/env python3
"""Generates the Qt applications' palette from pywal's.

The desktop runs with QT_QPA_PLATFORMTHEME=qt6ct (see environment.d), and VLC
-the only Qt5 app- with qt5ct through the ~/.local/bin/vlc wrapper. Both
platform themes read their palette from a file, and this is what writes that
file.

The desktop used to run with the gtk3 theme and this was only needed for Qt5.
The reason for switching: with gtk3, Qt6 DID inherit the colours (its qgtk3
plugin reads real GTK widgets) but only when the window opened, so the ones
already open kept the old palette until they were restarted. Qt5 never
inherited them: its qgtk3 provides dialogs, fonts and hints, never colours
-measured with a minimal Qt5 binary, with gtk3 and without it made no
difference-, and that is why VLC came out white (#efefef on #ffffff) in the
middle of a pywal desktop.

There are three outputs:

  1. The qt5ct scheme (~/.config/qt5ct/colors/pywal.conf), for VLC.
  2. The qt6ct one, for the rest of the Qt desktop.
  3. The colour sections of ~/.config/kdeglobals, which is what KDE Frameworks
     apps read when they ask for colours on their own (KColorScheme). There
     used to be a static lilac scheme there, 'MaterialYouDark', inherited from
     the old metapackages, which had nothing to do with the wallpaper.

For each of the two *ct, its part is only written if it is installed; if it
is missing, no junk that nobody reads gets created.
"""

import colorsys
import json
import os
import re
import shutil
import sys
from datetime import date


def tr(es, en):
    try:
        import json
        from pathlib import Path
        with (Path.home() / ".config/quickshell-rice.json").open(encoding="utf-8") as f:
            return en if json.load(f).get("language") == "en" else es
    except (OSError, ValueError, AttributeError):
        return es


CACHE = os.path.expanduser("~/.cache/wal/colors.json")
CONFIG = os.path.expanduser("~/.config")
BACKUPS = os.path.expanduser(f"~/.config-rice-backups/{date.today().isoformat()}")


# --- colour utilities --------------------------------------------------------

def rgb(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) / 255 for i in (0, 2, 4))


def hexa(t):
    return "#" + "".join(f"{max(0, min(255, round(c * 255))):02x}" for c in t)


def lum(h):
    """Relative luminance (WCAG), to decide light/dark and contrasts."""
    def lin(c):
        return c / 12.92 if c <= 0.03928 else ((c + 0.055) / 1.055) ** 2.4
    r, g, b = rgb(h)
    return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)


def contrast(a, b):
    la, lb = lum(a), lum(b)
    hi, lo = max(la, lb), min(la, lb)
    return (hi + 0.05) / (lo + 0.05)


def shade(h, amount):
    """Lightens (amount>0) or darkens (amount<0) by moving the L of HLS.

    It is done in HLS rather than by mixing with white/black so as not to wash
    out the tint: pywal backgrounds tend to be almost black with a tint from
    the image, and that tint is exactly what makes the window look as if it
    belongs to the same world as the desktop.
    """
    r, g, b = rgb(h)
    hh, ll, ss = colorsys.rgb_to_hls(r, g, b)
    ll = max(0.0, min(1.0, ll + amount))
    return hexa(colorsys.hls_to_rgb(hh, ll, ss))


def mix(a, b, t):
    """Linear mix: t=0 returns a, t=1 returns b."""
    ra, ga, ba = rgb(a)
    rb, gb, bb = rgb(b)
    return hexa((ra + (rb - ra) * t, ga + (gb - ga) * t, ba + (bb - ba) * t))


def legible(fondo, *candidatos):
    """The candidate that gives the most contrast against 'fondo'."""
    return max(candidatos, key=lambda c: contrast(fondo, c))


def semantico(base, fondo, tono, sat_min=0.45):
    """A status colour (error, success, warning) with the palette's tint.

    The three semantic colours cannot come from pywal as they are: with a blue
    wallpaper, color1 comes out blue and an error message in blue warns of
    nothing. It takes the palette's lightness and saturation -so it still
    belongs to this house- but forces the hue people already know how to read,
    and raises the lightness until it reads against the background.
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


# --- palette -----------------------------------------------------------------

def construir(wal):
    c = wal["colors"]
    esp = wal["special"]
    bg, fg = esp["background"], esp["foreground"]
    accent = c["color4"]
    oscuro = lum(bg) < 0.5
    # Sign of the relief: on a dark background surfaces rise, on a light one
    # they sink. Without this, a light wallpaper would leave buttons invisible.
    s = 1 if oscuro else -1

    p = {}
    p["window"] = bg
    p["windowtext"] = fg
    # Views (lists, text boxes) sink a touch relative to the window; buttons
    # rise. It is the same relief Fusion uses.
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
    # Selected text is chosen by measured contrast, not by eye: with dark
    # accents (a night blue) pywal's background on top did not read.
    p["highlightedtext"] = legible(accent, bg, fg, c["color15"], c["color0"])
    if contrast(accent, p["highlightedtext"]) < 4.5:
        # If the palette gives no colour that reads on the accent, white or
        # black: a selection you cannot read is worse than an outside colour.
        p["highlightedtext"] = legible(accent, "#ffffff", "#000000")
    p["link"] = c["color6"] if contrast(bg, c["color6"]) >= 3.5 else shade(accent, 0.15 * s)
    p["linkvisited"] = c["color5"] if contrast(bg, c["color5"]) >= 3.5 else shade(c["color5"], 0.15 * s)
    p["tooltipbase"] = shade(bg, 0.08 * s)
    p["tooltiptext"] = fg
    p["placeholder"] = mix(fg, bg, 0.55)
    p["accent"] = accent
    # Disabled: not just any grey, but the text itself moved towards the
    # background, which is what makes it read as "off" and not as "broken".
    p["disabledtext"] = mix(fg, bg, 0.62)
    p["border"] = shade(bg, 0.14 * s)
    return p


# --- output 1: qt5ct / qt6ct colour scheme ------------------------------------

# Order of QPalette::ColorRole as qt5ct/qt6ct serialise it: a list of
# comma-separated colours, by role index. The three groups (active, disabled,
# inactive) carry the whole list.
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
    # qt5ct/qt6ct expect #AARRGGBB
    return ", ".join("#ff" + v.lstrip("#").lower() for v in fuera)


def escribir_esquema(p, destino):
    os.makedirs(os.path.dirname(destino), exist_ok=True)
    texto = (
        "[ColorScheme]\n"
        "; Generated by qt-pywal.py from ~/.cache/wal/colors.json\n"
        "; Rewritten on each wallpaper change: do not edit by hand\n"
        f"active_colors={lista_colores(p, 'active')}\n"
        f"disabled_colors={lista_colores(p, 'disabled')}\n"
        f"inactive_colors={lista_colores(p, 'inactive')}\n"
    )
    escribir_en_sitio(destino, texto)


def asegurar_conf_ct(carpeta, esquema):
    """Leaves qt5ct.conf/qt6ct.conf pointing at the scheme, without trampling the rest.

    If the user has never opened qt5ct, the file does not exist and is created
    with the bare minimum. If it exists, only the three keys needed for the
    palette to apply are touched.
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
        # The file dialogs are still GTK's: it is what the rest of the desktop
        # uses, and the only piece of the gtk3 theme worth keeping when moving
        # to qt6ct.
        cuerpo += "standard_dialogs=gtk3\n"
        escribir_en_sitio(conf, cuerpo)
        return

    with open(conf, encoding="utf-8") as f:
        lineas = f.read().splitlines()
    salida, en_appearance, puestas = [], False, set()
    for linea in lineas:
        if linea.startswith("["):
            if en_appearance:
                # After the section's last key, not after the blank gap that
                # separates it from the next one.
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
    # The .conf is touched LAST and always, even if nothing changed: it is the
    # file the platform theme watches, and that touch is the "read the colours
    # again" signal for the applications that are already open.
    escribir_en_sitio(conf, "\n".join(salida) + "\n")


# --- output 2: kdeglobals ----------------------------------------------------

def grupos_kde(p):
    """The [Colors:*] and [WM] sections of kdeglobals with pywal's palette."""
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
    """The icon theme for Qt apps: the same one GTK uses.

    It is read from GTK3's settings.ini instead of being fixed here so that
    both halves of the desktop show the same icon. With breeze-dark, a kdialog
    showed KDE's blue circle -a fixed blue, foreign to pywal- where the rest of
    the desktop shows Adwaita's.
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
    # Everything that is not colour is kept (fonts, KFileDialog, icons...) and
    # the colour sections are replaced whole, so the old palette is not left
    # mixed with the new one.
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
            # The icon theme is always rewritten with GTK's: it pointed to
            # 'breeze-plus-dark', which left with the old metapackages and left
            # KDE apps without icons, and with breeze-dark they showed KDE's
            # fixed blue where the rest of the desktop shows Adwaita.
            if re.match(r"Theme\s*=", linea):
                continue
        fuera.append(linea)

    texto = "\n".join(fuera).strip("\n")

    def anadir_a_seccion(txt, nombre, pares):
        """Puts keys inside an existing section, or creates it at the end."""
        marca = f"[{nombre}]"
        if marca in txt:
            partes = txt.split(marca, 1)
            resto = partes[1].lstrip("\n")
            if resto.startswith("["):  # empty section: keep them from sticking together
                resto = "\n" + resto
            return partes[0] + marca + "\n" + "".join(f"{k}={v}\n" for k, v in pares.items()) + resto
        return txt + f"\n\n{marca}\n" + "".join(f"{k}={v}\n" for k, v in pares.items())

    texto = anadir_a_seccion(texto, "General", {"ColorScheme": "Pywal"})
    texto = anadir_a_seccion(texto, "Icons", {"Theme": primer_tema_de_iconos()})
    # The style pointed to 'Darkly', which is not installed: any KDE app fell
    # back to the default style and, with it, the stock palette.
    texto = anadir_a_seccion(texto, "KDE", {"widgetStyle": "Fusion"})

    bloques = []
    for nombre, pares in nuevas.items():
        bloques.append(f"[{nombre}]\n" + "".join(f"{k}={v}\n" for k, v in pares.items()))
    # KDE's effects for inactive/disabled windows: left as they were except for
    # the base colour, which was the old scheme's lilac.
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
    # [WM] holds the window frame colours; here Hyprland decorates windows, but
    # some KDE apps use them for their own title bar.
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
    # On the same inode, and for two reasons. One, so the open KDE apps notice,
    # just as with the qt5ct/qt6ct .conf files. And two, the important one:
    # with install.sh --link, ~/.config/kdeglobals IS a link into the repo, and
    # writing with temp file + rename REPLACES the link with a standalone file
    # -- the dotfile gets disconnected, silently.
    escribir_en_sitio(ruta, texto)


# --- plumbing ----------------------------------------------------------------

def respaldo(ruta):
    os.makedirs(BACKUPS, exist_ok=True)
    destino = os.path.join(BACKUPS, os.path.basename(ruta) + ".pre-qt-pywal")
    if not os.path.exists(destino):
        shutil.copy2(ruta, destino)


def escribir_en_sitio(ruta, texto, modo=0o644):
    """Writes keeping the inode, instead of creating and renaming.

    It is what makes the Qt applications that are already open change colour
    without restarting them. The qt5ct/qt6ct platform theme watches its config
    file with QFileSystemWatcher, and a QFileSystemWatcher follows the INODE:
    as soon as you write with the usual temp file + os.replace trick, the watch
    is left looking at a file that no longer exists and never fires again.
    Measured with VLC in front: with an atomic write the colour did not move;
    writing to the same inode it changes within three seconds.
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
        print(tr(f"qt-pywal: no se pudo leer {CACHE}: {e}", f"qt-pywal: could not read {CACHE}: {e}"), file=sys.stderr)
        return 1

    p = construir(wal)
    c = wal["colors"]
    bg = wal["special"]["background"]
    # Error in red, success in green, warning in amber: the hue is fixed, the
    # lightness and saturation come from the wallpaper's palette.
    p["negative"] = semantico(c["color1"], bg, 0.00)
    p["positive"] = semantico(c["color2"], bg, 0.33)
    p["neutral"] = semantico(c["color3"], bg, 0.10)

    hechos = []
    for nombre in ("qt5ct", "qt6ct"):
        # Only generated for the ones that are installed: if they are not, their
        # files would be junk that nobody reads.
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
