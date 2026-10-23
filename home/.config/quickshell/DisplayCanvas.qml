// DisplayCanvas.qml — the map: your screens to scale, draggable.
//
// Adapted from Impasto's settings/MonitorCanvas.qml
// (https://github.com/andreumassanet/impasto, GPL-3.0).
//
// It is Hyprland's coordinate space shrunk until it fits. You drag a screen
// and, WHEN YOU DROP IT, it snaps to the nearest edge of another one if that
// edge is close at hand. Snapping only on release and not during the drag is
// deliberate: if the plate jumped under the pointer, dragging would stop being
// dragging. And without the magnet, a free drag nearly always leaves a
// three-pixel gap between two monitors, which on the desktop shows up as a
// dead strip the mouse has to jump across.
import QtQuick

Item {
    id: root

    // The screens from Displays, or a subset of them.
    property var monitors: []
    property string selected: ""

    signal picked(string key)
    // The WHOLE layout as { key: { x, y } }: when normalising, moving one screen
    // can shift all the others, not just the one you dragged.
    signal arranged(var positions)

    // Disabled ones have no geometry to draw; the section lists them separately.
    readonly property var lit: root.monitors.filter(m => !m.disabled)

    readonly property int spanX: {
        let far = 1;
        for (const m of root.lit) far = Math.max(far, m.x + m.width);
        return far;
    }
    readonly property int spanY: {
        let far = 1;
        for (const m of root.lit) far = Math.max(far, m.y + m.height);
        return far;
    }

    // The whole set is fitted with some slack and centred, so there is room to
    // drop a screen to the left of or above all the others. 1.6 leaves about two
    // thirds of a width free on each side.
    readonly property real slack: 1.6
    readonly property int pad: 24

    readonly property real factor: Math.min(
        (width - 2 * root.pad) / (root.spanX * root.slack),
        (height - 2 * root.pad) / (root.spanY * root.slack))

    // Where the origin of Hyprland's space falls inside the map.
    readonly property real originX: (width - 2 * root.pad - root.spanX * root.factor) / 2
    readonly property real originY: (height - 2 * root.pad - root.spanY * root.factor) / 2

    // The magnet, in Hyprland pixels: derived from 80 px of the MAP, so it feels
    // just as strong with two screens as with four.
    readonly property int reach: Math.round(80 / Math.max(root.factor, 0.0001))

    // Where a screen dropped at (x, y) ends up. Each axis is decided on its own
    // and against four candidates per other screen: stuck to one side, stuck to
    // the other, or aligned along the top or the bottom. The nearest one within
    // reach wins.
    function settle(key, wantedX, wantedY) {
        const me = root.lit.find(m => m.key === key);
        if (!me) return { x: Math.round(wantedX), y: Math.round(wantedY) };

        let x = Math.round(wantedX);
        let y = Math.round(wantedY);
        let nearestX = root.reach;
        let nearestY = root.reach;

        for (const other of root.lit) {
            if (other.key === key) continue;

            for (const candidate of [other.x - me.width, other.x + other.width,
                                     other.x, other.x + other.width - me.width]) {
                const gap = Math.abs(candidate - wantedX);
                if (gap < nearestX) { nearestX = gap; x = candidate; }
            }
            for (const candidate of [other.y - me.height, other.y + other.height,
                                     other.y, other.y + other.height - me.height]) {
                const gap = Math.abs(candidate - wantedY);
                if (gap < nearestY) { nearestY = gap; y = candidate; }
            }
        }
        return { x: x, y: y };
    }

    // Where each screen ends up after the drop, with everything shifted so that
    // the top-left corner of the set is (0, 0). Hyprland accepts negative
    // coordinates, but normalising means the same layout is always saved with the
    // same numbers, and that way `differs` does not think something has changed
    // when nothing has.
    function arrangementWith(key, at) {
        const places = ({});
        for (const m of root.lit)
            places[m.key] = m.key === key ? { x: at.x, y: at.y } : { x: m.x, y: m.y };

        let leftmost = Infinity, topmost = Infinity;
        for (const k in places) {
            leftmost = Math.min(leftmost, places[k].x);
            topmost = Math.min(topmost, places[k].y);
        }
        for (const k in places) {
            places[k].x -= leftmost;
            places[k].y -= topmost;
        }
        return places;
    }

    Rectangle {
        anchors.fill: parent
        radius: Appearance.radM
        color: Colors.surface1
        border.width: 1
        border.color: Colors.hairline
    }

    Item {
        id: field
        x: root.pad
        y: root.pad
        width: parent.width - 2 * root.pad
        height: parent.height - 2 * root.pad

        Repeater {
            model: root.lit

            Rectangle {
                id: plate
                required property var modelData
                readonly property bool chosen: plate.modelData.key === root.selected

                // Bound to Hyprland's position except while being dragged.
                x: drag.active ? x : root.originX + plate.modelData.x * root.factor
                y: drag.active ? y : root.originY + plate.modelData.y * root.factor
                width: plate.modelData.width * root.factor
                height: plate.modelData.height * root.factor

                // 7 px and not radS: the plate is a miniature, and the shell's radius at
                // this size would eat the whole corner (same reasoning as the miniature
                // bar in SettingsBarPreview).
                radius: 7
                color: plate.chosen ? Qt.rgba(Colors.accent.r, Colors.accent.g, Colors.accent.b, 0.30)
                                    : Colors.fill3
                border.width: 1
                border.color: plate.chosen ? Colors.accent : Colors.hairline
                z: drag.active ? 2 : (plate.chosen ? 1 : 0)

                Behavior on color { ColorAnimation { duration: Appearance.mQuick; easing.type: Easing.OutQuad } }
                Behavior on border.color { ColorAnimation { duration: Appearance.mQuick; easing.type: Easing.OutQuad } }

                Column {
                    anchors.centerIn: parent
                    spacing: 1
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: plate.modelData.name
                        color: plate.chosen ? Colors.label : Colors.label2
                        font.family: Appearance.fontUI
                        font.pixelSize: Appearance.fsXS
                        font.weight: Font.DemiBold
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        visible: plate.height > 42
                        text: plate.modelData.width + " × " + plate.modelData.height
                        color: plate.chosen ? Colors.label2 : Colors.label3
                        font.family: Appearance.font
                        font.pixelSize: Appearance.fsXXS
                    }
                }

                MouseArea {
                    id: drag
                    anchors.fill: parent
                    cursorShape: root.lit.length > 1 ? Qt.OpenHandCursor : Qt.PointingHandCursor

                    property bool active: false
                    property real grabX: 0
                    property real grabY: 0

                    onPressed: function (mouse) {
                        root.picked(plate.modelData.key);
                        // With a single screen there is nothing to place: moving it would
                        // only change a number that Hyprland normalises to 0x0.
                        if (root.lit.length < 2) return;
                        drag.grabX = mouse.x;
                        drag.grabY = mouse.y;
                        drag.active = true;
                    }
                    onPositionChanged: function (mouse) {
                        if (!drag.active) return;
                        plate.x += mouse.x - drag.grabX;
                        plate.y += mouse.y - drag.grabY;
                    }
                    onReleased: {
                        if (!drag.active) return;
                        drag.active = false;
                        const at = root.settle(plate.modelData.key,
                                               (plate.x - root.originX) / root.factor,
                                               (plate.y - root.originY) / root.factor);
                        root.arranged(root.arrangementWith(plate.modelData.key, at));
                    }
                    onCanceled: drag.active = false
                }
            }
        }
    }
}
