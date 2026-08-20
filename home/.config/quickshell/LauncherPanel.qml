// LauncherPanel.qml — el centro de comandos, desplegado DESDE el notch.
//
// Se abre con Super+R o pulsando el logo de Arch, y el notch se estira hasta
// convertirse en él. Teclado: escribir filtra, ↑/↓ (o Ctrl+J/K) mueve, Enter
// ejecuta, Esc cierra.
//
// Ya no busca solo aplicaciones. El PRIMER CARÁCTER decide qué se busca:
//
//   (nada)  aplicaciones · calculadora · temporizador · favoritos
//   #       historial del portapapeles (texto e imágenes)
//   >       acciones del sistema
//   @       ventanas abiertas
//
// El prefijo se CONSUME: al escribirlo desaparece del campo y en su sitio sale
// una etiqueta con el nombre del modo. Si se quedara escrito habría dos cosas
// diciendo lo mismo, y el campo empezaría con un carácter que no es parte de lo
// que buscas. Se sale con un borrado sobre el campo vacío, que es donde la mano
// va sola cuando quieres deshacer.
//
// La lógica y los datos de cada modo viven en ShellState (la casa es así: este
// fichero es interfaz). Aquí solo está cómo se ve y cómo se navega.
//
// El foco de teclado lo da TopShell poniendo la capa en WlrKeyboardFocus
// .OnDemand mientras este panel está abierto.
import Quickshell
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Item {
    id: root

    readonly property bool active: ShellState.panel === "launcher"

    // El modo vive en ShellState y no aquí porque hay quien lo decide desde
    // fuera: Super+Shift+V abre directamente en portapapeles, y la acción
    // "Portapapeles" del modo ">" salta al modo "#" sin cerrar el panel.
    readonly property string mode: ShellState.launcherMode
    readonly property var modeInfo: ShellState.launcherModeInfo(root.mode)
    readonly property bool isApps: root.mode === "apps"

    property var results: []

    // QUIÉN ELIGE EL DELEGADO. Lo eligen LOS DATOS, no el modo, y la diferencia
    // no es teórica: `mode` es un enlace declarado arriba del todo y los
    // resultados los recarga un Connections declarado más abajo, así que al
    // cambiar de modo Qt actualiza primero el enlace y después el manejador. En
    // ese hueco de un fotograma la lista se repintaba con el delegado NUEVO y
    // los datos VIEJOS: el delegado de ventanas recibía aplicaciones y pedía
    // campos que no existen. Salían cinco avisos en el log por cada "@" que
    // escribías.
    //
    // Preguntándoselo a la primera fila esto no puede pasar, porque la respuesta
    // cambia exactamente a la vez que los datos. Las entradas de los tres modos
    // nuevos se etiquetan en ShellState; una entrada .desktop no lleva `kind` y
    // por eso el caso por defecto es "apps".
    readonly property string listKind: root.results.length > 0
        ? (root.results[0].kind || "apps") : root.mode

    // Calculadora: si lo escrito es una cuenta, sale arriba y es lo que está
    // seleccionado por defecto. Enter copia el resultado al portapapeles.
    property var calc: null
    readonly property bool hasCalc: root.calc !== null

    // Temporizador: si lo escrito es una duración ("10m", "1h30", "90s"), la
    // MISMA fila de arriba propone una cuenta atrás y Enter la arranca.
    //
    // Ni la calculadora ni el temporizador llevan prefijo, y no es un olvido: no
    // son un modo. Son lo que pasa cuando lo que escribes resulta ser una cuenta
    // o una duración. Fueron los que abrieron la puerta a que en el lanzador se
    // escriban cosas que no son nombres de aplicación; los modos solo terminan
    // esa idea.
    property int timerSec: -1
    readonly property bool hasTimer: root.timerSec > 0

    // La fila destacada es una sola y solo puede ser una cosa: "10m" no es una
    // cuenta y "2+2" no es una duración, así que nunca compiten.
    readonly property bool hasSpecial: root.hasCalc || root.hasTimer
    property bool calcSelected: false

    // ─────────────── favoritos ───────────────
    // La fila fijada de arriba. El orden EN PANTALLA es propio del panel y no de
    // Config a propósito: mientras arrastras, lo guardado no cambia. Si se
    // escribiera el fichero a cada píxel, la lista se repintaría entera y los
    // delegados se recrearían justo debajo del dedo, matando el gesto a medias.
    // Solo se confirma al soltar.
    property var favShown: []
    property int favDrag: -1         // índice que se arrastra, -1 = ninguno
    property bool favMoving: false   // ya superó el umbral: es arrastre, no clic
    property int favSlot: -1         // ranura de inserción (0..n) bajo el puntero
    property real favGhostX: 0
    property real favGhostY: 0
    property string favHover: ""     // nombre del favorito bajo el ratón

    // Solo en el modo de aplicaciones y con el campo vacío: en cuanto escribes
    // manda la búsqueda, y la fila desaparece para no robarle sitio.
    readonly property bool favVisible: root.isApps && field.text.length === 0
                                       && root.favShown.length > 0

    function syncFavs() { if (root.favDrag < 0) root.favShown = ShellState.favApps; }

    // Las tres pistas de la derecha: solo con el campo vacío en modo
    // aplicaciones. Es la única señal de que los modos existen, y por eso está
    // donde estás mirando cuando abres el lanzador y aún no has escrito nada.
    readonly property bool hintsVisible: root.isApps && field.text.length === 0
                                         && root.favHover.length === 0

    Connections {
        target: ShellState

        function onFavAppsChanged() {
            root.syncFavs();
            ShellState.launcherFavs = root.favVisible;
        }

        // Cambiar de modo es empezar de cero: el texto que había buscaba otra
        // cosa. Vale igual para el prefijo tecleado, para Super+Shift+V y para
        // la acción "Portapapeles".
        function onLauncherModeChanged() {
            // Vaciar la lista ANTES que nada, y hacerlo aunque el panel esté
            // cerrado. El delegado se elige por el modo, así que cambia en el
            // mismo instante en que cambia `mode`, pero los resultados son
            // todavía los del modo anterior: durante ese hueco el delegado del
            // portapapeles recibe acciones del sistema y pide campos que no
            // existen (`thumb`, `image`). Se veía como tres avisos de TypeError
            // en el log cada vez que Super+Shift+V abría el panel estando
            // cerrado, porque ahí el `return` de abajo se saltaba el refresco.
            root.results = [];
            if (!root.active) return;
            field.text = "";
            root.enterMode();
        }

        // Los datos de estos dos modos llegan tarde (un proceso, una consulta al
        // socket de Hyprland), así que la lista se vuelve a filtrar cuando caen.
        function onClipItemsChanged() { if (root.active && root.mode === "clip") root.refresh(); }
        function onWinItemsChanged() { if (root.active && root.mode === "win") root.refresh(); }
    }

    // ¿Manda el teclado o el ratón? Al abrirse manda el teclado, SIEMPRE.
    // Si no, el puntero que casualmente estaba encima de una fila secuestra la
    // selección; y peor: al escribir, la lista se refiltra y las filas se mueven
    // bajo un cursor quieto, disparando onEntered y robando el foco a cada
    // pulsación. El ratón solo recupera el mando si de verdad se MUEVE.
    property bool mouseNav: false
    property point lastMouse: Qt.point(-1, -1)

    // Único criterio para dar el mando al ratón: que el PUNTERO haya cambiado de
    // sitio. Distingue los dos casos que molestaban:
    //   · al abrir, Wayland manda un evento por "entrar" en la superficie nueva
    //     aunque el ratón esté quieto -> el primero solo fija la referencia;
    //   · al escribir, la lista se refiltra y las filas pasan bajo un cursor
    //     quieto -> mismo punto, así que no cuenta.
    function pointerMoved(px, py) {
        if (root.lastMouse.x < 0) { root.lastMouse = Qt.point(px, py); return false; }
        if (px === root.lastMouse.x && py === root.lastMouse.y) return false;
        root.lastMouse = Qt.point(px, py);
        return true;
    }

    // Entrar en un modo: pedir sus datos y refiltrar. El portapapeles se relee
    // SIEMPRE (cuesta centésimas y una lista de copiado desfasada no sirve de
    // nada); ShellState ya ignora la petición si hay una en vuelo.
    function enterMode() {
        if (root.mode === "clip") ShellState.clipRefresh();
        else if (root.mode === "win") ShellState.winRefresh();
        root.refresh();
    }

    function refresh() {
        root.mouseNav = false;
        // Fuera del modo de aplicaciones no hay cuentas ni duraciones: "2+2" en
        // el portapapeles es texto que buscar, no una suma.
        root.calc = root.isApps ? ShellState.calcEval(field.text) : null;
        root.timerSec = root.isApps ? ShellState.parseDuration(field.text) : -1;

        switch (root.mode) {
        case "clip": root.results = ShellState.searchClip(field.text); break;
        case "cmd":  root.results = ShellState.searchActions(field.text); break;
        case "win":  root.results = ShellState.searchWins(field.text); break;
        default:     root.results = ShellState.searchApps(field.text); break;
        }

        root.calcSelected = root.hasSpecial;
        list.currentIndex = (!root.hasSpecial && root.results.length > 0) ? 0 : -1;
        root.syncFavs();

        // para que el notch se ajuste a lo que hay
        ShellState.launcherRows = root.waiting ? ShellState.launcherMaxRows : root.results.length;
        ShellState.launcherCalc = root.hasSpecial;
        ShellState.launcherFavs = root.favVisible;
    }

    // Mientras el proceso del portapapeles contesta no se sabe cuántas filas
    // habrá. Si se publicara 0, el panel nacería del tamaño de "Sin resultados"
    // y daría un salto hacia abajo al llegar los datos. Se pide el máximo y
    // encoge, que es su gesto de siempre y además ocurre dentro de la animación
    // de apertura.
    readonly property bool waiting: root.mode === "clip" && ShellState.clipLoading
                                    && root.results.length === 0

    function jump(i) {
        if (root.results.length === 0) return;
        root.mouseNav = false;
        list.currentIndex = Math.max(0, Math.min(root.results.length - 1, i));
        list.positionViewAtIndex(list.currentIndex, ListView.Contain);
    }

    // Qué hace Enter. Cada modo sabe lo suyo; la fila destacada (calculadora o
    // temporizador) va antes que todo porque solo existe en el modo de apps.
    function launchCurrent() {
        if (root.calcSelected && root.hasTimer) {
            ShellState.timerStart(root.timerSec);
            ShellState.closePanel();
            return;
        }
        if (root.calcSelected && root.hasCalc) {
            ShellState.copyText(ShellState.calcFormat(root.calc));
            ShellState.closePanel();
            return;
        }
        if (list.currentIndex < 0 || list.currentIndex >= root.results.length) return;
        const it = root.results[list.currentIndex];
        switch (root.mode) {
        case "clip": ShellState.clipCopy(it); break;
        case "cmd":  ShellState.runAction(it); break;
        case "win":  ShellState.focusWindow(it); break;
        default:     ShellState.launchApp(it); break;
        }
    }

    // Suprimir borra la entrada del portapapeles sin cerrar el panel: limpiar el
    // historial es justo la tarea en la que quieres seguir mirándolo. Rofi no
    // podía hacerlo (elegir una entrada cerraba el menú), así que esto es cosa
    // nueva del modo nativo.
    function deleteCurrent() {
        if (root.mode !== "clip") return;
        if (list.currentIndex < 0 || list.currentIndex >= root.results.length) return;
        const i = list.currentIndex;
        ShellState.clipDelete(root.results[i]);
        root.results = ShellState.searchClip(field.text);
        ShellState.launcherRows = root.results.length;
        // Quedarse donde estaba, no volver arriba: borrar tres seguidas es un
        // gesto normal, y saltar al principio después de cada una lo impide.
        list.currentIndex = root.results.length === 0 ? -1
            : Math.min(i, root.results.length - 1);
    }

    function move(delta) {
        root.mouseNav = false;
        // la fila de la calculadora se comporta como una posición más, encima de la lista
        if (root.calcSelected && delta > 0) {
            if (root.results.length === 0) return;
            root.calcSelected = false;
            list.currentIndex = 0;
            return;
        }
        if (root.hasSpecial && !root.calcSelected && delta < 0 && list.currentIndex === 0) {
            root.calcSelected = true;
            list.currentIndex = -1;
            return;
        }
        if (root.results.length === 0) return;
        let i = list.currentIndex + delta;
        if (i < 0) i = root.results.length - 1;
        if (i >= root.results.length) i = 0;
        list.currentIndex = i;
        list.positionViewAtIndex(i, ListView.Contain);
    }

    // Al abrirse: campo vacío, foco en el campo y el teclado al mando. El modo
    // NO se toca aquí: lo ha decidido quien abrió (togglePanel entra siempre en
    // "apps", openLauncher entra en el que le pidan).
    onActiveChanged: {
        if (root.active) {
            field.text = "";
            // Un arrastre a medias que se quedó colgado al cerrar el panel no
            // debe reaparecer al abrirlo otra vez.
            root.favDrag = -1; root.favMoving = false; root.favSlot = -1; root.favHover = "";
            root.enterMode();
            field.forceActiveFocus();
            refocus.restart();   // seguro: la capa tarda un instante en aceptar foco
            root.lastMouse = Qt.point(-1, -1);
        }
    }
    Timer {
        id: refocus
        interval: 120
        onTriggered: if (root.active) field.forceActiveFocus()
    }

    // Absorbe clics y rueda en el hueco para que no lleguen al notch de debajo
    // (si no, pinchar en el fondo del panel lo cerraría).
    MouseArea {
        anchors.fill: parent
        onWheel: function (w) { w.accepted = true; }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.topMargin: 4
        spacing: 0

        // ─────────────── buscador ───────────────
        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 22
            Layout.rightMargin: 22
            Layout.preferredHeight: 50
            spacing: 12

            // El icono de la izquierda es el del MODO: la lupa solo cuando de
            // verdad se buscan aplicaciones.
            Text {
                text: root.modeInfo.icon
                color: (field.text.length > 0 || !root.isApps) ? Colors.accent : "#6c6c6c"
                font.family: Appearance.font
                font.pixelSize: 17
                Behavior on color { ColorAnimation { duration: Appearance.mQuick; easing.type: Easing.OutQuad } }
            }

            // La etiqueta del modo, en el sitio exacto donde estaba el prefijo
            // que la creó. Es lo que hace honesto haberlo borrado del campo: el
            // carácter desaparece pero deja algo en su lugar.
            Rectangle {
                visible: !root.isApps
                Layout.preferredWidth: modeChip.implicitWidth + 20
                Layout.preferredHeight: 26
                radius: 9
                color: Qt.rgba(Colors.accent.r, Colors.accent.g, Colors.accent.b, 0.16)

                RowLayout {
                    id: modeChip
                    anchors.centerIn: parent
                    spacing: 6
                    Text {
                        text: root.modeInfo.prefix
                        color: Colors.accent
                        font.family: Appearance.font; font.pixelSize: 13; font.weight: Font.Bold
                    }
                    Text {
                        text: root.modeInfo.name
                        color: "#e8e8e8"
                        font.family: Appearance.fontUI; font.pixelSize: 12; font.weight: Font.Medium
                    }
                }
            }

            TextField {
                id: field
                Layout.fillWidth: true
                placeholderText: root.modeInfo.hint
                color: "#ffffff"
                placeholderTextColor: "#5e5e5e"
                selectionColor: Colors.accent
                selectedTextColor: "#000000"
                font.family: Appearance.fontUI
                font.pixelSize: 16
                background: null
                padding: 0

                onTextChanged: {
                    // Un prefijo al PRINCIPIO del campo no es texto: es un cambio
                    // de modo. Se comprueba aquí y no en Keys.onPressed para que
                    // también funcione pegando ("#factura" pega y entra en el
                    // portapapeles buscando "factura").
                    if (root.isApps && field.text.length > 0) {
                        const m = ShellState.launcherModeOf(field.text.charAt(0));
                        if (m !== "") {
                            const rest = field.text.slice(1);
                            ShellState.launcherMode = m;   // vacía el campo y refresca
                            field.text = rest;             // se conserva lo que iba detrás
                            return;
                        }
                    }
                    root.refresh();
                }

                Keys.onEscapePressed: ShellState.closePanel()
                Keys.onDownPressed: root.move(1)
                Keys.onUpPressed: root.move(-1)
                Keys.onReturnPressed: root.launchCurrent()
                Keys.onEnterPressed: root.launchCurrent()
                Keys.onTabPressed: root.move(1)
                Keys.onBacktabPressed: root.move(-1)
                Keys.onPressed: function (e) {
                    // Borrar sobre el campo YA vacío sale del modo. Es la salida
                    // que la mano encuentra sola: si el prefijo se borró al
                    // escribirlo, seguir borrando tiene que deshacerlo.
                    if (e.key === Qt.Key_Backspace && !root.isApps && field.text.length === 0) {
                        ShellState.launcherMode = "apps";
                        e.accepted = true;
                        return;
                    }
                    if (e.key === Qt.Key_Delete && root.mode === "clip") {
                        root.deleteCurrent();
                        e.accepted = true;
                        return;
                    }
                    if (e.modifiers & Qt.ControlModifier) {
                        if (e.key === Qt.Key_J || e.key === Qt.Key_N) { root.move(1); e.accepted = true; }
                        else if (e.key === Qt.Key_K || e.key === Qt.Key_P) { root.move(-1); e.accepted = true; }
                        // Ctrl+D fija o suelta lo que tengas seleccionado, sin ratón.
                        else if (e.key === Qt.Key_D && root.isApps) {
                            if (!root.calcSelected && list.currentIndex >= 0 && list.currentIndex < root.results.length)
                                ShellState.toggleFav(root.results[list.currentIndex]);
                            e.accepted = true;
                        }
                        // Ctrl+1..9 lanza el favorito N. Es el motivo de que la
                        // fila esté ORDENADA y de que se pueda reordenar: la
                        // posición pasa a ser un atajo que se aprende con los dedos.
                        else if (root.isApps && e.key >= Qt.Key_1 && e.key <= Qt.Key_9) {
                            const n = e.key - Qt.Key_1;
                            if (n < ShellState.favApps.length) ShellState.launchApp(ShellState.favApps[n]);
                            e.accepted = true;
                        }
                    } else if (e.key === Qt.Key_Home) { root.jump(0); e.accepted = true; }
                    else if (e.key === Qt.Key_End) { root.jump(root.results.length - 1); e.accepted = true; }
                    else if (e.key === Qt.Key_PageDown) { root.move(7); e.accepted = true; }
                    else if (e.key === Qt.Key_PageUp) { root.move(-7); e.accepted = true; }
                }
            }

            // Nombre del favorito bajo el ratón. Los iconos de la fila fijada no
            // llevan etiqueta debajo (no cabe en 58 px y triplicaría el alto),
            // así que el nombre sale aquí: un sitio que ya existía y que ya
            // estás mirando.
            Text {
                visible: root.favHover.length > 0
                Layout.maximumWidth: 170
                text: root.favHover
                color: "#9a9a9a"
                elide: Text.ElideRight
                font.family: Appearance.fontUI
                font.pixelSize: 12
            }

            // Las pistas de los modos, donde iba el contador. El contador decía
            // "hay 49 aplicaciones", que no es un dato que nadie necesite; esto
            // ocupa el mismo hueco y sí enseña algo. En cuanto escribes una letra
            // vuelve el contador, que ahí sí significa algo.
            RowLayout {
                visible: root.hintsVisible
                spacing: 12
                Repeater {
                    model: ShellState.launcherModes
                    RowLayout {
                        required property var modelData
                        spacing: 4
                        Text {
                            text: modelData.prefix
                            color: Colors.accent
                            font.family: Appearance.font; font.pixelSize: 12; font.weight: Font.Bold
                        }
                        Text {
                            text: modelData.name
                            color: "#5e5e5e"
                            font.family: Appearance.fontUI; font.pixelSize: 11
                        }
                    }
                }
            }

            Text {
                visible: !root.hintsVisible && root.favHover.length === 0
                text: String(root.results.length)
                color: "#5e5e5e"
                font.family: Appearance.fontUI
                font.pixelSize: 12
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.leftMargin: 18
            Layout.rightMargin: 18
            Layout.bottomMargin: 6
            height: 1
            color: "#1e1e1e"
        }

        // ─────────────── favoritos fijados ───────────────
        // Arrastrar reordena. Clic lanza. Clic derecho quita de favoritos.
        // Ctrl+1..9 lanza el favorito N sin levantar la mano del teclado.
        Item {
            id: favRow
            Layout.fillWidth: true
            Layout.leftMargin: 12
            Layout.rightMargin: 12
            Layout.bottomMargin: root.favVisible ? 12 : 0
            Layout.preferredHeight: root.favVisible ? 58 : 0
            visible: root.favVisible
            clip: true

            readonly property int cellW: 58

            ListView {
                id: favList
                anchors.fill: parent
                orientation: ListView.Horizontal
                model: root.favShown
                spacing: 0
                boundsBehavior: Flickable.StopAtBounds
                // Solo se puede desplazar si de verdad no caben; si no, cualquier
                // arrastre horizontal movería la lista en vez del icono.
                interactive: contentWidth > width

                delegate: Item {
                    id: favCell
                    required property var modelData
                    required property int index

                    width: favRow.cellW
                    height: favRow.height

                    readonly property bool dragged: root.favDrag === favCell.index && root.favMoving

                    Rectangle {
                        anchors.centerIn: parent
                        width: 50; height: 50
                        radius: 15
                        color: favMa.containsMouse && !root.favMoving ? Qt.rgba(1, 1, 1, 0.08) : "transparent"
                        Behavior on color { ColorAnimation { duration: Appearance.mQuick; easing.type: Easing.OutQuad } }
                    }

                    Image {
                        anchors.centerIn: parent
                        width: 34; height: 34
                        sourceSize.width: 34; sourceSize.height: 34
                        source: Quickshell.iconPath(favCell.modelData.icon, "application-x-executable")
                        fillMode: Image.PreserveAspectFit
                        // el hueco de donde sale, mientras lo llevas
                        opacity: favCell.dragged ? 0.18 : 1
                        Behavior on opacity { NumberAnimation { duration: Appearance.mQuick } }
                    }

                    MouseArea {
                        id: favMa
                        anchors.fill: parent
                        hoverEnabled: true
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        cursorShape: Qt.PointingHandCursor
                        // Si no, el Flickable de la lista roba el gesto en cuanto
                        // el puntero se mueve en horizontal, que es justo lo que
                        // hace falta para reordenar.
                        preventStealing: true

                        property real pressX: 0
                        property real pressY: 0

                        onEntered: root.favHover = favCell.modelData.name || ""
                        onExited: if (root.favHover === (favCell.modelData.name || "")) root.favHover = ""

                        onPressed: function (m) {
                            if (m.button !== Qt.LeftButton) return;
                            favMa.pressX = m.x; favMa.pressY = m.y;
                            root.favDrag = favCell.index;
                            root.favMoving = false;
                        }

                        onPositionChanged: function (m) {
                            if (root.favDrag < 0) return;
                            // Umbral: sin él, el temblor de la mano al hacer clic
                            // ya contaría como arrastre y no lanzaría la app.
                            if (!root.favMoving) {
                                if (Math.abs(m.x - favMa.pressX) < 6 && Math.abs(m.y - favMa.pressY) < 6) return;
                                root.favMoving = true;
                            }
                            const p = favMa.mapToItem(favRow, m.x, m.y);
                            root.favGhostX = p.x;
                            root.favGhostY = p.y;
                            // Ranura de inserción, no índice de elemento: redondear
                            // (y no truncar) hace que la marca salte por la MITAD
                            // de cada celda, que es donde el ojo espera el corte.
                            const cx = favList.contentX + p.x;
                            root.favSlot = Math.max(0, Math.min(root.favShown.length,
                                                                Math.round(cx / favRow.cellW)));
                        }

                        onReleased: function (m) {
                            if (m.button !== Qt.LeftButton) return;
                            const moved = root.favMoving;
                            const from = root.favDrag;
                            const to = root.favSlot;
                            // Limpiar ANTES de tocar Config: al confirmar cambia
                            // ShellState.favApps, y syncFavs() solo repinta si ya
                            // no hay un arrastre en curso.
                            root.favDrag = -1; root.favMoving = false; root.favSlot = -1;
                            if (moved) { if (to >= 0) ShellState.moveFav(from, to); }
                            else ShellState.launchApp(favCell.modelData);
                        }

                        onCanceled: { root.favDrag = -1; root.favMoving = false; root.favSlot = -1; }

                        onClicked: function (m) {
                            // El izquierdo lo resuelve onReleased, que es quien
                            // sabe distinguir un clic de un arrastre.
                            if (m.button === Qt.RightButton) ShellState.toggleFav(favCell.modelData);
                        }
                    }
                }
            }

            // Dónde va a caer lo que llevas en la mano. Más alta que el icono
            // fantasma (40 px) a propósito: el cursor está justo encima de la
            // marca, así que si midieran lo mismo el icono la taparía entera.
            Rectangle {
                visible: root.favMoving && root.favSlot >= 0
                width: 2
                height: 52
                radius: 1
                color: Colors.accent
                y: (favRow.height - height) / 2
                x: root.favSlot * favRow.cellW - favList.contentX - 1
            }

            // El icono que sigue al puntero.
            Image {
                visible: root.favMoving && root.favDrag >= 0 && root.favDrag < root.favShown.length
                width: 40; height: 40
                sourceSize.width: 40; sourceSize.height: 40
                x: root.favGhostX - width / 2
                y: root.favGhostY - height / 2
                opacity: 0.92
                fillMode: Image.PreserveAspectFit
                source: (root.favDrag >= 0 && root.favDrag < root.favShown.length)
                        ? Quickshell.iconPath(root.favShown[root.favDrag].icon, "application-x-executable")
                        : ""
            }
        }

        // ─────────────── resultado de la calculadora ───────────────
        Rectangle {
            id: calcRow
            Layout.fillWidth: true
            Layout.leftMargin: 12
            Layout.rightMargin: 12
            Layout.bottomMargin: 6
            Layout.preferredHeight: root.hasSpecial ? 56 : 0
            visible: root.hasSpecial
            radius: 12
            color: root.calcSelected ? Qt.rgba(Colors.accent.r, Colors.accent.g, Colors.accent.b, 0.20)
                 : calcMa.containsMouse ? Qt.rgba(1, 1, 1, 0.06) : "transparent"
            Behavior on color { ColorAnimation { duration: Appearance.mQuick; easing.type: Easing.OutQuad } }

            RowLayout {
                anchors { fill: parent; leftMargin: 14; rightMargin: 14 }
                spacing: 13

                Text {
                    text: root.hasTimer ? Icons.timer : "󰪚"
                    color: Colors.accent
                    font.family: Appearance.font; font.pixelSize: 22
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    Text {
                        Layout.fillWidth: true
                        text: root.hasTimer ? ShellState.timerClock(root.timerSec)
                                            : ShellState.calcFormat(root.calc)
                        color: "#ffffff"; elide: Text.ElideRight
                        font.family: Appearance.fontUI; font.pixelSize: 19; font.weight: Font.DemiBold
                        font.features: ({ "tnum": 1 })
                    }
                    Text {
                        Layout.fillWidth: true
                        text: root.hasTimer ? "Enter arranca el temporizador"
                                            : "Enter copia al portapapeles"
                        color: "#7d7d7d"; elide: Text.ElideRight
                        font.family: Appearance.fontUI; font.pixelSize: 10
                    }
                }
                Text {
                    visible: root.calcSelected
                    text: root.hasTimer ? Icons.play : "󰆏"
                    color: Colors.accent
                    font.family: Appearance.font; font.pixelSize: 14
                }
            }

            MouseArea {
                id: calcMa
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    if (root.hasTimer) ShellState.timerStart(root.timerSec);
                    else ShellState.copyText(ShellState.calcFormat(root.calc));
                    ShellState.closePanel();
                }
            }
        }

        // ─────────────── resultados ───────────────
        // Un delegado por modo, elegido por la propia lista. La alternativa era
        // un delegado único con cuatro ramas dentro, que es el mismo código pero
        // sin poder leer ninguno de los cuatro de un vistazo.
        ListView {
            id: list
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.leftMargin: 12
            Layout.rightMargin: 12
            Layout.bottomMargin: 12
            clip: true
            model: root.results
            currentIndex: 0
            highlightMoveDuration: Appearance.mQuick
            boundsBehavior: Flickable.StopAtBounds

            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded; width: 4 }

            delegate: root.listKind === "clip" ? clipDelegate
                    : root.listKind === "cmd" ? cmdDelegate
                    : root.listKind === "win" ? winDelegate
                    : appDelegate

            // sin resultados
            Text {
                anchors.centerIn: parent
                visible: root.results.length === 0
                text: root.waiting ? "Leyendo el portapapeles…"
                    : field.text.length > 0 ? "Sin resultados"
                    : root.mode === "clip" ? "El portapapeles está vacío"
                    : root.mode === "win" ? "No hay ventanas abiertas"
                    : "Sin resultados"
                color: "#5e5e5e"
                font.family: Appearance.fontUI
                font.pixelSize: 13
            }
        }
    }

    // ═══════════════════════ delegados ═══════════════════════
    // El fondo, el resalte y el criterio de "manda el ratón" son idénticos en
    // los cuatro, así que viven en un componente base y cada modo solo pone lo
    // que va dentro. RowBase publica `sel` para que el contenido pueda pintar la
    // flecha de Enter sin volver a mirar el índice.
    // OJO: el contenido de cada modo se declara DETRÁS del MouseArea, sin
    // `default property alias` a un Item contenedor. Un alias de propiedad por
    // defecto en el propio tipo también se traga los hijos declarados en la
    // definición del tipo, o sea el MouseArea, y el resultado es un contenedor
    // que se contiene a sí mismo. Además el orden importa para el ratón: al ir
    // detrás, las zonas de la estrella y la papelera quedan POR ENCIMA de la
    // zona de la fila y se llevan su clic, que es justo lo que se busca.
    component RowBase: Rectangle {
        id: base
        required property int index

        readonly property bool sel: base.index === list.currentIndex
        readonly property bool hovered: baseMa.containsMouse
        signal activated(int button)

        width: list.width
        height: ShellState.launcherRowH
        radius: 12
        color: base.sel ? Qt.rgba(Colors.accent.r, Colors.accent.g, Colors.accent.b, 0.20)
             : (baseMa.containsMouse && root.mouseNav) ? Qt.rgba(1, 1, 1, 0.06)
             : "transparent"
        Behavior on color { ColorAnimation { duration: Appearance.mQuick; easing.type: Easing.OutQuad } }

        MouseArea {
            id: baseMa
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            cursorShape: Qt.PointingHandCursor
            // Mismo criterio en entrada y en movimiento: solo manda el ratón si
            // el puntero ha cambiado de sitio de verdad.
            onPositionChanged: function (m) {
                const p = baseMa.mapToItem(null, m.x, m.y);
                if (root.pointerMoved(p.x, p.y)) { root.mouseNav = true; root.calcSelected = false; list.currentIndex = base.index; }
            }
            onEntered: {
                const p = baseMa.mapToItem(null, baseMa.mouseX, baseMa.mouseY);
                if (root.pointerMoved(p.x, p.y)) { root.mouseNav = true; root.calcSelected = false; list.currentIndex = base.index; }
            }
            onClicked: function (m) { base.activated(m.button); }
        }
    }

    // La flecha de Enter, igual en los cuatro modos.
    component EnterMark: Text {
        text: "󰌑"
        color: Colors.accent
        font.family: Appearance.font
        font.pixelSize: 13
    }

    // ─── aplicaciones ───
    Component {
        id: appDelegate

        RowBase {
            id: appRow
            required property var modelData

            onActivated: function (button) {
                if (button === Qt.RightButton) ShellState.toggleFav(appRow.modelData);
                else ShellState.launchApp(appRow.modelData);
            }

            RowLayout {
                anchors { fill: parent; leftMargin: 12; rightMargin: 14 }
                spacing: 13

                Image {
                    Layout.preferredWidth: 30
                    Layout.preferredHeight: 30
                    source: Quickshell.iconPath(appRow.modelData.icon, "application-x-executable")
                    sourceSize.width: 30
                    sourceSize.height: 30
                    fillMode: Image.PreserveAspectFit
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    Text {
                        Layout.fillWidth: true
                        text: appRow.modelData.name || ""
                        color: "#ffffff"
                        elide: Text.ElideRight
                        font.family: Appearance.fontUI
                        font.pixelSize: 13
                        font.weight: Font.Medium
                    }
                    Text {
                        Layout.fillWidth: true
                        visible: text.length > 0
                        text: appRow.modelData.comment || appRow.modelData.genericName || ""
                        color: "#7d7d7d"
                        elide: Text.ElideRight
                        font.family: Appearance.fontUI
                        font.pixelSize: 11
                    }
                }

                // Estrella: llena si ya es favorito, hueca solo al pasar por
                // encima. Así una fila corriente no lleva ruido, pero la manera
                // de fijarla está siempre a un clic de distancia.
                Text {
                    visible: ShellState.isFav(appRow.modelData) || starMa.containsMouse || appRow.hovered
                    text: ShellState.isFav(appRow.modelData) ? Icons.star : Icons.starOff
                    color: ShellState.isFav(appRow.modelData) ? Colors.accent2
                         : starMa.containsMouse ? "#c9c9c9" : "#4a4a4a"
                    font.family: Appearance.font
                    font.pixelSize: 14
                    Behavior on color { ColorAnimation { duration: Appearance.mQuick; easing.type: Easing.OutQuad } }

                    MouseArea {
                        id: starMa
                        anchors.fill: parent
                        anchors.margins: -7      // zona de clic cómoda sin agrandar el icono
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: ShellState.toggleFav(appRow.modelData)
                    }
                }

                EnterMark { visible: appRow.sel }
            }
        }
    }

    // ─── # portapapeles ───
    Component {
        id: clipDelegate

        RowBase {
            id: clipRow
            required property var modelData

            onActivated: function (button) {
                // El derecho borra, igual que en la fila de aplicaciones el
                // derecho es "la acción secundaria de esta fila".
                if (button === Qt.RightButton) { list.currentIndex = clipRow.index; root.deleteCurrent(); }
                else ShellState.clipCopy(clipRow.modelData);
            }

            RowLayout {
                anchors { fill: parent; leftMargin: 10; rightMargin: 14 }
                spacing: 13

                // La miniatura de verdad para las imágenes; un icono de documento
                // para el texto. Van los dos en un hueco del MISMO tamaño para
                // que la columna de texto empiece siempre en la misma vertical:
                // si cada fila empezara donde le tocara, la lista sería un
                // zigzag ilegible.
                Rectangle {
                    Layout.preferredWidth: 46
                    Layout.preferredHeight: 40
                    radius: 8
                    color: clipRow.modelData.image ? "#111111" : "transparent"
                    clip: true

                    Image {
                        anchors.fill: parent
                        visible: clipRow.modelData.image && clipRow.modelData.thumb.length > 0
                        source: clipRow.modelData.thumb.length > 0 ? "file://" + clipRow.modelData.thumb : ""
                        // Recortada y no encajada: llenar el hueco enseña el
                        // CONTENIDO de la captura; encajarla la deja de 12 px de
                        // alto rodeada de negro y no se reconoce nada.
                        fillMode: Image.PreserveAspectCrop
                        sourceSize.width: 92
                        sourceSize.height: 80
                        asynchronous: true
                        cache: true
                    }

                    Text {
                        anchors.centerIn: parent
                        visible: !clipRow.modelData.image
                        text: Icons.textBox
                        color: "#6c6c6c"
                        font.family: Appearance.font
                        font.pixelSize: 20
                    }
                }

                Text {
                    Layout.fillWidth: true
                    text: clipRow.modelData.label
                    color: clipRow.modelData.image ? "#b9b9b9" : "#ffffff"
                    // Dos líneas: lo que se copia casi nunca cabe en una, y con
                    // una sola línea media lista parecía la misma entrada
                    // repetida (todo empieza por el mismo párrafo).
                    maximumLineCount: 2
                    wrapMode: Text.Wrap
                    elide: Text.ElideRight
                    font.family: Appearance.fontUI
                    font.pixelSize: 12
                    font.weight: clipRow.modelData.image ? Font.Normal : Font.Medium
                }

                // La papelera solo aparece en la fila señalada: es destructiva y
                // no tiene por qué estar ofreciéndose en las quince a la vez.
                Text {
                    visible: clipRow.sel
                    text: Icons.trash
                    color: trashMa.containsMouse ? "#ff6b6b" : "#5e5e5e"
                    font.family: Appearance.font
                    font.pixelSize: 15
                    Behavior on color { ColorAnimation { duration: Appearance.mQuick; easing.type: Easing.OutQuad } }

                    MouseArea {
                        id: trashMa
                        anchors.fill: parent
                        anchors.margins: -7
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: { list.currentIndex = clipRow.index; root.deleteCurrent(); }
                    }
                }

                EnterMark { visible: clipRow.sel }
            }
        }
    }

    // ─── > acciones ───
    Component {
        id: cmdDelegate

        RowBase {
            id: cmdRow
            required property var modelData

            onActivated: ShellState.runAction(cmdRow.modelData)

            RowLayout {
                anchors { fill: parent; leftMargin: 16; rightMargin: 14 }
                spacing: 15

                Text {
                    Layout.preferredWidth: 24
                    text: cmdRow.modelData.icon
                    color: cmdRow.sel ? Colors.accent : "#b9b9b9"
                    horizontalAlignment: Text.AlignHCenter
                    font.family: Appearance.font
                    font.pixelSize: 18
                    Behavior on color { ColorAnimation { duration: Appearance.mQuick; easing.type: Easing.OutQuad } }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    Text {
                        Layout.fillWidth: true
                        text: cmdRow.modelData.name
                        color: "#ffffff"
                        elide: Text.ElideRight
                        font.family: Appearance.fontUI
                        font.pixelSize: 13
                        font.weight: Font.Medium
                    }
                    Text {
                        Layout.fillWidth: true
                        text: cmdRow.modelData.desc
                        color: "#7d7d7d"
                        elide: Text.ElideRight
                        font.family: Appearance.fontUI
                        font.pixelSize: 11
                    }
                }

                EnterMark { visible: cmdRow.sel }
            }
        }
    }

    // ─── @ ventanas ───
    Component {
        id: winDelegate

        RowBase {
            id: winRow
            required property var modelData

            onActivated: ShellState.focusWindow(winRow.modelData)

            RowLayout {
                anchors { fill: parent; leftMargin: 12; rightMargin: 14 }
                spacing: 13

                Image {
                    Layout.preferredWidth: 28
                    Layout.preferredHeight: 28
                    source: Quickshell.iconPath(winRow.modelData.icon, "application-x-executable")
                    sourceSize.width: 28
                    sourceSize.height: 28
                    fillMode: Image.PreserveAspectFit
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    Text {
                        Layout.fillWidth: true
                        // El título se lee del toplevel VIVO y no de la copia del
                        // modelo: cambiar de pestaña en el navegador tiene que
                        // cambiar la fila sin esperar al siguiente refresco.
                        text: (winRow.modelData.tl && winRow.modelData.tl.title)
                              ? winRow.modelData.tl.title : winRow.modelData.title
                        color: "#ffffff"
                        elide: Text.ElideRight
                        font.family: Appearance.fontUI
                        font.pixelSize: 13
                        font.weight: Font.Medium
                    }
                    Text {
                        Layout.fillWidth: true
                        text: winRow.modelData.cls
                        color: "#7d7d7d"
                        elide: Text.ElideRight
                        font.family: Appearance.fontUI
                        font.pixelSize: 11
                    }
                }

                // A qué escritorio te vas. Es la única información que la lista
                // de ventanas tiene y el Alt+Tab del compositor no: saltar aquí
                // puede cambiarte de escritorio, y conviene saberlo antes.
                Rectangle {
                    Layout.preferredWidth: 22
                    Layout.preferredHeight: 20
                    radius: 7
                    color: winRow.modelData.ws === ShellState.activeWs
                           ? Qt.rgba(Colors.accent.r, Colors.accent.g, Colors.accent.b, 0.22)
                           : Qt.rgba(1, 1, 1, 0.07)

                    Text {
                        anchors.centerIn: parent
                        text: String(winRow.modelData.ws)
                        color: winRow.modelData.ws === ShellState.activeWs ? Colors.accent : "#8a8a8a"
                        font.family: Appearance.fontUI
                        font.pixelSize: 11
                        font.weight: Font.DemiBold
                    }
                }

                EnterMark { visible: winRow.sel }
            }
        }
    }
}
