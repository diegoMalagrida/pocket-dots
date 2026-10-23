// SettingsAppearance.qml — what until now you had to change by editing QML.
// Everything writes into Config.qml and is saved on its own to
// ~/.config/quickshell-rice.json; the bar and the notch react live while you
// move the sliders.
//
// The descriptions are NOT painted here: they go in `hint` and the window shows
// them in the footer strip when you hover over them (see SettingsControls.qml).
// Nor is the "Restablecer" (Reset) button: the window's fixed header paints it
// from `actionText`.
import Quickshell
import Quickshell.Hyprland
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Flickable {
    id: root
    property string tab: "notch"
    readonly property bool searching: ShellState.settingsQuery.trim().length > 0

    // contract with SettingsWindow: header button and default footer text
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
    // coming back to a section with the scroll halfway down is disorienting
    onVisibleChanged: if (visible) contentY = 0

    ColumnLayout {
        id: col
        width: root.width - 48
        x: 24
        y: 16
        spacing: 10

        SettingsBarPreview {
            Layout.fillWidth: true
            Layout.preferredHeight: 112
            visible: !root.searching && (root.tab === "notch" || root.tab === "bar")
        }

        // ─────────────────── language ───────────────────
        // It comes first because it is the only thing on this page that changes the
        // rest of the page. The two labels are each in their own language on purpose:
        // if you open the shell in a language you cannot read, "English" is
        // recognisable.
        SettingsControls.Card_ {
            id: cLang
            visible: visibleRows > 0 && (root.searching || root.tab === "type")
            title: I18n.tr("Idioma")

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

        // ─────────────────── notch shape ───────────────────
        SettingsControls.Card_ {
            id: cNotch
            visible: visibleRows > 0 && (root.searching || root.tab === "notch")
            title: I18n.tr("Notch")

            SettingsControls.Row_ {
                label: I18n.tr("Estilo")
                hint: I18n.tr("Notch: pegado al borde con las esquinas invertidas del MacBook. Isla: píldora flotante, redonda por los cuatro lados, como el Dynamic Island.")
                RowLayout {
                    Layout.preferredWidth: 270
                    spacing: 8
                    Repeater {
                        model: ["notch", "island"]
                        SettingsPreviewTile {
                            required property string modelData
                            caption: modelData === "notch" ? "Notch" : I18n.tr("Isla")
                            selected: Config.notchStyle === modelData
                            onPicked: Config.notchStyle = modelData
                            SettingsBarPreview {
                                anchors.fill: parent
                                attached: modelData === "notch"
                                compact: true
                            }
                        }
                    }
                }
            }

            SettingsControls.Row_ {
                label: I18n.tr("Color")
                hint: I18n.tr("El negro puro es el que imita al MacBook; el del tema sigue a pywal.")
                SettingsControls.Choice_ {
                    options: [I18n.tr("Negro"), I18n.tr("Tema")]
                    current: Config.notchColor.toString().toLowerCase() === "#000000" ? I18n.tr("Negro") : I18n.tr("Tema")
                    // The INTENTION is saved, not today's hex. This used to
                    // write Colors.bg.toString() and the notch kept the colour
                    // of the old palette as soon as you changed wallpaper, with
                    // Settings showing «Tema» (Theme) all the same. See
                    // Colors.notchTint().
                    onPicked: function (v) { Config.notchColor = (v === I18n.tr("Negro") ? "#000000" : Colors.notchTheme); }
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

        // ─────────────────── what it shows and when ───────────────────
        SettingsControls.Card_ {
            id: cBehav
            visible: visibleRows > 0 && (root.searching || root.tab === "notch")
            title: I18n.tr("Comportamiento")

            SettingsControls.Row_ {
                label: I18n.tr("Vista al pasar el ratón")
                hint: I18n.tr("Desactívala para abrir el notch solo al hacer clic. Los avisos y los atajos siguen funcionando.")
                SettingsControls.Switch_ {
                    checked: Config.hoverPreview
                    onToggled: function (v) { Config.hoverPreview = v; }
                }
            }
            SettingsControls.Row_ {
                shown: Config.hoverPreview
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

            // It goes after the date and the battery on purpose: they are the two things
            // the music face hides, so the setting that decides when that face appears
            // sits right next to what it pushes out of the way.
            SettingsControls.Row_ {
                label: I18n.tr("Música del navegador")
                hint: I18n.tr("Apagado, el notch solo cambia de cara con reproductores de música: un vídeo del navegador ya no lo ensancha ni esconde la fecha y la batería. Sigue saliendo en el panel de música, así que puedes pausarlo desde ahí igual.")
                SettingsControls.Switch_ {
                    checked: Config.browserMedia
                    onToggled: function (v) { Config.browserMedia = v; }
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

        // ─────────────────── bar ───────────────────
        SettingsControls.Card_ {
            id: cBar
            visible: visibleRows > 0 && (root.searching || root.tab === "bar")
            title: I18n.tr("Barra")

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
                label: I18n.tr("Organizador visual")
                hint: I18n.tr("Muestra miniaturas de tus escritorios al acercar el cursor al borde izquierdo.")
                SettingsControls.Switch_ { checked: Config.stageEnabled; onToggled: function (v) { Config.stageEnabled = v; } }
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

        // ─────────────────── typography ───────────────────
        SettingsControls.Card_ {
            id: cFont
            visible: visibleRows > 0 && (root.searching || root.tab === "type")
            title: I18n.tr("Tipografía")

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
                    // THE SLIDER SHOWS THE SIZE THE CLOCK USES, NOT THE ONE
                    // YOU DRAG.
                    //
                    // It had thirteen positions and the clock only knew two: with
                    // the Game Boy font on, Appearance.clockPixelSize() quantises to
                    // multiples of 8 (and rightly so, see Appearance.qml:24-38),
                    // so 12-19 were all painted at 16 and 20-24 at 24. You moved
                    // the number from 12 to 24, the preview grew smoothly and the
                    // notch clock did not budge. Right now it is at 17 and is
                    // painted at 16.
                    //
                    // The clock is not quantised: it is quantised HERE, which is
                    // where the lie was. And the minimum comes from Appearance, so
                    // if fontClock goes back to being the interface font this
                    // turns back into a continuous slider by itself.
                    value: Appearance.clockPixelSize(Config.clockSize)
                    from: Appearance.clockQuantum > 1 ? 16 : 12
                    to: 24
                    stepSize: Appearance.clockQuantum
                    suffix: " px"
                    onMoved: function (v) { Config.clockSize = Appearance.clockPixelSize(v); }
                }
            }
        }

        // ─────────────────── compositor effects ───────────────────
        // The only card on the page that does not govern something the shell paints:
        // this belongs to Hyprland. That is why the setting also goes out to
        // ~/.config/hypr/efectos.lua and not only to the JSON the footer announces —
        // the reason for the two paths is in Config.applyEffects().
        SettingsControls.Card_ {
            id: cFx
            visible: visibleRows > 0 && (root.searching || root.tab === "effects")
            title: I18n.tr("Efectos")

            SettingsControls.Row_ {
                label: I18n.tr("Esquinas de las ventanas")
                hint: I18n.tr("Cuánto se redondean las esquinas de las ventanas. A 0 salen cuadradas, que es como nació este escritorio: el foco se dice con luz y no con borde. Hyprland no acepta más de 20.")
                SettingsControls.Slider_ {
                    value: Config.windowRounding
                    from: 0; to: 20
                    stepSize: 1
                    suffix: " px"
                    onMoved: function (v) { Config.windowRounding = Math.round(v); Config.applyEffects(); }
                }
            }

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

        // ─────────────────── wallpaper ───────────────────
        SettingsControls.Card_ {
            id: cWall
            visible: visibleRows > 0 && (root.searching || root.tab === "effects")
            title: I18n.tr("Fondo")

            SettingsControls.Action_ {
                label: I18n.tr("Cambiar fondo de pantalla")
                hint: I18n.tr("Abre el selector: tus fondos y búsqueda en la web. Al aplicar uno, pywal retematiza el escritorio entero.")
                icon: Icons.image
                value: "Super+Shift+W"
                // This button has already broken TWICE for the same reason —the
                // text being sent is not the one Hyprland expects— and both
                // times it failed silently, doing NOTHING when pressed. It is
                // worth keeping both written down, because the symptom is identical:
                //
                // 1. It sent "global,quickshell:wallpaper", copying the comma
                //    from `bind =`. Over IPC the comma separates nothing: the first
                //    token IS the dispatcher name, and "global," does not exist.
                // 2. With a space instead, "global quickshell:wallpaper" stopped
                //    working in Hyprland 0.55: the argument of `dispatch` becomes a
                //    LUA EXPRESSION, and as such `global quickshell:wallpaper` is
                //    a syntax error. Now the real dispatcher is called,
                //    `hl.dsp.global`, with the name of the global shortcut that
                //    WallpaperPicker.qml's GlobalShortcut declares.
                //
                // The moral of both: if this button does not respond, the first
                // thing is to look at `journalctl --user -u quickshell` or try the
                // same text with `hyprctl dispatch '...'`, because the error stays
                // in Hyprland and never reaches the interface.
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
