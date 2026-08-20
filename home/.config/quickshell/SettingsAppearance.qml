// SettingsAppearance.qml — lo que hasta ahora había que tocar editando QML.
// Todo escribe en Config.qml y se guarda solo en ~/.config/quickshell-rice.json;
// la barra y el notch reaccionan en vivo mientras mueves los sliders.
//
// Las descripciones NO se pintan aquí: van en `hint` y la ventana las enseña en
// la franja del pie cuando pasas el ratón por encima (ver SettingsControls.qml).
// El botón "Restablecer" tampoco: lo pinta la cabecera fija de la ventana a
// partir de `actionText`.
import Quickshell
import Quickshell.Hyprland
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Flickable {
    id: root

    // contrato con SettingsWindow: botón de la cabecera y texto por defecto del pie
    property string actionText: "Restablecer"
    property bool actionDanger: true
    property bool actionConfirm: true
    property string note: "Se guarda solo en ~/.config/quickshell-rice.json"
    readonly property int matchCount: cNotch.visibleRows + cBehav.visibleRows
        + cBar.visibleRows + cFont.visibleRows + cWall.visibleRows
    signal actionRun
    onActionRun: Config.reset()

    contentHeight: col.implicitHeight + 34
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded; width: 5 }
    // volver a una sección con el scroll a medias es desorientador
    onVisibleChanged: if (visible) contentY = 0

    ColumnLayout {
        id: col
        width: root.width - 48
        x: 24
        y: 16
        spacing: 10

        // ─────────────────── forma del notch ───────────────────
        SettingsControls.Card_ {
            id: cNotch
            title: "NOTCH"

            SettingsControls.Row_ {
                label: "Estilo"
                hint: "Notch: pegado al borde con las esquinas invertidas del MacBook. Isla: píldora flotante, redonda por los cuatro lados, como el Dynamic Island."
                SettingsControls.Choice_ {
                    options: ["Notch", "Isla"]
                    current: Config.notchStyle === "island" ? "Isla" : "Notch"
                    onPicked: function (v) { Config.notchStyle = (v === "Isla" ? "island" : "notch"); }
                }
            }

            SettingsControls.Row_ {
                label: "Color"
                hint: "El negro puro es el que imita al MacBook; el del tema sigue a pywal."
                SettingsControls.Choice_ {
                    options: ["Negro", "Tema"]
                    current: Config.notchColor.toString().toLowerCase() === "#000000" ? "Negro" : "Tema"
                    onPicked: function (v) { Config.notchColor = (v === "Negro" ? "#000000" : Colors.bg.toString()); }
                }
            }

            SettingsControls.Row_ {
                label: "Alto de la banda"
                hint: "También es el alto del notch en reposo, y el espacio que se reserva arriba."
                SettingsControls.Slider_ {
                    value: Config.bandH; from: 24; to: 48; suffix: " px"
                    onMoved: function (v) { Config.bandH = Math.round(v); }
                }
            }

            SettingsControls.Row_ {
                label: "Ancho en reposo"
                hint: "Para la hora sola. Si enciendes la fecha o la batería, el notch se ensancha solo."
                SettingsControls.Slider_ {
                    value: Config.idleW; from: 110; to: 380; suffix: " px"
                    onMoved: function (v) { Config.idleW = Math.round(v); }
                }
            }

            SettingsControls.Row_ {
                shown: Config.notchStyle === "island"
                label: "Separación del borde"
                hint: "Cuánto se despega la isla del borde de la pantalla. Sale de la banda reservada, así que no tapa nada."
                SettingsControls.Slider_ {
                    value: Config.islandGap; from: 0; to: 14; suffix: " px"
                    onMoved: function (v) { Config.islandGap = Math.round(v); }
                }
            }

            SettingsControls.Row_ {
                shown: Config.notchStyle !== "island"
                label: "Esquina invertida"
                hint: "El vuelo cóncavo con el que el notch se une al borde de la pantalla."
                SettingsControls.Slider_ {
                    value: Config.flare; from: 0; to: 22; suffix: " px"
                    onMoved: function (v) { Config.flare = Math.round(v); }
                }
            }

            SettingsControls.Row_ {
                label: Config.notchStyle === "island" ? "Redondeo" : "Redondeo inferior"
                hint: "Cuánto se redondean las esquinas del notch cuando está desplegado."
                SettingsControls.Slider_ {
                    value: Config.roundMax; from: 8; to: 40; suffix: " px"
                    onMoved: function (v) { Config.roundMax = Math.round(v); }
                }
            }
        }

        // ─────────────────── qué enseña y cuándo ───────────────────
        SettingsControls.Card_ {
            id: cBehav
            title: "COMPORTAMIENTO"

            SettingsControls.Row_ {
                label: "Retardo del hover"
                hint: "Cuánto hay que quedarse encima antes de que se despliegue. A 0 se abre al cruzar el ratón."
                SettingsControls.Slider_ {
                    value: Config.hoverDelay; from: 0; to: 900; suffix: " ms"
                    onMoved: function (v) { Config.hoverDelay = Math.round(v); }
                }
            }

            SettingsControls.Row_ {
                label: "Fecha en reposo"
                hint: "En reposo el notch enseña solo la hora. Con esto añade también la fecha, y se ensancha solo para que quepa."
                SettingsControls.Switch_ {
                    checked: Config.showDate
                    onToggled: function (v) { Config.showDate = v; }
                }
            }

            SettingsControls.Row_ {
                label: "Batería en el notch"
                hint: "La batería sale siempre al pasar el ratón; esto la deja fija también en reposo."
                SettingsControls.Switch_ {
                    checked: Config.showBattery
                    onToggled: function (v) { Config.showBattery = v; }
                }
            }

            SettingsControls.Row_ {
                label: "Reservar espacio"
                hint: "Si lo apagas, las ventanas suben hasta el borde y el notch queda por encima."
                SettingsControls.Switch_ {
                    checked: Config.reserveSpace
                    onToggled: function (v) { Config.reserveSpace = v; }
                }
            }
        }

        // ─────────────────── barra ───────────────────
        SettingsControls.Card_ {
            id: cBar
            title: "BARRA"

            SettingsControls.Row_ {
                label: "Velo de fondo"
                hint: "A 0 la barra es del todo transparente. Súbelo si con fondos claros no lees los glifos."
                SettingsControls.Slider_ {
                    value: Config.scrimAlpha; from: 0; to: 0.7; decimals: 2
                    onMoved: function (v) { Config.scrimAlpha = v; }
                }
            }

            SettingsControls.Row_ {
                label: "Margen lateral"
                hint: "Cuánto se separan del borde de la pantalla las islas de los extremos."
                SettingsControls.Slider_ {
                    value: Config.sideMargin; from: 4; to: 48; suffix: " px"
                    onMoved: function (v) { Config.sideMargin = Math.round(v); }
                }
            }

            SettingsControls.Row_ {
                label: "Logo de Arch"
                hint: "El glifo de Arch en el extremo izquierdo de la barra."
                SettingsControls.Switch_ { checked: Config.showArch; onToggled: function (v) { Config.showArch = v; } }
            }
            SettingsControls.Row_ {
                label: "Workspaces"
                hint: "Los puntos de escritorio, con el activo alargado."
                SettingsControls.Switch_ { checked: Config.showWorkspaces; onToggled: function (v) { Config.showWorkspaces = v; } }
            }
            SettingsControls.Row_ {
                label: "Nombre de la app"
                hint: "El nombre de la ventana que tienes enfocada."
                SettingsControls.Switch_ { checked: Config.showAppName; onToggled: function (v) { Config.showAppName = v; } }
            }
            SettingsControls.Row_ {
                label: "Bandeja del sistema"
                hint: "Los iconos que publican las apps: nm-applet, rustdesk, etc."
                SettingsControls.Switch_ { checked: Config.showTray; onToggled: function (v) { Config.showTray = v; } }
            }
        }

        // ─────────────────── tipografía ───────────────────
        SettingsControls.Card_ {
            id: cFont
            title: "TIPOGRAFÍA"

            SettingsControls.Row_ {
                label: "Fuente del notch"
                hint: "Proporcional, solo para el texto de dentro del notch. Los iconos van siempre en la Nerd Font."
                SettingsControls.Choice_ {
                    options: Config.fontChoices
                    current: Config.fontUI
                    onPicked: function (v) { Config.fontUI = v; }
                }
            }

            SettingsControls.Row_ {
                label: "Tamaño de la hora"
                hint: "El reloj del notch en reposo."
                SettingsControls.Slider_ {
                    value: Config.clockSize; from: 12; to: 24; suffix: " px"
                    onMoved: function (v) { Config.clockSize = Math.round(v); }
                }
            }
        }

        // ─────────────────── fondo de pantalla ───────────────────
        SettingsControls.Card_ {
            id: cWall
            title: "FONDO"

            SettingsControls.Action_ {
                label: "Cambiar fondo de pantalla"
                hint: "Abre el selector: tus fondos y búsqueda en la web. Al aplicar uno, pywal retematiza el escritorio entero."
                icon: Icons.image
                value: "Super+Shift+W"
                // Este boton ya se ha roto DOS VECES por la misma razon —el
                // texto que se manda no es el que Hyprland espera— y las dos
                // fallo en silencio, sin hacer NADA al pulsarlo. Vale la pena
                // dejar las dos escritas, porque el sintoma es identico:
                //
                // 1. Se mandaba "global,quickshell:wallpaper", copiando la coma
                //    de `bind =`. Por IPC la coma no separa nada: el primer
                //    token ES el nombre del despachador, y "global," no existe.
                // 2. Ya con espacio, "global quickshell:wallpaper" dejo de valer
                //    en Hyprland 0.55: el argumento de `dispatch` pasa a ser una
                //    EXPRESION LUA, y como tal `global quickshell:wallpaper` es
                //    un error de sintaxis. Ahora se llama al despachador de
                //    verdad, `hl.dsp.global`, con el nombre del atajo global que
                //    declara el GlobalShortcut de WallpaperPicker.qml.
                //
                // La moraleja de las dos: si este boton no responde, lo primero
                // es mirar `journalctl --user -u quickshell` o probar el mismo
                // texto con `hyprctl dispatch '...'`, porque el error se queda
                // en Hyprland y no llega a la interfaz.
                onTriggered: Hyprland.dispatch('hl.dsp.global("quickshell:wallpaper")')
            }
        }

        SettingsControls.Note_ {
            Layout.topMargin: 10
            visible: ShellState.settingsQuery.length > 0
                     && !cNotch.visible && !cBehav.visible && !cBar.visible && !cFont.visible && !cWall.visible
            text: "Ningún ajuste de Apariencia coincide con «" + ShellState.settingsQuery + "»."
        }
    }
}
