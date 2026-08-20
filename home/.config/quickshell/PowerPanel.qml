// PowerPanel.qml — menú de encendido desplegado DESDE el notch.
// Sustituye a wlogout, que tomaba la pantalla completa. Aquí es una fila de
// cinco botones dentro del notch: ←/→ o Tab para moverse, Enter confirma,
// Esc cierra. El foco de teclado lo da TopShell.
//
// Salir, Reiniciar y Apagar piden DOS Enter: el primero arma el boton (se
// pone rojo y su etiqueta pasa a "¿Seguro?"), el segundo ejecuta. Bloquear y
// Suspender no lo piden: no pierdes nada y volver cuesta un tecleo.
// Cualquier cosa que no sea repetir el Enter desarma: moverte a otro boton,
// Esc, o dejarlo quieto unos segundos.
import Quickshell
import QtQuick
import QtQuick.Layouts

Item {
    id: root

    readonly property bool active: ShellState.panel === "power"
    property int current: 0

    readonly property var items: [
        { icon: "󰌾", label: "Bloquear",  cmd: "hyprlock",              danger: false },
        { icon: "󰤄", label: "Suspender", cmd: "systemctl suspend",     danger: false },
        // `exit` a secas ya no vale: desde Hyprland 0.55 el argumento de
        // `dispatch` es una expresion Lua, y un nombre suelto se queda en nil
        // ("expected a dispatcher"). Las comillas simples son necesarias para
        // que los parentesis lleguen enteros a hyprctl; el cmd se ejecuta con
        // `bash -lc`, asi que no se las come nadie por el camino.
        { icon: "󰗽", label: "Salir",     cmd: "hyprctl dispatch 'hl.dsp.exit()'", danger: false, confirm: true  },
        { icon: "󰜉", label: "Reiniciar", cmd: "systemctl reboot",      danger: true,  confirm: true  },
        { icon: "󰐥", label: "Apagar",    cmd: "systemctl poweroff",    danger: true,  confirm: true  }
    ]

    // Indice del boton armado, o -1. Solo lo usan las acciones con
    // confirm: true; el resto se ejecuta al primer Enter como siempre.
    property int armed: -1

    // Un boton armado no se queda armado para siempre: si te distraes y
    // vuelves, el siguiente Enter no te apaga el portatil. No es una
    // duracion de movimiento, es una espera, por eso no sale de Appearance.
    Timer { id: armTimer; interval: 4000; onTriggered: root.armed = -1 }

    function disarm() { root.armed = -1; armTimer.stop(); }

    function select(i) {
        if (i === root.current) return;   // seguir en el mismo boton no desarma
        root.current = i;
        root.disarm();
    }

    function run(i) {
        if (i < 0 || i >= root.items.length) return;
        // Primer Enter sobre una accion destructiva: armar y esperar al segundo.
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

    // Arranca siempre en "Bloquear": lo menos destructivo. Un Enter accidental
    // no puede apagarte el portátil.
    onActiveChanged: if (root.active) { root.current = 0; root.disarm(); keys.forceActiveFocus(); }

    MouseArea { anchors.fill: parent }

    Item {
        id: keys
        anchors.fill: parent
        focus: true
        // Esc con un boton armado solo cancela la confirmacion; el segundo Esc
        // ya cierra el panel. Asi salir de un armado nunca te cierra el menu.
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
                        : bMa.containsMouse ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(1, 1, 1, 0.05)
                    Behavior on color { ColorAnimation { duration: Appearance.mQuick; easing.type: Easing.OutQuad } }
                    scale: bMa.pressed ? 0.95 : 1
                    Behavior on scale { NumberAnimation { duration: Appearance.mQuick; easing.type: Easing.OutCubic } }

                    ColumnLayout {
                        anchors.centerIn: parent
                        spacing: 6
                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            text: btn.modelData.icon
                            color: btn.isArmed ? "#ffffff"
                                : btn.sel ? (btn.modelData.danger ? Colors.crit : Colors.accent) : "#cfcfcf"
                            font.family: Appearance.font; font.pixelSize: 26
                        }
                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            text: btn.isArmed ? "¿Seguro?" : btn.modelData.label
                            color: btn.sel ? "#ffffff" : "#8a8a8a"
                            font.family: Appearance.fontUI; font.pixelSize: 11
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
