// WallpaperPicker.qml — ilyamiro coverflow (parallelogram / skew cards)
// over an IMMERSIVE BACKGROUND: the selected wallpaper, blurred and darkened,
// fills the screen and crossfades as you navigate. That way the picker does not
// fight with whatever desktop/terminal is behind it and the cards stand out
// cleanly.
//
// Maximum-smoothness engine: each SLOT has a FIXED WIDTH (zero relayout when
// scrolling) and the card, of FIXED SIZE, is only animated with
// `scale`+`opacity` (a continuous function of its distance to the centre). No
// Behaviors that drift out of sync, no re-decoding and NO shadow layers per
// card (that killed performance). The inner image has a fixed size and always
// covers the parallelogram -> never any clipped corners.
//
// The cards do NOT read the original wallpapers but the 500 px thumbnails that
// scripts/wall-thumbs.sh keeps in ~/.cache/wallpaper-thumbs: decoding the
// originals (up to 6 MB) to paint a small card cost ~12x more.
// Each thumbnail keeps the full name of the original plus ".jpg", so the real
// path is recovered by dropping that suffix (see originalOf).
//
// Contract kept: GlobalShortcut "wallpaper" and the set-wallpaper.sh script.
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Io
import QtQuick
import QtQuick.Effects
import Qt.labs.folderlistmodel

