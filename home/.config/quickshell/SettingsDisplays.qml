// SettingsDisplays.qml — where each display is and how you want it.
//
// Adapted from Impasto's settings/MonitorsSection.qml
// (https://github.com/andreumassanet/impasto, GPL-3.0). The engine and the why
// of each decision are in Displays.qml; here there is only the part you touch.
//
// ONE CARD FOR THE CHOSEN DISPLAY, not one per display. With two monitors the
// difference does not show; with four, a column of four identical cards does
// not read, and besides the map already tells you which is which — picking up
// there and changing down here is the same gesture the desktop itself makes.
//
// Whatever can leave you in the dark (resolution, scale, rotation, mirroring)
// is NOT simply applied: it is put on trial and reverts by itself after 20
// seconds unless you say it looks fine. Whatever cannot (moving a display,
// turning it on, variable refresh rate) is applied on release, no questions.
import Quickshell
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Flickable {
    id: root

    property string note: I18n.tr("La distribución se guarda para ESTE conjunto de pantallas; con otras conectadas vuelve la suya.")

    // The display being edited. The KEY is stored, not a position in the list:
    // plugging or unplugging reorders the list and the same number would end
    // up pointing at another display.
    property string chosen: ""

    readonly property var monitors: Displays.monitors
    readonly property var current: {
        const found = root.monitors.find(m => m.key === root.chosen);
        return found || root.monitors[0] || null;
    }

    readonly property bool onlyLit: Displays.lit.length <= 1 && !(root.current && root.current.disabled)

    // The refresh rates offered by the resolution set right now.
    readonly property var refreshes: {
        const s = root.current;
        if (!s || s.disabled) return [];
        const group = (s.resolutions || []).find(r => r.width === s.width && r.height === s.height);
        return group ? group.refreshes : [];
    }

    readonly property var scales: [1, 1.25, 1.5, 1.75, 2]
    readonly property var turns: [I18n.tr("Sin girar"), "90°", "180°", "270°"]

    // The map is not a settings row, so it is searched separately, just as in
    // Profiles.
    readonly property bool matches: ShellState.settingsMatch(I18n.tr("Pantallas"), root.note)
    readonly property int matchCount: (root.matches ? 1 : 0) + cScreen.visibleRows + cSet.visibleRows

    property string confirming: ""
    Timer { id: disarm; interval: 2500; onTriggered: root.confirming = "" }
    function confirm(action) {
        if (root.confirming !== action) { root.confirming = action; disarm.restart(); return false; }
        root.confirming = ""; disarm.stop(); return true;
    }

    contentHeight: col.implicitHeight + 34
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded; width: 5 }
    onVisibleChanged: {
        root.confirming = "";
        if (visible) { contentY = 0; Displays.load(); }
    }

    // Changes the chosen display at once and with no safety net: for whatever
    // cannot leave you unable to see the screen.
    function set(fields) {
        if (root.current) Displays.remember(root.current.key, fields);
    }
    // And this for whatever can: it is tried, and saved only if you confirm.
    function test(fields) {
        if (root.current) Displays.tryOut(root.current.key, fields);
    }

    ColumnLayout {
        id: col
        width: root.width - 48
        x: 24
        y: 16
        spacing: 10

        // ─────────────────── the trial in progress ───────────────────
        // It goes at the very top and in colour: while it runs, it is the only
        // thing on this page that matters.
        Rectangle {
            Layout.fillWidth: true
            Layout.topMargin: 4
            visible: Displays.trying
            implicitHeight: 58
            radius: Appearance.radM
            color: Qt.rgba(Colors.accent.r, Colors.accent.g, Colors.accent.b, 0.16)
            border.width: 1
            border.color: Qt.rgba(Colors.accent.r, Colors.accent.g, Colors.accent.b, 0.55)

            RowLayout {
                anchors { fill: parent; leftMargin: 14; rightMargin: 12 }
                spacing: 12

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 1
                    Text {
                        text: I18n.tr("¿Se ve bien?")
                        color: Colors.label
                        font.family: Appearance.fontUI
                        font.pixelSize: Appearance.fsS
                        font.weight: Font.Medium
                    }
                    Text {
                        text: I18n.tr("Vuelve sola en {0} s si no dices nada.", Displays.trySeconds)
                        color: Colors.label2
                        font.family: Appearance.fontUI
                        font.pixelSize: Appearance.fsXS
                        font.features: ({ "tnum": 1 })   // the countdown ticks by itself: keep it from jittering
                    }
                }
                SettingsControls.Btn_ {
                    text: I18n.tr("Volver atrás")
                    onClicked: Displays.revert()
                }
                SettingsControls.Btn_ {
                    text: I18n.tr("Conservar")
                    onClicked: Displays.keep()
                }
            }
        }

        SettingsControls.Note_ {
            visible: Displays.problem.length > 0 && !Displays.trying
            text: Displays.problem
            color: Colors.warn
        }

        // ─────────────────── the map ───────────────────
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 8
            visible: root.matches && root.monitors.length > 0

            Text {
                Layout.leftMargin: 3
                text: I18n.tr("El mapa")
                color: Colors.accentInk
                font.family: Appearance.fontUI
                font.pixelSize: Appearance.fsXS
                font.weight: Font.DemiBold
            }

            SettingsControls.Note_ {
                text: Displays.lit.length > 1
                    ? I18n.tr("Arrastra una pantalla para colocarla; se pega sola a la de al lado. Pulsa una para cambiar sus ajustes.")
                    : I18n.tr("Con una sola pantalla no hay nada que colocar. Enchufa otra y aparecerá aquí.")
            }

            DisplayCanvas {
                Layout.fillWidth: true
                Layout.preferredHeight: 210
                monitors: root.monitors
                selected: root.current ? root.current.key : ""
                enabled: !Displays.mirroring && !Displays.trying
                opacity: (Displays.mirroring || Displays.trying) ? 0.45 : 1
                Behavior on opacity { NumberAnimation { duration: Appearance.mQuick } }

                onPicked: function (key) { root.chosen = key; }
                onArranged: function (positions) {
                    for (const key in positions)
                        Displays.remember(key, { position: positions[key].x + "x" + positions[key].y });
                }
            }

            // A display that is off takes no room on the map —Hyprland reports
            // it with no geometry— so it is listed here so you can pick it and
            // turn it back on.
            Repeater {
                model: root.monitors.filter(m => m.disabled)
                Rectangle {
                    id: dark
                    required property var modelData
                    Layout.fillWidth: true
                    Layout.preferredHeight: 34
                    radius: Appearance.radS
                    color: root.chosen === dark.modelData.key ? Colors.fill1 : Colors.fill3
                    border.width: 1
                    border.color: Colors.hairline
                    Behavior on color { ColorAnimation { duration: Appearance.mQuick } }

                    RowLayout {
                        anchors { fill: parent; leftMargin: 12; rightMargin: 12 }
                        spacing: 9
                        Text {
                            text: Icons.monitor
                            color: Colors.label4
                            font.family: Appearance.font
                            font.pixelSize: Appearance.fsS
                        }
                        Text {
                            Layout.fillWidth: true
                            text: I18n.tr("{0} — apagada, pero sigue enchufada", dark.modelData.name)
                            color: Colors.label3
                            elide: Text.ElideRight
                            font.family: Appearance.fontUI
                            font.pixelSize: Appearance.fsXS
                        }
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.chosen = dark.modelData.key
                    }
                }
            }
        }

        // ─────────────────── the chosen display ───────────────────
        SettingsControls.Card_ {
            id: cScreen
            title: root.current
                ? I18n.tr("PANTALLA · {0}", root.current.name)
                : I18n.tr("Pantalla")

            SettingsControls.Row_ {
                shown: root.monitors.length > 1
                label: I18n.tr("Cuál estás tocando")
                hint: I18n.tr("Los ajustes de aquí abajo son de esta pantalla sola. También puedes elegirla pulsándola en el mapa.")
                SettingsControls.Choice_ {
                    options: root.monitors.map(m => m.name)
                    current: root.current ? root.current.name : ""
                    onPicked: function (name) {
                        const found = root.monitors.find(m => m.name === name);
                        if (found) root.chosen = found.key;
                    }
                }
            }

            SettingsControls.Row_ {
                shown: !!root.current
                label: I18n.tr("Modelo")
                hint: I18n.tr("Lo que dice el propio monitor por el cable. Es lo que identifica la pantalla cuando cambias el cable de puerto.")
                SettingsControls.Val_ {
                    text: root.current
                        ? (String(root.current.make + " " + root.current.model).trim() || root.current.description)
                        : ""
                }
            }

            // The row is NOT dimmed when it is the only display that is on,
            // only the switch. Dimming both multiplies them (0.42 × 0.45) and
            // leaves the label almost unreadable just when you most need to
            // read it: the disabled switch does not matter, what you need to be
            // able to read is WHY it will not turn off, and that is in the
            // footer strip.
            SettingsControls.Row_ {
                shown: !!root.current
                active: !Displays.trying
                label: I18n.tr("Encendida")
                hint: root.onlyLit
                    ? I18n.tr("Es la única pantalla encendida que hay: apagarla te dejaría sin ninguna, y sin sitio desde el que volver a encenderla.")
                    : I18n.tr("Apagarla la saca de la distribución y mueve sus escritorios a las demás. Sigue enchufada y vuelve con solo encenderla.")
                SettingsControls.Switch_ {
                    checked: !(root.current && root.current.disabled)
                    live: !root.onlyLit && !Displays.trying
                    onToggled: function (v) { root.set({ disabled: !v }); }
                }
            }

            SettingsControls.Row_ {
                shown: !!root.current && !root.current.disabled
                       && (root.current.resolutions || []).length > 1
                active: !Displays.trying
                label: I18n.tr("Resolución")
                hint: I18n.tr("Solo salen los modos que anuncia el monitor. Al elegir una resolución se coge su frecuencia más alta. El cambio se prueba antes de quedarse.")
                SettingsControls.Choice_ {
                    options: (root.current ? root.current.resolutions : []).map(r => r.width + " × " + r.height)
                    current: root.current ? (root.current.width + " × " + root.current.height) : ""
                    onPicked: function (label) {
                        const r = (root.current.resolutions || []).find(x => (x.width + " × " + x.height) === label);
                        if (r) root.test({ mode: r.width + "x" + r.height + "@" + r.refreshes[0].toFixed(2) });
                    }
                }
            }

            SettingsControls.Row_ {
                shown: !!root.current && !root.current.disabled && root.refreshes.length > 1
                active: !Displays.trying
                label: I18n.tr("Frecuencia")
                hint: I18n.tr("Cuántas veces por segundo se refresca la imagen, entre las que admite la resolución puesta.")
                SettingsControls.Choice_ {
                    options: root.refreshes.map(hz => hz + " Hz")
                    current: root.current ? (Number(root.current.refresh.toFixed(2)) + " Hz") : ""
                    onPicked: function (label) {
                        const hz = parseFloat(label);
                        if (isFinite(hz))
                            root.test({ mode: root.current.width + "x" + root.current.height + "@" + hz.toFixed(2) });
                    }
                }
            }

            // Pills and not a slider on purpose: Hyprland rejects scales that
            // do not give a whole resolution ("scale is not divisible by the
            // resolution"), and a continuous slider passes through dozens of
            // values that do not work. These five are the ones actually used.
            SettingsControls.Row_ {
                shown: !!root.current && !root.current.disabled
                active: !Displays.trying
                label: I18n.tr("Escala")
                hint: I18n.tr("Agranda todo lo que se ve sin bajar la resolución: en una pantalla muy densa, 1× deja la letra diminuta. Se prueba antes de quedarse.")
                SettingsControls.Choice_ {
                    options: root.scales.map(s => s + "×")
                    current: root.current ? (Number(root.current.scale) + "×") : ""
                    onPicked: function (label) {
                        const s = parseFloat(label);
                        if (isFinite(s)) root.test({ scale: s });
                    }
                }
            }

            SettingsControls.Row_ {
                shown: !!root.current && !root.current.disabled
                active: !Displays.trying
                label: I18n.tr("Rotación")
                hint: I18n.tr("Para un monitor puesto de pie. Gira la imagen y el ratón; la resolución se cuenta al revés. Se prueba antes de quedarse.")
                SettingsControls.Choice_ {
                    options: root.turns
                    current: root.current ? root.turns[Math.min(3, root.current.transform)] : ""
                    onPicked: function (label) {
                        const at = root.turns.indexOf(label);
                        if (at >= 0) root.test({ transform: at });
                    }
                }
            }

            SettingsControls.Row_ {
                shown: !!root.current && !root.current.disabled
                active: !Displays.trying
                label: I18n.tr("Frecuencia variable")
                hint: I18n.tr("El monitor se sincroniza con lo que pinta el equipo en vez de ir a ritmo fijo (FreeSync o G-Sync). No todos lo admiten, aunque lo anuncien.")
                SettingsControls.Switch_ {
                    checked: !!(root.current && root.current.vrr)
                    live: !Displays.trying
                    onToggled: function (v) { root.set({ vrr: v ? 1 : 0 }); }
                }
            }
        }

        // ─────────────────── all at once ───────────────────
        SettingsControls.Card_ {
            id: cSet
            title: I18n.tr("Todas a la vez")

            SettingsControls.Row_ {
                shown: root.monitors.length > 1
                active: !Displays.trying
                label: I18n.tr("Distribución")
                hint: I18n.tr("Extendida, cada pantalla enseña una parte del escritorio. Duplicada, todas enseñan lo mismo que la primera y dejan de tener sitio propio.")
                SettingsControls.Choice_ {
                    options: [I18n.tr("Extender"), I18n.tr("Duplicar")]
                    current: Displays.mirroring ? I18n.tr("Duplicar") : I18n.tr("Extender")
                    onPicked: function (label) {
                        Displays.tryOut("*", { mirror: label === I18n.tr("Duplicar") });
                    }
                }
            }

            SettingsControls.Row_ {
                shown: Displays.arranged
                active: !Displays.trying
                label: I18n.tr("Olvidar esta distribución")
                hint: I18n.tr("Devuelve estas pantallas a la colocación automática de Hyprland. No toca las distribuciones guardadas para otros conjuntos de pantallas.")
                SettingsControls.Btn_ {
                    text: root.confirming === "forget" ? I18n.tr("Confirmar") : I18n.tr("Olvidar")
                    danger: true
                    onClicked: if (root.confirm("forget")) Displays.forget()
                }
            }

            SettingsControls.Row_ {
                shown: true
                label: I18n.tr("Conjunto guardado")
                hint: I18n.tr("Cada conjunto de pantallas guarda su propia distribución, así que enchufar el monitor de siempre la recupera sin tocar nada.")
                SettingsControls.Val_ {
                    text: Displays.arranged ? I18n.tr("Sí, para estas {0}", root.monitors.length)
                                            : I18n.tr("Todavía no")
                }
            }
        }

        SettingsControls.Note_ {
            Layout.topMargin: 10
            visible: ShellState.settingsQuery.length > 0 && !root.matches
                     && !cScreen.visible && !cSet.visible
            text: I18n.tr("Ningún ajuste de Pantallas coincide con «{0}».", ShellState.settingsQuery)
        }
    }
}
