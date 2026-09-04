// SettingsSystem.qml — los interruptores del sistema que hasta ahora solo
// existían en el centro de control del notch (Super+D).
//
// POR QUÉ REPETIRLOS AQUÍ: el centro de control es para tocar y salir corriendo
// — está pensado para un gesto. Ajustes es para cuando quieres LEER qué hace
// cada cosa antes de tocarla (para eso está la franja del pie) y para lo que no
// cabe en cuatro botones: el estado de la batería, qué red hay, cuántas
// notificaciones tienes. Ninguno de estos ajustes se guarda en el JSON del
// rice: son estado del sistema y los lee ShellState.
import Quickshell
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Flickable {
    id: root

    property string note: I18n.tr("Ajustes del sistema en vivo: no se guardan en el JSON del rice.")
    readonly property int matchCount: cScreen.visibleRows + cPower.visibleRows
        + cNet.visibleRows + cNotif.visibleRows + cTerm.visibleRows

    contentHeight: col.implicitHeight + 34
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded; width: 5 }
    onVisibleChanged: if (visible) contentY = 0

    ColumnLayout {
        id: col
        width: root.width - 48
        x: 24
        y: 16
        spacing: 10

        // ─────────────────── pantalla ───────────────────
        SettingsControls.Card_ {
            id: cScreen
            title: I18n.tr("PANTALLA")

            SettingsControls.Row_ {
                shown: ShellState.bright >= 0
                label: I18n.tr("Brillo")
                hint: I18n.tr("El mismo brillo que las teclas de función, y con el mismo OSD en el notch.")
                SettingsControls.Slider_ {
                    value: Math.max(0, ShellState.bright); from: 0; to: 100; suffix: " %"
                    onMoved: function (v) { ShellState.setBrightness(v); }
                }
            }

            SettingsControls.Row_ {
                label: I18n.tr("Luz nocturna")
                hint: I18n.tr("Baja la temperatura de color a 4000 K con hyprsunset. Súper+Shift+N hace lo mismo.")
                SettingsControls.Switch_ {
                    checked: ShellState.nightLight
                    onToggled: ShellState.toggleNightLight()
                }
            }

            SettingsControls.Row_ {
                label: I18n.tr("Modo lectura")
                hint: I18n.tr("Convierte la pantalla en papel cálido y tinta, añade un grano e-ink estático y pausa animaciones, desenfoque y sombras. Al salir restaura exactamente lo que había antes; no cambia el fondo, pywal ni el brillo.")
                SettingsControls.Switch_ {
                    checked: ShellState.readingMode
                    onToggled: function (v) { ShellState.setReadingMode(v); }
                }
            }
        }

        // ─────────────────── energía ───────────────────
        SettingsControls.Card_ {
            id: cPower
            title: I18n.tr("ENERGÍA")

            // En una torre no hay /sys/class/power_supply/BAT*, así que `batt`
            // vale -1 y esta fila decía "sin batería" para siempre. Contar algo
            // que en ese equipo no puede existir no es honestidad, es un hueco
            // con texto: las tres filas de abajo ya se escondían por lo mismo y
            // esta se quedaba sola presidiéndolas. La tarjeta ENERGÍA no se
            // vacía porque Cafeína y el resto siguen ahí.
            SettingsControls.Row_ {
                shown: ShellState.batt >= 0
                label: I18n.tr("Batería")
                hint: I18n.tr("Carga actual según el kernel, la misma que enseña el notch.")
                SettingsControls.Val_ {
                    text: I18n.tr("{0} % · {1}", ShellState.batt,
                                  ShellState.ac ? I18n.tr("cargando") : I18n.tr("con batería"))
                    color: ShellState.batt < 15 && !ShellState.ac ? Colors.crit : "#b9b9b9"
                }
            }

            SettingsControls.Row_ {
                shown: ShellState.battHealth >= 0 || ShellState.battCycles >= 0
                label: I18n.tr("Salud")
                hint: I18n.tr("Capacidad máxima actual frente a la capacidad de fábrica, según UPower. Los ciclos vienen directamente del contador de la batería.")
                SettingsControls.Val_ {
                    text: {
                        const salud = ShellState.battHealth >= 0
                                    ? ShellState.battHealth.toFixed(0) + " %" : I18n.tr("sin dato");
                        return ShellState.battCycles >= 0
                             ? I18n.tr("{0} · {1} ciclos", salud, ShellState.battCycles) : salud;
                    }
                    color: ShellState.battHealth >= 0 && ShellState.battHealth < 60 ? Colors.crit
                        : ShellState.battHealth >= 0 && ShellState.battHealth < 80 ? Colors.warn : "#b9b9b9"
                }
            }

            SettingsControls.Row_ {
                shown: ShellState.battFullWh > 0
                label: I18n.tr("Capacidad")
                hint: I18n.tr("Energía que admite cargada al máximo frente al diseño original. Se muestra en vatios-hora, no es el porcentaje de carga de ahora.")
                SettingsControls.Val_ {
                    text: ShellState.battDesignWh > 0
                        ? I18n.tr("{0} de {1}", ShellState.fmtWh(ShellState.battFullWh),
                                  ShellState.fmtWh(ShellState.battDesignWh))
                        : ShellState.fmtWh(ShellState.battFullWh)
                }
            }

            SettingsControls.Row_ {
                shown: ShellState.batt >= 0
                label: I18n.tr("Autonomía")
                hint: I18n.tr("Estimación de UPower según el consumo reciente. Puede tardar unos minutos en estabilizarse después de enchufar, desenchufar o despertar el equipo.")
                SettingsControls.Val_ {
                    text: ShellState.battEstimateText
                        + (ShellState.battRateW > 0.05 ? " · " + ShellState.battRateW.toFixed(1) + " W" : "")
                }
            }

            SettingsControls.Row_ {
                label: I18n.tr("Cafeína")
                hint: I18n.tr("Impide que la pantalla se apague y que el equipo se suspenda. Se activa sola al iniciar; apágala desde el notch cuando quieras permitir el reposo.")
                SettingsControls.Switch_ {
                    checked: ShellState.caffeine
                    onToggled: function (v) { ShellState.caffeine = v; }
                }
            }

            SettingsControls.Row_ {
                label: I18n.tr("Modo remoto")
                hint: I18n.tr("Para conectarte por RustDesk desde fuera: deja el bloqueo de sesión pero quita el apagado de pantalla y la suspensión, que es lo que cortaba la conexión.")
                SettingsControls.Switch_ {
                    checked: ShellState.remoteMode
                    onToggled: ShellState.toggleRemoteMode()
                }
            }
        }

        // ─────────────────── red ───────────────────
        SettingsControls.Card_ {
            id: cNet
            title: I18n.tr("RED")

            SettingsControls.Row_ {
                shown: ShellState.hasWifi
                label: I18n.tr("Wi-Fi")
                hint: I18n.tr("Enciende o apaga la radio wifi (NetworkManager).")
                SettingsControls.Switch_ {
                    checked: ShellState.wifiOn
                    onToggled: function (v) { ShellState.setWifi(v); }
                }
            }

            SettingsControls.Action_ {
                label: I18n.tr("Redes disponibles")
                hint: I18n.tr("Abre el selector de redes en el notch. Ajustes se cierra para no taparlo.")
                icon: Icons.wifi
                value: ShellState.wiredDev ? I18n.tr("cable")
                     : ShellState.wifiNet ? ShellState.wifiNet.name
                     : (ShellState.wifiOn || !ShellState.hasWifi) ? I18n.tr("sin conexión") : I18n.tr("apagado")
                onTriggered: {
                    ShellState.settingsOpen = false;
                    ShellState.togglePanel("network");
                }
            }

            SettingsControls.Action_ {
                label: I18n.tr("Perfiles de red")
                hint: I18n.tr("Gestiona perfiles WPA-Enterprise sin enseñar contraseñas en comandos: identidad, método EAP y certificados se guardan mediante NetworkManager.")
                icon: Icons.wifiLock
                value: I18n.tr("EAP y certificados")
                onTriggered: ShellState.openNetworkProfiles()
            }
        }

        // ─────────────────── notificaciones ───────────────────
        SettingsControls.Card_ {
            id: cNotif
            title: I18n.tr("NOTIFICACIONES")

            SettingsControls.Row_ {
                label: I18n.tr("No molestar")
                hint: I18n.tr("Las notificaciones siguen llegando y quedan en el centro de control, pero el notch no las anuncia.")
                SettingsControls.Switch_ {
                    checked: ShellState.dnd
                    onToggled: function (v) { ShellState.dnd = v; }
                }
            }

            SettingsControls.Action_ {
                label: I18n.tr("Vaciar la bandeja")
                hint: I18n.tr("Descarta todas las notificaciones guardadas.")
                icon: Icons.bell
                value: ShellState.notifCount === 0 ? I18n.tr("vacía")
                     : I18n.tr("{0} sin leer", ShellState.notifCount)
                onTriggered: ShellState.clearNotifs()
            }
        }

        // ─────────────────── terminal ───────────────────
        SettingsControls.Card_ {
            id: cTerm
            title: I18n.tr("TERMINAL")

            SettingsControls.Row_ {
                label: I18n.tr("Pokémon del tema")
                hint: I18n.tr("El pokémon que sale al abrir la primera terminal se elige entre los que mejor pegan con la paleta del fondo (tema azul → pokémon azules). Apagado sale uno al azar, como antes.")
                SettingsControls.Switch_ {
                    checked: ShellState.pokeTheme
                    onToggled: ShellState.togglePokeTheme()
                }
            }
        }

        SettingsControls.Note_ {
            Layout.topMargin: 10
            visible: ShellState.settingsQuery.length > 0
                     && !cScreen.visible && !cPower.visible && !cNet.visible
                     && !cNotif.visible && !cTerm.visible
            text: I18n.tr("Ningún ajuste de Sistema coincide con «{0}».", ShellState.settingsQuery)
        }
    }
}
