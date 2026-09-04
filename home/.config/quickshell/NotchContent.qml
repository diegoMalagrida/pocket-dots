// NotchContent.qml — lo que se ve DENTRO del notch, según el modo.
// Recibe el rectángulo completo del notch (franja de barra + bulto); cada modo
// es una capa que aparece/desaparece con opacidad, así el morfeo lo hace la
// forma de TopShell y el contenido solo se funde.
import Quickshell
import QtQuick
import QtQuick.Layouts

Item {
    id: root
    property int barH: 32

    // Sobreescribible A PROPOSITO: TopShell le pasa la cara de reposo en las
    // pantallas que no tienen el foco. Por defecto, la que mande ShellState.
    property string mode: ShellState.mode

    // ─────────────── idle / media ───────────────
    // Estructura fija de dos polos, para que nada salte al cambiar de estado:
    //   IZQUIERDA (siempre): el reloj.
    //   DERECHA (contextual): batería en reposo, carátula + picos con música.
    // La batería está AQUÍ y solo aquí: se quitó de la barra para no repetirla.
    NotchLayer {
        anchors.fill: parent
        active: root.mode === "media" || root.mode === "idle"

        // ---- hora (+ fecha si está activada) ----
        // Centrada: en reposo solo hay un dato, así que anclarla a un lado
        // dejaría el notch descompensado. Con música se aparta a la izquierda
        // para dejar sitio a la carátula y a los picos.
        Row {
            anchors {
                horizontalCenter: parent.horizontalCenter
                horizontalCenterOffset: ShellState.mediaLive ? -52 : 0
                verticalCenter: parent.verticalCenter
            }
            Behavior on anchors.horizontalCenterOffset {
                NumberAnimation { duration: Appearance.mInScale; easing.type: Easing.OutBack; easing.overshoot: Appearance.mInOvershoot }
            }
            spacing: 11

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: Qt.formatDateTime(ShellState.now, "HH:mm")
                color: "#ffffff"
                font.family: Appearance.fontUI
                font.pixelSize: Config.clockSize
                font.weight: Font.DemiBold
                font.features: ({ "tnum": 1 })   // dígitos de ancho fijo: no baila al cambiar de minuto
            }

            Column {
                anchors.verticalCenter: parent.verticalCenter
                // fundido en vez de aparecer/desaparecer de golpe al sonar música
                opacity: (Config.showDate && !ShellState.mediaLive) ? 1 : 0
                visible: opacity > 0.01
                Behavior on opacity { NumberAnimation { duration: Appearance.mIn; easing.type: Easing.OutCubic } }
                spacing: 0
                Text {
                    height: 12
                    verticalAlignment: Text.AlignVCenter
                    text: ShellState.capitalize(ShellState.now.toLocaleDateString(ShellState.loc, "dddd"))
                    color: "#d0d0d0"
                    font.family: Appearance.fontUI
                    font.pixelSize: 10
                    font.weight: Font.Medium
                }
                Text {
                    height: 12
                    verticalAlignment: Text.AlignVCenter
                    text: ShellState.now.toLocaleDateString(ShellState.loc, I18n.tr("d 'de' MMMM"))
                    color: "#7f7f7f"
                    font.family: Appearance.fontUI
                    font.pixelSize: 10
                }
            }
        }

        // ---- polo derecho en reposo: batería ----
        Row {
            anchors { right: parent.right; rightMargin: 15; verticalCenter: parent.verticalCenter }
            spacing: 6
            opacity: (Config.showBattery && !ShellState.mediaLive && ShellState.batt >= 0) ? 1 : 0
            visible: opacity > 0.01
            Behavior on opacity { NumberAnimation { duration: Appearance.mIn; easing.type: Easing.OutCubic } }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: ShellState.battIcon
                color: ShellState.ac ? Colors.ok
                    : ShellState.batt < 15 ? Colors.crit
                    : ShellState.batt < 30 ? Colors.warn : "#d0d0d0"
                font.family: Appearance.font; font.pixelSize: Appearance.fsM
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: ShellState.batt + "%"
                color: ShellState.ac ? Colors.ok
                    : ShellState.batt < 15 ? Colors.crit
                    : ShellState.batt < 30 ? Colors.warn : "#d0d0d0"
                font.family: Appearance.fontUI
                font.pixelSize: 11
                font.weight: Font.Medium
            }
        }

        // ---- polo derecho con música: carátula + picos ----
        Row {
            anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
            spacing: 9
            opacity: ShellState.mediaLive ? 1 : 0
            visible: opacity > 0.01
            Behavior on opacity { NumberAnimation { duration: Appearance.mIn; easing.type: Easing.OutCubic } }

            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: 22; height: 22; radius: 7
                color: "#171717"
                clip: true
                Image {
                    anchors.fill: parent
                    source: (ShellState.player && ShellState.player.trackArtUrl) ? ShellState.player.trackArtUrl : ""
                    fillMode: Image.PreserveAspectCrop
                    visible: status === Image.Ready
                }
                Text {
                    anchors.centerIn: parent
                    visible: !(ShellState.player && ShellState.player.trackArtUrl)
                    text: Icons.play; color: ShellState.mediaAccent
                    font.family: Appearance.font; font.pixelSize: 11
                    Behavior on color { ColorAnimation { duration: Appearance.mIn; easing.type: Easing.OutCubic } }
                }
            }

            // EL CAJÓN DE LAS BARRAS ES FIJO, no un Row que se ajusta solo.
            //
            // Con un Row, la altura del Row es la de su hijo más alto, y cada
            // barra se centraba respecto a ese Row. O sea: cada vez que la barra
            // más alta cambiaba, cambiaba el cajón, y con él la posición
            // vertical de LAS OCHO a la vez. Un golpe de bombo movía toda la
            // tira, no solo su barra — el temblor de conjunto que se veía por
            // encima del movimiento de cada barra.
            //
            // Aquí el cajón mide 18 px pase lo que pase, y cada barra vive en su
            // hueco: 4 de ancho + 4 de hueco = 8 px de paso. Una barra no puede
            // mover a sus vecinas.
            Item {
                anchors.verticalCenter: parent.verticalCenter
                width: ShellState.bands * 8 - 4
                height: 18

                Repeater {
                    // Una barra por banda de cava: graves a la izquierda,
                    // agudos a la derecha. Sin Behavior, y probado que es lo
                    // correcto: el movimiento ya lo lleva el seguidor por
                    // fotograma de ShellState; una animación aquí se reinicia
                    // con cada dato, no termina nunca, y solo mete tirones.
                    model: ShellState.bands
                    Rectangle {
                        required property int index
                        x: index * 8
                        width: 4; radius: 2
                        color: ShellState.mediaAccent
                        Behavior on color { ColorAnimation { duration: Appearance.mIn; easing.type: Easing.OutCubic } }

                        // ALTURA CONTINUA, CON DECIMALES. Aquí hubo un tiempo un
                        // redondeo a píxel entero con histéresis de 0,7 px, y era
                        // justo lo que hacía que esto no fuese fluido: en un
                        // recorrido de solo 14 px (4→18) eso deja quince alturas
                        // posibles, así que la barra se quedaba QUIETA y luego
                        // PEGABA UN SALTO del 7% del recorrido de golpe. Encima,
                        // al centrarse, cada salto cambiaba la paridad de la
                        // altura y con ella el reparto subpíxel de las tapas
                        // redondeadas: la barra alternaba entre nítida y borrosa
                        // en cada escalón. Eso es literalmente el parpadeo.
                        //
                        // (Está medido y anotado en scripts/cava.conf: cuantizar
                        // dejaba el visualizador MÁS parado, 2,6 px/s frente a
                        // 4,4. El redondeo se coló después de esa medición.)
                        //
                        // Un Rectangle con radius se dibuja con antialiasing, así
                        // que sí sabe pintar medio píxel: el borde se reparte
                        // entre dos filas. Eso NO es parpadeo, es exactamente el
                        // mecanismo con el que una pantalla enseña movimiento más
                        // fino que su propia rejilla. Lo que parpadeaba era el
                        // escalón, no el decimal.
                        antialiasing: true
                        // El suelo es el ancho: en reposo cada barra es un
                        // punto redondo, no una pastilla achatada.
                        height: Math.max(4, 18 * (ShellState.levels[index] || 0))
                        // Crece hacia los dos lados desde el centro del cajón,
                        // que es una constante: la referencia no se mueve nunca.
                        y: (18 - height) / 2
                    }
                }
            }
        }
    }

    // ─────────────── peek (hover): el reloj de reposo, con más detalle ───────────────
    // Misma fila centrada que en idle, pero la fecha se escribe entera y se
    // añade la batería: al pasar el ratón, el reloj "se despliega".
    NotchLayer {
        anchors.fill: parent
        active: root.mode === "peek"

        // Pasas el ratón, ves la fecha, clicas y se abre el mes (como en macOS).
        // Ignoramos el botón derecho y la rueda para que sigan llegando a TopShell
        // (play/pause de MPRIS y volumen/escritorio).
        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            acceptedButtons: Qt.LeftButton
            onClicked: ShellState.togglePanel("calendar")
            onWheel: function (wheel) { wheel.accepted = false; }
        }

        // Centrada igual que en reposo: al pasar el ratón el grupo crece y se
        // recentra, en vez de saltar de un anclaje a otro.
        Row {
            anchors {
                horizontalCenter: parent.horizontalCenter
                horizontalCenterOffset: -26
                verticalCenter: parent.verticalCenter
            }
            spacing: 13

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: Qt.formatDateTime(ShellState.now, "HH:mm")
                color: "#ffffff"
                font.family: Appearance.fontUI
                font.pixelSize: 21
                font.weight: Font.DemiBold
                font.features: ({ "tnum": 1 })
            }

            Column {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 0
                Text {
                    height: 14
                    verticalAlignment: Text.AlignVCenter
                    text: ShellState.capitalize(ShellState.now.toLocaleDateString(ShellState.loc, "dddd"))
                    color: "#e0e0e0"
                    font.family: Appearance.fontUI
                    font.pixelSize: 11
                    font.weight: Font.Medium
                }
                Text {
                    height: 14
                    verticalAlignment: Text.AlignVCenter
                    text: ShellState.now.toLocaleDateString(ShellState.loc, I18n.tr("d 'de' MMMM 'de' yyyy"))
                    color: "#8a8a8a"
                    font.family: Appearance.fontUI
                    font.pixelSize: 11
                }
            }
        }

        Row {
            anchors { right: parent.right; rightMargin: 15; verticalCenter: parent.verticalCenter }
            spacing: 6
            visible: ShellState.batt >= 0
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: ShellState.battIcon
                color: ShellState.ac ? Colors.ok
                    : ShellState.batt < 15 ? Colors.crit
                    : ShellState.batt < 30 ? Colors.warn : "#d0d0d0"
                font.family: Appearance.font; font.pixelSize: Appearance.fsL
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: ShellState.batt + "%"
                color: ShellState.ac ? Colors.ok
                    : ShellState.batt < 15 ? Colors.crit
                    : ShellState.batt < 30 ? Colors.warn : "#d0d0d0"
                font.family: Appearance.fontUI
                font.pixelSize: 12
                font.weight: Font.Medium
            }
        }
    }

    // ─────────────── activity: OSD de volumen / brillo ───────────────
    NotchLayer {
        id: osd
        anchors.fill: parent
        active: root.mode === "activity"

        readonly property bool isVol: ShellState.activity === "volume"
        readonly property int value: isVol ? (ShellState.muted ? 0 : ShellState.vol) : Math.max(0, ShellState.bright)
        // mismo motivo: el notch se ensancha al entrar en modo OSD, así que el
        // carril crece; animar el ancho haría que la barra fuese detrás
        property real shown: osd.value
        Behavior on shown { NumberAnimation { duration: Appearance.mQuick; easing.type: Easing.OutCubic } }

        RowLayout {
            anchors { fill: parent; leftMargin: 20; rightMargin: 20 }
            spacing: 12

            Text {
                text: osd.isVol
                    ? (ShellState.muted ? Icons.volMute
                        : ShellState.vol > 55 ? Icons.volHigh
                        : ShellState.vol > 20 ? Icons.volMed : Icons.volLow)
                    : Icons.brightness
                color: "#ffffff"
                font.family: Appearance.font; font.pixelSize: Appearance.fsL
            }
            Rectangle {
                id: osdTrack
                Layout.fillWidth: true
                Layout.preferredHeight: 5
                radius: 3
                color: "#2c2c2c"
                Rectangle {
                    width: osdTrack.width * Math.max(0, Math.min(1, osd.shown / 100))
                    height: parent.height; radius: parent.radius
                    color: osd.isVol ? Colors.accent : Colors.warn
                }
            }
            Text {
                text: Math.round(osd.shown) + "%"
                color: "#cccccc"
                Layout.preferredWidth: 34
                horizontalAlignment: Text.AlignRight
                font.family: Appearance.font; font.pixelSize: Appearance.fsXS
            }
        }
    }

    // ─────────────── ws: escritorio al que acabas de saltar ───────────────
    // Solo sale con el GESTO de la rueda horizontal sobre el notch, nunca con
    // Super+1..0. No es una omisión: con el atajo ya sabes a dónde vas porque
    // acabas de teclear el número, y el indicador de la barra está justo al
    // lado. Con la rueda no hay número que teclear y estás mirando el notch, así
    // que es el único caso en que el gesto necesita acuse de recibo.
    NotchLayer {
        anchors.fill: parent
        active: root.mode === "ws"

        Row {
            anchors.centerIn: parent
            spacing: 11

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: I18n.tr("Escritorio")
                color: "#8a8a8a"
                font.family: Appearance.fontUI
                font.pixelSize: 12
                font.weight: Font.Medium
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: String(ShellState.activeWs)
                color: Colors.accent
                font.family: Appearance.fontUI
                font.pixelSize: 20
                font.weight: Font.DemiBold
                font.features: ({ "tnum": 1 })   // del 9 al 10 el grupo no debe recolocarse
            }
        }
    }

    // ─────────────── charge: has enchufado o desenchufado ───────────────
    // El único aviso del notch que NO provocas tú. El resto (OSD, peek, paneles)
    // sale porque acabas de hacer algo; esto sale porque acaba de pasar algo, y
    // por eso se queda un poco más en pantalla que un OSD: no estabas mirando.
    NotchLayer {
        id: chargeLayer
        anchors.fill: parent
        active: root.mode === "charge"

        readonly property color tone: ShellState.ac ? Colors.ok
            : ShellState.batt < 15 ? Colors.crit
            : ShellState.batt < 30 ? Colors.warn : "#ffffff"

        Row {
            anchors.centerIn: parent
            spacing: 12

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: ShellState.battIcon
                color: chargeLayer.tone
                font.family: Appearance.font
                font.pixelSize: 21
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                // "Con batería" y no "Desenchufado": lo que importa no es que
                // hayas quitado un cable, es de qué estás tirando ahora.
                text: ShellState.ac ? I18n.tr("Cargando") : I18n.tr("Con batería")
                color: "#e6e6e6"
                font.family: Appearance.fontUI
                font.pixelSize: 13
                font.weight: Font.Medium
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: ShellState.batt >= 0
                text: I18n.tr("{0} %", ShellState.batt)
                color: chargeLayer.tone
                font.family: Appearance.fontUI
                font.pixelSize: 15
                font.weight: Font.DemiBold
                font.features: ({ "tnum": 1 })
            }
        }
    }

    // ─────────────── btpair: emparejando un aparato ───────────────
    // La única cara que sale por delante de un panel abierto, porque al otro
    // lado hay un aparato con un temporizador corriendo. Dos formas:
    //   · "display"  -> BlueZ nos da el código y lo tecleas TÚ en el teclado.
    //                   No hay nada que contestar, solo que leer.
    //   · el resto   -> hay que decir sí o no, y hay dos botones.
    NotchLayer {
        id: btLayer
        anchors.fill: parent
        active: root.mode === "btpair"

        readonly property bool ask: ShellState.btKind !== "display"

        ColumnLayout {
            anchors { fill: parent; leftMargin: 16; rightMargin: 16; topMargin: 8; bottomMargin: 10 }
            spacing: 6

            RowLayout {
                Layout.fillWidth: true
                spacing: 12

                Text {
                    text: ShellState.btKind === "display" ? Icons.keyboard : Icons.btPair
                    color: Colors.accent
                    font.family: Appearance.font
                    font.pixelSize: 22
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    Text {
                        Layout.fillWidth: true
                        text: ShellState.btName.length > 0 ? ShellState.btName : I18n.tr("Aparato desconocido")
                        color: "#ffffff"
                        elide: Text.ElideRight
                        font.family: Appearance.fontUI
                        font.pixelSize: 14
                        font.weight: Font.DemiBold
                    }
                    Text {
                        Layout.fillWidth: true
                        text: ShellState.btKind === "display"
                                ? I18n.tr("Teclea este código y pulsa Enter")
                                : ShellState.btKind === "authorize"
                                    ? I18n.tr("Quiere emparejarse con este equipo")
                                    : I18n.tr("¿Sale este mismo código en el aparato?")
                        color: "#8a8a8a"
                        elide: Text.ElideRight
                        font.family: Appearance.fontUI
                        font.pixelSize: 11
                    }
                }

                // El código, en cifras grandes: es lo que hay que comparar de un
                // vistazo con lo que enseña el aparato. tnum para que no baile
                // al ir tecleando.
                Text {
                    visible: ShellState.btCode.length > 0
                    text: ShellState.btCode
                    color: "#ffffff"
                    font.family: Appearance.fontUI
                    font.pixelSize: 22
                    font.weight: Font.DemiBold
                    font.letterSpacing: 2
                    font.features: ({ "tnum": 1 })
                }
            }

            // Progreso de tecleo: BlueZ va diciendo cuántos dígitos llevas.
            // Es la única señal de que el teclado está hablando con el equipo.
            Rectangle {
                visible: ShellState.btKind === "display" && ShellState.btEntered >= 0
                Layout.fillWidth: true
                Layout.preferredHeight: 3
                radius: 2
                color: "#242424"
                Rectangle {
                    height: parent.height
                    radius: parent.radius
                    color: Colors.accent
                    width: parent.width * Math.min(1, ShellState.btEntered
                            / Math.max(1, ShellState.btCode.length))
                    Behavior on width { NumberAnimation { duration: Appearance.mQuick; easing.type: Easing.OutQuad } }
                }
            }

            RowLayout {
                visible: btLayer.ask
                Layout.fillWidth: true
                Layout.topMargin: 2
                spacing: 8

                Item { Layout.fillWidth: true }

                Repeater {
                    model: [
                        { txt: I18n.tr("No"), ico: Icons.no, ok: false },
                        { txt: I18n.tr("Sí"), ico: Icons.yes, ok: true }
                    ]
                    delegate: Rectangle {
                        required property var modelData
                        implicitWidth: btBtnRow.implicitWidth + 26
                        implicitHeight: 30
                        radius: 15
                        color: modelData.ok
                            ? (btBtnMa.containsMouse ? Qt.rgba(Colors.accent.r, Colors.accent.g, Colors.accent.b, 0.34)
                                                     : Qt.rgba(Colors.accent.r, Colors.accent.g, Colors.accent.b, 0.20))
                            : (btBtnMa.containsMouse ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(1, 1, 1, 0.06))
                        Behavior on color { ColorAnimation { duration: Appearance.mQuick; easing.type: Easing.OutQuad } }

                        RowLayout {
                            id: btBtnRow
                            anchors.centerIn: parent
                            spacing: 7
                            Text {
                                text: modelData.ico
                                color: modelData.ok ? Colors.accent : "#b0b0b0"
                                font.family: Appearance.font
                                font.pixelSize: 13
                            }
                            Text {
                                text: modelData.txt
                                color: modelData.ok ? "#ffffff" : "#b0b0b0"
                                font.family: Appearance.fontUI
                                font.pixelSize: 12
                                font.weight: Font.Medium
                            }
                        }

                        MouseArea {
                            id: btBtnMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: ShellState.btReply(modelData.ok)
                        }
                    }
                }
            }
        }
    }

    // ─────────────── track: "ahora suena" ───────────────
    NotchLayer {
        anchors.fill: parent
        active: root.mode === "track"

        RowLayout {
            anchors { fill: parent; leftMargin: 12; rightMargin: 14 }
            spacing: 10

            Rectangle {
                Layout.preferredWidth: 34; Layout.preferredHeight: 34
                Layout.alignment: Qt.AlignVCenter
                radius: 9
                color: "#171717"
                clip: true
                Image {
                    anchors.fill: parent
                    source: (ShellState.player && ShellState.player.trackArtUrl) ? ShellState.player.trackArtUrl : ""
                    fillMode: Image.PreserveAspectCrop
                    visible: status === Image.Ready
                }
                Text {
                    anchors.centerIn: parent
                    visible: !(ShellState.player && ShellState.player.trackArtUrl)
                    text: "󰎈"; color: ShellState.mediaAccent
                    font.family: Appearance.font; font.pixelSize: 16
                    Behavior on color { ColorAnimation { duration: Appearance.mIn; easing.type: Easing.OutCubic } }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                spacing: 1
                Text {
                    Layout.fillWidth: true
                    text: ShellState.player ? (ShellState.player.trackTitle || "") : ""
                    color: "#ffffff"; elide: Text.ElideRight
                    font.family: Appearance.font; font.pixelSize: Appearance.fsXS; font.bold: true
                }
                Text {
                    Layout.fillWidth: true
                    text: ShellState.player ? (ShellState.player.trackArtist || "") : ""
                    color: "#9a9a9a"; elide: Text.ElideRight
                    font.family: Appearance.font; font.pixelSize: 10
                }
            }

            // Mismo cajón fijo y misma altura continua que en el polo derecho
            // (ver allí el porqué), aquí sobre 22 px de alto. Va con implicit*
            // porque el padre es un RowLayout: es el layout quien reparte, y lo
            // que le decimos es cuánto pedimos, no cuánto medimos.
            Item {
                Layout.alignment: Qt.AlignVCenter
                implicitWidth: ShellState.bands * 8 - 4
                implicitHeight: 22

                Repeater {
                    model: ShellState.bands
                    Rectangle {
                        required property int index
                        x: index * 8
                        width: 4; radius: 2
                        color: ShellState.mediaAccent
                        Behavior on color { ColorAnimation { duration: Appearance.mIn; easing.type: Easing.OutCubic } }
                        antialiasing: true
                        height: Math.max(4, 22 * (ShellState.levels[index] || 0))
                        y: (22 - height) / 2
                    }
                }
            }
        }
    }

    // ─────────────── notif: aviso emergente ───────────────
    // Al llegar una notificación el notch se estira y la enseña unos segundos,
    // como una live activity. Luego se queda en el centro de control.
    NotchLayer {
        id: notifLayer
        anchors.fill: parent
        active: root.mode === "notif"

        readonly property var n: ShellState.lastNotif

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            // Si el aviso trae acciones, pulsarlo HACE ESO en vez de abrir el
            // centro de control: es lo que espera cualquiera al ver un aviso
            // con algo que hacer detrás. La captura de pantalla manda una
            // acción "Editar" que abre la foto en satty
            // (~/.config/hypr/scripts/notify-shot.sh); el resto de avisos, que
            // no traen ninguna, siguen abriendo el centro de control como antes.
            onClicked: {
                const n = notifLayer.n;
                const acts = n ? n.actions : null;
                ShellState.activity = "";
                if (acts && acts.length > 0) acts[0].invoke();
                else ShellState.togglePanel("control");
            }
        }

        RowLayout {
            anchors { fill: parent; leftMargin: 13; rightMargin: 15 }
            spacing: 11

            Image {
                Layout.preferredWidth: 34; Layout.preferredHeight: 34
                Layout.alignment: Qt.AlignVCenter
                source: {
                    const n = notifLayer.n;
                    if (!n) return "";
                    return (n.image && n.image.length > 0) ? n.image
                        : Quickshell.iconPath(n.appIcon, "dialog-information");
                }
                sourceSize.width: 34; sourceSize.height: 34
                fillMode: Image.PreserveAspectFit
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                spacing: 1
                Text {
                    Layout.fillWidth: true
                    text: notifLayer.n ? (notifLayer.n.summary || "") : ""
                    color: "#ffffff"; elide: Text.ElideRight
                    font.family: Appearance.fontUI; font.pixelSize: 12; font.weight: Font.DemiBold
                }
                Text {
                    Layout.fillWidth: true
                    visible: text.length > 0
                    text: notifLayer.n ? (notifLayer.n.body || "") : ""
                    color: "#9a9a9a"; elide: Text.ElideRight
                    textFormat: Text.StyledText
                    font.family: Appearance.fontUI; font.pixelSize: 10
                }
            }

            Text {
                Layout.alignment: Qt.AlignVCenter
                text: notifLayer.n ? (notifLayer.n.appName || "") : ""
                color: Colors.accent
                font.family: Appearance.fontUI; font.pixelSize: 9; font.weight: Font.Medium
            }
        }
    }

    // ─────────────── toast: aviso breve (copiado al portapapeles) ───────────────
    NotchLayer {
        anchors.fill: parent
        active: root.mode === "toast"

        Row {
            anchors.centerIn: parent
            spacing: 11
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: ShellState.toastIcon
                color: Colors.accent
                font.family: Appearance.font; font.pixelSize: 17
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: ShellState.toastText
                color: "#ffffff"
                font.family: Appearance.fontUI; font.pixelSize: 13; font.weight: Font.Medium
            }
        }
    }

    // ─────────────── launcher: lanzador de aplicaciones ───────────────
    NotchLayer {
        anchors.fill: parent
        active: root.mode === "launcher"
        origin: -1   // el boton de Arch esta a la izquierda
        LauncherPanel { anchors.fill: parent }
    }

    // ─────────────── overview: mapa de escritorios ───────────────
    // Nace en el CENTRO (origin 0) y no por un lado: no lo abre ningún botón de
    // la barra, lo abre Super+Tab. Lo que no has pedido desde un sitio concreto
    // no tiene por qué venir de un sitio concreto.
    NotchLayer {
        anchors.fill: parent
        active: root.mode === "overview"
        OverviewPanel { anchors.fill: parent }
    }

    // ─────────────── control: centro de control ───────────────
    NotchLayer {
        anchors.fill: parent
        active: root.mode === "control"
        origin: 1   // la campana de notificaciones esta a la derecha
        ControlPanel { anchors.fill: parent }
    }

    // ─────────────── system: una mirada tranquila al equipo ───────────────
    NotchLayer {
        anchors.fill: parent
        active: root.mode === "system"
        origin: 1   // nace del botón Tu equipo del centro de control
        PerformancePanel { anchors.fill: parent }
    }

    // ─────────────── network: selector de red ───────────────
    NotchLayer {
        anchors.fill: parent
        active: root.mode === "network"
        origin: 1   // se abre desde el panel de control, a la derecha
        NetworkPanel { anchors.fill: parent }
    }

    // ─────────────── bluetooth: dispositivos ───────────────
    NotchLayer {
        anchors.fill: parent
        active: root.mode === "bluetooth"
        origin: 1   // se abre desde el panel de control, a la derecha
        BluetoothPanel { anchors.fill: parent }
    }

    // ─────────────── power: menú de encendido ───────────────
    NotchLayer {
        anchors.fill: parent
        active: root.mode === "power"
        origin: 1   // su icono esta a la derecha
        PowerPanel { anchors.fill: parent }
    }

    // ─────────────── calendar: calendario del mes ───────────────
    // Nace en el centro (origin 0), que es donde está el reloj del que sale.
    NotchLayer {
        anchors.fill: parent
        active: root.mode === "calendar"
        origin: 0
        CalendarPanel { anchors.fill: parent }
    }
}
