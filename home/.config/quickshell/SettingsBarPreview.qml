// ╭──────────────────────────────────────────────────────────────────────────╮
// │                                                                          │
// │   B A R   P R E V I E W                                                  │
// │   the bar's style, drawn small                                           │
// │                                                                          │
// │   github.com/andreumassanet/impasto                                      │
// │                                                                          │
// ╰──────────────────────────────────────────────────────────────────────────╯

// Live settings miniature, adapted from Impasto's components/BarPreview.qml.
// https://github.com/andreumassanet/impasto — Copyright 2026 Andreu Massanet.
// GPL-3.0. Draws Diego's bar and notch using his current appearance settings.
import QtQuick
import QtQuick.Shapes
import Quickshell.Widgets

Item {
    id: root
    property var values: Config
    property bool attached: values.notchStyle === "notch"
    property bool compact: false
    implicitWidth: 270
    implicitHeight: 112

    ClippingRectangle {
        id: screen
        anchors { fill: parent; margins: root.compact ? 6 : 0 }
        radius: root.compact ? 7 : Appearance.radM
        color: Colors.bg
        border.color: Colors.hairline
        border.width: 1

        Image {
            anchors.fill: parent
            source: Colors.wallpaper
            sourceSize: Qt.size(640, 180)
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            opacity: 0.65
        }
        Rectangle {
            anchors { left: parent.left; right: parent.right; top: parent.top }
            height: root.compact ? 12 : root.values.bandH
            color: Qt.rgba(0, 0, 0, root.values.scrimAlpha)
        }
        Row {
            x: root.compact ? 8 : root.values.sideMargin
            y: root.compact ? 5 : (root.values.bandH - height) / 2
            spacing: root.compact ? 2 : 6
            Text {
                visible: root.values.showArch && !root.compact
                text: "󰣇"
                color: Colors.label
                font.family: Appearance.font
                font.pixelSize: 14
            }
            Repeater {
                model: root.values.showWorkspaces ? 3 : 0
                Rectangle {
                    required property int index
                    width: index === 0 ? (root.compact ? 9 : 20) : (root.compact ? 3 : 5)
                    height: root.compact ? 3 : 5
                    y: root.compact ? 1 : 6
                    radius: height / 2
                    // The two tokens the real indicator uses (TopShell.qml):
                    // the inactive dot cannot be lighter than the active pill,
                    // and with a fixed grey it was.
                    color: index === 0 ? Colors.onWallAccent : Colors.onWallDim
                }
            }
            Text {
                visible: root.values.showAppName && !root.compact
                text: I18n.tr("Ajustes")
                color: Colors.label
                font { family: Appearance.fontUI; pixelSize: Appearance.fsXS }
            }
        }
        Text {
            anchors.right: parent.right
            anchors.rightMargin: root.compact ? 8 : root.values.sideMargin
            y: root.compact ? 4 : (root.values.bandH - height) / 2
            text: root.compact ? "•••" : (root.values.showTray ? "󰕾  󰖩  󰂯  󰁹" : "󰕾  󰖩  󰁹")
            color: Colors.label
            font { family: Appearance.font; pixelSize: root.compact ? 7 : Appearance.fsM }
        }
        Item {
            id: notch
            anchors.horizontalCenter: parent.horizontalCenter
            y: root.attached ? 0 : (root.compact ? 4 : root.values.islandGap)
            readonly property real fl: root.compact ? 3 : root.values.flare
            readonly property real bodyWidth: root.compact ? 32 : Math.min(screen.width * 0.55,
                root.values.idleW + (root.values.showDate ? 62 : 0) + (root.values.showBattery ? 36 : 0))
            width: bodyWidth + (root.attached ? 2 * fl : 0)
            height: root.compact ? 12 : root.values.bandH
            readonly property real rb: Math.max(2, Math.min(root.values.roundMax, height - fl - 1))
            Rectangle {
                anchors.fill: parent
                visible: !root.attached
                radius: Math.min(root.values.roundMax, height / 2)
                color: Colors.notchTint(root.values.notchColor)
            }
            Shape {
                anchors.fill: parent
                visible: root.attached
                preferredRendererType: Shape.CurveRenderer
                antialiasing: true
                ShapePath {
                    id: path
                    fillColor: Colors.notchTint(root.values.notchColor)
                    strokeColor: "transparent"
                    strokeWidth: 0
                    readonly property real f: notch.fl
                    readonly property real r: notch.rb
                    readonly property real w: notch.bodyWidth
                    readonly property real h: notch.height
                    startX: 0; startY: 0
                    PathCubic { control1X: path.f * 0.552; control1Y: 0; control2X: path.f; control2Y: path.f * 0.448; x: path.f; y: path.f }
                    PathLine { x: path.f; y: path.h - path.r }
                    PathCubic { control1X: path.f; control1Y: path.h - path.r * 0.448; control2X: path.f + path.r * 0.448; control2Y: path.h; x: path.f + path.r; y: path.h }
                    PathLine { x: path.f + path.w - path.r; y: path.h }
                    PathCubic { control1X: path.f + path.w - path.r * 0.448; control1Y: path.h; control2X: path.f + path.w; control2Y: path.h - path.r * 0.448; x: path.f + path.w; y: path.h - path.r }
                    PathLine { x: path.f + path.w; y: path.f }
                    PathCubic { control1X: path.f + path.w; control1Y: path.f * 0.448; control2X: path.f + path.w + path.f * 0.552; control2Y: 0; x: path.w + 2 * path.f; y: 0 }
                    PathLine { x: 0; y: 0 }
                }
            }
            Text {
                anchors.centerIn: parent
                text: root.compact ? "12:34" : (root.values.showDate ? "12:34 · 12/09" : "12:34")
                    + (root.values.showBattery ? "  85%" : "")
                color: Colors.label
                // THE PREVIEW HAS TO DRAW WHAT THE CLOCK DRAWS.
                //
                // The clock had been reimplemented here by hand: fontUI instead
                // of fontClock, and clockSize raw instead of going through
                // Appearance.clockPixelSize() as NotchContent.qml:96-97 does.
                // So the preview grew smoothly from 12 to 24 in a different
                // typeface while the real clock only moved in two steps. The
                // very contract the caption below promises, "los cambios se
                // aplican al instante" (changes apply instantly).
                font {
                    family: Appearance.fontClock
                    pixelSize: root.compact ? 6 : Appearance.clockPixelSize(root.values.clockSize)
                    weight: Font.Medium
                }
            }
        }
        // The caption sits on the real WALLPAPER, which can be anything. It
        // was solved with `style: Text.Outline` and a black outline at 40%,
        // and with this wallpaper -- a light sky -- that was not enough: the
        // white text got lost among the clouds.
        //
        // The HIG advise against exactly that: "In general, avoid adding depth
        // to text. Text that appears to hover above its background is difficult
        // to read" (spatial-layout.md), and an outline is fake depth; all it
        // does is muddy the letterforms. The recipe for text over rich
        // content is a dimming layer behind it: "If the underlying content is
        // bright, consider adding a dark dimming layer of 35% opacity"
        // (materials.md).
        //
        // It is a gradient and not a block so it does not read as a stuck-on
        // band: at the top it does not exist, at the bottom it reaches the 35%
        // the page asks for.
        Rectangle {
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
            height: 34
            visible: !root.compact
            gradient: Gradient {
                GradientStop { position: 0.0; color: "#00000000" }
                GradientStop { position: 1.0; color: "#59000000" }
            }
        }

        Text {
            anchors { left: parent.left; bottom: parent.bottom; margins: 12 }
            visible: !root.compact
            text: I18n.tr("Vista previa · los cambios se aplican al instante")
            // Fixed white on purpose, not `Colors.label`: what lies behind is
            // the dimmed wallpaper, not the theme's surface, so the theme's ink
            // guarantees nothing here. With the dimming behind it, white does.
            color: "#ffffff"
            font { family: Appearance.fontUI; pixelSize: Appearance.fsXS }
        }
    }
}
