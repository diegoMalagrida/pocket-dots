// PokeTeamPanel.qml — the pokemon team, unfolded FROM the notch.
//
// Six pokemon that level up with your GitHub commits. The idea comes from
// Impasto's pets (https://github.com/andreumassanet/impasto, GPL-3.0); the
// difference is where the experience comes from: there they earn it by
// letting themselves be looked after, here by working.
//
// Nothing about the game is decided HERE. Levels, experience sharing,
// evolutions, natures, badges and box are handled by ~/.local/bin/poke-team,
// and this panel only paints its JSON and sends it orders through ShellState.
//
// ABOUT THE FINISH, which is what was wrong in the first version:
//
//   · The row is laid out in FIXED-WIDTH COLUMNS, like GithubPanel's commit
//     list. With loose widths, the level landed in a different place on each
//     row and the whole thing read as an improvised list.
//   · The actions have their slot RESERVED even when invisible: if they
//     appeared on hover, the row would jump under the cursor.
//   · The bar is the SAME as the notch slider's (height 6, radius 3,
//     track #242424). It used to be a 4 px line with the track in bgAlt, which
//     could not be seen over the panel's black: it looked like an underline
//     of the name.
//   · The buttons are PillButton, the house one, with its feel on press. I had
//     made up one of my own, 22 px, with none of that.
//   · The hierarchy is done with OPACITY (0.72 content, 0.35 metadata), as in
//     the rest of the panels, and not with different colours.
//
// THREE FACES, never two at once: the team, the pokedex to choose from and the
// box.
import Quickshell
import Quickshell.Io   // FileView, to read the pokedex from nombres.tsv
import QtQuick
import QtQuick.Layouts

