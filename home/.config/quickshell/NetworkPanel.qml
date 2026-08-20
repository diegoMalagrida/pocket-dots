// NetworkPanel.qml — selector de red, desplegado DESDE el notch.
//
// Sustituye al menú de rofi (~/.config/rofi/scripts/network-menu.sh). Habla
// directamente con NetworkManager vía Quickshell.Networking. Solo los perfiles
// WPA-Enterprise saltan al editor oficial: Quickshell aún no expone identidad,
// método EAP ni certificados. El escáner solo corre con este panel abierto.
import Quickshell
import Quickshell.Networking
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Item {
    id: root

    readonly property bool active: ShellState.panel === "network"
    // SSID cuya fila está desplegada pidiendo contraseña
    property string askingFor: ""
    property string errorFor: ""

    onActiveChanged: {
        if (root.active) keys.forceActiveFocus();
        else { root.askingFor = ""; root.errorFor = ""; }
    }

    MouseArea { anchors.fill: parent }

    // Sin esto el panel era una ratonera: la capa coge el teclado en exclusiva
    // (lo necesita el campo de contraseña) pero no había nada que atendiera las
    // teclas, así que Escape no cerraba y no se podía escribir en ninguna otra
    // ventana.
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

        // ─────────────── cabecera ───────────────
        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            Text {
                text: ShellState.netIcon
                color: ShellState.online ? Colors.accent : "#7d7d7d"
                font.family: Appearance.font; font.pixelSize: 18
            }
            ColumnLayout {
                spacing: 0
                Text {
                    text: "Red"
                    color: "#ffffff"
                    font.family: Appearance.fontUI; font.pixelSize: 13; font.weight: Font.DemiBold
                }
                Text {
                    // "Wi-Fi apagado" solo cuando hay una radio que ENCENDER.
                    // En un equipo sin adaptador esa frase invita a buscar el
                    // interruptor que la arregle, y no existe.
                    text: ShellState.wiredDev ? "Cable conectado"
                        : ShellState.wifiNet ? ShellState.wifiNet.name
                        : (ShellState.wifiOn || !ShellState.hasWifi) ? "Sin conexión" : "Wi-Fi apagado"
                    color: "#8a8a8a"
                    font.family: Appearance.fontUI; font.pixelSize: 11
                }
            }
            Item { Layout.fillWidth: true }

            // interruptor de wifi — solo si hay radio que encender
            Rectangle {
                visible: ShellState.hasWifi
                implicitWidth: 42; implicitHeight: 23
                radius: 12
                color: ShellState.wifiOn ? Colors.accent : Qt.rgba(1, 1, 1, 0.14)
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

        Rectangle { Layout.fillWidth: true; height: 1; color: "#1e1e1e" }

        // ─────────────── lista de redes ───────────────
        ListView {
            id: list
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: 4
            model: ShellState.wifiOn ? ShellState.wifiNetworks : []
            currentIndex: -1
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded; width: 4 }

            // Enter sobre la red marcada con el teclado
            function activateCurrent() {
                const n = list.model[list.currentIndex];
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
                     : (netMa.containsMouse || netRow.asking || netRow.index === list.currentIndex) ? Qt.rgba(1, 1, 1, 0.08)
                     : Qt.rgba(1, 1, 1, 0.04)
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
                            color: netRow.modelData.connected ? Colors.accent : "#cfcfcf"
                            font.family: Appearance.font; font.pixelSize: 15
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0
                            Text {
                                Layout.fillWidth: true
                                text: netRow.ssid
                                color: "#ffffff"; elide: Text.ElideRight
                                font.family: Appearance.fontUI; font.pixelSize: 12
                                font.weight: netRow.modelData.connected ? Font.DemiBold : Font.Normal
                            }
                            Text {
                                Layout.fillWidth: true
                                visible: text.length > 0
                                text: root.errorFor === netRow.ssid
                                    ? (netRow.enterprise ? "Revisa el perfil empresarial" : "Contraseña incorrecta")
                                    : netRow.modelData.stateChanging ? "Conectando…"
                                    : netRow.modelData.connected ? (netRow.enterprise ? "Conectado · Empresa" : "Conectado")
                                    : netRow.modelData.known ? (netRow.enterprise ? "Empresa · Guardada" : "Guardada")
                                    : netRow.enterprise ? "Empresa · EAP" : ""
                                color: root.errorFor === netRow.ssid ? Colors.crit
                                     : netRow.modelData.connected ? Colors.accent : "#7d7d7d"
                                elide: Text.ElideRight
                                font.family: Appearance.fontUI; font.pixelSize: 10
                            }
                        }

                        Text {
                            visible: netRow.secured
                            text: netRow.enterprise ? Icons.wifiLock : Icons.lock
                            color: netRow.enterprise ? "#9a9a9a" : "#6f6f6f"
                            font.family: Appearance.font; font.pixelSize: 11
                        }

                        // EAP no cabe de forma segura en un campo de contraseña:
                        // abre el perfil exacto para identidad, método y CA.
                        Text {
                            visible: netRow.enterprise
                            text: Icons.edit
                            color: editMa.containsMouse ? Colors.accent : "#777777"
                            font.family: Appearance.font; font.pixelSize: 12
                            MouseArea {
                                id: editMa
                                anchors.fill: parent; anchors.margins: -6
                                hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onClicked: ShellState.editEnterprise(netRow.modelData)
                            }
                        }

                        // desconectar / olvidar
                        Text {
                            visible: netMa.containsMouse && netRow.modelData.connected
                            text: "󰅖"
                            color: discMa.containsMouse ? Colors.crit : "#8a8a8a"
                            font.family: Appearance.font; font.pixelSize: 13
                            MouseArea {
                                id: discMa
                                anchors.fill: parent; anchors.margins: -6
                                hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onClicked: netRow.modelData.disconnect()
                            }
                        }
                    }

                    // ---- contraseña, desplegada en la propia fila ----
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
                            border.color: pskField.activeFocus ? Colors.accent : "#2a2a2a"
                            Behavior on border.color { ColorAnimation { duration: Appearance.mQuick; easing.type: Easing.OutQuad } }

                            TextField {
                                id: pskField
                                anchors { fill: parent; leftMargin: 11; rightMargin: 11 }
                                echoMode: TextInput.Password
                                placeholderText: "Contraseña"
                                color: "#ffffff"
                                placeholderTextColor: "#5e5e5e"
                                selectionColor: Colors.accent
                                font.family: Appearance.fontUI; font.pixelSize: 12
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
                                text: "Conectar"
                                color: okMa.containsMouse ? "#000000" : "#ffffff"
                                font.family: Appearance.fontUI; font.pixelSize: 11; font.weight: Font.Medium
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
                        // Guardada u abierta -> directo; EAP -> editor seguro;
                        // solo una red PSK nueva despliega un campo de clave.
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
            // Sin adaptador la lista está vacía PARA SIEMPRE, así que decir
            // "Buscando redes…" sería una espera que no termina nunca.
            text: !ShellState.hasWifi ? (ShellState.wiredDev ? "Este equipo va por cable" : "Este equipo no tiene Wi-Fi")
                : !ShellState.wifiOn ? "Wi-Fi apagado" : "Buscando redes…"
            color: "#5e5e5e"
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            font.family: Appearance.fontUI; font.pixelSize: 12
        }
    }
}
