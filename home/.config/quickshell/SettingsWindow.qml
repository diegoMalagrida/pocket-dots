// SettingsWindow.qml — la app de Ajustes del sistema.
//
// POR QUÉ NO ES UN PANEL DEL NOTCH: todos los paneles del notch son
// transitorios (abres, haces una cosa, se cierran al pinchar fuera). Unos
// ajustes son lo contrario: exploras, tocas un slider y quieres mirar el
// terminal a ver si funcionó. Que se cerrase al pinchar fuera sería hostil, y
// anclado arriba del todo taparía media pantalla. Así que es una ventana
// flotante de verdad (xdg-toplevel) — pero con el mismo lenguaje visual que el
// notch, y se lanza desde él.
//
// ANATOMÍA (y el porqué de cada pieza):
//   · barra lateral  — identidad + buscador + secciones. El buscador está aquí
//     y no sobre el contenido porque es lo primero que recibe el foco al abrir:
//     abres y escribes.
//   · cabecera fija  — el título de la sección NO scrollea. Antes cada sección
//     pintaba su propio título dentro del scroll y al volver a una sección con
//     el scroll a medias te recibía un texto cortado por arriba.
//   · contenido      — tarjetas (SettingsControls.Card_).
//   · pie            — la descripción del ajuste que tienes debajo del ratón.
//     Ver el comentario largo de SettingsControls.qml: es lo que permite que
//     las filas midan 42 px en vez de tres líneas.
//
// Que se abra flotante, centrada y de 900x620 lo fuerza Hyprland con una
// windowrule sobre class org.quickshell + title Ajustes (hyprland.conf).
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import QtQuick
import QtQuick.Layouts

