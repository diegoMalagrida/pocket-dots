// MediaPanel.qml — vertical player inside the control centre (Super+D).
//
// The composition follows a single column: cover art in the lead role, title
// and artist, progress, controls and the spectrum. That way the player does not
// read as a horizontal card wedged into the control centre, but as a face of
// its own inside the expanded panel.
import QtQuick
import QtQuick.Effects
import QtQuick.Layouts

Item {
    id: root
    readonly property color accent: ShellState.mediaAccent

    // The whole background swallows the click so that a gap between controls
    // never reaches whatever action sits behind the panel.
    MouseArea { anchors.fill: parent }

    ColumnLayout {
        anchors {
            fill: parent
            leftMargin: 22
            rightMargin: 22
            topMargin: 22
            bottomMargin: 18
        }
        spacing: 10

        // ── circular cover art ─────────────────────────────────────────────
        Item {
            id: artStage
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: 166
            Layout.preferredHeight: 166

            // A very faint halo: it adds depth without turning the cover art into a
            // spinning wheel or competing with the visualiser below.
            Rectangle {
                anchors.centerIn: parent
                width: 166; height: 166; radius: 83
                color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.10)
                scale: ShellState.player && ShellState.player.isPlaying ? 1 : 0.94
                opacity: ShellState.player && ShellState.player.isPlaying ? 1 : 0.45
                Behavior on scale { SpringAnimation { spring: Appearance.sprPanel; damping: Appearance.dmpPanel; epsilon: Appearance.eppScale } }
                Behavior on opacity { NumberAnimation { duration: Appearance.mIn; easing.type: Easing.OutCubic } }
                Behavior on color { ColorAnimation { duration: Appearance.mIn; easing.type: Easing.OutCubic } }
            }

            Rectangle {
                anchors.centerIn: parent
                width: 154; height: 154; radius: 77
                color: Colors.surface1
                border.width: 2
                border.color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.72)
                Behavior on border.color { ColorAnimation { duration: Appearance.mIn; easing.type: Easing.OutCubic } }
            }

            Image {
                id: coverImage
                anchors.centerIn: parent
                width: 146; height: 146
                // With no player, the cover art of whatever played last. The file
                // may no longer exist (many players leave it in /tmp), and then the
                // Image never reaches Ready and the usual musical note appears: the
                // fallback was already written.
                source: (ShellState.player && ShellState.player.trackArtUrl)
                    ? ShellState.player.trackArtUrl
                    : ShellState.hayUltimo ? ShellState.ultimoArte : ""
                sourceSize.width: 292
                sourceSize.height: 292
                fillMode: Image.PreserveAspectCrop
                smooth: true
                mipmap: true
                asynchronous: true
                visible: false
            }

            // clip:true crops to a rectangle, even if the parent has a radius.
            // MultiEffect uses this real mask so the cover is a true circle, as
            // in the reference.
            Item {
                id: coverMask
                width: coverImage.width
                height: coverImage.height
                layer.enabled: true
                layer.smooth: true
                visible: false
                Rectangle { anchors.fill: parent; radius: width / 2 }
            }
            MultiEffect {
                anchors.fill: coverImage
                source: coverImage
                visible: coverImage.status === Image.Ready
                // Dimmed when it is a memory and not what is playing: the same
                // distinction the halo and the circle's border already make.
                opacity: ShellState.hayUltimo ? 0.45 : 1
                Behavior on opacity { NumberAnimation { duration: Appearance.mIn; easing.type: Easing.OutCubic } }
                antialiasing: true
                maskEnabled: true
                maskSource: coverMask
                maskSpreadAtMin: 1.0
                maskThresholdMin: 0.5
                maskThresholdMax: 1.0
            }

            Text {
                anchors.centerIn: parent
                visible: coverImage.status !== Image.Ready
                text: "󰎈"
                color: root.accent
                font.family: Appearance.font
                font.pixelSize: 48
                Behavior on color { ColorAnimation { duration: Appearance.mIn; easing.type: Easing.OutCubic } }
            }
        }

        // ── track and artist ──────────────────────────────────────────────
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2

            // The caption only appears when what is shown is NOT playing:
            // without it, the dimmed cover of yesterday's track reads as a
            // stopped player, and the button below would look like a broken play.
            Text {
                Layout.fillWidth: true
                visible: ShellState.hayUltimo
                text: I18n.tr("Lo último que sonó")
                color: Colors.label3
                horizontalAlignment: Text.AlignHCenter
                font.family: Appearance.fontUI
                font.pixelSize: Appearance.fsXXS
            }

            Text {
                Layout.fillWidth: true
                text: ShellState.player
                    ? (ShellState.player.trackTitle || I18n.tr("Sin reproducción"))
                    : ShellState.hayUltimo ? ShellState.ultimoTitulo
                    : I18n.tr("Sin reproducción")
                color: Colors.label
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                lineHeight: Appearance.leading(Appearance.fsL)
                lineHeightMode: Text.FixedHeight
                maximumLineCount: 2
                elide: Text.ElideRight
                font.family: Appearance.fontUI
                font.pixelSize: Appearance.fsL
                font.weight: Font.DemiBold
            }
            Text {
                Layout.fillWidth: true
                text: ShellState.player ? (ShellState.player.trackArtist || "")
                    : ShellState.hayUltimo ? ShellState.ultimoArtista : ""
                color: Colors.label2
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                font.family: Appearance.fontUI
                font.pixelSize: Appearance.fsS
            }
        }

        // ── progress: discreet, but you can click it to seek ──────────────
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 25
            Layout.topMargin: 2

            Rectangle {
                id: seek
                anchors { left: parent.left; right: parent.right; top: parent.top; topMargin: 1 }
                height: 4; radius: 2
                color: Colors.fill1

                Rectangle {
                    // The FRACTION is animated, not the width. The rail measures what
                    // the panel measures, and the panel widens on a spring when the
                    // notch opens: animating the width mixes that widening with the
                    // song's progress and the bar reaches its place half a second
                    // late, as if playback were running at another pace. See the long
                    // explanation in PokeTeamPanel.
                    property real p: ShellState.len > 0
                        ? Math.max(0, Math.min(1, ShellState.pos / ShellState.len)) : 0
                    Behavior on p { NumberAnimation { duration: Appearance.mTick } }

                    height: parent.height
                    radius: parent.radius
                    width: seek.width * p
                    color: root.accent
                    Behavior on color { ColorAnimation { duration: Appearance.mIn; easing.type: Easing.OutCubic } }
                }
                MouseArea {
                    // The grip grows 7 px on each side so that a 4 px rail can be
                    // clicked without aiming. That is fine; what was wrong was
                    // measuring the click against THAT grip.
                    readonly property int agarre: 7

                    anchors.fill: parent
                    anchors.margins: -agarre
                    cursorShape: Qt.PointingHandCursor
                    onClicked: function (m) {
                        if (!ShellState.player || ShellState.len <= 0)
                            return;
                        // MIND THE ORIGIN: HERE THEY ARE NOT THE SAME PLACE.
                        //
                        // Plain `width` resolved on this MouseArea -the rail PLUS
                        // the 14 px of grip- while `m.x` is measured from ITS edge,
                        // 7 px to the left of the real rail. Dividing one by the
                        // other did not just fail at the ends: it put a CONSTANT
                        // offset of ~3% along the whole rail. In an 80-minute
                        // podcast, the leftmost click landed on 2:26, and neither
                        // the start nor the end could be reached. It is measured
                        // against the rail and clamped, which is what
                        // MediaControls.qml:145-150 already got right by having no
                        // margins.
                        const f = Math.max(0, Math.min(1, (m.x - agarre) / seek.width));
                        ShellState.player.position = f * ShellState.len;
                    }
                }
            }

            Text {
                anchors { left: parent.left; bottom: parent.bottom }
                text: ShellState.fmt(ShellState.pos)
                color: Colors.label3
                font.family: Appearance.fontUI
                font.pixelSize: Appearance.fsXXS
                font.features: ({ "tnum": 1 })
            }
            Text {
                anchors { right: parent.right; bottom: parent.bottom }
                text: ShellState.fmt(ShellState.len)
                color: Colors.label3
                font.family: Appearance.fontUI
                font.pixelSize: Appearance.fsXXS
                font.features: ({ "tnum": 1 })
            }
        }

        // ── previous / pause / next ──────────────────────────────────────
        Row {
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredHeight: 52
            spacing: 22

            Repeater {
                model: 3
                Item {
                    id: transport
                    required property int index
                    width: index === 1 ? 52 : 38
                    height: 52

                    // With no player, previous and next have nobody to command.
                    // They dim instead of disappearing: the middle button has to
                    // stay in the same place, and three buttons of which one works
                    // read better than one on its own, off centre. The middle one
                    // does do something -- it reopens the app that was playing --
                    // as long as we know which one it was.
                    readonly property bool util: ShellState.player !== null
                        || (transport.index === 1 && ShellState.ultimaApp !== null)
                    opacity: transport.util ? 1 : 0.3
                    Behavior on opacity { NumberAnimation { duration: Appearance.mIn } }

                    Rectangle {
                        anchors.centerIn: parent
                        visible: transport.index === 1
                        width: 48; height: 48; radius: 24
                        color: transportMa.containsMouse
                            ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.34)
                            : Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.20)
                        scale: transportMa.pressed ? 0.90 : 1
                        Behavior on color { ColorAnimation { duration: Appearance.mQuick; easing.type: Easing.OutQuad } }
                        Behavior on scale { SpringAnimation { spring: Appearance.sprTight; damping: Appearance.dmpTight; epsilon: Appearance.eppScale } }
                    }

                    Text {
                        anchors.centerIn: parent
                        text: transport.index === 0 ? Icons.prev
                            : transport.index === 1
                                ? (ShellState.player && ShellState.player.isPlaying ? Icons.pause : Icons.play)
                                : Icons.next
                        color: transportMa.containsMouse ? root.accent : Colors.label
                        font.family: Appearance.font
                        font.pixelSize: transport.index === 1 ? 24 : 19
                        Behavior on color { ColorAnimation { duration: Appearance.mQuick; easing.type: Easing.OutQuad } }
                    }

                    MouseArea {
                        id: transportMa
                        anchors.fill: parent
                        hoverEnabled: transport.util
                        cursorShape: transport.util ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: {
                            // No player but a last track: play reopens the app
                            // that was playing it. It is not "resume" -- that
                            // does not exist if the program is closed -- but it
                            // is what you want when you press it: back to the
                            // music.
                            if (!ShellState.player) {
                                if (transport.index === 1 && ShellState.ultimaApp)
                                    ShellState.launchApp(ShellState.ultimaApp);
                                return;
                            }
                            if (transport.index === 0) ShellState.player.previous();
                            else if (transport.index === 1)
                                ShellState.player.isPlaying ? ShellState.player.pause() : ShellState.player.play();
                            else ShellState.player.next();
                        }
                    }
                }
            }
        }

        // ── spectrum: the live "illustration" at the foot of the column ──
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumHeight: 58

            Item {
                anchors.centerIn: parent
                width: ShellState.bands * 13 - 7
                height: 58

                Repeater {
                    model: ShellState.bands
                    Rectangle {
                        required property int index
                        x: index * 13
                        width: 6
                        radius: 3
                        antialiasing: true
                        color: root.accent
                        Behavior on color { ColorAnimation { duration: Appearance.mIn; easing.type: Easing.OutCubic } }
                        height: Math.max(6, 58 * (ShellState.levels[index] || 0))
                        y: (58 - height) / 2
                    }
                }
            }
        }
    }
}
