// HistoryGraph.qml — curva temporal compacta para métricas floor..ceiling.
// Canvas se usa aquí a propósito: una serie que cambia cada 1,5 s no merece
// sesenta Rectangle ni un modelo de delegados. El relleno, el suelo y el punto
// vivo salen de la misma geometría, así que nunca se separan entre sí.
//
// ESPECIFICACIÓN DE MARCAS (y no son gustos, son las medidas que hacen que un
// gráfico se lea tranquilo en vez de gritar):
//   · trazo de 2 px, con las uniones y los extremos redondos;
//   · relleno de área al ~10 % del tono — un velo, NUNCA un bloque saturado.
//     Estaba al 24 % y por eso la banda de memoria parecía un ladrillo: un
//     relleno grande y opaco es lo que separa un gráfico de un cartel;
//   · punto final de 8 px de diámetro (r 4) — por debajo de eso no es una
//     marca, es una mota;
//   · anillo de 2 px de SUPERFICIE alrededor del punto, para que se lea allí
//     donde cruza su propia línea. Se hace agujereando (destination-out) en vez
//     de pintando un borde: un borde es tinta que no es dato, y además aquí no
//     serviría porque la tarjeta es translúcida y no hay un color de fondo que
//     copiar;
//   · rejilla y suelo, filete de 1 px SÓLIDO. Punteados no: el punteado mete
//     ruido y se lee como «umbral» o «proyección» cuando solo es una rejilla.
import QtQuick

