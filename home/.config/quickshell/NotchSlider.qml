// NotchSlider.qml — compact slider (icon + bar + %) for the notch panel.
// The ink and the rail come from the Colors tokens, so they are re-themed by
// pywal like everything else; the fill uses whatever accent you pass it.
import QtQuick
import QtQuick.Layouts

RowLayout {
    id: root
    property string icon: ""
    property real value: 0          // 0..100
    property color accent: Colors.accent
    signal moved(real v)
    signal iconClicked()

    // The VALUE is animated, not the width. The width is derived (track x
    // fraction): if you animate it, any change in the container's size —the
    // notch expanding as the panel opens— makes the bar chase the track with a
    // lag and you see an odd bounce. Animating the value, resizing is instant
    // and only a real change of volume or brightness gets animated.
    property real shown: root.value
    Behavior on shown {
        enabled: !drag.pressed
        NumberAnimation { duration: Appearance.mQuick; easing.type: Easing.OutCubic }
    }

    spacing: 10

    Text {
        text: root.icon
        color: iconMouse.containsMouse ? root.accent : Colors.label
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
        color: Colors.fill3

        Rectangle {
            id: fill
            width: track.width * Math.max(0, Math.min(1, root.shown / 100))
            height: parent.height
            radius: parent.radius
            color: root.accent
        }

        Rectangle {
            width: 11; height: 11; radius: 6
            color: Colors.label
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
        color: Colors.label3
        Layout.preferredWidth: 34
        horizontalAlignment: Text.AlignRight
        font.family: Appearance.font
        font.pixelSize: Appearance.fsXXS
    }
}
