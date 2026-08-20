// OverviewWindow.qml — UNA ventana dentro de la rejilla del overview.
//
// Es una miniatura EN VIVO (ScreencopyView), no un icono: el mapa de
// escritorios solo sirve para decidir si sabes de un vistazo qué hay en el 4, y
// para eso hace falta ver el contenido, no el nombre de la app.
//
// Tres cosas que no son evidentes:
//
// 1. LA POSICIÓN SALE DE HYPRLAND, NO DE UN LAYOUT. La ventana se coloca donde
//    está de verdad en su escritorio (`at` y `size` de hyprctl clients, menos el
//    origen del monitor y la banda reservada, por la escala). Por eso una
//    flotante pequeña se ve pequeña y descentrada, igual que en el escritorio
//    real: la rejilla es un MAPA, no una lista de ventanas.
//
// 2. LA MINIATURA NUNCA SE SALE DE SU CELDA, y por eso la celda no necesita
//    recortar. Recortar obligaría a pintar cada ventana DOS veces (una copia
//    recortada dentro y otra libre para arrastrar, porque no puedes sacar algo
//    de una caja que lo recorta). Atando la posición y el tamaño al área de la
//    celda basta con una sola copia, que además es la que vuela al arrastrar.
//
// 3. constraintSize LIMITA LA CAPTURA. Sin él, capturar diez ventanas de
//    1908x1036 a tamaño completo para pintarlas a 267x145 quema la iGPU para
//    tirar el 98 % de los píxeles. Con él, el compositor entrega ya el tamaño
//    que se va a pintar.
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import QtQuick

