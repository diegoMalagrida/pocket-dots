// hyprisland — tema SDDM que replica la isla de hyprlock.
//
// Objetivo: que la pantalla de login al arrancar sea INDISTINGUIBLE del bloqueo
// que lanza el notch. Cada numero de aqui viene de ~/.config/hypr/hyprlock.conf;
// si cambias uno alli, cambialo aqui. Las duraciones y curvas son las de
// ~/.config/motion-language.md (PANEL 320, CONTENIDO 210, RESPUESTA 130).
//
// Los glifos van escapados (\u{F033E}) a proposito: son Private Use Area de
// Nerd Font y no sobreviven a todos los editores. No los pegues literales.

import QtQuick
import QtQuick.Effects

Item {
    id: root

    // El foco es critico: si el campo no lo recibe, no hay forma de entrar.
    // forceActiveFocus() en Component.onCompleted NO basta — el item aun no
    // cuelga de la ventana y la llamada se pierde en silencio. De ahi el
    // focus: true aqui, el reintento con Timer y el reenvio de teclas.
    focus: true
    Keys.forwardTo: [password]

    // ---- Paleta: espejo de ~/.cache/wal/colors-hyprlock.conf -----------------
    // El acento lo escribe login-sync.sh en /var/lib/sddm-hyprisland/accent
    // cada vez que cambia el wallpaper. NO es readonly a proposito: se lee de
    // disco al arrancar (ver Component.onCompleted) y se asigna. Lo que trae
    // theme.conf es solo el punto de partida -lo siembra el instalador del
    // tema con el acento del momento- para que no se vea saltar el color
    // mientras entra la isla. El resto es fijo, igual que en el notch: la
    // superficie es negra y pywal solo aporta el acento.
    property color accent:              config.accent || "#8cd8c2"

    // Idioma del login. Sale de theme.conf porque aqui no hay sesion de
    // usuario todavia y no se puede leer el JSON del rice: SDDM corre antes
    // de que exista el $HOME de nadie. Lo escribe el instalador.
    // Si la clave no esta, castellano, que es lo que habia siempre.
    readonly property string uiLang:    config.language || "es"
    readonly property bool english:     uiLang === "en"
    readonly property color surface:    Qt.rgba(0, 0, 0, 0.941)   // rgba(000000f0)
    readonly property color surfaceAlt: "#181818"
    readonly property color outline:    Qt.rgba(1, 1, 1, 0.094)   // rgba(ffffff18)
    readonly property color textColor:  "#ffffff"
    readonly property color muted:      "#b0b0b0"
    readonly property color dim:        "#7d7d7d"
    readonly property color okColor:    "#6dbd7a"
    readonly property color warnColor:  "#e0a458"
    readonly property color failColor:  "#e05c5c"

    // ---- Geometria de la isla (hyprlock: shape 520x340, rounding 32) ---------
    readonly property int islandW: 520
    readonly property int islandH: 340
    readonly property int fieldW:  360
    readonly property int fieldH:  50

    // ---- Estado del login ---------------------------------------------------
    property int  attempts: 0
    property bool checking: false
    property bool failed: false
    // RememberLastUser=true en /etc/sddm.conf, asi que lastUser suele bastar;
    // firstUser cubre el primer arranque y el modo test, donde viene vacio.
    property string firstUser: ""
    property string userName: userModel.lastUser || firstUser

    Repeater {
        model: userModel
        delegate: Item {
            required property string name
            required property int index
            Component.onCompleted: if (index === 0) root.firstUser = name
        }
    }

    // ---- Sesiones -----------------------------------------------------------
    // Antes se entraba SIEMPRE en sessionModel.lastIndex y no habia forma de
    // elegir otra. El dia que Hyprland no arranco eso dejo la maquina cerrada
    // por dentro: Plasma estaba instalado y no habia manera de llegar a el sin
    // editar la linea del kernel desde el gestor de arranque.
    //
    // El comportamiento por defecto NO cambia: sessionPick vale -1 mientras
    // nadie toque el selector, y en ese caso se le pasa a sddm.login() el mismo
    // sessionModel.lastIndex de siempre.
    //
    // Este Repeater no dibuja nada: solo copia los nombres del modelo. Se leen
    // por rol ("name", igual que en userModel) y no con
    // sessionModel.data(idx, 260) como hace el tema `silent`, porque ese 260 es
    // el numero crudo del enum de SDDM y se rompe en silencio si lo reordenan.
    property var sessionNames: []
    property int sessionPick: -1
    readonly property int sessionCurrent: sessionPick >= 0 ? sessionPick
                                                           : sessionModel.lastIndex
    readonly property string sessionName:
        (sessionCurrent >= 0 && sessionCurrent < sessionNames.length)
            ? sessionNames[sessionCurrent] : ""

    Repeater {
        id: sessionProbe
        model: sessionModel
        delegate: Item {
            required property string name
            required property int index
            Component.onCompleted: root.rememberSession(index, name)
        }
    }

    // Se reasigna el array entero a proposito: mutar uno en sitio no notifica a
    // los bindings y la etiqueta se quedaria vacia.
    function rememberSession(i, sessionTitle) {
        var a = sessionNames.slice();
        while (a.length <= i)
            a.push("");
        a[i] = sessionTitle;
        sessionNames = a;
    }

    // Ciclar, no desplegar. Un ComboBox de Qt mete su propio marco y su propio
    // popup encima de la isla, y un popup abierto puede tapar el campo o robarle
    // el foco, que es el fallo que mas caro costo montando este tema. Ciclando
    // no hay nada que se pueda quedar abierto.
    function cycleSession(step) {
        var n = sessionProbe.count;
        if (n <= 1)
            return;
        var cur = (sessionCurrent >= 0 && sessionCurrent < n) ? sessionCurrent : 0;
        sessionPick = (cur + step + n) % n;
        password.forceActiveFocus();      // el foco vuelve al campo, siempre
    }

    // La curva `softOut` de hyprlock.conf. Es la hermana de `forma` del lenguaje
    // de movimiento: 90 % del recorrido en el primer tercio, aterrizaje largo.
    readonly property var softOut: [0.16, 1.0, 0.3, 1.0, 1.0, 1.0]

    // =========================================================================
    // Fondo: el wallpaper actual, desenfocado y bajado de luz igual que hyprlock
    // (blur_passes 2, blur_size 4, brightness 0.68, contrast 0.92, vibrancy).
    // =========================================================================
    Rectangle {
        anchors.fill: parent
        color: "black"
    }

    Image {
        id: wallpaper
        anchors.fill: parent
        // Ruta fija y absoluta: ahi deja el fondo login-sync.sh, que corre como
        // tu usuario. Si el fichero no esta -tema recien instalado, o wallpaper
        // sin cambiar todavia- Qt marca status Error y caemos al que viene
        // dentro del tema, que es el ultimo que se publico con sudo.
        source: "file:///var/lib/sddm-hyprisland/current.jpg"
        onStatusChanged: if (status === Image.Error && source != fallback)
                             source = fallback
        readonly property url fallback: config.background || "backgrounds/current.jpg"
        fillMode: Image.PreserveAspectCrop
        asynchronous: false
        cache: false
        visible: false
        layer.enabled: true
    }

    MultiEffect {
        anchors.fill: parent
        source: wallpaper
        blurEnabled: true
        blur: 1.0
        blurMax: 40
        blurMultiplier: 1.0
        brightness: -0.32     // hyprlock brightness 0.68 (multiplicador)
        contrast: -0.08       // hyprlock contrast 0.92
        saturation: 0.14      // hyprlock vibrancy 0.14
    }

    // =========================================================================
    // La isla
    // =========================================================================

    // Sombra (hyprlock: shadow_passes 3, shadow_size 18, rgba(000000a6)).
    // Se dibuja como un degradado de anillos y no con MultiEffect a proposito:
    // un layer.effect recorta la sombra al borde del item, y alimentarlo con
    // una fuente `visible: false` daba un halo GRIS CLARO en vez de sombra.
    // Anillos de 1 px con alfa decreciente: predecible y sin efectos raros.
    Repeater {
        model: 18                                  // shadow_size
        delegate: Rectangle {
            required property int index
            anchors.centerIn: island
            anchors.verticalCenterOffset: 6
            width: island.width + (index + 1) * 2
            height: island.height + (index + 1) * 2
            radius: island.radius + index + 1
            color: "transparent"
            border.width: 1
            border.color: Qt.rgba(0, 0, 0, 0.65 * Math.pow(1 - index / 18, 2))
            opacity: island.opacity
        }
    }

    Rectangle {
        id: island
        anchors.centerIn: parent
        width: root.islandW
        height: root.islandH
        radius: 32
        color: root.surface
        border.width: 1
        border.color: root.outline

        // PANEL entra: 320 ms.
        opacity: 0
        Component.onCompleted: opacity = 1
        Behavior on opacity {
            NumberAnimation {
                duration: 320
                easing.type: Easing.Bezier
                easing.bezierCurve: root.softOut
            }
        }

        // ---- Medallon de bloqueo (42x42, +130 sobre el centro) --------------
        Rectangle {
            width: 42
            height: 42
            radius: 21
            color: root.surfaceAlt
            border.width: 1
            border.color: root.accent
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: -130

            Text {
                anchors.centerIn: parent
                text: "\u{F033E}"                     // nf-md-lock
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: 17
                color: root.accent
            }
        }

        // ---- Reloj (68 px, cifras tabulares para que no bailen) -------------
        Text {
            id: clock
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: -58
            font.family: "Adwaita Sans"
            font.pixelSize: 68
            font.features: ({ "tnum": 1 })
            color: root.textColor
            text: Qt.formatDateTime(new Date(), "HH:mm")
        }

        // ---- Fecha en espanol, independiente del locale del sistema ---------
        Text {
            id: dateLabel
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: -4
            font.family: "Adwaita Sans"
            font.pixelSize: 15
            color: root.muted
            text: root.localDate()
        }

        // ---- Campo-pildora --------------------------------------------------
        Rectangle {
            id: field
            width: root.fieldW
            height: root.fieldH
            radius: height / 2                        // hyprlock rounding -1
            color: root.surfaceAlt
            border.width: 2                           // outline_thickness
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: 58

            // El color del borde ES el mensaje: acento en reposo, ambar con
            // bloq-mayus, verde comprobando, rojo al fallar.
            border.color: root.checking ? root.okColor
                        : root.failed ? root.failColor
                        : keyboard.capsLock ? root.warnColor
                        : root.accent

            Behavior on border.color {
                ColorAnimation {
                    duration: 130                     // RESPUESTA
                    easing.type: Easing.Bezier
                    easing.bezierCurve: root.softOut
                }
            }

            // Captura las pulsaciones; los puntos se dibujan a mano debajo para
            // clavar el tamano de hyprlock (dots_size 0.20, spacing 0.38).
            TextInput {
                id: password
                anchors.fill: parent
                focus: true
                echoMode: TextInput.Password
                passwordCharacter: " "
                color: "transparent"
                selectionColor: "transparent"
                enabled: !root.checking

                onTextChanged: {
                    root.failed = false;
                }

                Keys.onPressed: function (event) {
                    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                        root.doLogin();
                        event.accepted = true;
                    }
                    // Ruta de teclado para el selector, por si el raton no
                    // responde: F1 pasa a la siguiente sesion, Mayus+F1 a la
                    // anterior. F1 no escribe nada, asi que no puede acabar
                    // dentro de la contrasena.
                    if (event.key === Qt.Key_F1) {
                        root.cycleSession((event.modifiers & Qt.ShiftModifier) ? -1 : 1);
                        event.accepted = true;
                    }
                }
            }

            // Estado en texto, centrado, sustituye al placeholder.
            Text {
                anchors.centerIn: parent
                font.family: "Adwaita Sans"
                font.pixelSize: 14
                visible: text !== ""
                color: root.checking ? root.okColor
                     : root.failed ? root.failColor
                     : Qt.rgba(1, 1, 1, 0.55)         // placeholder alpha 55 %
                text: root.checking ? (root.english ? "Checking…" : "Comprobando…")
                    : root.failed ? (root.english ? "No match · attempt " : "No coincide · intento ") + root.attempts
                    : password.text.length === 0 ? (root.english ? "Enter your password" : "Escribe tu contraseña")
                    : ""
            }

            // Los puntos. Diametro = 0.20 * alto, hueco = 0.38 * diametro.
            Row {
                anchors.centerIn: parent
                spacing: root.fieldH * 0.20 * 0.38
                visible: !root.checking && !root.failed && password.text.length > 0

                Repeater {
                    model: password.text.length
                    delegate: Rectangle {
                        width: root.fieldH * 0.20
                        height: width
                        radius: width / 2
                        color: root.textColor

                        // CONTENIDO entra: 210 ms.
                        scale: 0
                        Component.onCompleted: scale = 1
                        Behavior on scale {
                            NumberAnimation {
                                duration: 210
                                easing.type: Easing.Bezier
                                easing.bezierCurve: root.softOut
                            }
                        }
                    }
                }
            }
        }

        // ---- Pie: identidad a la izquierda, bateria a la derecha ------------
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.horizontalCenterOffset: -154
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: 124
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: 12
            color: root.dim
            text: "\u{F0004}  " + root.userName      // nf-md-account
        }

        Text {
            id: batteryLabel
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.horizontalCenterOffset: 154
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: 124
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: 12
            color: root.dim
            text: ""
        }

        // ---- Selector de sesion: el tercer dato del pie ----------------------
        // Va en la MISMA fila que el usuario y la bateria (offset 124), con la
        // misma fuente, el mismo cuerpo y el mismo gris. Entre esos dos hay 248
        // px libres, asi que no cuesta ni un pixel de alto ni una linea nueva:
        // el pie pasa de dos datos descolgados a una fila de tres.
        //
        // Si el modelo no diera ningun nombre, esto no se dibuja y la isla queda
        // EXACTAMENTE como estaba. Ese es el modo de fallo que interesa.
        Text {
            id: sessionLabel
            visible: root.sessionName !== ""
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: 124
            // Tope de ancho por si algun .desktop trae un nombre kilometrico:
            // antes de rozar al usuario o a la bateria, se corta.
            width: Math.min(implicitWidth, 232)
            elide: Text.ElideRight
            horizontalAlignment: Text.AlignHCenter
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: 12
            // El chevron aparece solo si hay a donde ir. Con una sola sesion
            // esto es un dato, no un boton, y no debe insinuar lo contrario.
            text: "\u{F0379}  " + root.sessionName          // nf-md-monitor
                + (sessionProbe.count > 1 ? "  \u{F0140}" : "")   // nf-md-chevron_down
            color: sessionArea.containsMouse ? root.accent : root.dim

            Behavior on color {
                ColorAnimation {
                    duration: 130                 // RESPUESTA
                    easing.type: Easing.Bezier
                    easing.bezierCurve: root.softOut
                }
            }

            MouseArea {
                id: sessionArea
                anchors.fill: parent
                anchors.margins: -8               // blanco de clic algo mayor
                enabled: sessionProbe.count > 1
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                onClicked: function (mouse) {
                    root.cycleSession(mouse.button === Qt.RightButton ? -1 : 1);
                }
            }
        }
    }

    // =========================================================================
    // Relojes y datos
    // =========================================================================
    Timer {
        interval: 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            clock.text = Qt.formatDateTime(new Date(), "HH:mm");
            dateLabel.text = root.localDate();
        }
    }

    Timer {
        interval: 30000
        running: true
        repeat: true
        onTriggered: root.refreshBattery()
    }

    // Mismo formato que ~/.config/hypr/scripts/lock-info.sh, y por el mismo
    // motivo: la sesion corre con LC_TIME=C pero la interfaz habla espanol.
    //
    // En ingles NO se reusa esa tabla ni se confia en el locale de la sesion:
    // se pide a Qt el locale en_GB explicito. Depender de LC_TIME=C daria el
    // mismo resultado hoy, pero el dia que alguien toque el entorno de SDDM la
    // fecha cambiaria de idioma sin que nadie hubiera tocado el tema.
    function localDate() {
        var d = new Date();
        if (root.english)
            return d.toLocaleDateString(Qt.locale("en_GB"), "dddd") + " · " +
                   d.toLocaleDateString(Qt.locale("en_GB"), "d MMMM");
        var days = ["Domingo", "Lunes", "Martes", "Miércoles",
                    "Jueves", "Viernes", "Sábado"];
        var months = ["enero", "febrero", "marzo", "abril", "mayo", "junio",
                      "julio", "agosto", "septiembre", "octubre",
                      "noviembre", "diciembre"];
        return days[d.getDay()] + " · " + d.getDate() +
               " de " + months[d.getMonth()];
    }

    // OJO: el XMLHttpRequest de QML **no admite modo sincrono**. Con
    // open(..., false) el send() lanza "Error: Invalid state" y te quedas sin
    // dato y sin pista. Todo lector de ficheros de aqui va por callback.
    function readFile(path, done) {
        var xhr = new XMLHttpRequest();
        xhr.onreadystatechange = function () {
            if (xhr.readyState === XMLHttpRequest.DONE)
                done(xhr.responseText ? xhr.responseText.trim() : "");
        };
        try {
            xhr.open("GET", "file://" + path, true);
            xhr.send();
        } catch (e) {
            done("");
        }
    }

    // Se descubre una vez cual es la bateria y luego solo se releen sus datos.
    property string batteryPath: ""

    function findBattery(i) {
        if (i > 2)
            return;
        var base = "/sys/class/power_supply/BAT" + i;
        readFile(base + "/capacity", function (cap) {
            if (cap === "") {
                root.findBattery(i + 1);
            } else {
                root.batteryPath = base;
                root.refreshBattery();
            }
        });
    }

    function refreshBattery() {
        if (batteryPath === "")
            return;
        readFile(batteryPath + "/capacity", function (cap) {
            if (cap === "") {
                batteryLabel.text = "";
                return;
            }
            root.readFile(root.batteryPath + "/status", function (st) {
                var icon = (st === "Charging" || st === "Full")
                         ? "\u{F0084}"                // nf-md-battery_charging
                         : "\u{F0079}";               // nf-md-battery
                batteryLabel.text = icon + "  " + cap + "%";
            });
        });
    }

    // =========================================================================
    // Login
    // =========================================================================
    function doLogin() {
        if (checking || password.text.length === 0)
            return;
        checking = true;
        failed = false;
        // sessionCurrent ES sessionModel.lastIndex mientras nadie toque el
        // selector del pie, asi que sin tocar nada esto se comporta igual que
        // cuando aqui ponia lastIndex a pelo.
        sddm.login(userName, password.text, sessionCurrent);
    }

    Connections {
        target: sddm

        function onLoginFailed() {
            root.checking = false;
            root.failed = true;
            root.attempts += 1;
            password.text = "";
            password.forceActiveFocus();
        }

        function onLoginSucceeded() {
            root.checking = false;
            island.opacity = 0;
        }
    }

    // Foco auto-reparador. Medido: ni Component.onCompleted ni un unico
    // reintento diferido agarran el foco — la ventana se activa despues y Qt no
    // se lo da a nadie, asi que el campo se queda mudo hasta que haces clic.
    // Este timer reinsiste mientras el campo NO tenga el foco y se apaga solo
    // en cuanto lo consigue, asi que tambien lo recupera si se pierde.
    Timer {
        interval: 200
        running: !password.activeFocus
        repeat: true
        triggeredOnStart: true
        onTriggered: password.forceActiveFocus()
    }

    // Ultimo recurso: un clic en cualquier parte devuelve el foco al campo.
    MouseArea {
        anchors.fill: parent
        z: -1
        onClicked: password.forceActiveFocus()
    }

    Component.onCompleted: {
        password.forceActiveFocus();
        findBattery(0);
        // El acento vivo. El fichero lo escribe tu usuario, no root, asi que se
        // valida antes de usarlo: solo se acepta exactamente #rrggbb. Si no
        // esta o no cuela, se queda el de theme.conf y no se nota nada.
        readFile("/var/lib/sddm-hyprisland/accent", function (txt) {
            if (/^#[0-9a-fA-F]{6}$/.test(txt))
                root.accent = txt;
        });
    }
}
