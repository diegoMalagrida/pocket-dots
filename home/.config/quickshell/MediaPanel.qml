// MediaPanel.qml — reproductor vertical dentro del centro de control (Super+D).
//
// La composición sigue una sola columna: carátula protagonista, título y
// artista, progreso, controles y el espectro. Así el reproductor no se lee como
// una tarjeta horizontal encajada en el centro de control, sino como una cara
// propia dentro del panel expandido.
import QtQuick
import QtQuick.Effects
import QtQuick.Layouts

Item {
    id: root
    readonly property color accent: ShellState.mediaAccent

    // El fondo entero absorbe el clic para que un hueco entre controles no
    // llegue a ninguna acción que haya detrás del panel.
    MouseArea { anchors.fill: parent }

    ColumnLayout {
        anchors {
            fill: parent
            leftMargin: 22
            rightMargin: 22
            topMargin: 22
            bottomMargin: 18
        }
        spacing: 10

        // ── carátula circular ──────────────────────────────────────────────
        Item {
            id: artStage
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: 166
            Layout.preferredHeight: 166

            // Halo muy tenue: da profundidad sin convertir la carátula en una
            // rueda que gira ni competir con el visualizador de abajo.
            Rectangle {
                anchors.centerIn: parent
                width: 166; height: 166; radius: 83
                color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.10)
                scale: ShellState.player && ShellState.player.isPlaying ? 1 : 0.94
                opacity: ShellState.player && ShellState.player.isPlaying ? 1 : 0.45
                Behavior on scale { SpringAnimation { spring: Appearance.sprPanel; damping: Appearance.dmpPanel; epsilon: Appearance.eppScale } }
                Behavior on opacity { NumberAnimation { duration: Appearance.mIn; easing.type: Easing.OutCubic } }
                Behavior on color { ColorAnimation { duration: Appearance.mIn; easing.type: Easing.OutCubic } }
            }

            Rectangle {
                anchors.centerIn: parent
                width: 154; height: 154; radius: 77
                color: "#151515"
                border.width: 2
                border.color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.72)
                Behavior on border.color { ColorAnimation { duration: Appearance.mIn; easing.type: Easing.OutCubic } }
            }

            Image {
                id: coverImage
                anchors.centerIn: parent
                width: 146; height: 146
                source: (ShellState.player && ShellState.player.trackArtUrl)
                    ? ShellState.player.trackArtUrl : ""
                sourceSize.width: 292
                sourceSize.height: 292
                fillMode: Image.PreserveAspectCrop
                smooth: true
                mipmap: true
                asynchronous: true
                visible: false
            }

            // clip:true recorta a un rectángulo, aunque el padre tenga radius.
            // MultiEffect usa esta máscara real para que la portada sea un
            // círculo de verdad como en la referencia.
            Item {
                id: coverMask
                width: coverImage.width
                height: coverImage.height
                layer.enabled: true
                layer.smooth: true
                visible: false
                Rectangle { anchors.fill: parent; radius: width / 2 }
            }
            MultiEffect {
                anchors.fill: coverImage
                source: coverImage
                visible: coverImage.status === Image.Ready
                antialiasing: true
                maskEnabled: true
                maskSource: coverMask
                maskSpreadAtMin: 1.0
                maskThresholdMin: 0.5
                maskThresholdMax: 1.0
            }

            Text {
                anchors.centerIn: parent
                visible: coverImage.status !== Image.Ready
                text: "󰎈"
                color: root.accent
                font.family: Appearance.font
                font.pixelSize: 48
                Behavior on color { ColorAnimation { duration: Appearance.mIn; easing.type: Easing.OutCubic } }
            }
        }

        // ── tema y artista ────────────────────────────────────────────────
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2

            Text {
                Layout.fillWidth: true
                text: ShellState.player
                    ? (ShellState.player.trackTitle || I18n.tr("Sin reproducción"))
                    : I18n.tr("Sin reproducción")
                color: "#ffffff"
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                maximumLineCount: 2
                elide: Text.ElideRight
                font.family: Appearance.fontUI
                font.pixelSize: 16
                font.weight: Font.DemiBold
            }
            Text {
                Layout.fillWidth: true
                text: ShellState.player ? (ShellState.player.trackArtist || "") : ""
                color: "#8d8d8d"
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                font.family: Appearance.fontUI
                font.pixelSize: 12
            }
        }

        // ── progreso: discreto, pero se puede pulsar para buscar ──────────
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 25
            Layout.topMargin: 2

            Rectangle {
                id: seek
                anchors { left: parent.left; right: parent.right; top: parent.top; topMargin: 1 }
                height: 4; radius: 2
                color: "#2c2c2c"

                Rectangle {
                    height: parent.height
                    radius: parent.radius
                    width: ShellState.len > 0
                        ? seek.width * Math.max(0, Math.min(1, ShellState.pos / ShellState.len)) : 0
                    color: root.accent
                    Behavior on color { ColorAnimation { duration: Appearance.mIn; easing.type: Easing.OutCubic } }
                    Behavior on width { NumberAnimation { duration: Appearance.mTick } }
                }
                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -7
                    cursorShape: Qt.PointingHandCursor
                    onClicked: function (m) {
                        if (ShellState.player && ShellState.len > 0)
                            ShellState.player.position = (m.x / width) * ShellState.len;
                    }
                }
            }

            Text {
                anchors { left: parent.left; bottom: parent.bottom }
                text: ShellState.fmt(ShellState.pos)
                color: "#666666"
                font.family: Appearance.fontUI
                font.pixelSize: 9
                font.features: ({ "tnum": 1 })
            }
            Text {
                anchors { right: parent.right; bottom: parent.bottom }
                text: ShellState.fmt(ShellState.len)
                color: "#666666"
                font.family: Appearance.fontUI
                font.pixelSize: 9
                font.features: ({ "tnum": 1 })
            }
        }

        // ── anterior / pausa / siguiente ─────────────────────────────────
        Row {
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredHeight: 52
            spacing: 22

            Repeater {
                model: 3
                Item {
                    id: transport
                    required property int index
                    width: index === 1 ? 52 : 38
                    height: 52

                    Rectangle {
                        anchors.centerIn: parent
                        visible: transport.index === 1
                        width: 48; height: 48; radius: 24
                        color: transportMa.containsMouse
                            ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.34)
                            : Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.20)
                        scale: transportMa.pressed ? 0.90 : 1
                        Behavior on color { ColorAnimation { duration: Appearance.mQuick; easing.type: Easing.OutQuad } }
                        Behavior on scale { SpringAnimation { spring: Appearance.sprTight; damping: Appearance.dmpTight; epsilon: Appearance.eppScale } }
                    }

                    Text {
                        anchors.centerIn: parent
                        text: transport.index === 0 ? Icons.prev
                            : transport.index === 1
                                ? (ShellState.player && ShellState.player.isPlaying ? Icons.pause : Icons.play)
                                : Icons.next
                        color: transportMa.containsMouse ? root.accent : "#ffffff"
                        font.family: Appearance.font
                        font.pixelSize: transport.index === 1 ? 24 : 19
                        Behavior on color { ColorAnimation { duration: Appearance.mQuick; easing.type: Easing.OutQuad } }
                    }

                    MouseArea {
                        id: transportMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (!ShellState.player) return;
                            if (transport.index === 0) ShellState.player.previous();
                            else if (transport.index === 1)
                                ShellState.player.isPlaying ? ShellState.player.pause() : ShellState.player.play();
                            else ShellState.player.next();
                        }
                    }
                }
            }
        }

        // ── espectro: la "ilustración" viva al pie de la columna ─────────
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumHeight: 58

            Item {
                anchors.centerIn: parent
                width: ShellState.bands * 13 - 7
                height: 58

                Repeater {
                    model: ShellState.bands
                    Rectangle {
                        required property int index
                        x: index * 13
                        width: 6
                        radius: 3
                        antialiasing: true
                        color: root.accent
                        Behavior on color { ColorAnimation { duration: Appearance.mIn; easing.type: Easing.OutCubic } }
                        height: Math.max(6, 58 * (ShellState.levels[index] || 0))
                        y: (58 - height) / 2
                    }
                }
            }
        }
    }
}
