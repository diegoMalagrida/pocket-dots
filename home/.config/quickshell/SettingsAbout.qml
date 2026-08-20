// SettingsAbout.qml — información del sistema. Una sola pasada de shell, no un
// poll: esto no cambia mientras miras la ventana (salvo el uptime, que se
// refresca al volver a entrar en la sección).
//
// Cada dato lleva su valor también como `hint`, así que si el texto no cabe en
// la fila (el nombre del procesador, por ejemplo) sale entero en la franja del
// pie al pasar por encima.
import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Flickable {
    id: root

    property string note: "Una sola pasada al entrar en la sección; nada de sondeos en bucle."
    readonly property int matchCount: cSw.visibleRows + cHw.visibleRows + cRice.visibleRows

    contentHeight: col.implicitHeight + 34
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded; width: 5 }

    property var info: ({})

    onVisibleChanged: {
        if (!visible) return;
        contentY = 0;
        probe.running = true;
    }

    Process {
        id: probe
        command: ["bash", "-lc", `
            printf 'distro\\t%s\\n' "$(. /etc/os-release 2>/dev/null; echo "$PRETTY_NAME")"
            printf 'kernel\\t%s\\n' "$(uname -r)"
            printf 'wm\\t%s\\n'     "Hyprland $(hyprctl version 2>/dev/null | head -1 | grep -oP '\\d+\\.\\d+\\.\\d+' | head -1)"
            printf 'shell\\t%s\\n'  "Quickshell $(quickshell --version 2>/dev/null | grep -oP '\\d+\\.\\d+\\.\\d+' | head -1)"
            printf 'cpu\\t%s\\n'    "$(awk -F': ' '/model name/{print $2; exit}' /proc/cpuinfo)"
            printf 'ram\\t%s\\n'    "$(free -h --si | awk '/^Mem:/{print $3" de "$2}')"
            printf 'disk\\t%s\\n'   "$(df -h --output=used,size,pcent / | tail -1 | awk '{print $1" de "$2" ("$3")"}')"
            printf 'up\\t%s\\n'     "$(awk '{s=int($1); d=int(s/86400); h=int(s%86400/3600); m=int(s%3600/60);
                                          if(d>0) printf "%d d %d h %d min", d, h, m;
                                          else if(h>0) printf "%d h %d min", h, m;
                                          else printf "%d min", m}' /proc/uptime)"
            printf 'pkgs\\t%s\\n'   "$(pacman -Qq 2>/dev/null | wc -l) paquetes"
        `]
        stdout: SplitParser {
            onRead: function (line) {
                const p = line.split("\t");
                if (p.length < 2) return;
                const o = root.info;
                o[p[0]] = p[1];
                root.info = o;
                root.infoChanged();
            }
        }
    }

    readonly property var hw: [
        { k: "kernel", label: "Kernel" },
        { k: "cpu",    label: "Procesador" },
        { k: "ram",    label: "Memoria" },
        { k: "disk",   label: "Disco raíz" },
        { k: "up",     label: "Encendido desde hace" },
        { k: "pkgs",   label: "Paquetes instalados" }
    ]

    readonly property var sw: [
        { k: "distro", label: "Sistema" },
        { k: "wm",     label: "Compositor" },
        { k: "shell",  label: "Shell" }
    ]

    ColumnLayout {
        id: col
        width: root.width - 48
        x: 24
        y: 16
        spacing: 10

        // ─────────────────── cabecera con el logo ───────────────────
        RowLayout {
            Layout.fillWidth: true
            Layout.bottomMargin: 4
            spacing: 18
            visible: ShellState.settingsQuery.length === 0

            Text {
                text: Icons.arch
                color: Colors.accent
                font.family: Appearance.font
                font.pixelSize: 46
            }
            ColumnLayout {
                spacing: 2
                Text {
                    text: root.info["distro"] || "Arch Linux"
                    color: "#ffffff"
                    font.family: Appearance.fontUI
                    font.pixelSize: 17
                    font.weight: Font.DemiBold
                }
                Text {
                    text: root.info["wm"] || ""
                    color: "#8a8a8a"
                    font.family: Appearance.fontUI
                    font.pixelSize: Appearance.fsS
                }
            }
        }

        SettingsControls.Card_ {
            id: cSw
            title: "SOFTWARE"
            Repeater {
                model: root.sw
                onItemAdded: cSw.recount()
                SettingsControls.Row_ {
                    required property var modelData
                    label: modelData.label
                    hint: root.info[modelData.k] || ""
                    SettingsControls.Val_ { text: root.info[modelData.k] || "…" }
                }
            }
        }

        SettingsControls.Card_ {
            id: cHw
            title: "EQUIPO"
            Repeater {
                model: root.hw
                onItemAdded: cHw.recount()
                SettingsControls.Row_ {
                    required property var modelData
                    label: modelData.label
                    hint: root.info[modelData.k] || ""
                    SettingsControls.Val_ { text: root.info[modelData.k] || "…" }
                }
            }
        }

        SettingsControls.Card_ {
            id: cRice
            title: "ESTE RICE"

            SettingsControls.Row_ {
                label: "Ajustes guardados en"
                hint: "El JSON que escribe la sección Apariencia. Bórralo y todo vuelve a los valores de fábrica."
                SettingsControls.Val_ { text: "~/.config/quickshell-rice.json" }
            }
            SettingsControls.Row_ {
                label: "Código del shell"
                hint: "Barra, notch, paneles, lanzador, selector de fondos y esta misma ventana."
                SettingsControls.Val_ { text: "~/.config/quickshell/" }
            }
            SettingsControls.Row_ {
                label: "Lenguaje de movimiento"
                hint: "La spec de duraciones, curvas y forma que siguen Hyprland y Quickshell."
                SettingsControls.Val_ { text: "~/.config/motion-language.md" }
            }
        }

        SettingsControls.Note_ {
            Layout.topMargin: 10
            visible: ShellState.settingsQuery.length > 0 && !cSw.visible && !cHw.visible && !cRice.visible
            text: "Nada de Acerca de coincide con «" + ShellState.settingsQuery + "»."
        }
    }
}
