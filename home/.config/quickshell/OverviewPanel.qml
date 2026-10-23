// OverviewPanel.qml — the workspace map, unfolded FROM the notch.
//
// It replaces the old Overview.qml, which took the whole screen and showed the
// windows in a loose grid. The problem with that was not aesthetic: a grid does
// not tell you WHICH WORKSPACE each thing is on, which is exactly the one thing
// you want to know when you press Super+Tab. Here each cell is a workspace to
// scale, with its windows placed where they really are, so the map reads just
// like the desktop.
//
// And the important part: WINDOWS CAN BE DRAGGED. You grab a thumbnail with the
// mouse and drop it on another cell; that is a `movetoworkspacesilent`. If it is
// floating and you drop it inside its own cell, it is repositioned in there
// (`movewindowpixel`). Rearranging the desktop stops being a sequence of
// shortcuts and becomes a gesture.
//
// Two things you do not see by reading the code:
//
// 1. EACH WINDOW'S WORKSPACE IS READ FROM `toplevel.workspace`, BUT ITS
//    POSITION FROM `lastIpcObject`. Measured: Quickshell keeps `workspace` up to
//    date by itself (it listens to Hyprland's events), but `lastIpcObject` —
//    which is where `at` and `size` come from — stays FROZEN until someone calls
//    refreshToplevels(). That is why there is a timer asking for it while the
//    overview is open, and only while it is.
//
// 2. THE MODEL GOES THROUGH ScriptModel ON PURPOSE. The list is recomputed every
//    time a window changes workspace, and a Repeater over a new array DESTROYS
//    AND RECREATES all its delegates: every drag would switch the ten screen
//    captures off and on again, flicker included. ScriptModel compares by
//    identity and only touches what has really changed.
import Quickshell
import Quickshell.Hyprland
import Quickshell.Widgets
import QtQuick

