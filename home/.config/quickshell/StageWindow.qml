// Stage Manager, as Apple draws it: the other workspaces float on the left as
// stacks of their real windows, turned towards the middle of the screen, and
// come out when the pointer touches the left edge. It never grabs the keyboard
// or reserves desktop space; only its visible footprint receives pointer input.
pragma ComponentBehavior: Bound
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Io
import QtQuick
import QtQuick.Controls

Scope {
    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: win
            required property var modelData
            screen: modelData
            anchors { left: true; top: true; bottom: true }
            implicitWidth: Math.min(330, screen ? screen.width * 0.3 : 330)
            // Setting exclusiveZone would override Ignore and offset this layer
            // by the bar's reserved band, moving the projection's vanishing point.
            exclusionMode: ExclusionMode.Ignore
            color: "transparent"
            visible: ShellState.stageEnabled
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "quickshell:stage"
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

            readonly property var hlMonitor: Hyprland.monitorFor(screen)
            readonly property var monitor: hlMonitor ? hlMonitor.lastIpcObject : null
            readonly property int currentWs: hlMonitor && hlMonitor.activeWorkspace
                ? hlMonitor.activeWorkspace.id
                : monitor && monitor.activeWorkspace ? monitor.activeWorkspace.id : -1
            readonly property bool available: ShellState.stageEnabled && ShellState.panel === ""
            // A window plane before the perspective folds it, and the room each stack takes.
            readonly property real cardWidth: Math.min(300, screen ? screen.width * 0.16 : 300)
            readonly property real slotHeight: Math.round(cardWidth * 0.64) + Appearance.gapL
            readonly property real chipSize: 26
            readonly property var allWorkspaces: [...Hyprland.workspaces.values]
                .filter(ws => ws.id > 0 && ws.monitor && ws.monitor.name === win.modelData.name)
                .sort((a, b) => a.id - b.id)
            readonly property var occupiedIds: [...Hyprland.toplevels.values]
                .filter(t => t.workspace && t.wayland).map(t => t.workspace.id)
            readonly property var workspaces: allWorkspaces.filter(ws =>
                ws.id !== win.currentWs && occupiedIds.indexOf(ws.id) >= 0)
            readonly property var emptyWorkspaces: allWorkspaces.filter(ws =>
                ws.id !== win.currentWs && occupiedIds.indexOf(ws.id) < 0)
            readonly property real chipsHeight: emptyWorkspaces.length > 0 ? chipSize + Appearance.gapL : 0
            property bool revealed: false

            IpcHandler {
                target: "stage-" + win.modelData.name
                function reveal(): void { win.reveal(); }
                function hide(): void { win.fold(); }
                function status(): string {
                    return JSON.stringify({ enabled: ShellState.stageEnabled, revealed: win.revealed,
                        current: win.currentWs, workspaces: win.workspaces.map(ws => ws.id),
                        empty: win.emptyWorkspaces.map(ws => ws.id),
                        x: rail.x, y: rail.y, height: rail.height });
                }
            }

            onAvailableChanged: if (!available) fold()
            onVisibleChanged: if (!visible) fold()

            function fold() {
                revealDelay.stop(); hideDelay.stop();
                revealed = false;
            }
            function reveal() {
                if (!available || allWorkspaces.length < 2) return;
                hideDelay.stop();
                Hyprland.refreshToplevels();
                revealed = true;
            }
            function choose(ws) {
                fold();
                // No grab is held, so the compositor can focus the workspace now.
                // Choosing the current one is deliberately a no-op: back-and-forth
                // workspace bindings must not turn a click into an unexpected jump.
                if (ws !== currentWs)
                    Hyprland.dispatch("hl.dsp.focus({ workspace = " + ws + " })");
            }

            Timer { id: revealDelay; interval: 160; onTriggered: win.reveal() }
            Timer { id: hideDelay; interval: 300; onTriggered: win.revealed = false }
            Timer { id: refreshDelay; interval: 90; onTriggered: Hyprland.refreshToplevels() }
            Connections {
                target: Hyprland
                enabled: win.revealed
                function onRawEvent(ev) {
                    const name = String(ev.name);
                    if (name.indexOf("window") >= 0 || name.indexOf("workspace") >= 0
                        || name === "changefloatingmode" || name === "fullscreen") refreshDelay.restart();
                }
            }

            // Invisible space stays click-through, including during the exit.
            mask: Region {
                x: 0; y: ShellState.bandH + Appearance.pad
                width: win.available ? 3 : 0
                height: Math.max(0, win.height - ShellState.bandH - 2 * Appearance.pad)
                Region {
                    intersection: Intersection.Combine
                    x: 0; y: Math.floor(rail.y)
                    width: win.revealed ? Math.ceil(rail.width) : 0
                    height: win.revealed ? Math.ceil(rail.height) : 0
                }
            }

            Item {
                id: edge
                x: 0; y: ShellState.bandH + Appearance.pad
                width: 3
                height: Math.max(0, win.height - ShellState.bandH - 2 * Appearance.pad)
                HoverHandler {
                    enabled: win.available
                    onHoveredChanged: {
                        if (hovered) {
                            hideDelay.stop();
                            if (!win.revealed) revealDelay.restart();
                        } else {
                            revealDelay.stop();
                            if (!railHover.hovered) hideDelay.restart();
                        }
                    }
                }
                // Where to push: a thin mark in the wallpaper's accent.
                Rectangle {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    width: 2; height: 32; radius: 1
                    color: Colors.onWallAccent
                    opacity: win.available && !win.revealed ? 0.35 : 0
                    Behavior on opacity { NumberAnimation { duration: Appearance.mIn } }
                }
            }

            // A shade from the edge, so the stacks read over whatever window is
            // behind them, the way a floating thing casts a shadow (motion law 2).
            Rectangle {
                anchors.fill: parent
                opacity: win.revealed ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: win.revealed ? Appearance.mIn : Appearance.mOut } }
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0; color: Qt.rgba(0, 0, 0, 0.42) }
                    GradientStop { position: 0.55; color: Qt.rgba(0, 0, 0, 0.18) }
                    GradientStop { position: 1; color: "transparent" }
                }
            }

            Item {
                id: rail
                x: win.revealed ? 0 : -width
                y: ShellState.bandH + Math.max(Appearance.pad, (win.height - ShellState.bandH - height) / 2)
                width: win.width
                height: Math.min(win.height - ShellState.bandH - 2 * Appearance.pad,
                    desktopList.contentHeight + win.chipsHeight + Appearance.gapL)
                opacity: win.revealed ? 1 : 0
                // `apple` coming in and `sale` going out (motion-language.md): a
                // displacement never overshoots, it would show the screen's edge.
                Behavior on x {
                    NumberAnimation {
                        duration: win.revealed ? Appearance.mInScale : Appearance.mOutScale
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: win.revealed ? [0.32, 0.72, 0, 1, 1, 1] : [0.3, 0, 1, 1, 1, 1]
                    }
                }
                Behavior on opacity { NumberAnimation { duration: win.revealed ? Appearance.mIn : Appearance.mOut } }

                HoverHandler {
                    id: railHover
                    enabled: win.revealed
                    onHoveredChanged: {
                        if (hovered) hideDelay.stop();
                        else hideDelay.restart();
                    }
                }

                ListView {
                    id: desktopList
                    x: 0; y: Appearance.gapM
                    width: parent.width
                    height: Math.max(0, parent.height - win.chipsHeight - Appearance.gapM)
                    clip: true
                    spacing: 2
                    interactive: contentHeight > height
                    boundsBehavior: Flickable.StopAtBounds
                    model: ScriptModel { values: win.workspaces }
                    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded; width: 3 }
                    delegate: StageWorkspace {
                        required property var modelData
                        workspace: modelData
                        cardWidth: win.cardWidth
                        slotHeight: win.slotHeight
                        vanishingY: win.height / 2 - rail.y - desktopList.y - y + desktopList.contentY
                        width: desktopList.width
                        live: (win.revealed || rail.opacity > 0) && y + height > desktopList.contentY
                            && y < desktopList.contentY + desktopList.height
                        onChosen: ws => win.choose(ws)
                    }
                }

                // The empty workspaces, as the bar counts them: just their number,
                // in the clock's face.
                Flickable {
                    x: Appearance.pad; y: parent.height - win.chipSize - Appearance.gapS
                    width: parent.width - 2 * Appearance.pad; height: win.chipSize
                    visible: win.emptyWorkspaces.length > 0
                    contentWidth: emptyRow.implicitWidth
                    contentHeight: height
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    Row {
                        id: emptyRow
                        spacing: Appearance.gapS
                        Repeater {
                            model: ScriptModel { values: win.emptyWorkspaces }
                            Rectangle {
                                id: chip
                                required property var modelData
                                width: win.chipSize; height: win.chipSize
                                radius: Appearance.radS
                                color: emptyMouse.containsMouse ? Colors.fill2 : Colors.fill3
                                border.width: 1
                                border.color: Colors.hairline
                                Behavior on color { ColorAnimation { duration: Appearance.mQuick } }
                                StyledText {
                                    readonly property int px: Appearance.clockPixelSize(Appearance.fsS)
                                    anchors.centerIn: parent
                                    anchors.verticalCenterOffset: Appearance.clockNudge(px)
                                    text: chip.modelData.id
                                    font.family: Appearance.fontClock
                                    font.pixelSize: px
                                    color: emptyMouse.containsMouse ? Colors.label : Colors.label2
                                }
                                MouseArea {
                                    id: emptyMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: win.choose(chip.modelData.id)
                                }
                                ToolTip.visible: emptyMouse.containsMouse
                                ToolTip.text: I18n.tr("Escritorio vacío {0}", chip.modelData.id)
                                ToolTip.delay: 600
                            }
                        }
                    }
                }
            }
        }
    }
}
