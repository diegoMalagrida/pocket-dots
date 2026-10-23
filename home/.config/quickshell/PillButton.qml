import QtQuick

Rectangle {
    id: root
    property string label: ""
    property bool active: false
    signal clicked()

    implicitHeight: 34
    radius: Appearance.radS
    color: mouse.containsMouse ? Colors.accent : (active ? Colors.accent2 : Colors.fill3)
    Behavior on color { ColorAnimation { duration: Appearance.animFast } }
    scale: mouse.pressed ? 0.96 : 1.0
    Behavior on scale { NumberAnimation { duration: Appearance.mQuick; easing.type: Easing.OutCubic } }

    StyledText {
        anchors.centerIn: parent
        text: root.label
        font.pixelSize: Appearance.fsS
        // Each state writes over a different fill, so each one needs its own ink:
        // hover sits on `accent`, active on `accent2` and rest on a veil of `fg`.
        // With `Colors.bg` for the first two, a palette whose background resembled
        // the accent left the label unreadable (see the block in Colors.qml).
        color: mouse.containsMouse ? Colors.accentText
             : (root.active ? Colors.accent2Text : Colors.fg)
    }
    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
