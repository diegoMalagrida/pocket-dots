// Each real window is its own plane, including its shadow and perspective.
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import QtQuick
import QtQuick.Effects

Item {
    id: root
    required property var toplevel
    property bool live: false
    property real yaw: 52
    // All planes share the display's centre as their vanishing point.
    property real vanishingY: height / 2
    property real cameraDistance: 1600
    readonly property var client: toplevel ? toplevel.lastIpcObject : null
    readonly property string appId: client ? (client["class"] || client.initialClass || "") : ""
    readonly property string icon: {
        const entry = DesktopEntries.heuristicLookup(appId);
        // No desktop entry: a kitty with its own --class (see StageWorkspace).
        return Quickshell.iconPath(entry ? entry.icon : "kitty", "application-x-executable");
    }

    transform: Rotation {
        origin.x: 0
        origin.y: root.vanishingY
        axis { x: 0; y: 1; z: 0 }
        angle: root.yaw
        distanceToPlane: root.cameraDistance
    }

    // The shadow surrounds the clipped window instead of being clipped by it.
    Item {
        anchors.fill: parent
        layer.enabled: root.live
        layer.smooth: true
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: "#000000"
            shadowOpacity: 0.65
            shadowBlur: 0.8
            shadowHorizontalOffset: 7
            shadowVerticalOffset: 10
            autoPaddingEnabled: true
        }
        ClippingRectangle {
            anchors.fill: parent
            // A window that touches no edge, as the workspace map draws it
            // (OverviewWindow's radMin).
            radius: 7
            color: Colors.surface2
            antialiasing: true
            contentUnderBorder: true
            border.width: 1
            // A dark window would sink into whatever is behind it: the plane keeps
            // a lit edge, and the light comes from the top left like everything else.
            border.color: Qt.rgba(Colors.fg.r, Colors.fg.g, Colors.fg.b, 0.20)
            ScreencopyView {
                id: capture
                anchors.fill: parent
                captureSource: root.live && root.toplevel ? root.toplevel.wayland : null
                live: root.live
                // Supersampling keeps text clean after the perspective transform.
                constraintSize: Qt.size(Math.max(1, Math.round(root.width * 1.5)),
                    Math.max(1, Math.round(root.height * 1.5)))
            }
            Image {
                anchors.centerIn: parent
                width: Math.min(32, parent.width * 0.4)
                height: width
                sourceSize: Qt.size(32, 32)
                source: root.icon
                visible: !capture.hasContent
            }
            // The side turned away is in shade, the near edge catches the light.
            Rectangle {
                anchors.fill: parent
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0; color: Qt.rgba(1, 1, 1, 0.07) }
                    GradientStop { position: 0.35; color: "transparent" }
                    GradientStop { position: 1; color: Qt.rgba(0, 0, 0, 0.16) }
                }
            }
        }
    }
}