Canvas {
    id: root

    property var values: []
    property real floor: 0
    property real ceiling: 100
    property color lineColor: Colors.accent
    property color fillTop: Qt.rgba(lineColor.r, lineColor.g, lineColor.b, 0.10)
    property color fillBottom: Qt.rgba(lineColor.r, lineColor.g, lineColor.b, 0.004)
    property color gridColor: Qt.rgba(1, 1, 1, 0.075)
    property bool showGrid: true
    property bool showBaseline: false
    property bool showPoint: true

    // Fracción del ancho por la que la serie se desvanece al entrar (0 = nada).
    // El extremo izquierdo es el pasado que se está cayendo del historial: si se
    // corta a hueso, la curva parece amputada contra el borde de la tarjeta y el
    // ojo va justo ahí. Difuminado, la banda no tiene principio y la mirada se
    // va sola al lado que importa, que es el de «ahora».
    property real fadeIn: 0

    // Muestra señalada por el puntero, o -1. La cruz la pinta el propio Canvas
    // porque tiene que caer EXACTAMENTE sobre la muestra: si fuera un Rectangle
    // colocado desde fuera habría que reproducir aquí el mismo cálculo de
    // coordenadas, y dos copias de una fórmula acaban separándose.
    property int markIndex: -1

    antialiasing: true

    onValuesChanged: requestPaint()
    onMarkIndexChanged: requestPaint()
    onShowBaselineChanged: requestPaint()
    onShowGridChanged: requestPaint()
    onShowPointChanged: requestPaint()
    onFadeInChanged: requestPaint()
    onFloorChanged: requestPaint()
    onCeilingChanged: requestPaint()
    onLineColorChanged: requestPaint()
    onFillTopChanged: requestPaint()
    onFillBottomChanged: requestPaint()
    onGridColorChanged: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    Component.onCompleted: requestPaint()

    function trace(ctx, pts) {
        if (pts.length === 0) return;
        ctx.moveTo(pts[0].x, pts[0].y);
        if (pts.length === 1) return;
        for (let i = 1; i < pts.length - 1; i++) {
            const mx = (pts[i].x + pts[i + 1].x) / 2;
            const my = (pts[i].y + pts[i + 1].y) / 2;
            ctx.quadraticCurveTo(pts[i].x, pts[i].y, mx, my);
        }
        const last = pts[pts.length - 1];
        ctx.quadraticCurveTo(last.x, last.y, last.x, last.y);
    }

    onPaint: {
        const ctx = getContext("2d");
        ctx.clearRect(0, 0, width, height);
        if (width < 2 || height < 2) return;

        // 7 px de aire arriba y abajo: es el radio del punto vivo (4) más su
        // anillo (2), o el punto se recorta contra el borde cuando la serie
        // toca techo o suelo.
        const top = 7, bottom = height - 7;
        const graphH = Math.max(1, bottom - top);

        // Filete sólido de 1 px, un escalón por encima de la superficie. Lo
        // tuve punteado un rato porque «competía menos con la curva»; es al
        // revés: el punteado añade ruido y encima significa otra cosa (umbral,
        // proyección). Lo que hace que la rejilla no compita es que sea tenue,
        // no que esté rota.
        if (root.showGrid) {
            ctx.lineWidth = 1;
            ctx.strokeStyle = root.gridColor;
            for (let i = 1; i <= 3; i++) {
                const gy = top + graphH * i / 4;
                ctx.beginPath();
                ctx.moveTo(0, Math.round(gy) + 0.5);
                ctx.lineTo(width, Math.round(gy) + 0.5);
                ctx.stroke();
            }
        }

        // El suelo. Sin él el área se corta en el vacío y la carta no tiene
        // dónde apoyarse; con él la curva descansa sobre algo.
        if (root.showBaseline) {
            ctx.lineWidth = 1;
            ctx.strokeStyle = root.gridColor;
            ctx.beginPath();
            ctx.moveTo(0, Math.round(bottom) + 0.5);
            ctx.lineTo(width, Math.round(bottom) + 0.5);
            ctx.stroke();
        }

        let raw = root.values && root.values.length ? root.values : [0];
        const vals = raw.length === 1 ? [raw[0], raw[0]] : raw;
        const span = Math.max(0.001, root.ceiling - root.floor);
        const pts = [];
        for (let i = 0; i < vals.length; i++) {
            const v = Math.max(root.floor, Math.min(root.ceiling, Number(vals[i]) || 0));
            pts.push({
                x: vals.length === 1 ? 0 : i * width / (vals.length - 1),
                y: bottom - ((v - root.floor) / span) * graphH
            });
        }

        // Área: más tinta junto a la señal, casi transparente contra la base.
        const gradient = ctx.createLinearGradient(0, top, 0, bottom);
        gradient.addColorStop(0, root.fillTop);
        gradient.addColorStop(1, root.fillBottom);
        ctx.beginPath();
        root.trace(ctx, pts);
        ctx.lineTo(pts[pts.length - 1].x, bottom);
        ctx.lineTo(pts[0].x, bottom);
        ctx.closePath();
        ctx.fillStyle = gradient;
        ctx.fill();

        ctx.beginPath();
        root.trace(ctx, pts);
        ctx.lineCap = "round";
        ctx.lineJoin = "round";
        ctx.lineWidth = 2;
        ctx.strokeStyle = root.lineColor;
        ctx.stroke();

        // Una marca con su anillo: se agujerea (destination-out) el hueco de la
        // superficie y luego se posa el punto dentro. Antes esto era un halo
        // del propio tono sobre una mota de r 2,3 — o sea, más tinta de la
        // serie encima de la serie, que es justo lo que el anillo evita.
        function dot(x, y) {
            ctx.globalCompositeOperation = "destination-out";
            ctx.beginPath();
            ctx.arc(x, y, 6, 0, Math.PI * 2);
            ctx.fillStyle = "rgba(0,0,0,1)";
            ctx.fill();
            ctx.globalCompositeOperation = "source-over";
            ctx.beginPath();
            ctx.arc(x, y, 4, 0, Math.PI * 2);
            ctx.fillStyle = root.lineColor;
            ctx.fill();
        }

        // La cruz busca la X: se engancha a la muestra más cercana, así que se
        // apunta a un instante y no a una línea de dos píxeles.
        const mi = root.markIndex;
        if (mi >= 0 && mi < pts.length) {
            const m = pts[mi];
            ctx.lineWidth = 1;
            ctx.strokeStyle = root.gridColor;
            ctx.beginPath();
            ctx.moveTo(Math.round(m.x) + 0.5, 0);
            ctx.lineTo(Math.round(m.x) + 0.5, height);
            ctx.stroke();
            dot(m.x, m.y);
        }

        // El punto de «ahora». Se aparta 4 px del borde para que su anillo no
        // se salga del lienzo.
        if (root.showPoint) {
            const p = pts[pts.length - 1];
            dot(p.x - 4, p.y);
        }

        // El desvanecido va AL FINAL y se come todo lo pintado antes (rejilla,
        // suelo, área y trazo a la vez). Con 'destination-out' el degradado no
        // añade tinta: quita alfa, así que funciona igual sea cual sea el color
        // que haya debajo de la tarjeta. Pintar encima un degradado del color
        // del fondo no valdría: la tarjeta es translúcida y se notaría el
        // parche.
        if (root.fadeIn > 0) {
            const edge = Math.max(1, width * root.fadeIn);
            const mask = ctx.createLinearGradient(0, 0, edge, 0);
            mask.addColorStop(0, "rgba(0,0,0,1)");
            mask.addColorStop(1, "rgba(0,0,0,0)");
            ctx.globalCompositeOperation = "destination-out";
            ctx.fillStyle = mask;
            ctx.fillRect(0, 0, edge, height);
            ctx.globalCompositeOperation = "source-over";
        }
    }
}
