// PerformancePanel.qml — «Tu máquina» (Your computer), unfolded FROM the notch.
//
// Sibling of NetworkPanel and BluetoothPanel, and built the same way as them:
// header (icon · title · subtitle · one control on the right), a 1 px hairline
// (Colors.hairline), and body. Nothing else.
//
// The previous face broke out of that everywhere, and that is why it stuck out
// so much: it let the wallpaper through as a background with a black gradient
// on top —it was the only place in the shell with a surface of its own—, it
// invented a whole grey scale (#f2f2f2, #efefef, #bcbcbc, #a8a8a8, #858585,
// #747474, #686868, #555555) that nobody else uses, it titled in lower case
// («actividad reciente», «ahora mismo»: recent activity, just now) while the
// rest of the notch says «Red» (Network) or «Notificaciones», and it opened
// with a cheering phrase. Opening it felt like jumping into another
// application.
//
// Here there is no surface of its own: the panel paints over the notch's like
// the others, and the only things floating on top are the same radM cards with
// the token surface and hairline (Colors.surface1 and Colors.hairline) that the
// Settings window uses. And the ink is not a grey scale of its own either: it
// is Colors' label levels (label · label2 · label3), which get re-themed by
// pywal instead of staying neutral when the wallpaper changes.
//
// THE CURVES RULE. They are the only thing this panel shows that cannot be
// seen anywhere else on the desktop, so they get the whole big card and the
// temperature gets its own. The battery, on the other hand, IS ALWAYS in the
// notch at rest ALREADY: repeating it here with card, bar and estimate meant
// spending a third of the panel on a figure you can see without opening
// anything. Now it is half a line in the subtitle, and it only changes tone
// when there really is little left.
//
// And the curves are governed by three decisions that are explained where they
// live, but it is worth knowing they exist before touching anything:
//   · ONE BAND PER SERIES, each with its own ceiling (see `ceilFor`). Sharing an
//     axis between processor and memory condemned one of the two to crawl along
//     the floor, and on top of that invited comparing two percentages that do
//     not mean the same thing.
//   · THE CEILING IS ANNOUNCED, top left of each band. An axis that moves on its
//     own and does not say so is an axis that lies.
//   · THE MARKS ARE THIN (see the header of HistoryGraph.qml): 2 px stroke,
//     10 % fill —a veil, not a block—, an 8 px point with a surface ring and not
//     a single grid line. That is what separates a calm chart from a monitoring
//     dashboard, and it is not a matter of taste: they are measurements.
import QtQuick
import QtQuick.Layouts

