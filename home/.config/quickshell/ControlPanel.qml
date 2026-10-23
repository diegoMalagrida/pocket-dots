// ControlPanel.qml — the Control Centre, unfolded FROM the notch.
//
// Replaces swaync's "control center" (which was a GTK window of its own and so
// could not be put in here). Left: vertical player. Centre: sliders and
// switches. Right: the notification history, served by our own
// NotificationServer (see ShellState.qml).
import Quickshell
import Quickshell.Services.Notifications
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Item {
    id: root

    // swallows clicks on the gaps so they do not close the panel
    MouseArea { anchors.fill: parent }

    RowLayout {
        anchors { fill: parent; leftMargin: 24; rightMargin: 22; topMargin: 20; bottomMargin: 20 }
        spacing: 20

        // ═════════════ izquierda: reproductor vertical ═════════════
        // It is the player from the reference, but INSIDE Super+D: it shares the
        // same surface and the same close-on-click-outside as the rest of the
        // Control Centre.
        MediaPanel {
            Layout.preferredWidth: 260
            Layout.fillHeight: true
        }

        Rectangle { Layout.fillHeight: true; width: 1; color: Colors.hairline }

        // ═════════════════ centro: controles ═════════════════
        ColumnLayout {
            // maximumWidth AS WELL AS preferredWidth: in Qt Layouts the preferred size
            // is NOT a cap, and it only takes one row asking for more for the whole
            // column to widen and steal space from the notifications, which ended up
            // with 218 px of the 282 that are theirs. With the cap, what adjusts is
            // the content -- which is what it has elide for.
            Layout.preferredWidth: 410
            Layout.maximumWidth: 410
            Layout.fillHeight: true
            spacing: 14

            // ---- sliders ----
            NotchSlider {
                Layout.fillWidth: true
                icon: ShellState.muted ? Icons.volMute : Icons.volHigh
                value: ShellState.muted ? 0 : ShellState.vol
                accent: Colors.accent
                onMoved: function (v) { ShellState.setVolume(v); }
                onIconClicked: ShellState.toggleMute()
            }
            // On a machine with no internal panel (a tower) there is no
            // /sys/class/backlight at all, brightnessctl finds nothing and `bright`
            // stays at -1 forever. The slider showed up anyway: at zero, motionless
            // and with no effect. A control that controls nothing lies about what
            // you can do, so the whole row disappears and the volume is left on its
            // own. Being a ColumnLayout, an invisible item takes no space and the
            // gap closes by itself (same reasoning as Settings, which already hid
            // its brightness row with `shown`).
            NotchSlider {
                visible: ShellState.bright >= 0
                Layout.fillWidth: true
                icon: Icons.brightness
                value: Math.max(0, ShellState.bright)
                // BOTH SLIDERS ARE THE SAME COLOUR; THE ICON TELLS THEM APART.
                //
                // There used to be `accent: Colors.warn` here, and that was two problems
                // in one line. `warn` is the FIXED amber that means «warning» and so it
                // is not recoloured by pywal: brightness is not a warning, and on top of
                // that this slider stayed un-themed while the volume one, right above
                // it, did change.
                //
                // `accent2` was tried, which does come from the palette, and the flaw in
                // that idea showed as soon as the wallpaper changed: with today's green
                // palette, accent2 (#216655) and accent (#2e8a6b) are almost the same
                // colour, so the distinction we were after is guaranteed by nobody.
                // pywal promises no contrast between color1 and color4.
                //
                // So colour is taken out of the equation, which is what the HIG
                // prescribe: "you can use text labels or glyph shapes to identify
                // objects or states" (color.md) -- never colour alone. The speaker and
                // the sun are already there and already say it. It is what macOS does
                // with these same two sliders.
                onMoved: function (v) { ShellState.setBrightness(v); }
            }

            // ---- switches ----
            GridLayout {
                Layout.fillWidth: true
                Layout.topMargin: 2
                columns: 5
                columnSpacing: 10

                // One single target per card. If it has a dedicated panel, any click
                // opens that panel; its switch already lives in the Network/Bluetooth
                // header. The other switches DO act right here.
                component Toggle: Rectangle {
                    id: tg
                    property string icon: ""
                    property string label: ""
                    property bool on: false
                    property string panel: ""      // "" = no dedicated panel
                    property int idx: 0            // its turn in the cascade
                    signal activated()

                    Layout.fillWidth: true
                    Layout.preferredHeight: 58

                    // CASCADE. The six appeared at once, which is the same as saying
                    // they did not appear: a block that switches on has no direction
                    // and cannot be followed with the eye. Staggered, the eye runs
                    // over them from left to right and the panel reads as something
                    // unfolding.
                    //
                    // NOTE: opacity is NOT touched here. The fade is already done by
                    // the NotchLayer that contains this panel, and two chained
                    // opacities multiply: it does not look smoother, it looks like it
                    // arrives late. The layer takes care of appearing; the cascade,
                    // only of getting into place. One gesture, one owner.
                    property real ent: ShellState.mode === "control" ? 1 : 0
                    Behavior on ent {
                        SequentialAnimation {
                            PauseAnimation { duration: ShellState.mode === "control" ? tg.idx * 32 : 0 }
                            SpringAnimation {
                                spring: Appearance.sprPanel
                                damping: Appearance.dmpPanel
                                epsilon: Appearance.eppScale
                            }
                        }
                    }
                    scale: 0.82 + 0.18 * tg.ent
                    transform: Translate { y: (1 - tg.ent) * 12 }
                    radius: Appearance.radM
                    // THE COLOUR GOES ON THE BACKGROUND, NOT ON THE SYMBOL.
                    //
                    // The on state used to paint the background in accent at 26% AND
                    // ALSO write the icon and the label in accent. Measured with
                    // his palette: the text ended up at 2.78:1 over that background,
                    // while the off state -light grey over a neutral fill- gave
                    // 9.22:1. In other words the state that matters read 3.3 times
                    // WORSE than the other one. You see it as soon as you look: the
                    // three that were on looked like the off ones and vice versa.
                    //
                    // The HIG say it in one line: "To emphasize primary actions,
                    // apply color to the background rather than to symbols or text"
                    // (color.md). The background states the state; the ink only has
                    // to be readable.
                    //
                    // And the fill goes up to 0.42 because at 0.26 the on state was
                    // barely distinguishable from the off one (1.21:1 between the two
                    // backgrounds). At 0.42 it is 1.51:1 and the text stays at 6.8:1.
                    color: tg.on ? Qt.rgba(Colors.accent.r, Colors.accent.g, Colors.accent.b, 0.42)
                         : tgMa.containsMouse ? Colors.fill2 : Colors.fill3
                    Behavior on color { ColorAnimation { duration: Appearance.mQuick; easing.type: Easing.OutQuad } }

                    ColumnLayout {
                        anchors.centerIn: parent
                        spacing: 1
                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            text: tg.icon
                            color: Colors.label
                            font.family: Appearance.font; font.pixelSize: Appearance.fsL
                        }
                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            text: tg.label
                            // When on it goes up to full ink: the label of what is
                            // active is not secondary information.
                            color: tg.on ? Colors.label : Colors.label3
                            font.family: Appearance.fontUI; font.pixelSize: Appearance.fsXXS
                            font.weight: tg.on ? Appearance.wMedium : Appearance.wRegular
                        }
                    }
                    MouseArea {
                        id: tgMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (tg.panel.length > 0) ShellState.togglePanel(tg.panel);
                            else tg.activated();
                        }
                    }
                }

                Toggle {
                    icon: ShellState.netIcon; label: I18n.tr("Red"); idx: 0
                    on: ShellState.online
                    panel: "network"
                }
                Toggle {
                    icon: ShellState.btIcon; label: I18n.tr("Bluetooth"); idx: 1
                    on: ShellState.btOn
                    panel: "bluetooth"
                }
                Toggle {
                    icon: ShellState.dnd ? "󰂛" : "󰂚"; label: I18n.tr("No molestar"); idx: 2
                    on: ShellState.dnd
                    onActivated: ShellState.dnd = !ShellState.dnd
                }
                Toggle {
                    icon: Icons.coffee; label: I18n.tr("Cafeína"); idx: 3
                    on: ShellState.caffeine
                    onActivated: ShellState.caffeine = !ShellState.caffeine
                }
                Toggle {
                    icon: Icons.moon; label: I18n.tr("Luz noct."); idx: 4
                    on: ShellState.nightLight
                    onActivated: ShellState.toggleNightLight()
                }
                Toggle {
                    icon: Icons.remote; label: I18n.tr("Remoto"); idx: 5
                    on: ShellState.remoteMode
                    onActivated: ShellState.toggleRemoteMode()
                }
                Toggle {
                    icon: Icons.pokeball; label: I18n.tr("Pokémon"); idx: 6
                    on: ShellState.pokeTheme
                    onActivated: ShellState.togglePokeTheme()
                }
                // `on` is always false on purpose: the other tiles switch something on
                // and the colour says whether it is on, but this one is a door, not a
                // switch. Painting it on would promise a state that does not exist.
                Toggle {
                    icon: Icons.calendar; label: I18n.tr("Calendario"); idx: 7
                    on: false
                    panel: "calendar"
                }
            }

            // ---- the pokemon team ----
            // A spacer on EACH side instead of a single one on top: the spare air
            // between the switches and the weather is shared out, and the strip
            // floats in its gap instead of sticking to the grid above, where it
            // would read as one more row of switches.
            Item { Layout.fillHeight: true }

            PokeTeamStrip {}

            Item { Layout.fillHeight: true }

            // ---- weather + system (inherited from the retired Sidebar) ----
            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: 2
                spacing: 16

                // The sky picks the icon. Here there used to be Icons.brightness —the
                // glyph of the brightness slider— standing in for the weather, with its
                // warning orange included: an orange sun got away with it, but an
                // orange cloud did not, and on top of that it promised a colour that
                // means nothing. Grey, like the labels of the switches that are off.
                Text {
                    text: ShellState.weatherIcon
                    color: Colors.label3
                    font.family: Appearance.font; font.pixelSize: 14
                }
                // The temperature is what you look for at a glance and the condition
                // is the context. Both were in the same type and the same grey, so you
                // had to read the whole line to get the number out. Now the number
                // carries weight and the condition comes along.
                Text {
                    text: ShellState.weatherTemp
                    color: Colors.label
                    font.family: Appearance.fontUI; font.pixelSize: Appearance.fsS
                    font.features: ({ "tnum": 1 })
                }
                Text {
                    Layout.fillWidth: true
                    text: ShellState.weatherCond
                    color: Colors.label3; elide: Text.ElideRight
                    font.family: Appearance.fontUI; font.pixelSize: Appearance.fsXS
                }
            }

            // ---- the two doors: performance and GitHub ----
            // A row of its own and NOT inside the weather one. With both cards up
            // there, that row asked for 506 px and this column is declared at 410:
            // the RowLayout widened it to 474, and it took those 64 px from the
            // notifications column (218 instead of 282), which came out squeezed
            // against the edge, with the slider percentages treading on the
            // separator and the weather compressed until it vanished. They share
            // the width between the two instead of measuring a fixed 222.
            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: 10
                spacing: 12

                // The three glyphs with percentages were indecipherable unless you
                // knew by heart what each one meant. Now this is a door with a name:
                // it keeps the quick glance and opens the graphs.
                Rectangle {
                    id: performanceLink
                    Layout.fillWidth: true
                    Layout.preferredHeight: 42
                    radius: 13
                    color: performanceMa.containsMouse
                        ? Qt.rgba(Colors.accent.r, Colors.accent.g, Colors.accent.b, 0.14)
                        : Colors.fill3
                    border.width: 1
                    border.color: performanceMa.containsMouse
                        ? Qt.rgba(Colors.accent.r, Colors.accent.g, Colors.accent.b, 0.26)
                        : Colors.hairline
                    Behavior on color { ColorAnimation { duration: Appearance.mQuick; easing.type: Easing.OutQuad } }

                    RowLayout {
                        anchors { fill: parent; leftMargin: 12; rightMargin: 10 }
                        spacing: 8
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0
                            Text {
                                text: I18n.tr("Tu máquina")
                                color: performanceMa.containsMouse ? Colors.accentInk : Colors.label
                                font.family: Appearance.fontUI; font.pixelSize: Appearance.fsXXS
                                font.weight: Font.DemiBold
                            }
                            Text {
                                text: I18n.tr("CPU {0}%  ·  RAM {1}%  ·  SSD {2}%",
                                              ShellState.cpu, ShellState.mem, ShellState.disk)
                                color: Colors.label3
                                font.family: Appearance.fontUI; font.pixelSize: 8
                                font.features: ({ "tnum": 1 })
                            }
                        }
                        Text {
                            text: "›"
                            color: performanceMa.containsMouse ? Colors.accentInk : Colors.label3
                            font.family: Appearance.fontUI; font.pixelSize: 20
                        }
                    }

                    MouseArea {
                        id: performanceMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: ShellState.togglePanel("system")
                    }
                }

                // Same idea as the one above, and the same shape on purpose: a
                // glance (the last twelve weeks, the total and the streak) and a door
                // to the whole panel. The squares take pywal's accent, not GitHub's
                // green, so it does not look bolted on.
                Rectangle {
                    id: githubLink
                    Layout.fillWidth: true
                    Layout.preferredHeight: 42
                    radius: 13
                    color: githubMa.containsMouse
                        ? Qt.rgba(Colors.accent.r, Colors.accent.g, Colors.accent.b, 0.14)
                        : Colors.fill3
                    border.width: 1
                    border.color: githubMa.containsMouse
                        ? Qt.rgba(Colors.accent.r, Colors.accent.g, Colors.accent.b, 0.26)
                        : Colors.hairline
                    Behavior on color { ColorAnimation { duration: Appearance.mQuick; easing.type: Easing.OutQuad } }

                    // The last twelve columns of the big grid. If the data has not
                    // arrived yet, this is an empty array and nothing is painted:
                    // the card is still a valid door.
                    readonly property var mini: (ShellState.github.weeks || []).slice(-12)

                    RowLayout {
                        anchors { fill: parent; leftMargin: 12; rightMargin: 10 }
                        spacing: 8

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0
                            Text {
                                text: I18n.tr("GitHub")
                                color: githubMa.containsMouse ? Colors.accentInk : Colors.label
                                font.family: Appearance.fontUI; font.pixelSize: Appearance.fsXXS
                                font.weight: Font.DemiBold
                            }
                            Text {
                                text: ShellState.github.stale
                                    ? I18n.tr("sin conexión")
                                    : I18n.tr("{0}  ·  racha {1}",
                                              ShellState.github.total || 0,
                                              ShellState.github.streak || 0)
                                color: Colors.label3
                                font.family: Appearance.fontUI; font.pixelSize: 8
                                font.features: ({ "tnum": 1 })
                            }
                        }

                        // The grid in miniature: 12 columns of 3 px. It has no mouse
                        // over it and counts nothing; that is what the panel is for.
                        Item {
                            implicitWidth: 12 * 4 - 1
                            implicitHeight: 7 * 4 - 1
                            Repeater {
                                model: githubLink.mini.length
                                Item {
                                    id: miniCol
                                    required property int index
                                    readonly property var niveles: githubLink.mini[index] || []
                                    x: index * 4
                                    width: 3
                                    height: 7 * 4 - 1
                                    Repeater {
                                        model: 7
                                        Rectangle {
                                            required property int index
                                            y: index * 4
                                            width: 3; height: 3; radius: 1
                                            readonly property int lvl:
                                                miniCol.niveles[index] !== undefined
                                                    ? miniCol.niveles[index] : -1
                                            color: lvl < 0 ? "transparent"
                                                 : lvl === 0 ? Colors.fill3
                                                 : Qt.rgba(Colors.accent.r, Colors.accent.g,
                                                           Colors.accent.b,
                                                           [0, 0.30, 0.52, 0.74, 1.0][lvl])
                                        }
                                    }
                                }
                            }
                        }

                        Text {
                            text: "›"
                            color: githubMa.containsMouse ? Colors.accentInk : Colors.label3
                            font.family: Appearance.fontUI; font.pixelSize: 20
                        }
                    }

                    MouseArea {
                        id: githubMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: ShellState.togglePanel("github")
                    }
                }
            }
        }

        Rectangle { Layout.fillHeight: true; width: 1; color: Colors.hairline }

        // ══════════════════ derecha: notificaciones ══════════════════
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 8

            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                Text {
                    text: I18n.tr("Notificaciones")
                    color: Colors.label
                    font.family: Appearance.fontUI; font.pixelSize: Appearance.fsS; font.weight: Font.DemiBold
                }
                Rectangle {
                    visible: ShellState.notifCount > 0
                    implicitWidth: cnt.implicitWidth + 12
                    implicitHeight: 17
                    radius: 9
                    color: Qt.rgba(Colors.accent.r, Colors.accent.g, Colors.accent.b, 0.28)
                    Text {
                        id: cnt
                        anchors.centerIn: parent
                        text: ShellState.notifCount
                        color: Colors.accentInk
                        font.family: Appearance.fontUI; font.pixelSize: Appearance.fsXXS; font.weight: Font.Medium
                        font.features: ({ "tnum": 1 })
                    }
                }
                Item { Layout.fillWidth: true }
                Text {
                    text: "󰒓"
                    color: gearMa.containsMouse ? Colors.accentInk : Colors.label3
                    font.family: Appearance.font; font.pixelSize: 14
                    Behavior on color { ColorAnimation { duration: Appearance.mQuick; easing.type: Easing.OutQuad } }
                    MouseArea {
                        id: gearMa
                        anchors.fill: parent; anchors.margins: -5
                        hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: { ShellState.closePanel(); ShellState.settingsOpen = true; }
                    }
                }
                Text {
                    visible: ShellState.notifCount > 0
                    text: I18n.tr("Limpiar")
                    color: clearMa.containsMouse ? Colors.accentInk : Colors.label3
                    font.family: Appearance.fontUI; font.pixelSize: Appearance.fsXS
                    Behavior on color { ColorAnimation { duration: Appearance.mQuick; easing.type: Easing.OutQuad } }
                    MouseArea {
                        id: clearMa
                        anchors.fill: parent; anchors.margins: -5
                        hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: ShellState.clearNotifs()
                    }
                }
            }

            // ─────────── the mouse is read ONCE, and it is read here ───────────
            // Each row had its own MouseArea and the cross another one on top. Three
            // bugs came out of that, and all three show up right when you go to close
            // one:
            //
            //   · the body is in StyledText (whatever markup the app sends), and a
            //     Text with markup ACCEPTS hover events so it can detect links: it
            //     swallowed the row's. Measured: over the title the row lit up and
            //     the cross came out; two lines further down, nothing. Most of the
            //     surface of each row was a dead zone.
            //   · the cross appeared with `visible`, so it went in and out of the
            //     layout: the text column widened by 23 px as soon as you took the
            //     mouse away. It is the least of the three, but it is geometry that
            //     moves by itself right under the pointer.
            //   · and when you dismiss one, the model is a NEW array (see
            //     ShellState.notifications): all the delegates are rebuilt with
            //     hover at zero. Since the hand has not moved no event arrives to
            //     correct it, and the list is left lying: cross lit over a row that
            //     is off, and the second click in the same place closes nothing
            //     because it lands in the gap.
            //
            // With a single MouseArea over the list there is one single owner of
            // "what is under the pointer". And —this is what fixes the third one—
            // that owner can look again when the list changes, without having to
            // wait for the hand to move.
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

                ListView {
                    id: notifList
                    anchors.fill: parent
                    clip: true
                    spacing: 7
                    // ScriptModel: with the bare array, dismissing a
                    // notification reset the model and ALL the rows were
                    // rebuilt; now only its own disappears and the rest keep
                    // their delegate. The retrack further down is still
                    // needed: the ones below move up and another row ends up
                    // under a still pointer. Notifications are the same
                    // server objects while they live -> identity.
                    model: ScriptModel {
                        values: ShellState.notifications
                        comparisonMode: ObjectComparison.Identity
                    }
                    boundsBehavior: Flickable.StopAtBounds
                    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded; width: 4 }

                    property int hoverIdx: -1        // row under the pointer; -1 = none
                    property bool overClose: false   // ...and over its cross

                    // (mx, my) in viewport coordinates, which is how the mouse gives them.
                    function track(mx, my) {
                        const y = my + notifList.contentY;
                        const i = notifList.indexAt(notifList.width / 2, y);
                        notifList.hoverIdx = i;
                        const fila = i >= 0 ? notifList.itemAtIndex(i) : null;
                        const equis = fila ? fila.closeItem : null;
                        if (!equis) {
                            notifList.overClose = false;
                            return;
                        }
                        // The target is not written by hand: the layout is asked where
                        // it left the cross and it is given the 6 px of margin that the
                        // MouseArea that used to live there had. If the row spacing
                        // changes tomorrow, the target moves by itself.
                        const p = equis.mapToItem(fila, 0, 0);
                        notifList.overClose = mx >= p.x - 6 && mx <= p.x + equis.width + 6
                            && (y - fila.y) >= p.y - 6 && (y - fila.y) <= p.y + equis.height + 6;
                    }

                    // Look again without the mouse having moved: when a notification
                    // is closed the ones below move up and what is under the pointer
                    // is now another row. forceLayout because otherwise the old list
                    // is measured and the cross comes out lit on the wrong row.
                    function retrack() {
                        if (!listMa.containsMouse) {
                            notifList.hoverIdx = -1;
                            notifList.overClose = false;
                            return;
                        }
                        notifList.forceLayout();
                        notifList.track(listMa.mouseX, listMa.mouseY);
                    }

                    onCountChanged: Qt.callLater(notifList.retrack)
                    // With the wheel it is the rows that move, not the hand.
                    onContentYChanged: if (listMa.containsMouse) notifList.track(listMa.mouseX, listMa.mouseY)

                    delegate: Rectangle {
                        id: nrow
                        required property var modelData
                        required property int index
                        readonly property bool hovered: notifList.hoverIdx === nrow.index
                        // The only thing the row tells the list: where its cross is,
                        // so it knows who the click is meant for.
                        readonly property Item closeItem: equis

                        width: notifList.width
                        height: ncol.implicitHeight + 20
                        radius: 12
                        color: nrow.hovered ? Colors.fill2 : Colors.fill3
                        Behavior on color { ColorAnimation { duration: Appearance.mQuick; easing.type: Easing.OutQuad } }

                        RowLayout {
                            anchors { fill: parent; leftMargin: 12; rightMargin: 10; topMargin: 10; bottomMargin: 10 }
                            spacing: 11

                            Image {
                                Layout.preferredWidth: 22
                                Layout.preferredHeight: 22
                                Layout.alignment: Qt.AlignTop
                                source: nrow.modelData.image && nrow.modelData.image.length > 0
                                    ? nrow.modelData.image
                                    : Quickshell.iconPath(nrow.modelData.appIcon, "dialog-information")
                                sourceSize.width: 22; sourceSize.height: 22
                                fillMode: Image.PreserveAspectFit
                            }

                            ColumnLayout {
                                id: ncol
                                Layout.fillWidth: true
                                spacing: 2
                                Text {
                                    Layout.fillWidth: true
                                    text: nrow.modelData.appName || ""
                                    color: nrow.modelData.urgency === NotificationUrgency.Critical ? Colors.crit : Colors.label3
                                    elide: Text.ElideRight
                                    font.family: Appearance.fontUI; font.pixelSize: Appearance.fsXXS
                                    font.weight: Font.DemiBold
                                }
                                Text {
                                    Layout.fillWidth: true
                                    text: nrow.modelData.summary || ""
                                    color: Colors.label
                                    elide: Text.ElideRight
                                    font.family: Appearance.fontUI; font.pixelSize: Appearance.fsS; font.weight: Font.Medium
                                }
                                Text {
                                    Layout.fillWidth: true
                                    visible: text.length > 0
                                    text: nrow.modelData.body || ""
                                    color: Colors.label2
                                    wrapMode: Text.Wrap
                                    maximumLineCount: 3
                                    elide: Text.ElideRight
                                    textFormat: Text.StyledText
                                    font.family: Appearance.fontUI; font.pixelSize: Appearance.fsXS
                                    lineHeight: Appearance.leading(Appearance.fsXS)
                                    lineHeightMode: Text.FixedHeight
                                }
                            }

                            Text {
                                id: equis
                                Layout.alignment: Qt.AlignTop
                                // Opacity, not `visible`: the cross takes up its slot whether
                                // it is lit or not, so the row measures the same with and
                                // without the mouse. Reserving the space costs nothing and
                                // gets rid of the class of bug in which what you are chasing
                                // moves because you are chasing it.
                                opacity: nrow.hovered ? 1 : 0
                                text: "󰅖"
                                color: nrow.hovered && notifList.overClose ? Colors.crit : Colors.label3
                                font.family: Appearance.font; font.pixelSize: Appearance.fsS
                                Behavior on opacity { NumberAnimation { duration: Appearance.mQuick; easing.type: Easing.OutQuad } }
                                Behavior on color { ColorAnimation { duration: Appearance.mQuick; easing.type: Easing.OutQuad } }
                            }
                        }
                    }
                }

                MouseArea {
                    id: listMa
                    anchors.fill: parent
                    z: 1                     // above the rows: the hover is its own
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton
                    cursorShape: notifList.overClose ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onPositionChanged: function (mouse) { notifList.track(mouse.x, mouse.y); }
                    onEntered: notifList.track(listMa.mouseX, listMa.mouseY)
                    onExited: { notifList.hoverIdx = -1; notifList.overClose = false; }
                    onClicked: {
                        // ShellState's list and NOT notifList.model: the model
                        // is a ScriptModel, not an array, so `model[i]` would
                        // return undefined and neither the cross nor a click on
                        // the row would do anything. The index came from
                        // indexAt() on this same list and the order is the same,
                        // but the range is checked because one may have expired
                        // between the hover and the click.
                        const ns = ShellState.notifications;
                        const n = (notifList.hoverIdx >= 0 && notifList.hoverIdx < ns.length)
                            ? ns[notifList.hoverIdx] : null;
                        if (!n) return;
                        if (notifList.overClose) { ShellState.dismissNotif(n); return; }
                        const acts = n.actions;
                        if (acts && acts.length > 0) { acts[0].invoke(); ShellState.closePanel(); }
                    }
                }
            }

            Text {
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: ShellState.notifCount === 0
                text: I18n.tr("Sin notificaciones")
                color: Colors.label3
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                font.family: Appearance.fontUI; font.pixelSize: Appearance.fsS
            }
        }
    }
}
