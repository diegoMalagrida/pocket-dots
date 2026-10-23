// BluetoothPanel.qml — bluetooth devices, unfolded FROM the notch.
// Sibling of NetworkPanel: same skeleton (header + switch + list) and the same
// treatment from the Control Centre. It talks to Bluez through
// Quickshell.Bluetooth, with no scripts. Discovery only runs while this panel
// is open (see ShellState.onPanelChanged).
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

    // Every panel must handle Escape (see the note in TopShell).
    Item {
        id: keys
        anchors.fill: parent
        focus: true
        Keys.onEscapePressed: function (e) { ShellState.closePanel(); e.accepted = true; }
    }

    ColumnLayout {
        anchors { fill: parent; leftMargin: 22; rightMargin: 20; topMargin: 20; bottomMargin: 18 }
        spacing: 12

        // ─────────────── header ───────────────
        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            Text {
                text: ShellState.btIcon
                color: ShellState.btConnected > 0 ? Colors.accentInk : (ShellState.btOn ? Colors.label : Colors.label3)
                font.family: Appearance.font; font.pixelSize: 18
            }
            ColumnLayout {
                spacing: 0
                Text {
                    text: I18n.tr("Bluetooth")
                    color: Colors.label
                    font.family: Appearance.fontUI; font.pixelSize: Appearance.fsM; font.weight: Font.DemiBold
                }
                Text {
                    text: !root.adapter ? I18n.tr("Sin adaptador")
                        : ShellState.btBlocked ? I18n.tr("Bloqueado por rfkill")
                        : !ShellState.btOn ? I18n.tr("Apagado")
                        : ShellState.btConnected > 0
                            ? ShellState.btLabel(ShellState.btPaired[0])
                            : I18n.tr("Sin conexión")
                    color: Colors.label2; elide: Text.ElideRight
                    font.family: Appearance.fontUI; font.pixelSize: Appearance.fsXS
                }
            }
            Item { Layout.fillWidth: true }

            Rectangle {
                implicitWidth: 42; implicitHeight: 23
                radius: 12
                opacity: ShellState.btBlocked ? 0.4 : 1
                color: ShellState.btOn ? Colors.accent : Colors.fill1
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

        Rectangle { Layout.fillWidth: true; height: 1; color: Colors.hairline }

        // ─────────────── lists ───────────────
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
                    text: I18n.tr("Mis dispositivos")
                    color: Colors.accentInk
                    font.family: Appearance.fontUI; font.pixelSize: Appearance.fsXXS
                    font.weight: Font.DemiBold
                }
                // ScriptModel: while this panel is open Bluez discovers
                // non-stop and these two lists are rebuilt from scratch. With an
                // array that recreated ALL the rows on every sweep (flicker, and
                // the bin's hover staying lit over a row that is now a different
                // one). The devices are the same Bluez objects between sweeps,
                // so by identity.
                Repeater {
                    model: ScriptModel {
                        values: ShellState.btPaired
                        comparisonMode: ObjectComparison.Identity
                    }
                    BtRow {}
                }

                Text {
                    Layout.fillWidth: true
                    Layout.topMargin: 10
                    visible: ShellState.btOn && ShellState.btNearby.length > 0
                    text: I18n.tr("Disponibles")
                    color: Colors.accentInk
                    font.family: Appearance.fontUI; font.pixelSize: Appearance.fsXXS
                    font.weight: Font.DemiBold
                }
                Repeater {
                    model: ScriptModel {
                        values: ShellState.btOn ? ShellState.btNearby : []
                        comparisonMode: ObjectComparison.Identity
                    }
                    BtRow {}
                }
            }
        }

        Text {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: !ShellState.btOn || (ShellState.btPaired.length === 0 && ShellState.btNearby.length === 0)
            text: !root.adapter ? I18n.tr("No hay adaptador bluetooth")
                : ShellState.btBlocked
                    ? I18n.tr("El adaptador está bloqueado por rfkill.")
                        + "\n" + I18n.tr("Desbloquéalo con:  rfkill unblock bluetooth")
                : !ShellState.btOn ? I18n.tr("Bluetooth apagado")
                : I18n.tr("Buscando dispositivos…")
            color: Colors.label3
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            lineHeight: 1.5
            font.family: Appearance.fontUI; font.pixelSize: Appearance.fsS
        }
    }

    // ─────────── device row ───────────
    component BtRow: Rectangle {
        id: dev
        required property var modelData

        Layout.fillWidth: true
        Layout.preferredHeight: 46
        radius: 12
        color: dev.modelData.connected ? Qt.rgba(Colors.accent.r, Colors.accent.g, Colors.accent.b, 0.18)
             : dMa.containsMouse ? Colors.fill2 : Colors.fill3
        Behavior on color { ColorAnimation { duration: Appearance.mQuick; easing.type: Easing.OutQuad } }

        RowLayout {
            anchors { fill: parent; leftMargin: 13; rightMargin: 12 }
            spacing: 11

            Text {
                text: dev.modelData.connected ? "󰂱" : "󰂯"
                color: dev.modelData.connected ? Colors.accentInk : Colors.label
                font.family: Appearance.font; font.pixelSize: 15
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                Text {
                    Layout.fillWidth: true
                    text: ShellState.btLabel(dev.modelData)
                    color: Colors.label; elide: Text.ElideRight
                    font.family: Appearance.fontUI; font.pixelSize: Appearance.fsS
                    font.weight: dev.modelData.connected ? Font.DemiBold : Font.Normal
                }
                Text {
                    Layout.fillWidth: true
                    visible: text.length > 0
                    text: dev.modelData.pairing ? I18n.tr("Emparejando…")
                        : dev.modelData.connected
                            ? (dev.modelData.batteryAvailable
                                ? I18n.tr("Conectado · {0} %", Math.round(dev.modelData.battery * 100))
                                : I18n.tr("Conectado"))
                        : (dev.modelData.paired || dev.modelData.bonded) ? I18n.tr("Emparejado") : ""
                    color: dev.modelData.connected ? Colors.accentInk : Colors.label2
                    elide: Text.ElideRight
                    font.family: Appearance.fontUI; font.pixelSize: Appearance.fsXXS
                    font.features: ({ "tnum": 1 })   // the battery % refreshes by itself: keep it from jiggling
                }
            }

            Text {
                visible: dMa.containsMouse && (dev.modelData.paired || dev.modelData.bonded)
                text: "󰩹"
                color: fMa.containsMouse ? Colors.crit : Colors.label3
                font.family: Appearance.font; font.pixelSize: Appearance.fsM
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
