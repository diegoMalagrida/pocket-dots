// BluetoothPanel.qml — dispositivos bluetooth, desplegado DESDE el notch.
// Hermano de NetworkPanel: mismo esqueleto (cabecera + interruptor + lista) y
// mismo trato desde el centro de control. Habla con Bluez vía
// Quickshell.Bluetooth, sin scripts. El descubrimiento solo corre mientras este
// panel está abierto (ver ShellState.onPanelChanged).
import Quickshell
import Quickshell.Bluetooth
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Item {
    id: root

    readonly property bool active: ShellState.panel === "bluetooth"
    readonly property var adapter: ShellState.btAdapter

    onActiveChanged: if (root.active) keys.forceActiveFocus()

    MouseArea { anchors.fill: parent }

    // Todo panel debe atender Escape (ver la nota en TopShell).
    Item {
        id: keys
        anchors.fill: parent
        focus: true
        Keys.onEscapePressed: function (e) { ShellState.closePanel(); e.accepted = true; }
    }

    ColumnLayout {
        anchors { fill: parent; leftMargin: 22; rightMargin: 20; topMargin: 20; bottomMargin: 18 }
        spacing: 12

        // ─────────────── cabecera ───────────────
        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            Text {
                text: ShellState.btIcon
                color: ShellState.btConnected > 0 ? Colors.accent : (ShellState.btOn ? "#cfcfcf" : "#7d7d7d")
                font.family: Appearance.font; font.pixelSize: 18
            }
            ColumnLayout {
                spacing: 0
                Text {
                    text: "Bluetooth"
                    color: "#ffffff"
                    font.family: Appearance.fontUI; font.pixelSize: 13; font.weight: Font.DemiBold
                }
                Text {
                    text: !root.adapter ? "Sin adaptador"
                        : ShellState.btBlocked ? "Bloqueado por rfkill"
                        : !ShellState.btOn ? "Apagado"
                        : ShellState.btConnected > 0
                            ? ShellState.btLabel(ShellState.btPaired[0])
                            : "Sin conexión"
                    color: "#8a8a8a"; elide: Text.ElideRight
                    font.family: Appearance.fontUI; font.pixelSize: 11
                }
            }
            Item { Layout.fillWidth: true }

            Rectangle {
                implicitWidth: 42; implicitHeight: 23
                radius: 12
                opacity: ShellState.btBlocked ? 0.4 : 1
                color: ShellState.btOn ? Colors.accent : Qt.rgba(1, 1, 1, 0.14)
                Behavior on color { ColorAnimation { duration: Appearance.mQuick; easing.type: Easing.OutQuad } }
                Rectangle {
                    width: 17; height: 17; radius: 9
                    color: "#ffffff"
                    y: 3
                    x: ShellState.btOn ? parent.width - width - 3 : 3
                    Behavior on x { NumberAnimation { duration: Appearance.mQuick; easing.type: Easing.OutCubic } }
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    enabled: !ShellState.btBlocked
                    onClicked: ShellState.toggleBt()
                }
            }
        }

        Rectangle { Layout.fillWidth: true; height: 1; color: "#1e1e1e" }

        // ─────────────── listas ───────────────
        Flickable {
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            contentHeight: lists.implicitHeight
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded; width: 4 }

            ColumnLayout {
                id: lists
                width: parent.width
                spacing: 4

                Text {
                    Layout.fillWidth: true
                    Layout.topMargin: 4
                    visible: ShellState.btPaired.length > 0
                    text: "MIS DISPOSITIVOS"
                    color: Colors.accent
                    font.family: Appearance.fontUI; font.pixelSize: 10
                    font.weight: Font.DemiBold; font.letterSpacing: 0.6
                }
                Repeater { model: ShellState.btPaired; BtRow {} }

                Text {
                    Layout.fillWidth: true
                    Layout.topMargin: 10
                    visible: ShellState.btOn && ShellState.btNearby.length > 0
                    text: "DISPONIBLES"
                    color: Colors.accent
                    font.family: Appearance.fontUI; font.pixelSize: 10
                    font.weight: Font.DemiBold; font.letterSpacing: 0.6
                }
                Repeater { model: ShellState.btOn ? ShellState.btNearby : []; BtRow {} }
            }
        }

        Text {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: !ShellState.btOn || (ShellState.btPaired.length === 0 && ShellState.btNearby.length === 0)
            text: !root.adapter ? "No hay adaptador bluetooth"
                : ShellState.btBlocked ? "El adaptador está bloqueado por rfkill.\nDesbloquéalo con:  rfkill unblock bluetooth"
                : !ShellState.btOn ? "Bluetooth apagado"
                : "Buscando dispositivos…"
            color: "#5e5e5e"
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            lineHeight: 1.5
            font.family: Appearance.fontUI; font.pixelSize: 12
        }
    }

    // ─────────── fila de dispositivo ───────────
    component BtRow: Rectangle {
        id: dev
        required property var modelData

        Layout.fillWidth: true
        Layout.preferredHeight: 46
        radius: 12
        color: dev.modelData.connected ? Qt.rgba(Colors.accent.r, Colors.accent.g, Colors.accent.b, 0.18)
             : dMa.containsMouse ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(1, 1, 1, 0.04)
        Behavior on color { ColorAnimation { duration: Appearance.mQuick; easing.type: Easing.OutQuad } }

        RowLayout {
            anchors { fill: parent; leftMargin: 13; rightMargin: 12 }
            spacing: 11

            Text {
                text: dev.modelData.connected ? "󰂱" : "󰂯"
                color: dev.modelData.connected ? Colors.accent : "#cfcfcf"
                font.family: Appearance.font; font.pixelSize: 15
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                Text {
                    Layout.fillWidth: true
                    text: ShellState.btLabel(dev.modelData)
                    color: "#ffffff"; elide: Text.ElideRight
                    font.family: Appearance.fontUI; font.pixelSize: 12
                    font.weight: dev.modelData.connected ? Font.DemiBold : Font.Normal
                }
                Text {
                    Layout.fillWidth: true
                    visible: text.length > 0
                    text: dev.modelData.pairing ? "Emparejando…"
                        : dev.modelData.connected
                            ? (dev.modelData.batteryAvailable ? "Conectado · " + Math.round(dev.modelData.battery * 100) + " %" : "Conectado")
                        : (dev.modelData.paired || dev.modelData.bonded) ? "Emparejado" : ""
                    color: dev.modelData.connected ? Colors.accent : "#7d7d7d"
                    elide: Text.ElideRight
                    font.family: Appearance.fontUI; font.pixelSize: 10
                }
            }

            Text {
                visible: dMa.containsMouse && (dev.modelData.paired || dev.modelData.bonded)
                text: "󰩹"
                color: fMa.containsMouse ? Colors.crit : "#7d7d7d"
                font.family: Appearance.font; font.pixelSize: 13
                MouseArea {
                    id: fMa
                    anchors.fill: parent; anchors.margins: -6
                    hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                    onClicked: dev.modelData.forget()
                }
            }
        }

        MouseArea {
            id: dMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            z: -1
            onClicked: {
                const d = dev.modelData;
                if (d.connected) d.disconnect();
                else if (d.paired || d.bonded) d.connect();
                else d.pair();
            }
        }
    }
}
