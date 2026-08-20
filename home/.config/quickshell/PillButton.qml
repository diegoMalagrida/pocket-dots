import QtQuick

Rectangle {
    id: root
    property string label: ""
    property bool active: false
    signal clicked()

    implicitHeight: 34
    radius: Appearance.radS
    color: mouse.containsMouse ? Colors.accent : (active ? Colors.accent2 : Qt.rgba(Colors.fg.r, Colors.fg.g, Colors.fg.b, 0.07))
    Behavior on color { ColorAnimation { duration: Appearance.animFast } }
    scale: mouse.pressed ? 0.96 : 1.0
    Behavior on scale { NumberAnimation { duration: Appearance.mQuick; easing.type: Easing.OutCubic } }

    StyledText {
        anchors.centerIn: parent
        text: root.label
        font.pixelSize: Appearance.fsS
        color: (mouse.containsMouse || root.active) ? Colors.bg : Colors.fg
    }
    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
