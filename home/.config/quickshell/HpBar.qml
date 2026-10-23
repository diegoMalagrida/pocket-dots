// HpBar.qml — the battery told as a pokémon's HP.
//
// The data is the same as ever; what changes is the language. Green, amber and
// red with the game's thresholds (half and one fifth), a reading that needs no
// legend: anyone who has played knows what a red bar means without anybody
// explaining it.
//
// The idea comes from omarchy-lock-pokemon (MIT), but its version does
// something that will not do here: while charging, it runs a shine through the
// bar in an endless loop. That is exactly what law 7 of
// the rice's motion rules forbids -- "no shines running across anything".
// So charging is shown with the blink the spec ALREADY has registered as an
// exception (the recording indicator's: twice 130 ms every 2 s), and nothing
// new has to be invented or registered.

import QtQuick
import QtQuick.Layouts

Item {
    id: root

    // 0..100. Below zero means there is no battery (the tower), and then this
    // is not painted: an empty HP bar on a desktop computer reads as a fault,
    // not as information.
    property int nivel: -1
    property bool cargando: false
    property bool conEtiqueta: true
    // The control-centre strip writes at fsXXS and the panel at fsXS; it comes
    // in from outside so the bar adapts to its place and not the other way round.
    property int tamTexto: Appearance.fsXS

    // The colours do NOT come from pywal, on purpose. They are game semantics,
    // like the red of an error: if the wallpaper changes hue, low HP has to
    // stay red.
    readonly property color cBien: "#78c850"
    readonly property color cMedio: "#f8d030"
    readonly property color cMal: "#f04040"

    readonly property real fraccion: Math.max(0, Math.min(1, nivel / 100))
    readonly property color cRelleno: fraccion > 0.5 ? cBien
                                    : fraccion > 0.2 ? cMedio : cMal

    visible: nivel >= 0
    implicitHeight: Math.max(alto, etiqueta.implicitHeight)
    implicitWidth: 160

    readonly property int alto: 6

    RowLayout {
        anchors.fill: parent
        spacing: Appearance.gapS

        Text {
            id: etiqueta
            visible: root.conEtiqueta
            text: I18n.tr("PS")
            color: Colors.label3
            font.family: Appearance.fontUI
            font.pixelSize: root.tamTexto
            font.weight: Font.DemiBold
            Layout.alignment: Qt.AlignVCenter
        }

        Rectangle {
            id: riel
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            implicitHeight: root.alto
            radius: height / 2
            color: Colors.fill3

            Rectangle {
                id: relleno
                height: parent.height
                radius: parent.radius
                color: root.cRelleno

                // The FRACTION is animated, never the width. The panel widens
                // on a spring when it opens, so an animated width would spend
                // half a second chasing a geometry that is still moving --
                // the same reason the experience bar next to it is written
                // this way.
                property real p: root.fraccion
                width: Math.max(parent.height, parent.width * p)
                Behavior on p {
                    NumberAnimation { duration: Appearance.mTick; easing.type: Easing.OutCubic }
                }
                Behavior on color { ColorAnimation { duration: Appearance.mQuick } }

                // Charging: a blink, not a loop. It is the pattern the spec
                // already allows for the recording indicator, and here it says
                // the same thing -- "this is happening right now" -- at the
                // same near-zero cost.
                SequentialAnimation on opacity {
                    running: root.cargando && root.visible
                    loops: Animation.Infinite
                    NumberAnimation { to: 0.45; duration: Appearance.mQuick; easing.type: Easing.OutQuad }
                    NumberAnimation { to: 1.0;  duration: Appearance.mQuick; easing.type: Easing.OutQuad }
                    PauseAnimation { duration: 2000 - Appearance.mQuick * 2 }
                }
                // When charging stops the opacity has to be restored by hand,
                // because the animation stops wherever it was and would leave
                // it halfway. The event to listen for is 'cargando' (charging)
                // CHANGING, not the opacity changing: if the blink stops
                // halfway, the opacity never changes again, so an
                // onOpacityChanged would never get to run and the bar would
                // stay half-lit forever.
                Connections {
                    target: root
                    function onCargandoChanged() {
                        if (!root.cargando) relleno.opacity = 1
                    }
                }
            }
        }

        Text {
            text: root.nivel + "%"
            color: Colors.label3
            font.family: Appearance.fontUI
            font.pixelSize: root.tamTexto
            // Fixed-width figures: otherwise the bar shifts by itself going
            // from 99 to 100 and it looks as if something has moved.
            font.features: ({ "tnum": 1 })
            Layout.alignment: Qt.AlignVCenter
        }
    }
}
