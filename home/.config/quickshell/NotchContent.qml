// NotchContent.qml — what you see INSIDE the notch, depending on the mode.
// It receives the notch's full rectangle (bar strip + bulge); each mode is a
// layer that appears/disappears with opacity, so the morph is done by
// TopShell's shape and the content only cross-fades.
import Quickshell
import QtQuick
import QtQuick.Layouts

Item {
    id: root
    property int barH: 32

    // Overridable ON PURPOSE: TopShell passes it the idle face on the screens
    // that do not have focus. By default, whatever ShellState says.
    property string mode: ShellState.mode

    // ─────────────── idle / media ───────────────
    // Fixed two-pole structure, so nothing jumps when the state changes:
    //   LEFT (always): the clock.
    //   RIGHT (contextual): battery at rest, cover art + peaks with music.
    // The battery is HERE and only here: it left the bar to avoid repeating it.
    NotchLayer {
        anchors.fill: parent
        active: root.mode === "media" || root.mode === "idle"

        // ---- time (+ date if enabled) ----
        // Centred: at rest there is only one piece of data, so anchoring it to
        // a side would leave the notch lopsided. With music it moves left to
        // make room for the cover art and the peaks.
        Row {
            anchors {
                horizontalCenter: parent.horizontalCenter
                horizontalCenterOffset: ShellState.mediaLive ? -52 : 0
                verticalCenter: parent.verticalCenter
            }
            Behavior on anchors.horizontalCenterOffset {
                NumberAnimation { duration: Appearance.mInScale; easing.type: Easing.OutBack; easing.overshoot: Appearance.mInOvershoot }
            }
            spacing: 11

            // Inner row with spacing 0 ON PURPOSE: the gap between the
            // pokemon and the time goes INSIDE the sprite's width, not in the
            // outer row's spacing. If it were left in the spacing, putting on
            // a pokemon would make the time jump a hard 11 px instead of
            // moving along with the sprite as it comes in.
            Row {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 0

                // ---- the pokemon you are wearing ----
                // Only there if 'poke-theme wear' has left something: the rest
                // of the time it measures 0 and is neither seen nor takes room.
                Item {
                    id: pokeSlot
                    anchors.verticalCenter: parent.verticalCenter
                    height: 22
                    width: ShellState.pokeWorn ? pokeSprite.implicitWidth + Appearance.gapM : 0
                    // Without this the row would still reserve its spacing when
                    // there is no pokemon, and the time would be off-centre.
                    visible: width > 0.5
                    clip: true
                    Behavior on width {
                        SpringAnimation {
                            spring: Appearance.sprTight
                            damping: Appearance.dmpTight
                            epsilon: Appearance.eppPx
                        }
                    }

                    AnimatedImage {
                        id: pokeSprite
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        source: ShellState.pokeWornSprite
                        // Decoded straight at the final height: rescaling a 63 px
                        // sprite to 22 on each of its 40 frames costs more and
                        // looks worse.
                        sourceSize.height: 22
                        height: 22
                        fillMode: Image.PreserveAspectFit
                        // Still when not visible: there is no point decoding
                        // frames for nobody.
                        playing: pokeSlot.visible
                        opacity: ShellState.pokeWorn ? 1 : 0
                        Behavior on opacity {
                            NumberAnimation { duration: Appearance.mIn; easing.type: Easing.OutCubic }
                        }
                    }
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.verticalCenterOffset: Appearance.clockNudge(Config.clockSize)
                    text: Qt.formatDateTime(ShellState.now, "HH:mm")
                    color: Colors.label
                    font.family: Appearance.fontClock
                    font.pixelSize: Appearance.clockPixelSize(Config.clockSize)
                    font.weight: Font.DemiBold
                    font.features: ({ "tnum": 1 })   // fixed-width digits: no jitter when the minute changes
                }
            }

            Column {
                anchors.verticalCenter: parent.verticalCenter
                // fade instead of popping in/out abruptly when music starts
                opacity: (Config.showDate && !ShellState.mediaLive) ? 1 : 0
                visible: opacity > 0.01
                Behavior on opacity { NumberAnimation { duration: Appearance.mIn; easing.type: Easing.OutCubic } }
                spacing: 0
                Text {
                    height: 12
                    verticalAlignment: Text.AlignVCenter
                    text: ShellState.capitalize(ShellState.now.toLocaleDateString(ShellState.loc, "dddd"))
                    color: Colors.label
                    font.family: Appearance.fontUI
                    font.pixelSize: Appearance.fsXXS
                    font.weight: Font.Medium
                }
                Text {
                    height: 12
                    verticalAlignment: Text.AlignVCenter
                    text: ShellState.now.toLocaleDateString(ShellState.loc, I18n.tr("d 'de' MMMM"))
                    color: Colors.label2
                    font.family: Appearance.fontUI
                    font.pixelSize: Appearance.fsXXS
                }
            }
        }

        // ---- right pole at rest: battery ----
        Row {
            anchors { right: parent.right; rightMargin: 15; verticalCenter: parent.verticalCenter }
            spacing: 6
            opacity: (Config.showBattery && !ShellState.mediaLive && ShellState.batt >= 0) ? 1 : 0
            visible: opacity > 0.01
            Behavior on opacity { NumberAnimation { duration: Appearance.mIn; easing.type: Easing.OutCubic } }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: ShellState.battIcon
                color: ShellState.ac ? Colors.ok
                    : ShellState.batt < 15 ? Colors.crit
                    : ShellState.batt < 30 ? Colors.warn : Colors.label
                font.family: Appearance.font; font.pixelSize: Appearance.fsM
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: ShellState.batt + "%"
                color: ShellState.ac ? Colors.ok
                    : ShellState.batt < 15 ? Colors.crit
                    : ShellState.batt < 30 ? Colors.warn : Colors.label
                font.family: Appearance.fontUI
                font.pixelSize: Appearance.fsXS
                font.weight: Font.Medium
                font.features: ({ "tnum": 1 })   // the % must not change width as the charge drops
            }
        }

        // ---- right pole with music: cover art + peaks ----
        Row {
            anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
            spacing: 9
            opacity: ShellState.mediaLive ? 1 : 0
            visible: opacity > 0.01
            Behavior on opacity { NumberAnimation { duration: Appearance.mIn; easing.type: Easing.OutCubic } }

            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: 22; height: 22; radius: 7
                color: Colors.fill3
                clip: true
                Image {
                    anchors.fill: parent
                    source: (ShellState.player && ShellState.player.trackArtUrl) ? ShellState.player.trackArtUrl : ""
                    fillMode: Image.PreserveAspectCrop
                    // Without sourceSize the cover art is decoded at its native
                    // resolution (600-1000 px) to paint 22-34 px; 64 is plenty.
                    sourceSize.width: 64
                    visible: status === Image.Ready
                }
                Text {
                    anchors.centerIn: parent
                    visible: !(ShellState.player && ShellState.player.trackArtUrl)
                    text: Icons.play; color: ShellState.mediaAccent
                    font.family: Appearance.font; font.pixelSize: Appearance.fsXS
                    Behavior on color { ColorAnimation { duration: Appearance.mIn; easing.type: Easing.OutCubic } }
                }
            }

            // THE BARS' BOX IS FIXED, not a Row that sizes itself.
            //
            // With a Row, the Row's height is that of its tallest child, and
            // each bar was centred on that Row. In other words: every time the
            // tallest bar changed, the box changed, and with it the vertical
            // position of ALL EIGHT at once. A kick drum hit moved the whole
            // strip, not just its bar — the collective tremor you could see on
            // top of each bar's own movement.
            //
            // Here the box is 18 px no matter what, and each bar lives in its
            // slot: 4 wide + 4 gap = 8 px pitch. One bar cannot move its
            // neighbours.
            Item {
                anchors.verticalCenter: parent.verticalCenter
                width: ShellState.bands * 8 - 4
                height: 18

                Repeater {
                    // One bar per cava band: bass on the left, treble on the
                    // right. No Behavior, and it has been tested that this is
                    // right: the motion is already carried by ShellState's
                    // per-frame follower; an animation here restarts with
                    // every sample, never finishes, and only adds judder.
                    model: ShellState.bands
                    Rectangle {
                        required property int index
                        x: index * 8
                        width: 4; radius: 2
                        color: ShellState.mediaAccent
                        Behavior on color { ColorAnimation { duration: Appearance.mIn; easing.type: Easing.OutCubic } }

                        // CONTINUOUS HEIGHT, WITH DECIMALS. There was once a
                        // rounding to whole pixels here with 0.7 px hysteresis,
                        // and it was exactly what kept this from being smooth:
                        // over a travel of only 14 px (4→18) that leaves fifteen
                        // possible heights, so the bar stayed STILL and then
                        // JUMPED 7% of its travel all at once. On top of that,
                        // being centred, each jump flipped the parity of the
                        // height and with it the subpixel split of the rounded
                        // caps: the bar alternated between sharp and blurry on
                        // every step. That is literally the flicker.
                        //
                        // (It is measured and noted in scripts/cava.conf:
                        // quantising left the visualiser MORE static, 2.6 px/s
                        // against 4.4. The rounding crept in after that test.)
                        //
                        // A Rectangle with radius is drawn antialiased, so it
                        // can paint half a pixel: the edge is split across two
                        // rows. That is NOT flicker, it is exactly the
                        // mechanism by which a screen shows motion finer than
                        // its own grid. What flickered was the step, not the
                        // decimal.
                        antialiasing: true
                        // The floor is the width: at rest each bar is a round
                        // dot, not a squashed pill.
                        height: Math.max(4, 18 * (ShellState.levels[index] || 0))
                        // It grows both ways from the centre of the box, which
                        // is a constant: the reference never moves.
                        y: (18 - height) / 2
                    }
                }
            }
        }
    }

    // ─────────────── peek (hover): the idle clock, in more detail ───────────────
    // Same centred row as in idle, but the date is written out in full and the
    // battery is added: on hover, the clock "unfolds".
    NotchLayer {
        anchors.fill: parent
        active: root.mode === "peek"

        // Centred just as at rest: on hover the group grows and re-centres,
        // instead of jumping from one anchor to another.
        Row {
            anchors {
                horizontalCenter: parent.horizontalCenter
                horizontalCenterOffset: -26
                verticalCenter: parent.verticalCenter
            }
            spacing: 13

            // THE PEEK CLOCK FOLLOWS THE SETTING, NOT THE OTHER WAY ROUND.
            //
            // It was pinned at 21 while the idle one uses Config.clockSize,
            // which is 17 by default. So the peek was 4 px bigger, and that is
            // fine -- what was wrong is that it was a fixed number: if you
            // raise the clock size in Settings above 21, on hover it SHRINKS,
            // which is exactly the opposite of what a peek does.
            // Now the +4 step holds whatever the size is.
            readonly property int pxPeek: Config.clockSize + 4

            Text {
                anchors.verticalCenter: parent.verticalCenter
                anchors.verticalCenterOffset: Appearance.clockNudge(parent.pxPeek)
                text: Qt.formatDateTime(ShellState.now, "HH:mm")
                color: Colors.label
                font.family: Appearance.fontClock
                font.pixelSize: Appearance.clockPixelSize(parent.pxPeek)
                font.weight: Font.DemiBold
                font.features: ({ "tnum": 1 })
            }

            Column {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 0
                Text {
                    height: 14
                    verticalAlignment: Text.AlignVCenter
                    text: ShellState.capitalize(ShellState.now.toLocaleDateString(ShellState.loc, "dddd"))
                    color: Colors.label
                    font.family: Appearance.fontUI
                    font.pixelSize: Appearance.fsXS
                    font.weight: Font.Medium
                }
                Text {
                    height: 14
                    verticalAlignment: Text.AlignVCenter
                    text: ShellState.now.toLocaleDateString(ShellState.loc, I18n.tr("d 'de' MMMM 'de' yyyy"))
                    color: Colors.label2
                    font.family: Appearance.fontUI
                    font.pixelSize: Appearance.fsXS
                }
            }
        }

        Row {
            anchors { right: parent.right; rightMargin: 15; verticalCenter: parent.verticalCenter }
            spacing: 6
            visible: ShellState.batt >= 0
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: ShellState.battIcon
                color: ShellState.ac ? Colors.ok
                    : ShellState.batt < 15 ? Colors.crit
                    : ShellState.batt < 30 ? Colors.warn : Colors.label
                font.family: Appearance.font; font.pixelSize: Appearance.fsL
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: ShellState.batt + "%"
                color: ShellState.ac ? Colors.ok
                    : ShellState.batt < 15 ? Colors.crit
                    : ShellState.batt < 30 ? Colors.warn : Colors.label
                font.family: Appearance.fontUI
                font.pixelSize: Appearance.fsS
                font.weight: Font.Medium
                font.features: ({ "tnum": 1 })
            }
        }
    }

    // ─────────────── activity: volume / brightness OSD ───────────────
    NotchLayer {
        id: osd
        anchors.fill: parent
        active: root.mode === "activity"

        readonly property bool isVol: ShellState.activity === "volume"
        // THE LEVEL IS NOT FAKED: THE ICON ALREADY SAYS IT IS MUTED.
        //
        // This was `muted ? 0 : vol`, and raising the volume does NOT unmute
        // (hyprland.lua:627 and :629 are different keys). So with the sound
        // muted you pressed up, the OSD showed 0%, you pressed again, 0%, and
        // on unmuting you got slapped at 140%. The mute icon was already right
        // here below, so this notice never lied about the mute: it lied about
        // the LEVEL, which is the only thing there is to show. It is what
        // impasto's OsdService.qml:51-58 documents.
        //
        // In the sliders (SettingsAudio.qml:123, ControlPanel.qml:50) the
        // `muted ? 0 : vol` stays, and rightly so: moving them calls
        // setVolume(), which unmutes. Here there is nothing to move.
        readonly property int value: isVol ? ShellState.vol : Math.max(0, ShellState.bright)
        readonly property bool callado: isVol && ShellState.muted
        // same reason: the notch widens on entering OSD mode, so the track
        // grows; animating the width would make the bar lag behind
        property real shown: osd.value
        Behavior on shown { NumberAnimation { duration: Appearance.mQuick; easing.type: Easing.OutCubic } }

        RowLayout {
            anchors { fill: parent; leftMargin: 20; rightMargin: 20 }
            spacing: 12

            Text {
                text: osd.isVol
                    ? (ShellState.muted ? Icons.volMute
                        : ShellState.vol > 55 ? Icons.volHigh
                        : ShellState.vol > 20 ? Icons.volMed : Icons.volLow)
                    : Icons.brightness
                color: Colors.label
                font.family: Appearance.font; font.pixelSize: Appearance.fsL
            }
            Rectangle {
                id: osdTrack
                Layout.fillWidth: true
                Layout.preferredHeight: 5
                radius: 3
                color: Colors.fill3
                Rectangle {
                    width: osdTrack.width * Math.max(0, Math.min(1, osd.shown / 100))
                    height: parent.height; radius: parent.radius
                    color: osd.isVol ? Colors.accent : Colors.warn
                    // Now that the bar tells the real level, you need to tell
                    // "playing at 40" apart from "at 40 but muted". The icon
                    // says it; this repeats it without hiding the value.
                    opacity: osd.callado ? 0.35 : 1
                    Behavior on opacity { NumberAnimation { duration: Appearance.mQuick } }
                }
            }
            Text {
                text: Math.round(osd.shown) + "%"
                // label4 is the level reserved for what is unavailable, and with
                // the sound muted the level is exactly that: there, but silent.
                color: osd.callado ? Colors.label4 : Colors.label
                Behavior on color { ColorAnimation { duration: Appearance.mQuick } }
                Layout.preferredWidth: 34
                horizontalAlignment: Text.AlignRight
                font.family: Appearance.font; font.pixelSize: Appearance.fsXS
            }
        }
    }

    // ─────────────── ws: the workspace you just jumped to ───────────────
    // It only shows with the horizontal-wheel GESTURE over the notch, never with
    // Super+1..0. Not an omission: with the shortcut you know where you are going
    // because you just typed the number, and the bar indicator is right beside
    // it. With the wheel there is no number to type and you are looking at the
    // notch, so it is the only case where the gesture needs an acknowledgement.
    NotchLayer {
        anchors.fill: parent
        active: root.mode === "ws"

        Row {
            anchors.centerIn: parent
            spacing: 11

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: I18n.tr("Escritorio")
                color: Colors.label3
                font.family: Appearance.fontUI
                font.pixelSize: Appearance.fsS
                font.weight: Font.Medium
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: String(ShellState.activeWs)
                color: Colors.accentInk
                font.family: Appearance.fontUI
                font.pixelSize: 20
                font.weight: Font.DemiBold
                font.features: ({ "tnum": 1 })   // from 9 to 10 the group must not shift
            }
        }
    }

    // ─────────────── charge: you have plugged in or unplugged ───────────────
    // The only notch notice you do NOT trigger. The rest (OSD, peek, panels)
    // appear because you just did something; this one because something just
    // happened, so it lingers a little longer than an OSD: you were not looking.
    NotchLayer {
        id: chargeLayer
        anchors.fill: parent
        active: root.mode === "charge"

        readonly property color tone: ShellState.ac ? Colors.ok
            : ShellState.batt < 15 ? Colors.crit
            : ShellState.batt < 30 ? Colors.warn : Colors.label

        Row {
            anchors.centerIn: parent
            spacing: 12

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: ShellState.battIcon
                color: chargeLayer.tone
                font.family: Appearance.font
                font.pixelSize: 21
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                // "Con batería" (On battery) and not "Desenchufado" (Unplugged):
                // what matters is not that a cable came out, but what you run on.
                text: ShellState.ac ? I18n.tr("Cargando") : I18n.tr("Con batería")
                color: Colors.label
                font.family: Appearance.fontUI
                font.pixelSize: Appearance.fsM
                font.weight: Font.Medium
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: ShellState.batt >= 0
                text: I18n.tr("{0} %", ShellState.batt)
                color: chargeLayer.tone
                font.family: Appearance.fontUI
                font.pixelSize: 15
                font.weight: Font.DemiBold
                font.features: ({ "tnum": 1 })
            }
        }
    }

    // ─────────────── btpair: pairing a device ───────────────
    // The only face that comes out in front of an open panel, because on the
    // other end there is a device with a timer running. Two forms:
    //   · "display"  -> BlueZ gives us the code and YOU type it on the keyboard.
    //                   There is nothing to answer, only something to read.
    //   · the rest   -> you have to say yes or no, and there are two buttons.
    NotchLayer {
        id: btLayer
        anchors.fill: parent
        active: root.mode === "btpair"

        readonly property bool ask: ShellState.btKind !== "display"

        ColumnLayout {
            anchors { fill: parent; leftMargin: 16; rightMargin: 16; topMargin: 8; bottomMargin: 10 }
            spacing: 6

            RowLayout {
                Layout.fillWidth: true
                spacing: 12

                Text {
                    text: ShellState.btKind === "display" ? Icons.keyboard : Icons.btPair
                    color: Colors.accentInk
                    font.family: Appearance.font
                    font.pixelSize: Appearance.fsXL
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    Text {
                        Layout.fillWidth: true
                        text: ShellState.btName.length > 0 ? ShellState.btName : I18n.tr("Aparato desconocido")
                        color: Colors.label
                        elide: Text.ElideRight
                        font.family: Appearance.fontUI
                        font.pixelSize: 14
                        font.weight: Font.DemiBold
                    }
                    Text {
                        Layout.fillWidth: true
                        text: ShellState.btKind === "display"
                                ? I18n.tr("Teclea este código y pulsa Enter")
                                : ShellState.btKind === "authorize"
                                    ? I18n.tr("Quiere emparejarse con este equipo")
                                    : I18n.tr("¿Sale este mismo código en el aparato?")
                        color: Colors.label2
                        elide: Text.ElideRight
                        font.family: Appearance.fontUI
                        font.pixelSize: Appearance.fsXS
                    }
                }

                // The code, in large digits: it is what you compare at a glance
                // with what the device shows. tnum so it does not jitter as you
                // type.
                Text {
                    visible: ShellState.btCode.length > 0
                    text: ShellState.btCode
                    color: Colors.label
                    font.family: Appearance.fontUI
                    font.pixelSize: Appearance.fsXL
                    font.weight: Font.DemiBold
                    font.letterSpacing: 2
                    font.features: ({ "tnum": 1 })
                }
            }

            // Typing progress: BlueZ keeps reporting how many digits you have
            // typed. It is the only sign the keyboard is talking to the machine.
            Rectangle {
                visible: ShellState.btKind === "display" && ShellState.btEntered >= 0
                Layout.fillWidth: true
                Layout.preferredHeight: 3
                radius: 2
                color: Colors.fill3
                Rectangle {
                    // The fraction, not the width: the rail stretches with the
                    // notch as it opens, and animating the width makes the code
                    // progress seem to advance by itself. See PokeTeamPanel.
                    property real p: Math.min(1, ShellState.btEntered
                            / Math.max(1, ShellState.btCode.length))
                    Behavior on p { NumberAnimation { duration: Appearance.mQuick; easing.type: Easing.OutQuad } }

                    height: parent.height
                    radius: parent.radius
                    color: Colors.accent
                    width: parent.width * p
                }
            }

            RowLayout {
                visible: btLayer.ask
                Layout.fillWidth: true
                Layout.topMargin: 2
                spacing: 8

                Item { Layout.fillWidth: true }

                Repeater {
                    model: [
                        { txt: I18n.tr("No"), ico: Icons.no, ok: false },
                        { txt: I18n.tr("Sí"), ico: Icons.yes, ok: true }
                    ]
                    delegate: Rectangle {
                        required property var modelData
                        implicitWidth: btBtnRow.implicitWidth + 26
                        implicitHeight: 30
                        radius: 15
                        color: modelData.ok
                            ? (btBtnMa.containsMouse ? Qt.rgba(Colors.accent.r, Colors.accent.g, Colors.accent.b, 0.34)
                                                     : Qt.rgba(Colors.accent.r, Colors.accent.g, Colors.accent.b, 0.20))
                            : (btBtnMa.containsMouse ? Colors.fill2 : Colors.fill3)
                        Behavior on color { ColorAnimation { duration: Appearance.mQuick; easing.type: Easing.OutQuad } }

                        RowLayout {
                            id: btBtnRow
                            anchors.centerIn: parent
                            spacing: 7
                            Text {
                                text: modelData.ico
                                color: modelData.ok ? Colors.accentInk : Colors.label2
                                font.family: Appearance.font
                                font.pixelSize: Appearance.fsM
                            }
                            Text {
                                text: modelData.txt
                                color: modelData.ok ? Colors.label : Colors.label2
                                font.family: Appearance.fontUI
                                font.pixelSize: Appearance.fsS
                                font.weight: Font.Medium
                            }
                        }

                        MouseArea {
                            id: btBtnMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: ShellState.btReply(modelData.ok)
                        }
                    }
                }
            }
        }
    }

    // ─────────────── track: "now playing" ───────────────
    NotchLayer {
        anchors.fill: parent
        active: root.mode === "track"

        RowLayout {
            anchors { fill: parent; leftMargin: 12; rightMargin: 14 }
            spacing: 10

            Rectangle {
                Layout.preferredWidth: 34; Layout.preferredHeight: 34
                Layout.alignment: Qt.AlignVCenter
                radius: 9
                color: Colors.fill3
                clip: true
                Image {
                    anchors.fill: parent
                    source: (ShellState.player && ShellState.player.trackArtUrl) ? ShellState.player.trackArtUrl : ""
                    fillMode: Image.PreserveAspectCrop
                    // Without sourceSize the cover art is decoded at its native
                    // resolution (600-1000 px) to paint 22-34 px; 64 is plenty.
                    sourceSize.width: 64
                    visible: status === Image.Ready
                }
                Text {
                    anchors.centerIn: parent
                    visible: !(ShellState.player && ShellState.player.trackArtUrl)
                    text: "󰎈"; color: ShellState.mediaAccent
                    font.family: Appearance.font; font.pixelSize: Appearance.fsL
                    Behavior on color { ColorAnimation { duration: Appearance.mIn; easing.type: Easing.OutCubic } }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                spacing: 1
                Text {
                    Layout.fillWidth: true
                    text: ShellState.player ? (ShellState.player.trackTitle || "") : ""
                    color: Colors.label; elide: Text.ElideRight
                    font.family: Appearance.font; font.pixelSize: Appearance.fsXS; font.bold: true
                }
                Text {
                    Layout.fillWidth: true
                    text: ShellState.player ? (ShellState.player.trackArtist || "") : ""
                    color: Colors.label2; elide: Text.ElideRight
                    font.family: Appearance.font; font.pixelSize: Appearance.fsXXS
                }
            }

            // Same fixed box and same continuous height as in the right pole
            // (see the why there), here over 22 px of height. It uses implicit*
            // because the parent is a RowLayout: the layout is what hands out
            // space, and what we tell it is how much we ask for, not our size.
            Item {
                Layout.alignment: Qt.AlignVCenter
                implicitWidth: ShellState.bands * 8 - 4
                implicitHeight: 22

                Repeater {
                    model: ShellState.bands
                    Rectangle {
                        required property int index
                        x: index * 8
                        width: 4; radius: 2
                        color: ShellState.mediaAccent
                        Behavior on color { ColorAnimation { duration: Appearance.mIn; easing.type: Easing.OutCubic } }
                        antialiasing: true
                        height: Math.max(4, 22 * (ShellState.levels[index] || 0))
                        y: (22 - height) / 2
                    }
                }
            }
        }
    }

    // ─────────────── notif: pop-up notice ───────────────
    // When a notification arrives the notch stretches and shows it for a few
    // seconds, like a live activity. Then it stays in the Control Centre.
    NotchLayer {
        id: notifLayer
        anchors.fill: parent
        active: root.mode === "notif"

        readonly property var n: ShellState.lastNotif

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            // If the notice carries actions, clicking it DOES THAT instead of
            // opening the Control Centre: it is what anyone expects from a
            // notice with something to do behind it. The screenshot sends an
            // "Editar" (Edit) action that opens the picture in satty
            // (~/.config/hypr/scripts/notify-shot.sh); the other notices, which
            // carry none, still open the Control Centre as before.
            onClicked: {
                const n = notifLayer.n;
                const acts = n ? n.actions : null;
                ShellState.activity = "";
                if (acts && acts.length > 0) acts[0].invoke();
                else ShellState.togglePanel("control");
            }
        }

        RowLayout {
            anchors { fill: parent; leftMargin: 13; rightMargin: 15 }
            spacing: 11

            Image {
                Layout.preferredWidth: 34; Layout.preferredHeight: 34
                Layout.alignment: Qt.AlignVCenter
                source: {
                    const n = notifLayer.n;
                    if (!n) return "";
                    return (n.image && n.image.length > 0) ? n.image
                        : Quickshell.iconPath(n.appIcon, "dialog-information");
                }
                sourceSize.width: 34; sourceSize.height: 34
                fillMode: Image.PreserveAspectFit
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                spacing: 1
                Text {
                    Layout.fillWidth: true
                    text: notifLayer.n ? (notifLayer.n.summary || "") : ""
                    color: Colors.label; elide: Text.ElideRight
                    font.family: Appearance.fontUI; font.pixelSize: Appearance.fsS; font.weight: Font.DemiBold
                }
                Text {
                    Layout.fillWidth: true
                    visible: text.length > 0
                    text: notifLayer.n ? (notifLayer.n.body || "") : ""
                    color: Colors.label2; elide: Text.ElideRight
                    textFormat: Text.StyledText
                    font.family: Appearance.fontUI; font.pixelSize: Appearance.fsXXS
                }
            }

            Text {
                Layout.alignment: Qt.AlignVCenter
                text: notifLayer.n ? (notifLayer.n.appName || "") : ""
                color: Colors.accentInk
                font.family: Appearance.fontUI; font.pixelSize: Appearance.fsXXS; font.weight: Font.Medium
            }
        }
    }

    // ─────────────── toast: brief notice (copied to clipboard) ───────────────
    NotchLayer {
        anchors.fill: parent
        active: root.mode === "toast"

        Row {
            anchors.centerIn: parent
            spacing: 11
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: ShellState.toastIcon
                color: Colors.accentInk
                font.family: Appearance.font; font.pixelSize: 17
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: ShellState.toastText
                color: Colors.label
                font.family: Appearance.fontUI; font.pixelSize: Appearance.fsM; font.weight: Font.Medium
            }
        }
    }

    // ─────────────── launcher: application launcher ───────────────
    NotchLayer {
        anchors.fill: parent
        active: root.mode === "launcher"
        origin: -1   // the Arch button is on the left
        // The same condition as the layer: if this screen is not showing the
        // launcher, its copy ignores everything. See the LauncherPanel block.
        LauncherPanel { anchors.fill: parent; enPantalla: root.mode === "launcher" }
    }

    // ─────────────── overview: workspace map ───────────────
    // It is born in the CENTRE (origin 0) and not from a side: no bar button
    // opens it, Super+Tab does. What you did not ask for from a particular
    // place has no reason to come from a particular place.
    NotchLayer {
        anchors.fill: parent
        active: root.mode === "overview"
        OverviewPanel { anchors.fill: parent }
    }

    // ─────────────── control: Control Centre ───────────────
    NotchLayer {
        anchors.fill: parent
        active: root.mode === "control"
        origin: 1   // the notification bell is on the right
        ControlPanel { anchors.fill: parent }
    }

    // ─────────────── system: a calm look at the machine ───────────────
    NotchLayer {
        anchors.fill: parent
        active: root.mode === "system"
        origin: 1   // born from the Control Centre's "Tu máquina" (Your machine) button
        PerformancePanel { anchors.fill: parent }
    }

    // ─────────────── network: network picker ───────────────
    NotchLayer {
        anchors.fill: parent
        active: root.mode === "network"
        origin: 1   // opens from the control panel, on the right
        NetworkPanel { anchors.fill: parent }
    }

    // ─────────────── bluetooth: devices ───────────────
    NotchLayer {
        anchors.fill: parent
        active: root.mode === "bluetooth"
        origin: 1   // opens from the control panel, on the right
        BluetoothPanel { anchors.fill: parent }
    }

    // ─────────────── power: power menu ───────────────
    NotchLayer {
        anchors.fill: parent
        active: root.mode === "power"
        origin: 1   // its icon is on the right
        PowerPanel { anchors.fill: parent }
    }

    // ─────────────── calendar: the month's calendar ───────────────
    NotchLayer {
        anchors.fill: parent
        active: root.mode === "calendar"
        origin: 1   // opens from the Control Centre, on the right
        CalendarPanel { anchors.fill: parent }
    }

    // ─────────────── github: contributions and latest commits ───────────────
    NotchLayer {
        anchors.fill: parent
        active: root.mode === "github"
        origin: 1   // also comes out of a Control Centre card
        GithubPanel { anchors.fill: parent }
    }

    // ─────────────── the pokemon team ───────────────
    NotchLayer {
        anchors.fill: parent
        active: root.mode === "poke"
        origin: 1   // comes out of the Control Centre, like github
        PokeTeamPanel { anchors.fill: parent }
    }

    // ─────────────── evolution: the ceremony ───────────────
    // The notch's only festive face. The sprite alternates between the old
    // form and the new one faster and faster —the rhythm of the original
    // game— and settles on the new one with a scale overshoot. No sound on
    // purpose: Diego chose animation, not a shout.
    NotchLayer {
        id: capaEvo
        anchors.fill: parent
        active: root.mode === "evo"

        Item {
            id: evo
            anchors.fill: parent
            // The queue is shared with the shiny, so the type has to be
            // checked here: without this filter a shiny would ALSO start this
            // rite underneath —invisible, but with its 5 s Timer advancing the
            // queue a second time and eating whatever came next— and the
            // sprite would be left asking for an aGif that does not exist.
            readonly property var datos: (ShellState.pokeEvo && ShellState.pokeEvo.tipo !== "shiny")
                                         ? ShellState.pokeEvo : null
            property bool nueva: false      // which form is shown right now
            property bool revelado: false

            // The ceremony starts when a NEW evolution arrives, not when the
            // face opens: that way a second chained evolution (ShellState's
            // queue) restarts the rite even though the mode has not changed.
            Connections {
                target: ShellState
                function onPokeEvoChanged() {
                    if (!evo.datos)
                        return;
                    evo.nueva = false;
                    evo.revelado = false;
                    alterna.intervalo = 420;
                    alterna.interval = 420;
                    alterna.restart();
                    // `fin` is NO LONGER started by hand: its `running` hangs
                    // off evo.active, so a restart() here would break the
                    // binding and leave the clock running behind a panel again.
                }
            }

            Timer {
                id: alterna
                property real intervalo: 420
                interval: 420
                repeat: true
                running: false
                onTriggered: {
                    if (evo.revelado)
                        return;
                    evo.nueva = !evo.nueva;
                    // speeds up as in the game: each round a little shorter,
                    // and on reaching the floor the new form is revealed.
                    intervalo = intervalo * 0.8;
                    if (intervalo <= 70) {
                        evo.revelado = true;
                        evo.nueva = true;
                        alterna.stop();
                    } else {
                        interval = intervalo;
                        restart();
                    }
                }
            }
            // Moves on to the next in the queue (or lets the face expire).
            //
            // THE CLOCK ONLY RUNS WHILE THE CEREMONY IS VISIBLE.
            //
            // It used to be `running: false` and was started by hand from
            // onPokeEvoChanged, ignoring `root.mode` and `visible`. And
            // NotchLayer is NOT a Loader -it only animates opacity/scale/slide-,
            // so the Item always exists on both screens and this Timer kept
            // counting behind any panel: open the Control Centre mid-evolution
            // and the ceremony was used up without you ever seeing it. Tied to
            // `evo.active`, it stops when covered and starts over when
            // uncovered, so it is seen whole. Exact twin in the shiny one.
            Timer {
                id: fin
                interval: 5000
                running: capaEvo.active && ShellState.pokeEvo !== null
                onTriggered: ShellState.pokeEvoSiguiente()
            }

            // the halo: an accent circle that pulses with the flicker
            Rectangle {
                anchors.centerIn: forma
                width: 100; height: 100; radius: 50
                color: Colors.accent
                opacity: evo.revelado ? 0 : (evo.nueva ? 0.28 : 0.10)
                Behavior on opacity { NumberAnimation { duration: Appearance.mQuick } }
            }

            AnimatedImage {
                id: forma
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.top
                anchors.topMargin: 22
                source: evo.datos ? (evo.nueva ? evo.datos.aGif : evo.datos.deGif) : ""
                sourceSize.height: 72
                height: 72
                fillMode: Image.PreserveAspectFit
                // still during the flicker, alive once revealed
                playing: evo.revelado
                cache: true      // alternates two sources without reloading from disk
                scale: evo.revelado ? 1 : 0.92
                Behavior on scale {
                    NumberAnimation { duration: Appearance.mInScale; easing.type: Easing.OutBack; easing.overshoot: Appearance.mInOvershoot }
                }
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: forma.bottom
                anchors.topMargin: 12
                width: parent.width - 40
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                text: !evo.datos ? ""
                    : evo.revelado
                        ? I18n.tr("¡{0} evolucionó en {1}!", evo.datos.de, evo.datos.a)
                        : I18n.tr("¡{0} está evolucionando!", evo.datos.de)
                color: Colors.label
                // The Game Boy font for the Game Boy moment. It renders accents
                // and opening marks (checked glyph by glyph when installing it).
                font.family: evo.revelado ? Appearance.fontClock : Appearance.fontUI
                font.pixelSize: evo.revelado ? Appearance.fsL : Appearance.fsM
                lineHeight: Appearance.leading(evo.revelado ? Appearance.fsL : Appearance.fsM)
                lineHeightMode: Text.FixedHeight
                opacity: evo.revelado ? 1 : 0.75
                Behavior on opacity { NumberAnimation { duration: Appearance.mIn; easing.type: Easing.OutCubic } }
            }
        }
    }

    // ─────────────── variocolor (shiny): the burst ───────────────
    // The other festive face, and the little sister of the one above: they
    // share queue, width and height. A shiny comes up 1 time in 64 and until
    // now nobody noticed —the only sign was a 9 px ✦ in a row of the panel—,
    // so what was missing was not information, it was a moment.
    //
    // There is nothing to guess here (it does not alternate two forms like the
    // evolution): the creature ALREADY is what it is, and what is told is your
    // luck. So it is a single burst that comes FROM THE SPRITE (law 6: nothing
    // appears out of thin air) with the scale overshoot of an evolution reveal.
    NotchLayer {
        id: capaShiny
        anchors.fill: parent
        active: root.mode === "shiny"

        Item {
            id: vario
            anchors.fill: parent
            readonly property var datos: (ShellState.pokeEvo && ShellState.pokeEvo.tipo === "shiny")
                                         ? ShellState.pokeEvo : null
            property bool revelado: false

            // Same as the evolution: the rite starts with the DATA, not with
            // the face, so that a second chained shiny relaunches it even
            // though the notch's mode has not changed.
            Connections {
                target: ShellState
                function onPokeEvoChanged() {
                    if (!vario.datos)
                        return;
                    vario.revelado = false;
                    arranca.restart();
                    eco.restart();
                    // `caduca` hangs off capaShiny.active: never set by hand.
                }
            }

            // The face takes mStagger to start and mIn to be fully there, i.e.
            // a PANEL coming in: firing the burst earlier wastes it against a
            // layer that is still growing, and you only see half of it.
            Timer {
                id: arranca
                interval: Appearance.mInScale
                onTriggered: { vario.revelado = true; chispas.disparo++; }
            }
            // A second wave and that is it. The first is the blast and this is
            // the echo, just as the previous one is fading (a whole burst is
            // two FORMS: the stagger of the waves plus the travel). A third
            // would already be a loop by another name, which is what law 7
            // forbids.
            Timer {
                id: eco
                interval: Appearance.mInScale + Appearance.mShape * 2
                onTriggered: chispas.disparo++
            }
            // moves on to the next in the queue (or lets the face expire)
            // Same case as the evolution's `fin`, and for the same reason:
            // NotchLayer is not a Loader, so this clock ran behind any panel
            // and ate the burst without showing it. A shiny comes up 1 in
            // 64.
            Timer {
                id: caduca
                interval: 3400
                running: capaShiny.active && ShellState.pokeEvo !== null
                onTriggered: ShellState.pokeEvoSiguiente()
            }

            AnimatedImage {
                id: bicho
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.top
                anchors.topMargin: 26
                source: vario.datos ? vario.datos.gif : ""
                sourceSize.height: 72
                height: 72
                fillMode: Image.PreserveAspectFit
                playing: true
                scale: vario.revelado ? 1 : Appearance.mScaleFrom
                Behavior on scale {
                    NumberAnimation { duration: Appearance.mInScale; easing.type: Easing.OutBack; easing.overshoot: Appearance.mInOvershoot }
                }
            }

            // The burst goes IN FRONT of the sprite and BEHIND the text:
            // sparkles over 16 px lettering make it unreadable just in the
            // second you want to read the name. The box is wider than it is
            // tall on purpose —the face measures 520×168— so the sparkles
            // spread across the space there is, instead of spilling out the top.
            ShinySparkle {
                id: chispas
                anchors.centerIn: bicho
                width: 300
                height: 120
            }

            Text {
                id: nombre
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: bicho.bottom
                anchors.topMargin: 14
                width: parent.width - 40
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                text: vario.datos ? I18n.tr("¡{0} es VARIOCOLOR!", vario.datos.quien) : ""
                color: Colors.label
                // The Game Boy font, the same one an evolution debuts: the two
                // things this desktop celebrates speak the same way.
                font.family: Appearance.fontClock
                font.pixelSize: Appearance.fsL
                lineHeight: Appearance.leading(Appearance.fsL)
                lineHeightMode: Text.FixedHeight
                opacity: vario.revelado ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: Appearance.mIn; easing.type: Easing.OutCubic } }
            }

            // The rarity is the news: without this number, «variocolor» is just
            // an odd word. With it you know you were 64 tries in.
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: nombre.bottom
                anchors.topMargin: 6
                text: vario.datos && vario.datos.unoDe ? I18n.tr("1 entre {0}", vario.datos.unoDe) : ""
                color: Colors.accentInk
                font.family: Appearance.fontUI
                font.pixelSize: Appearance.fsS
                opacity: vario.revelado ? 0.85 : 0
                Behavior on opacity { NumberAnimation { duration: Appearance.mIn; easing.type: Easing.OutCubic } }
            }
        }
    }
}