Item {
    id: root

    readonly property bool active: ShellState.panel === "system"

    // ─────────────── what really needs a warning ───────────────
    // No cheering phrase: if nothing is happening, the subtitle says how long
    // it has been on and how the battery is doing, which are facts. Only when
    // something happens do the subtitle (and the header icon) change colour.
    readonly property bool battLow: ShellState.batt >= 0 && ShellState.batt < 18 && !ShellState.ac
    readonly property bool hot: ShellState.cpuTemp >= 78
    readonly property color headTone: root.battLow ? Colors.crit
        : root.hot ? Colors.warn : Colors.accent

    function decimal(v, digits) { return Number(v).toFixed(digits).replace(".", ","); }
    function gibFromKib(v) { return root.decimal(v / 1048576, 1); }
    function gibFromBytes(v) { return root.decimal(v / 1073741824, 1); }
    function uptime(seconds) {
        const mins = Math.max(0, Math.floor(seconds / 60));
        const days = Math.floor(mins / 1440);
        const hours = Math.floor((mins % 1440) / 60);
        const rest = mins % 60;
        if (days > 0) return days + " d " + hours + " h";
        if (hours > 0) return hours + " h " + rest + " min";
        return rest + " min";
    }

    // ══════════════════════════════════════════════════════════════════════
    //  THE SCALES FIT WHAT IS THERE
    //
    //  With the axis nailed to 0..100 the curves spent their life crawling
    //  along the bottom edge: at rest the processor runs at 4 % and memory at
    //  21 %, so three quarters of the card were empty and the signal was a
    //  two-pixel tremor. A chart that does not use its height is not a chart,
    //  it is an ornament.
    //
    //  But raw autoscaling will not do either: the ceiling would dance with
    //  every sample and the curve would move even if the machine did nothing.
    //  That is why the ceiling JUMPS BETWEEN FOUR VALUES (25 · 50 · 75 · 100)
    //  and is announced top left, in the place where an axis carries its label.
    //  That way the band is always full, the jump happens rarely and you never
    //  have to guess what it is being measured against.
    //
    //  And EACH SERIES HAS ITS OWN BAND. Sharing an axis between processor and
    //  memory was the underlying mistake: at rest memory runs four or five
    //  times higher than the processor, so an axis that let one breathe
    //  squashed the other against the floor, whatever it did. Two stacked
    //  bands with their own ceiling fit in the same height, both fill up, and
    //  they also stop inviting a comparison between two things that do not
    //  compare (20 % of RAM and 20 % of CPU do not mean remotely the same).
    // ══════════════════════════════════════════════════════════════════════
    //  The ladder goes down to 5 on purpose. With the first rung at 25 —which
    //  is what seems reasonable when you write it— a processor at rest at 4 %
    //  was still a line at a third of the height: the axis had changed but not
    //  the problem. The rungs are numbers you read at a glance
    //  (5·10·20·30·50·75·100), and the 1.25 is headroom: without it the series
    //  sticks to the top edge of its band and seems to be hitting the ceiling.
    //  The rungs are tight at the bottom and loose at the top on purpose:
    //  between 5 and 20 is where a laptop at rest lives and a jump from 10 to
    //  20 leaves half the band empty, whereas up top the jump from 50 to 75
    //  goes unnoticed because by then what you look at is the shape of the
    //  peak, not the exact number.
    readonly property var ceilSteps: [5, 10, 15, 20, 30, 40, 50, 75, 100]
    function ceilFor(series) {
        let m = 0;
        if (series) for (let i = 0; i < series.length; i++) if (series[i] > m) m = series[i];
        m *= 1.25;
        for (let i = 0; i < root.ceilSteps.length; i++)
            if (m <= root.ceilSteps[i]) return root.ceilSteps[i];
        return 100;
    }

    // No round scale works for temperature: between 38 and 44 °C there are six
    // degrees of real travel and on 0..100 —or even on 35..95— that is a
    // straight line. Here the window hugs what has happened in the last minute
    // and a half, with a minimum of 10 degrees so that two tenths of nothing do
    // not look like a mountain. The big figure calls out the exact degree; the
    // curve is there to show the SHAPE.
    readonly property var tempRange: {
        const h = ShellState.tempHistory;
        if (!h || h.length === 0) return { lo: 35, hi: 55 };
        let lo = h[0], hi = h[0];
        for (let i = 1; i < h.length; i++) {
            if (h[i] < lo) lo = h[i];
            if (h[i] > hi) hi = h[i];
        }
        const mid = (lo + hi) / 2;
        const span = Math.max(10, (hi - lo) * 1.6);
        return { lo: Math.max(0, mid - span / 2), hi: mid + span / 2 };
    }

    // ─────────────── reading on the fly ───────────────
    // sysstats.sh spits out a sample every 1.5 s (see ShellState): that is
    // where both the label's «hace 90 s» (90 s ago) and this countdown come
    // from.
    readonly property real samplePeriod: 1.5

    // Index of the sample nearest to an X. It rounds instead of truncating
    // because the crosshair snaps to the NEAREST point: you point at an
    // instant, you do not have to hunt a two-pixel line.
    function sampleAt(x, w, series) {
        const n = series ? series.length : 0;
        if (n < 2 || w <= 0) return -1;
        return Math.max(0, Math.min(n - 1, Math.round(x / w * (n - 1))));
    }
    function agoText(stepsBack) {
        const secs = Math.round(stepsBack * root.samplePeriod);
        if (secs <= 0) return I18n.tr("ahora mismo");
        if (secs < 60) return I18n.tr("hace {0} s", secs);
        const mins = Math.floor(secs / 60), rest = secs % 60;
        if (rest > 0) return I18n.tr("hace {0} min {1} s", mins, rest);
        return I18n.tr("hace {0} min", mins);
    }

    // ══════════════════════════════════════════════════════════════════════
    //  THE CURVES' TONE IS NOT PLAIN Colors.accent
    //
    //  The accent comes from pywal, that is from the wallpaper, and with a dark
    //  wallpaper it comes back dark: on the card's surface (almost black) a
    //  curve like that gets lost. «It usually looks fine» will not do here — a
    //  2 px stroke is a graphical element and needs 3:1 against its
    //  background. The accent's lightness is raised, and ONLY the lightness,
    //  until it reaches that 3:1: the hue is still pywal's, so the re-theming
    //  is kept whole. It is the same recipe Colors.onWallAccent uses for the
    //  bar, but measured against the card instead of against the wallpaper.
    // ══════════════════════════════════════════════════════════════════════
    readonly property color plotSurface: Colors.surface1   // the card's surface
    function readable(c) {
        const h = c.hslHue < 0 ? 0 : c.hslHue;
        const s = c.hslSaturation;
        let l = c.hslLightness;
        let out = Qt.hsla(h, s, l, 1);
        for (let i = 0; i < 60 && Colors.contrast(out, root.plotSurface) < 3.0; i++) {
            l = Math.min(l + 0.02, 1);
            out = Qt.hsla(h, s, l, 1);
        }
        return out;
    }
    readonly property color plotTone: root.readable(Colors.accent)
    readonly property color tempTone: root.readable(ShellState.cpuTemp >= 80 ? Colors.crit
        : ShellState.cpuTemp >= 68 ? Colors.warn : Colors.accent)
    readonly property color diskTone: root.readable(ShellState.disk >= 92 ? Colors.crit
        : ShellState.disk >= 82 ? Colors.warn : Colors.accent)

    MouseArea { anchors.fill: parent }   // the gap belongs to the panel

    Item {
        id: keys
        anchors.fill: parent
        focus: true
        Keys.onEscapePressed: function (e) {
            ShellState.closePanel();
            e.accepted = true;
        }
    }
    onActiveChanged: if (root.active) keys.forceActiveFocus()

    // ─────────────── one of the house cards ───────────────
    // The same cascade as the Control Centre toggles: it is this shell's own
    // gesture and there was no reason for it to be missing here. As there, the
    // opacity is NOT touched — the NotchLayer already takes care of that, and
    // two chained fades multiply.
    component Card: Rectangle {
        id: card
        property int idx: 0
        radius: Appearance.radM
        color: Colors.surface1
        border.width: 1
        border.color: Colors.hairline

        property real ent: ShellState.mode === "system" ? 1 : 0
        Behavior on ent {
            SequentialAnimation {
                PauseAnimation { duration: ShellState.mode === "system" ? card.idx * 32 : 0 }
                SpringAnimation {
                    spring: Appearance.sprPanel
                    damping: Appearance.dmpPanel
                    epsilon: Appearance.eppScale
                }
            }
        }
        scale: 0.92 + 0.08 * card.ent
        transform: Translate { y: (1 - card.ent) * 10 }
    }

    // ─────────────── one band: series header + its curve ───────────────
    //
    // READING ON THE FLY, NO TOOLTIP. Moving the mouse over the curve snaps a
    // crosshair to the nearest sample, and the value already in the header
    // BECOMES the reading: the big figure turns into that instant's and the
    // note beside it says how long ago it was. A floating tooltip would have
    // been yet another surface on top of a panel that is already a surface on
    // top of the notch, and it would also cover exactly the stretch of curve
    // being looked at. Nothing stays hidden behind the mouse: at rest the
    // figure is the current one, which is the fact that matters.
    component Lane: ColumnLayout {
        id: lane
        property string label: ""
        property string value: ""
        property string note: ""
        property string aside: ""          // only the first band carries the «últimos 90 s» (last 90 s)
        property string unit: " %"
        property color tone: Colors.accent
        property var series: []
        readonly property int ceil: root.ceilFor(lane.series)

        property int hover: -1             // the sample pointed at, or -1
        readonly property bool reading: lane.hover >= 0 && lane.hover < (lane.series ? lane.series.length : 0)

        spacing: 5

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Rectangle {
                Layout.alignment: Qt.AlignVCenter
                width: 6; height: 6; radius: 3
                color: lane.tone
            }
            Text {
                Layout.alignment: Qt.AlignBaseline
                text: lane.label
                color: Colors.label2
                font.family: Appearance.fontUI; font.pixelSize: Appearance.fsXS
            }
            Text {
                Layout.alignment: Qt.AlignBaseline
                Layout.leftMargin: 3
                text: lane.reading
                    ? Math.round(lane.series[lane.hover]) + lane.unit
                    : lane.value
                color: Colors.label
                font.family: Appearance.fontUI; font.pixelSize: 18
                font.weight: Font.DemiBold
                font.features: ({ "tnum": 1 })
            }
            Text {
                Layout.alignment: Qt.AlignBaseline
                Layout.fillWidth: true
                text: lane.reading ? root.agoText(lane.series.length - 1 - lane.hover) : lane.note
                color: Colors.label3; elide: Text.ElideRight
                font.family: Appearance.fontUI; font.pixelSize: Appearance.fsXXS
                font.features: ({ "tnum": 1 })
            }
            Text {
                Layout.alignment: Qt.AlignBaseline
                visible: lane.aside.length > 0
                text: lane.aside
                color: Colors.label3
                font.family: Appearance.fontUI; font.pixelSize: Appearance.fsXXS
            }
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            // Room so the live point at the end does not eat the hairline.
            Layout.rightMargin: 4

            HistoryGraph {
                id: laneGraph
                anchors.fill: parent
                values: lane.series
                ceiling: lane.ceil
                lineColor: lane.tone
                fillTop: Qt.rgba(lane.tone.r, lane.tone.g, lane.tone.b, 0.10)
                fillBottom: Qt.rgba(lane.tone.r, lane.tone.g, lane.tone.b, 0.004)
                showGrid: false
                showBaseline: true
                showPoint: true
                fadeIn: 0.12
                markIndex: lane.hover
            }

            // acceptedButtons: NoButton — this mouse area only listens. If it
            // accepted clicks it would eat the one that closes the panel, which
            // the root MouseArea handles.
            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.NoButton
                onPositionChanged: function (m) { lane.hover = root.sampleAt(m.x, width, lane.series); }
                onExited: lane.hover = -1
            }

            // The axis label, where an axis label goes.
            Text {
                anchors { left: parent.left; top: parent.top }
                text: lane.ceil + " %"
                color: Colors.label3
                font.family: Appearance.fontUI; font.pixelSize: Appearance.fsXXS
                font.features: ({ "tnum": 1 })
            }
        }
    }


    ColumnLayout {
        anchors { fill: parent; leftMargin: 22; rightMargin: 20; topMargin: 20; bottomMargin: 18 }
        spacing: 12

        // ─────────────── header ───────────────
        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            Text {
                text: Icons.cpu
                color: root.headTone
                font.family: Appearance.font; font.pixelSize: 18
                Behavior on color { ColorAnimation { duration: Appearance.mIn; easing.type: Easing.OutCubic } }
            }
            ColumnLayout {
                spacing: 0
                Text {
                    // The same name as the door you come in through from the
                    // Control Centre. A door and a room with different names
                    // are two places.
                    text: I18n.tr("Tu máquina")
                    color: Colors.label
                    font.family: Appearance.fontUI; font.pixelSize: Appearance.fsM; font.weight: Font.DemiBold
                }
                Text {
                    text: root.battLow ? I18n.tr("Batería baja · {0}", ShellState.battEstimateText)
                        : root.hot ? I18n.tr("El procesador está caliente · {0} °C", Math.round(ShellState.cpuTemp))
                        : ShellState.batt >= 0
                            ? I18n.tr("Encendido desde hace {0}  ·  Batería {1} %{2}",
                                      root.uptime(ShellState.uptimeSeconds), ShellState.batt,
                                      ShellState.ac ? I18n.tr(", cargando") : "")
                            : I18n.tr("Encendido desde hace {0}", root.uptime(ShellState.uptimeSeconds))
                    color: root.battLow ? Colors.crit : root.hot ? Colors.warn : Colors.label2
                    elide: Text.ElideRight
                    font.family: Appearance.fontUI; font.pixelSize: Appearance.fsXS
                    font.features: ({ "tnum": 1 })
                    Behavior on color { ColorAnimation { duration: Appearance.mIn; easing.type: Easing.OutCubic } }
                }
            }
            Item { Layout.fillWidth: true }

            // Where Network and Bluetooth put their switch. Here there is
            // nothing to turn on, but there is somewhere you came from: a real
            // button, not a loose bit of grey text.
            Rectangle {
                implicitWidth: backRow.implicitWidth + 24
                implicitHeight: 29
                radius: Appearance.radS
                color: backMa.containsMouse ? Qt.rgba(Colors.accent.r, Colors.accent.g, Colors.accent.b, 0.16)
                                            : Colors.fill3
                Behavior on color { ColorAnimation { duration: Appearance.mQuick; easing.type: Easing.OutQuad } }

                Row {
                    id: backRow
                    anchors.centerIn: parent
                    spacing: 7
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "‹"
                        color: backMa.containsMouse ? Colors.accentInk : Colors.label3
                        font.family: Appearance.fontUI; font.pixelSize: 15
                        Behavior on color { ColorAnimation { duration: Appearance.mQuick; easing.type: Easing.OutQuad } }
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: I18n.tr("Centro de control")
                        color: backMa.containsMouse ? Colors.accentInk : Colors.label
                        font.family: Appearance.fontUI; font.pixelSize: Appearance.fsXS
                        Behavior on color { ColorAnimation { duration: Appearance.mQuick; easing.type: Easing.OutQuad } }
                    }
                }
                MouseArea {
                    id: backMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: ShellState.togglePanel("control")
                }
            }
        }

        Rectangle { Layout.fillWidth: true; height: 1; color: Colors.hairline }

        // ─────────────── body ───────────────
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 14

            // ── left: a minute and a half of activity ──
            // The legend already says what each line is, so there is no title
            // on top («actividad reciente», recent activity) repeating the same
            // thing in lower case.
            Card {
                idx: 0
                Layout.fillWidth: true
                Layout.fillHeight: true

                ColumnLayout {
                    anchors { fill: parent; leftMargin: 18; rightMargin: 18; topMargin: 14; bottomMargin: 14 }
                    spacing: 14

                    Lane {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        label: I18n.tr("Procesador")
                        value: ShellState.cpu + " %"
                        note: I18n.tr("carga {0} · {1} hilos",
                                      root.decimal(ShellState.cpuLoad, 2), ShellState.cpuThreads)
                        aside: I18n.tr("últimos 90 s")
                        tone: root.plotTone
                        series: ShellState.cpuHistory
                    }
                    // Memory does NOT split the height evenly with the
                    // processor. In ninety seconds RAM moves two or three
                    // points: giving it half the card meant devoting the same
                    // space to a straight line as to the only series where
                    // things actually happen. A low strip says «this is here
                    // and it is calm» without shouting, and the processor keeps
                    // the height it needs for its shape to show.
                    // (Height pinned on all three counts for the same reason
                    // as the right-hand column: Lane is a ColumnLayout, and a
                    // layout inside another fills by default — with only
                    // preferredHeight it took the whole card and left the
                    // processor in a slit.)
                    Lane {
                        Layout.fillWidth: true
                        Layout.fillHeight: false
                        Layout.minimumHeight: 96
                        Layout.preferredHeight: 96
                        Layout.maximumHeight: 96
                        label: I18n.tr("Memoria")
                        value: ShellState.mem + " %"
                        note: ShellState.memTotalKib > 0
                            ? I18n.tr("{0} de {1} GiB", root.gibFromKib(ShellState.memUsedKib),
                                      root.gibFromKib(ShellState.memTotalKib))
                            : ""
                        // Same accent as the processor, not the wallpaper's
                        // ink: when the two series shared a card they had to be
                        // told apart by colour, but now each has its own
                        // labelled band and the second tone only served to make
                        // half the card come out a washed-out grey that belongs
                        // nowhere. One accent, as in the rest of the shell.
                        tone: root.plotTone
                        series: ShellState.memHistory
                    }
                }
            }

            // ── right: what changes slowly ──
            // Width pinned on all three counts: a ColumnLayout nested inside a
            // RowLayout fills by default (for layouts fillWidth is true, unlike
            // the rest of the items) and it swallowed the left-hand column
            // whole.
            ColumnLayout {
                Layout.fillWidth: false
                Layout.minimumWidth: 272
                Layout.preferredWidth: 272
                Layout.maximumWidth: 272
                Layout.fillHeight: true
                spacing: 12

                // ── temperature: it has a curve too ──
                Card {
                    id: tempCard
                    idx: 1
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    // Same reading on the fly as the bands on the left.
                    property int hover: -1
                    readonly property bool reading: tempCard.hover >= 0
                        && tempCard.hover < ShellState.tempHistory.length

                    ColumnLayout {
                        anchors { fill: parent; leftMargin: 16; rightMargin: 16; topMargin: 13; bottomMargin: 13 }
                        spacing: 2

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 9
                            Text {
                                text: "󰔏"
                                color: root.tempTone
                                font.family: Appearance.font; font.pixelSize: 15
                                Behavior on color { ColorAnimation { duration: Appearance.mIn; easing.type: Easing.OutCubic } }
                            }
                            Text {
                                Layout.fillWidth: true
                                text: I18n.tr("Temperatura")
                                color: Colors.label2
                                font.family: Appearance.fontUI; font.pixelSize: Appearance.fsXS
                            }
                            Text {
                                text: tempCard.reading
                                    ? Math.round(ShellState.tempHistory[tempCard.hover]) + " °C"
                                    : ShellState.cpuTemp >= 0 ? Math.round(ShellState.cpuTemp) + " °C" : "—"
                                color: Colors.label
                                font.family: Appearance.fontUI; font.pixelSize: 18
                                font.weight: Font.DemiBold
                                font.features: ({ "tnum": 1 })
                            }
                        }

                        // The state comes with a WORD as well as a colour: the
                        // accent comes from pywal and with a low-chroma palette
                        // the jump to «aviso» (warning) is almost invisible. A
                        // state colour cannot be the only channel saying the
                        // state.
                        Text {
                            Layout.fillWidth: true
                            Layout.leftMargin: 24
                            text: tempCard.reading
                                ? root.agoText(ShellState.tempHistory.length - 1 - tempCard.hover)
                                : ShellState.cpuTemp < 0 ? I18n.tr("Sin lectura")
                                : ShellState.cpuTemp < 52 ? I18n.tr("Fresco")
                                : ShellState.cpuTemp < 68 ? I18n.tr("Templado")
                                : ShellState.cpuTemp < 80 ? I18n.tr("Caliente") : I18n.tr("Muy caliente")
                            color: Colors.label3
                            font.family: Appearance.fontUI; font.pixelSize: Appearance.fsXXS
                            font.features: ({ "tnum": 1 })
                        }

                        Item {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            Layout.topMargin: 6
                            Layout.rightMargin: 4

                            HistoryGraph {
                                anchors.fill: parent
                                values: ShellState.tempHistory
                                floor: root.tempRange.lo
                                ceiling: root.tempRange.hi
                                lineColor: root.tempTone
                                fillTop: Qt.rgba(lineColor.r, lineColor.g, lineColor.b, 0.10)
                                fillBottom: Qt.rgba(lineColor.r, lineColor.g, lineColor.b, 0.004)
                                showGrid: false
                                showBaseline: true
                                showPoint: true
                                fadeIn: 0.12
                                markIndex: tempCard.hover
                            }
                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                acceptedButtons: Qt.NoButton
                                onPositionChanged: function (m) {
                                    tempCard.hover = root.sampleAt(m.x, width, ShellState.tempHistory);
                                }
                                onExited: tempCard.hover = -1
                            }
                        }
                    }
                }

                // ── disk space: no history to tell here ──
                // The disk does not move in ninety seconds, so a curve would be
                // a straight line pretending to be a chart. A bar says the same
                // and does not lie about what is underneath.
                Card {
                    idx: 2
                    Layout.fillWidth: true
                    Layout.preferredHeight: 92

                    ColumnLayout {
                        anchors { fill: parent; leftMargin: 16; rightMargin: 16; topMargin: 13; bottomMargin: 13 }
                        spacing: 9

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 9
                            Text {
                                text: "󰋊"
                                color: ShellState.disk >= 92 ? Colors.crit
                                    : ShellState.disk >= 82 ? Colors.warn : Colors.accent
                                font.family: Appearance.font; font.pixelSize: 15
                                Behavior on color { ColorAnimation { duration: Appearance.mIn; easing.type: Easing.OutCubic } }
                            }
                            Text {
                                Layout.fillWidth: true
                                text: I18n.tr("Almacenamiento")
                                color: Colors.label2
                                font.family: Appearance.fontUI; font.pixelSize: Appearance.fsXS
                            }
                            Text {
                                text: ShellState.disk + " %"
                                color: Colors.label
                                font.family: Appearance.fontUI; font.pixelSize: 15
                                font.weight: Font.DemiBold
                                font.features: ({ "tnum": 1 })
                            }
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 3
                            radius: 2
                            // The track is a light step of the SAME tone as
                            // the fill, not a house grey: that way the state
                            // (accent / warning / critical) reads along the
                            // whole bar and not only in the filled part.
                            color: Qt.rgba(root.diskTone.r, root.diskTone.g, root.diskTone.b, 0.18)
                            Rectangle {
                                // The fraction, not the width: the rail widens
                                // with the panel as it opens and animating the
                                // width makes the disk look as if it were
                                // filling up by itself. See the long
                                // explanation in PokeTeamPanel.
                                property real p: Math.max(0, Math.min(1, ShellState.disk / 100))
                                Behavior on p { NumberAnimation { duration: Appearance.mTick; easing.type: Easing.Linear } }

                                height: parent.height
                                radius: parent.radius
                                width: parent.width * p
                                color: root.diskTone
                                Behavior on color { ColorAnimation { duration: Appearance.mIn; easing.type: Easing.OutCubic } }
                            }
                        }

                        Text {
                            Layout.fillWidth: true
                            text: ShellState.diskTotalBytes > 0
                                ? I18n.tr("{0} GiB libres de {1}",
                                          root.gibFromBytes(Math.max(0, ShellState.diskTotalBytes - ShellState.diskUsedBytes)),
                                          root.gibFromBytes(ShellState.diskTotalBytes))
                                : ""
                            color: Colors.label3; elide: Text.ElideRight
                            font.family: Appearance.fontUI; font.pixelSize: Appearance.fsXXS
                            font.features: ({ "tnum": 1 })
                        }
                    }
                }
            }
        }
    }
}
