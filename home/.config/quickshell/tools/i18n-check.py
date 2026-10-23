#!/usr/bin/env python3
"""Checks the shell's language layer.

    ./tools/i18n-check.py            everything
    ./tools/i18n-check.py --faltan   only what has no translation

Four things, which are the four ways of breaking this:

  1. strings wrapped in I18n.tr() that are not in translations-en.js
     -> they would come out in Spanish with the shell in English;
  2. dictionary entries that nobody uses any more
     -> rubbish that outlives a text change and misleads the next person;
  3. {0} {1} {2} placeholders lost or invented in the translation
     -> the number, the name or the percentage vanishes from the sentence;
  4. visible literals (text/label/hint/title/...) still NOT wrapped
     -> the bit of interface that was forgotten.

Exit 0 if everything is fine, 1 if there is something to look at.
"""
import ast
import os
import re
import sys

AQUI = os.path.dirname(os.path.abspath(__file__))
SHELL = os.path.dirname(AQUI)

# Properties whose value ends up on screen. `icon` and `value` are not here:
# the first holds glyphs and the second is nearly always data, not a sentence.
VISIBLES = ("text", "label", "hint", "title", "note", "body", "placeholderText",
            "actionText", "subtitle", "description", "tooltip")

# Strings that are NOT translated on purpose. Each carries its reason because
# in a year nobody will remember, and without this the check always comes out
# with five false complaints and ends up with nobody looking at it.
A_PROPOSITO = {
    ("I18n.qml", "Español"):
        "the language is shown in its own language so it can be found",
    ("I18n.qml", "English"):
        "same as above",
    ("SettingsWindow.qml", "Ajustes"):
        "the window title matched by the hyprland.lua window rule "
        "(title = ^(Ajustes)$) and SettingsWindow focus: translating it leaves the "
        "window tiled and unfocused",
    ("SettingsWindow.qml", "Notch"):
        "the section is called the same in both languages",
}

