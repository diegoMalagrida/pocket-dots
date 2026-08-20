// ControlPanel.qml — el centro de control, desplegado DESDE el notch.
//
// Sustituye al "control center" de swaync (que era una ventana GTK suya y por
// eso no se podía meter aquí dentro). Izquierda: reproductor vertical. Centro:
// sliders y conmutadores. Derecha: el historial de notificaciones, servido por
// nuestro propio NotificationServer (ver ShellState.qml).
import Quickshell
import Quickshell.Services.Notifications
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Item {
    id: root

    // absorbe clics en el hueco para que no cierren el panel
    MouseArea { anchors.fill: parent }

    RowLayout {
        anchors { fill: parent; leftMargin: 24; rightMargin: 22; topMargin: 20; bottomMargin: 20 }
        spacing: 20

        // ═════════════ izquierda: reproductor vertical ═════════════
        // Es el reproductor de la referencia, pero DENTRO de Super+D: comparte
        // la misma superficie y el mismo cierre por clic fuera que el resto del
        // centro de control.
        MediaPanel {
            Layout.preferredWidth: 260
            Layout.fillHeight: true
        }

        Rectangle { Layout.fillHeight: true; width: 1; color: "#1e1e1e" }

        // ═════════════════ centro: controles ═════════════════
        ColumnLayout {
            Layout.preferredWidth: 410
            Layout.fillHeight: true
            spacing: 14

            // ---- sliders ----
            NotchSlider {
                Layout.fillWidth: true
                icon: ShellState.muted ? Icons.volMute : Icons.volHigh
                value: ShellState.muted ? 0 : ShellState.vol
                accent: Colors.accent
                onMoved: function (v) { ShellState.setVolume(v); }
                onIconClicked: ShellState.toggleMute()
            }
            // En un equipo sin panel interno (una torre) no hay ningún
            // /sys/class/backlight, brightnessctl no encuentra nada y `bright`
            // se queda en -1 para siempre. El slider salía igualmente: a cero,
            // inmóvil y sin efecto. Un mando que no manda nada miente sobre lo
            // que puedes hacer, así que la fila desaparece entera y el volumen
            // se queda solo. Al ser un ColumnLayout, un item invisible no ocupa
            // sitio y el hueco se cierra solo (mismo criterio que Ajustes, que
            // ya escondía su fila de brillo con `shown`).
            NotchSlider {
                visible: ShellState.bright >= 0
                Layout.fillWidth: true
                icon: Icons.brightness
                value: Math.max(0, ShellState.bright)
                accent: Colors.warn
                onMoved: function (v) { ShellState.setBrightness(v); }
            }

            // ---- conmutadores ----
            GridLayout {
                Layout.fillWidth: true
                Layout.topMargin: 2
                columns: 5
                columnSpacing: 10

                // Una sola diana por tarjeta. Si tiene panel dedicado, cualquier
                // clic abre ese panel; su interruptor vive ya en la cabecera de
                // Red/Bluetooth. Los demás conmutadores sí actúan aquí mismo.
                component Toggle: Rectangle {
                    id: tg
                    property string icon: ""
                    property string label: ""
                    property bool on: false
                    property string panel: ""      // "" = sin panel dedicado
                    property int idx: 0            // su turno en la cascada
                    signal activated()

                    Layout.fillWidth: true
                    Layout.preferredHeight: 58

                    // CASCADA. Los seis aparecian a la vez, que es lo mismo que
                    // decir que no aparecian: un bloque que se enciende no tiene
                    // direccion y no se puede seguir con la vista. Escalonados,
                    // el ojo los recorre de izquierda a derecha y el panel se
                    // lee como algo que se despliega.
                    //
                    // OJO: aqui NO se toca la opacidad. El fundido ya lo hace
                    // el NotchLayer que contiene este panel, y dos opacidades
                    // encadenadas se multiplican: no se ve mas suave, se ve que
                    // llega tarde. La capa se encarga de aparecer; la cascada,
                    // solo de colocarse. Un gesto, un dueno.
                    property real ent: ShellState.mode === "control" ? 1 : 0
                    Behavior on ent {
                        SequentialAnimation {
                            PauseAnimation { duration: ShellState.mode === "control" ? tg.idx * 32 : 0 }
                            SpringAnimation {
                                spring: Appearance.sprPanel
                                damping: Appearance.dmpPanel
                                epsilon: Appearance.eppScale
                            }
                        }
                    }
                    scale: 0.82 + 0.18 * tg.ent
                    transform: Translate { y: (1 - tg.ent) * 12 }
                    radius: 14
                    color: tg.on ? Qt.rgba(Colors.accent.r, Colors.accent.g, Colors.accent.b, 0.26)
                         : tgMa.containsMouse ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(1, 1, 1, 0.05)
                    Behavior on color { ColorAnimation { duration: Appearance.mQuick; easing.type: Easing.OutQuad } }

                    ColumnLayout {
                        anchors.centerIn: parent
                        spacing: 1
                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            text: tg.icon
                            color: tg.on ? Colors.accent : "#cfcfcf"
                            font.family: Appearance.font; font.pixelSize: 16
                        }
                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            text: tg.label
                            color: tg.on ? Colors.accent : "#8a8a8a"
                            font.family: Appearance.fontUI; font.pixelSize: 9
                        }
                    }
                    MouseArea {
                        id: tgMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (tg.panel.length > 0) ShellState.togglePanel(tg.panel);
                            else tg.activated();
                        }
                    }
                }

                Toggle {
                    icon: ShellState.netIcon; label: "Red"; idx: 0
                    on: ShellState.online
                    panel: "network"
                }
                Toggle {
                    icon: ShellState.btIcon; label: "Bluetooth"; idx: 1
                    on: ShellState.btOn
                    panel: "bluetooth"
                }
                Toggle {
                    icon: ShellState.dnd ? "󰂛" : "󰂚"; label: "No molestar"; idx: 2
                    on: ShellState.dnd
                    onActivated: ShellState.dnd = !ShellState.dnd
                }
                Toggle {
                    icon: Icons.coffee; label: "Cafeína"; idx: 3
                    on: ShellState.caffeine
                    onActivated: ShellState.caffeine = !ShellState.caffeine
                }
                Toggle {
                    icon: Icons.moon; label: "Luz noct."; idx: 4
                    on: ShellState.nightLight
                    onActivated: ShellState.toggleNightLight()
                }
                Toggle {
                    icon: Icons.remote; label: "Remoto"; idx: 5
                    on: ShellState.remoteMode
                    onActivated: ShellState.toggleRemoteMode()
                }
                Toggle {
                    icon: Icons.pokeball; label: "Pokémon"; idx: 6
                    on: ShellState.pokeTheme
                    onActivated: ShellState.togglePokeTheme()
                }
            }

            Item { Layout.fillHeight: true }

            // ---- tiempo + sistema (heredado del Sidebar retirado) ----
            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: 2
                spacing: 16

                Text {
                    text: Icons.brightness
                    color: Colors.warn
                    font.family: Appearance.font; font.pixelSize: 14
                }
                Text {
                    Layout.fillWidth: true
                    text: ShellState.weather
                    color: "#b0b0b0"; elide: Text.ElideRight
                    font.family: Appearance.fontUI; font.pixelSize: 11
                }
                // Los tres glifos con porcentajes eran indescifrables sin saber
                // de memoria qué significaba cada uno. Ahora esto es una puerta
                // con nombre: conserva el vistazo rápido y abre las gráficas.
                Rectangle {
                    id: performanceLink
                    Layout.preferredWidth: 222
                    Layout.preferredHeight: 42
                    radius: 13
                    color: performanceMa.containsMouse
                        ? Qt.rgba(Colors.accent.r, Colors.accent.g, Colors.accent.b, 0.14)
                        : Qt.rgba(1, 1, 1, 0.05)
                    border.width: 1
                    border.color: performanceMa.containsMouse
                        ? Qt.rgba(Colors.accent.r, Colors.accent.g, Colors.accent.b, 0.26)
                        : Qt.rgba(1, 1, 1, 0.06)
                    Behavior on color { ColorAnimation { duration: Appearance.mQuick; easing.type: Easing.OutQuad } }

                    RowLayout {
                        anchors { fill: parent; leftMargin: 12; rightMargin: 10 }
                        spacing: 8
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0
                            Text {
                                text: "Tu equipo"
                                color: performanceMa.containsMouse ? Colors.accent : "#cfcfcf"
                                font.family: Appearance.fontUI; font.pixelSize: 10
                                font.weight: Font.DemiBold
                            }
                            Text {
                                text: "CPU " + ShellState.cpu + "%  ·  RAM " + ShellState.mem + "%  ·  SSD " + ShellState.disk + "%"
                                color: "#747474"
                                font.family: Appearance.fontUI; font.pixelSize: 8
                                font.features: ({ "tnum": 1 })
                            }
                        }
                        Text {
                            text: "›"
                            color: performanceMa.containsMouse ? Colors.accent : "#707070"
                            font.family: Appearance.fontUI; font.pixelSize: 20
                        }
                    }

                    MouseArea {
                        id: performanceMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: ShellState.togglePanel("system")
                    }
                }
            }
        }

        Rectangle { Layout.fillHeight: true; width: 1; color: "#1e1e1e" }

        // ══════════════════ derecha: notificaciones ══════════════════
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 8

            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                Text {
                    text: "Notificaciones"
                    color: "#ffffff"
                    font.family: Appearance.fontUI; font.pixelSize: 12; font.weight: Font.DemiBold
                }
                Rectangle {
                    visible: ShellState.notifCount > 0
                    implicitWidth: cnt.implicitWidth + 12
                    implicitHeight: 17
                    radius: 9
                    color: Qt.rgba(Colors.accent.r, Colors.accent.g, Colors.accent.b, 0.28)
                    Text {
                        id: cnt
                        anchors.centerIn: parent
                        text: ShellState.notifCount
                        color: Colors.accent
                        font.family: Appearance.fontUI; font.pixelSize: 10; font.weight: Font.Medium
                    }
                }
                Item { Layout.fillWidth: true }
                Text {
                    text: "󰒓"
                    color: gearMa.containsMouse ? Colors.accent : "#7d7d7d"
                    font.family: Appearance.font; font.pixelSize: 14
                    Behavior on color { ColorAnimation { duration: Appearance.mQuick; easing.type: Easing.OutQuad } }
                    MouseArea {
                        id: gearMa
                        anchors.fill: parent; anchors.margins: -5
                        hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: { ShellState.closePanel(); ShellState.settingsOpen = true; }
                    }
                }
                Text {
                    visible: ShellState.notifCount > 0
                    text: "Limpiar"
                    color: clearMa.containsMouse ? Colors.accent : "#7d7d7d"
                    font.family: Appearance.fontUI; font.pixelSize: 11
                    Behavior on color { ColorAnimation { duration: Appearance.mQuick; easing.type: Easing.OutQuad } }
                    MouseArea {
                        id: clearMa
                        anchors.fill: parent; anchors.margins: -5
                        hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: ShellState.clearNotifs()
                    }
                }
            }

            // ─────────── el ratón se lee UNA vez, y se lee aquí ───────────
            // Cada fila tenía su MouseArea y la equis otra encima. De ahí salían
            // tres fallos, y los tres se notan justo al ir a cerrar una:
            //
            //   · el cuerpo va en StyledText (el marcado que mande la app), y un
            //     Text con marcado ACEPTA eventos de hover para poder detectar
            //     enlaces: se comía el de la fila. Medido: sobre el título la
            //     fila se encendía y la equis salía; dos líneas más abajo, nada.
            //     La mayor parte de la superficie de cada fila era zona muerta.
            //   · la equis aparecía con `visible`, así que entraba y salía del
            //     layout: la columna de texto se ensanchaba 23 px en cuanto le
            //     quitabas el ratón. Es el menor de los tres, pero es geometría
            //     que se mueve sola justo debajo del puntero.
            //   · y al descartar una, el modelo es un array NUEVO (ver
            //     ShellState.notifications): se rehacen todos los delegados con el
            //     hover a cero. Como la mano no se ha movido no llega ningún
            //     evento que lo corrija, y la lista se queda mintiendo: equis
            //     encendida sobre una fila apagada, y el segundo clic en el mismo
            //     sitio no cierra nada porque cae en el hueco.
            //
            // Con un solo MouseArea por encima de la lista hay un único dueño de
            // "qué hay debajo del puntero". Y —esto es lo que arregla el tercero—
            // ese dueño puede volver a mirarlo cuando la lista cambia, sin tener
            // que esperar a que la mano se mueva.
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

                ListView {
                    id: notifList
                    anchors.fill: parent
                    clip: true
                    spacing: 7
                    model: ShellState.notifications
                    boundsBehavior: Flickable.StopAtBounds
                    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded; width: 4 }

                    property int hoverIdx: -1        // fila bajo el puntero; -1 = ninguna
                    property bool overClose: false   // ...y encima de su equis

                    // (mx, my) en coordenadas del visor, que es como las da el ratón.
                    function track(mx, my) {
                        const y = my + notifList.contentY;
                        const i = notifList.indexAt(notifList.width / 2, y);
                        notifList.hoverIdx = i;
                        const fila = i >= 0 ? notifList.itemAtIndex(i) : null;
                        const equis = fila ? fila.closeItem : null;
                        if (!equis) {
                            notifList.overClose = false;
                            return;
                        }
                        // La diana no se escribe a mano: se le pregunta al layout
                        // dónde ha dejado la equis y se le dan los 6 px de margen que
                        // tenía la MouseArea que vivía ahí. Si mañana cambia el
                        // espaciado de la fila, la diana se mueve sola.
                        const p = equis.mapToItem(fila, 0, 0);
                        notifList.overClose = mx >= p.x - 6 && mx <= p.x + equis.width + 6
                            && (y - fila.y) >= p.y - 6 && (y - fila.y) <= p.y + equis.height + 6;
                    }

                    // Volver a mirar sin que el ratón se haya movido: al cerrar una
                    // notificación las de abajo suben y quien queda bajo el puntero
                    // ya es otra fila. forceLayout porque si no se mide la lista de
                    // antes y la equis sale encendida en la fila equivocada.
                    function retrack() {
                        if (!listMa.containsMouse) {
                            notifList.hoverIdx = -1;
                            notifList.overClose = false;
                            return;
                        }
                        notifList.forceLayout();
                        notifList.track(listMa.mouseX, listMa.mouseY);
                    }

                    onCountChanged: Qt.callLater(notifList.retrack)
                    // Con la rueda son las filas las que se mueven, no la mano.
                    onContentYChanged: if (listMa.containsMouse) notifList.track(listMa.mouseX, listMa.mouseY)

                    delegate: Rectangle {
                        id: nrow
                        required property var modelData
                        required property int index
                        readonly property bool hovered: notifList.hoverIdx === nrow.index
                        // Lo único que la fila le cuenta a la lista: dónde tiene la
                        // equis, para que sepa a quién va dirigido el clic.
                        readonly property Item closeItem: equis

                        width: notifList.width
                        height: ncol.implicitHeight + 20
                        radius: 12
                        color: nrow.hovered ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(1, 1, 1, 0.045)
                        Behavior on color { ColorAnimation { duration: Appearance.mQuick; easing.type: Easing.OutQuad } }

                        RowLayout {
                            anchors { fill: parent; leftMargin: 12; rightMargin: 10; topMargin: 10; bottomMargin: 10 }
                            spacing: 11

                            Image {
                                Layout.preferredWidth: 22
                                Layout.preferredHeight: 22
                                Layout.alignment: Qt.AlignTop
                                source: nrow.modelData.image && nrow.modelData.image.length > 0
                                    ? nrow.modelData.image
                                    : Quickshell.iconPath(nrow.modelData.appIcon, "dialog-information")
                                sourceSize.width: 22; sourceSize.height: 22
                                fillMode: Image.PreserveAspectFit
                            }

                            ColumnLayout {
                                id: ncol
                                Layout.fillWidth: true
                                spacing: 2
                                Text {
                                    Layout.fillWidth: true
                                    text: (nrow.modelData.appName || "").toUpperCase()
                                    color: nrow.modelData.urgency === NotificationUrgency.Critical ? Colors.crit : "#9a9a9a"
                                    elide: Text.ElideRight
                                    font.family: Appearance.fontUI; font.pixelSize: 10
                                    font.weight: Font.DemiBold
                                    font.letterSpacing: 0.5
                                }
                                Text {
                                    Layout.fillWidth: true
                                    text: nrow.modelData.summary || ""
                                    color: "#ffffff"
                                    elide: Text.ElideRight
                                    font.family: Appearance.fontUI; font.pixelSize: 12; font.weight: Font.Medium
                                }
                                Text {
                                    Layout.fillWidth: true
                                    visible: text.length > 0
                                    text: nrow.modelData.body || ""
                                    color: "#8a8a8a"
                                    wrapMode: Text.Wrap
                                    maximumLineCount: 3
                                    elide: Text.ElideRight
                                    textFormat: Text.StyledText
                                    font.family: Appearance.fontUI; font.pixelSize: 11
                                }
                            }

                            Text {
                                id: equis
                                Layout.alignment: Qt.AlignTop
                                // Opacidad, no `visible`: la equis ocupa su hueco esté
                                // encendida o no, así que la fila mide lo mismo con
                                // ratón y sin ratón. Reservarle el sitio no cuesta
                                // nada y quita del medio la clase de fallo en la que
                                // lo que persigues se mueve porque lo persigues.
                                opacity: nrow.hovered ? 1 : 0
                                text: "󰅖"
                                color: nrow.hovered && notifList.overClose ? Colors.crit : "#7d7d7d"
                                font.family: Appearance.font; font.pixelSize: 12
                                Behavior on opacity { NumberAnimation { duration: Appearance.mQuick; easing.type: Easing.OutQuad } }
                                Behavior on color { ColorAnimation { duration: Appearance.mQuick; easing.type: Easing.OutQuad } }
                            }
                        }
                    }
                }

                MouseArea {
                    id: listMa
                    anchors.fill: parent
                    z: 1                     // por encima de las filas: el hover es suyo
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton
                    cursorShape: notifList.overClose ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onPositionChanged: function (mouse) { notifList.track(mouse.x, mouse.y); }
                    onEntered: notifList.track(listMa.mouseX, listMa.mouseY)
                    onExited: { notifList.hoverIdx = -1; notifList.overClose = false; }
                    onClicked: {
                        const n = notifList.hoverIdx >= 0 ? notifList.model[notifList.hoverIdx] : null;
                        if (!n) return;
                        if (notifList.overClose) { ShellState.dismissNotif(n); return; }
                        const acts = n.actions;
                        if (acts && acts.length > 0) { acts[0].invoke(); ShellState.closePanel(); }
                    }
                }
            }

            Text {
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: ShellState.notifCount === 0
                text: "Sin notificaciones"
                color: "#5e5e5e"
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                font.family: Appearance.fontUI; font.pixelSize: 12
            }
        }
    }
}