Item {
    id: tile

    // ─── datos ───
    property var client: null       // objeto de `hyprctl clients` (lastIpcObject)
    property var toplevel: null     // Toplevel de Wayland, la fuente de la miniatura
    property var mon: null          // lastIpcObject del monitor
    property real sc: 0.14          // escala escritorio -> celda
    property real cellW: 0
    property real cellH: 0
    property real offX: 0           // esquina de la celda dentro de la rejilla
    property real offY: 0

    // ─── estado visual ───
    property bool live: false       // ¿capturamos? solo con el overview abierto
    property bool hovered: false
    property bool pressed: false
    property bool dragging: false

    // La ventana a la que volverías si cerraras el overview ahora mismo. No se
    // usa `toplevel.activated`: mientras el overview está abierto el foco de
    // teclado lo tiene la propia capa del shell, así que NINGUNA ventana está
    // activada y el resaltado desaparecería justo cuando hace falta.
    // focusHistoryID === 0 es "la última que tuvo el foco", que es lo que se
    // quiere decir aquí y sobrevive al grab.
    readonly property bool focused: !!(client && client.focusHistoryID === 0)

    property real radOut: 18        // radio de la esquina exterior de la rejilla
    property real radIn: 10         // radio de las esquinas interiores
    property real radMin: 7         // radio de una ventana que no toca ningún borde
    property bool atL: false; property bool atR: false
    property bool atT: false; property bool atB: false

    // ── la posición optimista ──
    // Hyprland tarda ~100 ms en confirmar un movimiento. Si la miniatura
    // esperase a la confirmación, al soltar volvería de un salto al sitio viejo
    // y saltaría después al nuevo. Con esto se queda donde la has dejado, y la
    // mentira se retira sola en cuanto el dato real coincide (o a los 700 ms, si
    // el movimiento no llegó a hacerse).
    property var posHint: null
    Timer { id: hintGuard; interval: 700; onTriggered: tile.posHint = null }
    function setHint(hx, hy) { tile.posHint = { x: hx, y: hy }; hintGuard.restart(); }
    onClientChanged: {
        if (!posHint || !client || !client.at) return;
        if (Math.abs(client.at[0] - posHint.x) <= 2 && Math.abs(client.at[1] - posHint.y) <= 2) {
            posHint = null;
            hintGuard.stop();
        }
    }

    readonly property var res: (mon && mon.reserved) ? mon.reserved : [0, 0, 0, 0]
    readonly property real monX: mon ? mon.x : 0
    readonly property real monY: mon ? mon.y : 0
    readonly property var at: posHint ? [posHint.x, posHint.y]
        : (client && client.at ? client.at : [monX + res[0], monY + res[1]])

    // Suelos y techos en píxeles. El suelo, porque un diálogo de 200x100 daría
    // una miniatura de 28x14 que no se puede ni ver ni pinchar. El techo, porque
    // es lo que garantiza que la ventana no se salga de su celda (ver nota 2).
    readonly property real tw: Math.min(cellW, Math.max(34, (client && client.size ? client.size[0] : 240) * sc))
    readonly property real th: Math.min(cellH, Math.max(24, (client && client.size ? client.size[1] : 140) * sc))
    readonly property real initX: offX + Math.max(0, Math.min(cellW - tw, (at[0] - monX - res[0]) * sc))
    readonly property real initY: offY + Math.max(0, Math.min(cellH - th, (at[1] - monY - res[1]) * sc))

    // ── el redondeo se HEREDA del borde que toca ──
    // Una ventana maximizada llena la celda: si tuviera su propio radio pequeño
    // se vería un halo negro en las cuatro esquinas de la celda. Aquí, cuanto
    // más pegada está a un borde, más adopta el radio de ESE borde; en cuanto se
    // separa unos píxeles vuelve al suyo. Así el mosaico se lee como una sola
    // pieza recortada y no como cartas sueltas encima de un fondo.
    readonly property real dL: Math.max(0, initX - offX)
    readonly property real dR: Math.max(0, cellW - (initX - offX) - tw)
    readonly property real dT: Math.max(0, initY - offY)
    readonly property real dB: Math.max(0, cellH - (initY - offY) - th)
    function corner(cA, cB, dA, dB_) {
        const base = (cA && cB) ? tile.radOut : tile.radIn;
        return Math.max(base - Math.max(dA, dB_), tile.radMin);
    }

    x: initX
    y: initY
    width: tw
    height: th

    // Restaura los bindings de posición al soltar.
    function rebind() {
        tile.x = Qt.binding(() => tile.initX);
        tile.y = Qt.binding(() => tile.initY);
    }

    // Y los SUELTA al empezar a arrastrar. Esto era el fallo del arrastre, y la
    // nota de rebind() lo decía justo al revés: `drag.target` no mueve la
    // miniatura desde QML, la mueve desde C++ (QQuickItem::setX), y eso NO rompe
    // el binding. El binding seguía vivo, así que cada vez que se reevaluaba
    // `initX` -o sea a cada evento del ratón- devolvía la miniatura a su celda
    // de un salto, y las dos cosas se peleaban a 60 fps. Medido en el log: x
    // alternaba entre 1100 (su sitio) y 2606, que está FUERA de la rejilla (1372
    // px de ancho), o sea fuera de la pantalla.
    //
    // En cámara eso se veía exactamente como lo describió Diego: la ventana no
    // se arrastra, solo se enciende la celda de destino, y al soltar aparece
    // allí. Con los bindings sueltos, Qt manda solo y la miniatura va pegada al
    // cursor, que es lo que se quería enseñar.
    function unbind() {
        const px = tile.x;
        const py = tile.y;
        tile.x = px;
        tile.y = py;
    }

    // Mientras arrastras, la miniatura tiene que ir PEGADA al cursor: cualquier
    // interpolación aquí se lee como retraso, no como suavidad.
    Behavior on x { enabled: !tile.dragging; NumberAnimation { duration: Appearance.mIn; easing.type: Easing.OutCubic } }
    Behavior on y { enabled: !tile.dragging; NumberAnimation { duration: Appearance.mIn; easing.type: Easing.OutCubic } }
    Behavior on width { NumberAnimation { duration: Appearance.mIn; easing.type: Easing.OutCubic } }
    Behavior on height { NumberAnimation { duration: Appearance.mIn; easing.type: Easing.OutCubic } }

    // El levantamiento al agarrar. No es adorno: es lo que separa "estoy
    // arrastrando esto" de "el ratón pasa por encima". Va con muelle para que al
    // soltar se pose en vez de cortarse.
    property real lift: dragging ? 1.07 : (pressed ? 0.97 : 1)
    Behavior on lift { SpringAnimation { spring: Appearance.sprTight; damping: Appearance.dmpTight; epsilon: Appearance.eppScale } }
    scale: lift
    transformOrigin: Item.Center

    ClippingRectangle {
        anchors.fill: parent
        color: "#101010"
        antialiasing: true
        contentUnderBorder: true
        topLeftRadius: tile.corner(tile.atL, tile.atT, tile.dL, tile.dT)
        topRightRadius: tile.corner(tile.atR, tile.atT, tile.dR, tile.dT)
        bottomLeftRadius: tile.corner(tile.atL, tile.atB, tile.dL, tile.dB)
        bottomRightRadius: tile.corner(tile.atR, tile.atB, tile.dR, tile.dB)
        // El borde dice tres cosas distintas y por eso son tres colores, no tres
        // grosores: cambiar el grosor movería el contenido un píxel y con diez
        // miniaturas eso se ve como un temblor de la rejilla entera.
        border.width: 1
        border.color: tile.dragging ? Colors.accent
            : tile.hovered ? Qt.rgba(1, 1, 1, 0.45)
            : tile.focused ? Qt.rgba(Colors.accent.r, Colors.accent.g, Colors.accent.b, 0.7)
            : Qt.rgba(1, 1, 1, 0.16)
        Behavior on border.color { ColorAnimation { duration: Appearance.mQuick } }

        ScreencopyView {
            id: shot
            anchors.fill: parent
            captureSource: tile.live ? tile.toplevel : null
            // Redondeado al píxel: un tamaño fraccionario haría que el
            // compositor reescalase la captura en cada fotograma.
            constraintSize: Qt.size(Math.max(1, Math.round(tile.width)), Math.max(1, Math.round(tile.height)))
            live: tile.live
        }

        // Icono de respaldo. Una ventana recién abierta puede tardar en dar su
        // primer fotograma; sin esto el hueco queda negro y parece que no existe.
        Image {
            id: fallback
            readonly property real s: Math.max(20, Math.min(tile.width, tile.height) * 0.42)
            anchors.centerIn: parent
            visible: !shot.hasContent && source !== ""
            source: tile.iconSource
            width: s; height: s
            sourceSize: Qt.size(s, s)
            mipmap: true
            opacity: 0.9
        }

        // Velo de estado. Va DENTRO del recorte para que respete las esquinas.
        Rectangle {
            anchors.fill: parent
            color: tile.dragging ? Qt.rgba(Colors.accent.r, Colors.accent.g, Colors.accent.b, 0.14)
                : tile.hovered ? Qt.rgba(1, 1, 1, 0.08) : "transparent"
            Behavior on color { ColorAnimation { duration: Appearance.mQuick } }
        }
    }

    readonly property string cls: client ? (client["class"] || client.initialClass || "") : ""
    readonly property string iconSource: {
        if (tile.cls.length === 0) return "";
        const entry = DesktopEntries.heuristicLookup(tile.cls);
        return Quickshell.iconPath(entry ? entry.icon : tile.cls.toLowerCase(), "application-x-executable");
    }
}
