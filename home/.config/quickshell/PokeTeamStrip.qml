// PokeTeamStrip.qml — the pokemon team at a glance, in the Control Centre.
//
// The team levels up by itself, with the contributions poke-team keeps
// pulling out of GitHub, and until now that happened behind your back: you did
// not find out about a new level or an evolution about to drop until you opened
// Super+P by hand. This strip takes the gap that was left free in the centre
// column and does exactly the same as the two cards below it: a GLANCE that is
// also a DOOR. Same shape, same background and same hover as them, so they
// read as the same family and not as a pokemon patch stuck onto the panel.
//
// It does NOT repeat what PokeTeamPanel already does -nicknames, natures,
// badges, box, pokedex-, which is the whole panel. This is the peephole: who
// you are carrying, how far they have to go and who is ready to evolve. The
// rest is one click away.
import QtQuick
import QtQuick.Layouts

Rectangle {
    id: root

    readonly property bool active: ShellState.panel === "control"
    readonly property var equipo: ShellState.pokeTeam.equipo || []
    readonly property int tamano: ShellState.pokeTeam.tamano || 6

    // The house ink levels, the same ones PokeTeamPanel uses so that the two
    // places where the team shows up speak alike. They are no longer alphas by
    // eye: each level comes from Colors with its contrast measured, so the
    // hierarchy holds with any pywal palette and not according to whatever is
    // behind.
    readonly property color cTexto: Colors.label2   // body
    readonly property color cMedio: Colors.label3   // summary
    readonly property color cTenue: Colors.label3   // metadata
    readonly property color cRiel:  Colors.fill3    // meter track

    // THE SHARED LINE, once again the pattern of the GitHub panel and the
    // pokemon one: at rest it summarises the trainer and when you point at a
    // critter it tells you about THAT critter. It always exists and only the
    // text changes, so nothing moves under the cursor and there is no need for
    // a bubble covering exactly what you are looking at.
    property string detalle: ""

    Layout.fillWidth: true
    // The usual 118, plus the 17 of the HP bar when there is a battery. On the
            // tower there is none, so the card stays exactly as it was.
            Layout.preferredHeight: 118 + (ShellState.batt >= 0 ? 17 : 0)

    // The 13 of the radius and the two accent veils of the hover are still the
    // same literal numbers as performanceLink and githubLink, down below: if they
    // are ever touched, all three are touched at once. The rest state and the
    // border, on the other hand, now go through tokens -- they were
    // Qt.rgba(1, 1, 1, α), and pure white does not re-theme: over a tinted
    // background this card leaned towards neutral grey while its neighbours leaned
    // towards the palette colour.
    radius: 13
    color: ma.containsMouse
        ? Qt.rgba(Colors.accent.r, Colors.accent.g, Colors.accent.b, 0.14)
        : Colors.fill3
    border.width: 1
    border.color: ma.containsMouse
        ? Qt.rgba(Colors.accent.r, Colors.accent.g, Colors.accent.b, 0.26)
        : Colors.hairline
    Behavior on color { ColorAnimation { duration: Appearance.mQuick; easing.type: Easing.OutQuad } }

    // The team was only read when opening Super+P. Without this the strip comes
    // out empty the first time you open the Control Centre in the whole session.
    onActiveChanged: {
        if (root.active)
            ShellState.pokeTeamRefresh();
        else
            root.detalle = "";
    }

    // At the very back and NOT in the slots: the whole card is one single
    // target, like the two below. The slots only listen to the mouse (they go
    // with NoButton), so the click passes through them and arrives here.
    MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: ShellState.togglePanel("poke")
    }

    ColumnLayout {
        anchors { fill: parent; leftMargin: 12; rightMargin: 10; topMargin: 9; bottomMargin: 9 }
        spacing: 0

        // ---- header: name, who you are and the door arrow ----
        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            StyledText {
                text: I18n.tr("Equipo")
                color: ma.containsMouse ? Colors.accentInk : Colors.label
                font.family: Appearance.fontUI
                font.pixelSize: Appearance.fsXXS
                font.weight: Font.DemiBold
            }

            StyledText {
                Layout.fillWidth: true
                elide: Text.ElideRight
                text: {
                    if (root.detalle)
                        return root.detalle;
                    const t = ShellState.pokeTeam;
                    const trozos = [];
                    if (t.rango)
                        trozos.push(I18n.tr(t.rango));
                    if (t.nivel_total)
                        trozos.push(I18n.tr("Niv") + " " + t.nivel_total);
                    // Written the same as in the panel («+3 para Roca», +3 to Rock),
                    // which is where you end up if you click: the same phrase on both
                    // sides of the door.
                    const p = t.proxima_medalla;
                    if (p && p.faltan > 0)
                        trozos.push("+" + p.faltan + " " + I18n.tr("para") + " " + I18n.tr(p.nombre));
                    return trozos.join("  ·  ");
                }
                color: root.detalle ? Colors.fg : Colors.label3
                Behavior on color { ColorAnimation { duration: Appearance.mQuick; easing.type: Easing.OutQuad } }
                font.family: Appearance.fontUI
                font.pixelSize: 8
            }

            StyledText {
                text: "›"
                color: ma.containsMouse ? Colors.accent : "#707070"
                font.family: Appearance.fontUI
                font.pixelSize: 20
            }
        }

        Item { Layout.fillHeight: true }

        // ---- the six slots ----
        // The model is `tamano`, not `equipo`: free slots are drawn all the
        // same, as an empty gap. That way the strip always measures the same,
        // it does not reshuffle when you put a critter in or take one out, and
        // the empty gap says on its own that there is room for one more.
        RowLayout {
            Layout.fillWidth: true
            spacing: 0

            Repeater {
                model: root.tamano

                Item {
                    id: puesto
                    required property int index

                    readonly property var m: puesto.index < root.equipo.length
                                             ? root.equipo[puesto.index] : null
                    readonly property bool lider: puesto.index === 0 && puesto.m

                    Layout.fillWidth: true
                    implicitHeight: 66

                    function resumen() {
                        if (!puesto.m)
                            return I18n.tr("Puesto libre — pulsa para elegir");
                        const m = puesto.m;
                        const trozos = [m.mote || ShellState.pokeEspecie(m.especie, m.especie_es)];
                        const tipos = (m.tipos || []).map(x => ShellState.pokeTipo(x.id, x.es)).join(" · ");
                        if (tipos)
                            trozos.push(tipos);
                        if (m.puede_evolucionar)
                            trozos.push(I18n.tr("listo para evolucionar"));
                        else if (m.nivel < 100)
                            trozos.push(m.xp + "/" + m.umbral + " " + I18n.tr("exp"));
                        else
                            trozos.push(I18n.tr("al tope"));
                        return trozos.join("  ·  ");
                    }

                    // NoButton: listens to the mouse to say who it is on the
                    // line above, but lets the click through to the card.
                    MouseArea {
                        anchors.fill: parent
                        acceptedButtons: Qt.NoButton
                        hoverEnabled: true
                        onEntered: root.detalle = puesto.resumen()
                        onExited: if (root.detalle === puesto.resumen()) root.detalle = ""
                    }

                    ColumnLayout {
                        anchors.centerIn: parent
                        spacing: 4

                        // sprite, or the empty gap
                        Item {
                            Layout.alignment: Qt.AlignHCenter
                            implicitWidth: 44
                            implicitHeight: 36

                            AnimatedImage {
                                id: gifPuesto
                                anchors.centerIn: parent
                                visible: !!puesto.m && status === AnimatedImage.Ready
                                source: (puesto.m && puesto.m.gif) ? "file://" + puesto.m.gif : ""
                                sourceSize.height: 36
                                width: 44
                                height: 36
                                fillMode: Image.PreserveAspectFit
                                // Alive only while the panel is open:
                                // six gifs spinning with the notch closed is
                                // battery thrown away. On closing they stop by themselves.
                                playing: root.active
                                cache: false
                                asynchronous: true
                            }

                            // Same fallback as the team panel: the sprite cache
                            // does not travel in the repo and the installer
                            // offers not to download it. Without this, a freshly
                            // installed Control Centre shows six empty slots.
                            Image {
                                anchors.centerIn: parent
                                visible: !!puesto.m && !gifPuesto.visible && status === Image.Ready
                                source: (puesto.m && !gifPuesto.visible && puesto.m.art)
                                        ? "file://" + puesto.m.art : ""
                                sourceSize.height: 36
                                width: 44
                                height: 36
                                fillMode: Image.PreserveAspectFit
                                asynchronous: true
                            }

                            // The free slot: a ring, not a square. It reads as
                            // a pokeball with nothing inside and weighs just
                            // enough not to compete with the ones that ARE there.
                            Rectangle {
                                anchors.centerIn: parent
                                visible: !puesto.m
                                width: 18; height: 18
                                radius: width / 2
                                color: "transparent"
                                border.width: 1
                                border.color: root.cRiel
                            }

                            // The evolution arrow, the strip's only alarm: if it
                            // is there, there is something to do TODAY. That is
                            // why it takes the accent and why it pulses.
                            StyledText {
                                visible: puesto.m && puesto.m.puede_evolucionar
                                anchors { right: parent.right; top: parent.top; rightMargin: -1; topMargin: -3 }
                                text: "↑"
                                color: Colors.accent
                                font.family: Appearance.fontUI
                                font.pixelSize: 12
                                font.weight: Font.Bold

                                SequentialAnimation on opacity {
                                    running: parent.visible && root.active
                                    loops: Animation.Infinite
                                    NumberAnimation { from: 1; to: 0.35; duration: 900; easing.type: Easing.InOutQuad }
                                    NumberAnimation { from: 0.35; to: 1; duration: 900; easing.type: Easing.InOutQuad }
                                }
                            }
                        }

                        // the bar: the same as the notch slider and the
                        // same as the rows in the team panel
                        Item {
                            Layout.alignment: Qt.AlignHCenter
                            implicitWidth: 40
                            implicitHeight: 4
                            visible: !!puesto.m

                            Rectangle {
                                id: riel
                                anchors.fill: parent
                                radius: 2
                                color: root.cRiel

                                Rectangle {
                                    // The FRACTION is animated and not the width: the
                                    // track changes size when the notch opens, and
                                    // animating the width makes the fill chase that
                                    // geometry half a second behind. See the long
                                    // explanation in PokeTeamPanel.
                                    property real p: Math.max(0, Math.min(1, (puesto.m && puesto.m.progreso) || 0))
                                    Behavior on p {
                                        NumberAnimation { duration: Appearance.mTick; easing.type: Easing.OutCubic }
                                    }

                                    width: riel.width * p
                                    height: parent.height
                                    radius: parent.radius
                                    color: puesto.lider ? Colors.accent : root.cTexto
                                }
                            }
                        }

                        // name, with the drop of type colour in front. The
                        // dot is the only concession to the series' colours
                        // in the whole interface, and it earns it because the
                        // sprite right above it already carries that colour:
                        // the drop does not bring in a new colour, it names the
                        // one you were already seeing. The type in words lives
                        // on the line above.
                        RowLayout {
                            Layout.alignment: Qt.AlignHCenter
                            spacing: 4
                            visible: !!puesto.m

                            Rectangle {
                                Layout.alignment: Qt.AlignVCenter
                                width: 4; height: 4
                                radius: 2
                                visible: puesto.m && (puesto.m.tipos || []).length > 0
                                // Through Colors.typeInk and not the raw hex: that
                                // way this drop weighs the same as the label of the
                                // same type in the team panel.
                                color: puesto.m && (puesto.m.tipos || []).length > 0
                                       ? Colors.typeInk(puesto.m.tipos[0].color) : "transparent"
                            }

                            StyledText {
                                Layout.maximumWidth: 50
                                text: puesto.m ? (puesto.m.mote || ShellState.pokeEspecie(puesto.m.especie, puesto.m.especie_es)) : ""
                                color: puesto.lider ? Colors.fg : root.cMedio
                                elide: Text.ElideRight
                                font.family: Appearance.fontUI
                                font.pixelSize: Appearance.fsXXS
                            }
                        }
                    }
                }
            }
        }

        // ---- the battery, told like the team's HP ----
        // The figure was already in the bar above with its icon; here it is not
        // repeated for decoration, it is TRANSLATED: on this surface the team is in
        // charge, and in the team's language the energy you have left is health
        // points. Green, amber and red with the game's thresholds.
        //
        // On the tower there is no battery and ShellState.batt stays at -1: then the
        // bar is not painted and the strip stays exactly as it was.
        HpBar {
            Layout.fillWidth: true
            Layout.topMargin: Appearance.gapS
            nivel: ShellState.batt
            cargando: ShellState.ac && ShellState.batt < 100
            tamTexto: 9
        }

        Item { Layout.fillHeight: true }
    }
}
