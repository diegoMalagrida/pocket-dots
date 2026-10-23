// NetworkPanel.qml — network picker, unfolded FROM the notch.
//
// Replaces the rofi menu (~/.config/rofi/scripts/network-menu.sh). It talks
// straight to NetworkManager through Quickshell.Networking. Only WPA-Enterprise
// profiles jump to the official editor: Quickshell does not expose identity,
// EAP method or certificates yet. The scanner only runs with this panel open.
import Quickshell
import Quickshell.Networking
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Item {
    id: root

    readonly property bool active: ShellState.panel === "network"
    // One single source for the list: the ScriptModel below paints it and
    // the keyboard's Enter indexes it. If each one worked it out on its own,
    // it would only take one of them changing criteria for Enter to activate
    // a different network from the one highlighted.
    readonly property var nets: ShellState.wifiOn ? ShellState.wifiNetworks : []
    // SSID whose row is unfolded asking for a password
    property string askingFor: ""
    property string errorFor: ""

    onActiveChanged: {
        if (root.active) keys.forceActiveFocus();
        else { root.askingFor = ""; root.errorFor = ""; }
    }

    MouseArea { anchors.fill: parent }

    // Without this the panel was a mousetrap: the layer grabs the keyboard
    // exclusively (the password field needs it) but there was nothing handling the
    // keys, so Escape did not close it and you could not type in any other
    // window.
    Item {
        id: keys
        anchors.fill: parent
        focus: true
        Keys.onEscapePressed: function (e) {
            if (root.askingFor !== "") { root.askingFor = ""; root.errorFor = ""; }
            else ShellState.closePanel();
            e.accepted = true;
        }
        Keys.onDownPressed: if (list.count > 0) list.currentIndex = Math.min(list.count - 1, list.currentIndex + 1)
        Keys.onUpPressed: if (list.count > 0) list.currentIndex = Math.max(0, list.currentIndex - 1)
        Keys.onReturnPressed: list.activateCurrent()
        Keys.onEnterPressed: list.activateCurrent()
    }

    ColumnLayout {
        anchors { fill: parent; leftMargin: 22; rightMargin: 20; topMargin: 20; bottomMargin: 18 }
        spacing: 12

        // ─────────────── header ───────────────
        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            Text {
                text: ShellState.netIcon
                color: ShellState.online ? Colors.accentInk : Colors.label3
                font.family: Appearance.font; font.pixelSize: 18
            }
            ColumnLayout {
                spacing: 0
                Text {
                    text: I18n.tr("Red")
                    color: Colors.label
                    font.family: Appearance.fontUI; font.pixelSize: Appearance.fsM; font.weight: Font.DemiBold
                }
                Text {
                    // "Wi-Fi apagado" (Wi-Fi off) only when there is a radio to TURN ON.
                    // On a machine with no adapter that phrase invites you to look for
                    // the switch that fixes it, and there is none.
                    text: ShellState.wiredDev ? I18n.tr("Cable conectado")
                        : ShellState.wifiNet ? ShellState.wifiNet.name
                        : (ShellState.wifiOn || !ShellState.hasWifi) ? I18n.tr("Sin conexión") : I18n.tr("Wi-Fi apagado")
                    color: Colors.label2
                    font.family: Appearance.fontUI; font.pixelSize: Appearance.fsXS
                }
            }
            Item { Layout.fillWidth: true }

            // wifi switch — only if there is a radio to turn on
            Rectangle {
                visible: ShellState.hasWifi
                implicitWidth: 42; implicitHeight: 23
                radius: 12
                color: ShellState.wifiOn ? Colors.accent : Colors.fill1
                Behavior on color { ColorAnimation { duration: Appearance.mQuick; easing.type: Easing.OutQuad } }
                Rectangle {
                    width: 17; height: 17; radius: 9
                    color: "#ffffff"
                    y: 3
                    x: ShellState.wifiOn ? parent.width - width - 3 : 3
                    Behavior on x { NumberAnimation { duration: Appearance.mQuick; easing.type: Easing.OutCubic } }
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: ShellState.toggleWifi()
                }
            }
        }

        Rectangle { Layout.fillWidth: true; height: 1; color: Colors.hairline }

        // ─────────────── network list ───────────────
        ListView {
            id: list
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: 4
            // ScriptModel instead of the bare array. The scanner only runs with
            // this panel open, so the list was rebuilt every few seconds
            // UNDERNEATH whatever you were doing: with an array, every change is a
            // model reset and all the rows are destroyed, including the one with
            // the password field unfolded — it wiped your key halfway through
            // typing and took your focus away. The access points are the SAME
            // NetworkManager objects from one scan to the next, so by comparing
            // them by identity the row survives: a change of signal, order or
            // state moves or repaints the delegate instead of recreating it.
            model: ScriptModel {
                values: root.nets
                comparisonMode: ObjectComparison.Identity
            }
            currentIndex: -1
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded; width: 4 }

            // Enter on the network highlighted with the keyboard. It indexes
            // root.nets and NOT list.model: the model is no longer an array but a
            // ScriptModel, and `model[i]` would return undefined — Enter would not
            // connect to anything. With currentIndex at -1 (nothing highlighted)
            // it comes out undefined and the `if` below stops it, same as before.
            function activateCurrent() {
                const n = root.nets[list.currentIndex];
                if (!n || n.connected) return;
                root.errorFor = "";
                if (n.known || !ShellState.isSecured(n)) n.connect();
                else if (ShellState.isEnterprise(n)) ShellState.editEnterprise(n);
                else root.askingFor = n.name || "";
            }

            delegate: Rectangle {
                id: netRow
                required property var modelData
                required property int index

                readonly property string ssid: modelData.name || ""
                readonly property bool asking: root.askingFor === netRow.ssid
                readonly property bool secured: ShellState.isSecured(modelData)
                readonly property bool enterprise: ShellState.isEnterprise(modelData)

                width: list.width
                height: netRow.asking ? 88 : 44
                Behavior on height { NumberAnimation { duration: Appearance.mIn; easing.type: Easing.OutCubic } }
                radius: 12
                clip: true
                color: modelData.connected ? Qt.rgba(Colors.accent.r, Colors.accent.g, Colors.accent.b, 0.18)
                     : (netMa.containsMouse || netRow.asking || netRow.index === list.currentIndex) ? Colors.fill2
                     : Colors.fill3
                Behavior on color { ColorAnimation { duration: Appearance.mQuick; easing.type: Easing.OutQuad } }

                Connections {
                    target: netRow.modelData
                    ignoreUnknownSignals: true
                    function onConnectionFailed(reason) {
                        root.errorFor = netRow.ssid;
                        root.askingFor = netRow.secured && !netRow.enterprise ? netRow.ssid : "";
                    }
                    function onConnectedChanged() {
                        if (netRow.modelData.connected) { root.askingFor = ""; root.errorFor = ""; }
                    }
                }

                ColumnLayout {
                    anchors { fill: parent; leftMargin: 13; rightMargin: 12; topMargin: 0; bottomMargin: 8 }
                    spacing: 6

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 44
                        spacing: 11

                        Text {
                            text: ShellState.wifiIconFor(netRow.modelData.signalStrength || 0)
                            color: netRow.modelData.connected ? Colors.accentInk : Colors.label
                            font.family: Appearance.font; font.pixelSize: 15
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0
                            Text {
                                Layout.fillWidth: true
                                text: netRow.ssid
                                color: Colors.label; elide: Text.ElideRight
                                font.family: Appearance.fontUI; font.pixelSize: Appearance.fsS
                                font.weight: netRow.modelData.connected ? Font.DemiBold : Font.Normal
                            }
                            Text {
                                Layout.fillWidth: true
                                visible: text.length > 0
                                text: root.errorFor === netRow.ssid
                                    ? (netRow.enterprise ? I18n.tr("Revisa el perfil empresarial") : I18n.tr("Contraseña incorrecta"))
                                    : netRow.modelData.stateChanging ? I18n.tr("Conectando…")
                                    : netRow.modelData.connected ? (netRow.enterprise ? I18n.tr("Conectado · Empresa") : I18n.tr("Conectado"))
                                    : netRow.modelData.known ? (netRow.enterprise ? I18n.tr("Empresa · Guardada") : I18n.tr("Guardada"))
                                    : netRow.enterprise ? I18n.tr("Empresa · EAP") : ""
                                color: root.errorFor === netRow.ssid ? Colors.crit
                                     : netRow.modelData.connected ? Colors.accentInk : Colors.label2
                                elide: Text.ElideRight
                                font.family: Appearance.fontUI; font.pixelSize: Appearance.fsXXS
                            }
                        }

                        Text {
                            visible: netRow.secured
                            text: netRow.enterprise ? Icons.wifiLock : Icons.lock
                            // One single weight for both padlocks: the glyph already
                            // tells enterprise from PSK, and two different greys in
                            // the same column only made the line uneven.
                            color: Colors.label3
                            font.family: Appearance.font; font.pixelSize: Appearance.fsXS
                        }

                        // EAP does not fit safely in a password field: it opens
                        // the exact profile for identity, method and CA.
                        Text {
                            visible: netRow.enterprise
                            text: Icons.edit
                            color: editMa.containsMouse ? Colors.accentInk : Colors.label3
                            font.family: Appearance.font; font.pixelSize: Appearance.fsS
                            MouseArea {
                                id: editMa
                                anchors.fill: parent; anchors.margins: -6
                                hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onClicked: ShellState.editEnterprise(netRow.modelData)
                            }
                        }

                        // disconnect / forget
                        Text {
                            visible: netMa.containsMouse && netRow.modelData.connected
                            text: "󰅖"
                            color: discMa.containsMouse ? Colors.crit : Colors.label3
                            font.family: Appearance.font; font.pixelSize: Appearance.fsM
                            MouseArea {
                                id: discMa
                                anchors.fill: parent; anchors.margins: -6
                                hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onClicked: netRow.modelData.disconnect()
                            }
                        }
                    }

                    // ---- password, unfolded in the row itself ----
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 30
                        visible: netRow.asking
                        spacing: 8

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 30
                            radius: 9
                            color: Qt.rgba(0, 0, 0, 0.45)
                            border.width: 1
                            border.color: pskField.activeFocus ? Colors.accent : Colors.hairline
                            Behavior on border.color { ColorAnimation { duration: Appearance.mQuick; easing.type: Easing.OutQuad } }

                            TextField {
                                id: pskField
                                anchors { fill: parent; leftMargin: 11; rightMargin: 11 }
                                echoMode: TextInput.Password
                                placeholderText: I18n.tr("Contraseña")
                                color: Colors.label
                                placeholderTextColor: Colors.label4
                                selectionColor: Colors.accent
                                font.family: Appearance.fontUI; font.pixelSize: Appearance.fsS
                                background: null
                                padding: 0
                                verticalAlignment: TextInput.AlignVCenter

                                onVisibleChanged: if (visible) forceActiveFocus()
                                Keys.onEscapePressed: { root.askingFor = ""; root.errorFor = ""; }
                                Keys.onReturnPressed: netRow.tryConnect()
                                Keys.onEnterPressed: netRow.tryConnect()
                            }
                        }

                        Rectangle {
                            Layout.preferredWidth: 74; Layout.preferredHeight: 30
                            radius: 9
                            color: okMa.containsMouse ? Colors.accent : Qt.rgba(Colors.accent.r, Colors.accent.g, Colors.accent.b, 0.28)
                            Behavior on color { ColorAnimation { duration: Appearance.mQuick; easing.type: Easing.OutQuad } }
                            Text {
                                anchors.centerIn: parent
                                text: I18n.tr("Conectar")
                                // On hover the fill is the full accent, so the ink is
                                // decided by inkOn(accent) and not by a fixed black.
                                color: okMa.containsMouse ? Colors.accentText : Colors.label
                                font.family: Appearance.fontUI; font.pixelSize: Appearance.fsXS; font.weight: Font.Medium
                            }
                            MouseArea {
                                id: okMa
                                anchors.fill: parent
                                hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onClicked: netRow.tryConnect()
                            }
                        }
                    }
                }

                function tryConnect() {
                    root.errorFor = "";
                    if (netRow.enterprise && !netRow.modelData.known) {
                        ShellState.editEnterprise(netRow.modelData);
                    } else if (netRow.secured && !netRow.modelData.known) netRow.modelData.connectWithPsk(pskField.text);
                    else netRow.modelData.connect();
                    root.askingFor = "";
                }

                MouseArea {
                    id: netMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    z: -1
                    onClicked: {
                        if (netRow.modelData.connected) return;
                        root.errorFor = "";
                        // Saved or open -> straight away; EAP -> safe editor;
                        // only a new PSK network unfolds a key field.
                        if (netRow.modelData.known || !netRow.secured) netRow.modelData.connect();
                        else if (netRow.enterprise) ShellState.editEnterprise(netRow.modelData);
                        else root.askingFor = netRow.asking ? "" : netRow.ssid;
                    }
                }
            }
        }

        Text {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: !ShellState.wifiOn || ShellState.wifiNetworks.length === 0
            // With no adapter the list is empty FOREVER, so saying
            // "Buscando redes…" (searching for networks) would be a wait that never ends.
            text: !ShellState.hasWifi ? (ShellState.wiredDev ? I18n.tr("Este equipo va por cable") : I18n.tr("Este equipo no tiene Wi-Fi"))
                : !ShellState.wifiOn ? I18n.tr("Wi-Fi apagado") : I18n.tr("Buscando redes…")
            color: Colors.label3
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            font.family: Appearance.fontUI; font.pixelSize: Appearance.fsS
        }
    }
}
