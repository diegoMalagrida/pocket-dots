// OverviewWindow.qml — ONE window inside the overview grid.
//
// It is a LIVE thumbnail (ScreencopyView), not an icon: the workspace map is
// only useful if it lets you tell at a glance what is on 4, and for that you
// need to see the content, not the app's name.
//
// Three things that are not obvious:
//
// 1. THE POSITION COMES FROM HYPRLAND, NOT FROM A LAYOUT. The window is placed
//    where it really is on its workspace (`at` and `size` from hyprctl clients,
//    minus the monitor's origin and the reserved band, times the scale). That
//    is why a small floating window looks small and off-centre, just as on the
//    real desktop: the grid is a MAP, not a list of windows.
//
// 2. THE THUMBNAIL NEVER LEAVES ITS CELL, and that is why the cell does not
//    need to clip. Clipping would mean painting every window TWICE (a clipped
//    copy inside and a free one for dragging, because you cannot pull something
//    out of a box that clips it). Tying position and size to the cell's area,
//    one single copy is enough, and it is also the one that flies when dragged.
//
// 3. constraintSize LIMITS THE CAPTURE. Without it, capturing ten 1908x1036
//    windows at full size to paint them at 267x145 burns the iGPU only to throw
//    away 98 % of the pixels. With it, the compositor already delivers the size
//    that is going to be painted.
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import QtQuick

