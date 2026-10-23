// SettingsBluetooth.qml — bluetooth devices via Quickshell.Bluetooth (Bluez),
// replacing the rofi menu. Pair, connect, disconnect and forget.
//
// WHAT THIS VERSION FIXES: if the adapter is blocked by rfkill (which is how
// this laptop normally keeps it, for the battery), the screen said "Bluetooth
// off, turn it on with the switch" — and the switch did absolutely nothing,
// because with a soft-block Bluez ignores `enabled`. Now it says so plainly,
// the switch goes dead so as not to lie, and there is a button that runs
// `rfkill unblock` (the user has an ACL on /dev/rfkill, so no sudo is needed).
import Quickshell
import Quickshell.Bluetooth
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Flickable {
    id: root

    property string note: I18n.tr("Solo busca dispositivos mientras esta sección está abierta.")
    readonly property int matchCount: cAdapter.visibleRows + cPaired.visibleRows + cNearby.visibleRows

    contentHeight: col.implicitHeight + 34
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded; width: 5 }
    onVisibleChanged: {
        if (visible) contentY = 0;
        // discovery is governed by a single Binding in ShellState
        ShellState.btScanWanted = visible;
    }
    Component.onDestruction: ShellState.btScanWanted = false

    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property bool blocked: ShellState.btBlocked
    readonly property bool on_: root.adapter ? root.adapter.enabled : false

    ColumnLayout {
        id: col
        width: root.width - 48
        x: 24
        y: 16
        spacing: 10

        SettingsControls.Card_ {
            id: cAdapter
            title: I18n.tr("Adaptador")

            SettingsControls.Row_ {
                label: I18n.tr("Bluetooth")
                active: !root.blocked && root.adapter !== null
                hint: root.blocked
                    ? I18n.tr("No se puede encender: la radio está bloqueada por rfkill (soft-block). Desbloquéala abajo.")
                    : I18n.tr("Enciende o apaga el adaptador.")
                SettingsControls.Switch_ {
                    checked: root.on_
                    live: !root.blocked && root.adapter !== null
                    onToggled: function (v) { if (root.adapter) root.adapter.enabled = v; }
                }
            }

            SettingsControls.Action_ {
                shown: root.blocked
                label: I18n.tr("Desbloquear la radio")
                hint: I18n.tr("Ejecuta «rfkill unblock bluetooth». Suele estar bloqueada a propósito para ahorrar batería.")
                icon: "󰂲"
                value: "rfkill"
                onTriggered: Quickshell.execDetached(["rfkill", "unblock", "bluetooth"])
            }
        }

        SettingsControls.Note_ {
            Layout.topMargin: 4
            visible: !root.adapter
            text: I18n.tr("No hay ningún adaptador bluetooth en este equipo.")
        }

        // This state has to be explained without hovering: a switch that is
        // off and does not respond either looks like a broken app.
        SettingsControls.Note_ {
            Layout.topMargin: 4
            visible: root.blocked
            text: I18n.tr("La radio está bloqueada por rfkill (soft-block), así que Bluez ignora el interruptor. Suele estar así a propósito para ahorrar batería.")
        }

        SettingsControls.Card_ {
            id: cPaired
            title: I18n.tr("Mis dispositivos")

            Repeater {
                // Same as in BluetoothPanel: this section also asks for discovery
                // while it is open (btScanWanted), so the list rebuilds itself,
                // and with an array every row was recreated. onItemRemoved goes
                // through Qt.callLater on purpose: Qt emits that signal BEFORE
                // unparenting the row, so recount() would still count it and the
                // card would stay visible and empty when the last device left.
                // It did not show before because the array was a reset and the
                // last signal was always onItemAdded.
                model: ScriptModel {
                    values: ShellState.btPaired
                    comparisonMode: ObjectComparison.Identity
                }
                onItemAdded: cPaired.recount()
                onItemRemoved: Qt.callLater(cPaired.recount)
                DevRow {}
            }
        }

        SettingsControls.Card_ {
            id: cNearby
            title: I18n.tr("Disponibles")

            Repeater {
                model: ScriptModel {
                    values: root.on_ ? ShellState.btNearby : []
                    comparisonMode: ObjectComparison.Identity
                }
                onItemAdded: cNearby.recount()
                onItemRemoved: Qt.callLater(cNearby.recount)
                DevRow {}
            }
        }

        SettingsControls.Empty_ {
            Layout.topMargin: 4
            visible: ShellState.settingsQuery.length === 0
                && root.on_ && ShellState.btNearby.length === 0
            icon: "󰂯"
            title: I18n.tr("Buscando dispositivos")
            body: I18n.tr("Pon el equipo cerca y activa su modo de emparejamiento. Aparecerá aquí en cuanto Bluez lo encuentre.")
        }

        SettingsControls.Empty_ {
            Layout.topMargin: 4
            visible: ShellState.settingsQuery.length === 0 && !root.on_ && !root.blocked
                && root.adapter !== null && ShellState.btPaired.length === 0
            icon: "󰂲"
            title: I18n.tr("Bluetooth está apagado")
            body: I18n.tr("Enciéndelo arriba para buscar y emparejar dispositivos cercanos.")
        }
    }

    // ─────────────── device row ────────────────
    component DevRow: Rectangle {
        id: dev
        required property var modelData

        readonly property string name_: ShellState.btLabel(dev.modelData)
        readonly property string state_: dev.modelData.pairing ? I18n.tr("Emparejando…")
            : dev.modelData.connected
                ? (dev.modelData.batteryAvailable
                    ? I18n.tr("Conectado · {0} %", Math.round(dev.modelData.battery * 100))
                    : I18n.tr("Conectado"))
            : (dev.modelData.paired || dev.modelData.bonded) ? I18n.tr("Emparejado") : ""

        readonly property bool isSettingsRow: true
        readonly property bool matches: ShellState.settingsMatch(dev.name_, dev.modelData.address || "")
        function _recount() {
            let p = dev.parent;
            while (p) { if (p.isSettingsCard) { p.recount(); return; } p = p.parent; }
        }
        onMatchesChanged: dev._recount()
        Component.onCompleted: dev._recount()

        Layout.fillWidth: true
        Layout.preferredHeight: 44
        visible: dev.matches
        radius: Appearance.radS
        color: dev.modelData.connected ? Qt.rgba(Colors.accent.r, Colors.accent.g, Colors.accent.b, 0.18)
             : dMa.containsMouse ? Colors.fill2 : "transparent"
        Behavior on color { ColorAnimation { duration: Appearance.mQuick; easing.type: Easing.OutQuad } }

        RowLayout {
            anchors { fill: parent; leftMargin: 12; rightMargin: 12 }
            spacing: 12

            Text {
                text: dev.modelData.connected ? "󰂱" : "󰂯"
                color: dev.modelData.connected ? Colors.accentInk : Colors.label2
                font.family: Appearance.font
                font.pixelSize: 15
            }

            Text {
                Layout.fillWidth: true
                text: dev.name_
                color: Colors.label
                elide: Text.ElideRight
                font.family: Appearance.fontUI
                font.pixelSize: Appearance.fsS
                font.weight: dev.modelData.connected ? Font.Medium : Font.Normal
            }

            Text {
                visible: dev.state_.length > 0
                text: dev.state_
                color: dev.modelData.connected ? Colors.accentInk : Colors.label3
                font.family: Appearance.fontUI
                font.pixelSize: Appearance.fsXS
                font.features: ({ "tnum": 1 })   // the battery % refreshes by itself: keep it from jittering
            }

            // forget
            Text {
                visible: dMa.containsMouse && (dev.modelData.paired || dev.modelData.bonded)
                text: "󰩹"
                color: fMa.containsMouse ? Colors.crit : Colors.label3
                font.family: Appearance.font
                font.pixelSize: Appearance.fsM
                MouseArea {
                    id: fMa
                    anchors.fill: parent
                    anchors.margins: -6
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onEntered: ShellState.settingsHint = I18n.tr("Olvidar «{0}»: borra el emparejamiento.", dev.name_)
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
            onEntered: ShellState.settingsHint = dev.modelData.address
                ? dev.name_ + " · " + dev.modelData.address
                : dev.name_
            onExited: ShellState.settingsHint = ""
            onClicked: {
                const d = dev.modelData;
                if (d.connected) d.disconnect();
                else if (d.paired || d.bonded) d.connect();
                else d.pair();
            }
        }
    }
}
