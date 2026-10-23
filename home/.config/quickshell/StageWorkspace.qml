// A workspace is a stack of its real windows, not a framed picture of the
// desktop: in front the one you used last, up to two more behind it.
pragma ComponentBehavior: Bound
import Quickshell
import Quickshell.Hyprland
import QtQuick
import QtQuick.Controls

Item {
    id: root
    required property var workspace
    property bool live: false
    property real cardWidth: 224
    property real slotHeight: 157
    property real vanishingY: height / 2
    signal chosen(int workspaceId)

    readonly property var windows: [...Hyprland.toplevels.values].filter(t =>
        t.workspace && root.workspace && t.workspace.id === root.workspace.id && t.wayland)
        .sort((a, b) => {
            const ca = a.lastIpcObject, cb = b.lastIpcObject;
            return (ca ? ca.focusHistoryID : 999) - (cb ? cb.focusHistoryID : 999);
        }).slice(0, 3)
    readonly property var front: windows.length > 0 ? windows[0] : null
    readonly property var frontClient: front ? front.lastIpcObject : null
    readonly property var frontSize: frontClient && frontClient.size ? frontClient.size : [1600, 900]
    readonly property real planeHeight: slotHeight - Appearance.gapL
    readonly property real windowScale: Math.min(cardWidth / Math.max(1, frontSize[0]),
        planeHeight / Math.max(1, frontSize[1]))
    readonly property string frontClass: frontClient ? (frontClient["class"] || frontClient.initialClass || "") : ""
    readonly property var app: DesktopEntries.heuristicLookup(frontClass)
    readonly property string appName: app ? app.name : frontClass
    // A window with a class of its own (kitty --class yazi-rice, rice-cava…) has
    // no desktop entry, and the generic icon is not in the theme either: it came
    // out as the missing-icon checkerboard. On this desktop such a window is a
    // kitty almost every time, so that is the icon it gets.
    readonly property string appIcon: Quickshell.iconPath(app ? app.icon : "kitty",
        "application-x-executable")
    readonly property bool hovered: pointer.containsMouse
    // Turned away at rest, towards you under the pointer: the stack comes
    // forward into the light instead of getting an outline (motion law 2).
    property real yaw: hovered ? 26 : 46
    Behavior on yaw { NumberAnimation { duration: Appearance.mIn; easing.type: Easing.OutCubic } }

    implicitWidth: cardWidth
    implicitHeight: slotHeight

    Repeater {
        model: ScriptModel { values: root.windows }
        StageThumbnail {
            required property var modelData
            required property int index
            readonly property var clientData: modelData.lastIpcObject
            readonly property var dimensions: clientData && clientData.size ? clientData.size : [1600, 900]
            width: Math.max(16, Math.min(root.cardWidth, dimensions[0] * root.windowScale))
            height: Math.max(16, Math.min(root.planeHeight, dimensions[1] * root.windowScale))
            x: (root.hovered ? 14 : 8) + index * (root.hovered ? 16 : 10)
            y: (root.height - height) / 2 - index * 8
            z: 10 - index
            toplevel: modelData
            live: root.live
            yaw: root.yaw + index * 4
            vanishingY: root.vanishingY - y
            // The ones behind sink, the way unfocused windows do on the desktop.
            opacity: index === 0 ? 1 : (root.hovered ? 0.92 : 0.8) - (index - 1) * 0.12
            Behavior on x { NumberAnimation { duration: Appearance.mIn; easing.type: Easing.OutCubic } }
            Behavior on opacity { NumberAnimation { duration: Appearance.mQuick } }
        }
    }

    // The app's icon faces you, as on Apple's stacks. Beside it, the workspace
    // number is a little notch: the pocket's colour and the clock's face.
    Image {
        id: icon
        x: 0
        y: (root.height + Math.min(root.planeHeight, root.frontSize[1] * root.windowScale)) / 2 - height + 8
        z: 20
        width: 32; height: 32
        source: root.appIcon
        sourceSize: Qt.size(64, 64)
        mipmap: true
    }
    Rectangle {
        anchors.left: icon.right
        anchors.leftMargin: -3
        anchors.verticalCenter: icon.verticalCenter
        anchors.verticalCenterOffset: 3
        z: 21
        width: number.implicitWidth + 2 * Appearance.gapS
        height: 22
        radius: height / 2
        color: Colors.notchTint(Config.notchColor)
        border.width: 1
        border.color: Colors.hairline
        StyledText {
            id: number
            readonly property int px: Appearance.clockPixelSize(Appearance.fsS)
            anchors.centerIn: parent
            anchors.verticalCenterOffset: Appearance.clockNudge(px)
            text: root.workspace ? root.workspace.id : ""
            font.family: Appearance.fontClock
            font.pixelSize: px
            color: Colors.label
        }
    }

    MouseArea {
        id: pointer
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: if (root.workspace) root.chosen(root.workspace.id)
    }
    ToolTip.visible: hovered
    ToolTip.delay: 650
    ToolTip.text: I18n.tr("Escritorio {0}", workspace ? workspace.id : "") + " · " + appName
}
