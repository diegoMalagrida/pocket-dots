// OverviewPanel.qml — el mapa de escritorios, desplegado DESDE el notch.
//
// Sustituye al Overview.qml antiguo, que tomaba la pantalla entera y enseñaba
// las ventanas en una parrilla suelta. El problema de aquello no era estético:
// una parrilla no dice EN QUÉ ESCRITORIO está cada cosa, que es justo lo único
// que quieres saber cuando pulsas Super+Tab. Aquí cada celda es un escritorio a
// escala, con sus ventanas colocadas donde están de verdad, así que el mapa se
// lee igual que el escritorio.
//
// Y lo importante: LAS VENTANAS SE ARRASTRAN. Coges una miniatura con el ratón y
// la sueltas en otra celda; eso es un `movetoworkspacesilent`. Si es flotante y
// la sueltas dentro de su propia celda, se recoloca ahí dentro
// (`movewindowpixel`). Reordenar el escritorio deja de ser una secuencia de
// atajos y pasa a ser un gesto.
//
// Dos cosas que no se ven leyendo el código:
//
// 1. EL ESCRITORIO DE CADA VENTANA SE LEE DE `toplevel.workspace`, PERO SU
//    POSICIÓN DE `lastIpcObject`. Medido: Quickshell mantiene `workspace` al día
//    solo (escucha los sucesos de Hyprland), pero `lastIpcObject` — que es de
//    donde salen `at` y `size` — se queda CONGELADO hasta que alguien llama a
//    refreshToplevels(). Por eso hay un temporizador que lo pide mientras el
//    overview está abierto, y solo mientras lo está.
//
// 2. EL MODELO PASA POR ScriptModel A PROPÓSITO. La lista se recalcula cada vez
//    que una ventana cambia de escritorio, y un Repeater sobre un array nuevo
//    DESTRUYE Y RECREA todos sus delegados: cada arrastre apagaría y volvería a
//    encender las diez capturas de pantalla, con su parpadeo. ScriptModel
//    compara por identidad y solo toca lo que ha cambiado de verdad.
import Quickshell
import Quickshell.Hyprland
import Quickshell.Widgets
import QtQuick

