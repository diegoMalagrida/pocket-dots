// HistoryGraph.qml — compact time curve for floor..ceiling metrics.
// Canvas is used here on purpose: a series that changes every 1.5 s does not
// deserve sixty Rectangles or a delegate model. The fill, the baseline and the
// live point come from the same geometry, so they never drift apart.
//
// MARK SPECIFICATION (and these are not matters of taste, they are the
// measurements that make a chart read calmly instead of shouting):
//   · 2 px stroke, with round joins and caps;
//   · area fill at ~10 % of the hue — a veil, NEVER a saturated block.
//     It was at 24 % and that is why the memory band looked like a brick: a
//     large, opaque fill is what separates a chart from a poster;
//   · end point 8 px in diameter (r 4) — below that it is not a mark, it is a
//     speck;
//   · a 2 px ring of SURFACE around the point, so it reads where it crosses
//     its own line. It is done by punching a hole (destination-out) instead of
//     painting a border: a border is ink that is not data, and besides it
//     would not work here because the card is translucent and there is no
//     background colour to copy;
//   · grid and baseline, a 1 px SOLID rule. Not dotted: dotting adds noise and
//     reads as «threshold» or «projection» when it is only a grid.
import QtQuick

Canvas {
    id: root

    property var values: []
    property real floor: 0
    property real ceiling: 100
    property color lineColor: Colors.accent
    property color fillTop: Qt.rgba(lineColor.r, lineColor.g, lineColor.b, 0.10)
    property color fillBottom: Qt.rgba(lineColor.r, lineColor.g, lineColor.b, 0.004)
    property color gridColor: Colors.hairline
    property bool showGrid: true
    property bool showBaseline: false
    property bool showPoint: true

    // Fraction of the width over which the series fades in (0 = none). The
    // left end is the past falling off the history: if it is cut hard, the
    // curve looks amputated against the edge of the card and the eye goes
    // straight there. Faded, the band has no beginning and the gaze drifts on
    // its own to the side that matters, which is «now».
    property real fadeIn: 0

    // Sample pointed at by the cursor, or -1. The crosshair is painted by the
    // Canvas itself because it has to land EXACTLY on the sample: if it were a
    // Rectangle placed from outside, the same coordinate calculation would have
    // to be reproduced here, and two copies of a formula end up drifting apart.
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

        // 7 px of air above and below: it is the radius of the live point (4)
        // plus its ring (2), or the point gets clipped against the edge when the
        // series touches the ceiling or the floor.
        const top = 7, bottom = height - 7;
        const graphH = Math.max(1, bottom - top);

        // Solid 1 px rule, one step above the surface. I had it dotted for a
        // while because it «competed less with the curve»; it is the other way
        // round: dotting adds noise and on top of that it means something else
        // (threshold, projection). What keeps the grid from competing is being
        // faint, not being broken.
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

        // The baseline. Without it the area is cut off in mid-air and the chart
        // has nothing to stand on; with it the curve rests on something.
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

        // Area: more ink next to the signal, almost transparent at the base.
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

        // A mark with its ring: the surface gap is punched out
        // (destination-out) and then the point is set inside it. This used to
        // be a halo of the same hue over a speck of r 2.3 — in other words,
        // more of the series' ink on top of the series, which is exactly what
        // the ring avoids.
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

        // The crosshair looks for the X: it snaps to the nearest sample, so you
        // point at an instant and not at a two-pixel line.
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

        // The «now» point. It is moved 4 px away from the edge so its ring does
        // not spill off the canvas.
        if (root.showPoint) {
            const p = pts[pts.length - 1];
            dot(p.x - 4, p.y);
        }

        // The fade goes LAST and eats everything painted before it (grid,
        // baseline, area and stroke at once). With 'destination-out' the
        // gradient adds no ink: it removes alpha, so it works the same whatever
        // colour lies under the card. Painting a gradient of the background
        // colour on top would not do: the card is translucent and the patch
        // would show.
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
