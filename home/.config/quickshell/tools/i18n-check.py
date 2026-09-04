#!/usr/bin/env python3
"""Repasa la capa de idioma del shell.

    ./tools/i18n-check.py            todo
    ./tools/i18n-check.py --faltan   solo lo que no tiene traducción

Cuatro cosas, que son las cuatro formas de romper esto:

  1. cadenas envueltas en I18n.tr() que no están en translations-en.js
     -> saldrían en castellano con el shell en inglés;
  2. entradas del diccionario que ya no usa nadie
     -> basura que sobrevive a un cambio de texto y despista al siguiente;
  3. huecos {0} {1} {2} que se pierden o se inventan en la traducción
     -> el número, el nombre o el porcentaje desaparecen de la frase;
  4. literales visibles (text/label/hint/title/...) que siguen SIN envolver
     -> el trozo de interfaz que se olvidó.

Salida 0 si está todo bien, 1 si hay algo que mirar.
"""
import os
import re
import sys

AQUI = os.path.dirname(os.path.abspath(__file__))
SHELL = os.path.dirname(AQUI)

# Propiedades cuyo valor acaba en pantalla. `icon` y `value` no están: la
# primera son glifos y la segunda casi siempre es un dato, no una frase.
VISIBLES = ("text", "label", "hint", "title", "note", "body", "placeholderText",
            "actionText", "subtitle", "description", "tooltip")

# Cadenas que NO se traducen a propósito. Van con su motivo porque en un año
# nadie se acordará, y sin esto el repaso sale siempre con cinco quejas falsas
# y acaba no mirándolo nadie.
A_PROPOSITO = {
    ("I18n.qml", "Español"):
        "el idioma se ofrece en su propio idioma, para poder encontrarlo",
    ("I18n.qml", "English"):
        "igual que el anterior",
    ("SettingsWindow.qml", "Ajustes"):
        "es el título de ventana con el que casa la windowrule de hyprland.lua "
        "(title = ^(Ajustes)$) y el focus de SettingsWindow: traducirlo deja la "
        "ventana sin flotar y sin foco",
    ("MediaControls.qml", "Toggle media controls"):
        "description de un GlobalShortcut: no se ve en el shell, solo en "
        "hyprctl globalshortcuts, y ya está en inglés",
    ("WallpaperPicker.qml", "Wallpaper picker"):
        "igual que el anterior",
}

# Lo que parece una frase pero no lo es. Si una cadena casa con esto, no se
# reclama que falte por traducir.
NO_ES_TEXTO = re.compile(r"""
      ^\s*$                     # vacía
    | ^[\W\d_]+$                # solo símbolos, glifos o números
    | ^[~/.]                    # rutas: ~/.config/..., ./algo, /etc/...
    | ^[a-z0-9_-]+$             # identificadores sueltos: "network", "wifi-off"
    | ^\#[0-9a-fA-F]{3,8}$      # colores (el \# es obligatorio: en modo VERBOSE
                                # una almohadilla suelta abre un comentario y se
                                # come el resto de la alternativa)
    | ^[A-Z][a-z]+\ [A-Z]       # nombres propios de fuente: "Adwaita Sans"
    | ^\{                       # solo un hueco
""", re.VERBOSE)

RE_TR = re.compile(r'I18n\.tr\(\s*"((?:[^"\\]|\\.)*)"')
RE_VIS = re.compile(
    r'\b(' + "|".join(VISIBLES) + r')\s*:\s*"((?:[^"\\]|\\.)*)"')
RE_ENTRADA = re.compile(r'^\s*"((?:[^"\\]|\\.)*)"\s*:\s*"((?:[^"\\]|\\.)*)"\s*,?\s*$')
RE_HUECO = re.compile(r"\{[012]\}")


def qmls():
    for nombre in sorted(os.listdir(SHELL)):
        if nombre.endswith(".qml"):
            yield nombre, os.path.join(SHELL, nombre)