Scope {
    id: root
    property bool open: false
    readonly property string home: Quickshell.env("HOME")
    readonly property string wallsDir:  home + "/Pictures/wallpapers"
    readonly property string thumbsDir: home + "/.cache/wallpaper-thumbs"

    // "anime-9o9yw1.jpg.jpg" -> "~/Pictures/wallpapers/anime-9o9yw1.jpg"
    function originalOf(thumbName) { return root.wallsDir + "/" + String(thumbName).replace(/\.jpg$/, "") }
    function apply(thumbName) {
        Quickshell.execDetached([root.home + "/.config/hypr/set-wallpaper.sh", root.originalOf(thumbName)])
        root.open = false
    }

    // Refreshes the thumbnail cache: when the shell starts and every time the
    // picker opens. Warm it takes ~30 ms (it only checks dates).
    Process {
        id: thumbsProc
        command: ["bash", root.home + "/.config/quickshell/scripts/wall-thumbs.sh"]
        onExited: {
            // If the cache did not exist yet, the model's watcher never sees it
            // being born and it has to be re-pointed by hand once.
            if (wallModel.count === 0) { wallModel.folder = ""; wallModel.folder = "file://" + root.thumbsDir }
        }
    }
    function refreshThumbs() { thumbsProc.running = false; thumbsProc.running = true }
    Component.onCompleted: root.refreshThumbs()

    GlobalShortcut { name: "wallpaper"; description: "Wallpaper picker"; onPressed: root.open = !root.open }
    HyprlandFocusGrab { windows: [win]; active: root.open; onCleared: root.open = false }

    FolderListModel {
        id: wallModel
        folder: "file://" + root.thumbsDir
        nameFilters: ["*.jpg"]
        showDirs: false
        sortField: FolderListModel.Name
    }

    PanelWindow {
        id: win
        // Only on the screen you are looking at, not always on the first one.
        screen: ShellState.focusedScreen
        // Mapped until the fade-out finishes: with visible bound only to open,
        // the window was unmapped in the same frame and the closing animation
        // was never seen (the no_anim in hyprland.lua relies on this stage
        // fading out by itself).
        visible: root.open || stage.opacity > 0
        anchors { top: true; bottom: true; left: true; right: true }
        exclusiveZone: 0
        color: "transparent"
        WlrLayershell.layer: WlrLayer.Overlay
        // Exclusive only while it is open: during the ~110 ms of the fade-out
        // the window is still mapped and must not hold on to anything.
        WlrLayershell.keyboardFocus: root.open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
        // Without a namespace no layerrule is possible: it is the handle by which
        // Hyprland animates THIS surface and not all of them alike.
        WlrLayershell.namespace: "quickshell:wallpaper"

        Item {
            id: stage
            anchors.fill: parent
            focus: true
            opacity: root.open ? 1 : 0
            // In 210/OutCubic; out 110 ms (mOut) with InCubic, which is the
            // `sale` (exit) curve: it accelerates and does not brake. Law 3: what
            // leaves goes in half the time.
            Behavior on opacity { NumberAnimation { duration: root.open ? Appearance.animMed : Appearance.mOut; easing.type: root.open ? Easing.OutCubic : Easing.InCubic } }

            Connections {
                target: root
                function onOpenChanged() {
                    if (!root.open) return
                    stage.forceActiveFocus()
                    root.refreshThumbs()
                }
            }

            Keys.onEscapePressed: root.open = false
            Keys.onLeftPressed:   carousel.decrementCurrentIndex()
            Keys.onRightPressed:  carousel.incrementCurrentIndex()
            Keys.onReturnPressed: carousel.applyCurrent()
            Keys.onEnterPressed:  carousel.applyCurrent()
            WheelHandler {
                onWheel: (e) => {
                    if (e.angleDelta.y > 0 || e.angleDelta.x > 0) carousel.decrementCurrentIndex()
                    else carousel.incrementCurrentIndex()
                }
            }

            // NO BACKGROUND: the picker floats transparent over the desktop (no
            // blurred wallpaper and no veil). The cards are opaque and the chrome
            // carries a shadow halo so it reads over any background.
            // A click on an empty area closes it.
            MouseArea { anchors.fill: parent; z: -1; onClicked: root.open = false }

            // ----- ilyamiro coverflow (parallelogram / skew cards) -----
            ListView {
                id: carousel
                anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; verticalCenterOffset: 12 }
                height: 560
                orientation: ListView.Horizontal
                model: wallModel
                property real iw: 720                            // base width of the hero (fixed)
                property real ih: 406                            // base height of the hero (~16:9, fixed)
                property real skew: -0.35
                property real bw: 3
                property real slotW: 360                         // FIXED scroll step
                property real sideBase: 0.56                     // scale of the 1st neighbour
                readonly property real imgW: iw + ih * Math.abs(skew) + 12
                spacing: 0; clip: false; cacheBuffer: 2500
                highlightRangeMode: ListView.StrictlyEnforceRange
                preferredHighlightBegin: (width - slotW) / 2
                preferredHighlightEnd:   (width + slotW) / 2
                highlightMoveDuration: 420
                highlightMoveVelocity: 3000
                snapMode: ListView.SnapToItem
                boundsBehavior: Flickable.StopAtBounds
                maximumFlickVelocity: 6000

                function applyCurrent() {
                    if (currentIndex < 0 || wallModel.count <= currentIndex) return
                    root.apply(wallModel.get(currentIndex, "fileName"))
                }

                delegate: Item {
                    id: slot
                    width: carousel.slotW
                    height: carousel.height
                    // continuous distance to the centre of the viewport, in slots.
                    readonly property real d: (x + width / 2 - (carousel.contentX + carousel.width / 2)) / carousel.slotW
                    readonly property real ad: Math.abs(d)
                    // Scale: 1.0 at the centre (sharp hero at real size) and it falls
                    // smoothly towards the back, symmetric on both sides.
                    readonly property real sc: ad <= 1
                        ? carousel.sideBase + (1 - carousel.sideBase) * Math.pow(1 - ad, 1.35)
                        : carousel.sideBase * Math.pow(0.86, ad - 1)
                    z: Math.round(100 - ad * 10)
                    opacity: Math.max(0, Math.min(1, 1.15 - 0.34 * ad))

                    Item {
                        id: card
                        anchors.centerIn: parent
                        width: carousel.iw
                        height: carousel.ih
                        scale: slot.sc                           // GPU transform only
                        transformOrigin: Item.Center
                        // Shear relative to the vertical CENTRE -> it centres itself.
                        transform: Matrix4x4 { matrix: Qt.matrix4x4(1, carousel.skew, 0, -carousel.skew * carousel.ih / 2,  0, 1, 0, 0,  0, 0, 1, 0,  0, 0, 0, 1) }

                        // Frame: dark base + subtle edge.
                        Rectangle {
                            anchors.fill: parent
                            color: Colors.bg
                            border.width: 1
                            border.color: Colors.hairline
                        }
                        // Straight content (inverse shear) + PreserveAspectCrop.
                        // FIXED size and sourceSize -> it always covers the
                        // parallelogram (no clipped corners) and keeps the same framing.
                        Item {
                            anchors.fill: parent; anchors.margins: carousel.bw; clip: true
                            Image {
                                anchors.centerIn: parent
                                width: carousel.imgW
                                height: carousel.ih
                                fillMode: Image.PreserveAspectCrop
                                source: model.fileUrl
                                asynchronous: true; cache: true; mipmap: true
                                sourceSize: Qt.size(carousel.imgW, carousel.ih)
                                transform: Matrix4x4 { matrix: Qt.matrix4x4(1, -carousel.skew, 0, carousel.skew * carousel.ih / 2,  0, 1, 0, 0,  0, 0, 1, 0,  0, 0, 0, 1) }
                            }
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: slot.ad < 0.5 ? carousel.applyCurrent() : (carousel.currentIndex = index)
                        }
                    }
                }
            }

            // Empty state.
            StyledText {
                anchors.centerIn: parent
                visible: wallModel.count === 0
                text: I18n.tr("No hay wallpapers en {0}", "~/Pictures/wallpapers")
                color: Colors.label
                font.pixelSize: Appearance.fsL
                opacity: 0.85
                layer.enabled: true
                layer.effect: MultiEffect {
                    shadowEnabled: true
                    shadowColor: "#000000"
                    shadowBlur: 1.0
                    blurMax: 16
                    shadowVerticalOffset: 0
                }
            }
        }
    }
}
