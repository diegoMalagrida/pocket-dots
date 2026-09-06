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
    property string actionText: I18n.tr("Restablecer")
    property bool actionDanger: true
    property bool actionConfirm: true
    property string note: I18n.tr("Se guarda solo en ~/.config/quickshell-rice.json")
    readonly property int matchCount: cLang.visibleRows + cNotch.visibleRows
        + cBehav.visibleRows + cBar.visibleRows + cFont.visibleRows + cFx.visibleRows
        + cWall.visibleRows
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

        // ─────────────────── idioma ───────────────────
        // Va primero porque es lo único de esta página que cambia el resto de
        // la página. Los dos rótulos van cada uno en su idioma a propósito: si
        // abres el shell en un idioma que no lees, "English" se reconoce.
        SettingsControls.Card_ {
            id: cLang
            title: I18n.tr("IDIOMA")

            SettingsControls.Row_ {
                label: I18n.tr("Idioma del shell")
                hint: I18n.tr("Cambia la barra, el notch, los paneles y esta ventana. No toca el idioma del sistema ni el de las aplicaciones: es solo el shell. El cambio es inmediato, no hay que reiniciar nada.")
                SettingsControls.Choice_ {
                    options: I18n.labels
                    current: I18n.labelFor(Config.language)
                    onPicked: function (v) { Config.language = I18n.codeFor(v); Config.save(); }
                }
            }
        }

        // ─────────────────── forma del notch ───────────────────
        SettingsControls.Card_ {
            id: cNotch
            title: I18n.tr("NOTCH")

            SettingsControls.Row_ {
                label: I18n.tr("Estilo")
                hint: I18n.tr("Notch: pegado al borde con las esquinas invertidas del MacBook. Isla: píldora flotante, redonda por los cuatro lados, como el Dynamic Island.")
                SettingsControls.Choice_ {
                    // Se traduce el rótulo, nunca el valor que va al JSON.
                    options: ["Notch", I18n.tr("Isla")]
                    current: Config.notchStyle === "island" ? I18n.tr("Isla") : "Notch"
                    onPicked: function (v) { Config.notchStyle = (v === I18n.tr("Isla") ? "island" : "notch"); }
                }
            }

            SettingsControls.Row_ {
                label: I18n.tr("Color")
                hint: I18n.tr("El negro puro es el que imita al MacBook; el del tema sigue a pywal.")
                SettingsControls.Choice_ {
                    options: [I18n.tr("Negro"), I18n.tr("Tema")]
                    current: Config.notchColor.toString().toLowerCase() === "#000000" ? I18n.tr("Negro") : I18n.tr("Tema")
                    onPicked: function (v) { Config.notchColor = (v === I18n.tr("Negro") ? "#000000" : Colors.bg.toString()); }
                }
            }

            SettingsControls.Row_ {
                label: I18n.tr("Alto de la banda")
                hint: I18n.tr("También es el alto del notch en reposo, y el espacio que se reserva arriba.")
                SettingsControls.Slider_ {
                    value: Config.bandH; from: 24; to: 48; suffix: " px"
                    onMoved: function (v) { Config.bandH = Math.round(v); }
                }
            }

            SettingsControls.Row_ {
                label: I18n.tr("Ancho en reposo")
                hint: I18n.tr("Para la hora sola. Si enciendes la fecha o la batería, el notch se ensancha solo.")
                SettingsControls.Slider_ {
                    value: Config.idleW; from: 110; to: 380; suffix: " px"
                    onMoved: function (v) { Config.idleW = Math.round(v); }
                }
            }

            SettingsControls.Row_ {
                shown: Config.notchStyle === "island"
                label: I18n.tr("Separación del borde")
                hint: I18n.tr("Cuánto se despega la isla del borde de la pantalla. Sale de la banda reservada, así que no tapa nada.")
                SettingsControls.Slider_ {
                    value: Config.islandGap; from: 0; to: 14; suffix: " px"
                    onMoved: function (v) { Config.islandGap = Math.round(v); }
                }
            }

            SettingsControls.Row_ {
                shown: Config.notchStyle !== "island"
                label: I18n.tr("Esquina invertida")
                hint: I18n.tr("El vuelo cóncavo con el que el notch se une al borde de la pantalla.")
                SettingsControls.Slider_ {
                    value: Config.flare; from: 0; to: 22; suffix: " px"
                    onMoved: function (v) { Config.flare = Math.round(v); }
                }
            }

            SettingsControls.Row_ {
                label: Config.notchStyle === "island" ? I18n.tr("Redondeo") : I18n.tr("Redondeo inferior")
                hint: I18n.tr("Cuánto se redondean las esquinas del notch cuando está desplegado.")
                SettingsControls.Slider_ {
                    value: Config.roundMax; from: 8; to: 40; suffix: " px"
                    onMoved: function (v) { Config.roundMax = Math.round(v); }
                }
            }
        }

        // ─────────────────── qué enseña y cuándo ───────────────────
        SettingsControls.Card_ {
            id: cBehav
            title: I18n.tr("COMPORTAMIENTO")

            SettingsControls.Row_ {
                label: I18n.tr("Retardo del hover")
                hint: I18n.tr("Cuánto hay que quedarse encima antes de que se despliegue. A 0 se abre al cruzar el ratón.")
                SettingsControls.Slider_ {
                    value: Config.hoverDelay; from: 0; to: 900; suffix: " ms"
                    onMoved: function (v) { Config.hoverDelay = Math.round(v); }
                }
            }

            SettingsControls.Row_ {
                label: I18n.tr("Fecha en reposo")
                hint: I18n.tr("En reposo el notch enseña solo la hora. Con esto añade también la fecha, y se ensancha solo para que quepa.")
                SettingsControls.Switch_ {
                    checked: Config.showDate
                    onToggled: function (v) { Config.showDate = v; }
                }
            }

            SettingsControls.Row_ {
                label: I18n.tr("Batería en el notch")
                hint: I18n.tr("La batería sale siempre al pasar el ratón; esto la deja fija también en reposo.")
                SettingsControls.Switch_ {
                    checked: Config.showBattery
                    onToggled: function (v) { Config.showBattery = v; }
                }
            }

            SettingsControls.Row_ {
                label: I18n.tr("Reservar espacio")
                hint: I18n.tr("Si lo apagas, las ventanas suben hasta el borde y el notch queda por encima.")
                SettingsControls.Switch_ {
                    checked: Config.reserveSpace
                    onToggled: function (v) { Config.reserveSpace = v; }
                }
            }
        }

        // ─────────────────── barra ───────────────────
        SettingsControls.Card_ {
            id: cBar
            title: I18n.tr("BARRA")

            SettingsControls.Row_ {
                label: I18n.tr("Velo de fondo")
                hint: I18n.tr("A 0 la barra es del todo transparente. Súbelo si con fondos claros no lees los glifos.")
                SettingsControls.Slider_ {
                    value: Config.scrimAlpha; from: 0; to: 0.7; decimals: 2
                    onMoved: function (v) { Config.scrimAlpha = v; }
                }
            }

            SettingsControls.Row_ {
                label: I18n.tr("Margen lateral")
                hint: I18n.tr("Cuánto se separan del borde de la pantalla las islas de los extremos.")
                SettingsControls.Slider_ {
                    value: Config.sideMargin; from: 4; to: 48; suffix: " px"
                    onMoved: function (v) { Config.sideMargin = Math.round(v); }
                }
            }

            SettingsControls.Row_ {
                label: I18n.tr("Logo de Arch")
                hint: I18n.tr("El glifo de Arch en el extremo izquierdo de la barra.")
                SettingsControls.Switch_ { checked: Config.showArch; onToggled: function (v) { Config.showArch = v; } }
            }
            SettingsControls.Row_ {
                label: I18n.tr("Workspaces")
                hint: I18n.tr("Los puntos de escritorio, con el activo alargado.")
                SettingsControls.Switch_ { checked: Config.showWorkspaces; onToggled: function (v) { Config.showWorkspaces = v; } }
            }
            SettingsControls.Row_ {
                label: I18n.tr("Nombre de la app")
                hint: I18n.tr("El nombre de la ventana que tienes enfocada.")
                SettingsControls.Switch_ { checked: Config.showAppName; onToggled: function (v) { Config.showAppName = v; } }
            }
            SettingsControls.Row_ {
                label: I18n.tr("Bandeja del sistema")
                hint: I18n.tr("Los iconos que publican las apps: nm-applet, rustdesk, etc.")
                SettingsControls.Switch_ { checked: Config.showTray; onToggled: function (v) { Config.showTray = v; } }
            }
        }

        // ─────────────────── tipografía ───────────────────
        SettingsControls.Card_ {
            id: cFont
            title: I18n.tr("TIPOGRAFÍA")

            SettingsControls.Row_ {
                label: I18n.tr("Fuente del notch")
                hint: I18n.tr("Proporcional, solo para el texto de dentro del notch. Los iconos van siempre en la Nerd Font.")
                SettingsControls.Choice_ {
                    options: Config.fontChoices
                    current: Config.fontUI
                    onPicked: function (v) { Config.fontUI = v; }
                }
            }

            SettingsControls.Row_ {
                label: I18n.tr("Tamaño de la hora")
                hint: I18n.tr("El reloj del notch en reposo.")
                SettingsControls.Slider_ {
                    value: Config.clockSize; from: 12; to: 24; suffix: " px"
                    onMoved: function (v) { Config.clockSize = Math.round(v); }
                }
            }
        }

        // ─────────────────── efectos del compositor ───────────────────
        // La única tarjeta de la página que no manda sobre algo que pinte el
        // shell: esto es de Hyprland. Por eso el ajuste sale además a
        // ~/.config/hypr/efectos.lua y no solo al JSON que anuncia el pie —
        // el porqué de los dos caminos está en Config.applyEffects().
        SettingsControls.Card_ {
            id: cFx
            title: I18n.tr("EFECTOS")

            SettingsControls.Row_ {
                label: I18n.tr("Desenfoque de movimiento")
                hint: I18n.tr("La ventana se desenfoca hacia donde va, mientras dura la animación. Solo en las transiciones: arrastrar con el ratón ya va 1:1 con tu mano y no deja estela. Si la batería aprieta, este es el primero que apagar.")
                SettingsControls.Switch_ {
                    checked: Config.motionBlur
                    onToggled: function (v) { Config.motionBlur = v; Config.applyEffects(); }
                }
            }

            SettingsControls.Row_ {
                shown: Config.motionBlur
                label: I18n.tr("Muestras")
                hint: I18n.tr("Cuántas copias de la ventana se promedian a lo largo del recorrido. Más muestras, estela más suave y más cara de pintar. No alarga la estela: eso lo decide cuánto se ha movido la ventana.")
                SettingsControls.Slider_ {
                    value: Config.motionBlurSamples; from: 2; to: 24
                    onMoved: function (v) { Config.motionBlurSamples = Math.round(v); Config.applyEffects(); }
                }
            }
        }

        // ─────────────────── fondo de pantalla ───────────────────
        SettingsControls.Card_ {
            id: cWall
            title: I18n.tr("FONDO")

            SettingsControls.Action_ {
                label: I18n.tr("Cambiar fondo de pantalla")
                hint: I18n.tr("Abre el selector: tus fondos y búsqueda en la web. Al aplicar uno, pywal retematiza el escritorio entero.")
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
                     && !cLang.visible && !cNotch.visible && !cBehav.visible && !cBar.visible
                     && !cFont.visible && !cFx.visible && !cWall.visible
            text: I18n.tr("Ningún ajuste de Apariencia coincide con «{0}».", ShellState.settingsQuery)
        }
    }
}
