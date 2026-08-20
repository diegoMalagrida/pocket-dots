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

    property string note: "Ajustes del sistema en vivo: no se guardan en el JSON del rice."
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
            title: "PANTALLA"

            SettingsControls.Row_ {
                shown: ShellState.bright >= 0
                label: "Brillo"
                hint: "El mismo brillo que las teclas de función, y con el mismo OSD en el notch."
                SettingsControls.Slider_ {
                    value: Math.max(0, ShellState.bright); from: 0; to: 100; suffix: " %"
                    onMoved: function (v) { ShellState.setBrightness(v); }
                }
            }

            SettingsControls.Row_ {
                label: "Luz nocturna"
                hint: "Baja la temperatura de color a 4000 K con hyprsunset. Súper+Shift+N hace lo mismo."
                SettingsControls.Switch_ {
                    checked: ShellState.nightLight
                    onToggled: ShellState.toggleNightLight()
                }
            }

            SettingsControls.Row_ {
                label: "Modo lectura"
                hint: "Convierte la pantalla en papel cálido y tinta, añade un grano e-ink estático y pausa animaciones, desenfoque y sombras. Al salir restaura exactamente lo que había antes; no cambia el fondo, pywal ni el brillo."
                SettingsControls.Switch_ {
                    checked: ShellState.readingMode
                    onToggled: function (v) { ShellState.setReadingMode(v); }
                }
            }
        }

        // ─────────────────── energía ───────────────────
        SettingsControls.Card_ {
            id: cPower
            title: "ENERGÍA"

            // En una torre no hay /sys/class/power_supply/BAT*, así que `batt`
            // vale -1 y esta fila decía "sin batería" para siempre. Contar algo
            // que en ese equipo no puede existir no es honestidad, es un hueco
            // con texto: las tres filas de abajo ya se escondían por lo mismo y
            // esta se quedaba sola presidiéndolas. La tarjeta ENERGÍA no se
            // vacía porque Cafeína y el resto siguen ahí.
            SettingsControls.Row_ {
                shown: ShellState.batt >= 0
                label: "Batería"
                hint: "Carga actual según el kernel, la misma que enseña el notch."
                SettingsControls.Val_ {
                    text: ShellState.batt + " % · " + (ShellState.ac ? "cargando" : "con batería")
                    color: ShellState.batt < 15 && !ShellState.ac ? Colors.crit : "#b9b9b9"
                }
            }

            SettingsControls.Row_ {
                shown: ShellState.battHealth >= 0 || ShellState.battCycles >= 0
                label: "Salud"
                hint: "Capacidad máxima actual frente a la capacidad de fábrica, según UPower. Los ciclos vienen directamente del contador de la batería."
                SettingsControls.Val_ {
                    text: (ShellState.battHealth >= 0 ? ShellState.battHealth.toFixed(0) + " %" : "sin dato")
                        + (ShellState.battCycles >= 0 ? " · " + ShellState.battCycles + " ciclos" : "")
                    color: ShellState.battHealth >= 0 && ShellState.battHealth < 60 ? Colors.crit
                        : ShellState.battHealth >= 0 && ShellState.battHealth < 80 ? Colors.warn : "#b9b9b9"
                }
            }

            SettingsControls.Row_ {
                shown: ShellState.battFullWh > 0
                label: "Capacidad"
                hint: "Energía que admite cargada al máximo frente al diseño original. Se muestra en vatios-hora, no es el porcentaje de carga de ahora."
                SettingsControls.Val_ {
                    text: ShellState.fmtWh(ShellState.battFullWh)
                        + (ShellState.battDesignWh > 0 ? " de " + ShellState.fmtWh(ShellState.battDesignWh) : "")
                }
            }

            SettingsControls.Row_ {
                shown: ShellState.batt >= 0
                label: "Autonomía"
                hint: "Estimación de UPower según el consumo reciente. Puede tardar unos minutos en estabilizarse después de enchufar, desenchufar o despertar el equipo."
                SettingsControls.Val_ {
                    text: ShellState.battEstimateText
                        + (ShellState.battRateW > 0.05 ? " · " + ShellState.battRateW.toFixed(1) + " W" : "")
                }
            }

            SettingsControls.Row_ {
                label: "Cafeína"
                hint: "Impide que la pantalla se apague y que el equipo se suspenda. Se activa sola al iniciar; apágala desde el notch cuando quieras permitir el reposo."
                SettingsControls.Switch_ {
                    checked: ShellState.caffeine
                    onToggled: function (v) { ShellState.caffeine = v; }
                }
            }

            SettingsControls.Row_ {
                label: "Modo remoto"
                hint: "Para conectarte por RustDesk desde fuera: deja el bloqueo de sesión pero quita el apagado de pantalla y la suspensión, que es lo que cortaba la conexión."
                SettingsControls.Switch_ {
                    checked: ShellState.remoteMode
                    onToggled: ShellState.toggleRemoteMode()
                }
            }
        }

        // ─────────────────── red ───────────────────
        SettingsControls.Card_ {
            id: cNet
            title: "RED"

            SettingsControls.Row_ {
                shown: ShellState.hasWifi
                label: "Wi-Fi"
                hint: "Enciende o apaga la radio wifi (NetworkManager)."
                SettingsControls.Switch_ {
                    checked: ShellState.wifiOn
                    onToggled: function (v) { ShellState.setWifi(v); }
                }
            }

            SettingsControls.Action_ {
                label: "Redes disponibles"
                hint: "Abre el selector de redes en el notch. Ajustes se cierra para no taparlo."
                icon: Icons.wifi
                value: ShellState.wiredDev ? "cable"
                     : ShellState.wifiNet ? ShellState.wifiNet.name
                     : (ShellState.wifiOn || !ShellState.hasWifi) ? "sin conexión" : "apagado"
                onTriggered: {
                    ShellState.settingsOpen = false;
                    ShellState.togglePanel("network");
                }
            }

            SettingsControls.Action_ {
                label: "Perfiles de red"
                hint: "Gestiona perfiles WPA-Enterprise sin enseñar contraseñas en comandos: identidad, método EAP y certificados se guardan mediante NetworkManager."
                icon: Icons.wifiLock
                value: "EAP y certificados"
                onTriggered: ShellState.openNetworkProfiles()
            }
        }

        // ─────────────────── notificaciones ───────────────────
        SettingsControls.Card_ {
            id: cNotif
            title: "NOTIFICACIONES"

            SettingsControls.Row_ {
                label: "No molestar"
                hint: "Las notificaciones siguen llegando y quedan en el centro de control, pero el notch no las anuncia."
                SettingsControls.Switch_ {
                    checked: ShellState.dnd
                    onToggled: function (v) { ShellState.dnd = v; }
                }
            }

            SettingsControls.Action_ {
                label: "Vaciar la bandeja"
                hint: "Descarta todas las notificaciones guardadas."
                icon: Icons.bell
                value: ShellState.notifCount === 0 ? "vacía" : ShellState.notifCount + " sin leer"
                onTriggered: ShellState.clearNotifs()
            }
        }

        // ─────────────────── terminal ───────────────────
        SettingsControls.Card_ {
            id: cTerm
            title: "TERMINAL"

            SettingsControls.Row_ {
                label: "Pokémon del tema"
                hint: "El pokémon que sale al abrir la primera terminal se elige entre los que mejor pegan con la paleta del fondo (tema azul → pokémon azules). Apagado sale uno al azar, como antes."
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
            text: "Ningún ajuste de Sistema coincide con «" + ShellState.settingsQuery + "»."
        }
    }
}
