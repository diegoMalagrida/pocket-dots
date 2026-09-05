// TopShell.qml — la superficie superior: notch protagonista + barra mínima.
//
// Filosofía:
//   · El notch es la ÚNICA forma de la pantalla. Isla negra suelta, pegada al
//     borde superior, con las esquinas superiores invertidas del MacBook.
//   · La barra NO es una superficie: no tiene fondo, ni franja, ni islas. Son
//     glifos sueltos sobre el fondo de pantalla, alineados con el notch.
//   · En reposo el notch mide EXACTAMENTE la banda reservada (32 px), así que
//     no tapa nada. Solo sobresale cuando tú lo provocas.
//   · La barra enseña ESTADO; el panel del notch tiene los CONTROLES.
//
//        Arch  ●━● ●   Kitty          ╭──────╮        󰤨 󰕾 󰁹 50%  16:23
//                                     │      │
//                                     ╰──────╯
//
// Una sola ventana (enfoque caelestia/drawers): un estado, una máscara, un
// manejo de pantalla completa. Datos y estado en ShellState.qml.
// Probar aislado:  qs -p ~/.config/quickshell/TopShell.qml
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Services.SystemTray
import QtQuick
import QtQuick.Shapes
import QtQuick.Effects
import QtQuick.Layouts

Scope {
    id: root

    // ═══════════════════════ aspecto ═══════════════════════
    readonly property int barH: ShellState.bandH       // banda reservada = alto del notch en reposo
    readonly property color notchColor: Config.notchColor
    readonly property int sideMargin: Config.sideMargin
    readonly property int flare: Config.flare           // radio de la esquina superior invertida
    readonly property int roundMax: Config.roundMax     // radio inferior del notch
    // Modo isla: la píldora se despega del borde y se redondea por los cuatro
    // lados. El hueco de arriba sale de la banda reservada, así que sigue sin
    // tapar ventanas.
    readonly property bool island: Config.island
    // Una sola fuente: los paneles que calculan su alto exacto (el lanzador) lo
    // descuentan desde ShellState, así que el hueco se define allí.
    readonly property real topGap: ShellState.notchTopGap
    readonly property real kArc: 0.5523

    // Velo opcional bajo la barra. 0 = barra 100 % transparente (por defecto).
    readonly property real scrimAlpha: Config.scrimAlpha

    readonly property int maxH: 546                    // Super+D es ahora la cara más alta (526 px)

    property bool shown: true

    // ver la nota del HyprlandFocusGrab más abajo
    property bool grabArmed: false
    Timer { id: grabArm; interval: 400; onTriggered: root.grabArmed = true }
    Connections {
        target: ShellState
        function onPanelChanged() {
            root.grabArmed = false;
            if (ShellState.panel !== "") grabArm.restart(); else grabArm.stop();
        }
    }

    // ═══════════════════════ atajos e IPC ═══════════════════════
    GlobalShortcut { name: "notch"; description: I18n.tr("Centro de control"); onPressed: ShellState.togglePanel("control") }
    GlobalShortcut { name: "launcher"; description: I18n.tr("Lanzador de aplicaciones"); onPressed: ShellState.togglePanel("launcher") }
    // El lanzador abierto directamente en un modo. Tienen atajo propio los dos
    // que YA lo tenían cuando eran menús de rofi —Super+Shift+V para el
    // portapapeles y Super+Alt+Space para el menú de comandos—: cambiar por
    // dentro cómo se pintan no es motivo para quitarle a nadie una tecla que ya
    // tiene aprendida. Las ventanas no estrenan atajo: se llega escribiendo "@",
    // que es la costumbre nueva que interesa enseñar.
    GlobalShortcut { name: "clipboard"; description: I18n.tr("Historial del portapapeles"); onPressed: ShellState.openLauncher("clip") }
    GlobalShortcut { name: "actions"; description: I18n.tr("Acciones del sistema"); onPressed: ShellState.openLauncher("cmd") }
    GlobalShortcut { name: "power"; description: I18n.tr("Menú de encendido"); onPressed: ShellState.togglePanel("power") }
    GlobalShortcut { name: "overview"; description: I18n.tr("Mapa de escritorios"); onPressed: ShellState.togglePanel("overview") }
    GlobalShortcut { name: "network"; description: I18n.tr("Selector de red"); onPressed: ShellState.togglePanel("network") }
    GlobalShortcut { name: "bluetooth"; description: I18n.tr("Dispositivos bluetooth"); onPressed: ShellState.togglePanel("bluetooth") }
    GlobalShortcut { name: "system"; description: I18n.tr("Estado del equipo"); onPressed: ShellState.togglePanel("system") }
    GlobalShortcut { name: "calendar"; description: I18n.tr("Calendario del mes"); onPressed: ShellState.togglePanel("calendar") }
    GlobalShortcut { name: "bar"; description: I18n.tr("Ocultar/mostrar la barra y el notch"); onPressed: root.shown = !root.shown }
    GlobalShortcut {
        name: "notchstyle"
        description: I18n.tr("Alternar notch / isla")
        // Sin aviso de texto: que el notch cambie de forma ya es la confirmación.
        onPressed: Config.notchStyle = Config.island ? "notch" : "island"
    }

    IpcHandler {
        target: "notch"
        function toggle(): void { ShellState.togglePanel("control"); }
        function control(): void { ShellState.togglePanel("control"); }
        function power(): void { ShellState.togglePanel("power"); }
        function network(): void { ShellState.togglePanel("network"); }
        function bluetooth(): void { ShellState.togglePanel("bluetooth"); }
        function system(): void { ShellState.togglePanel("system"); }
        function settings(): void { ShellState.toggleSettings(); }
        // Ajustes abiertos ya en el mapa de atajos: lo mismo que Super+K.
        function keys(): void { ShellState.openSettingsAt("keys"); }
        function style(): void { Config.notchStyle = Config.island ? "notch" : "island"; }
        function launcher(): void { ShellState.togglePanel("launcher"); }
        // El lanzador en un modo concreto: "apps" | "clip" | "cmd" | "win".
        // Cualquier otra cosa entra en "apps", que es la puerta de siempre.
        function open(mode: string): void {
            const ok = ["apps", "clip", "cmd", "win"];
            ShellState.openLauncher(ok.indexOf(mode) >= 0 ? mode : "apps");
        }
        function clipboard(): void { ShellState.openLauncher("clip"); }
        function overview(): void { ShellState.togglePanel("overview"); }
        function close(): void { ShellState.closePanel(); }

        // Apuntar y devolver el panel abierto. Lo usa la captura de pantalla
        // (~/.config/hypr/scripts/capture-region.sh): para poder fotografiar el
        // notch hay que congelar la pantalla, congelar manda el foco fuera, y
        // eso cancela el HyprlandFocusGrab -> el panel se cierra por debajo de
        // la foto. Se apunta cuál era y se vuelve a abrir al terminar, así que
        // hacer una captura deja de ser algo que te cierra lo que estabas
        // mirando.
        function current(): string { return ShellState.panel; }
        function restore(name: string): void {
            if (name !== "" && ShellState.panel !== name) ShellState.togglePanel(name);
        }
        function bright(dir: string): void { ShellState.stepBrightness(dir); }
        // Ahora acepta cualquiera de las caras transitorias por su nombre, no
        // solo tres. Sirve para provocarlas desde un script y, sobre todo, para
        // poder VERLAS al tocar el diseño sin tener que enchufar un cargador o
        // esperar a que cambie la canción.
        function osd(kind: string): void {
            const ok = ["volume", "brightness", "track", "charge", "ws", "toast", "notif"];
            ShellState.flash(ok.indexOf(kind) >= 0 ? kind : "volume");
        }
        // Emparejamiento bluetooth. Lo llama scripts/bt-agent.py, que es quien
        // recibe las preguntas de BlueZ (QML no puede exportar objetos D-Bus).
        //   kind: "confirm" | "display" | "authorize"
        //   entered: dígitos ya tecleados, solo en "display"; -1 si no aplica
        function btask(kind: string, name: string, code: string, entered: int): void {
            const ok = ["confirm", "display", "authorize"];
            if (ok.indexOf(kind) < 0) return;
            ShellState.btAsk(kind, name, code, entered);
        }
        function btclear(): void { ShellState.btClear(); }

        // Temporizador: "10m", "1h30", "90s"… y "stop" para cancelarlo.
        // Lo mismo que escribirlo en el lanzador, pero desde un script: al
        // final de un `make`, de una copia de seguridad, de lo que sea.
        function timer(spec: string): void {
            if (spec === "stop" || spec === "off" || spec === "") { ShellState.timerClear(); return; }
            const secs = ShellState.parseDuration(spec);
            if (secs > 0) ShellState.timerStart(secs);
        }
    }

    // ═══════════════════════ la ventana ═══════════════════════
    // Una superficie POR PANTALLA. Variants instancia el delegado una vez por
    // monitor y lo destruye al desenchufarlo, así que enchufar o quitar una
    // pantalla no necesita recargar la shell.
    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: win

            // ── esta ventana pertenece a UNA pantalla ──────────────────────────
            // Variants crea una copia por monitor; modelData es la pantalla de esta.
            required property var modelData
            screen: modelData

            // La pantalla con el foco es la que manda: solo ahí se despliega el
            // notch, salen los paneles y se pide teclado. En las demás la barra y el
            // notch siguen ahí, pero en reposo.
            readonly property bool primary: modelData.name === ShellState.focusedMon

            // El monitor de Hyprland que corresponde a ESTA pantalla. Se busca
            // por nombre dentro de Hyprland.monitors (que es un modelo vivo) y
            // NO con Hyprland.monitorFor(): monitorFor es un método, así que un
            // binding sobre él no se reevalúa al enchufar o quitar una salida y
            // se quedaría apuntando a un monitor que ya no existe.
            readonly property var hlMon: {
                const ms = Hyprland.monitors ? Hyprland.monitors.values : [];
                for (let i = 0; i < ms.length; i++)
                    if (ms[i] && ms[i].name === modelData.name) return ms[i];
                return null;
            }

            // Cara que pinta esta pantalla. Las que no tienen el foco se quedan
            // siempre en la de reposo (el reloj, o la de música si suena algo), así
            // que enseñan la hora sin heredar los despliegues de la otra pantalla.
            readonly property string faceMode: win.primary ? ShellState.mode
                : (ShellState.mediaLive ? "media" : "idle")
            readonly property int faceW: win.primary ? ShellState.notchW : ShellState.restW
            readonly property int faceH: win.primary ? ShellState.notchH : ShellState.bandH

            // El apartarse por pantalla completa es de la pantalla que la tiene, no
            // de todas: un vídeo a pantalla completa aquí no debe borrar la barra de
            // la otra pantalla.
            property real fsProg: (ShellState.fullscreen && win.primary) ? 1 : 0
            Behavior on fsProg { NumberAnimation { duration: Appearance.mIn; easing.type: Easing.OutCubic } }
            readonly property bool fsHidden: ShellState.fullscreen && win.primary
            visible: root.shown
            anchors { top: true; left: true; right: true }
            implicitHeight: root.maxH + 40
            exclusiveZone: (win.fsHidden || !Config.reserveSpace) ? 0 : root.barH
            color: "transparent"
            // Top, no Overlay: rofi, wlogout y hyprlock deben salir por encima.
            WlrLayershell.layer: WlrLayer.Top
            WlrLayershell.namespace: "quickshell:bar"
            // Teclado solo para los paneles que lo necesitan; el resto del tiempo la
            // capa no debe robar foco a las ventanas.
            // OnDemand, NO Exclusive: con Exclusive el foco se queda pegado y
            // Hyprland ya no cancela el HyprlandFocusGrab, así que un clic fuera no
            // cerraba el panel y te quedabas atrapado dentro. Con OnDemand es el
            // propio grab el que fuerza el foco de teclado, y al hacer clic fuera se
            // cancela y el panel se cierra.
            WlrLayershell.keyboardFocus: win.primary && (ShellState.panel === "launcher" || ShellState.panel === "power"
                                          || ShellState.panel === "network" || ShellState.panel === "bluetooth"
                                          || ShellState.panel === "overview" || ShellState.panel === "system"
                                          || ShellState.panel === "calendar")
                ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

            // La máscara cubre SOLO el notch y los dos grupos de glifos. El resto de
            // la banda deja pasar el ratón: la barra no es una superficie.
            mask: win.fsHidden ? nothing : shellRegion

            Region { id: nothing; width: 0; height: 0 }
            Region {
                id: shellRegion
                item: notch
                Region { item: leftGroup; intersection: Intersection.Combine }
                Region { item: rightGroup; intersection: Intersection.Combine }
                // La burbuja va por coordenadas y no por `item:` porque necesita
                // MEDIR CERO cuando no hay nada que enseñar. Con `item:` la zona de
                // ratón seguiría ahí aunque la burbuja fuera invisible, y te
                // comerías los clics en un trozo de escritorio de 28 px al lado del
                // notch sin ver por qué.
                Region {
                    intersection: Intersection.Combine
                    x: Math.floor(bubble.x); y: Math.floor(bubble.y)
                    width: ShellState.bubbleOn ? Math.ceil(bubble.width) : 0
                    height: ShellState.bubbleOn ? Math.ceil(bubble.height) : 0
                }
            }

            // "Clic fuera = cerrar".
            // OJO: al abrir un panel cambia keyboardFocus, la capa se reconfigura y
            // Hyprland cancela el grab al instante -> el panel se cerraba solo nada
            // más abrirlo. Por eso el grab se arma con retardo, cuando la capa ya
            // se ha asentado.
            HyprlandFocusGrab {
                windows: [win]
                active: ShellState.open && root.grabArmed && win.primary
                onCleared: ShellState.closePanel()
            }

            IdleInhibitor { window: win; enabled: ShellState.caffeine && win.primary }

            Item {
                id: surface
                width: parent.width
                height: root.maxH
                y: -(root.maxH) * win.fsProg
                opacity: 1 - win.fsProg

                // Velo suave (desactivado por defecto)
                Rectangle {
                    anchors { left: parent.left; right: parent.right; top: parent.top }
                    height: root.barH + 12
                    visible: root.scrimAlpha > 0
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: Qt.rgba(0, 0, 0, root.scrimAlpha) }
                        GradientStop { position: 1.0; color: "transparent" }
                    }
                }

                // ══════════════ barra: izquierda ══════════════
                RowLayout {
                    id: leftGroup
                    anchors { left: parent.left; leftMargin: root.sideMargin; top: parent.top }
                    height: root.barH
                    spacing: 2

                    BarItem {
                        visible: Config.showArch
                        icon: Icons.arch
                        iconSize: Appearance.fsL
                        iconColor: Colors.accent
                        hpad: 7
                        onClicked: ShellState.togglePanel("launcher")
                        onScrolled: function (d) { ShellState.nudgeVolume(d); }
                    }

                    // El indicador de escritorio VIAJA.
                    //
                    // Antes cada punto animaba su propio ancho por su cuenta: al
                    // saltar del 1 al 3, uno encogía y otro crecía a la vez y no
                    // había ningún gesto que los uniera — dos animaciones sueltas
                    // ocurriendo cerca, no un recorrido.
                    //
                    // Ahora hay UNA sola píldora que se estira hacia el destino y
                    // se recoge al llegar, cubriendo por el camino los puntos que
                    // salta. Los puntos son de ancho FIJO, así que la fila no se
                    // recoloca a media animación (era eso lo que impedía que la
                    // píldora pudiera viajar: el suelo se movía bajo sus pies).
                    Item {
                        id: wsGroup
                        visible: Config.showWorkspaces
                        Layout.alignment: Qt.AlignVCenter
                        Layout.leftMargin: 0
                        property int hovered: -1        // que punto senala el raton
                        // La pildora es mas estrecha y los puntos estan mas
                        // separados que antes, y no es estetica: es lo que hace
                        // posible el fluido. Con pildora 22 y separacion 8 quedaba
                        // 1 px entre la pildora y el punto vecino, asi que estaban
                        // FUNDIDOS EN REPOSO -- y si ya estan pegados, no hay nada
                        // que fundirse al pasar. Ahora hay ~7 px de aire: cuerpos
                        // separados que se unen solo cuando la pildora llega.
                        readonly property int pill: 18
                        readonly property int pad: (pill - 8) / 2   // lo que sobresale la píldora por los extremos
                        implicitWidth: wsRow.implicitWidth + pill - 8
                        implicitHeight: 8

                        Row {
                            id: wsRow
                            x: wsGroup.pad
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 12
                            Repeater {
                                id: wsRepeater
                                // Hyprland mete en esta lista los workspaces
                                // ESPECIALES (scratchpads, p.ej. el special:ia del
                                // panel de IA). Tienen id NEGATIVO, y como la lista
                                // viene ordenada por id salían los PRIMEROS: ese era
                                // el punto suelto de la izquierda que no era ningún
                                // escritorio. Encima no se podía pinchar, porque
                                // `dispatch workspace -98` NO es "ve al -98": para
                                // Hyprland un número negativo a secas es un salto
                                // RELATIVO (98 escritorios hacia atrás). Un especial
                                // solo se abre con togglespecialworkspace, y para eso
                                // ya está su atajo. Aquí solo pintamos escritorios.
                                // Y con DOS pantallas, cada barra habla de LA
                                // SUYA. Sin filtrar, las dos barras pintaban la
                                // lista entera de escritorios y la píldora de la
                                // pantalla de la derecha señalaba uno que estaba
                                // en la de la izquierda: un indicador que apunta
                                // a otro sitio es peor que no tenerlo.
                                //
                                // El respaldo NO sobra: al arrancar la shell los
                                // escritorios llegan antes que los monitores, así
                                // que `ws.monitor` es null durante un instante y
                                // sin él la fila de puntos parpadearía vacía. Si
                                // ninguno se sabe de quién es, se pintan todos —
                                // que es exactamente lo que había con una sola
                                // pantalla.
                                model: ScriptModel {
                                    values: {
                                        const all = [...Hyprland.workspaces.values].filter(ws => ws.id > 0);
                                        const mine = all.filter(ws => ws.monitor && ws.monitor.name === win.modelData.name);
                                        return mine.length > 0 ? mine : all;
                                    }
                                }
                                Item {
                                    id: dot
                                    required property var modelData
                                    required property int index
                                    // El activo de ESTA pantalla, no el que tiene
                                    // el foco del teclado: con dos monitores cada
                                    // uno enseña un escritorio a la vez, y los dos
                                    // son "el actual" de su barra. Solo si aún no
                                    // se sabe qué monitor es este manda el foco
                                    // global, que es lo único que hay.
                                    readonly property bool isActive: win.hlMon
                                        ? (win.hlMon.activeWorkspace && win.hlMon.activeWorkspace.id === modelData.id)
                                        : (Hyprland.focusedWorkspace && Hyprland.focusedWorkspace.id === modelData.id)
                                    // Ya no se dibuja: solo ocupa su sitio en la
                                    // fila y escucha al raton. Lo PINTA el shader,
                                    // como un cuerpo mas del mismo fluido. Dibujarlo
                                    // aqui ademas seria contraproducente: dos
                                    // figuras separadas no se pueden fundir, y
                                    // fundirse es justo el efecto.
                                    width: 8
                                    height: 8
                                    anchors.verticalCenter: parent.verticalCenter

                                    // El punto activo le dice a la píldora adónde ir.
                                    // También al recolocarse: si creas o destruyes un
                                    // escritorio la fila se mueve y el destino cambia.
                                    function aim() { if (isActive) worm.target = x + width / 2; }
                                    onIsActiveChanged: aim()
                                    onXChanged: aim()
                                    Component.onCompleted: aim()

                                    MouseArea {
                                        id: wsMa
                                        anchors.fill: parent
                                        anchors.margins: -5
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        // Sintaxis Lua (Hyprland 0.55+): aquí el
                                        // destino es un id concreto, así que va como
                                        // NÚMERO, sin comillas. La rueda horizontal
                                        // de ShellState sí las necesita porque manda
                                        // `e+1`, que es una cadena.
                                        onClicked: Hyprland.dispatch("hl.dsp.focus({ workspace = " + dot.modelData.id + " })")
                                        onContainsMouseChanged: wsGroup.hovered = containsMouse ? dot.index : -1
                                    }
                                }
                            }
                        }

                        // El "worm" ya no se dibuja: es solo la FISICA. Calcula
                        // donde estan los dos extremos de la pildora y con que
                        // grosor, y el shader de abajo se encarga de pintarlo
                        // fundido con los puntos.
                        Item {
                            id: worm
                            visible: false
                            property real target: 0
                            // Dos seguidores del MISMO destino a velocidades
                            // distintas: el borde de delante llega en mIn y el de
                            // detrás en mInScale, rebotando. Mientras uno espera al
                            // otro la píldora está estirada — ese estiramiento ES
                            // el efecto. Un solo destino, dos tiempos.
                            property real lead: 0
                            property real trail: 0
                            onTargetChanged: { lead = target; trail = target; }
                            // MUELLES, y aqui esta el porque. Con duracion fija,
                            // cambiar de escritorio dos veces seguidas rapido
                            // cortaba el recorrido y lo reiniciaba desde cero: la
                            // pildora daba un tiron. Un muelle guarda la velocidad
                            // que llevaba, asi que el segundo salto CONTINUA el
                            // primero. Justo el caso en que mas se nota, porque es
                            // lo que haces sin pensar.
                            // El estiramiento sale de que los dos muelles tiran
                            // distinto: el de delante fuerte y contenido, el de
                            // detras flojo y con cola. Uno adelanta al otro y esa
                            // separacion ES la pildora estirada.
                            // El borde de delante sale disparado en cuanto cambia
                            // el destino.
                            Behavior on lead {
                                SpringAnimation {
                                    spring: Appearance.sprTight
                                    damping: Appearance.dmpTight
                                    epsilon: Appearance.eppPx
                                }
                            }

                            // El de detras SE QUEDA AGARRADO Y LUEGO SE SUELTA, y
                            // esto es la animacion entera.
                            //
                            // Antes los dos eran muelles y solo cambiaba su dureza,
                            // con la idea de que el mas blando se retrasaria. MEDIDO:
                            // en un salto de dos escritorios (40 px de recorrido) la
                            // pildora se estiraba 4 PX. Nada. Lo que yo tomaba por
                            // estiramiento era casi todo la fusion del metaball con
                            // el punto de al lado. Dos muelles distintos no producen
                            // un ligamento; producen dos cosas que llegan casi a la
                            // vez.
                            //
                            // Un liquido no se estira porque su cola sea mas lenta:
                            // se estira porque la cola SIGUE PEGADA donde estaba
                            // hasta que la tension la vence, y entonces se suelta de
                            // golpe. Eso es una pausa y despues un tiron, no una
                            // dureza distinta. Durante la pausa el estiramiento es el
                            // recorrido ENTERO, y al soltarse el muelle duro con poca
                            // amortiguacion da el latigazo y el temblor de llegada.
                            Behavior on trail {
                                SequentialAnimation {
                                    PauseAnimation { duration: Appearance.mStagger }
                                    SpringAnimation {
                                        spring: Appearance.sprSquash
                                        // Rigidez de aplastamiento pero amortiguacion
                                        // de panel, no la de aplastamiento. Con 0.20
                                        // el borde de detras se quedaba oscilando y
                                        // la pildora latia despues de llegar: un
                                        // temblor esta bien en el GROSOR, donde se
                                        // lee como materia, y es un fallo en la
                                        // POSICION, donde se lee como que no sabe
                                        // donde pararse.
                                        damping: Appearance.dmpPanel
                                        epsilon: Appearance.eppPx
                                    }
                                }
                            }

                            // SQUASH & STRETCH. No hay una animacion de "aplastarse"
                            // aparte: la deformacion SALE del propio viaje. 'fly' es
                            // cuanto esta estirada ahora mismo, y con eso la pildora
                            // ADELGAZA mientras vuela (8 -> 4.4 px) y recupera el
                            // grosor al posarse. Un cuerpo que se alarga sin
                            // estrecharse gana masa por el camino y el ojo lo lee
                            // como un dibujo que se deforma; estrechandose, lo lee
                            // como algo elastico que se tensa. Es la diferencia
                            // entre estirar una imagen y estirar una goma.
                            readonly property real stretch: Math.abs(lead - trail)

                            // Normalizado AL HUECO ENTRE DOS PUNTOS, no a un numero
                            // fijo. Estaba en 45 px, que es un salto de dos o tres
                            // escritorios; pero el salto que haces siempre es al de
                            // al lado, 20 px, y ahi la deformacion se quedaba a
                            // medias. El caso normal tiene que ser el que se ve
                            // bien, no el raro.
                            readonly property real fly: Math.min(1, stretch / (8 + wsRow.spacing))

                            // El grosor sale DIRECTO del estiramiento, sin muelle
                            // propio. Lo intente con muelle para que se pasara al
                            // aterrizar y NO SE PUEDE HACER ASI: un Behavior sobre
                            // una propiedad cuyo binding cambia cada fotograma
                            // reinicia el muelle 60 veces por segundo, asi que no
                            // llega a simular nada, y cuando el binding deja de
                            // cambiar se queda CONGELADO en el ultimo valor. Se veia
                            // como una pildora que adelgazaba y ya no recuperaba el
                            // grosor nunca. Los muelles son para destinos que cambian
                            // por SUCESOS, no para seguir una senal continua.
                            //
                            // El temblor de llegada sale igual y gratis: el borde de
                            // detras se pasa al frenar, asi que el estiramiento
                            // repunta un poco despues de aterrizar y el grosor con
                            // el. Un rebote emergente, no uno pintado.
                            readonly property real thick: 8 - 3.4 * fly

                            readonly property bool live: target > 0
                            x: wsGroup.pad + Math.min(lead, trail) - wsGroup.pill / 2
                            width: stretch + wsGroup.pill
                            height: thick
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        // ── EL FLUIDO ──
                        // Aqui no se dibujan figuras, se resuelve UN CAMPO. Los
                        // puntos y la pildora entran como cuerpos y se unen con una
                        // union suave, asi que al acercarse se funden con un CUELLO
                        // antes de tocarse y al separarse el hilo se estira y se
                        // rompe. Eso es tension superficial, y es lo que el ojo
                        // reconoce como liquido: no se puede fingir animando
                        // escalas ni opacidades de figuras sueltas.
                        //
                        // Va con margen (m) porque el cuello ABULTA fuera de la caja
                        // de los cuerpos; sin aire alrededor se recortaria justo la
                        // parte que hace el efecto.
                        // SOMBRA, que no es lo mismo que CERCO. El shader avisa —con
                        // razon— de que un halo CLARO pegado al borde es lo que hace
                        // que algo se vea sucio. Una sombra oscura por DETRAS es lo
                        // contrario: sobre fondo oscuro no existe (negro sobre
                        // negro) y solo asoma donde el wallpaper es claro, que es
                        // justo donde los cuerpos se disolvian. Con esto la barra
                        // puede seguir sin superficie propia y aun asi leerse con
                        // cualquier fondo.
                        MultiEffect {
                            anchors.fill: liquid
                            source: liquid
                            shadowEnabled: true
                            shadowColor: "#000000"
                            shadowOpacity: 0.5
                            shadowBlur: 0.45
                            shadowScale: 1.04
                        }

                        ShaderEffect {
                            id: liquid
                            readonly property real m: 10
                            anchors.centerIn: parent
                            width: wsGroup.implicitWidth + 2 * m
                            height: 24
                            // lo pinta el MultiEffect de arriba, no el arbol normal
                            layer.enabled: true
                            visible: false

                            // OJO AL NOMBRE VERSIONADO: Qt CACHEA el shader compilado
                            // por URL. Recompilar el .qsb encima del mismo nombre y
                            // recargar el QML NO lo recarga -- se sigue pintando el
                            // viejo, sin ningun aviso. Al cambiar el shader hay que
                            // subir el numero aqui y en el fichero, o reiniciar qs.
                            fragmentShader: Qt.resolvedUrl("shaders/liquid.v5.frag.qsb")

                            // Cuenta los puntos que hay REALMENTE en la fila, no los
                            // workspaces que reporta Hyprland: desde que filtramos
                            // los especiales ya no son lo mismo, y si el shader
                            // pintara uno de mas quedaria un punto fantasma al final
                            // sin nada debajo que se pueda pinchar.
                            property real count: wsRepeater.count
                            property real stepX: 8 + wsRow.spacing
                            property real first: m + wsGroup.pad + 4
                            property real dotR: 4
                            property real pillR: Math.max(0.5, worm.height / 2)
                            property real pillA: m + worm.x + pillR
                            property real pillB: m + worm.x + worm.width - pillR
                            property real hasPill: worm.live ? 1 : 0
                            property real hoverIdx: wsGroup.hovered
                            // 'k' es cuanto moja: el tamano del cuello. Por debajo de
                            // ~4 los cuerpos se ignoran hasta tocarse (y entonces es
                            // un choque, no una fusion); muy por encima todo queda
                            // permanentemente pegado y se pierde la fila.
                            property real k: 4.5
                            property real w: width
                            property real h: height
                            // Los dos salen de Colors con el contraste ya resuelto
                            // contra el fondo de pantalla: ver el bloque grande de
                            // Colors.qml. Con blanco al 50 % fijo y Colors.accent a
                            // pelo, un wallpaper monocromo dejaba los puntos
                            // apagados MAS claros que la pildora encendida.
                            property color dotColor: Colors.onWallDim
                            property color pillColor: Colors.onWallAccent
                        }
                    }

                    BarItem {
                        Layout.leftMargin: 6
                        visible: Config.showAppName && ShellState.appName.length > 0
                        label: ShellState.appName
                        labelBold: true
                        interactive: false
                        hpad: 4
                    }
                }

                // ══════════════ barra: derecha ══════════════
                // Solo estado que merezca un vistazo. Lo condicional aparece y
                // desaparece; los controles viven en el panel del notch.
                RowLayout {
                    id: rightGroup
                    anchors { right: parent.right; rightMargin: root.sideMargin; top: parent.top }
                    height: root.barH
                    spacing: 1

                    // Te están capturando la pantalla. Va aquí y no en el notch
                    // porque la barra derecha es donde viven las EXCEPCIONES: cosas
                    // que normalmente no pasan y que, cuando pasan, quieres ver de
                    // un vistazo sin que nadie te las cuente. Late porque un punto
                    // rojo quieto se confunde con un adorno.
                    BarItem {
                        id: castItem
                        visible: ShellState.casting
                        icon: Icons.rec
                        iconColor: Colors.crit
                        interactive: false
                        SequentialAnimation on opacity {
                            running: ShellState.casting
                            loops: Animation.Infinite
                            NumberAnimation { to: 0.35; duration: 900; easing.type: Easing.InOutSine }
                            NumberAnimation { to: 1.0;  duration: 900; easing.type: Easing.InOutSine }
                        }
                    }

                    BarItem {
                        visible: ShellState.caffeine
                        icon: Icons.coffee
                        iconColor: Colors.accent
                        onClicked: ShellState.caffeine = false
                    }

                    BarItem {
                        visible: ShellState.pacman.length > 0 && ShellState.pacman !== "0"
                        icon: Icons.updates
                        // Sin cifra: la nube dice "hay actualizaciones" y punto. El
                        // cuantas se ve al pulsarla, que abre la lista.
                        label: ""
                        iconColor: Colors.c4
                        labelColor: Colors.c4
                        onClicked: Quickshell.execDetached(["bash", "-lc", "kitty --hold -e " + ShellState.home + "/.config/hypr/scripts/pacman-updates.sh --list"])
                        // Antes era un execDetached: el script se sincronizaba y
                        // escupia el JSON nuevo A LA NADA, porque execDetached no
                        // recoge stdout. Ahora pasa por el Process de ShellState, que
                        // si lo lee, asi que el numero de la barra se actualiza.
                        onRightClicked: ShellState.pacmanRefresh()
                    }

                    BarItem {
                        // Sin contador diario de notificaciones, pero el modo No
                        // Molestar si tiene que verse: si no, lo dejas puesto sin
                        // saberlo y te pierdes avisos.
                        visible: ShellState.dnd
                        icon: ShellState.notifIcon
                        label: ShellState.notifCount > 0 ? String(ShellState.notifCount) : ""
                        iconColor: ShellState.dnd ? Colors.dim : Colors.accent
                        labelColor: iconColor
                        onClicked: ShellState.togglePanel("control")
                        onRightClicked: ShellState.dnd = !ShellState.dnd
                    }

                    Row {
                        visible: Config.showTray
                        Layout.alignment: Qt.AlignVCenter
                        Layout.leftMargin: 4
                        Layout.rightMargin: 4
                        spacing: 9
                        Repeater {
                            model: SystemTray.items
                            Item {
                                id: trayItem
                                required property var modelData
                                width: 16; height: 16
                                anchors.verticalCenter: parent.verticalCenter

                                Image {
                                    anchors.fill: parent
                                    source: trayItem.modelData.icon
                                    sourceSize.width: 16; sourceSize.height: 16
                                    opacity: trayMa.containsMouse ? 1 : 0.85
                                    Behavior on opacity { NumberAnimation { duration: Appearance.mQuick } }
                                }
                                QsMenuAnchor {
                                    id: trayMenu
                                    menu: trayItem.modelData.menu
                                    anchor.item: trayItem
                                    anchor.edges: Edges.Bottom
                                    anchor.gravity: Edges.Bottom
                                }
                                MouseArea {
                                    id: trayMa
                                    anchors.fill: parent
                                    anchors.margins: -4
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                                    onClicked: function (m) {
                                        if (m.button === Qt.MiddleButton) { trayItem.modelData.secondaryActivate(); return; }
                                        if (m.button === Qt.RightButton || trayItem.modelData.onlyMenu) {
                                            if (trayItem.modelData.hasMenu) trayMenu.open();
                                            return;
                                        }
                                        trayItem.modelData.activate();
                                    }
                                }
                            }
                        }
                    }

                    // bluetooth: solo si hay algo CONECTADO (cascos, mando...).
                    // Encendido-pero-sin-nada no es información, es ruido.
                    BarItem {
                        visible: ShellState.btConnected > 0
                        icon: "󰂱"
                        iconColor: Colors.accent
                        onClicked: ShellState.togglePanel("bluetooth")
                    }

                    // red: solo si NO hay. Estar conectado es lo normal y no merece
                    // un icono permanente; quedarse sin red sí.
                    BarItem {
                        visible: !ShellState.online
                        icon: "󰤭"
                        iconColor: Colors.crit
                        onClicked: ShellState.togglePanel("network")
                    }

                    // volumen: solo si está silenciado. El nivel lo enseña el OSD del
                    // notch al cambiarlo, y el slider del panel.
                    BarItem {
                        visible: ShellState.muted
                        icon: Icons.volMute
                        iconColor: Colors.warn
                        onClicked: ShellState.toggleMute()
                    }

                    // NO están aquí a propósito, porque ya viven en el notch:
                    //   reloj y fecha -> contenido en reposo
                    //   batería       -> polo derecho del notch
                    //   volumen/brillo-> OSD + sliders del panel
                    //   CPU/RAM       -> panel
                    //   red/bt/notis/cafeína/apagado -> acciones del panel
                }

                // ══════════════ la burbuja satélite ══════════════
                // Un cuerpo pequeño que asoma por DETRÁS del borde derecho del notch
                // mientras hay algo corriendo de fondo (una cuenta atrás, una
                // sincronización). Los datos y la prioridad, en ShellState.bubble*.
                //
                // TRES DECISIONES, y ninguna es dónde ponerla:
                //
                // 1. SE DECLARA ANTES QUE EL NOTCH, o sea que el notch la PINTA
                //    ENCIMA. No es un descuido: cuando el notch crece (un OSD, un
                //    panel) se traga la burbuja, y al encogerse la burbuja vuelve a
                //    asomar. Es exactamente la metáfora — algo que estaba detrás —
                //    y sale gratis, sin una sola línea que esconda nada.
                //
                // 2. SU SITIO SE MIDE CONTRA EL NOTCH EN REPOSO, no contra el notch
                //    de ahora. Si siguiera al borde vivo, abrir el mapa de
                //    escritorios (1396 px) la mandaría volando al otro extremo de la
                //    pantalla y volvería. Quieta detrás es lo correcto.
                //
                // 3. CABE DENTRO DE LA BANDA RESERVADA (28 de 32 px). Una cuenta
                //    atrás dura minutos: si sobresaliera, taparía la esquina de una
                //    ventana durante minutos, y esa es justo la regla que el notch
                //    entero existe para no romper.
                Item {
                    id: bubble

                    readonly property bool on: ShellState.bubbleOn
                    readonly property real h: 28
                    // Borde derecho del notch EN REPOSO (ver decisión 2).
                    readonly property real restRight: (surface.width
                        + (root.island ? ShellState.restW : ShellState.restW + 2 * root.flare)) / 2
                    readonly property real hiddenX: restRight - h * 0.62
                    readonly property real shownX: restRight + 8

                    // Un solo número gobierna entrada y salida: 0 = escondida
                    // detrás, 1 = fuera del todo. Con muelle, así que si el
                    // temporizador se cancela mientras aún está saliendo, no corta:
                    // continúa el movimiento hacia dentro con la velocidad que
                    // llevaba.
                    property real reveal: on ? 1 : 0
                    Behavior on reveal {
                        SpringAnimation { spring: Appearance.sprPanel; damping: Appearance.dmpPanel; epsilon: Appearance.eppScale }
                    }

                    readonly property bool wide: bubbleMa.containsMouse || ShellState.bubbleAlert

                    x: hiddenX + (shownX - hiddenX) * reveal
                    y: notch.gap + (root.barH - notch.gap - h) / 2
                    height: h
                    width: h + (wide ? label.implicitWidth + 16 : 0)
                    Behavior on width { SpringAnimation { spring: Appearance.sprTight; damping: Appearance.dmpTight; epsilon: Appearance.eppPx } }

                    opacity: reveal
                    scale: 0.55 + 0.45 * reveal
                    transformOrigin: Item.Left
                    visible: reveal > 0.01

                    Rectangle {
                        anchors.fill: parent
                        radius: height / 2
                        color: root.notchColor
                    }

                    // ── el anillo ──
                    // Con progreso conocido dibuja lo que QUEDA (se vacía en sentido
                    // horario); sin él da vueltas. Un arco que gira dice "sigo" sin
                    // mentir sobre cuánto falta, que es lo que hace una barra
                    // indeterminada fingiendo un porcentaje.
                    Shape {
                        id: ring
                        width: bubble.h; height: bubble.h
                        preferredRendererType: Shape.CurveRenderer
                        antialiasing: true
                        readonly property real det: ShellState.bubbleProgress
                        readonly property real r: bubble.h / 2 - 2.5

                        ShapePath {
                            strokeColor: Qt.rgba(1, 1, 1, 0.14)
                            strokeWidth: 2
                            fillColor: "transparent"
                            capStyle: ShapePath.RoundCap
                            PathAngleArc {
                                centerX: bubble.h / 2; centerY: bubble.h / 2
                                radiusX: ring.r; radiusY: ring.r
                                startAngle: 0; sweepAngle: 360
                            }
                        }
                        ShapePath {
                            strokeColor: ShellState.bubbleAlert ? Colors.crit : Colors.accent
                            strokeWidth: 2.5
                            fillColor: "transparent"
                            capStyle: ShapePath.RoundCap
                            PathAngleArc {
                                centerX: bubble.h / 2; centerY: bubble.h / 2
                                radiusX: ring.r; radiusY: ring.r
                                startAngle: -90
                                // 300 grados y no 360 en el modo indeterminado: un
                                // círculo completo girando es un círculo quieto.
                                sweepAngle: ring.det >= 0 ? 360 * ring.det : 300
                            }
                        }
                        // El giro es del arco entero y solo existe sin progreso.
                        RotationAnimation on rotation {
                            running: ring.det < 0 && bubble.on
                            from: 0; to: 360
                            duration: 1100
                            loops: Animation.Infinite
                        }
                        onDetChanged: if (det >= 0) rotation = 0
                    }

                    Text {
                        x: (bubble.h - implicitWidth) / 2
                        anchors.verticalCenter: parent.verticalCenter
                        text: ShellState.bubbleIcon
                        color: ShellState.bubbleAlert ? Colors.crit : "#ffffff"
                        font.family: Appearance.font
                        font.pixelSize: 12
                    }

                    Text {
                        id: label
                        x: bubble.h + 2
                        anchors.verticalCenter: parent.verticalCenter
                        text: ShellState.bubbleLabel
                        color: "#ffffff"
                        font.family: Appearance.fontUI
                        font.pixelSize: 12
                        font.weight: Font.DemiBold
                        font.features: ({ "tnum": 1 })   // los segundos no deben mover la píldora
                        opacity: bubble.wide ? 1 : 0
                        visible: opacity > 0.01
                        Behavior on opacity { NumberAnimation { duration: Appearance.mQuick } }
                    }

                    MouseArea {
                        id: bubbleMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        onClicked: function (m) {
                            if (ShellState.bubbleKind !== "timer") return;
                            if (m.button === Qt.RightButton) ShellState.timerClear();
                            else ShellState.timerToggle();
                        }
                    }
                }

                // ══════════════ el notch ══════════════
                Item {
                    id: notch
                    readonly property real gap: root.topGap
                    // Red de seguridad: si un panel no atiende Escape, la tecla
                    // burbujea hasta aquí y se cierra igual. Ningún panel puede
                    // dejarte atrapado.
                    focus: true
                    Keys.onEscapePressed: function (e) { ShellState.closePanel(); e.accepted = true; }

                    width: root.island ? nw : nw + 2 * root.flare
                    height: nh - notch.gap
                    x: (surface.width - width) / 2
                    y: notch.gap

                    property real nw: win.faceW
                    property real nh: win.faceH
                    // Los dos ejes iban con la MISMA duracion y la misma curva,
                    // y por eso el notch se reescalaba como una caja en vez de
                    // deformarse. Ahora cada eje lleva su propio muelle: el ancho
                    // tira fuerte y llega antes, el alto va flojo, lo sigue y se
                    // pasa un poco al aterrizar. El notch se ABRE -- primero se
                    // ensancha, luego cae -- en vez de inflarse entero a la vez.
                    // Es squash & stretch de manual, y ademas rb (el redondeo de
                    // las esquinas de abajo) se calcula desde height, asi que la
                    // forma se curva sola durante el recorrido.
                    Behavior on nw { SpringAnimation { spring: Appearance.sprTight; damping: Appearance.dmpTight; epsilon: Appearance.eppPx } }
                    Behavior on nh { SpringAnimation { spring: Appearance.sprLoose; damping: Appearance.dmpLoose; epsilon: Appearance.eppPx } }

                    readonly property real fl: root.flare
                    readonly property real rb: Math.max(6, Math.min(root.roundMax, height - fl - 1))

                    // ---- modo isla: una píldora redonda por los cuatro lados ----
                    Rectangle {
                        anchors.fill: parent
                        visible: root.island
                        radius: Math.min(root.roundMax, height / 2)
                        color: root.notchColor
                    }

                    // ---- modo notch: esquinas superiores INVERTIDAS contra el borde ----
                    Shape {
                        anchors.fill: parent
                        visible: !root.island
                        preferredRendererType: Shape.CurveRenderer
                        antialiasing: true

                        ShapePath {
                            id: sp
                            fillColor: root.notchColor
                            strokeWidth: 0
                            strokeColor: "transparent"

                            readonly property real fl: notch.fl
                            readonly property real rb: notch.rb
                            readonly property real w: notch.nw
                            readonly property real h: notch.height
                            readonly property real k: root.kArc
                            readonly property real ik: 1 - k

                            startX: 0; startY: 0
                            // esquina superior izquierda invertida
                            PathCubic {
                                control1X: sp.fl * sp.k; control1Y: 0
                                control2X: sp.fl;        control2Y: sp.fl * sp.ik
                                x: sp.fl;                y: sp.fl
                            }
                            PathLine { x: sp.fl; y: sp.h - sp.rb }
                            PathCubic {
                                control1X: sp.fl;                 control1Y: sp.h - sp.rb * sp.ik
                                control2X: sp.fl + sp.rb * sp.ik; control2Y: sp.h
                                x: sp.fl + sp.rb;                 y: sp.h
                            }
                            PathLine { x: sp.fl + sp.w - sp.rb; y: sp.h }
                            PathCubic {
                                control1X: sp.fl + sp.w - sp.rb * sp.ik; control1Y: sp.h
                                control2X: sp.fl + sp.w;                 control2Y: sp.h - sp.rb * sp.ik
                                x: sp.fl + sp.w;                         y: sp.h - sp.rb
                            }
                            PathLine { x: sp.fl + sp.w; y: sp.fl }
                            // esquina superior derecha invertida
                            PathCubic {
                                control1X: sp.fl + sp.w;                control1Y: sp.fl * sp.ik
                                control2X: sp.fl + sp.w + sp.fl * sp.k; control2Y: 0
                                x: sp.fl + sp.w + sp.fl;                y: 0
                            }
                            PathLine { x: 0; y: 0 }
                        }
                    }

                    // Retardo antes de abrir el "peek": si solo pasas el ratón por
                    // encima, el notch no se mueve.
                    Timer { id: dwell; interval: Config.hoverDelay; onTriggered: ShellState.hovered = true }

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        cursorShape: Qt.PointingHandCursor
                        onEntered: dwell.restart()
                        onExited: { dwell.stop(); ShellState.hovered = false; }
                        onClicked: function (m) {
                            if (m.button === Qt.RightButton && ShellState.player)
                                ShellState.player.isPlaying ? ShellState.player.pause() : ShellState.player.play();
                            else ShellState.togglePanel("control");
                        }
                        // Dos ejes, dos cosas. El vertical era lo unico que habia y
                        // sigue igual (volumen); el horizontal no hacia nada y ahora
                        // cambia de escritorio. Se compara el valor absoluto para
                        // decidir cual manda: un panel tactil manda siempre algo en
                        // los dos ejes, y sin esto un gesto vertical con un pelo de
                        // desvio te cambiaria de escritorio al subir el volumen.
                        // Solo con el notch en reposo: con un panel abierto la rueda
                        // es del panel (una lista que se desplaza, un arrastre).
                        onWheel: function (w) {
                            const dx = w.angleDelta.x, dy = w.angleDelta.y;
                            if (Math.abs(dx) > Math.abs(dy)) {
                                // El gesto de escritorio solo con el notch en reposo:
                                // con un panel abierto la rueda es del panel.
                                if (!ShellState.open) ShellState.scrollWorkspace(dx);
                                return;
                            }
                            // El `dy !== 0` no sobra: `dy > 0 ? 1 : -1` convierte un
                            // cero en -1, asi que un gesto puramente horizontal
                            // bajaba el volumen sin que nadie lo pidiera.
                            if (dy !== 0) ShellState.nudgeVolume(dy > 0 ? 1 : -1);
                        }
                    }

                    NotchContent {
                        mode: win.faceMode
                        x: root.island ? 0 : notch.fl
                        y: 0
                        width: notch.nw
                        height: notch.height
                        clip: true
                    }
                }
            }
        }
    }
}
