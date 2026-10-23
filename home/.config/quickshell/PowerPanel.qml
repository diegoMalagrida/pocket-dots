// PowerPanel.qml — power menu unfolded FROM the notch.
// It replaces wlogout, which took over the whole screen. Here it is a row of
// five buttons inside the notch: ←/→ or Tab to move, Enter confirms, Esc
// closes. TopShell provides the keyboard focus.
//
// Log out, Restart and Shut down ask for TWO Enters: the first arms the button
// (it turns red and its label becomes "¿Seguro?", "Sure?"), the second runs it.
// Lock and Suspend do not ask: you lose nothing and coming back costs one
// keystroke. Anything other than repeating the Enter disarms: moving to another
// button, Esc, or leaving it alone for a few seconds.
import Quickshell
import QtQuick
import QtQuick.Layouts

Item {
    id: root

    readonly property bool active: ShellState.panel === "power"
    property int current: 0

    readonly property var items: [
        { icon: "󰌾", label: I18n.tr("Bloquear"),  cmd: "hyprlock",              danger: false },
        { icon: "󰤄", label: I18n.tr("Suspender"), cmd: "systemctl suspend",     danger: false },
        // Plain `exit` no longer works: since Hyprland 0.55 the argument to
        // `dispatch` is a Lua expression, and a bare name ends up as nil
        // ("expected a dispatcher"). The single quotes are needed so that the
        // parentheses reach hyprctl intact; the cmd runs under `bash -lc`, so
        // nothing eats them along the way.
        { icon: "󰗽", label: I18n.tr("Salir"),     cmd: "hyprctl dispatch 'hl.dsp.exit()'", danger: false, confirm: true  },
        { icon: "󰜉", label: I18n.tr("Reiniciar"), cmd: "systemctl reboot",      danger: true,  confirm: true  },
        { icon: "󰐥", label: I18n.tr("Apagar"),    cmd: "systemctl poweroff",    danger: true,  confirm: true  }
    ]

    // Index of the armed button, or -1. Only the actions with
    // confirm: true use it; the rest run on the first Enter as always.
    property int armed: -1

    // An armed button does not stay armed forever: if you get distracted and
    // come back, the next Enter does not shut the laptop down. It is not a
    // motion duration, it is a wait, which is why it does not come from Appearance.
    Timer { id: armTimer; interval: 4000; onTriggered: root.armed = -1 }

    function disarm() { root.armed = -1; armTimer.stop(); }

    function select(i) {
        if (i === root.current) return;   // staying on the same button does not disarm
        root.current = i;
        root.disarm();
    }

    function run(i) {
        if (i < 0 || i >= root.items.length) return;
        // First Enter on a destructive action: arm and wait for the second.
        if (root.items[i].confirm && root.armed !== i) {
            root.armed = i;
            armTimer.restart();
            return;
        }
        const cmd = root.items[i].cmd;
        root.disarm();
        ShellState.closePanel();
        Quickshell.execDetached(["bash", "-lc", cmd]);
    }
    function move(d) {
        let i = root.current + d;
        if (i < 0) i = root.items.length - 1;
        if (i >= root.items.length) i = 0;
        root.select(i);
    }

    // Always starts on "Bloquear" (Lock): the least destructive. An accidental
    // Enter cannot shut your laptop down.
    onActiveChanged: if (root.active) { root.current = 0; root.disarm(); keys.forceActiveFocus(); }

    MouseArea { anchors.fill: parent }

    Item {
        id: keys
        anchors.fill: parent
        focus: true
        // Esc with a button armed only cancels the confirmation; the second Esc
        // closes the panel. That way leaving an armed state never closes the menu.
        Keys.onEscapePressed: if (root.armed >= 0) root.disarm(); else ShellState.closePanel()
        Keys.onLeftPressed: root.move(-1)
        Keys.onRightPressed: root.move(1)
        Keys.onReturnPressed: root.run(root.current)
        Keys.onEnterPressed: root.run(root.current)
        Keys.onTabPressed: root.move(1)
        Keys.onBacktabPressed: root.move(-1)

        RowLayout {
            anchors { fill: parent; leftMargin: 22; rightMargin: 22; topMargin: 30; bottomMargin: 20 }
            spacing: 12

            Repeater {
                model: root.items

                Rectangle {
                    id: btn
                    required property var modelData
                    required property int index
                    readonly property bool sel: index === root.current
                    readonly property bool isArmed: index === root.armed

                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: 16
                    color: btn.isArmed
                        ? Qt.rgba(Colors.crit.r, Colors.crit.g, Colors.crit.b, 0.52)
                        : btn.sel
                        ? (modelData.danger ? Qt.rgba(Colors.crit.r, Colors.crit.g, Colors.crit.b, 0.26)
                                            : Qt.rgba(Colors.accent.r, Colors.accent.g, Colors.accent.b, 0.26))
                        : bMa.containsMouse ? Colors.fill2 : Colors.fill3
                    Behavior on color { ColorAnimation { duration: Appearance.mQuick; easing.type: Easing.OutQuad } }
                    scale: bMa.pressed ? 0.95 : 1
                    Behavior on scale { NumberAnimation { duration: Appearance.mQuick; easing.type: Easing.OutCubic } }

                    ColumnLayout {
                        anchors.centerIn: parent
                        spacing: 6
                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            text: btn.modelData.icon
                            color: btn.isArmed ? Colors.label
                                : btn.sel ? (btn.modelData.danger ? Colors.crit : Colors.accentInk) : Colors.label
                            font.family: Appearance.font; font.pixelSize: 26
                        }
                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            text: btn.isArmed ? I18n.tr("¿Seguro?") : btn.modelData.label
                            color: btn.sel ? Colors.label : Colors.label3
                            font.family: Appearance.fontUI; font.pixelSize: Appearance.fsXS
                            font.weight: btn.sel ? Font.Medium : Font.Normal
                        }
                    }

                    MouseArea {
                        id: bMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onEntered: root.select(btn.index)
                        onClicked: root.run(btn.index)
                    }
                }
            }
        }
    }
}