Item {
    id: tile

    // ─── data ───
    property var client: null       // object from `hyprctl clients` (lastIpcObject)
    property var toplevel: null     // Wayland Toplevel, the thumbnail's source
    property var mon: null          // the monitor's lastIpcObject
    property real sc: 0.14          // scale desktop -> cell
    property real cellW: 0
    property real cellH: 0
    property real offX: 0           // the cell's corner inside the grid
    property real offY: 0

    // ─── visual state ───
    property bool live: false       // capturing? only with the overview open
    property bool hovered: false
    property bool pressed: false
    property bool dragging: false

    // The window you would go back to if you closed the overview right now.
    // `toplevel.activated` is not used: while the overview is open the keyboard
    // focus belongs to the shell's own layer, so NO window is activated and the
    // highlight would vanish exactly when it is needed.
    // focusHistoryID === 0 is "the last one that had focus", which is what is
    // meant here and survives the grab.
    readonly property bool focused: !!(client && client.focusHistoryID === 0)

    property real radOut: 18        // radius of the grid's outer corner
    property real radIn: 10         // radius of the inner corners
    property real radMin: 7         // radius of a window that touches no edge
    property bool atL: false; property bool atR: false
    property bool atT: false; property bool atB: false

    // ── the optimistic position ──
    // Hyprland takes ~100 ms to confirm a move. If the thumbnail waited for the
    // confirmation, on release it would jump back to the old spot and then
    // jump again to the new one. With this it stays where you left it, and the
    // lie withdraws itself as soon as the real data matches (or after 700 ms,
    // if the move never happened).
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

    // Floors and ceilings in pixels. The floor, because a 200x100 dialog would
    // give a 28x14 thumbnail you can neither see nor click. The ceiling,
    // because it is what guarantees the window does not leave its cell (see
    // note 2).
    readonly property real tw: Math.min(cellW, Math.max(34, (client && client.size ? client.size[0] : 240) * sc))
    readonly property real th: Math.min(cellH, Math.max(24, (client && client.size ? client.size[1] : 140) * sc))
    readonly property real initX: offX + Math.max(0, Math.min(cellW - tw, (at[0] - monX - res[0]) * sc))
    readonly property real initY: offY + Math.max(0, Math.min(cellH - th, (at[1] - monY - res[1]) * sc))

    // ── the rounding is INHERITED from the edge it touches ──
    // A maximised window fills the cell: if it had its own small radius you
    // would see a black halo in the cell's four corners. Here, the closer it
    // sits to an edge, the more it adopts THAT edge's radius; as soon as it
    // moves a few pixels away it returns to its own. That way the mosaic reads
    // as one single cut-out piece and not as loose cards on top of a background.
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

    // Restores the position bindings on release.
    function rebind() {
        tile.x = Qt.binding(() => tile.initX);
        tile.y = Qt.binding(() => tile.initY);
    }

    // And RELEASES them when a drag starts. This was the drag bug, and the note
    // on rebind() said exactly the opposite: `drag.target` does not move the
    // thumbnail from QML, it moves it from C++ (QQuickItem::setX), and that
    // does NOT break the binding. The binding stayed alive, so every time
    // `initX` was re-evaluated -that is, on every mouse event- it snapped the
    // thumbnail back to its cell, and the two fought each other at 60 fps.
    // Measured in the log: x alternated between 1100 (its spot) and 2606, which
    // is OUTSIDE the grid (1372 px wide), that is, off the screen.
    //
    // On camera that looked exactly as Diego described it: the window does not
    // drag, only the target cell lights up, and on release it appears there.
    // With the bindings released, Qt alone is in charge and the thumbnail stays
    // stuck to the cursor, which is what it was meant to show.
    function unbind() {
        const px = tile.x;
        const py = tile.y;
        tile.x = px;
        tile.y = py;
    }

    // While you drag, the thumbnail has to be STUCK to the cursor: any
    // interpolation here reads as lag, not as smoothness.
    Behavior on x { enabled: !tile.dragging; NumberAnimation { duration: Appearance.mIn; easing.type: Easing.OutCubic } }
    Behavior on y { enabled: !tile.dragging; NumberAnimation { duration: Appearance.mIn; easing.type: Easing.OutCubic } }
    Behavior on width { NumberAnimation { duration: Appearance.mIn; easing.type: Easing.OutCubic } }
    Behavior on height { NumberAnimation { duration: Appearance.mIn; easing.type: Easing.OutCubic } }

    // The lift on grabbing. It is not decoration: it is what separates "I am
    // dragging this" from "the mouse is passing over". It is on a spring so
    // that on release it settles instead of cutting off.
    property real lift: dragging ? 1.07 : (pressed ? 0.97 : 1)
    Behavior on lift { SpringAnimation { spring: Appearance.sprTight; damping: Appearance.dmpTight; epsilon: Appearance.eppScale } }
    scale: lift
    transformOrigin: Item.Center

    ClippingRectangle {
        anchors.fill: parent
        color: Colors.surface2
        antialiasing: true
        contentUnderBorder: true
        topLeftRadius: tile.corner(tile.atL, tile.atT, tile.dL, tile.dT)
        topRightRadius: tile.corner(tile.atR, tile.atT, tile.dR, tile.dT)
        bottomLeftRadius: tile.corner(tile.atL, tile.atB, tile.dL, tile.dB)
        bottomRightRadius: tile.corner(tile.atR, tile.atB, tile.dR, tile.dB)
        // The border says three different things and that is why they are
        // three colours, not three thicknesses: changing the thickness would
        // shift the content by a pixel, and with ten thumbnails that shows as
        // the whole grid trembling.
        border.width: 1
        border.color: tile.dragging ? Colors.accent
            : tile.hovered ? Qt.rgba(1, 1, 1, 0.45)
            : tile.focused ? Qt.rgba(Colors.accent.r, Colors.accent.g, Colors.accent.b, 0.7)
            : Colors.hairline
        Behavior on border.color { ColorAnimation { duration: Appearance.mQuick } }

        ScreencopyView {
            id: shot
            anchors.fill: parent
            captureSource: tile.live ? tile.toplevel : null
            // Rounded to the pixel: a fractional size would make the
            // compositor rescale the capture on every frame.
            constraintSize: Qt.size(Math.max(1, Math.round(tile.width)), Math.max(1, Math.round(tile.height)))
            live: tile.live
        }

        // Fallback icon. A freshly opened window can take a while to deliver its
        // first frame; without this the gap stays black and looks as if it did
        // not exist.
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

        // State veil. It goes INSIDE the clip so it respects the corners.
        Rectangle {
            anchors.fill: parent
            color: tile.dragging ? Qt.rgba(Colors.accent.r, Colors.accent.g, Colors.accent.b, 0.14)
                : tile.hovered ? Colors.fill2 : "transparent"
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