Scope {
    id: root

    readonly property var sections: [
        { id: "look",   icon: "󰸌", label: I18n.tr("Apariencia"), desc: I18n.tr("Forma, barra, tipografía y fondo") },
        { id: "system", icon: "󰒓", label: I18n.tr("Sistema"), desc: I18n.tr("Pantalla, energía, red y notificaciones") },
        { id: "audio",  icon: "󰕾", label: I18n.tr("Sonido"), desc: I18n.tr("Volumen y dispositivos PipeWire") },
        { id: "bt",     icon: "󰂯", label: I18n.tr("Bluetooth"), desc: I18n.tr("Radio, equipos guardados y descubrimiento") },
        { id: "keys",   icon: "󰌌", label: I18n.tr("Atajos"), desc: I18n.tr("Mapa vivo de teclas de Hyprland") },
        { id: "about",  icon: "󰋼", label: I18n.tr("Acerca de"), desc: I18n.tr("Hardware, software y rutas del rice") }
    ]
    property string section: "look"
    property bool actionArmed: false
    readonly property bool searching: ShellState.settingsQuery.trim().length > 0
    readonly property int totalHits: look.matchCount + system.matchCount + audio.matchCount
        + bt.matchCount + keys.matchCount + about.matchCount
    readonly property string actionConfirmHint: I18n.tr("Vuelve a pulsar «Confirmar» para restablecer todos los ajustes de Apariencia.")

    function sectionInfo(id) {
        for (let i = 0; i < root.sections.length; i++)
            if (root.sections[i].id === id) return root.sections[i];
        return ({ id: "", icon: "", label: "", desc: "" });
    }
    function sectionHits(id) {
        if (id === "look") return look.matchCount;
        if (id === "system") return system.matchCount;
        if (id === "audio") return audio.matchCount;
        if (id === "bt") return bt.matchCount;
        if (id === "keys") return keys.matchCount;
        return about.matchCount;
    }
    function selectFirstMatchingSection() {
        if (!root.searching || root.totalHits === 0 || root.sectionHits(root.section) > 0) return;
        for (let i = 0; i < root.sections.length; i++) {
            if (root.sectionHits(root.sections[i].id) > 0) {
                root.section = root.sections[i].id;
                return;
            }
        }
    }
    function cancelActionConfirm() {
        root.actionArmed = false;
        confirmTimer.stop();
        if (ShellState.settingsHint === root.actionConfirmHint) ShellState.settingsHint = "";
    }
    function runSectionAction(sec) {
        if (!sec) return;
        if (sec.actionConfirm === true && !root.actionArmed) {
            root.actionArmed = true;
            ShellState.settingsHint = root.actionConfirmHint;
            confirmTimer.restart();
            return;
        }
        root.cancelActionConfirm();
        sec.actionRun();
    }
    // ↑/↓ recorren solo las secciones que tienen resultados, sin sacar el
    // foco del buscador.
    function step(d) {
        const available = [];
        for (let i = 0; i < root.sections.length; i++) {
            if (!root.searching || root.sectionHits(root.sections[i].id) > 0)
                available.push(root.sections[i].id);
        }
        if (available.length === 0) return;
        let at = available.indexOf(root.section);
        if (at < 0) at = 0;
        root.section = available[(at + d + available.length) % available.length];
    }
    onSectionChanged: root.cancelActionConfirm()

    // Entrar directamente en una sección. Si Ajustes YA estaba abierta en esa
    // misma sección, la tecla la cierra: el resto de atajos del notch son
    // interruptores y este no va a ser la excepción.
    function openAt(id) {
        if (ShellState.settingsOpen && root.section === id) {
            ShellState.settingsOpen = false;
            return;
        }
        root.section = id;
        ShellState.settingsOpen = true;
    }

    GlobalShortcut { name: "settings"; description: I18n.tr("Ajustes del sistema"); onPressed: ShellState.toggleSettings() }
    // Super+K. Antes abría ~/.config/hypr/list_keybinds.sh: un menú de rofi que
    // parseaba el mismo hyprland.conf que parsea SettingsShortcuts.qml, o sea
    // dos listas de atajos que solo se parecían mientras nadie tocara ninguna.
    // Ahora la tecla entra en la sección «Atajos» y no hay segunda lista.
    GlobalShortcut { name: "keybinds"; description: I18n.tr("Mapa de atajos de teclado"); onPressed: root.openAt("keys") }

    // La misma puerta, pero para quien no tiene el id de esta ventana: el menú
    // de comandos (ShellState.runAction) y `qs ipc call notch keys`.
    Connections {
        target: ShellState
        function onSettingsSection(id) { root.openAt(id); }
    }

    // La ventana nace SIN FOCO de forma intermitente: aparece, pero el teclado
    // se queda en la ventana de antes, así que el buscador —que se lleva el foco
    // al abrir para que «abras y escribas»— no recibía ni una tecla, y Esc
    // tampoco cerraba. Solo se salvaba cuando el puntero caía dentro y el
    // follow_mouse de Hyprland le daba el foco de rebote.
    //
    // Por eso se pide a mano. Los 90 ms son para que Hyprland ya tenga mapeada
    // la superficie: pedirlo en el mismo instante en que se hace visible llega
    // demasiado pronto y el dispatcher no encuentra la ventana.
    Timer {
        id: grabFocus
        interval: 90
        onTriggered: Hyprland.dispatch('hl.dsp.focus({ window = "title:Ajustes" })')
    }

    // Pinchar fuera cierra Ajustes, con el mismo mecanismo que los paneles del
    // notch: el grab de foco de Hyprland. Mientras está activo, un clic fuera
    // de la ventana cancela el grab y Hyprland nos avisa.
    //
    // Ese clic se lo come el grab, como en cualquier menú: la app de debajo no
    // lo recibe, solo se cierra Ajustes. Es el precio de que «fuera» signifique
    // fuera de verdad.
    //
    // POR QUÉ NO SE MIRA EL FOCO A SECAS, que sería lo obvio: con
    // follow_mouse = 1 el foco se va con solo CRUZAR el ratón por encima de otra
    // ventana, así que Ajustes se cerraría sola en cuanto miras el terminal a
    // ver si el slider ha hecho algo. Tampoco valen las otras dos vías, las dos
    // probadas: un bind sobre el botón izquierdo sin modificadores se registra
    // pero no dispara nunca (en 0.56 los binds de ratón necesitan modificador),
    // y `hl.config` deja apagar follow_mouse en caliente solo de boquilla —
    // `getoption` dice 0 y el foco sigue yéndose con el ratón.
    //
    // El retardo al armarlo es por lo mismo que en TopShell: recién mapeada la
    // ventana, Hyprland cancela el grab al instante y Ajustes se cerraba sola
    // nada más abrirla.
    property bool grabArmed: false
    Timer { id: grabArm; interval: 400; onTriggered: root.grabArmed = true }

    Timer {
        id: confirmTimer
        interval: 2500
        onTriggered: root.cancelActionConfirm()
    }

    FloatingWindow {
        id: win
        visible: ShellState.settingsOpen
        title: "Ajustes"
        // Sigue siendo una ventana contenida, pero ya no conserva el tamaño de
        // cuando había muchas menos filas. El alto deja ver Energía completa y
        // el ancho da aire a nombres de dispositivos y atajos.
        implicitWidth: 900
        implicitHeight: 620
        minimumSize.width: 780
        minimumSize.height: 500
        color: "#0b0b0b"

        // Al abrir: buscador vacío y con el foco, y sin descripción heredada de
        // la vez anterior.
        onVisibleChanged: {
            if (!win.visible) {
                root.cancelActionConfirm();
                ShellState.settingsQuery = "";
                ShellState.settingsHint = "";
                grabFocus.stop();
                root.grabArmed = false;
                grabArm.stop();
                return;
            }
            search.text = "";
            ShellState.settingsHint = "";
            search.forceActiveFocus();
            grabFocus.restart();
            root.grabArmed = false;
            grabArm.restart();
        }

        HyprlandFocusGrab {
            windows: [win]
            active: ShellState.settingsOpen && root.grabArmed
            onCleared: ShellState.settingsOpen = false
        }

        Item {
            anchors.fill: parent
            focus: true
            Keys.onEscapePressed: ShellState.settingsOpen = false


            Shortcut {
                sequence: "Ctrl+F"
                context: Qt.ApplicationShortcut
                onActivated: {
                    search.forceActiveFocus();
                    search.selectAll();
                }
            }
            Shortcut {
                sequence: "Ctrl+W"
                context: Qt.ApplicationShortcut
                onActivated: ShellState.settingsOpen = false
            }

            RowLayout {
                anchors.fill: parent
                spacing: 0

                // ══════════ barra lateral ══════════
                Rectangle {
                    Layout.preferredWidth: 224
                    Layout.fillHeight: true
                    color: "#000000"

                    ColumnLayout {
                        anchors { fill: parent; topMargin: 22; leftMargin: 14; rightMargin: 14 }
                        spacing: 5

                        Text {
                            Layout.leftMargin: 8
                            text: I18n.tr("Ajustes")
                            color: "#ffffff"
                            font.family: Appearance.fontUI
                            font.pixelSize: 19
                            font.weight: Font.DemiBold
                        }

                        // ─────── buscador ───────
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.topMargin: 12
                            Layout.bottomMargin: root.searching ? 2 : 9
                            implicitHeight: 38
                            radius: 12
                            color: search.activeFocus ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(1, 1, 1, 0.075)
                            border.width: 1
                            border.color: search.activeFocus
                                ? Qt.rgba(Colors.accent.r, Colors.accent.g, Colors.accent.b, 0.42)
                                : Qt.rgba(1, 1, 1, 0.04)
                            Behavior on color { ColorAnimation { duration: Appearance.mQuick; easing.type: Easing.OutQuad } }
                            Behavior on border.color { ColorAnimation { duration: Appearance.mQuick } }

                            RowLayout {
                                anchors { fill: parent; leftMargin: 10; rightMargin: 8 }
                                spacing: 7

                                Text {
                                    text: "󰍉"
                                    color: search.activeFocus ? Colors.accent : "#828282"
                                    font.family: Appearance.font
                                    font.pixelSize: 12
                                }

                                Item {
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true

                                    TextInput {
                                        id: search
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: parent.width
                                        color: "#ffffff"
                                        selectionColor: Qt.rgba(Colors.accent.r, Colors.accent.g, Colors.accent.b, 0.45)
                                        selectByMouse: true
                                        clip: true
                                        font.family: Appearance.fontUI
                                        font.pixelSize: Appearance.fsS
                                        onTextChanged: {
                                            ShellState.settingsQuery = text;
                                            root.cancelActionConfirm();
                                            Qt.callLater(root.selectFirstMatchingSection);
                                        }

                                        Keys.onDownPressed: root.step(1)
                                        Keys.onUpPressed: root.step(-1)
                                        Keys.onEscapePressed: {
                                            if (search.text.length > 0) search.text = "";
                                            else ShellState.settingsOpen = false;
                                        }
                                    }

                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        // 2 px para que el cursor parpadeante no
                                        // se pegue a la B y parezca parte de ella
                                        x: 2
                                        visible: search.text.length === 0
                                        text: I18n.tr("Buscar en Ajustes")
                                        color: "#707070"
                                        font.family: Appearance.fontUI
                                        font.pixelSize: Appearance.fsS
                                    }
                                }

                                Text {
                                    visible: search.text.length > 0
                                    text: "󰅖"
                                    color: clearMa.containsMouse ? "#ffffff" : "#828282"
                                    font.family: Appearance.font
                                    font.pixelSize: 11
                                    MouseArea {
                                        id: clearMa
                                        anchors.fill: parent
                                        anchors.margins: -5
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: { search.text = ""; search.forceActiveFocus(); }
                                    }
                                }
                            }
                        }

                        Text {
                            Layout.leftMargin: 9
                            Layout.bottomMargin: 4
                            visible: root.searching
                            text: root.totalHits === 0 ? I18n.tr("Sin coincidencias")
                                : (root.totalHits === 1 ? I18n.tr("{0} resultado", root.totalHits)
                                                        : I18n.tr("{0} resultados", root.totalHits))
                            color: root.totalHits === 0 ? Colors.warn : "#777777"
                            font.family: Appearance.fontUI
                            font.pixelSize: Appearance.fsXS
                        }

                        // ─────── secciones ───────
                        Repeater {
                            model: root.sections
                            Rectangle {
                                id: navItem
                                required property var modelData
                                readonly property bool sel: root.section === modelData.id
                                readonly property int hits: root.sectionHits(modelData.id)

                                Layout.fillWidth: true
                                Layout.preferredHeight: 40
                                visible: !root.searching || navItem.hits > 0
                                radius: 12
                                color: navItem.sel ? Qt.rgba(Colors.accent.r, Colors.accent.g, Colors.accent.b, 0.24)
                                     : navMa.containsMouse ? Qt.rgba(1, 1, 1, 0.07) : "transparent"
                                Behavior on color { ColorAnimation { duration: Appearance.mQuick; easing.type: Easing.OutQuad } }

                                RowLayout {
                                    anchors { fill: parent; leftMargin: 12; rightMargin: 12 }
                                    spacing: 11
                                    Text {
                                        text: navItem.modelData.icon
                                        color: navItem.sel ? Colors.accent : "#9a9a9a"
                                        font.family: Appearance.font
                                        font.pixelSize: 14
                                    }
                                    Text {
                                        Layout.fillWidth: true
                                        text: navItem.modelData.label
                                        color: navItem.sel ? "#ffffff" : "#b0b0b0"
                                        font.family: Appearance.fontUI
                                        font.pixelSize: Appearance.fsS
                                        font.weight: navItem.sel ? Font.Medium : Font.Normal
                                    }
                                    Rectangle {
                                        visible: root.searching
                                        implicitWidth: Math.max(22, hitText.implicitWidth + 12)
                                        implicitHeight: 20
                                        radius: 7
                                        color: navItem.sel
                                            ? Qt.rgba(Colors.accent.r, Colors.accent.g, Colors.accent.b, 0.28)
                                            : Qt.rgba(1, 1, 1, 0.07)
                                        Text {
                                            id: hitText
                                            anchors.centerIn: parent
                                            text: navItem.hits
                                            color: navItem.sel ? "#ffffff" : "#8a8a8a"
                                            font.family: Appearance.fontUI
                                            font.pixelSize: 10
                                            font.weight: Font.Medium
                                        }
                                    }
                                }
                                MouseArea {
                                    id: navMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.section = navItem.modelData.id
                                }
                            }
                        }

                        Item { Layout.fillHeight: true }

                        ColumnLayout {
                            Layout.leftMargin: 8
                            Layout.rightMargin: 8
                            Layout.bottomMargin: 16
                            spacing: 3
                            Text {
                                text: I18n.tr("Ctrl+F  buscar  ·  Esc  cerrar")
                                color: "#666666"
                                font.family: Appearance.fontUI
                                font.pixelSize: 10
                            }
                            Text {
                                text: I18n.tr("Quickshell · rice de diego")
                                color: "#454545"
                                font.family: Appearance.fontUI
                                font.pixelSize: 10
                            }
                        }
                    }
                }

                // ══════════ contenido ══════════
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: 0

                    // ─────── cabecera fija ───────
                    Item {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 72

                        RowLayout {
                            anchors { fill: parent; leftMargin: 24; rightMargin: 18 }
                            spacing: 13

                            Rectangle {
                                Layout.preferredWidth: 38
                                Layout.preferredHeight: 38
                                radius: 12
                                color: Qt.rgba(Colors.accent.r, Colors.accent.g, Colors.accent.b, 0.18)
                                Text {
                                    anchors.centerIn: parent
                                    text: root.sectionInfo(root.section).icon
                                    color: Colors.accent
                                    font.family: Appearance.font
                                    font.pixelSize: 17
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 1
                                Text {
                                    Layout.fillWidth: true
                                    text: root.sectionInfo(root.section).label
                                    color: "#ffffff"
                                    elide: Text.ElideRight
                                    font.family: Appearance.fontUI
                                    font.pixelSize: 18
                                    font.weight: Font.DemiBold
                                }
                                Text {
                                    Layout.fillWidth: true
                                    readonly property int hits: root.sectionHits(root.section)
                                    text: root.searching
                                        ? (root.totalHits === 0 ? I18n.tr("Sin coincidencias en todos los ajustes")
                                            : (hits === 1 ? I18n.tr("{0} resultado en esta sección", hits)
                                                          : I18n.tr("{0} resultados en esta sección", hits)))
                                        : root.sectionInfo(root.section).desc
                                    color: root.totalHits === 0 && root.searching ? Colors.warn : "#7f7f7f"
                                    elide: Text.ElideRight
                                    font.family: Appearance.fontUI
                                    font.pixelSize: Appearance.fsXS
                                }
                            }

                            // acción propia de cada sección (Restablecer, Buscar…)
                            SettingsControls.Btn_ {
                                readonly property var sec: content.current
                                visible: !root.searching && sec
                                    && sec.actionText !== undefined && sec.actionText.length > 0
                                text: visible ? (root.actionArmed ? I18n.tr("Confirmar") : sec.actionText) : ""
                                danger: visible && sec.actionDanger === true
                                onClicked: root.runSectionAction(sec)
                            }

                            Rectangle {
                                Layout.preferredWidth: 32
                                Layout.preferredHeight: 32
                                radius: 10
                                color: closeMa.containsMouse ? Qt.rgba(1, 1, 1, 0.11) : Qt.rgba(1, 1, 1, 0.055)
                                Behavior on color { ColorAnimation { duration: Appearance.mQuick } }
                                Text {
                                    anchors.centerIn: parent
                                    text: "󰅖"
                                    color: closeMa.containsMouse ? "#ffffff" : "#8a8a8a"
                                    font.family: Appearance.font
                                    font.pixelSize: 12
                                }
                                MouseArea {
                                    id: closeMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onEntered: ShellState.settingsHint = I18n.tr("Cerrar Ajustes · Ctrl+W")
                                    onExited: if (ShellState.settingsHint === I18n.tr("Cerrar Ajustes · Ctrl+W")) ShellState.settingsHint = ""
                                    onClicked: ShellState.settingsOpen = false
                                }
                            }
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 1
                        color: Qt.rgba(1, 1, 1, 0.06)
                    }

                    // ─────── secciones ───────
                    // Se instancian todas y se enseña una: así Bluetooth puede
                    // atar su búsqueda a `visible` y ninguna pierde su estado al
                    // cambiar de pestaña.
                    Item {
                        id: content
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        readonly property bool noResults: root.searching && root.totalHits === 0

                        readonly property var current: root.section === "look" ? look
                                                     : root.section === "system" ? system
                                                     : root.section === "audio" ? audio
                                                     : root.section === "bt" ? bt
                                                     : root.section === "keys" ? keys
                                                     : about

                        // El `ShellState.settingsOpen` de cada `visible` NO sobra:
                        // esconder una VENTANA no cambia el `visible` de lo que
                        // lleva dentro, así que al cerrar Ajustes ninguna sección
                        // se enteraba. Consecuencias, todas reales: volvías a
                        // abrir y te recibía el scroll a medias de la vez
                        // anterior (justo lo que dice evitar el comentario de
                        // cada sección), «Acerca de» enseñaba el uptime viejo, y
                        // Bluetooth se quedaba escaneando para siempre con la
                        // ventana cerrada. Atando también a settingsOpen, cerrar
                        // y abrir es un cambio de visibilidad de verdad y cada
                        // sección hace su onVisibleChanged.
                        SettingsAppearance { id: look;   anchors.fill: parent; visible: ShellState.settingsOpen && !content.noResults && root.section === "look" }
                        SettingsSystem     { id: system; anchors.fill: parent; visible: ShellState.settingsOpen && !content.noResults && root.section === "system" }
                        SettingsAudio      { id: audio;  anchors.fill: parent; visible: ShellState.settingsOpen && !content.noResults && root.section === "audio" }
                        SettingsBluetooth  { id: bt;     anchors.fill: parent; visible: ShellState.settingsOpen && !content.noResults && root.section === "bt" }
                        SettingsShortcuts  { id: keys;   anchors.fill: parent; visible: ShellState.settingsOpen && !content.noResults && root.section === "keys" }
                        SettingsAbout      { id: about;  anchors.fill: parent; visible: ShellState.settingsOpen && !content.noResults && root.section === "about" }

                        ColumnLayout {
                            anchors.centerIn: parent
                            width: Math.min(360, parent.width - 56)
                            spacing: 8
                            visible: content.noResults
                            Text {
                                Layout.alignment: Qt.AlignHCenter
                                text: "󰍉"
                                color: "#666666"
                                font.family: Appearance.font
                                font.pixelSize: 26
                            }
                            Text {
                                Layout.fillWidth: true
                                text: I18n.tr("No hay ajustes para «{0}»", ShellState.settingsQuery.trim())
                                color: "#d2d2d2"
                                horizontalAlignment: Text.AlignHCenter
                                wrapMode: Text.Wrap
                                font.family: Appearance.fontUI
                                font.pixelSize: Appearance.fsS
                                font.weight: Font.Medium
                            }
                            Text {
                                Layout.fillWidth: true
                                text: I18n.tr("Prueba otra palabra o pulsa Esc para limpiar la búsqueda.")
                                color: "#777777"
                                horizontalAlignment: Text.AlignHCenter
                                wrapMode: Text.Wrap
                                font.family: Appearance.fontUI
                                font.pixelSize: Appearance.fsXS
                            }
                        }
                    }

                    // ─────── pie: qué hace el ajuste que tienes debajo ───────
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 1
                        color: Qt.rgba(1, 1, 1, 0.06)
                    }
                    Item {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 48

                        RowLayout {
                            anchors { fill: parent; leftMargin: 24; rightMargin: 18 }
                            spacing: 10
                            Text {
                                text: "󰋼"
                                color: ShellState.settingsHint.length > 0 ? Colors.accent : "#606060"
                                font.family: Appearance.font
                                font.pixelSize: 12
                                Behavior on color { ColorAnimation { duration: Appearance.mQuick } }
                            }
                            Text {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                verticalAlignment: Text.AlignVCenter
                                wrapMode: Text.Wrap
                                maximumLineCount: 2
                                elide: Text.ElideRight
                                text: ShellState.settingsHint.length > 0 ? ShellState.settingsHint
                                    : (content.current && content.current.note !== undefined ? content.current.note : "")
                                color: ShellState.settingsHint.length > 0 ? "#ababab" : "#6f6f6f"
                                font.family: Appearance.fontUI
                                font.pixelSize: Appearance.fsXS
                                // el hover es un estado: entra y sale igual (ley 3)
                                Behavior on color { ColorAnimation { duration: Appearance.mQuick } }
                            }
                        }
                    }
                }
            }
        }
    }
}