# What looks like a sentence but is not one. If a string matches this, it is
# not reported as missing a translation.
NO_ES_TEXTO = re.compile(r"""
      ^\s*$                     # empty
    | ^[\W\d_]+$                # only symbols, glyphs or numbers
    | ^[~/.]                    # paths: ~/.config/..., ./something, /etc/...
    | ^[a-z0-9_-]+$             # bare identifiers: "network", "wifi-off"
    | ^\#[0-9a-fA-F]{3,8}$      # colours (the \# is required: in VERBOSE mode
                                # a bare hash opens a comment and eats the
                                # rest of the alternative)
    | ^[A-Z][a-z]+\ [A-Z]       # font names: "Adwaita Sans"
    | ^\{                       # just a placeholder
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
    """Keys that do NOT appear as I18n.tr("literal") in any .qml.

    Right now they are the shortcut descriptions: SettingsShortcuts reads the
    comments on the `bind =` lines of hyprland.conf and passes them through
    I18n.tr(comment), with the variable inside. Without this the check would
    take them for dead entries and someone would end up deleting them.
    """
    # FIRST the hyprland.conf sitting next to this script, and only if it does
    # not exist, the one in $HOME. The other way round —which is how it was—
    # checking the repo before installing read the OLD config of the live system:
    # shortcuts you had just added showed up as dead entries and the ones you
    # removed went unseen.
    conf = os.path.join(os.path.dirname(os.path.dirname(SHELL)),
                        "hypr", "hyprland.conf")
    if not os.path.exists(conf):
        conf = os.path.expanduser("~/.config/hypr/hyprland.conf")
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


def claves_del_equipo():
    """Keys the pokémon team panel passes through I18n.tr(value).

    The nature, badge and rank of the save are Spanish names that come from
    the engine's JSON, so they never show up as a literal in any .qml. They are
    read from the engine's own lists -NATURALEZAS, MEDALLAS and RANGOS- with
    ast, without running it, and in the same order as hyprland.conf above: the
    repo copy first, the installed one only if that is missing.
    """
    motor = os.path.join(os.path.dirname(os.path.dirname(SHELL)),
                         ".local", "bin", "poke-team")
    if not os.path.exists(motor):
        motor = os.path.expanduser("~/.local/bin/poke-team")
    fuera = set()
    if not os.path.exists(motor):
        return fuera
    with open(motor, encoding="utf-8") as f:
        arbol = ast.parse(f.read())
    for nodo in arbol.body:
        if not (isinstance(nodo, ast.Assign) and len(nodo.targets) == 1
                and isinstance(nodo.targets[0], ast.Name)):
            continue
        nombre = nodo.targets[0].id
        try:
            valor = ast.literal_eval(nodo.value)
        except ValueError:
            continue
        if nombre == "NATURALEZAS":
            fuera.update(valor)
        elif nombre in ("MEDALLAS", "RANGOS"):
            fuera.update(n for _, n in valor)
    return fuera


def claves_de_pantallas():
    """The errors scripts/monitors.py sends to Settings > Screens.

    Displays.qml shows them through I18n.tr(message), so, like the team's
    names, they never appear as a literal in a .qml. These are the string
    literals given to ValueError() or to a message= keyword in that script.
    """
    fuera = set()
    ruta = os.path.join(SHELL, "scripts", "monitors.py")
    if not os.path.exists(ruta):
        return fuera
    with open(ruta, encoding="utf-8") as f:
        arbol = ast.parse(f.read())
    for nodo in ast.walk(arbol):
        if not isinstance(nodo, ast.Call):
            continue
        func = nodo.func
        nombre = func.id if isinstance(func, ast.Name) else getattr(func, "attr", "")
        candidatos = []
        if nombre == "ValueError" and nodo.args:
            candidatos.append(nodo.args[0])
        for kw in nodo.keywords:
            if kw.arg == "message":
                v = kw.value
                candidatos += [v.body, v.orelse] if isinstance(v, ast.IfExp) else [v]
        for c in candidatos:
            if isinstance(c, ast.Constant) and isinstance(c.value, str) and c.value:
                fuera.add(c.value)
    return fuera


def diccionario():
    """The entries of translations-en.js, without evaluating JavaScript."""
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

    usadas = {}       # string -> files where it is used
    sin_envolver = {}  # file -> [strings]

    for nombre, ruta in qmls():
        with open(ruta, encoding="utf-8") as f:
            texto = f.read()
        for m in RE_TR.finditer(texto):
            usadas.setdefault(m.group(1), set()).add(nombre)
        # a visible literal that does NOT sit inside an I18n.tr(
        for m in RE_VIS.finditer(texto):
            crudo = m.group(2)
            # A GlobalShortcut's description is not seen in the shell, only in
            # `hyprctl globalshortcuts`, and Quickshell freezes it at creation:
            # an I18n.tr() there only buys a warning per shortcut on every start
            # (see the note above them in TopShell.qml). They are written in
            # English, like everything else the compositor lists.
            obj = texto.rfind("GlobalShortcut", 0, m.start())
            if m.group(1) == "description" and obj >= 0 \
                    and "}" not in texto[obj:m.start()]:
                continue
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
    for s in claves_del_equipo():
        usadas.setdefault(s, set()).add("poke-team")
    for s in claves_de_pantallas():
        usadas.setdefault(s, set()).add("monitors.py")

    faltan = sorted(s for s in usadas if s not in dic)
    muertas = sorted(k for k in dic if k not in usadas)
    huecos = []
    for clave, valor in dic.items():
        if sorted(RE_HUECO.findall(clave)) != sorted(RE_HUECO.findall(valor)):
            huecos.append(clave)

    print(f"  {len(usadas)} wrapped strings · {len(dic)} translated")

    if faltan:
        print(f"\n  UNTRANSLATED ({len(faltan)}) — would appear in Spanish:")
        for s in faltan:
            print(f'    {sorted(usadas[s])[0]:24} "{s}"')
    if solo_faltan:
        return 1 if faltan else 0

    if huecos:
        print(f"\n  MISMATCHED PLACEHOLDERS ({len(huecos)}):")
        for s in sorted(huecos):
            print(f'    "{s}"\n      -> "{dic[s]}"')
    if dobles:
        print(f"\n  DUPLICATE KEYS ({len(dobles)}):")
        for s in sorted(set(dobles)):
            print(f'    "{s}"')
    if muertas:
        print(f"\n  UNUSED ENTRIES ({len(muertas)}) — no longer referenced:")
        for s in muertas:
            print(f'    "{s}"')
    if sin_envolver:
        total = sum(len(v) for v in sin_envolver.values())
        print(f"\n  UNWRAPPED VISIBLE STRINGS ({total}):")
        for nombre in sorted(sin_envolver):
            for s in sin_envolver[nombre]:
                print(f'    {nombre:24} "{s}"')

    mal = bool(faltan or huecos or dobles or sin_envolver)
    print("\n  all in order" if not mal else "")
    return 1 if mal else 0


if __name__ == "__main__":
    sys.exit(main())
