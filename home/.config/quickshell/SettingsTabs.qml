// ╭──────────────────────────────────────────────────────────────────────────╮
// │                                                                          │
// │   T A B   S T R I P                                                      │
// │   tabs within a settings page                                            │
// │                                                                          │
// │   github.com/andreumassanet/impasto                                      │
// │                                                                          │
// ╰──────────────────────────────────────────────────────────────────────────╯

import QtQuick
import QtQuick.Layouts

// Adapted for Diego’s rice from Impasto. GPL-3.0; original header retained.

// Pills naming the parts of a settings page, all visible, the current one
// filled. A page with a single part gets no strip.
Item {
    id: root

    // Entries of { id, label }.
    property var tabs: []
    property string current: ""

    signal picked(string id)

    Layout.fillWidth: true
    implicitHeight: root.tabs.length > 1 ? 30 : 0
    visible: root.tabs.length > 1

    Row {
        anchors.left: parent.left
        anchors.leftMargin: 2
        anchors.verticalCenter: parent.verticalCenter
        spacing: 4

        Repeater {
            model: root.tabs

            Rectangle {
                id: pill

                required property var modelData

                readonly property bool active: pill.modelData.id === root.current
                activeFocusOnTab: true
                Accessible.role: Accessible.PageTab
                Accessible.name: pill.modelData.label
                Accessible.selected: active
                Accessible.onPressAction: root.picked(pill.modelData.id)
                Keys.onSpacePressed: root.picked(pill.modelData.id)
                Keys.onReturnPressed: root.picked(pill.modelData.id)

                width: caption.implicitWidth + 24
                height: 26
                radius: height / 2
                color: pill.active ? Colors.accent
                    : (pillMouse.containsMouse ? Colors.fill2 : Colors.fill3)
                border.color: pill.active ? Colors.accent : Colors.hairline
                border.width: activeFocus ? 2 : 1

                Behavior on color { ColorAnimation { duration: Appearance.mQuick } }
                Behavior on border.color { ColorAnimation { duration: Appearance.mQuick } }

                Text {
                    id: caption

                    anchors.centerIn: parent
                    text: pill.modelData.label
                    font.family: Appearance.fontUI
                    font.pixelSize: Appearance.fsS
                    font.weight: pill.active ? Font.DemiBold : Font.Normal
                    // accentText, not bg: both come from the same pywal photo and with 5 of
                    // the 21 wallpapers the active tab dropped below 4.5:1 (see the block in
                    // Colors.qml). The token picks the theme's ink as long as it stays
                    // readable, so with most palettes this is still exactly `Colors.bg`.
                    color: pill.active ? Colors.accentText : Colors.label2

                    Behavior on color { ColorAnimation { duration: Appearance.mQuick } }
                }

                MouseArea {
                    id: pillMouse

                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.picked(pill.modelData.id)
                }
            }
        }
    }
}
