// NotchSlider.qml — slider compacto (icono + barra + %) para el panel del notch.
// Colores fijos oscuros porque vive dentro del negro del notch; el relleno usa
// el acento de pywal que le pases.
import QtQuick
import QtQuick.Layouts

RowLayout {
    id: root
    property string icon: ""
    property real value: 0          // 0..100
    property color accent: "#61afef"
    signal moved(real v)
    signal iconClicked()

    // Se anima el VALOR, no el ancho. El ancho es derivado (carril x fracción):
    // si lo animas, cualquier cambio de tamaño del contenedor —el notch
    // expandiéndose al abrir el panel— hace que la barra persiga al carril con
    // retraso y se vea un rebote raro. Animando el valor, redimensionar es
    // instantáneo y solo se anima un cambio real de volumen o brillo.
    property real shown: root.value
    Behavior on shown {
        enabled: !drag.pressed
        NumberAnimation { duration: Appearance.mQuick; easing.type: Easing.OutCubic }
    }

    spacing: 10

    Text {
        text: root.icon
        color: iconMouse.containsMouse ? root.accent : "#ffffff"
        font.family: Appearance.font
        font.pixelSize: Appearance.fsM
        Layout.preferredWidth: 18
        Behavior on color { ColorAnimation { duration: Appearance.mQuick; easing.type: Easing.OutQuad } }
        MouseArea {
            id: iconMouse
            anchors.fill: parent; anchors.margins: -4
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.iconClicked()
        }
    }

    Rectangle {
        id: track
        Layout.fillWidth: true
        Layout.preferredHeight: 6
        radius: 3
        color: "#242424"

        Rectangle {
            id: fill
            width: track.width * Math.max(0, Math.min(1, root.shown / 100))
            height: parent.height
            radius: parent.radius
            color: root.accent
        }

        Rectangle {
            width: 11; height: 11; radius: 6
            color: "#ffffff"
            x: Math.max(0, Math.min(track.width - width, fill.width - width / 2))
            anchors.verticalCenter: parent.verticalCenter
            opacity: drag.containsMouse || drag.pressed ? 1 : 0
            scale: drag.pressed ? 1.15 : 1
            Behavior on opacity { NumberAnimation { duration: Appearance.mQuick; easing.type: Easing.OutCubic } }
            Behavior on scale { NumberAnimation { duration: Appearance.mQuick; easing.type: Easing.OutCubic } }
        }

        MouseArea {
            id: drag
            anchors.fill: parent
            anchors.margins: -8
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            function emit(x) { root.moved(Math.max(0, Math.min(100, ((x + 8) / track.width) * 100))); }
            onPressed: function (m) { emit(m.x); }
            onPositionChanged: function (m) { if (pressed) emit(m.x); }
            onWheel: function (w) { root.moved(Math.max(0, Math.min(100, root.value + (w.angleDelta.y > 0 ? 5 : -5)))); }
        }
    }

    Text {
        text: Math.round(root.shown) + "%"
        color: "#888888"
        Layout.preferredWidth: 34
        horizontalAlignment: Text.AlignRight
        font.family: Appearance.font
        font.pixelSize: 10
    }
}