Item {
    id: root

    readonly property bool active: ShellState.panel === "overview"

    // ─── geometría (la calcula ShellState, que también dimensiona el notch) ───
    readonly property int cols: ShellState.ovCols
    readonly property int rows: ShellState.ovRows
    readonly property int cells: ShellState.ovCount
    readonly property real cellW: ShellState.ovCellW
    readonly property real cellH: ShellState.ovCellH
    readonly property real gap: ShellState.ovGap
    readonly property real sc: ShellState.ovScale
    readonly property var mon: ShellState.ovMon
    readonly property real gridW: ShellState.ovGridW
    readonly property real gridH: ShellState.ovGridH

    readonly property real radOut: 18
    readonly property real radIn: 10

    // ─── estado de interacción ───
    property string dragAddr: ""     // dirección de la ventana que vuela ahora mismo
    property int dropWs: -1          // celda bajo el cursor mientras arrastras
    property int hoverWs: -1         // celda bajo el cursor sin arrastrar
    // La ventana señalada, para la franja del pie. Se guarda el TOPLEVEL y no su
    // lastIpcObject: ese mapa se reconstruye en cada refresco, así que comparar
    // dos lecturas con === daría siempre falso y el resaltado no se apagaría
    // nunca. El toplevel es el mismo objeto mientras la ventana exista, y al
    // cerrarse QML pone esta propiedad a null él solo (por eso es QtObject y no
    // var: un `var` se quedaría apuntando a un objeto muerto).
    property QtObject hoverTl: null
    property int selWs: 1            // selección de teclado

    // Viene de ShellState y no se recalcula aquí: la cara "ws" del notch lee el
    // mismo dato, y dos derivaciones de lo mismo es justo cómo empiezan a
    // desincronizarse las cosas.
    readonly property int activeWs: ShellState.activeWs

    // Hyprland 0.55+ interpreta `dispatch` como una expresion Lua. Quickshell
    // envia directamente lo que recibe Hyprland.dispatch(), asi que aqui hay
    // que construir dispatchers `hl.dsp.*`; la sintaxis hyprlang antigua
    // ("movetoworkspacesilent 2,address:...") se acepta en el QML pero el
    // compositor la rechaza al soltar la miniatura.
    function winSelector(addr) { return '"address:' + addr + '"'; }

    // Se filtran los escritorios especiales (id negativo: el scratchpad de la IA,
    // por ejemplo) y los que caen fuera de la rejilla.
    readonly property var wins: [...Hyprland.toplevels.values].filter(t =>
        t.workspace && t.workspace.id >= 1 && t.workspace.id <= root.cells && t.wayland)

    ScriptModel { id: winModel; values: root.wins }

    function wsX(ws) { return ((ws - 1) % root.cols) * (root.cellW + root.gap); }
    function wsY(ws) { return Math.floor((ws - 1) / root.cols) * (root.cellH + root.gap); }
    function wsAt(px, py) {
        const c = Math.floor(px / (root.cellW + root.gap));
        const r = Math.floor(py / (root.cellH + root.gap));
        if (c < 0 || c >= root.cols || r < 0 || r >= root.rows) return -1;
        // El hueco entre celdas no es de nadie: soltar ahí no mueve nada.
        if (px - c * (root.cellW + root.gap) > root.cellW) return -1;
        if (py - r * (root.cellH + root.gap) > root.cellH) return -1;
        return r * root.cols + c + 1;
    }

    // ── irse de aquí: primero cerrar, DESPUÉS pedir el foco ──
    // Al cerrar el panel se suelta el HyprlandFocusGrab, y Hyprland responde
    // devolviendo el foco a la ventana que lo tenía antes de abrirse el
    // overview. Si el `focuswindow` va en el mismo instante, no está garantizado
    // quién llega el último, y si llega la devolución te quedas en la ventana de
    // la que venías: justo lo que acabas de pedir que NO pase. Los 60 ms dejan
    // que la devolución ocurra primero y que nuestra petición tenga la última
    // palabra. Es el mismo remedio que usa Tide-island (allí, 50 ms).
    //
    // HONESTIDAD sobre cómo se llegó aquí: esto se escribió creyendo haber visto
    // la carrera en vivo, y la prueba estaba viciada — la sesión estaba en el
    // estado "lockscreen crashed" de Hyprland, donde NINGUNA ventana puede coger
    // el foco y `focuswindow` contesta `ok` sin hacer nada. O sea que la carrera
    // es real por construcción pero NO está observada. Se deja porque cuesta
    // 60 ms y el fallo que evita es de los que solo aparecen de vez en cuando.
    property int pendingWs: -1
    property string pendingAddr: ""
    Timer {
        id: deferred
        interval: 60
        onTriggered: {
            if (root.pendingAddr !== "") {
                Hyprland.dispatch("hl.dsp.focus({ window = "
                    + root.winSelector(root.pendingAddr) + " })");
                root.pendingAddr = "";
            } else if (root.pendingWs >= 1) {
                Hyprland.dispatch("hl.dsp.focus({ workspace = " + root.pendingWs + " })");
            }
            root.pendingWs = -1;
        }
    }

    function goTo(ws) {
        if (ws < 1) return;
        root.pendingWs = ws;
        root.pendingAddr = "";
        ShellState.closePanel();
        deferred.restart();
    }

    function focusWin(addr) {
        root.pendingAddr = addr;
        root.pendingWs = -1;
        ShellState.closePanel();
        deferred.restart();
    }

    function countIn(ws) {
        let n = 0;
        for (const t of root.wins) if (t.workspace.id === ws) n++;
        return n;
    }

    // ── refresco de datos ──
    // Solo con el overview abierto. Un refreshToplevels() es una consulta al
    // socket de Hyprland: pedirla siempre sería pagarla siempre, y el 99 % del
    // tiempo esto no se está mirando.
    Timer { id: poll; interval: 90; onTriggered: Hyprland.refreshToplevels() }
    Connections {
        target: Hyprland
        enabled: root.active
        function onRawEvent(ev) {
            const n = String(ev.name);
            if (n.indexOf("window") >= 0 || n.indexOf("workspace") >= 0
                || n === "changefloatingmode" || n === "fullscreen" || n === "resizewindow")
                poll.restart();
        }
    }

    function clearHover() { root.dragAddr = ""; root.dropWs = -1; root.hoverWs = -1; root.hoverTl = null; }

    onActiveChanged: {
        clearHover();
        if (!root.active) return;
        Hyprland.refreshToplevels();
        root.selWs = root.activeWs;
        keys.forceActiveFocus();
        refocus.restart();   // seguro: la capa tarda un instante en aceptar foco
    }
    Timer {
        id: refocus
        interval: 120
        onTriggered: if (root.active) keys.forceActiveFocus()
    }

    // absorbe los clics del hueco para que no cierren el panel
    MouseArea { anchors.fill: parent }

    Item {
        id: keys
        anchors.fill: parent
        focus: true
        Keys.onEscapePressed: ShellState.closePanel()
        Keys.onLeftPressed: if ((root.selWs - 1) % root.cols !== 0) root.selWs--
        Keys.onRightPressed: if (root.selWs % root.cols !== 0) root.selWs++
        Keys.onUpPressed: if (root.selWs > root.cols) root.selWs -= root.cols
        Keys.onDownPressed: if (root.selWs <= root.cells - root.cols) root.selWs += root.cols
        Keys.onReturnPressed: root.goTo(root.selWs)
        Keys.onEnterPressed: root.goTo(root.selWs)
        // 1..9 y 0 saltan directamente, igual que Super+1..0 fuera del overview:
        // el atajo que ya tienes en los dedos sigue valiendo aquí dentro.
        Keys.onPressed: function (e) {
            if (e.key >= Qt.Key_1 && e.key <= Qt.Key_9) { root.goTo(e.key - Qt.Key_0); e.accepted = true; }
            else if (e.key === Qt.Key_0) { root.goTo(root.cells); e.accepted = true; }
        }
    }

    Item {
        id: stage
        x: (root.width - root.gridW) / 2
        y: ShellState.ovPadTop
        width: root.gridW
        height: root.gridH

        // ══════════════ las celdas (solo pintura) ══════════════
        Repeater {
            model: root.cells

            ClippingRectangle {
                id: cell
                required property int index
                readonly property int ws: index + 1
                readonly property int col: index % root.cols
                readonly property int row: Math.floor(index / root.cols)
                readonly property bool atL: col === 0
                readonly property bool atR: col === root.cols - 1
                readonly property bool atT: row === 0
                readonly property bool atB: row === root.rows - 1
                readonly property bool isDrop: root.dropWs === ws && root.dragAddr !== ""
                readonly property bool isHover: root.hoverWs === ws && root.dragAddr === ""
                readonly property bool empty: root.countIn(ws) === 0

                x: root.wsX(ws); y: root.wsY(ws)
                width: root.cellW; height: root.cellH
                color: "#0a0a0a"
                antialiasing: true
                contentUnderBorder: true
                topLeftRadius: (atL && atT) ? root.radOut : root.radIn
                topRightRadius: (atR && atT) ? root.radOut : root.radIn
                bottomLeftRadius: (atL && atB) ? root.radOut : root.radIn
                bottomRightRadius: (atR && atB) ? root.radOut : root.radIn
                border.width: 1
                border.color: cell.isDrop ? Colors.accent : Qt.rgba(1, 1, 1, 0.07)

                // El fondo de pantalla, a tamaño de celda. Es lo que convierte
                // diez rectángulos grises en diez PANTALLAS: sin él no hay forma
                // de leer una celda vacía como un escritorio.
                // Las diez comparten source y sourceSize, así que Qt descodifica
                // el JPEG UNA vez y reparte el mismo pixmap.
                Image {
                    anchors.fill: parent
                    source: Colors.wallpaper
                    fillMode: Image.PreserveAspectCrop
                    sourceSize.width: Math.round(root.cellW)
                    sourceSize.height: Math.round(root.cellH)
                    asynchronous: true
                    cache: true
                    visible: status === Image.Ready
                }

                // Velo. El fondo tiene que quedar por DEBAJO de las miniaturas en
                // jerarquía visual: si compite, la rejilla se vuelve ruido.
                Rectangle {
                    anchors.fill: parent
                    color: cell.isDrop ? Qt.rgba(Colors.accent.r, Colors.accent.g, Colors.accent.b, 0.20)
                        : cell.isHover ? Qt.rgba(0, 0, 0, 0.28) : Qt.rgba(0, 0, 0, 0.44)
                    Behavior on color { ColorAnimation { duration: Appearance.mQuick } }
                }

                // Número del escritorio. Grande y tenue si está vacío (es lo único
                // que hay que mirar ahí); pequeño en la esquina si tiene ventanas,
                // para no pintar por encima de ellas.
                Text {
                    anchors.centerIn: parent
                    visible: cell.empty
                    text: String(cell.ws)
                    color: Qt.rgba(1, 1, 1, 0.22)
                    font.family: Appearance.fontUI
                    font.pixelSize: Math.round(root.cellH * 0.34)
                    font.weight: Font.DemiBold
                }
            }
        }

        // ══════════════ clic en el hueco: ir a ese escritorio ══════════════
        // Va DEBAJO de las miniaturas: si pinchas una ventana manda la ventana,
        // y si pinchas el fondo de la celda manda esto.
        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onPositionChanged: function (m) { root.hoverWs = root.wsAt(m.x, m.y); root.hoverTl = null; }
            // Aquí NO se toca hoverTl. Al entrar el puntero en una miniatura,
            // esta zona pierde el hover y dispara su onExited: si limpiara
            // hoverTl podría hacerlo DESPUÉS de que la miniatura lo haya puesto
            // (el orden entre salir de uno y entrar en otro no está garantizado)
            // y la franja del pie se quedaría muda justo al señalar una ventana.
            onExited: root.hoverWs = -1
            onClicked: function (m) {
                const ws = root.wsAt(m.x, m.y);
                if (ws >= 1) root.goTo(ws);
            }
        }

        // ══════════════ las ventanas ══════════════
        // Una sola copia por ventana: es a la vez lo que ves y lo que agarras.
        // Puede volar libre por toda la rejilla porque nadie la recorta (ver la
        // nota 2 de OverviewWindow.qml).
        Repeater {
            model: winModel

            OverviewWindow {
                id: tile
                required property var modelData
                // OJO: `toplevel.address` viene SIN el "0x" y los despachadores
                // de Hyprland lo exigen ("address:0x5637..."). Sin el prefijo
                // todos los dispatch de aquí contestan "moveWindow: no window" y
                // el arrastre no hace nada, en silencio.
                readonly property string addr: {
                    const a = String(modelData.address || "");
                    return a.startsWith("0x") ? a : "0x" + a;
                }
                readonly property int ws: modelData.workspace ? modelData.workspace.id : -1
                readonly property bool floating: !!(client && client.floating)

                client: modelData.lastIpcObject
                toplevel: modelData.wayland
                mon: root.mon
                sc: root.sc
                cellW: root.cellW; cellH: root.cellH
                offX: root.wsX(ws); offY: root.wsY(ws)
                radOut: root.radOut; radIn: root.radIn
                atL: (ws - 1) % root.cols === 0
                atR: (ws - 1) % root.cols === root.cols - 1
                atT: ws <= root.cols
                atB: ws > root.cells - root.cols

                live: root.active
                dragging: root.dragAddr === addr
                hovered: pointer.containsMouse
                pressed: pointer.pressed
                // Una ventana a pantalla completa tapa a las demás, y una
                // flotante va por encima de las embaldosadas: el mismo orden que
                // tienen de verdad en el escritorio. La que vuela, por encima de
                // todo, incluso del marco del escritorio activo.
                z: dragging ? 300 : (client && client.fullscreen ? 30 : 20) + (client && client.floating ? 5 : 0)

                MouseArea {
                    id: pointer
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton

                    // EL ARRASTRE VA A MANO, y no con `drag.target` de Qt.
                    //
                    // Con `drag.target` la miniatura no se movía: Qt la mueve
                    // desde C++ (QQuickItem::setX) y eso NO rompe el binding
                    // `x: initX`, así que el binding la devolvía a su celda a
                    // cada evento del ratón y los dos se peleaban. Medido en el
                    // log del shell: x alternaba entre 1100 -su sitio- y 2606,
                    // que está fuera de una rejilla de 1372 px, o sea fuera de
                    // la pantalla. En cámara se veía como que la ventana no se
                    // arrastra: solo se encendía la celda de destino y al soltar
                    // aparecía allí.
                    //
                    // Moverla desde QML es además lo único que rompe el binding
                    // de verdad, así que el arreglo y el gesto son la misma cosa.
                    property real grabX: 0
                    property real grabY: 0
                    property bool moved: false

                    onEntered: { root.hoverTl = tile.modelData; root.hoverWs = tile.ws; }
                    onExited: if (root.hoverTl === tile.modelData) root.hoverTl = null

                    onPressed: function (m) {
                        if (m.button !== Qt.LeftButton) return;
                        pointer.moved = false;
                        pointer.grabX = m.x;
                        pointer.grabY = m.y;
                    }

                    onPositionChanged: function (m) {
                        if (!(pointer.pressedButtons & Qt.LeftButton)) return;

                        // El umbral que separa un clic de un arrastre. Diez
                        // píxeles, los mismos que usaba Qt: por debajo, un clic
                        // con pulso tembloroso levantaría la miniatura y se
                        // leería como un arrastre fallido.
                        if (!pointer.moved) {
                            if (Math.hypot(m.x - pointer.grabX, m.y - pointer.grabY) < 10)
                                return;
                            pointer.moved = true;
                            tile.unbind();
                            root.dragAddr = tile.addr;
                            root.dropWs = tile.ws;
                        }

                        // El cursor en coordenadas de la rejilla se calcula ANTES
                        // de mover la miniatura: después, `m.x` ya no es lo que
                        // era porque el sistema de coordenadas se ha movido con
                        // ella.
                        const p = tile.mapToItem(stage, m.x, m.y);
                        tile.x += m.x - pointer.grabX;
                        tile.y += m.y - pointer.grabY;

                        // Una embaldosada se suelta donde apunta el CURSOR (es
                        // enorme y solaparía tres celdas a la vez); una flotante,
                        // por su CENTRO, que es como se lee un objeto que dejas.
                        root.dropWs = tile.floating
                            ? root.wsAt(tile.x + tile.width / 2, tile.y + tile.height / 2)
                            : root.wsAt(p.x, p.y);
                    }

                    onReleased: function (m) {
                        if (m.button === Qt.RightButton) {
                            // Solo si sueltas ENCIMA. Cerrar es lo único
                            // irreversible que hay aquí, así que sacar el puntero
                            // antes de soltar tiene que ser una forma de echarse
                            // atrás.
                            if (pointer.containsMouse)
                                Hyprland.dispatch("hl.dsp.window.close({ window = "
                                    + root.winSelector(tile.addr) + " })");
                            return;
                        }
                        if (m.button === Qt.MiddleButton) {
                            if (pointer.containsMouse) {
                                Hyprland.dispatch("hl.dsp.window.float({ action = \"toggle\", window = "
                                    + root.winSelector(tile.addr) + " })");
                                poll.restart();
                            }
                            return;
                        }
                        if (m.button !== Qt.LeftButton) return;

                        const target = pointer.moved ? root.dropWs : -1;
                        root.dragAddr = "";
                        root.dropWs = -1;
                        root.applyDrop(tile, target, pointer.moved);
                    }

                    onCanceled: {
                        root.dragAddr = "";
                        root.dropWs = -1;
                        pointer.moved = false;
                        tile.rebind();
                    }
                }
            }
        }

        // ══════════════ marco del escritorio activo ══════════════
        // Viaja con muelle en vez de aparecer ya puesto en la celda nueva: si
        // cambias de escritorio con el overview abierto, el marco RECORRE el
        // camino, así que ves de dónde vienes.
        Rectangle {
            property real tx: root.wsX(root.activeWs)
            property real ty: root.wsY(root.activeWs)
            x: tx; y: ty
            width: root.cellW; height: root.cellH
            color: "transparent"
            radius: root.radIn
            border.width: 2
            border.color: Colors.accent
            z: 200
            Behavior on x { SpringAnimation { spring: Appearance.sprTight; damping: Appearance.dmpTight; epsilon: Appearance.eppPx } }
            Behavior on y { SpringAnimation { spring: Appearance.sprTight; damping: Appearance.dmpTight; epsilon: Appearance.eppPx } }
        }

        // Marco de la selección de teclado. Solo sale cuando la selección se
        // separa del escritorio activo: si coincidieran serían dos marcos
        // pintados uno encima del otro diciendo lo mismo.
        Rectangle {
            visible: root.selWs !== root.activeWs
            x: root.wsX(root.selWs); y: root.wsY(root.selWs)
            width: root.cellW; height: root.cellH
            color: "transparent"
            radius: root.radIn
            border.width: 2
            border.color: Qt.rgba(1, 1, 1, 0.55)
            z: 199
            Behavior on x { NumberAnimation { duration: Appearance.mQuick; easing.type: Easing.OutCubic } }
            Behavior on y { NumberAnimation { duration: Appearance.mQuick; easing.type: Easing.OutCubic } }
        }
    }

    // ══════════════ la franja del pie ══════════════
    // El mismo patrón que la app de Ajustes: el detalle NO se pinta sobre cada
    // cosa (a esta escala un título no cabe en la miniatura y encima taparía la
    // ventana), va a una franja fija que enseña lo que tienes debajo del ratón.
    // Cuando no señalas nada, recuerda lo que se puede hacer aquí.
    Text {
        anchors {
            left: parent.left; right: parent.right
            bottom: parent.bottom; bottomMargin: 10
            leftMargin: 20; rightMargin: 20
        }
        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideRight
        text: {
            const t = root.hoverTl;
            if (!t) return I18n.tr("Arrastra una ventana a otro escritorio · clic derecho la cierra · clic con la rueda la vuelve flotante");
            if (t.title && t.title.length > 0) return t.title;
            const c = t.lastIpcObject;
            return c ? (c["class"] || "") : "";
        }
        color: root.hoverTl ? "#e6e6e6" : "#6e6e6e"
        font.family: Appearance.fontUI
        font.pixelSize: 11
        font.weight: root.hoverTl ? Font.Medium : Font.Normal
        Behavior on color { ColorAnimation { duration: Appearance.mQuick } }
    }

    // ── qué pasa al soltar ──
    // Vive aquí, fuera del manejador del ratón, por dos razones: el manejador ya
    // era demasiado largo para leerlo de un vistazo, y así el efecto de soltar se
    // puede provocar sin ratón (es como se probó, con la pantalla bloqueada).
    function applyDrop(tile, target, moved) {
        if (!moved) {
            // Un clic sin viaje es "llévame ahí".
            root.focusWin(tile.addr);
            tile.rebind();
            return;
        }

        if (target >= 1 && target !== tile.ws) {
            if (tile.floating) {
                // Primero el escritorio y luego la posición: al cambiar de
                // escritorio Hyprland recoloca las flotantes, así que hacerlo al
                // revés perdería el sitio donde la has dejado.
                const p = root.desktopPos(tile, target);
                tile.setHint(p.x, p.y);
                Hyprland.dispatch("hl.dsp.window.move({ workspace = " + target
                    + ", follow = false, window = " + root.winSelector(tile.addr) + " })");
                Hyprland.dispatch("hl.dsp.window.move({ x = " + p.x + ", y = " + p.y
                    + ", relative = false, window = " + root.winSelector(tile.addr) + " })");
            } else {
                Hyprland.dispatch("hl.dsp.window.move({ workspace = " + target
                    + ", follow = false, window = " + root.winSelector(tile.addr) + " })");
            }
        } else if (target === tile.ws && tile.floating) {
            const p = root.desktopPos(tile, target);
            tile.setHint(p.x, p.y);
            Hyprland.dispatch("hl.dsp.window.move({ x = " + p.x + ", y = " + p.y
                + ", relative = false, window = " + root.winSelector(tile.addr) + " })");
        }

        // Suelte donde suelte, la posición vuelve a mandarla el dato real: o cae
        // en su hueco nuevo, o el muelle la devuelve a donde estaba.
        tile.rebind();
        poll.restart();
    }

    // ── de coordenadas de la rejilla a píxeles del escritorio ──
    // La inversa exacta de lo que hace OverviewWindow para colocarse: se le quita
    // el origen de la celda, se divide por la escala y se le suma otra vez el
    // origen del monitor y la banda reservada. Y se ata al área útil, porque
    // soltar una ventana medio fuera de la rejilla la dejaría medio fuera de la
    // pantalla de verdad.
    function desktopPos(tile, ws) {
        const res = (root.mon && root.mon.reserved) ? root.mon.reserved : [0, 0, 0, 0];
        const mx = root.mon ? root.mon.x : 0;
        const my = root.mon ? root.mon.y : 0;
        const mw = root.mon ? root.mon.width : 1920;
        const mh = root.mon ? root.mon.height : 1080;
        const ux = mx + res[0], uy = my + res[1];
        const uw = Math.max(1, mw - res[0] - res[2]), uh = Math.max(1, mh - res[1] - res[3]);
        const ww = (tile.client && tile.client.size) ? tile.client.size[0] : 0;
        const wh = (tile.client && tile.client.size) ? tile.client.size[1] : 0;
        const lx = (tile.x - root.wsX(ws)) / root.sc;
        const ly = (tile.y - root.wsY(ws)) / root.sc;
        return {
            x: Math.round(Math.max(ux, Math.min(ux + Math.max(0, uw - ww), ux + lx))),
            y: Math.round(Math.max(uy, Math.min(uy + Math.max(0, uh - wh), uy + ly)))
        };
    }
}