def claves_dinamicas():
    """Claves que NO aparecen como I18n.tr("literal") en ningún .qml.

    Ahora mismo son las descripciones de los atajos: SettingsShortcuts lee los
    comentarios de las líneas `bind =` de hyprland.conf y los pasa por
    I18n.tr(comment), con la variable dentro. Sin esto el repaso las daría por
    entradas muertas y alguien acabaría borrándolas.
    """
    conf = os.path.expanduser("~/.config/hypr/hyprland.conf")
    if not os.path.exists(conf):
        conf = os.path.join(os.path.dirname(os.path.dirname(SHELL)),
                            "hypr", "hyprland.conf")
    fuera = set()
    if not os.path.exists(conf):
        return fuera
    with open(conf, encoding="utf-8") as f:
        for linea in f:
            m = re.match(r'^\s*bind[a-z]*\s*=\s*(.+)$', linea.strip())
            if not m:
                continue
            resto = m.group(1)
            i = resto.find("#")
            if i >= 0 and resto[i + 1:].strip():
                fuera.add(resto[i + 1:].strip())
    return fuera


def diccionario():
    """Las entradas de translations-en.js, sin evaluar JavaScript."""
    ruta = os.path.join(SHELL, "translations-en.js")
    dic, dobles = {}, []
    dentro = False
    with open(ruta, encoding="utf-8") as f:
        for linea in f:
            if linea.strip().startswith("var en"):
                dentro = True
                continue
            if not dentro:
                continue
            if linea.strip().startswith("};"):
                break
            m = RE_ENTRADA.match(linea)
            if m:
                clave, valor = m.group(1), m.group(2)
                if clave in dic:
                    dobles.append(clave)
                dic[clave] = valor
    return dic, dobles


def main():
    solo_faltan = "--faltan" in sys.argv
    dic, dobles = diccionario()

    usadas = {}       # cadena -> ficheros donde se usa
    sin_envolver = {}  # fichero -> [cadenas]

    for nombre, ruta in qmls():
        with open(ruta, encoding="utf-8") as f:
            texto = f.read()
        for m in RE_TR.finditer(texto):
            usadas.setdefault(m.group(1), set()).add(nombre)
        # un literal visible que NO va dentro de un I18n.tr(
        for m in RE_VIS.finditer(texto):
            crudo = m.group(2)
            antes = texto[max(0, m.start() - 40):m.start(2)]
            if "I18n.tr(" in antes[-30:]:
                continue
            if NO_ES_TEXTO.search(crudo):
                continue
            if (nombre, crudo) in A_PROPOSITO:
                continue
            sin_envolver.setdefault(nombre, []).append(crudo)

    dinamicas = claves_dinamicas()
    for s in dinamicas:
        usadas.setdefault(s, set()).add("hyprland.conf")

    faltan = sorted(s for s in usadas if s not in dic)
    muertas = sorted(k for k in dic if k not in usadas)
    huecos = []
    for clave, valor in dic.items():
        if sorted(RE_HUECO.findall(clave)) != sorted(RE_HUECO.findall(valor)):
            huecos.append(clave)

    print(f"  {len(usadas)} cadenas envueltas · {len(dic)} traducidas")

    if faltan:
        print(f"\n  SIN TRADUCIR ({len(faltan)}) — saldrían en castellano:")
        for s in faltan:
            print(f'    {sorted(usadas[s])[0]:24} "{s}"')
    if solo_faltan:
        return 1 if faltan else 0

    if huecos:
        print(f"\n  HUECOS QUE NO CUADRAN ({len(huecos)}):")
        for s in sorted(huecos):
            print(f'    "{s}"\n      -> "{dic[s]}"')
    if dobles:
        print(f"\n  CLAVES REPETIDAS ({len(dobles)}):")
        for s in sorted(set(dobles)):
            print(f'    "{s}"')
    if muertas:
        print(f"\n  ENTRADAS MUERTAS ({len(muertas)}) — ya no las usa nadie:")
        for s in muertas:
            print(f'    "{s}"')
    if sin_envolver:
        total = sum(len(v) for v in sin_envolver.values())
        print(f"\n  LITERALES VISIBLES SIN ENVOLVER ({total}):")
        for nombre in sorted(sin_envolver):
            for s in sin_envolver[nombre]:
                print(f'    {nombre:24} "{s}"')

    mal = bool(faltan or huecos or dobles or sin_envolver)
    print("\n  todo en orden" if not mal else "")
    return 1 if mal else 0


if __name__ == "__main__":
    sys.exit(main())
