// MediaControls.qml — reproductor flotante (MPRIS) con carátula, progreso y
// controles. Toggle por GlobalShortcut "media" (bind en hyprland.conf) o
// `hyprctl dispatch global quickshell:media`. La carátula aporta el acento y
// pywal queda como fallback cuando el reproductor no publica ninguna.
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import QtQuick
import QtQuick.Layouts
import QtQuick.Effects

Scope {
    id: root
    property bool open: false
    readonly property var player: ShellState.player
    readonly property color accent: ShellState.mediaAccent

    property real pos: 0
    property real len: (player && player.lengthSupported) ? player.length : 0
    Timer {
        interval: Appearance.mTick; repeat: true; running: root.open && root.player !== null
        onTriggered: root.pos = (root.player && root.player.positionSupported) ? root.player.position : 0
    }
    function fmt(sec) {
        if (!sec || sec < 0) return "0:00";
        var m = Math.floor(sec / 60), s = Math.floor(sec % 60);
        return m + ":" + (s < 10 ? "0" + s : s);
    }

    GlobalShortcut { name: "media"; description: "Toggle media controls"; onPressed: root.open = !root.open }
    HyprlandFocusGrab { windows: [win]; active: root.open; onCleared: root.open = false }

    PanelWindow {
        id: win
        // Solo en la pantalla que estas mirando, no siempre en la primera.
        screen: ShellState.focusedScreen
        visible: root.open
        color: "transparent"
        exclusiveZone: 0
        anchors { bottom: true; left: true; right: true }
        implicitHeight: card.implicitHeight + 40
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
        // Sin namespace no hay layerrule posible: es el asa por la que
        // Hyprland anima ESTA superficie y no todas por igual.
        WlrLayershell.namespace: "quickshell:media"

        Item {
            anchors.fill: parent
            focus: true
            Keys.onEscapePressed: root.open = false

            Rectangle {
                id: card
                width: 440
                anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 24 }
                implicitHeight: 148
                radius: Appearance.radL
                color: Colors.bg
                border.width: 1
                border.color: Qt.rgba(Colors.fg.r, Colors.fg.g, Colors.fg.b, 0.10)
                property real anim: root.open ? 1 : 0
                Behavior on anim { NumberAnimation { duration: Appearance.mInScale; easing.type: Easing.OutBack; easing.overshoot: Appearance.mInOvershoot } }
                opacity: anim
                transformOrigin: Item.Bottom
                scale: 0.92 + 0.08 * anim
                layer.enabled: true
                layer.effect: MultiEffect { shadowEnabled: true; shadowColor: "#000000"; shadowOpacity: 0.5; shadowBlur: 1.0; shadowVerticalOffset: 6; autoPaddingEnabled: true }

                MouseArea { anchors.fill: parent }

                RowLayout {
                    anchors { fill: parent; margins: 16 }
                    spacing: 16

                    // ---- carátula ----
                    Rectangle {
                        Layout.preferredWidth: 116; Layout.preferredHeight: 116
                        radius: Appearance.radM
                        color: Colors.bgAlt
                        clip: true
                        Image {
                            anchors.fill: parent
                            source: (root.player && root.player.trackArtUrl) ? root.player.trackArtUrl : ""
                            fillMode: Image.PreserveAspectCrop
                            visible: status === Image.Ready
                        }
                        StyledText {
                            anchors.centerIn: parent
                            visible: !(root.player && root.player.trackArtUrl)
                            text: Icons.volHigh
                            color: Colors.dim
                            font.pixelSize: 40
                        }
                        Rectangle {
                            anchors.fill: parent
                            radius: parent.radius
                            color: "transparent"
                            border.width: 2
                            border.color: root.accent
                            z: 2
                            Behavior on border.color { ColorAnimation { duration: Appearance.mIn; easing.type: Easing.OutCubic } }
                        }
                    }

                    // ---- info + progreso + controles ----
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 4
                        StyledText {
                            Layout.fillWidth: true
                            text: root.player ? (root.player.trackTitle || "Sin reproducción") : "Sin reproducción"
                            color: Colors.fg; font.pixelSize: Appearance.fsL; font.bold: true
                            elide: Text.ElideRight
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: root.player ? (root.player.trackArtist || "") : ""
                            color: Colors.dim; font.pixelSize: Appearance.fsM
                            elide: Text.ElideRight
                        }
                        Item { Layout.fillHeight: true }
                        // progreso
                        Rectangle {
                            id: prog
                            Layout.fillWidth: true; height: 6; radius: 3
                            color: Qt.rgba(Colors.fg.r, Colors.fg.g, Colors.fg.b, 0.15)
                            visible: root.len > 0
                            Rectangle {
                                height: parent.height; radius: 3
                                width: parent.width * Math.max(0, Math.min(1, root.len > 0 ? root.pos / root.len : 0))
                                color: root.accent
                                Behavior on color { ColorAnimation { duration: Appearance.mIn; easing.type: Easing.OutCubic } }
                                Behavior on width { NumberAnimation { duration: Appearance.mTick } }
                            }
                            MouseArea {
                                anchors.fill: parent; hoverEnabled: false
                                onPressed: function(m) {
                                    if (root.player && root.len > 0) root.player.position = (m.x / width) * root.len;
                                }
                            }
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            Layout.topMargin: 4
                            StyledText { text: root.fmt(root.pos); color: Colors.dim; font.pixelSize: Appearance.fsXS }
                            Item { Layout.fillWidth: true }
                            Repeater {
                                model: 3
                                StyledText {
                                    required property int index
                                    text: index === 0 ? Icons.prev : (index === 1 ? (root.player && root.player.isPlaying ? Icons.pause : Icons.play) : Icons.next)
                                    color: root.accent
                                    Behavior on color { ColorAnimation { duration: Appearance.mIn; easing.type: Easing.OutCubic } }
                                    font.pixelSize: 24
                                    Layout.leftMargin: 10
                                    MouseArea {
                                        anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            if (!root.player) return;
                                            if (index === 0) root.player.previous();
                                            else if (index === 1) { root.player.isPlaying ? root.player.pause() : root.player.play(); }
                                            else root.player.next();
                                        }
                                    }
                                }
                            }
                            Item { Layout.fillWidth: true }
                            StyledText { text: root.fmt(root.len); color: Colors.dim; font.pixelSize: Appearance.fsXS }
                        }
                    }
                }
            }
        }
    }
}