Item {
    id: root

    readonly property bool active: ShellState.panel === "overview"

    // ─── geometry (computed by ShellState, which also sizes the notch) ───
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

    // ─── interaction state ───
    property string dragAddr: ""     // address of the window flying right now
    property int dropWs: -1          // cell under the cursor while dragging
    property int hoverWs: -1         // cell under the cursor when not dragging
    // The pointed-at window, for the footer strip. The TOPLEVEL is stored and
    // not its lastIpcObject: that map is rebuilt on every refresh, so comparing
    // two reads with === would always be false and the highlight would never
    // turn off. The toplevel is the same object for as long as the window
    // exists, and when it closes QML sets this property to null by itself
    // (that is why it is QtObject and not var: a `var` would be left pointing
    // at a dead object).
    property QtObject hoverTl: null
    property int selWs: 1            // keyboard selection

    // It comes from ShellState and is not recomputed here: the notch's "ws"
    // face reads the same value, and two derivations of the same thing is
    // exactly how things start to drift out of sync.
    readonly property int activeWs: ShellState.activeWs

    // Hyprland 0.55+ interprets `dispatch` as a Lua expression. Quickshell
    // sends whatever Hyprland.dispatch() receives as is, so `hl.dsp.*`
    // dispatchers have to be built here; the old hyprlang syntax
    // ("movetoworkspacesilent 2,address:...") is accepted by the QML but the
    // compositor rejects it when the thumbnail is dropped.
    function winSelector(addr) { return '"address:' + addr + '"'; }

    // Special workspaces are filtered out (negative id: the AI scratchpad, for
    // example) along with those that fall outside the grid.
    readonly property var wins: [...Hyprland.toplevels.values].filter(t =>
        t.workspace && t.workspace.id >= 1 && t.workspace.id <= root.cells && t.wayland)

    ScriptModel { id: winModel; values: root.wins }

    function wsX(ws) { return ((ws - 1) % root.cols) * (root.cellW + root.gap); }
    function wsY(ws) { return Math.floor((ws - 1) / root.cols) * (root.cellH + root.gap); }
    function wsAt(px, py) {
        const c = Math.floor(px / (root.cellW + root.gap));
        const r = Math.floor(py / (root.cellH + root.gap));
        if (c < 0 || c >= root.cols || r < 0 || r >= root.rows) return -1;
        // The gap between cells belongs to no one: dropping there moves nothing.
        if (px - c * (root.cellW + root.gap) > root.cellW) return -1;
        if (py - r * (root.cellH + root.gap) > root.cellH) return -1;
        return r * root.cols + c + 1;
    }

    // ── leaving: close first, THEN ask for focus ──
    // Closing the panel releases the HyprlandFocusGrab, and Hyprland responds by
    // giving focus back to the window that had it before the overview opened.
    // If the `focuswindow` goes at the same instant, there is no guarantee who
    // arrives last, and if the hand-back wins you stay on the window you came
    // from: exactly what you have just asked NOT to happen. The 60 ms let the
    // hand-back happen first and give our request the last word. It is the
    // same remedy Tide-island uses (50 ms there).
    //
    // HONESTY about how this came about: it was written believing the race had
    // been seen live, and the test was flawed — the session was in Hyprland's
    // "lockscreen crashed" state, where NO window can take focus and
    // `focuswindow` answers `ok` without doing anything. So the race is real by
    // construction but has NOT been observed. It stays because it costs 60 ms
    // and the bug it prevents is the kind that only shows up now and then.
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

    // ── data refresh ──
    // Only with the overview open. A refreshToplevels() is a query to
    // Hyprland's socket: asking for it all the time would mean paying for it
    // all the time, and 99 % of the time nobody is looking at this.
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
        refocus.restart();   // safety net: the layer takes a moment to accept focus
    }
    Timer {
        id: refocus
        interval: 120
        onTriggered: if (root.active) keys.forceActiveFocus()
    }

    // absorbs clicks on the empty space so they do not close the panel
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
        // 1..9 and 0 jump straight there, just like Super+1..0 outside the
        // overview: the shortcut already in your fingers still works in here.
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
                color: Colors.surface1
                antialiasing: true
                contentUnderBorder: true
                topLeftRadius: (atL && atT) ? root.radOut : root.radIn
                topRightRadius: (atR && atT) ? root.radOut : root.radIn
                bottomLeftRadius: (atL && atB) ? root.radOut : root.radIn
                bottomRightRadius: (atR && atB) ? root.radOut : root.radIn
                border.width: 1
                border.color: cell.isDrop ? Colors.accent : Colors.hairline

                // The wallpaper, at cell size. It is what turns ten grey
                // rectangles into ten SCREENS: without it there is no way to
                // read an empty cell as a workspace.
                // All ten share source and sourceSize, so Qt decodes the JPEG
                // ONCE and hands out the same pixmap.
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

                // Veil. The wallpaper has to stay BELOW the thumbnails in the
                // visual hierarchy: if it competes, the grid turns into noise.
                Rectangle {
                    anchors.fill: parent
                    color: cell.isDrop ? Qt.rgba(Colors.accent.r, Colors.accent.g, Colors.accent.b, 0.20)
                        : cell.isHover ? Qt.rgba(0, 0, 0, 0.28) : Qt.rgba(0, 0, 0, 0.44)
                    Behavior on color { ColorAnimation { duration: Appearance.mQuick } }
                }

                // Workspace number. Large and faint if it is empty (it is the
                // only thing to look at there); small in the corner if it has
                // windows, so as not to paint over them.
                Text {
                    anchors.centerIn: parent
                    visible: cell.empty
                    text: String(cell.ws)
                    color: Colors.label3
                    font.family: Appearance.fontUI
                    font.pixelSize: Math.round(root.cellH * 0.34)
                    font.weight: Font.DemiBold
                }
            }
        }

        // ══════════════ clic en el hueco: ir a ese escritorio ══════════════
        // It sits BELOW the thumbnails: if you click a window the window wins,
        // and if you click the cell's background this wins.
        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onPositionChanged: function (m) { root.hoverWs = root.wsAt(m.x, m.y); root.hoverTl = null; }
            // hoverTl is NOT touched here. When the pointer enters a thumbnail,
            // this area loses hover and fires its onExited: if it cleared
            // hoverTl it might do so AFTER the thumbnail has set it (the order
            // between leaving one and entering another is not guaranteed) and
            // the footer strip would go silent just as you point at a window.
            onExited: root.hoverWs = -1
            onClicked: function (m) {
                const ws = root.wsAt(m.x, m.y);
                if (ws >= 1) root.goTo(ws);
            }
        }

        // ══════════════ las ventanas ══════════════
        // A single copy per window: it is both what you see and what you grab.
        // It can fly freely across the whole grid because nothing clips it
        // (see note 2 in OverviewWindow.qml).
        Repeater {
            model: winModel

            OverviewWindow {
                id: tile
                required property var modelData
                // CAREFUL: `toplevel.address` comes WITHOUT the "0x" and
                // Hyprland's dispatchers require it ("address:0x5637...").
                // Without the prefix every dispatch here answers "moveWindow: no
                // window" and the drag does nothing, silently.
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
                // A fullscreen window covers the others, and a floating one
                // goes above the tiled ones: the same order they really have on
                // the desktop. The one in flight goes above everything, even
                // the active workspace's frame.
                z: dragging ? 300 : (client && client.fullscreen ? 30 : 20) + (client && client.floating ? 5 : 0)

                MouseArea {
                    id: pointer
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton

                    // THE DRAG IS DONE BY HAND, not with Qt's `drag.target`.
                    //
                    // With `drag.target` the thumbnail did not move: Qt moves it
                    // from C++ (QQuickItem::setX) and that does NOT break the
                    // `x: initX` binding, so the binding sent it back to its
                    // cell on every mouse event and the two fought each other.
                    // Measured in the shell's log: x alternated between 1100
                    // -its place- and 2606, which is outside a 1372 px grid,
                    // i.e. off the screen. On camera it looked as if the window
                    // would not drag: only the target cell lit up and on
                    // release it appeared there.
                    //
                    // Moving it from QML is also the only thing that truly
                    // breaks the binding, so the fix and the gesture are one.
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

                        // The threshold that separates a click from a drag. Ten
                        // pixels, the same Qt used: below that, a click with a
                        // shaky hand would lift the thumbnail and read as a
                        // failed drag.
                        if (!pointer.moved) {
                            if (Math.hypot(m.x - pointer.grabX, m.y - pointer.grabY) < 10)
                                return;
                            pointer.moved = true;
                            tile.unbind();
                            root.dragAddr = tile.addr;
                            root.dropWs = tile.ws;
                        }

                        // The cursor in grid coordinates is worked out BEFORE
                        // moving the thumbnail: afterwards, `m.x` is no longer
                        // what it was because the coordinate system has moved
                        // with it.
                        const p = tile.mapToItem(stage, m.x, m.y);
                        tile.x += m.x - pointer.grabX;
                        tile.y += m.y - pointer.grabY;

                        // A tiled one drops where the CURSOR points (it is huge
                        // and would overlap three cells at once); a floating one,
                        // by its CENTRE, which is how you read an object you put
                        // down.
                        root.dropWs = tile.floating
                            ? root.wsAt(tile.x + tile.width / 2, tile.y + tile.height / 2)
                            : root.wsAt(p.x, p.y);
                    }

                    onReleased: function (m) {
                        if (m.button === Qt.RightButton) {
                            // Only if you release ON it. Closing is the only
                            // irreversible thing here, so moving the pointer off
                            // before releasing has to be a way to back out.
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
        // It travels on a spring instead of appearing already in the new cell:
        // if you switch workspace with the overview open, the frame TRAVELS the
        // path, so you see where you are coming from.
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

        // Keyboard selection frame. It only appears when the selection moves
        // away from the active workspace: if they coincided there would be two
        // frames painted one on top of the other saying the same thing.
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
    // The same pattern as the Settings app: the detail is NOT painted over each
    // thing (at this scale a title does not fit in the thumbnail and would
    // cover the window anyway), it goes to a fixed strip that shows whatever is
    // under the mouse. When you point at nothing, it reminds you what can be
    // done here.
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
        color: root.hoverTl ? Colors.label : Colors.label3
        font.family: Appearance.fontUI
        font.pixelSize: Appearance.fsXS
        font.weight: root.hoverTl ? Font.Medium : Font.Normal
        Behavior on color { ColorAnimation { duration: Appearance.mQuick } }
    }

    // ── what happens on drop ──
    // It lives here, outside the mouse handler, for two reasons: the handler was
    // already too long to read at a glance, and this way the drop's effect can
    // be triggered without a mouse (which is how it was tested, with the screen
    // locked).
    function applyDrop(tile, target, moved) {
        if (!moved) {
            // A click with no travel means "take me there".
            root.focusWin(tile.addr);
            tile.rebind();
            return;
        }

        if (target >= 1 && target !== tile.ws) {
            if (tile.floating) {
                // First the workspace and then the position: when changing
                // workspace Hyprland repositions floating windows, so doing it
                // the other way round would lose the spot where you left it.
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

        // Wherever it is dropped, the real data takes charge of the position
        // again: either it lands in its new slot, or the spring returns it to
        // where it was.
        tile.rebind();
        poll.restart();
    }

    // ── from grid coordinates to desktop pixels ──
    // The exact inverse of what OverviewWindow does to place itself: subtract
    // the cell's origin, divide by the scale and add back the monitor's origin
    // and the reserved band. And it is clamped to the usable area, because
    // dropping a window half outside the grid would leave it half off the real
    // screen.
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