Item {
    id: root

    readonly property bool active: ShellState.panel === "poke"
    readonly property var equipo: ShellState.pokeTeam.equipo || []
    readonly property var caja: ShellState.pokeTeam.caja || []
    readonly property int tamano: ShellState.pokeTeam.tamano || 6

    // "equipo" | "pokedex" | "caja"
    property string cara: "equipo"
    property string busqueda: ""

    // The row's columns, in one single place: changing them here moves them all
    // at once and they keep lining up.
    readonly property int colSprite: 42
    // The name used to measure "whatever was left" (fillWidth) and 240 px were
    // left, so it pushed the level and the bar to the far end of the panel: the
    // name at the very left, its progress 200 px away and a hole in the middle.
    // They read as two different tables placed side by side.
    // With a FIXED width, identity and progress go together and the columns also
    // keep lining up between rows -- which is exactly what is lost if the name
    // measures what its text takes up.
    // 124 and not 150: the two longest names in the pokedex ("Crabominable",
    // "Fletchinder") fit, and every pixel taken away here goes to the gap at the
    // end, i.e. it brings the level and the bar closer to the name.
    // The extra width goes ENTIRELY to the bar, and the name stays at its 124.
    // I tried sharing it out and it is worse: the gap between the name and the
    // level is `colNombre minus whatever the text measures`, so widening that
    // column opens exactly the hole that was closed by fixing it. The bar, on the
    // other hand, stretches without leaving a gap because what grows is the
    // drawing.
    readonly property int anchoUtil: root.width - 42       // the 21 on each side
    readonly property int sobra: Math.max(0, root.anchoUtil - 538)
    readonly property int colNombre: 124
    readonly property int colNivel: 46
    // The bar eats the gap that was left in the middle of the row instead of
    // leaving it empty. 538 usable px (580 minus the 21 on each side) minus the
    // other four columns and their gaps leave 210; it gets 196 and the other 14
    // stay as air before the actions. Incidentally, a long bar tells the progress
    // much better than an 88 px stub.
    readonly property int colBarra: 196 + root.sobra
    readonly property int colAcciones: 76

    // House opacities (the same as GithubPanel): content at 0.72, metadata at
    // 0.35. The hierarchy is done with opacity, not with a different colour for
    // each thing.
    // The house scale, exactly as it comes out of GithubPanel: six steps with one
    // role each, and Colors.fg RESERVED for what is active or under the mouse.
    // Colors.dim is not used here: it does not appear even once in its panels.
    readonly property color cTexto: Qt.rgba(Colors.fg.r, Colors.fg.g, Colors.fg.b, 0.72)  // body
    readonly property color cMedio: Qt.rgba(Colors.fg.r, Colors.fg.g, Colors.fg.b, 0.45)  // summary
    readonly property color cTenue: Qt.rgba(Colors.fg.r, Colors.fg.g, Colors.fg.b, 0.35)  // metadata
    readonly property color cDeco:  Qt.rgba(Colors.fg.r, Colors.fg.g, Colors.fg.b, 0.30)  // decoration
    readonly property color cLinea: Qt.rgba(Colors.fg.r, Colors.fg.g, Colors.fg.b, 0.07)  // separator
    readonly property color cRiel:  Qt.rgba(Colors.fg.r, Colors.fg.g, Colors.fg.b, 0.12)  // meter track

    // THE SHARED LINE. At rest it summarises the trainer; when you point at a row
    // it tells you about THAT row. It is the GitHub panel's pattern, which with
    // the same line says the streak or the day you point at, and it is there for
    // a reason: a floating bubble covers exactly what you are looking at, and a
    // line that appears moves everything below it. Here the line always exists
    // and only the text changes.
    property string detalle: ""

    // ── drag to reorder ─────────────────────────────────────────────────────
    // Which row you are holding and where it would land if you let go now. They
    // live in the panel and not in the row because the OTHER rows need them too:
    // they are the ones that move aside to open the gap. -1 = no drag.
    //
    // While you drag nothing is really reordered: the team only changes when you
    // let go, with an order to poke-team. Reordering live would force the model
    // to be rebuilt on every pixel and the delegates would be reconstructed under
    // your finger.
    property int arrastreDe: -1
    property int arrastreA: -1
    readonly property int filaH: 44

    onActiveChanged: {
        if (root.active) {
            root.cara = "equipo";
            root.busqueda = "";
            ShellState.pokeTeamRefresh();
        }
    }

    // ── the pokedex, for the picking face ───────────────────────────────────
    // It is read from the same file poke-team uses, so the two always talk
    // about the same pokedex and there is no duplicated list in QML.
    property var pokedex: []
    FileView {
        id: nombresFile
        path: Quickshell.env("HOME") + "/.cache/pokepalette/nombres.tsv"
        watchChanges: true
        onFileChanged: reload()
        printErrors: false
        onLoaded: {
            const fuera = [];
            for (const linea of nombresFile.text().split("\n")) {
                const trozos = linea.split("\t");
                const num = parseInt(trozos[0]);
                if (trozos.length >= 2 && !isNaN(num) && trozos[1])
                    fuera.push({ num: num, nombre: trozos[1] });
            }
            root.pokedex = fuera;
        }
    }

    // The Spanish goes in its own file (poke-names downloads it) because
    // nombres.tsv is already read by four places that split on the first tab.
    property var pokedexEs: ({})
    FileView {
        id: nombresEsFile
        path: Quickshell.env("HOME") + "/.cache/pokepalette/nombres-es.tsv"
        watchChanges: true
        onFileChanged: reload()
        printErrors: false
        onLoaded: {
            const fuera = {};
            for (const linea of nombresEsFile.text().split("\n")) {
                const trozos = linea.split("\t");
                const num = parseInt(trozos[0]);
                if (trozos.length >= 2 && !isNaN(num) && trozos[1])
                    fuera[num] = trozos[1];
            }
            root.pokedexEs = fuera;
        }
    }

    function nombreDe(p) {
        return I18n.english ? ShellState.pokeTitulo(p.nombre)
                            : root.pokedexEs[p.num] || root.mayus(p.nombre);
    }

    // ── the types, to filter the pokedex ────────────────────────────────────
    // From the SAME file poke-team uses to say what each critter is, so the
    // two always talk about the same pokedex. It brings all 1025 and already
    // comes in the series' order (normal, fighting, flying...), which is what
    // anyone who has played expects: reordering it alphabetically would be
    // "correcting" something that is not wrong.
    property var tipos: ({ es: {}, pokemon: {} })
    FileView {
        id: tiposFile
        path: Quickshell.env("HOME") + "/.cache/pokepalette/tipos.json"
        watchChanges: true
        onFileChanged: reload()
        printErrors: false
        onLoaded: {
            try {
                root.tipos = JSON.parse(tiposFile.text());
            } catch (e) {
                // Same as with the team: with garbage, better what we had before
                // than leaving the type row empty.
            }
        }
    }
    readonly property var tiposOrden: Object.keys(root.tipos.es || {})

    // ── the colour of each type ─────────────────────────────────────────────
    // The series' eighteen colours come in the same JSON and until now they sat
    // there untouched, on purpose: "they are a FOREIGN palette and a widget that
    // brings its own looks stuck on top, not inside". The objection was good, but
    // it was aimed at the wrong thing. What clashes is not the HUE -- that Fire is
    // red and Grass green is read without thinking by anyone who has played, and
    // it is real information when you have 1025 critters in front of you -- but
    // that each colour also brings its own BRIGHTNESS. Used as they are, Ghost
    // (#705898) sinks into the background and Electric (#F7D02C) screams; together
    // in a row they look like eighteen stickers from different sources.
    //
    // So the work is shared out: the series sets the hue, the house sets the
    // weight. All of them are brought to the same lightness -- the one needed to
    // read over THIS background, which changes with pywal -- and to a minimum
    // saturation. They are still the usual colours and they all weigh the same.
    // The normalisation lives in Colors.typeInk: it shares it with the Control
    // Centre strip, which used to paint the same type with the raw hex.
    function tintaTipo(clave) {
        const base = (root.tipos.colores || {})[clave];
        return base ? Colors.typeInk(base) : root.cMedio;
    }

    // The same colour, for the background of a pill: the hue is just as
    // recognisable and it does not compete with the text on top of it.
    function velo(c, a) {
        return Qt.rgba(c.r, c.g, c.b, a);
    }

    // What type each pokemon in the grid is. It is looked up 1025 times when the
    // filter opens, so it comes from the table already loaded and not from
    // walking through anything.
    function tiposDe(num) {
        return (root.tipos.pokemon || ({}))[num] || [];
    }

    // "" = all. It is the grid's filter, separate from the search box text:
    // the two add up, so you can ask for "the fire ones starting with
    // char".
    property string tipoFiltro: ""

    // Who is already in the team or in the box. They are NOT removed from the
    // grid: they are dimmed. Taking them out left the pokedex with holes and the
    // number sequence skipped -- it read as a broken list instead of a pokedex.
    readonly property var yaTengo: {
        const dentro = {};
        for (const m of root.equipo)
            dentro[m.num] = true;
        for (const m of root.caja)
            dentro[m.num] = true;
        return dentro;
    }

    readonly property var filtrados: {
        const q = root.busqueda.trim().toLowerCase();
        const t = root.tipoFiltro;
        const deTipo = root.tipos.pokemon || ({});
        const fuera = [];
        for (const p of root.pokedex) {
            // The type first, which discards 90% in one go and is cheaper than
            // comparing two names. The JSON keys are strings ("4") and p.num is a
            // number, but in JS indexing with a number already converts, so
            // String(p.num) is not needed.
            if (t && (deTipo[p.num] || []).indexOf(t) < 0)
                continue;
            // It searches by the English name AND by the Spanish one: the grid
            // shows the Spanish, so filtering only by the English would be
            // asking the user to type something they are not seeing.
            if (q) {
                const es = (root.pokedexEs[p.num] || "").toLowerCase();
                if (p.nombre.indexOf(q) !== 0 && es.indexOf(q) !== 0
                    && String(p.num) !== q)
                    continue;
            }
            fuera.push(p);
        }
        // No cap: all 1025 are there and you scroll down with the wheel. There
        // was a cut-off at 60 "because the grid cannot take more", and it was
        // false -- GridView only builds the visible cells, so all the cap
        // achieved was hiding the whole pokedex from Raichu onwards.
        return fuera;
    }

    function mayus(s) {
        return s && s.length ? s[0].toUpperCase() + s.slice(1) : "";
    }

    ColumnLayout {
        // The frame of its panels, measured in GithubPanel: 21 on the sides, 18
        // at the top and 16 at the bottom. And spacing 0 on purpose -- the
        // vertical rhythm is set by each child with its Layout.topMargin, which
        // is how rhythm is written in this house.
        anchors.fill: parent
        anchors.leftMargin: 21
        anchors.rightMargin: 21
        anchors.topMargin: 18
        anchors.bottomMargin: 16
        spacing: 0

        // ── header ──────────────────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            spacing: Appearance.gapM

            StyledText {
                text: root.cara === "pokedex" ? I18n.tr("Elegir Pokémon")
                    : root.cara === "caja" ? I18n.tr("Caja")
                    : I18n.tr("Equipo")
                font.family: Appearance.fontUI
                font.pixelSize: Appearance.fsL
            }

            Item { Layout.fillWidth: true }

            Pildora {
                visible: root.cara !== "equipo"
                rotulo: I18n.tr("Volver")
                onPulsada: { root.cara = "equipo"; root.busqueda = ""; }
            }
            Pildora {
                visible: root.cara === "equipo" && root.equipo.length < root.tamano
                rotulo: "+ " + I18n.tr("Añadir")
                onPulsada: root.cara = "pokedex"
            }
            Pildora {
                visible: root.cara === "equipo"
                rotulo: ShellState.pokeTeamLoading ? "…" : I18n.tr("Actualizar")
                onPulsada: ShellState.pokeTeamSync()
            }
        }

        // ── the shared line ─────────────────────────────────────────────────
        // At rest: who you are. Pointing at a row: who it is. Fixed height,
        // so nothing moves on hover.
        StyledText {
            visible: root.cara === "equipo"
            Layout.fillWidth: true
            Layout.topMargin: 9
            elide: Text.ElideRight
            text: {
                if (root.detalle)
                    return root.detalle;
                const g = ShellState.pokeTeam.github || {};
                const trozos = [];
                if (ShellState.pokeTeam.rango)
                    trozos.push(I18n.tr(ShellState.pokeTeam.rango));
                trozos.push((g.contadas || 0) + " " + I18n.tr("aportes"));
                if ((g.racha || 0) > 1)
                    trozos.push(I18n.tr("racha") + " " + g.racha
                                + " ×" + (1 + Math.min(g.racha, 10) / 10).toFixed(1));
                return trozos.join("  ·  ");
            }
            color: root.detalle ? Colors.fg : root.cMedio
            Behavior on color { ColorAnimation { duration: Appearance.mQuick; easing.type: Easing.OutQuad } }
            font.family: Appearance.fontUI
            font.pixelSize: Appearance.fsXS
        }

        // ── badges ──────────────────────────────────────────────────────────
        // Label + eight dots + how many to go. Without a label they were eight
        // little circles with no possible explanation.
        Rectangle {
            visible: root.cara === "equipo" && (ShellState.pokeTeam.medallas || []).length > 0
            Layout.fillWidth: true
            Layout.topMargin: 13
            implicitHeight: 1
            color: root.cLinea
        }

        RowLayout {
            visible: root.cara === "equipo" && (ShellState.pokeTeam.medallas || []).length > 0
            Layout.fillWidth: true
            Layout.topMargin: 11
            spacing: 9

            StyledText {
                text: I18n.tr("Medallas")
                color: root.cTenue
                font.family: Appearance.fontUI
                font.pixelSize: Appearance.fsXXS
            }

            Row {
                spacing: 5
                Repeater {
                    model: ShellState.pokeTeam.medallas || []
                    Item {
                        id: punto
                        required property var modelData
                        required property int index
                        width: 7
                        height: 7

                        // THE NEXT ONE STANDS OUT FROM THE ONES STILL MISSING.
                        //
                        // There used to be only two states -- earned or not -- and the
                        // seven pending ones were seven identical dots: the label on
                        // the right says which one you are going for, but the row did
                        // not point it out. The first one not yet earned is an accent
                        // ring, hollow: it reads as "this is the next one" without
                        // shouting as loud as one already won.
                        readonly property bool proxima: !modelData.ganada
                            && index === (ShellState.pokeTeam.medallas || []).findIndex(m => !m.ganada)

                        Rectangle {
                            anchors.fill: parent
                            radius: 999
                            color: punto.modelData.ganada ? Colors.accent
                                 : punto.proxima ? "transparent" : root.cLinea
                            border.width: punto.proxima ? 1 : 0
                            border.color: Qt.rgba(Colors.accent.r, Colors.accent.g, Colors.accent.b, 0.55)
                            Behavior on color { ColorAnimation { duration: Appearance.mQuick } }
                        }
                        MouseArea {
                            id: medallaMa
                            anchors.fill: parent
                            anchors.margins: -3
                            hoverEnabled: true
                            // to the line above, like everything else
                            onEntered: root.detalle = I18n.tr("Medalla {0}", I18n.tr(modelData.nombre))
                                       + "  ·  " + modelData.aportes + " " + I18n.tr("aportes")
                                       + (modelData.ganada ? "  ·  " + I18n.tr("ganada") : "")
                            onExited: root.detalle = ""
                        }
                    }
                }
            }

            StyledText {
                Layout.fillWidth: true
                text: {
                    const p = ShellState.pokeTeam.proxima_medalla;
                    return p ? "+" + p.faltan + " " + I18n.tr("para") + " " + I18n.tr(p.nombre) : "";
                }
                color: root.cTenue
                font.family: Appearance.fontUI
                font.pixelSize: Appearance.fsXXS
            }
        }

        // ── face 1: the team ────────────────────────────────────────────────
        ColumnLayout {
            visible: root.cara === "equipo"
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.topMargin: 10
            spacing: 0

            Repeater {
                model: root.equipo

                // Item outside and RowLayout inside, like the commit rows:
                // the MouseArea covering the whole row needs anchors, and a
                // direct child of a ColumnLayout cannot use them.
                Item {
                    id: fila
                    required property int index
                    required property var modelData

                    property bool eligiendoEvo: false
                    property bool renombrando: false

                    // How far the row you are holding has moved. The row's
                    // CONTENT is moved, never the row: the MouseArea has to stay
                    // still or mouse.y is measured against something that is
                    // moving, the drag feeds back on itself and the row shoots
                    // off.
                    property real arrastreY: 0
                    // Only on release. Animating the drag as well would put a
                    // delay between the hand and the row, which is exactly what
                    // makes a drag feel broken.
                    Behavior on arrastreY {
                        enabled: !filaMa.moviendo
                        NumberAnimation { duration: Appearance.mOut; easing.type: Easing.OutCubic }
                    }

                    // How far THIS row moves aside to open the gap where the one
                    // you are holding will land. It comes from (origin, target), so
                    // each row works it out on its own: there is no reordered list
                    // anywhere until you let go.
                    // No `readonly` on purpose, even though only its binding writes
                    // it: a Behavior needs to be able to write the property to
                    // animate it, and on a readonly one Qt rejects the whole file
                    // ("Invalid property assignment: apartado is a read-only
                    // property").
                    property real apartado: {
                        const de = root.arrastreDe, a = root.arrastreA;
                        if (de < 0 || fila.index === de)
                            return 0;
                        if (de < a && fila.index > de && fila.index <= a)
                            return -root.filaH;
                        if (de > a && fila.index >= a && fila.index < de)
                            return root.filaH;
                        return 0;
                    }
                    Behavior on apartado {
                        NumberAnimation { duration: Appearance.mOut; easing.type: Easing.OutCubic }
                    }

                    // The one you are holding is drawn above the others.
                    z: root.arrastreDe === fila.index ? 5 : 0

                    Layout.fillWidth: true
                    implicitHeight: root.filaH

                    Rectangle {
                        anchors.fill: parent
                        anchors.leftMargin: -Appearance.gapS
                        anchors.rightMargin: -Appearance.gapS
                        radius: Appearance.radS
                        // Held weighs more than pointed at: it is the only one in the
                        // list that is doing something.
                        color: root.arrastreDe === fila.index
                               ? Qt.rgba(Colors.fg.r, Colors.fg.g, Colors.fg.b, 0.10)
                               : filaMa.containsMouse
                               ? Qt.rgba(Colors.fg.r, Colors.fg.g, Colors.fg.b, 0.05)
                               : "transparent"
                        Behavior on color { ColorAnimation { duration: Appearance.mQuick } }
                        transform: Translate { y: fila.arrastreY + fila.apartado }
                    }

                    MouseArea {
                        id: filaMa
                        anchors.fill: parent
                        hoverEnabled: true
                        // The open hand says "this can be picked up", which is now
                        // true of every row -- including the leader's, which cannot
                        // be clicked for anything but can be dragged.
                        cursorShape: filaMa.moviendo ? Qt.ClosedHandCursor : Qt.OpenHandCursor

                        // Where it was pressed and whether that has turned into a drag.
                        property real origenY: 0
                        property bool moviendo: false

                        onPressed: function (mouse) {
                            filaMa.origenY = mouse.y;
                            filaMa.moviendo = false;
                        }

                        onPositionChanged: function (mouse) {
                            if (!filaMa.pressed || fila.renombrando)
                                return;
                            const dy = mouse.y - filaMa.origenY;
                            // 6 px threshold. Without it, the hand's tremor when
                            // clicking to set the leader would start a drag and
                            // the row would jump on every click.
                            if (!filaMa.moviendo && Math.abs(dy) < 6)
                                return;
                            filaMa.moviendo = true;
                            fila.arrastreY = dy;
                            root.arrastreDe = fila.index;
                            // Half a row of travel already counts as one slot,
                            // which is what `round` does: on passing the midpoint
                            // of the neighbour, the gap opens there.
                            const salto = Math.round(dy / root.filaH);
                            root.arrastreA = Math.max(0, Math.min(root.equipo.length - 1,
                                                                  fila.index + salto));
                        }

                        onReleased: {
                            if (filaMa.moviendo) {
                                if (root.arrastreA !== fila.index)
                                    ShellState.pokeOrden(["mover", String(fila.index),
                                                          String(root.arrastreA)]);
                            } else if (fila.index !== 0) {
                                // Without a drag it is still the usual thing:
                                // clicking a row makes it the leader, which is who
                                // takes the bulk of the experience and who walks
                                // around the screen.
                                ShellState.pokeLiderA(fila.index);
                            }
                            fila.soltar();
                        }
                        // If the panel closes mid-drag, the grab is lost
                        // without going through onReleased and the row would stay
                        // displaced and the gap open forever.
                        onCanceled: fila.soltar()

                        // This row's details go to the line above, not
                        // to a bubble on top of it.
                        onEntered: root.detalle = fila.resumen()
                        onExited: if (root.detalle === fila.resumen()) root.detalle = ""
                    }

                    function soltar(): void {
                        filaMa.moviendo = false;
                        fila.arrastreY = 0;
                        root.arrastreDe = -1;
                        root.arrastreA = -1;
                    }

                    function resumen() {
                        const m = fila.modelData;
                        const trozos = [m.mote || ShellState.pokeEspecie(m.especie, m.especie_es)];
                        const tipos = (m.tipos || []).map(x => ShellState.pokeTipo(x.id, x.es)).join(" · ");
                        if (tipos)
                            trozos.push(tipos);
                        // The reason for the hollow star, on the same line
                        // that already tells the rest of the row: there is no need
                        // for a separate bubble for one sentence.
                        if (m.shiny === true && m.shiny_listo === false)
                            trozos.push(I18n.tr("variocolor: aún pasea con los colores normales"));
                        if (m.naturaleza)
                            trozos.push(I18n.tr(m.naturaleza)
                                        + (m.naturaleza_mult !== 1 ? " ×" + m.naturaleza_mult : ""));
                        if (m.nivel < 100)
                            trozos.push(m.xp + "/" + m.umbral + " " + I18n.tr("exp"));
                        else
                            trozos.push(I18n.tr("al tope"));

                        // WHAT IT EVOLVES INTO AND WHEN.
                        //
                        // The data already came in the JSON and was not painted
                        // anywhere: the button only appeared when it ALREADY could.
                        // Without this, levelling up leads nowhere visible -- and
                        // that is exactly what makes it worthwhile. With several
                        // branches they are not listed (Eevee has eight and they
                        // would not fit): it says how many there are, and choosing
                        // is the button's job.
                        //
                        // With a stone the level is NOT shown even if the JSON
                        // brings it: Eevee says 30 and that is an operational lie,
                        // what is needed is the stone.
                        const evos = (m.evoluciones || []).filter(e => !e.listo);
                        if (evos.length === 1) {
                            const e = evos[0];
                            const porNivel = e.como === "nivel" || e.como === "level-up";
                            trozos.push("→ " + ShellState.pokeEspecie(e.especie, e.especie_es)
                                        + (porNivel && e.nivel ? "  " + I18n.tr("Niv") + " " + e.nivel
                                                               : "  " + I18n.tr("con piedra")));
                        } else if (evos.length > 1) {
                            trozos.push("→ " + evos.length + " " + I18n.tr("evoluciones posibles"));
                        }
                        return trozos.join("  ·  ");
                    }

                    RowLayout {
                        anchors.fill: parent
                        spacing: Appearance.gapM
                        // It moves with the background: both are "the row's
                        // content", and the MouseArea stays where it was.
                        transform: Translate { y: fila.arrastreY + fila.apartado }

                        // THE SPRITE, WITH TWO FALLBACKS.
                        //
                        // The sprite cache does NOT travel in the repo and the
                        // installer offers not to download it. Without a fallback,
                        // whoever says no opens the panel and sees six rows with a
                        // gap where their team should be, without a word to
                        // explain it. The animated gif is the pretty part; if it is
                        // missing, the official artwork says the same standing
                        // still; and if that is missing too, at least the pokedex
                        // number names the critter.
                        Item {
                            Layout.preferredWidth: root.colSprite
                            Layout.preferredHeight: 34

                            AnimatedImage {
                                id: gifBicho
                                anchors.fill: parent
                                source: fila.modelData.gif ? "file://" + fila.modelData.gif : ""
                                sourceSize.height: 34
                                fillMode: Image.PreserveAspectFit
                                // All of them alive while the panel is open: a
                                // still team looks like a drawer of plush toys. When
                                // it closes they stop by themselves.
                                playing: root.active
                                cache: false
                                visible: status === AnimatedImage.Ready
                            }

                            Image {
                                id: artBicho
                                anchors.fill: parent
                                source: (!gifBicho.visible && fila.modelData.art)
                                        ? "file://" + fila.modelData.art : ""
                                sourceSize.height: 34
                                fillMode: Image.PreserveAspectFit
                                visible: !gifBicho.visible && status === Image.Ready
                            }

                            StyledText {
                                anchors.centerIn: parent
                                visible: !gifBicho.visible && !artBicho.visible
                                text: "#" + fila.modelData.num
                                color: root.cTenue
                                font.family: Appearance.fontUI
                                font.pixelSize: Appearance.fsXXS
                            }
                        }

                        ColumnLayout {
                            Layout.preferredWidth: root.colNombre
                            Layout.maximumWidth: root.colNombre
                            spacing: 3

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 6

                                StyledText {
                                    visible: !fila.renombrando
                                    text: fila.modelData.mote || ShellState.pokeEspecie(fila.modelData.especie, fila.modelData.especie_es)
                                    color: fila.index === 0 ? Colors.fg : root.cTexto
                                    font.family: Appearance.fontUI
                                    font.pixelSize: Appearance.fsM
                                    elide: Text.ElideRight
                                    Layout.maximumWidth: 130
                                    // click on the name = give it a nickname. It sits
                                    // above the row's MouseArea, so it does NOT change
                                    // the leader along the way.
                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.IBeamCursor
                                        onClicked: fila.renombrando = true
                                    }
                                }
                                TextInput {
                                    visible: fila.renombrando
                                    Layout.preferredWidth: 130
                                    color: Colors.fg
                                    font.family: Appearance.fontUI
                                    font.pixelSize: Appearance.fsM
                                    onVisibleChanged: if (visible) {
                                        text = fila.modelData.mote || ShellState.pokeEspecie(fila.modelData.especie, fila.modelData.especie_es);
                                        selectAll();
                                        forceActiveFocus();
                                    }
                                    onAccepted: {
                                        if (text.trim())
                                            ShellState.pokeMote(fila.index, text.trim());
                                        fila.renombrando = false;
                                    }
                                    onActiveFocusChanged: if (!activeFocus) fila.renombrando = false
                                }

                                // The star is NEVER removed: being shiny is 1 in
                                // 64 and it is theirs. What is distinguished is
                                // something else — whether it can also WALK AROUND
                                // as a shiny. Without the gif in ~/.cache/pokeshiny
                                // (right now there are only three: 25, 133 and 197),
                                // poke-leader-shimeji brings it out in the normal
                                // colours on purpose, because fabricating a
                                // "…Shiny" prototype with the usual sprite
                                // inside would be lying twice. The panel said the
                                // opposite with the same filled star as one that
                                // really does look shiny.
                                //
                                // Hollow and at half light: it reads the same at a
                                // glance, it adds not a single pixel to the row and
                                // the reason is one hover away (see resumen()).
                                StyledText {
                                    visible: fila.modelData.shiny === true
                                    text: fila.modelData.shiny_listo === false ? "✧" : "✦"
                                    color: Colors.accent
                                    opacity: fila.modelData.shiny_listo === false ? 0.45 : 1
                                    font.pixelSize: Appearance.fsS
                                }

                                StyledText {
                                    visible: fila.index === 0
                                    text: I18n.tr("líder")
                                    color: Colors.accent
                                    font.family: Appearance.fontUI
                                    font.pixelSize: Appearance.fsXXS
                                    font.letterSpacing: 0.5
                                }

                                Item { Layout.fillWidth: true }
                            }

                            // The types, each with its own (see tintaTipo).
                            // It is text and not pills because here the line
                            // measures 9 px and fits just under the name: two
                            // pills with their fill would ask for twice the height
                            // and would push the whole row. Colour alone, without
                            // a box, says the same and does not take a pixel more.
                            Row {
                                Layout.fillWidth: true
                                spacing: 4
                                clip: true

                                Repeater {
                                    model: fila.modelData.tipos || []

                                    Row {
                                        id: parTipo
                                        required property var modelData
                                        required property int index
                                        spacing: 4

                                        StyledText {
                                            visible: parTipo.index > 0
                                            text: "·"
                                            color: root.cLinea
                                            font.family: Appearance.fontUI
                                            font.pixelSize: Appearance.fsXXS
                                        }
                                        StyledText {
                                            text: ShellState.pokeTipo(parTipo.modelData.id, parTipo.modelData.es)
                                            color: root.tintaTipo(parTipo.modelData.id)
                                            font.family: Appearance.fontUI
                                            font.pixelSize: Appearance.fsXXS
                                            font.letterSpacing: 0.3
                                        }
                                    }
                                }
                            }
                        }

                        // level: fixed column aligned right, like the %
                        // of the notch slider
                        StyledText {
                            Layout.preferredWidth: root.colNivel
                            horizontalAlignment: Text.AlignRight
                            text: I18n.tr("Niv") + " " + fila.modelData.nivel
                            color: fila.modelData.nivel >= 100 ? Colors.accent : root.cTenue
                            font.family: Appearance.fontUI
                            font.pixelSize: 10
                        }

                        // the bar: the same as the notch slider
                        Item {
                            Layout.preferredWidth: root.colBarra
                            Layout.preferredHeight: 6

                            Rectangle {
                                id: riel
                                anchors.fill: parent
                                radius: 3
                                // alpha over the palette, not a hex: that way the
                                // track follows the theme instead of being a stuck-on grey.
                                color: root.cRiel

                                Rectangle {
                                    // THE ANIMATION GOES ON THE VALUE, NOT ON THE WIDTH.
                                    // It looks the same and it is not: the track
                                    // measures what the panel measures, and the panel
                                    // widens with a SPRING every time the notch opens.
                                    // Animating the width, that widening comes in
                                    // through the same door as "you have gained
                                    // experience" and the fill chases it half a
                                    // second behind: on opening you saw the bar
                                    // almost full and shrinking to its place.
                                    // Animating the FRACTION, the fill follows the
                                    // track in the same frame and only slides when
                                    // the experience changes, which is the only thing
                                    // that deserves half a second.
                                    id: relleno
                                    property real p: Math.max(0, Math.min(1, fila.modelData.progreso || 0))
                                    Behavior on p {
                                        NumberAnimation { duration: Appearance.mTick; easing.type: Easing.OutCubic }
                                    }

                                    width: riel.width * p
                                    height: parent.height
                                    radius: parent.radius

                                    // THE BAR IS THE CRITTER'S COLOUR.
                                    //
                                    // They were six identical grey bars -- only the
                                    // leader's carried the accent-- in a list where
                                    // each row ALREADY says what type it is right
                                    // above. The data was there and was not used:
                                    // looking at the panel there was no way to tell
                                    // at a glance which one is the fire one and which
                                    // the electric one, which is the first thing you
                                    // ask yourself.
                                    //
                                    // The hue goes through tintaTipo(), i.e. with the
                                    // same lightness and saturation normalisation as
                                    // the type row above: the series' colours have
                                    // very different weights -- Dark sinks, Electric
                                    // screams-- and without bringing them to a common
                                    // lightness the list looks like stickers from
                                    // different sources. Dual-type ones carry both,
                                    // in a horizontal gradient and in the same order
                                    // in which they read below.
                                    readonly property var tps: fila.modelData.tipos || []
                                    // No readonly on purpose: QML does not let you
                                    // put a Behavior on a read-only property, and
                                    // the transition is exactly what you want when
                                    // evolving -- an Eevee that becomes Vaporeon
                                    // changes from Normal to Water, and the bar
                                    // slides from one colour to the other instead
                                    // of jumping.
                                    property color c1: tps.length > 0 ? root.tintaTipo(tps[0].id) : root.cTexto
                                    property color c2: tps.length > 1 ? root.tintaTipo(tps[1].id) : c1
                                    Behavior on c1 { ColorAnimation { duration: Appearance.mQuick } }
                                    Behavior on c2 { ColorAnimation { duration: Appearance.mQuick } }

                                    gradient: Gradient {
                                        orientation: Gradient.Horizontal
                                        GradientStop { position: 0.0; color: relleno.c1 }
                                        GradientStop { position: 1.0; color: relleno.c2 }
                                    }
                                }
                            }

                        }

                        // All the spare air piles up HERE, not spread
                        // across the row: that way the actions stay anchored to
                        // the right edge -- their usual place -- and the block of
                        // sprite, name, level and bar reads in one go.
                        Item { Layout.fillWidth: true }

                        // actions: slot ALWAYS reserved; only the opacity
                        // changes. If they appeared out of nowhere, the whole
                        // row would jump right under the cursor.
                        Item {
                            Layout.preferredWidth: root.colAcciones
                            Layout.preferredHeight: 22
                            opacity: filaMa.containsMouse || fila.modelData.puede_evolucionar
                                     || btnQuitar.armado ? 1 : 0
                            Behavior on opacity { NumberAnimation { duration: Appearance.mQuick } }

                            Row {
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 4

                                Mini {
                                    visible: fila.modelData.puede_evolucionar
                                    glifo: "↑"
                                    resalte: true
                                    ayuda: I18n.tr("Evolucionar")
                                    onPulsado: {
                                        const opciones = (fila.modelData.evoluciones || []).filter(e => e.listo);
                                        // With a single outcome it just evolves;
                                        // with several (Eevee has eight) you have
                                        // to choose, so the list opens.
                                        if (opciones.length === 1)
                                            ShellState.pokeEvolucionar(fila.index, "");
                                        else
                                            fila.eligiendoEvo = !fila.eligiendoEvo;
                                    }
                                }

                                Mini {
                                    glifo: "↓"
                                    ayuda: I18n.tr("A la caja")
                                    onPulsado: ShellState.pokeOrden(["guardar", String(fila.index)])
                                }

                                Mini {
                                    id: btnQuitar
                                    // Two presses, like Displays' Forget
                                    // button: a stray x cannot take away
                                    // months of levels.
                                    property bool armado: false
                                    glifo: armado ? "!" : "×"
                                    resalte: armado
                                    ayuda: armado ? I18n.tr("¿seguro?") : I18n.tr("Soltar")
                                    onPulsado: {
                                        if (btnQuitar.armado) {
                                            ShellState.pokeQuitar(fila.index);
                                            btnQuitar.armado = false;
                                        } else {
                                            btnQuitar.armado = true;
                                            desarme.restart();
                                        }
                                    }
                                    Timer { id: desarme; interval: 3000; onTriggered: btnQuitar.armado = false }
                                }
                            }
                        }
                    }

                    // the branches, when an evolution has to be chosen
                    Rectangle {
                        visible: fila.eligiendoEvo
                        anchors.right: parent.right
                        anchors.top: parent.bottom
                        width: ramas.implicitWidth + Appearance.gapM * 2
                        height: ramas.implicitHeight + Appearance.gapS * 2
                        radius: Appearance.radS
                        color: Colors.bgAlt
                        border.width: 1
                        border.color: root.cLinea
                        z: 10

                        Row {
                            id: ramas
                            anchors.centerIn: parent
                            spacing: 4
                            Repeater {
                                model: (fila.modelData.evoluciones || []).filter(e => e.listo)
                                Pildora {
                                    required property var modelData
                                    rotulo: ShellState.pokeEspecie(modelData.especie, modelData.especie_es)
                                    onPulsada: {
                                        ShellState.pokeEvolucionar(fila.index, modelData.especie);
                                        fila.eligiendoEvo = false;
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // ── the slots still free ────────────────────────────────────────
            // They used to not be drawn: with four critters the panel showed four
            // rows and then a dead hole down to the footer, because the panel
            // measures 424 px whatever it carries. Drawing them fixes both things at
            // once -- the gap closes by itself and at last you SEE there is room for
            // more, which before you only knew if you noticed there was still an
            // "Añadir" (Add) button at the top. And there is no need to touch the
            // notch geometry, which is the delicate part: six rows are always six
            // rows.
            //
            // The "you have no team yet" message was retired for this very reason:
            // six empty rows you can click say it better than a sentence, and on top
            // of that they can be clicked.
            Repeater {
                model: Math.max(0, root.tamano - root.equipo.length)

                Item {
                    id: hueco
                    required property int index

                    Layout.fillWidth: true
                    implicitHeight: 44

                    Rectangle {
                        anchors.fill: parent
                        anchors.leftMargin: -Appearance.gapS
                        anchors.rightMargin: -Appearance.gapS
                        radius: Appearance.radS
                        color: huecoMa.containsMouse
                               ? Qt.rgba(Colors.fg.r, Colors.fg.g, Colors.fg.b, 0.05)
                               : "transparent"
                        Behavior on color { ColorAnimation { duration: Appearance.mQuick } }
                    }

                    MouseArea {
                        id: huecoMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.cara = "pokedex"
                        onEntered: root.detalle = I18n.tr("Puesto libre — pulsa para elegir")
                        onExited: if (root.detalle === I18n.tr("Puesto libre — pulsa para elegir"))
                                      root.detalle = ""
                    }

                    RowLayout {
                        anchors.fill: parent
                        spacing: Appearance.gapM

                        // The ring goes in the sprite column and measures what an
                        // empty pokeball measures: it is the same symbol the
                        // Control Centre strip uses for a free slot, and the
                        // two places have to say the same thing with the same thing.
                        Item {
                            Layout.preferredWidth: root.colSprite
                            Layout.preferredHeight: 34

                            Rectangle {
                                anchors.centerIn: parent
                                width: 18; height: 18
                                radius: width / 2
                                color: "transparent"
                                border.width: 1
                                border.color: huecoMa.containsMouse ? Colors.accent : root.cRiel
                                Behavior on border.color { ColorAnimation { duration: Appearance.mQuick } }
                            }
                        }

                        StyledText {
                            Layout.preferredWidth: root.colNombre
                            Layout.maximumWidth: root.colNombre
                            text: I18n.tr("Puesto libre")
                            color: huecoMa.containsMouse ? root.cMedio : root.cDeco
                            Behavior on color { ColorAnimation { duration: Appearance.mQuick } }
                            elide: Text.ElideRight
                            font.family: Appearance.fontUI
                            font.pixelSize: Appearance.fsS
                        }

                        Item { Layout.fillWidth: true }

                        // The "+" only when pointed at, and in the actions slot:
                        // the same corner where evolve, store and release live
                        // in the rows above.
                        StyledText {
                            Layout.preferredWidth: root.colAcciones
                            horizontalAlignment: Text.AlignRight
                            text: "+"
                            color: Colors.accent
                            opacity: huecoMa.containsMouse ? 1 : 0
                            Behavior on opacity { NumberAnimation { duration: Appearance.mQuick } }
                            font.family: Appearance.fontUI
                            font.pixelSize: Appearance.fsL
                        }
                    }
                }
            }

            Item { Layout.fillHeight: true }
        }

        // ── team footer ─────────────────────────────────────────────────────
        Rectangle {
            visible: root.cara === "equipo"
            Layout.fillWidth: true
            Layout.topMargin: 8
            implicitHeight: 1
            color: root.cLinea
        }

        RowLayout {
            visible: root.cara === "equipo"
            Layout.fillWidth: true
            Layout.topMargin: 8
            spacing: Appearance.gapS

            Pildora {
                rotulo: I18n.tr("Repartir experiencia")
                active: ShellState.pokeTeam.repartir === true
                onPulsada: ShellState.pokeOrden(["repartir", "toggle"])
            }
            Pildora {
                rotulo: I18n.tr("Pasea por el escritorio")
                active: ShellState.pokeTeam.pasear === true
                onPulsada: ShellState.pokeOrden(["pasear", "toggle"])
            }
            Item { Layout.fillWidth: true }
            Pildora {
                visible: root.caja.length > 0
                rotulo: I18n.tr("Caja") + " · " + root.caja.length
                onPulsada: root.cara = "caja"
            }
        }

        // Whatever went wrong with the walk, if anything. The one that tries it is
        // poke-leader-shimeji, and the shell launches it with execDetached: neither
        // the output nor the exit code comes back, so a failure of its own was
        // invisible. The worst one was the expensive one: if the new leader's
        // prototype could not be built, the panel celebrated the evolution, the
        // critter kept its old form and every time you opened this four minutes of
        // factory work were relaunched. Now it writes it down and it arrives the way
        // everything else arrives — the JSON from 'poke-team estado' —, without
        // inventing another channel.
        StyledText {
            visible: root.cara === "equipo" && !!ShellState.pokeTeam.pasea_fallo
            Layout.fillWidth: true
            Layout.topMargin: 6
            text: I18n.tr("No pude sacarlo a pasear: {0}",
                          (ShellState.pokeTeam.pasea_fallo || {}).motivo || "")
            color: root.cTenue
            font.family: Appearance.fontUI
            font.pixelSize: Appearance.fsXXS
            wrapMode: Text.WordWrap
            maximumLineCount: 2
            elide: Text.ElideRight
        }

        // ── face 2: the pokedex ─────────────────────────────────────────────
        ColumnLayout {
            visible: root.cara === "pokedex"
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.topMargin: 12
            spacing: Appearance.gapS

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 30
                radius: Appearance.radS
                color: Qt.rgba(Colors.fg.r, Colors.fg.g, Colors.fg.b, 0.06)
                border.width: 1
                border.color: buscador.activeFocus
                              ? Qt.rgba(Colors.accent.r, Colors.accent.g, Colors.accent.b, 0.5)
                              : root.cLinea
                Behavior on border.color { ColorAnimation { duration: Appearance.mQuick } }

                TextInput {
                    id: buscador
                    anchors.fill: parent
                    anchors.leftMargin: Appearance.gapM
                    anchors.rightMargin: Appearance.gapM
                    verticalAlignment: TextInput.AlignVCenter
                    color: Colors.fg
                    font.family: Appearance.fontUI
                    font.pixelSize: Appearance.fsS
                    clip: true
                    focus: root.cara === "pokedex"
                    onTextChanged: root.busqueda = text
                    // It is emptied on ENTERING, not on leaving: emptying it on
                    // leaving would recompute the whole grid right as the panel closes.
                    Connections {
                        target: root
                        function onCaraChanged() {
                            if (root.cara === "pokedex") {
                                buscador.text = "";
                                // The type is cleared along with the text: coming
                                // back in and finding half the pokedex hidden by a
                                // filter you set two days ago reads as critters
                                // missing, not as a filter.
                                root.tipoFiltro = "";
                                filtroTipos.positionViewAtBeginning();
                            }
                        }
                    }

                    StyledText {
                        visible: !buscador.text
                        anchors.verticalCenter: parent.verticalCenter
                        text: I18n.tr("Buscar por nombre o número…")
                        color: root.cTenue
                        font.family: Appearance.fontUI
                        font.pixelSize: Appearance.fsS
                    }
                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.right: parent.right
                        text: root.filtrados.length
                        color: root.cTenue
                        font.family: Appearance.fontUI
                        font.pixelSize: Appearance.fsXXS
                    }
                }
            }

            // ── filter by type ──────────────────────────────────────────────
            // ONE row and not two: the eighteen labels ask for about 950 px and here
            // there are 538, so in two rows they would just fit but they would take 28
            // px from the grid FOREVER, whether you filter or not. It scrolls with the
            // wheel, and the pill peeking out cut off by the right edge is all it takes
            // to show that there is more.
            //
            // WITH the series' colours, run through tintaTipo first so they all weigh
            // the same. This is where they show the most: eighteen labels in a
            // scrolling row are eighteen words you have to read one by one, and as soon
            // as they carry their colour they are recognised at a glance without
            // reading them. "Todos" (All) keeps the theme accent, since it is not a
            // type: it is the way out.
            ListView {
                id: filtroTipos
                Layout.fillWidth: true
                Layout.preferredHeight: 22
                orientation: ListView.Horizontal
                spacing: 5
                clip: true
                // "" in front is the way out: with a filter set there must always be
                // a visible way of removing it without remembering which one it was.
                model: [""].concat(root.tiposOrden)

                delegate: Rectangle {
                    id: past
                    required property var modelData

                    readonly property bool activa: root.tipoFiltro === past.modelData
                    readonly property string rotulo: past.modelData
                        ? ShellState.pokeTipo(past.modelData, root.tipos.es[past.modelData])
                        : I18n.tr("Todos")
                    // "" is not a type: it is the way out, and it carries the theme accent.
                    readonly property color tinta: past.modelData
                        ? root.tintaTipo(past.modelData)
                        : Colors.accent

                    width: medidaTipo.width + 16
                    height: 22
                    radius: Appearance.radPill

                    // It FADES OUT when leaving by either side, instead of being cut
                    // off with a knife against the edge. Half a pill cut in two reads
                    // as a clipping bug; half a pill fading out reads as "there is
                    // still more list". It is done with opacity and not with a gradient
                    // on top because a gradient would have to paint in the background
                    // colour, and here pywal decides the background: the day the theme
                    // went light, the fade would be a dark smudge.
                    opacity: {
                        const izq = past.x - filtroTipos.contentX;
                        const der = izq + past.width;
                        if (der > filtroTipos.width)
                            return Math.max(0.12, (filtroTipos.width - izq) / past.width);
                        if (izq < 0)
                            return Math.max(0.12, der / past.width);
                        return 1;
                    }
                    // The background is the colour itself at low alpha, so the
                    // selected pill needs no other colour to stand out: it is
                    // enough to turn its own up.
                    color: past.activa ? root.velo(past.tinta, 0.26)
                        : pastMa.containsMouse ? root.velo(past.tinta, 0.16)
                        : root.velo(past.tinta, 0.08)
                    Behavior on color { ColorAnimation { duration: Appearance.mQuick } }

                    TextMetrics {
                        id: medidaTipo
                        font.family: Appearance.font
                        font.pixelSize: Appearance.fsXS
                        text: past.rotulo
                    }

                    StyledText {
                        anchors.centerIn: parent
                        text: past.rotulo
                        // At rest the colour is somewhat muted so the row is not
                        // a rainbow shouting its head off; the selected one and the
                        // one under the mouse go at full ink.
                        color: (past.activa || pastMa.containsMouse)
                               ? past.tinta : root.velo(past.tinta, 0.68)
                        Behavior on color { ColorAnimation { duration: Appearance.mQuick } }
                        font.pixelSize: Appearance.fsXS
                    }

                    MouseArea {
                        id: pastMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        // Clicking the one already selected again removes it: it is the
                        // same way out as "Todos" (All), but without going to look for it.
                        onClicked: root.tipoFiltro = past.activa ? "" : past.modelData
                    }
                }
            }

            // The GridView is wrapped in an Item so that the scroll bar can be
            // its SIBLING without being a child of the ColumnLayout. Hanging it
            // from the layout (parent: rejilla.parent) Qt warned on every
            // reload: "anchors on an item that is managed by a layout, this is
            // undefined behavior". And it was -- the layout gave it position and
            // size at the same time as the anchors, and which of the two won
            // depended on the evaluation order. It looked right by a miracle.
            Item {
                id: zonaRejilla
                Layout.fillWidth: true
                Layout.fillHeight: true

                GridView {
                    id: rejilla
                    anchors.fill: parent
                    clip: true
                    // The cell shares out WHATEVER width there is. With a fixed 76,
                    // the leftover of the last column stayed as a dead gap against
                    // the right edge -- it looked like a badly placed margin, not a
                    // grid -- and as soon as the panel changes width (another
                    // screen, another monitor) the mismatch grows. 76 goes from being
                    // THE size to being the MINIMUM size: it works out how many fit
                    // and shares the rest out among them.
                    readonly property int columnas: Math.max(4, Math.floor(width / 76))
                    cellWidth: Math.floor(width / columnas)
                    cellHeight: 74
                    model: root.filtrados
                    // A two-row buffer: it smooths the wheel without building the
                    // thousand cells in one go.
                    cacheBuffer: 140

                    delegate: Item {
                        id: celda
                        required property var modelData
                        readonly property bool tenido: root.yaTengo[modelData.num] === true
                        readonly property var susTipos: root.tiposDe(celda.modelData.num)
                        width: rejilla.cellWidth
                        height: rejilla.cellHeight

                        Rectangle {
                            anchors.fill: parent
                            anchors.margins: 2
                            radius: Appearance.radS
                            color: celdaMa.containsMouse && !celda.tenido
                                   ? Qt.rgba(Colors.fg.r, Colors.fg.g, Colors.fg.b, 0.07)
                                   : "transparent"
                            Behavior on color { ColorAnimation { duration: Appearance.mQuick } }
                        }

                        Column {
                            anchors.centerIn: parent
                            spacing: 2
                            // Dimmed, not hidden: 0.30 is the "disabled"
                            // step of the house scale.
                            opacity: celda.tenido ? 0.30 : 1
                            Behavior on opacity { NumberAnimation { duration: Appearance.mQuick } }

                            Image {
                                // Still: animating a thousand gifs at once eats
                                // the machine. The animated one is already seen in the team.
                                source: "file://" + Quickshell.env("HOME")
                                        + "/.cache/pokeanim/" + celda.modelData.num + ".gif"
                                sourceSize.height: 36
                                height: 36
                                fillMode: Image.PreserveAspectFit
                                anchors.horizontalCenter: parent.horizontalCenter
                                asynchronous: true
                            }
                            StyledText {
                                text: root.nombreDe(celda.modelData)
                                color: celda.tenido ? root.cTenue
                                     : (celdaMa.containsMouse ? Colors.fg : root.cTenue)
                                font.family: Appearance.fontUI
                                font.pixelSize: Appearance.fsXXS
                                elide: Text.ElideRight
                                width: celda.width - 6
                                horizontalAlignment: Text.AlignHCenter
                                anchors.horizontalCenter: parent.horizontalCenter
                                Behavior on color { ColorAnimation { duration: Appearance.mQuick } }
                            }

                            // What type it is, in 3 px of height. With a thousand
                            // critters in a grid, the name has to be READ one by
                            // one; a wisp of colour is seen without looking at it,
                            // and it is what turns scrolling into something you
                            // can leaf through. Split in two if it has two types.
                            Row {
                                anchors.horizontalCenter: parent.horizontalCenter
                                spacing: 2

                                Repeater {
                                    model: celda.susTipos

                                    Rectangle {
                                        required property var modelData
                                        // The two pieces always add up to the same,
                                        // whether there is one or two: otherwise the
                                        // single-type ones would show half a wisp and
                                        // look like something else.
                                        width: celda.susTipos.length > 1 ? 12 : 26
                                        height: 3
                                        radius: 999
                                        color: root.tintaTipo(modelData)
                                        opacity: celda.tenido ? 0.5 : 0.9
                                    }
                                }
                            }
                        }

                        // An accent dot in the corner: at half light it tells apart
                        // "dimmed because it is already yours" from "dimmed because the
                        // image has not loaded yet".
                        Rectangle {
                            visible: celda.tenido
                            anchors.top: parent.top
                            anchors.right: parent.right
                            anchors.margins: 6
                            width: 5
                            height: 5
                            radius: 999
                            color: Colors.accent
                        }

                        MouseArea {
                            id: celdaMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: celda.tenido ? Qt.ArrowCursor : Qt.PointingHandCursor
                            // The line above tells you about the cell you point at,
                            // just as it tells you about the row you point at in the
                            // team. It used to talk only about the ones you ALREADY
                            // have, so in practice it was mute: there are 1025 and
                            // you have five. And it is the only place where there is
                            // room to say what type each one is without putting text
                            // in the cell, which at 76 px does not take one more word.
                            onEntered: {
                                const nombres = celda.susTipos
                                    .map(t => ShellState.pokeTipo(t, (root.tipos.es || {})[t]));
                                const trozos = [root.nombreDe(celda.modelData),
                                                "#" + celda.modelData.num];
                                if (nombres.length)
                                    trozos.push(nombres.join(" · "));
                                if (celda.tenido)
                                    trozos.push(I18n.tr("ya está en tu equipo"));
                                root.detalle = trozos.join("  ·  ");
                            }
                            onExited: root.detalle = ""
                            onClicked: {
                                if (celda.tenido)
                                    return;          // already yours: nothing to do
                                ShellState.pokeAdd(celda.modelData.nombre);
                                root.cara = "equipo";
                            }
                        }
                    }

                    // Scroll bar, sibling and overlaid. Inside the GridView it
                    // would have gone along with the content: a Flickable's
                    // children live in its contentItem.
                    Rectangle {
                        id: barraRejilla
                        parent: zonaRejilla
                        anchors.right: parent.right
                        width: 2
                        radius: 1
                        color: root.cTenue

                        // How much of the list is visible, and where it starts.
                        readonly property real parte: rejilla.visibleArea.heightRatio
                        readonly property real desde: rejilla.visibleArea.yPosition

                        // THE MINIMUM OF 24 HAS TO BE SUBTRACTED FROM THE TRAVEL. With
                        // 1025 critters the visible part is 4%, i.e. a 13 px thumb: the
                        // minimum kicks in and it goes up to 24. But the position was
                        // still being worked out as if it measured 13, so when scrolled
                        // to the very bottom the bar stuck out TEN PIXELS below the grid.
                        // It shows right at the end of the scroll, which is where nobody
                        // looks twice, and that is why it lasted so long.
                        //
                        // The right thing is to share out the REAL travel --the height
                        // minus the thumb-- over the part of the list that can be
                        // travelled, which is 1 minus what is already visible.
                        height: Math.max(24, barraRejilla.parte * zonaRejilla.height)
                        y: {
                            const recorrido = zonaRejilla.height - barraRejilla.height;
                            const recorrible = 1 - barraRejilla.parte;
                            return recorrible > 0.0001
                                ? (barraRejilla.desde / recorrible) * recorrido : 0;
                        }

                        // It appears and goes with a fade, instead of switching on all at
                        // once. It is not vanity: when the panel opens there is a frame
                        // in which the content is already tall but the list has not yet
                        // measured how much of it is visible, and there the bar came out
                        // at FULL height for a blink. The fade swallows that frame, and
                        // along the way the extra condition --if it is all visible, there
                        // is nothing to scroll-- catches it before it gets drawn.
                        visible: opacity > 0.01
                        opacity: (rejilla.contentHeight <= rejilla.height + 1
                                  || barraRejilla.parte >= 0.999) ? 0
                               : rejilla.moving ? 0.9 : 0.35
                        Behavior on opacity { NumberAnimation { duration: Appearance.mIn } }
                    }
                }
            }
        }

        // ── face 3: the box ─────────────────────────────────────────────────
        // The ones that do not fit in the team. They keep EVERYTHING -- level,
        // experience, nickname, nature, shininess -- because storing is moving
        // house, not dying.
        ColumnLayout {
            visible: root.cara === "caja"
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.topMargin: 12
            spacing: Appearance.gapS

            StyledText {
                visible: root.caja.length === 0
                Layout.fillWidth: true
                Layout.topMargin: Appearance.gapL
                horizontalAlignment: Text.AlignHCenter
                text: I18n.tr("La caja está vacía.")
                color: root.cTenue
                font.family: Appearance.fontUI
                font.pixelSize: Appearance.fsM
            }

            GridView {
                id: rejillaCaja
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                // Same as the pokedex grid: 86 is the minimum, and however many
                // fit share out whatever width there is.
                readonly property int columnas: Math.max(3, Math.floor(width / 86))
                cellWidth: Math.floor(width / columnas)
                cellHeight: 78
                model: root.caja

                delegate: Item {
                    required property int index
                    required property var modelData
                    width: rejillaCaja.cellWidth
                    height: rejillaCaja.cellHeight

                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: 2
                        radius: Appearance.radS
                        color: cajaMa.containsMouse
                               ? Qt.rgba(Colors.fg.r, Colors.fg.g, Colors.fg.b, 0.07)
                               : "transparent"
                        Behavior on color { ColorAnimation { duration: Appearance.mQuick } }
                    }

                    Column {
                        anchors.centerIn: parent
                        spacing: 2
                        Image {
                            source: "file://" + modelData.gif
                            sourceSize.height: 36
                            height: 36
                            fillMode: Image.PreserveAspectFit
                            anchors.horizontalCenter: parent.horizontalCenter
                            asynchronous: true
                        }
                        StyledText {
                            text: (modelData.shiny ? "✦ " : "")
                                  + (modelData.mote || ShellState.pokeEspecie(modelData.especie, modelData.especie_es))
                            color: cajaMa.containsMouse ? Colors.fg : root.cTexto
                            font.family: Appearance.fontUI
                            font.pixelSize: Appearance.fsXXS
                            elide: Text.ElideRight
                            width: rejillaCaja.cellWidth - 6
                            horizontalAlignment: Text.AlignHCenter
                            anchors.horizontalCenter: parent.horizontalCenter
                            Behavior on color { ColorAnimation { duration: Appearance.mQuick } }
                        }
                        StyledText {
                            text: I18n.tr("Niv") + " " + modelData.nivel
                            color: root.cTenue
                            font.family: Appearance.fontUI
                            font.pixelSize: Appearance.fsXXS
                            anchors.horizontalCenter: parent.horizontalCenter
                        }
                    }

                    MouseArea {
                        id: cajaMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: root.equipo.length < root.tamano ? Qt.PointingHandCursor
                                                                      : Qt.ForbiddenCursor
                        // click = to the team, if there is room
                        onClicked: if (root.equipo.length < root.tamano)
                            ShellState.pokeOrden(["sacar", String(index)])
                    }
                }
            }

            StyledText {
                visible: root.caja.length > 0 && root.equipo.length >= root.tamano
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                text: I18n.tr("Equipo completo: guarda a alguno para sacar otro.")
                color: root.cTenue
                font.family: Appearance.fontUI
                font.pixelSize: Appearance.fsXS
            }
        }
    }

    // The panel's pill: the house PillButton, but 26 px and sizing itself by
    // its text. PillButton does not work out a width -- whoever uses it gives
    // it one-- and here the labels have very different lengths ("Caja · 1"
    // against "Pasea por el escritorio"): with widths by eye, the footer row
    // came out misaligned.
    component Pildora: PillButton {
        id: pild
        property string rotulo: ""
        signal pulsada()

        label: pild.rotulo
        implicitHeight: 26
        // Layout.preferredWidth and not just implicitWidth: inside a RowLayout
        // the layout is in charge, and with implicitWidth alone it shared out the
        // width as it pleased -- long labels came out cut in half.
        implicitWidth: medida.width + 22
        Layout.preferredWidth: medida.width + 22
        Layout.preferredHeight: 26
        onClicked: pild.pulsada()

        // Measured with Appearance.font, NOT with fontUI: PillButton's text is a
        // StyledText, and StyledText comes with the mono font as standard.
        // Measuring with the proportional one -narrower- the button came out
        // short and the label overflowed at the sides.
        TextMetrics {
            id: medida
            font.family: Appearance.font
            font.pixelSize: Appearance.fsS
            text: pild.rotulo
        }
    }

    // Square row-action button. PillButton measures 34 and here something of
    // 22 that fits in the row is needed; the rest -- the feel on press, the
    // cursor, the curve -- is copied from it on purpose, so it feels the same.
    component Mini: Rectangle {
        id: mini
        property string glifo: ""
        property string ayuda: ""
        property bool resalte: false
        signal pulsado()

        width: 22
        height: 22
        radius: Appearance.radS
        color: miniMa.containsMouse
               ? (mini.resalte ? Colors.accent
                               : Qt.rgba(Colors.fg.r, Colors.fg.g, Colors.fg.b, 0.14))
               : (mini.resalte ? Qt.rgba(Colors.accent.r, Colors.accent.g, Colors.accent.b, 0.28)
                               : Qt.rgba(Colors.fg.r, Colors.fg.g, Colors.fg.b, 0.07))
        Behavior on color { ColorAnimation { duration: Appearance.mQuick } }
        scale: miniMa.pressed ? 0.92 : 1.0
        Behavior on scale { NumberAnimation { duration: Appearance.mQuick; easing.type: Easing.OutCubic } }

        StyledText {
            anchors.centerIn: parent
            text: mini.glifo
            color: miniMa.containsMouse && mini.resalte ? Colors.bg : Colors.fg
            font.family: Appearance.fontUI
            font.pixelSize: Appearance.fsS
        }

        MouseArea {
            id: miniMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            // The help goes to the line above, not to a bubble over the button:
            // on top of a 22 px button, the bubble covers the row next to it.
            onEntered: if (mini.ayuda) root.detalle = mini.ayuda
            onExited: if (root.detalle === mini.ayuda) root.detalle = ""
            onClicked: mini.pulsado()
        }
    }
}
