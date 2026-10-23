// GithubPanel.qml — GitHub activity, unfolded FROM the notch.
//
// Two halves: on top the year of contributions, one square per day, and below
// the latest commits. scripts/github-stats.py brings the data through
// ShellState.github; nothing here talks to the network or touches any token.
//
// The squares are NOT green. They use the pywal accent, like the rest of the
// desktop: a widget that brings its own palette looks stuck on top, not part
// of it. GitHub decides the level (0..4) and here it only grades the opacity.
import Quickshell
import QtQuick
import QtQuick.Layouts

Item {
    id: root

    readonly property bool active: ShellState.panel === "github"

    // Careful with the name: `data` will NOT do, it is the list of children
    // every Item has built in, and QML treats it as read-only.
    readonly property var gh: ShellState.github
    readonly property var weeks: root.gh.weeks || []
    readonly property var counts: root.gh.counts || []

    // Grid geometry (`lado` = side, `aire` = gap). `paso` (step) is what a
    // square takes up with its gap: the MouseArea below divides by it to know
    // which square you are over, so the three numbers must keep agreeing.
    readonly property int lado: 9
    readonly property int aire: 2
    readonly property int paso: root.lado + root.aire

    // Square under the mouse, or -1. Kept here and not in each cell so as not
    // to place 371 MouseAreas: a single one over the grid and a division.
    property int hoverCol: -1
    property int hoverRow: -1

    readonly property bool hovering: root.hoverCol >= 0 && root.hoverRow >= 0
        && root.hoverCol < root.weeks.length
        && (root.counts[root.hoverCol] || [])[root.hoverRow] >= 0

    // The square's date is worked out by adding days to the Sunday the grid
    // starts on, which is the only thing the script sends. 12:00 and not
    // 00:00: where the clock change jumps at midnight that instant does not
    // exist and the day would resolve as the previous one. Same caution as the
    // calendar.
    function fechaDe(col, row) {
        if (!root.gh.start)
            return null;
        const p = root.gh.start.split("-");
        return new Date(parseInt(p[0]), parseInt(p[1]) - 1,
                        parseInt(p[2]) + col * 7 + row, 12);
    }

    function colorDe(nivel) {
        if (nivel < 0)
            return "transparent";              // a day that has not come yet
        if (nivel === 0)
            return Colors.fill3;               // blank day, barely a gap
        const a = [0, 0.30, 0.52, 0.74, 1.0][nivel];
        return Qt.rgba(Colors.accent.r, Colors.accent.g, Colors.accent.b, a);
    }

    // "hace 2 h" (2 h ago). Recomputed when ShellState.github changes, which
    // is when new commits arrive; it does not hang off the shell's clock on
    // purpose, since that ticks every second and would repaint the whole list
    // with nothing new to say.
    function hace(iso) {
        const s = (new Date().getTime() - new Date(iso).getTime()) / 1000;
        if (s < 3600)
            return I18n.tr("hace {0} min", Math.max(1, Math.floor(s / 60)));
        if (s < 86400)
            return I18n.tr("hace {0} h", Math.floor(s / 3600));
        if (s < 604800)
            return I18n.tr("hace {0} d", Math.floor(s / 86400));
        return I18n.tr("hace {0} sem", Math.floor(s / 604800));
    }

    function abrir(url) {
        Quickshell.execDetached(["xdg-open", url]);
    }

    // On opening, fresh data is requested -- ShellState's Timer runs every 15
    // min, and opening the panel is exactly when you want what is happening
    // right now. If the process is already running, githubRefresh() does
    // nothing.
    onActiveChanged: {
        if (root.active) {
            ShellState.githubRefresh();
            keys.forceActiveFocus();
        } else {
            root.hoverCol = -1;
            root.hoverRow = -1;
        }
    }

    // Absorbs clicks that land on empty space: without this they would go
    // outside the panel and the HyprlandFocusGrab would close it.
    MouseArea {
        anchors.fill: parent
    }

    Item {
        id: keys
        anchors.fill: parent
        focus: true
        Keys.onEscapePressed: ShellState.closePanel()
        // A manual refresh, so you do not have to wait for the quarter hour.
        Keys.onPressed: function (e) {
            if (e.key === Qt.Key_R) {
                ShellState.githubRefresh();
                e.accepted = true;
            }
        }
    }

    ColumnLayout {
        anchors {
            fill: parent
            leftMargin: 21
            rightMargin: 21
            topMargin: 18
            bottomMargin: 16
        }
        spacing: 0

        // ─────────────── header: who and how much ───────────────
        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Text {
                text: Icons.github
                color: Colors.accentInk
                font.family: Appearance.font
                font.pixelSize: 15
            }

            Text {
                text: root.gh.login || I18n.tr("GitHub")
                color: Colors.label
                font.family: Appearance.fontUI
                font.pixelSize: Appearance.fsL
            }

            Item { Layout.fillWidth: true }

            // When the data comes from the cache it says so, instead of
            // showing yesterday's numbers as if they were current.
            Text {
                text: root.gh.stale ? I18n.tr("sin conexión")
                    : ShellState.githubLoading ? I18n.tr("actualizando…")
                    : I18n.tr("{0} contribuciones este año", root.gh.total || 0)
                color: root.gh.stale ? Colors.warn : Colors.label3
                font.family: Appearance.fontUI
                font.pixelSize: Appearance.fsXS
                font.features: ({ "tnum": 1 })   // the total refreshes by itself: keep it from jiggling
            }
        }

        // ─────────────── the year grid ───────────────
        Item {
            Layout.topMargin: 14
            Layout.alignment: Qt.AlignHCenter
            implicitWidth: 16 + root.weeks.length * root.paso - root.aire
            implicitHeight: 12 + 7 * root.paso - root.aire

            // Day initials. Only three, alternating, as GitHub does: with all
            // seven, none can be read at a 9 px step.
            Repeater {
                model: [1, 3, 5]
                Text {
                    required property var modelData
                    x: 0
                    y: 12 + modelData * root.paso - 2
                    width: 14
                    // GitHub's grid ALWAYS starts on Sunday, whatever the
                    // locale says, so the row is the day of the week as is:
                    // 0 Sunday, 1 Monday...
                    text: ShellState.loc.dayName(modelData, Locale.NarrowFormat)
                    color: Colors.label3
                    font.family: Appearance.fontUI
                    font.pixelSize: Appearance.fsXXS
                }
            }

            // The months, above the column they start in.
            Repeater {
                model: root.weeks.length
                Text {
                    id: mes
                    required property int index
                    readonly property var f: root.fechaDe(index, 0)
                    readonly property var fPrev: index > 0 ? root.fechaDe(index - 1, 0) : null
                    // The label is only painted on the month's first column,
                    // and never on the last: it would not fit and would spill
                    // out of the panel.
                    visible: mes.f && (!mes.fPrev || mes.f.getMonth() !== mes.fPrev.getMonth())
                             && index < root.weeks.length - 3
                    x: 16 + index * root.paso
                    y: 0
                    text: mes.f ? ShellState.capitalize(
                              mes.f.toLocaleDateString(ShellState.loc, "MMM")) : ""
                    color: Colors.label3
                    font.family: Appearance.fontUI
                    font.pixelSize: Appearance.fsXXS
                }
            }

            // One column per week, seven squares each.
            Repeater {
                model: root.weeks.length

                Item {
                    id: col
                    required property int index
                    readonly property var niveles: root.weeks[index] || []
                    x: 16 + index * root.paso
                    y: 12
                    width: root.lado
                    height: 7 * root.paso - root.aire

                    Repeater {
                        model: 7
                        Rectangle {
                            required property int index
                            y: index * root.paso
                            width: root.lado
                            height: root.lado
                            radius: 2
                            color: root.colorDe(col.niveles[index] !== undefined
                                                ? col.niveles[index] : -1)
                            // The hovered square is lifted with a border
                            // instead of changing colour: colour ALREADY means
                            // how much you did that day and cannot be reused.
                            border.width: root.hoverCol === col.index && root.hoverRow === index ? 1 : 0
                            border.color: Colors.fg
                        }
                    }
                }
            }

            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onPositionChanged: function (m) {
                    const c = Math.floor((m.x - 16) / root.paso);
                    const r = Math.floor((m.y - 12) / root.paso);
                    root.hoverCol = (m.x >= 16 && c >= 0 && c < root.weeks.length) ? c : -1;
                    root.hoverRow = (m.y >= 12 && r >= 0 && r < 7) ? r : -1;
                }
                onExited: {
                    root.hoverCol = -1;
                    root.hoverRow = -1;
                }
                onClicked: if (root.gh.login)
                    root.abrir("https://github.com/" + root.gh.login)
            }
        }

        // ─────────────── grid footer ───────────────
        // The same line for two things: at rest the summary, and when you
        // hover over a square, that day. A floating tooltip would cover the
        // grid right where you are looking.
        Text {
            Layout.topMargin: 9
            Layout.alignment: Qt.AlignHCenter
            text: {
                if (root.hovering) {
                    const f = root.fechaDe(root.hoverCol, root.hoverRow);
                    const n = root.counts[root.hoverCol][root.hoverRow];
                    const dia = f ? f.toLocaleDateString(ShellState.loc, "d MMM") : "";
                    return n === 0 ? I18n.tr("{0} · nada", dia)
                        : n === 1 ? I18n.tr("{0} · 1 contribución", dia)
                        : I18n.tr("{0} · {1} contribuciones", dia, n);
                }
                if (root.gh.stale && !root.gh.total)
                    return I18n.tr("No se pudo hablar con GitHub");
                const r = root.gh.streak || 0;
                const h = root.gh.today || 0;
                return (r === 1 ? I18n.tr("racha de 1 día")
                                : I18n.tr("racha de {0} días", r))
                     + "  ·  " + (h === 1 ? I18n.tr("1 hoy") : I18n.tr("{0} hoy", h));
            }
            color: root.hovering ? Colors.label : Colors.label3
            font.family: Appearance.fontUI
            font.pixelSize: Appearance.fsXS
            font.features: ({ "tnum": 1 })   // the streak and the "hoy" (today) count refresh by themselves
        }

        Rectangle {
            Layout.topMargin: 13
            Layout.fillWidth: true
            implicitHeight: 1
            color: Colors.hairline
        }

        // ─────────────── the latest commits ───────────────
        Text {
            Layout.topMargin: 11
            text: I18n.tr("Últimos commits")
            color: Colors.label3
            font.family: Appearance.fontUI
            font.pixelSize: Appearance.fsXXS
        }

        Repeater {
            model: (root.gh.commits || []).slice(0, 5)

            // One Item per row, and the RowLayout INSIDE. The MouseArea that
            // covers the whole row needs anchors, and a direct child of a
            // ColumnLayout cannot use them: the layout positions it and Qt
            // warns that the result is undefined.
            Item {
                id: fila
                required property var modelData
                Layout.fillWidth: true
                Layout.topMargin: 6
                implicitHeight: filaRow.implicitHeight

            RowLayout {
                id: filaRow
                anchors.fill: parent
                spacing: 9

                Text {
                    text: fila.modelData.repo
                    color: Colors.accentInk
                    font.family: Appearance.fontUI
                    font.pixelSize: Appearance.fsS
                    elide: Text.ElideRight
                    Layout.maximumWidth: 150
                }

                // The padlock is not decoration: the list mixes public and
                // private repos, and it is worth knowing what you are showing
                // if someone is looking at the screen.
                Text {
                    visible: fila.modelData.priv
                    text: Icons.lock
                    color: Colors.label3
                    font.family: Appearance.font
                    font.pixelSize: Appearance.fsXXS
                }

                Text {
                    Layout.fillWidth: true
                    text: fila.modelData.msg
                    color: filaMa.containsMouse ? Colors.label : Colors.label2
                    Behavior on color { ColorAnimation { duration: Appearance.mQuick; easing.type: Easing.OutQuad } }
                    font.family: Appearance.fontUI
                    font.pixelSize: Appearance.fsS
                    elide: Text.ElideRight
                }

                Text {
                    text: root.hace(fila.modelData.when)
                    color: Colors.label3
                    font.family: Appearance.fontUI
                    font.pixelSize: Appearance.fsXS
                    font.features: ({ "tnum": 1 })   // "hace 2 h" (2 h ago) recomputes by itself
                }

            }

                MouseArea {
                    id: filaMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: if (root.gh.login)
                        root.abrir("https://github.com/" + root.gh.login
                                   + "/" + fila.modelData.repo)
                }
            }
        }

        // Empty state: first load, or GitHub down with no cache.
        Text {
            Layout.topMargin: 10
            Layout.alignment: Qt.AlignHCenter
            visible: (root.gh.commits || []).length === 0
            text: ShellState.githubLoading ? I18n.tr("Cargando…")
                                           : I18n.tr("Ningún commit reciente")
            color: Colors.label3
            font.family: Appearance.fontUI
            font.pixelSize: Appearance.fsS
        }

        Item { Layout.fillHeight: true }
    }
}
