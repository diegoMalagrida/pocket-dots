// ShellState.qml — hub de datos y de estado de la superficie superior.
//
// Al estilo de caelestia (services/): toda la lógica y los datos viven aquí, y
// TopShell.qml se queda siendo UI pura. Así la barra y el notch leen EXACTAMENTE
// el mismo estado y no pueden desincronizarse.
pragma Singleton

import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Networking
import Quickshell.Bluetooth
import Quickshell.Services.Mpris
import Quickshell.Services.Notifications
import Quickshell.Services.Pipewire
import Quickshell.Services.UPower
import QtQuick

Singleton {
    id: root

    readonly property string home: Quickshell.env("HOME")
    // El locale con el que TODO el shell da formato a fechas y números. Tiene
    // que seguir al idioma: con el shell en inglés, un "miércoles" en el notch
    // canta tanto como una etiqueta sin traducir.
    //
    // en_GB y no en_US porque el inglés de este repo es el británico del README
    // ("recoloured", "licence", "centre"), y porque el formato acompaña: en_GB
    // pone el día antes que el mes (3/9/2026) y la hora en 24 h, igual que el
    // castellano. Con en_US la fecha se daría la vuelta (9/3/2026) y saldría el
    // "PM", que aquí no lo usa nadie.
    readonly property var loc: Qt.locale(I18n.english ? "en_GB" : "es_ES")

    // ═══════════════════════ estado del notch ═══════════════════════
    // El notch es el punto de entrada del escritorio: de él se despliegan
    // paneles. "" = ninguno. Añadir uno nuevo = un valor más aquí, su tamaño en
    // notchW/notchH, y su capa en NotchContent.qml.
    property string panel: ""     // "" | "control" | "system" | "launcher" | "power" | "network" | "bluetooth" | "overview" | "calendar"
    readonly property bool open: panel !== ""

    // La app de Ajustes NO es un panel del notch (ver SettingsWindow.qml), pero
    // se lanza desde él, así que su estado vive aquí.
    property bool settingsOpen: false
    function toggleSettings() { root.settingsOpen = !root.settingsOpen; }

    // Abrir Ajustes YA EN una sección concreta, en vez de en la de siempre.
    // Lo estrena Super+K, que hasta ahora lanzaba un rofi aparte
    // (~/.config/hypr/list_keybinds.sh) para enseñar una lista de atajos
    // sacada del MISMO hyprland.conf que ya lee SettingsShortcuts.qml. No
    // hacía falta otra vista: hacía falta una puerta a la que ya había.
    //
    // Va por señal y no por una propiedad de aquí porque quien manda en qué
    // sección se ve es la ventana de Ajustes; ShellState solo sabe si está
    // abierta o cerrada.
    signal settingsSection(string id)
    function openSettingsAt(id) { root.settingsSection(id); }

    // Buscador de Ajustes. Vive aquí y no en la ventana porque quien decide si
    // una fila se ve es la propia fila (SettingsControls.Row_), que es un
    // componente en línea y no alcanza el id de la ventana.
    property string settingsQuery: ""
    function settingsFold(value) {
        // Buscar "bateria" debe encontrar "Batería": al escribir deprisa no
        // tiene sentido exigir tildes exactas en un buscador de ajustes.
        return String(value).toLowerCase().normalize("NFD").replace(/[\u0300-\u036f]/g, "");
    }
    function settingsMatch(label, hint) {
        const q = root.settingsFold(root.settingsQuery.trim());
        if (q.length === 0) return true;
        return root.settingsFold(String(label) + " " + String(hint)).indexOf(q) >= 0;
    }

    // La descripción de un ajuste NO va debajo de su etiqueta: iría siempre
    // visible, haría cada fila de tres líneas y en una ventana de 520 px solo
    // cabrían siete ajustes. Va a una franja fija al pie de la ventana, que
    // enseña la del ajuste que tienes debajo del ratón. Cero reflow, cero
    // popups tapando cosas, y no se pierde ni una palabra.
    property string settingsHint: ""

    function togglePanel(name) {
        // El lanzador es el único panel que abre en varios modos, así que tiene
        // su propia puerta (openLauncher). Por aquí se entra SIEMPRE en "apps":
        // ni Super+R ni el logo de Arch piden portapapeles ni ventanas.
        if (name === "launcher") { root.openLauncher("apps"); return; }
        root.panel = (root.panel === name) ? "" : name;
    }
    function closePanel() { root.panel = ""; }
    property bool hovered: false             // ratón sobre el notch
    property string activity: ""             // "" | "volume" | "brightness" | "track"
    property bool armed: false               // ya pasó el arranque: se permiten OSD

    Timer { interval: 1500; running: true; onTriggered: root.armed = true }
    Timer { id: activityTimer; onTriggered: root.activity = "" }

    function flash(kind) {
        root.activity = kind;
        // "ws" dura menos que el resto a proposito: no es informacion que
        // tengas que leer, es el acuse de recibo de un gesto que acabas de hacer.
        // Un OSD de volumen se mira; este solo se comprueba de reojo.
        activityTimer.interval = (kind === "track" || kind === "notif") ? 4200
            : kind === "toast" ? 1600
            : kind === "ws" ? 1100
            : kind === "charge" ? 2200 : 1800;
        activityTimer.restart();
    }

    readonly property bool mediaLive: player !== null && player.isPlaying

    // btpair va POR DELANTE del panel abierto, y es la única cara que se salta
    // esa regla. No es un aviso: es una pregunta con caducidad al otro lado de
    // la cual hay un aparato esperando. Si se quedara detrás del panel que
    // tuvieras abierto, el emparejamiento vencería sin que llegaras a verla.
    readonly property string mode: btAsking ? "btpair"
        : panel !== "" ? panel
        : activity === "notif" ? "notif"
        : activity === "toast" ? "toast"
        : activity === "track" ? "track"
        : activity === "ws" ? "ws"
        : activity === "charge" ? "charge"
        : activity !== "" ? "activity"
        : hovered ? "peek"
        : mediaLive ? "media" : "idle"

    // Geometría objetivo del notch (isla suelta pegada al borde superior).
    // REGLA: en reposo y con música la altura es EXACTAMENTE la banda reservada
    // (barH) para que el notch no tape nunca ninguna ventana. Solo sobresale
    // cuando tú provocas algo: hover, OSD, cambio de canción o el panel.
    readonly property int bandH: Config.bandH

    // Hueco entre el borde de la pantalla y la píldora en modo isla. Vive aquí y
    // no solo en TopShell porque los paneles que calculan su alto exacto tienen
    // que descontarlo: TopShell dibuja el notch con `height: notchH - gap`.
    readonly property int notchTopGap: Config.island ? Config.islandGap : 0

    // Ningún panel puede ser más ancho que la pantalla donde sale. Los anchos de
    // abajo se eligieron mirando ESTE portátil, donde caben de sobra (el más
    // gordo, el centro de control, mide 1080 sobre 1920: 420 px de aire por
    // lado). Pero son números fijos, y en una salida más estrecha el notch se
    // saldría por los dos costados con el contenido cortado y sin ningún aviso.
    // 48 px de respiro a cada lado; si no se sabe aún cuál es la pantalla, no se
    // recorta nada, que es como se ha comportado hasta hoy.
    readonly property int notchW: Math.min(root.notchWWanted, root.maxNotchW)
    readonly property int maxNotchW: {
        const s = root.focusedScreen;
        return (s && s.width > 0) ? Math.max(220, s.width - 96) : 100000;
    }
    readonly property int notchWWanted: mode === "launcher" ? 660
        : mode === "btpair" ? 470
        : mode === "overview" ? ovW
        : mode === "control" ? 1080
        : mode === "system" ? 920
        : mode === "network" || mode === "bluetooth" ? 470
        : mode === "power" ? 520
        : mode === "calendar" ? 350
        : mode === "notif" ? 430
        : mode === "toast" ? 330
        : mode === "ws" ? 220
        : mode === "charge" ? 260
        : mode === "track" ? 400
        : mode === "peek" ? 380
        : mode === "activity" ? 330
        : mode === "media" ? root.mediaW : root.idleW

    readonly property int mediaW: 268

    // Ancho del notch en su cara EN REPOSO: la hora sola, o la de música si hay
    // algo sonando. Las caras PASAJERAS (paneles, OSD, el destello de cambio de
    // canción, el mapa) no cuentan: esas sí tienen que tragarse la burbuja
    // satélite y devolverla al encogerse, que es la metáfora.
    //
    // Antes esto era `idleW` a secas y la burbuja se quedaba debajo del notch
    // durante toda la reproducción: con música puesta -o sea, casi siempre- una
    // cuenta atrás corriendo era invisible.
    readonly property int restW: root.mediaLive ? root.mediaW : root.idleW

    // El lanzador se ajusta a lo que hay: si buscas algo y salen tres apps, o si
    // es una cuenta, el panel encoge hacia arriba en vez de dejar un hueco negro.
    // LauncherPanel publica aquí cuántas filas tiene tras cada búsqueda.
    property int launcherRows: 0
    property bool launcherCalc: false
    // La fila de favoritos solo existe con el campo vacío, así que también entra
    // y sale del alto del panel igual que la de la calculadora.
    property bool launcherFavs: false

    // OJO con estas constantes: tienen que cuadrar EXACTAMENTE con los márgenes
    // de LauncherPanel.qml. Si se quedan cortas, la lista recibe menos alto del
    // que ocupan sus filas y la última se ve recortada por abajo.
    //   4 (topMargin) + 50 (buscador) + 1 + 6 (separador) + 12 (margen inferior)
    readonly property int launcherChrome: 73
    // El alto de fila depende del MODO, y es el único que se sale de 48: una
    // entrada del portapapeles enseña una miniatura de verdad, no un icono de
    // 30 px, y a 48 las imágenes no se distinguían unas de otras.
    readonly property int launcherRowH: root.launcherMode === "clip" ? 60 : 48
    readonly property int launcherCalcH: 62      // 56 de la fila + 6 de margen
    readonly property int launcherFavH: 70       // 58 de la fila + 12 de margen
    readonly property int launcherMaxRows: 7     // a partir de aquí, scroll

    readonly property int launcherH: {
        const calc = root.launcherCalc ? root.launcherCalcH : 0;
        const favs = root.launcherFavs ? root.launcherFavH : 0;
        const rows = Math.min(root.launcherRows, root.launcherMaxRows) * root.launcherRowH;
        const vacio = (root.launcherRows === 0 && !root.launcherCalc) ? 46 : 0;  // "Sin resultados"
        // El hueco del modo isla NO es alto útil: TopShell despega la píldora del
        // borde con `height: nh - gap`, así que el contenido recibe islandGap menos
        // de lo que pide este cálculo. Sin sumarlo aquí, la lista (fillHeight) se
        // come el déficit y recorta la última fila justo por sus esquinas
        // redondeadas — se ve sobre todo con un único resultado.
        return root.launcherChrome + calc + favs + rows + vacio + root.notchTopGap;
    }

    // Config.idleW es el ancho para la hora SOLA. Si en Ajustes vuelves a
    // encender la fecha o la batería, el notch se ensancha solo: si fuera un
    // ancho fijo, al reactivarlas el contenido quedaría recortado.
    readonly property int idleW: Config.idleW
        + (Config.showDate ? 92 : 0)
        + (Config.showBattery ? 64 : 0)
    readonly property int notchH: mode === "launcher" ? launcherH
        : mode === "btpair" ? (btKind === "display" ? 96 : 112)
        : mode === "overview" ? ovH
        : mode === "control" ? 526
        : mode === "system" ? 420
        : mode === "network" || mode === "bluetooth" ? 412
        : mode === "power" ? 158
        // +notchTopGap por lo mismo que el lanzador unas lineas mas arriba: en
        // modo isla TopShell despega la pildora con `height: nh - gap`, asi que
        // sin sumarlo se recortan los ultimos pixeles y la fila de abajo pierde
        // el borde. Diego usa el notch en modo isla, o sea que esto se veia.
        : mode === "calendar" ? 320 + root.notchTopGap
        : mode === "notif" ? 66
        : mode === "toast" ? 44
        : mode === "ws" ? 44
        : mode === "charge" ? 46
        : mode === "track" ? 52
        : mode === "peek" ? 44
        : mode === "activity" ? 42
        : bandH

    // ═══════════════════════ overview de escritorios ═══════════════════════
    // La rejilla del overview (OverviewPanel.qml) se dimensiona SOLA a partir
    // del monitor: cada celda es el área útil de la pantalla a escala. Está aquí
    // y no en el panel porque el notch tiene que saber cuánto va a medir ANTES
    // de que el panel exista — el morfeo de la forma empieza en el mismo
    // fotograma que la capa.
    //
    // 5x2 no es un número bonito: son exactamente los diez escritorios que tiene
    // atados hyprland.conf a Super+1..0. Si algún día hubiera doce, esto y los
    // atajos tienen que cambiar a la vez o el mapa mentiría.
    readonly property int ovCols: 5
    readonly property int ovRows: 2
    readonly property int ovCount: ovCols * ovRows

    // La escala. 0.14 sale de una restricción real: 5 celdas + huecos + aire
    // tienen que caber holgadas en 1920 px, y una celda por debajo de ~250 px de
    // ancho ya no deja reconocer una ventana por su contenido, que es lo único
    // que justifica capturar en vivo en vez de pintar iconos.
    readonly property real ovScale: 0.14
    readonly property real ovGap: 6          // hueco entre celdas
    readonly property real ovPad: 14         // aire a los lados y por abajo
    readonly property real ovPadTop: 16
    readonly property real ovFooterH: 24     // la franja con el título de la ventana señalada

    // Se descuenta la banda reservada (`reserved`), no el alto entero: las
    // ventanas se colocan dentro del área ÚTIL, así que si la celda representara
    // la pantalla completa todas saldrían desplazadas 32 px hacia arriba.
    // Se busca por NOMBRE con el foco que ya tenemos sembrado (ver focusedMon,
    // más abajo) en vez de fiarse de Hyprland.focusedMonitor: esa propiedad nace
    // vacía y solo se rellena al primer evento, así que recién arrancada la shell
    // el overview se dibujaba con el respaldo de 1920x1080. En este portátil no
    // se notaba porque el panel MIDE 1920x1080; en una pantalla de otro tamaño
    // las celdas salen con la proporción equivocada y las miniaturas no
    // coinciden con las ventanas de verdad.
    readonly property var ovMon: {
        const ms = Hyprland.monitors ? Hyprland.monitors.values : [];
        for (let i = 0; i < ms.length; i++)
            if (ms[i] && ms[i].name === root.focusedMon) return ms[i].lastIpcObject;
        return Hyprland.focusedMonitor ? Hyprland.focusedMonitor.lastIpcObject : null;
    }
    // Y si ni siquiera eso, la pantalla de Quickshell antes que un número fijo.
    readonly property real ovMonW: (ovMon && ovMon.width) ? ovMon.width
        : (root.focusedScreen ? root.focusedScreen.width : 1920)
    readonly property real ovMonH: (ovMon && ovMon.height) ? ovMon.height
        : (root.focusedScreen ? root.focusedScreen.height : 1080)
    readonly property var ovRes: (ovMon && ovMon.reserved) ? ovMon.reserved : [0, bandH, 0, 0]
    readonly property real ovCellW: (ovMonW - ovRes[0] - ovRes[2]) * ovScale
    readonly property real ovCellH: (ovMonH - ovRes[1] - ovRes[3]) * ovScale
    readonly property real ovGridW: ovCols * ovCellW + (ovCols - 1) * ovGap
    readonly property real ovGridH: ovRows * ovCellH + (ovRows - 1) * ovGap
    readonly property int ovW: Math.round(ovGridW + 2 * ovPad)
    readonly property int ovH: Math.round(ovPadTop + ovGridH + ovFooterH + ovPad)

    // ═══════════════════════ reloj ═══════════════════════
    property var now: new Date()
    Timer { interval: 1000; running: true; repeat: true; onTriggered: root.now = new Date() }

    // ═══════════════════════ ventana activa ═══════════════════════
    readonly property var activeToplevel: ToplevelManager.activeToplevel
    readonly property bool fullscreen: activeToplevel ? activeToplevel.fullscreen : false
    readonly property string appName: {
        if (!activeToplevel || !activeToplevel.appId) return "";
        const a = String(activeToplevel.appId).split(".").pop();
        return a.charAt(0).toUpperCase() + a.slice(1);
    }
    readonly property string winTitle: activeToplevel ? (activeToplevel.title || "") : ""

    // ═══════════════════════ media (MPRIS) ═══════════════════════
    readonly property var player: {
        const ps = Mpris.players.values;
        if (!ps || ps.length === 0) return null;
        for (let i = 0; i < ps.length; i++) if (ps[i].isPlaying) return ps[i];
        // Con todo en pausa mandaba el primero de la lista, y ese suele ser una
        // sesión de medios del navegador que ya no tiene nada cargado: el panel
        // decía "Sin reproducción" con Spotify ahí al lado, con su canción
        // puesta y en pausa, y los botones no controlaban nada.
        for (let i = 0; i < ps.length; i++) if (ps[i].trackTitle) return ps[i];
        return ps[0];
    }

    // El acento de música nace de la carátula, no del fondo. ColorQuantizer es
    // asíncrono: mientras llega una paleta nueva conserva el acento anterior y,
    // si no hay imagen o la portada es prácticamente gris, vuelve a pywal.
    // Se normaliza la luminosidad porque el color se usa sobre fondos oscuros:
    // un tono fiel pero casi negro no serviría para una barra de 4 px.
    readonly property string mediaArtUrl: (player && player.trackArtUrl)
        ? String(player.trackArtUrl) : ""
    ColorQuantizer {
        id: mediaQuantizer
        source: root.mediaArtUrl
        depth: 3
        rescaleSize: 48
    }
    function mediaHsl(c) {
        const r = Number(c.r), g = Number(c.g), b = Number(c.b);
        const hi = Math.max(r, g, b), lo = Math.min(r, g, b);
        const d = hi - lo, l = (hi + lo) / 2;
        let h = 0, s = 0;
        if (d > 0.0001) {
            s = d / (1 - Math.abs(2 * l - 1));
            if (hi === r) h = ((g - b) / d) % 6;
            else if (hi === g) h = (b - r) / d + 2;
            else h = (r - g) / d + 4;
            h /= 6;
            if (h < 0) h += 1;
        }
        return { h: h, s: isFinite(s) ? s : 0, l: l };
    }
    readonly property color mediaAccent: {
        if (root.mediaArtUrl.length === 0) return Colors.accent;
        const cs = mediaQuantizer.colors;
        if (!cs || cs.length === 0) return Colors.accent;

        let best = null, bestScore = -100;
        for (let i = 0; i < cs.length; i++) {
            const hsl = root.mediaHsl(cs[i]);
            // Premia color y legibilidad; penaliza blancos y negros de portada.
            const score = hsl.s * 1.75 - Math.abs(hsl.l - 0.56) * 1.35
                - (hsl.l < 0.12 || hsl.l > 0.90 ? 1.5 : 0) + (i === 0 ? 0.04 : 0);
            if (score > bestScore) { bestScore = score; best = hsl; }
        }
        if (!best || best.s < 0.15) return Colors.accent;
        const saturation = Math.max(0.45, Math.min(0.90, best.s * 1.12));
        const lightness = Math.max(0.48, Math.min(0.67, best.l));
        return Qt.hsla(best.h, saturation, lightness, 1);
    }
    property real pos: 0
    readonly property real len: (player && player.lengthSupported) ? player.length : 0
    Timer {
        interval: 500; repeat: true; running: root.player !== null && (root.open || root.mediaLive)
        onTriggered: root.pos = (root.player && root.player.positionSupported) ? root.player.position : 0
    }
    // Solo la primera letra. Font.Capitalize de Qt capitaliza TODAS las palabras
    // y en español deja cosas como "Martes, 4 De Agosto".
    function capitalize(s) { return s ? s.charAt(0).toUpperCase() + s.slice(1) : ""; }

    function fmt(sec) {
        if (!sec || sec < 0) return "0:00";
        const m = Math.floor(sec / 60), s = Math.floor(sec % 60);
        return m + ":" + (s < 10 ? "0" + s : s);
    }
    Connections {
        target: root.player
        ignoreUnknownSignals: true
        function onTrackTitleChanged() { if (root.armed && root.player && root.player.trackTitle) root.flash("track"); }
        function onIsPlayingChanged() { if (root.armed && root.player && root.player.isPlaying) root.flash("track"); }
    }

    // ═══════════════════════ audio (Pipewire) ═══════════════════════
    PwObjectTracker { objects: [Pipewire.defaultAudioSink] }
    readonly property var sink: Pipewire.defaultAudioSink
    readonly property int vol: (sink && sink.audio) ? Math.round(sink.audio.volume * 100) : 0
    readonly property bool muted: (sink && sink.audio) ? sink.audio.muted : false

    onVolChanged: if (armed) flash("volume")
    onMutedChanged: if (armed) flash("volume")

    function setVolume(pct) {
        if (!sink || !sink.audio) return;
        sink.audio.muted = false;
        sink.audio.volume = Math.max(0, Math.min(1.4, pct / 100));
    }
    function nudgeVolume(dir) {
        if (!sink || !sink.audio) return;
        sink.audio.volume = Math.max(0, Math.min(1.4, sink.audio.volume + dir * 0.02));
    }
    function toggleMute() { if (sink && sink.audio) sink.audio.muted = !sink.audio.muted; }

    // ═══════════════════ rueda horizontal sobre el notch ═══════════════════
    // La idea viene de Tide-island (deslizar sobre la isla hace algo), pero allí
    // el gesto cambia de CARA y aquí eso no cabe: en este shell cada cara sale
    // de un estado o de un botón concreto, no de un carrusel. Lo que sí sobraba
    // era el eje horizontal, que no hacía nada. Ahora cambia de escritorio.
    //
    // Dos detalles que lo separan de "restar y sumar uno":
    //
    // · SE ACUMULA. Un panel táctil no manda un evento por gesto, manda una
    //   ráfaga de decenas; sin acumular, un arrastre corto te cruzaría los diez
    //   escritorios de golpe. 120 es el equivalente a una muesca de rueda, que es
    //   la unidad que Qt usa para "un paso".
    //
    // · VA A `e+1`, NO A `id+1`. Es exactamente lo mismo que hace la rueda
    //   vertical con Super en hyprland.lua: salta al siguiente escritorio que
    //   EXISTE. Sumar al id te metería en escritorios vacíos que no habías
    //   creado, y el mapa del overview los enseña de todas formas.
    property real wsAccum: 0
    Timer { id: wsAccumReset; interval: 350; onTriggered: root.wsAccum = 0 }

    function scrollWorkspace(dx) {
        root.wsAccum += dx;
        wsAccumReset.restart();
        while (Math.abs(root.wsAccum) >= 120) {
            const dir = root.wsAccum > 0 ? 1 : -1;
            root.wsAccum -= dir * 120;
            // `e+1` va ENTRECOMILLADO. Desde 0.55 el argumento de `dispatch` es
            // una expresión Lua (ver la nota larga en OverviewPanel.qml), y ahí
            // el destino del escritorio es de dos tipos según lo que pidas: un
            // número suelto para "vete al 3", pero una CADENA para los destinos
            // simbólicos como `e+1`. Sin las comillas, Lua lee `e` como una
            // variable que no existe y revienta con error de sintaxis.
            Hyprland.dispatch('hl.dsp.focus({ workspace = "e' + (dir > 0 ? "+1" : "-1") + '" })');
            // El destello se pide YA, sin esperar a que Hyprland conteste: la
            // cara lee el escritorio activo con un binding vivo, así que si el
            // primer fotograma llega con el número viejo se corrige solo en el
            // siguiente, y eso pasa dentro de la propia animación de entrada.
            root.flash("ws");
        }
    }

    readonly property int activeWs: Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.id : 1

    // ─────────────── monitor con el foco ───────────────
    // Con varias pantallas, la barra se dibuja en TODAS pero los paneles y los
    // overlays salen solo en esta. Nombre de la salida, p. ej. "eDP-1".
    //
    // NO se usa Hyprland.focusedMonitor: en Quickshell 0.3.0 esa propiedad nace
    // vacía —igual que focusedWorkspace y que monitor.focused— y solo se rellena
    // cuando llega el primer evento. Recién arrancada la shell no sabría dónde
    // está el foco hasta que cambiases de monitor a mano, y hasta entonces los
    // paneles no aparecerían en ninguna parte. Comprobado con instancias de
    // prueba: ni refreshMonitors() ni refreshWorkspaces() la siembran. Así que se
    // pregunta una vez a hyprctl y a partir de ahí mandan los eventos.
    property string focusedMon: ""

    // La misma idea pero como objeto de pantalla, que es lo que piden las
    // superficies sueltas (picker de wallpaper, controles de medios) para salir
    // solo donde estas mirando. Si aun no se sabe el foco, la primera pantalla:
    // mas vale que salga en algun sitio que en ninguno.
    readonly property var focusedScreen: {
        const ss = Quickshell.screens;
        for (let i = 0; i < ss.length; i++)
            if (ss[i].name === root.focusedMon) return ss[i];
        return ss.length > 0 ? ss[0] : null;
    }

    Process {
        id: monSeed
        command: ["sh", "-c", "hyprctl monitors -j | jq -r '.[] | select(.focused) | .name'"]
        stdout: SplitParser {
            onRead: function (line) {
                const n = String(line).trim();
                if (n !== "") root.focusedMon = n;
            }
        }
    }
    function reseedMonitor(): void { monSeed.running = false; monSeed.running = true; }
    Component.onCompleted: root.reseedMonitor()

    Connections {
        target: Hyprland
        function onRawEvent(ev) {
            const n = String(ev.name);
            if (n === "focusedmon" || n === "focusedmonv2") {
                // data = "NOMBRE,workspace" (v2 manda el id del workspace)
                const m = String(ev.data).split(",")[0].trim();
                if (m !== "") root.focusedMon = m;
            } else if (n.indexOf("monitor") === 0) {
                // monitoradded / monitorremoved / sus v2: cambió la lista de
                // salidas, así que hay que volver a preguntar quién tiene el foco.
                root.reseedMonitor();
            }
        }
    }

    // ─────────────── espectro de audio (cava) ───────────────
    // Las barritas del notch. Antes esto era un PwNodePeakMonitor: UN solo
    // número (el pico global del sink) que se iba desplazando por el array. Eso
    // no es un espectro, es la misma señal repetida 14 veces —todas las barras
    // subían y bajaban juntas— y como el pico en lineal casi siempre roza 1, se
    // quedaban clavadas al techo (efecto código de barras). Peor: onPeakChanged
    // solo salta cuando el valor CAMBIA, así que en un tramo comprimido dejaba
    // de llegar señal y las barras se CONGELABAN.
    //
    // cava sí hace FFT: da `bands` valores independientes por frame, de graves
    // a agudos, y con su propio autosens (música baja llena igual, música alta
    // no satura). Salida "raw" en ascii, una línea por frame: "0;312;…;\n".
    // La configuración vive en scripts/cava.conf.
    // Pocas y gruesas. Con 14 la tira se leía como una trama de rayas en vez
    // de como un ecualizador: a 2,5 px de ancho no se distingue una barra de
    // su vecina. Si cambias esto, cambia `bars` en scripts/cava.conf.
    readonly property int bands: 8

    // POR QUÉ NO SE PINTA EL VALOR DE CAVA TAL CUAL. Porque los valores de cava
    // PEGAN SALTOS: una misma banda va de 2 a 1000 y vuelve en un puñado de
    // fotogramas. Pintar eso directamente no es un ecualizador, es un
    // estroboscopio — y era exactamente el temblor que se veía. Medido grabando
    // el notch a 60 fps y midiendo las barras PINTADAS:
    //
    //                            salto máximo   tirones
    //   pintando el valor tal cual   16,7 px     0,200
    //   con este seguidor             1,3 px     0,079
    //
    // Así que cava solo pone el OBJETIVO, y quien MUEVE la barra es el reloj de
    // la pantalla: un FrameAnimation que en cada fotograma la acerca un poco,
    // según el tiempo REAL transcurrido (frameTime). Es lo que hace caelestia
    // (Internal/visualiserbars.cpp: alpha = 1 - exp(-dt/tau)), de donde viene la
    // arquitectura de esta barra.
    //
    // Exponencial a propósito: avanzar una FRACCIÓN de lo que falta no da saltos
    // ni frenazos —la velocidad es continua— y al ir ligado al tiempo real da
    // igual que se pierda un fotograma: la barra está siempre donde le toca.
    //
    // Lo que NO funciona, probado y medido: suavizar en cava (noise_reduction),
    // suavizar el valor recibido, o cuantizar la altura en escalones. Todo eso
    // toca los NÚMEROS, y lo que tiene que ser continuo es el MOVIMIENTO.
    //
    // SUBE RÁPIDO Y BAJA DESPACIO, como un vúmetro. Con una sola constante para
    // los dos sentidos la barra se DESPLOMA tan deprisa como sube: a tau 35 se
    // come el 38% de lo que le falta en cada fotograma, así que un pico se
    // deshace en tres fotogramas (~50 ms). Eso no se lee como una barra que
    // baja, se lee como una barra que se apaga — un parpadeo.
    //
    // Separando ataque y caída, el golpe sigue llegando igual de seco (es lo que
    // marca el ritmo) pero el regreso es un deslizamiento de ~1/3 de segundo,
    // que es tiempo de sobra para que el ojo lo siga como movimiento continuo.
    //
    // tau = ms que tarda en comerse el 63% de lo que le falta. Más bajo = más
    // pegado a la música y más nervioso; más alto = más suave y más perezoso.
    // La caída no puede pasar de ~150: por encima, dos golpes seguidos de un
    // bombo a 120 bpm se solapan y la barra deja de marcar el compás.
    readonly property int cavaSube: 32    // ataque
    readonly property int cavaBaja: 110   // caída

    property var cavaTarget: new Array(bands).fill(0)   // lo que dice cava
    property var levels: new Array(bands).fill(0)       // lo que se pinta
    property bool cavaQuieto: true

    FrameAnimation {
        // Sigue corriendo tras parar la música hasta que las barras han bajado
        // del todo: así se deslizan hasta el suelo en vez de desaparecer de golpe.
        running: cavaProc.running || !root.cavaQuieto
        onTriggered: {
            // smoothFrameTime y no frameTime: el hueco real entre fotogramas
            // fluctúa (16,7 · 12 · 21 · 16…), y como el paso del seguidor se
            // calcula con ese hueco, usar el crudo hace que la barra avance a
            // trompicones aunque la señal sea perfecta. Qt promedia esa medida
            // justo para esto; el error de posición que introduce se corrige
            // solo en el fotograma siguiente, porque el seguidor persigue el
            // objetivo, no acumula.
            const dt = smoothFrameTime * 1000;
            const aSube = 1 - Math.exp(-dt / root.cavaSube);
            const aBaja = 1 - Math.exp(-dt / root.cavaBaja);
            const out = new Array(root.bands);
            let quieto = true;
            for (let i = 0; i < root.bands; i++) {
                const falta = root.cavaTarget[i] - root.levels[i];
                if (Math.abs(falta) > 0.001) {
                    out[i] = root.levels[i] + falta * (falta > 0 ? aSube : aBaja);
                    quieto = false;
                } else {
                    out[i] = root.cavaTarget[i];
                }
            }
            root.levels = out;
            root.cavaQuieto = quieto;
        }
    }

    // Enciende y apaga cava con la música, y lo RESUCITA si se muere.
    //
    // Aquí NO se pone `running: root.mediaLive`, que es lo natural y estuvo así
    // hasta el 7-ago-2026: cuando el proceso muere (se cae, o alguien lo mata),
    // quickshell escribe running=false, y esa escritura ROMPE el binding. A
    // partir de ahí cava no vuelve a arrancar nunca —ni recargando la config— y
    // el visualizador se queda con las ocho barras planas aunque suene música.
    // Se gobierna a mano: el temporizador reafirma el estado cada 3 s, así que
    // como mucho tarda eso en levantarse solo. triggeredOnStart = arranca ya al
    // empezar a sonar, sin esperar al primer tic.
    Timer {
        interval: 3000
        repeat: true
        triggeredOnStart: true
        running: root.mediaLive
        onTriggered: cavaProc.running = true
    }
    onMediaLiveChanged: if (!root.mediaLive) cavaProc.running = false

    Process {
        id: cavaProc
        command: ["cava", "-p", root.home + "/.config/quickshell/scripts/cava.conf"]
        stdout: SplitParser {
            onRead: function (line) {
                const parts = line.split(";");
                const out = new Array(root.bands);
                for (let i = 0; i < root.bands; i++) {
                    const v = Math.max(0, Math.min(1, (+parts[i] || 0) / 1000));
                    // Gamma: en lineal los agudos son tan pequeños al lado de
                    // los graves que en 18px de alto no se verían moverse.
                    out[i] = Math.pow(v, 0.6);
                }
                root.cavaTarget = out;   // solo el objetivo; mover es del FrameAnimation
                root.cavaQuieto = false;
            }
        }
        // Al pausar, cava muere y el objetivo se quedaría con la última foto:
        // barras a media altura durante todo el fundido de salida.
        onRunningChanged: if (!running) root.cavaTarget = new Array(root.bands).fill(0)
    }

    // ═══════════════════════ brillo ═══════════════════════
    property int bright: -1
    Process {
        id: brightProc
        stdout: SplitParser {
            onRead: function (line) {
                const v = parseInt(line.trim());
                if (!isNaN(v)) { root.bright = v; root.flash("brightness"); }
            }
        }
    }
    // `-c backlight` en TODAS las llamadas, y no por gusto: sin clase,
    // brightnessctl recorre backlight y luego leds, y se queda con la primera
    // que tenga algo. En un equipo sin panel interno no hay backlight, o sea
    // que las teclas XF86MonBrightness acabarian encendiendo y apagando el LED
    // de bloq-mayus y el OSD del notch te ensenaria ese 0/100 como si fuera el
    // brillo de la pantalla. Con la clase fijada no hay dispositivo, no hay
    // salida, no hay destello: la tecla no hace nada, que es la verdad.
    function stepBrightness(dir) {
        brightProc.command = ["bash", "-c",
            "brightnessctl -c backlight -m set 5%" + (dir === "down" ? "-" : "+") +
            " >/dev/null 2>&1; brightnessctl -c backlight -m 2>/dev/null | awk -F, '{gsub(\"%\",\"\",$4); print $4}'"];
        brightProc.running = false;
        brightProc.running = true;
    }
    // El 0 es alcanzable A PROPÓSITO (pantalla apagada del todo): no hay suelo
    // en 1, solo se recorta al rango válido. brightnessctl también llega a 0
    // por su cuenta con las teclas (5%- se queda en el raw 0, verificado).
    function setBrightness(pct) {
        // Sin panel no hay nada que mover, y sin este guardia el slider (que ya
        // no se dibuja, pero la funcion sigue siendo publica) escribiria sobre
        // el primer LED que encontrase.
        if (root.bright < 0) return;
        const v = Math.max(0, Math.min(100, Math.round(pct)));
        Quickshell.execDetached(["brightnessctl", "-c", "backlight", "-q", "set", v + "%"]);
        root.bright = v;
    }

    // ═══════════════════════ sistema ═══════════════════════
    property int cpu: 0
    property int mem: 0
    property int batt: -1
    property int disk: 0
    property bool ac: false
    property real memUsedKib: 0
    property real memTotalKib: 0
    property real diskUsedBytes: 0
    property real diskTotalBytes: 0
    property real cpuTemp: -1
    property real cpuLoad: 0
    property int uptimeSeconds: 0
    property int cpuThreads: 1

    // Sesenta muestras a 1,5 s: minuto y medio de contexto. Se sustituyen los
    // arrays enteros (en vez de mutarlos) para que Canvas reciba valuesChanged
    // y repinte las curvas aunque el porcentaje actual coincida con el anterior.
    property var cpuHistory: []
    property var memHistory: []
    property var tempHistory: []
    function appendMetric(history, value) {
        const next = history.slice(Math.max(0, history.length - 59));
        next.push(isFinite(value) ? value : 0);
        return next;
    }
    Process {
        command: [root.home + "/.config/quickshell/scripts/sysstats.sh"]
        running: true
        stdout: SplitParser {
            onRead: function (line) {
                const p = line.trim().split(/\s+/);
                if (p.length < 8) return;
                root.cpu = parseInt(p[0]); root.mem = parseInt(p[1]);
                root.batt = parseInt(p[2]); root.ac = p[3] === "1";
                if (p.length >= 9) root.disk = parseInt(p[8]);
                if (p.length >= 17) {
                    root.memUsedKib = parseFloat(p[9]);
                    root.memTotalKib = parseFloat(p[10]);
                    root.diskUsedBytes = parseFloat(p[11]);
                    root.diskTotalBytes = parseFloat(p[12]);
                    const milliC = parseFloat(p[13]);
                    root.cpuTemp = milliC >= 0 ? milliC / 1000 : -1;
                    root.cpuLoad = parseFloat(p[14]);
                    root.uptimeSeconds = parseInt(p[15]);
                    root.cpuThreads = Math.max(1, parseInt(p[16]));
                }
                root.cpuHistory = root.appendMetric(root.cpuHistory, root.cpu);
                root.memHistory = root.appendMetric(root.memHistory, root.mem);
                if (root.cpuTemp >= 0)
                    root.tempHistory = root.appendMetric(root.tempHistory, root.cpuTemp);
                if (root.bright < 0) root.bright = parseInt(p[4]);   // solo el valor inicial
            }
        }
    }
    // ENCHUFAR Y DESENCHUFAR son de las poquisimas cosas que le pasan al
    // portatil SIN que tu toques nada y que quieres saber en el momento. El
    // resto de lo que sale en el notch lo provocas tu; esto lo provoca el
    // mundo, y por eso merece cara propia en vez de un icono mas en la barra.
    //
    // El `armed` no sobra: sysstats.sh escupe la primera linea a los pocos
    // milisegundos de arrancar y ese primer valor NO es un cambio, es el estado
    // inicial. Sin el guardia, cada reinicio de la shell te saludaria con un
    // "Cargando" que no habias pedido.
    onAcChanged: if (root.armed) root.flash("charge")

    readonly property string battIcon: ac ? "󰂄"
        : batt < 0 ? "󰂑"
        : batt >= 90 ? "󰁹" : batt >= 70 ? "󰂂" : batt >= 50 ? "󰁿"
        : batt >= 30 ? "󰁼" : batt >= 15 ? "󰁻" : "󰁺"

    // UPower expone los datos eléctricos ya normalizados (Wh, W y segundos).
    // sysstats sigue llevando el porcentaje rápido del notch; esta capa añade
    // la información que merece una pantalla de Ajustes: desgaste, capacidad,
    // ciclos y estimación temporal.
    readonly property var batteryDevice: {
        const ds = UPower.devices ? UPower.devices.values : [];
        for (let i = 0; i < ds.length; i++)
            if (ds[i] && ds[i].isLaptopBattery && ds[i].isPresent) return ds[i];
        const display = UPower.displayDevice;
        return (display && display.isPresent) ? display : null;
    }
    readonly property real battHealth: batteryDevice && batteryDevice.ready
        && batteryDevice.healthSupported ? batteryDevice.healthPercentage : -1
    readonly property real battFullWh: batteryDevice && batteryDevice.ready
        ? batteryDevice.energyCapacity : -1
    readonly property real battDesignWh: battHealth > 0 && battFullWh > 0
        ? battFullWh / (battHealth / 100) : -1
    readonly property real battRateW: batteryDevice && batteryDevice.ready
        ? Math.abs(batteryDevice.changeRate) : -1
    readonly property real battEstimateSeconds: {
        if (!batteryDevice || !batteryDevice.ready) return -1;
        const seconds = root.ac ? batteryDevice.timeToFull : batteryDevice.timeToEmpty;
        return seconds > 0 ? seconds : -1;
    }
    property int battCycles: -1

    function fmtBatteryTime(seconds) {
        if (!isFinite(seconds) || seconds <= 0) return "";
        const mins = Math.max(1, Math.round(seconds / 60));
        const h = Math.floor(mins / 60), m = mins % 60;
        if (h <= 0) return I18n.tr("{0} min", m);
        return m > 0 ? I18n.tr("{0} h {1} min", h, m) : I18n.tr("{0} h", h);
    }
    function fmtWh(value) { return value > 0 ? I18n.tr("{0} Wh", value.toFixed(1)) : ""; }
    readonly property string battEstimateText: {
        if (root.batt < 0) return I18n.tr("sin batería");
        if (root.ac && root.batt >= 99 && root.battEstimateSeconds < 0) return I18n.tr("completa");
        const time = root.fmtBatteryTime(root.battEstimateSeconds);
        if (time.length === 0) return I18n.tr("calculando…");
        // Frase entera y no `time + sufijo`: en inglés el orden no tiene por qué
        // ser el mismo, y cada rama necesita su propia traducción.
        return root.ac ? I18n.tr("{0} para completar", time) : I18n.tr("{0} restantes", time);
    }

    Process {
        id: battCyclesProc
        stdout: SplitParser {
            onRead: function (line) {
                const cycles = parseInt(line.trim());
                if (!isNaN(cycles) && cycles >= 0) root.battCycles = cycles;
            }
        }
    }
    function refreshBatteryCycles() {
        if (!root.batteryDevice || battCyclesProc.running) return;
        const nativeName = String(root.batteryDevice.nativePath || "");
        if (!/^[A-Za-z0-9._-]+$/.test(nativeName)) return;
        battCyclesProc.command = ["cat", "/sys/class/power_supply/" + nativeName + "/cycle_count"];
        battCyclesProc.running = true;
    }
    onBatteryDeviceChanged: root.refreshBatteryCycles()
    Timer {
        interval: 3600000
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: root.refreshBatteryCycles()
    }

    // ═══════════════════════ captura de pantalla ═══════════════════════
    // Hyprland lo cuenta por su socket de sucesos: "screencast>>estado,dueño".
    //
    // MEDIDO en este portátil, y es justo lo que hace que esto no sea trivial:
    //   grim (pantallazo)      -> 1,monitor  …  0,monitor
    //   una grabación de zona  -> 1,region
    //   TU PROPIO overview     -> 1,window, UNA POR VENTANA
    // O sea que contar todos los sucesos encendería el aviso de "te están
    // grabando" cada vez que pulsas Super+Tab. Solo cuentan monitor y region.
    //
    // Y el retardo tampoco es por gusto: un pantallazo con grim abre y cierra
    // la captura en menos de medio segundo. Sin esperar, la barra daría un
    // fogonazo rojo cada vez que haces una captura, que es exactamente cuando
    // menos quieres un elemento nuevo apareciendo en la pantalla.
    property int castCount: 0
    property bool casting: false
    Timer { id: castArm; interval: 1500; onTriggered: root.casting = root.castCount > 0 }

    Connections {
        target: Hyprland
        function onRawEvent(ev) {
            if (String(ev.name) !== "screencast") return;
            const p = String(ev.data).split(",");
            if (p.length < 2) return;
            if (p[1] !== "monitor" && p[1] !== "region") return;
            root.castCount = Math.max(0, root.castCount + (p[0] === "1" ? 1 : -1));
            if (root.castCount > 0) {
                castArm.restart();
            } else {
                castArm.stop();
                root.casting = false;
            }
        }
    }

    // ═══════════════════════ la burbuja satélite ═══════════════════════
    // Un cuerpo pequeño que asoma por DETRÁS del borde derecho del notch cuando
    // hay algo corriendo de fondo.
    //
    // Por qué un satélite y no una cara más: el notch en reposo mide exactamente
    // la banda reservada y no puede crecer solo — esa es la regla que hace que
    // no tape ninguna ventana nunca. Una cuenta atrás dura minutos, así que no
    // cabe ahí sin romperla. Un cuerpo aparte sí: nace detrás del borde, se
    // queda DENTRO de la banda, y el notch sigue siendo del mismo tamaño.
    //
    // Esto es un HUECO, no un temporizador. Hoy lo llenan dos cosas y meter una
    // tercera (una descarga, una compilación) es una línea más en bubbleKind.
    // El temporizador manda sobre el trabajo de fondo porque el temporizador lo
    // has pedido tú y el otro ocurre solo.
    readonly property string bubbleKind: timerTotal > 0 ? "timer" : (busy ? "busy" : "")
    readonly property bool bubbleOn: bubbleKind !== ""
    // -1 = indeterminado: sabemos que sigue, no cuánto le queda.
    readonly property real bubbleProgress: (bubbleKind === "timer" && timerTotal > 0)
        ? Math.max(0, Math.min(1, timerLeft / timerTotal)) : -1
    readonly property string bubbleIcon: bubbleKind === "timer"
        ? (timerDone ? Icons.alarm : (timerRunning ? Icons.timer : Icons.pause))
        : Icons.sync
    readonly property string bubbleLabel: bubbleKind === "timer"
        ? (timerDone ? I18n.tr("¡Tiempo!") : timerClock(timerLeft))
        : I18n.tr("Sincronizando")
    readonly property bool bubbleAlert: timerDone

    // "Estoy haciendo algo y tarda." Solo la sincronización que pides tú con el
    // clic derecho sobre las actualizaciones, no la comprobación automática de
    // cada cinco minutos: esa ocurre sola y encender un cuerpo nuevo en la
    // pantalla cada cinco minutos es ruido, no información.
    readonly property bool busy: pacmanProc.running && pacmanProc.forceSync

    // ── el temporizador ──
    property int timerTotal: 0        // segundos pedidos; 0 = no hay temporizador
    property int timerLeft: 0
    property bool timerRunning: false
    property bool timerDone: false    // ya sonó y aún no lo has descartado

    Timer {
        interval: 1000
        repeat: true
        running: root.timerRunning
        onTriggered: {
            root.timerLeft = Math.max(0, root.timerLeft - 1);
            if (root.timerLeft > 0) return;
            root.timerRunning = false;
            root.timerDone = true;
            // Nosotros SOMOS el servidor de notificaciones (ver más abajo), así
            // que este notify-send da la vuelta y vuelve a nuestro propio notch.
            // No hace falta inventar un aviso: se usa el que ya existe, y de
            // paso queda en el historial del centro de control.
            Quickshell.execDetached(["notify-send", "-u", "critical",
                                     "-a", I18n.tr("Temporizador"),
                                     I18n.tr("Temporizador"),
                                     I18n.tr("{0} cumplidos", root.timerSpoken(root.timerTotal))]);
        }
    }

    function timerStart(seconds) {
        if (seconds <= 0) return;
        root.timerTotal = seconds;
        root.timerLeft = seconds;
        root.timerDone = false;
        root.timerRunning = true;
    }
    // Un clic en la burbuja: si ya sonó, la descarta; si no, pausa y reanuda.
    function timerToggle() {
        if (root.timerDone) { root.timerClear(); return; }
        if (root.timerTotal <= 0) return;
        root.timerRunning = !root.timerRunning;
    }
    function timerClear() {
        root.timerRunning = false;
        root.timerTotal = 0;
        root.timerLeft = 0;
        root.timerDone = false;
    }

    // mm:ss, y hh:mm:ss solo si de verdad hay horas. Un "00:09:59" para diez
    // minutos son dos dígitos que no dicen nada ocupando sitio en un cuerpo de
    // 28 px.
    function timerClock(sec) {
        const h = Math.floor(sec / 3600), m = Math.floor((sec % 3600) / 60), x = sec % 60;
        const two = n => (n < 10 ? "0" + n : String(n));
        return h > 0 ? (h + ":" + two(m) + ":" + two(x)) : (m + ":" + two(x));
    }
    // Cómo se dice en voz alta, para el aviso: "25 min", "1 h 30 min".
    function timerSpoken(sec) {
        const h = Math.floor(sec / 3600), m = Math.floor((sec % 3600) / 60), x = sec % 60;
        const parts = [];
        if (h > 0) parts.push(I18n.tr("{0} h", h));
        if (m > 0) parts.push(I18n.tr("{0} min", m));
        if (x > 0 && h === 0) parts.push(I18n.tr("{0} s", x));
        return parts.join(" ");
    }

    // ── de lo que escribes a segundos ──
    // Reconoce "10m", "25 min", "1h", "90s", "1h30", "1h 5 min".
    //
    // EXIGE UNIDAD a propósito. Un "5" suelto es una búsqueda, y si el lanzador
    // propusiera una cuenta atrás cada vez que tecleas un número se metería en
    // medio de todas las búsquedas que empiezan por cifra. Es la misma regla que
    // ya usa la calculadora para no dispararse con "7zip".
    function parseDuration(text) {
        const t = String(text || "").trim().toLowerCase().replace(/\s+/g, "");
        if (t.length === 0) return -1;
        // "1h30" = una hora y media. Es como lo escribe todo el mundo y no
        // encaja en la forma con unidades, así que va aparte.
        const hm = t.match(/^(\d+)h(\d{1,2})$/);
        if (hm) return parseInt(hm[1]) * 3600 + parseInt(hm[2]) * 60;
        const m = t.match(/^(?:(\d+)(?:horas?|h))?(?:(\d+)(?:minutos?|mins?|m))?(?:(\d+)(?:segundos?|segs?|s))?$/);
        if (!m || (!m[1] && !m[2] && !m[3])) return -1;
        const sec = parseInt(m[1] || 0) * 3600 + parseInt(m[2] || 0) * 60 + parseInt(m[3] || 0);
        return (sec > 0 && sec <= 86400) ? sec : -1;
    }

    // ═══════════════════════ red ═══════════════════════
    readonly property var wifiDev: {
        const ds = Networking.devices ? Networking.devices.values : [];
        for (let i = 0; i < ds.length; i++) if (ds[i].type === DeviceType.Wifi) return ds[i];
        return null;
    }
    readonly property var wiredDev: {
        const ds = Networking.devices ? Networking.devices.values : [];
        for (let i = 0; i < ds.length; i++) if (ds[i].type === DeviceType.Wired && ds[i].connected) return ds[i];
        return null;
    }
    readonly property var wifiNet: {
        if (!wifiDev || !wifiDev.networks) return null;
        const ns = wifiDev.networks.values;
        for (let i = 0; i < ns.length; i++) if (ns[i].connected) return ns[i];
        return null;
    }
    readonly property bool online: wiredDev !== null || wifiNet !== null

    // Si el equipo TIENE radio wifi. Una torre conectada por cable no tiene
    // ninguna, y sin esto el shell no sabía distinguir "no hay adaptador" de
    // "el adaptador está apagado": enseñaba un interruptor de wifi que no
    // encendía nada y una lista vacía con el rótulo "Wi-Fi apagado", como si
    // bastara con pulsarlo. Se mira el dispositivo, no wifiEnabled, porque
    // NetworkManager reporta la radio como deshabilitada también cuando
    // sencillamente no hay ninguna.
    readonly property bool hasWifi: wifiDev !== null

    // ---- lista de wifis para el panel de red ----
    // Espejo de SOLO LECTURA del estado real de NetworkManager.
    //
    // Antes era una property normal ligada a Networking.wifiEnabled MAS un
    // onWifiOnChanged que la reescribia. Dos consecuencias, las dos observadas
    // en vivo el 2026-08-05:
    //   1. al arrancar la shell, wifiEnabled se lee false antes de que lleguen
    //      los datos de NetworkManager; el handler devolvia ese false y LA
    //      SHELL TE APAGABA EL WIFI SOLA. Queda en el audit de NM:
    //      op="radio-control" arg="wireless-enabled:off" pid=<el de qs>, con
    //      el vaiven off/on/off de un lazo. Y como systemd-rfkill persiste el
    //      bloqueo, el portatil arrancaba SIN WIFI los dias siguientes.
    //   2. asignar a una property ligada DESTRUYE el binding, asi que al primer
    //      clic el interruptor dejaba de reflejar la realidad para siempre.
    // Por eso ahora es readonly y todo cambio pasa por setWifi/toggleWifi, que
    // solo se llaman desde un gesto explicito del usuario.
    readonly property bool wifiOn: Networking.wifiEnabled
    function setWifi(on) { Networking.wifiEnabled = on; }
    function toggleWifi() { root.setWifi(!root.wifiOn); }

    // El escáner solo se enciende mientras el panel de red está abierto: si no,
    // NetworkManager está barriendo el aire todo el rato para nada.
    // Escanear/descubrir solo mientras el panel correspondiente está abierto:
    // si no, NetworkManager y Bluez barren el aire todo el rato para nada.
    //
    // Binding declarativo y NO un onPanelChanged: el manejador imperativo solo
    // se disparaba al cambiar de panel, así que si encendías el bluetooth desde
    // dentro de su propio panel el descubrimiento no arrancaba nunca. Así se
    // reevalúa también cuando cambia el estado del adaptador.
    Binding {
        target: root.wifiDev
        property: "scannerEnabled"
        value: root.panel === "network"
        when: root.wifiDev !== null
        restoreMode: Binding.RestoreNone
    }
    // La sección Bluetooth de Ajustes también quiere descubrir mientras está
    // abierta. Lo pide por aquí en vez de escribir `discovering` a mano: dos
    // sitios escribiendo la misma propiedad (uno con Binding y otro
    // imperativamente) es una carrera, y quien perdía era Ajustes en cuanto
    // cambiaba el panel del notch.
    property bool btScanWanted: false
    Binding {
        target: root.btAdapter
        property: "discovering"
        value: (root.panel === "bluetooth" || root.btScanWanted) && root.btOn
        when: root.btAdapter !== null
        restoreMode: Binding.RestoreNone
    }

    // Un mismo SSID puede aparecer varias veces (varios puntos de acceso): se
    // deja el de mejor señal. Orden: conectada, luego guardadas, luego señal.
    readonly property var wifiNetworks: {
        if (!wifiDev || !wifiDev.networks) return [];
        const ns = wifiDev.networks.values;
        const best = {};
        for (let i = 0; i < ns.length; i++) {
            const n = ns[i];
            const k = n.name || "";
            if (k.length === 0) continue;
            const prev = best[k];
            if (!prev || (n.signalStrength || 0) > (prev.signalStrength || 0)) best[k] = n;
        }
        const out = [];
        for (const k in best) out.push(best[k]);
        out.sort(function (a, b) {
            if (a.connected !== b.connected) return a.connected ? -1 : 1;
            if (a.known !== b.known) return a.known ? -1 : 1;
            return (b.signalStrength || 0) - (a.signalStrength || 0);
        });
        return out;
    }

    // Umbrales apretados a propósito: en la práctica las señales caen entre 30 y
    // 60, y con el reparto "clásico" (75/50/25) salían todas con el mismo icono.
    function wifiIconFor(s) {
        return s >= 72 ? "󰤨" : s >= 48 ? "󰤥" : s >= 24 ? "󰤢" : "󰤟";
    }
    function isSecured(net) {
        if (!net) return false;
        return net.security !== WifiSecurityType.Open && net.security !== WifiSecurityType.Unknown;
    }
    function isEnterprise(net) {
        if (!net) return false;
        return net.security === WifiSecurityType.WpaEap
            || net.security === WifiSecurityType.Wpa2Eap
            || net.security === WifiSecurityType.Wpa3SuiteB192
            || net.security === WifiSecurityType.DynamicWep
            || net.security === WifiSecurityType.Leap;
    }
    function editEnterprise(net) {
        if (!net || !net.name) return;
        const known = Boolean(net.known);
        root.closePanel();
        Quickshell.execDetached([
            root.home + "/.config/hypr/scripts/wifi-enterprise.sh",
            known ? "edit" : "create", String(net.name)
        ]);
        root.toast(Icons.wifiLock, known
            ? I18n.tr("Abriendo credenciales de {0}", String(net.name))
            : I18n.tr("Nueva red empresarial: {0}", String(net.name)));
    }
    function openNetworkProfiles() {
        root.settingsOpen = false;
        root.closePanel();
        Quickshell.execDetached(["nm-connection-editor", "--show"]);
    }
    readonly property string netIcon: {
        if (wiredDev) return "󰈀";
        if (!wifiNet) return "󰤭";
        const s = wifiNet.signalStrength;
        return s >= 75 ? "󰤨" : s >= 50 ? "󰤥" : s >= 25 ? "󰤢" : "󰤟";
    }

    // ═══════════════════════ bluetooth ═══════════════════════
    readonly property var btAdapter: Bluetooth.defaultAdapter
    readonly property bool btOn: btAdapter ? btAdapter.enabled : false
    readonly property int btConnected: {
        const ds = Bluetooth.devices ? Bluetooth.devices.values : [];
        let n = 0;
        for (let i = 0; i < ds.length; i++) if (ds[i].connected) n++;
        return n;
    }
    readonly property string btIcon: btBlocked ? "󰂲" : !btOn ? "󰂲" : (btConnected > 0 ? "󰂱" : "󰂯")

    // Bloqueado por rfkill: el interruptor no puede hacer nada y hay que decirlo,
    // en vez de que pulsarlo se quede en nada sin explicación.
    readonly property bool btBlocked: btAdapter !== null && btAdapter.state === BluetoothAdapterState.Blocked

    // conectados primero, luego el resto de emparejados
    readonly property var btPaired: {
        const vs = Bluetooth.devices ? Bluetooth.devices.values : [];
        const out = [];
        for (let i = 0; i < vs.length; i++) if (vs[i].paired || vs[i].bonded) out.push(vs[i]);
        out.sort(function (a, b) { return (b.connected ? 1 : 0) - (a.connected ? 1 : 0); });
        return out;
    }
    readonly property var btNearby: {
        const vs = Bluetooth.devices ? Bluetooth.devices.values : [];
        const out = [];
        for (let i = 0; i < vs.length; i++) if (!vs[i].paired && !vs[i].bonded) out.push(vs[i]);
        return out;
    }
    function btLabel(d) {
        if (!d) return "";
        return d.deviceName || d.name || d.address || "";
    }
    function toggleBt() { if (btAdapter) btAdapter.enabled = !btAdapter.enabled; }

    // ═══════════════════════ actualizaciones ═══════════════════════
    // La cadencia la lleva el Timer de abajo, NO un bucle en bash. Antes esto
    // era un `bash -c "while true; do ...; sleep 300; done"` con running: true,
    // y ese bucle SOBREVIVÍA a quickshell: si qs se muere sin poder limpiar
    // (segfault, o un kill -9 mientras trasteas la config) el bash se queda
    // huérfano, lo adopta systemd --user y sigue lanzando checkupdates cada 5
    // min PARA SIEMPRE. Así se acumularon 7 el 5-ago-2026.
    //
    // Y ojo al detalle de por qué SOLO se colgaba éste y no sysstats.sh, que es
    // el mismo patrón: sysstats escribe en stdout cada 1,5 s, así que en cuanto
    // se cierra la tubería recibe SIGPIPE y se muere solo. Aquí el que escribía
    // era el script de dentro; el bucle de fuera no escribía nunca —solo
    // dormía—, así que el SIGPIPE que lo habría matado no le llegaba jamás.
    //
    // Ahora el proceso es de UN SOLO disparo: dura lo que dura la consulta y se
    // acaba. Aunque qs muera de la peor manera posible, lo más que puede quedar
    // suelto es un checkupdates que se cierra solo (el script ya lo lanza con
    // timeout 60), no un bucle inmortal.
    property string pacman: ""
    Process {
        id: pacmanProc
        // true = clic derecho: invalida la marca de tiempo y fuerza sincronización.
        property bool forceSync: false
        command: forceSync
            ? [root.home + "/.config/hypr/scripts/pacman-updates.sh", "--refresh"]
            : [root.home + "/.config/hypr/scripts/pacman-updates.sh"]
        stdout: SplitParser {
            onRead: function (line) { try { root.pacman = String(JSON.parse(line).text || ""); } catch (e) {} }
        }
        onExited: forceSync = false
    }
    Timer {
        interval: 300000
        running: true
        repeat: true
        triggeredOnStart: true   // como el bucle viejo: consulta ya al arrancar
        onTriggered: if (!pacmanProc.running) pacmanProc.running = true
    }
    function pacmanRefresh() {
        if (pacmanProc.running) return;
        pacmanProc.forceSync = true;
        pacmanProc.running = true;
    }

    // ═══════════════════════ notificaciones (servidor propio) ═══════════════════════
    // Sustituye a swaync: su "centro de control" es una ventana GTK suya, no se
    // puede meter dentro del notch. Aquí somos el servidor D-Bus y pintamos
    // nosotros tanto el aviso emergente como el historial.
    property bool dnd: false
    property var lastNotif: null

    NotificationServer {
        id: notifServer
        keepOnReload: true
        bodySupported: true
        bodyMarkupSupported: true
        imageSupported: true
        actionsSupported: true
        actionIconsSupported: true

        onNotification: function (n) {
            n.tracked = true;               // se queda en el historial
            root.lastNotif = n;
            if (!root.dnd) root.flash("notif");
        }
    }

    // más recientes primero
    readonly property var notifications: {
        const vs = notifServer.trackedNotifications ? notifServer.trackedNotifications.values : [];
        return vs.slice().reverse();
    }
    readonly property int notifCount: notifications.length

    function dismissNotif(n) { if (n) n.dismiss(); }
    function clearNotifs() {
        const vs = notifServer.trackedNotifications ? notifServer.trackedNotifications.values.slice() : [];
        for (let i = 0; i < vs.length; i++) vs[i].dismiss();
    }

    readonly property string notifIcon: dnd ? (notifCount > 0 ? "󰂠" : "󰪓")
        : (notifCount > 0 ? "󱅫" : "󰂜")

    // ═══════════════════════ luz nocturna ═══════════════════════
    property bool nightLight: false
    function toggleNightLight() {
        root.nightLight = !root.nightLight;
        Quickshell.execDetached(["bash", "-lc",
            root.nightLight ? "pgrep -x hyprsunset >/dev/null || hyprsunset -t 4000 &" : "pkill -x hyprsunset"]);
    }

    // ═══════════════════════ modo lectura ═══════════════════════
    // El script guarda/restaura el estado REAL de Hyprland. Aquí solo se refleja
    // su salida para que Ajustes y el centro de comandos nunca inventen estado.
    readonly property string readingTool: root.home + "/.config/hypr/scripts/reading-mode.sh"
    property bool readingMode: false
    property int readingPending: -1
    Process {
        id: readingProc
        property bool announce: false
        command: [root.readingTool, "status"]
        stdout: SplitParser {
            onRead: function (line) {
                const state = line.trim();
                if (state !== "on" && state !== "off") return;
                root.readingMode = state === "on";
                if (readingProc.announce) {
                    root.toast(Icons.reading, root.readingMode
                        ? I18n.tr("Modo lectura activado") : I18n.tr("Modo lectura desactivado"));
                    readingProc.announce = false;
                }
            }
        }
        onExited: function (exitCode) {
            if (exitCode !== 0 && announce)
                root.toast(Icons.reading, I18n.tr("No se pudo cambiar el modo lectura"));
            announce = false;
            if (root.readingPending >= 0) {
                const desired = root.readingPending === 1;
                root.readingPending = -1;
                Qt.callLater(function () { root.setReadingMode(desired); });
            }
        }
    }
    Timer {
        interval: 3000
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: {
            if (readingProc.running) return;
            readingProc.command = [root.readingTool, "status"];
            readingProc.running = true;
        }
    }
    function setReadingMode(on) {
        if (readingProc.running) {
            // Si el clic coincide con el sondeo de 3 s, no se pierde: se lanza
            // en cuanto ese proceso de pocos milisegundos termine.
            root.readingPending = on ? 1 : 0;
            return;
        }
        readingProc.announce = true;
        readingProc.command = [root.readingTool, on ? "on" : "off"];
        readingProc.running = true;
    }
    function toggleReadingMode() { root.setReadingMode(!root.readingMode); }

    // ═══════════════════════ acceso remoto (RustDesk) ═══════════════════════
    // remote-mode impide que hypridle apague la pantalla o suspenda el equipo.
    // Sin el, el portatil se dormia a los 20 min y quedaba inaccesible desde
    // fuera de casa (con la pantalla apagada la captura se va a negro, y a un
    // equipo suspendido no se conecta nadie). Activalo antes de salir.
    property bool remoteMode: false
    function toggleRemoteMode() {
        root.remoteMode = !root.remoteMode;
        Quickshell.execDetached([root.home + "/.local/bin/remote-mode",
            root.remoteMode ? "on" : "off"]);
    }
    // Estado real al arrancar. Lo deduce el propio script de que config tiene
    // puesta hypridle, no de un fichero de marca aparte (eso se desincronizaba
    // si un paso fallaba a medias).
    Process {
        id: remoteModeProbe
        command: [root.home + "/.local/bin/remote-mode", "is-on"]
        running: true
        stdout: SplitParser {
            onRead: function (line) { root.remoteMode = line.trim() === "on"; }
        }
    }

    // ═══════════════════════ pokemon del tema ═══════════════════════
    // El pokemon que sale al abrir la primera terminal se elige comparando la
    // paleta del sprite con la de pywal (~/.local/bin/poke-theme). Apagado
    // vuelve al azar de siempre, que es como estaba antes: el interruptor no
    // quita el pokemon, solo deja de elegirlo por color.
    property bool pokeTheme: true
    function togglePokeTheme() {
        root.pokeTheme = !root.pokeTheme;
        Quickshell.execDetached([root.home + "/.local/bin/poke-theme",
            root.pokeTheme ? "on" : "off"]);
    }
    // Estado real al arrancar (lo dice el propio script, no lo adivinamos aqui).
    Process {
        id: pokeThemeProbe
        command: [root.home + "/.local/bin/poke-theme", "is-on"]
        running: true
        stdout: SplitParser {
            onRead: function (line) { root.pokeTheme = line.trim() === "on"; }
        }
    }

    // ═══════════════════════ el tiempo ═══════════════════════
    // Heredado del Sidebar al retirarlo. Refresca cada media hora.
    //
    // Timer + proceso de un disparo, por el mismo motivo que las
    // actualizaciones de arriba: un `while true` en bash sobrevive a quickshell
    // si éste se muere de golpe. Éste no llegaba a ser inmortal —al escribir en
    // stdout cada media hora acababa comiéndose un SIGPIPE y muriendo—, pero
    // hasta que le tocaba escribir se quedaba hasta 30 min suelto haciendo una
    // petición de red por nadie. Era el último sitio con este patrón.
    property string weather: "…"
    Process {
        id: weatherProc
        // El `echo` del final NO sobra: wttr.in con ?format= responde SIN salto
        // de línea, y SplitParser corta justo por saltos de línea. Sin él la
        // lectura se queda en el buffer y el tiempo no se actualiza nunca.
        command: ["bash", "-c", "curl -s --max-time 8 'wttr.in/?format=%t·%C' 2>/dev/null; echo"]
        stdout: SplitParser {
            onRead: function (line) { if (line.trim().length) root.weather = line.trim(); }
        }
    }
    Timer {
        interval: 1800000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: if (!weatherProc.running) weatherProc.running = true
    }

    // ═══════════════════════ cafeína ═══════════════════════
    // Activa en cada arranque/recarga. El usuario puede apagarla manualmente
    // desde el notch cuando sí quiera que hypridle vuelva a actuar.
    property bool caffeine: true

    // ═══════════════════════ aplicaciones (lanzador) ═══════════════════════
    readonly property var allApps: {
        const out = [];
        const vs = DesktopEntries.applications ? DesktopEntries.applications.values : [];
        for (let i = 0; i < vs.length; i++) if (!vs[i].noDisplay) out.push(vs[i]);
        out.sort((a, b) => (a.name || "").localeCompare(b.name || ""));
        return out;
    }

    // Puntuación: cuanto más "al principio del nombre" encaje, más alto. El
    // último recurso es subsecuencia (escribir "gimp" encuentra "GNU Image...").
    function scoreApp(app, q) {
        const name = (app.name || "").toLowerCase();
        if (name === q) return 1000;
        if (name.startsWith(q)) return 900 - name.length * 0.1;
        const words = name.split(/[\s\-_.]+/);
        for (let i = 0; i < words.length; i++)
            if (words[i].startsWith(q)) return 800 - name.length * 0.1;
        const idx = name.indexOf(q);
        if (idx >= 0) return 700 - idx - name.length * 0.1;
        if ((app.genericName || "").toLowerCase().indexOf(q) >= 0) return 500;
        if ((app.comment || "").toLowerCase().indexOf(q) >= 0) return 400;
        let kw = "";
        try { kw = (app.keywords || []).join(" ").toLowerCase(); } catch (e) {}
        if (kw.indexOf(q) >= 0) return 300;
        // subsecuencia
        let ti = 0;
        for (let i = 0; i < q.length; i++) {
            ti = name.indexOf(q[i], ti);
            if (ti < 0) return -1;
            ti++;
        }
        return 200 - name.length * 0.1;
    }

    function searchApps(query) {
        const q = (query || "").trim().toLowerCase();
        if (q.length === 0) return root.allApps;
        const hits = [];
        for (let i = 0; i < root.allApps.length; i++) {
            const s = root.scoreApp(root.allApps[i], q);
            if (s > 0) hits.push({ app: root.allApps[i], score: s });
        }
        hits.sort((a, b) => b.score - a.score);
        return hits.map(h => h.app);
    }

    // ═══════════════ el lanzador como centro de comandos ═══════════════
    //
    // El lanzador deja de ser "la lista de aplicaciones" y pasa a ser la única
    // caja donde se escribe. Un carácter al principio decide QUÉ se busca:
    //
    //   (nada)  aplicaciones, y de propina la calculadora y el temporizador
    //   #       historial del portapapeles (texto e imágenes)
    //   >       acciones del sistema
    //   @       ventanas abiertas
    //
    // POR QUÉ PREFIJOS Y NO CUATRO ATAJOS. Los atajos hay que recordarlos con
    // los dedos y cada uno abre una ventana distinta que hay que aprender por
    // separado. Un prefijo se descubre solo (están escritos en el propio panel
    // cuando está vacío), se corrige con un borrado, y sobre todo: la costumbre
    // es una sola —Super+R y escribir—, que es exactamente la que ya había.
    //
    // ES LA MISMA PUERTA QUE ABRIÓ LA CALCULADORA. Escribir "2+2" en el lanzador
    // ya era escribir algo que no es un nombre de aplicación; esto solo termina
    // la idea. Por eso la calculadora y el temporizador siguen sin prefijo: no
    // son un modo, son lo que pasa cuando lo que escribes resulta ser una cuenta
    // o una duración.
    //
    // Con esto se retiran los dos últimos menús de rofi del rice (el historial
    // del portapapeles y el menú de comandos); ver README.
    property string launcherMode: "apps"     // "apps" | "clip" | "cmd" | "win"

    readonly property var launcherModes: [
        { key: "clip", prefix: "#", icon: Icons.clipboard, name: I18n.tr("Portapapeles"),
          hint: I18n.tr("Buscar en el portapapeles…") },
        { key: "cmd",  prefix: ">", icon: Icons.bolt,      name: I18n.tr("Acciones"),
          hint: I18n.tr("Buscar una acción del sistema…") },
        { key: "win",  prefix: "@", icon: Icons.windows,   name: I18n.tr("Ventanas"),
          hint: I18n.tr("Buscar una ventana abierta…") }
    ]

    readonly property var launcherAppsMode: ({ key: "apps", prefix: "", icon: "󰍉",
        name: I18n.tr("Aplicaciones"), hint: I18n.tr("Buscar aplicaciones…") })

    // "#" -> "clip". Devuelve "" si ese carácter no abre ningún modo.
    function launcherModeOf(ch) {
        for (let i = 0; i < root.launcherModes.length; i++)
            if (root.launcherModes[i].prefix === ch) return root.launcherModes[i].key;
        return "";
    }

    function launcherModeInfo(key) {
        for (let i = 0; i < root.launcherModes.length; i++)
            if (root.launcherModes[i].key === key) return root.launcherModes[i];
        return root.launcherAppsMode;
    }

    // Abrir el lanzador YA en un modo. Pulsar el atajo del modo que ya está
    // abierto lo cierra, igual que hace togglePanel con los demás paneles: un
    // atajo que abre pero no cierra obliga a ir a por Escape.
    function openLauncher(m) {
        const mode = m || "apps";
        if (root.panel === "launcher" && root.launcherMode === mode) { root.closePanel(); return; }
        root.launcherMode = mode;
        root.launcherPreload(mode);
        if (mode === "clip") root.clipRefresh();
        if (mode === "win") root.winRefresh();
        root.panel = "launcher";
    }

    // El alto de arranque. Sin esto el panel nace con el alto de la BÚSQUEDA
    // ANTERIOR y corrige en el fotograma siguiente: se ve un doble movimiento.
    // En "clip" no se sabe cuántas filas habrá hasta que conteste el proceso, así
    // que se pide el máximo y el panel encoge —hacia arriba, que es su gesto
    // natural— durante la propia animación de apertura.
    function launcherPreload(mode) {
        root.launcherCalc = false;
        root.launcherFavs = mode === "apps" && root.favApps.length > 0;
        root.launcherRows = mode === "apps" ? root.allApps.length
            : mode === "cmd" ? root.sysActions.length
            : mode === "win" ? root.winItems.length
            : root.clipItems.length > 0 ? root.clipItems.length : root.launcherMaxRows;
    }

    // ─────────────── # portapapeles ───────────────
    // Los datos los sirve scripts/cliphist-tool.sh, que sustituye al par de
    // scripts de rofi. Aquí no se decodifica nada: una entrada de imagen es un
    // binario, y meter binarios en una cadena de QML es pedir que algo se rompa
    // en silencio. El script entrega id, tipo, ruta de miniatura y etiqueta.
    readonly property string clipTool: root.home + "/.config/quickshell/scripts/cliphist-tool.sh"

    property var clipItems: []
    property bool clipLoading: false

    Process {
        id: clipListProc
        command: [root.clipTool, "list"]
        stdout: StdioCollector {
            id: clipOut
            onStreamFinished: {
                const out = [];
                const lines = String(clipOut.text).split("\n");
                for (let i = 0; i < lines.length; i++) {
                    if (lines[i].length === 0) continue;
                    const p = lines[i].split("\t");
                    if (p.length < 4) continue;
                    out.push({
                        kind: "clip",
                        id: p[0],
                        image: p[1] === "image",
                        thumb: p[2] === "-" ? "" : p[2],
                        // join por si la etiqueta trajera un tabulador que el
                        // script no hubiera limpiado: partir por el primero y
                        // volver a unir el resto no pierde texto.
                        label: p.slice(3).join("\t")
                    });
                }
                root.clipItems = out;
                root.clipLoading = false;
            }
        }
        // Red de seguridad: si el proceso muriera sin escribir nada (script
        // borrado, cliphist desinstalado), sin esto el panel se quedaría para
        // siempre en "Leyendo el portapapeles…" y con el alto máximo puesto.
        onExited: root.clipLoading = false
    }

    function clipRefresh() {
        if (clipListProc.running) return;
        root.clipLoading = true;
        clipListProc.running = true;
    }

    function searchClip(query) {
        const q = (query || "").trim().toLowerCase();
        if (q.length === 0) return root.clipItems;
        const out = [];
        for (let i = 0; i < root.clipItems.length; i++)
            if (root.clipItems[i].label.toLowerCase().indexOf(q) >= 0) out.push(root.clipItems[i]);
        return out;
    }

    // El aviso no puede llevar los 200 caracteres de la vista previa: la cara
    // "toast" mide 330 px fijos y el texto se saldría del notch por los lados.
    function clipShort(t) {
        const s = String(t).replace(/\s+/g, " ").trim();
        return s.length > 32 ? s.slice(0, 32) + "…" : s;
    }

    function clipCopy(item) {
        if (!item) return;
        Quickshell.execDetached([root.clipTool, "copy", String(item.id)]);
        root.closePanel();
        root.toast(item.image ? Icons.image : "󰆏",
                   item.image ? I18n.tr("Imagen copiada")
                              : I18n.tr("Copiado: {0}", root.clipShort(item.label)));
    }

    function clipDelete(item) {
        if (!item) return;
        Quickshell.execDetached([root.clipTool, "delete", String(item.id)]);
        // Se quita de la lista AQUÍ en vez de releerla entera: releer son 150
        // líneas y un proceso más para tachar una fila que el usuario acaba de
        // ver desaparecer. El id de cliphist no se reutiliza, así que la copia
        // local no puede quedar apuntando a otra cosa.
        const out = [];
        for (let i = 0; i < root.clipItems.length; i++)
            if (root.clipItems[i].id !== item.id) out.push(root.clipItems[i]);
        root.clipItems = out;
    }

    // ─────────────── > acciones del sistema ───────────────
    // La lista que había en ~/.config/hypr/scripts/menu.sh, más lo que ese menú
    // no podía ofrecer porque vivía fuera del shell (ajustes, mapa de
    // escritorios, no molestar, cafeína).
    //
    // Las que tienen equivalente NATIVO en el notch ya no llaman a un programa
    // externo: "Wifi" abría `kitty -e impala` y ahora abre NetworkPanel; "Apagar"
    // abría wlogout y ahora abre PowerPanel. Lanzar una terminal para tocar el
    // wifi teniendo el panel al lado era el resto de una época anterior.
    //
    // Solo `name` y `desc` son visibles: `id` es lo que despacha runAction() y
    // `keys` son las palabras que TECLEAS para encontrar la acción, que no se ven.
    // Por eso `keys` no pasa por tr(): las claves no se traducen, se ACUMULAN. Con
    // el shell en inglés, `name` y `desc` ya salen traducidos y la búsqueda casa
    // con ellos, pero quien teclee "shutdown" o "screenshot" no encontraría nada
    // si las claves siguieran solo en castellano. Con las dos listas juntas, la
    // búsqueda funciona en los dos idiomas a la vez y sin duplicar la tabla.
    readonly property var sysActions: [
        { kind: "cmd", id: "clip", icon: Icons.clipboard, name: I18n.tr("Portapapeles"),
          desc: I18n.tr("Historial de copiado"),
          keys: "clipboard cliphist copiar pegar historial copy paste history" },
        { kind: "cmd", id: "lock", icon: Icons.lock, name: I18n.tr("Bloquear pantalla"),
          desc: "hyprlock",
          keys: "lock bloquear candado lock screen padlock" },
        { kind: "cmd", id: "night", icon: Icons.moon, name: I18n.tr("Luz nocturna"),
          desc: I18n.tr("Alternar hyprsunset"),
          keys: "night light nocturna calida azul hyprsunset warm blue filter" },
        { kind: "cmd", id: "reading", icon: Icons.reading, name: I18n.tr("Modo lectura"),
          desc: readingMode ? I18n.tr("Desactivar papel y tinta")
                            : I18n.tr("Papel cálido, tinta y menos movimiento"),
          keys: "lectura leer reading eink e-ink papel tinta concentracion read paper ink focus" },
        { kind: "cmd", id: "shot", icon: Icons.screenshot, name: I18n.tr("Captura + anotar"),
          desc: I18n.tr("Recorte y edición"),
          keys: "screenshot captura pantallazo anotar recortar screen shot annotate crop snip" },
        { kind: "cmd", id: "wall", icon: Icons.wallpaper, name: I18n.tr("Cambiar fondo"),
          desc: I18n.tr("Selector de fondos de pantalla"),
          keys: "wallpaper fondo escritorio papel background desktop change" },
        { kind: "cmd", id: "pick", icon: Icons.eyedropper, name: I18n.tr("Cuentagotas de color"),
          desc: I18n.tr("Copia el color del píxel"),
          keys: "color picker cuentagotas hex pipeta colour eyedropper dropper pixel" },
        { kind: "cmd", id: "ocr", icon: Icons.ocr, name: I18n.tr("OCR: extraer texto"),
          desc: I18n.tr("Texto de una zona de pantalla"),
          keys: "ocr texto reconocer leer imagen text recognise extract image" },
        { kind: "cmd", id: "rec", icon: Icons.video, name: I18n.tr("Grabar pantalla"),
          desc: I18n.tr("Iniciar o parar la grabación"),
          keys: "record grabar video captura recording screen capture" },
        { kind: "cmd", id: "wifi", icon: Icons.wifi, name: I18n.tr("Wifi"),
          desc: I18n.tr("Redes disponibles"),
          keys: "wifi red network internet wi-fi wireless networks" },
        { kind: "cmd", id: "bt", icon: Icons.bluetooth, name: I18n.tr("Bluetooth"),
          desc: I18n.tr("Dispositivos emparejados"),
          keys: "bluetooth bt auriculares mando headphones headset controller pair devices" },
        { kind: "cmd", id: "overview", icon: Icons.grid, name: I18n.tr("Mapa de escritorios"),
          desc: I18n.tr("Ver y mover ventanas"),
          keys: "overview escritorios workspaces mapa workspace map windows grid" },
        { kind: "cmd", id: "system", icon: Icons.cpu, name: I18n.tr("Tu equipo"),
          desc: I18n.tr("Actividad, temperatura y batería"),
          keys: "sistema monitor cpu ram memoria disco temperatura bateria rendimiento equipo system memory disk temperature battery performance machine" },
        { kind: "cmd", id: "settings", icon: Icons.cog, name: I18n.tr("Ajustes"),
          desc: I18n.tr("Apariencia, sonido, atajos…"),
          keys: "settings ajustes preferencias config preferences configuration" },
        { kind: "cmd", id: "keys", icon: Icons.keyboard, name: I18n.tr("Atajos de teclado"),
          desc: I18n.tr("Mapa vivo de teclas de Hyprland"),
          keys: "atajos teclas teclado keybinds shortcuts hotkeys mapa keyboard keys map" },
        { kind: "cmd", id: "dnd", icon: Icons.bellOff, name: I18n.tr("No molestar"),
          desc: I18n.tr("Silenciar notificaciones"),
          keys: "dnd molestar silencio notificaciones do not disturb silence notifications mute" },
        { kind: "cmd", id: "caffeine", icon: Icons.coffee, name: I18n.tr("Café"),
          desc: I18n.tr("Impedir que se apague la pantalla"),
          keys: "caffeine cafe insomnio despierto suspender coffee awake keep screen on sleep" },
        { kind: "cmd", id: "saver", icon: Icons.monitor, name: I18n.tr("Salvapantallas"),
          desc: I18n.tr("Arrancarlo ahora"),
          keys: "screensaver salvapantallas screen saver idle" },
        { kind: "cmd", id: "power", icon: Icons.power, name: I18n.tr("Apagar / salir"),
          desc: I18n.tr("Apagar, reiniciar, cerrar sesión"),
          keys: "power apagar reiniciar salir logout suspender shutdown shut down restart reboot log out sign out suspend hibernate" }
    ]

    function searchActions(query) {
        const q = (query || "").trim().toLowerCase();
        if (q.length === 0) return root.sysActions;
        const out = [];
        for (let i = 0; i < root.sysActions.length; i++) {
            const a = root.sysActions[i];
            const hay = (a.name + " " + a.desc + " " + a.keys).toLowerCase();
            if (hay.indexOf(q) >= 0) out.push(a);
        }
        return out;
    }

    function runAction(a) {
        if (!a) return;
        const S = root.home + "/.config/hypr/scripts/";

        // ── las que se quedan DENTRO del shell ──
        // No cierran el panel: cambian de cara. Cerrar y volver a abrir en el
        // mismo instante hace parpadear el notch entero.
        switch (a.id) {
        case "clip":     root.openLauncher("clip"); return;
        case "wifi":     root.panel = "network"; return;
        case "bt":       root.panel = "bluetooth"; return;
        case "power":    root.panel = "power"; return;
        case "overview": Hyprland.refreshToplevels(); root.panel = "overview"; return;
        case "system":   root.panel = "system"; return;
        case "settings": root.closePanel(); root.settingsOpen = true; return;
        case "keys":     root.closePanel(); root.openSettingsAt("keys"); return;
        case "reading":
            root.closePanel(); root.toggleReadingMode(); return;
        case "dnd":
            root.dnd = !root.dnd; root.closePanel();
            root.toast(Icons.bell, root.dnd ? I18n.tr("No molestar activado")
                                            : I18n.tr("No molestar desactivado"));
            return;
        case "caffeine":
            root.caffeine = !root.caffeine; root.closePanel();
            root.toast(Icons.coffee, root.caffeine ? I18n.tr("Café: la pantalla no se apaga")
                                                   : I18n.tr("Café desactivado"));
            return;
        }

        // ── las que salen fuera: cerrar primero ──
        // Varias de estas congelan la pantalla o piden un recorte, y hacerlo con
        // el panel todavía puesto lo dejaría dentro de la foto.
        root.closePanel();
        switch (a.id) {
        case "lock":  Quickshell.execDetached(["loginctl", "lock-session"]); break;
        case "night": Quickshell.execDetached([S + "hyprsunset-toggle.sh"]); break;
        case "shot":  Quickshell.execDetached([S + "screenshot-annotate.sh"]); break;
        case "pick":  Quickshell.execDetached([S + "colorpicker.sh"]); break;
        case "ocr":   Quickshell.execDetached([S + "ocr.sh"]); break;
        case "rec":   Quickshell.execDetached([S + "screenrecord.sh"]); break;
        case "saver": Quickshell.execDetached([S + "screensaver.sh"]); break;
        // El selector de fondos NATIVO (WallpaperPicker.qml) es una ventana
        // aparte, no un panel del notch, y solo se abre por su atajo global. Es
        // la misma llamada que usa el botón de Ajustes › Apariencia.
        case "wall":  Hyprland.dispatch('hl.dsp.global("quickshell:wallpaper")'); break;
        }
    }

    // ─────────────── @ ventanas abiertas ───────────────
    // Se lee de Hyprland y no del ToplevelManager de Wayland porque hace falta
    // el ESCRITORIO de cada ventana, y eso solo lo sabe el compositor.
    //
    // winTick existe porque `Hyprland.toplevels.values` avisa cuando una ventana
    // nace o muere, pero NO cuando cambia de título: sin él, buscar "github" no
    // encontraría la pestaña que acabas de abrir en un Chrome que ya estaba.
    property int winTick: 0
    Timer {
        id: winPoll
        interval: 90
        onTriggered: { Hyprland.refreshToplevels(); root.winTick++; }
    }
    function winRefresh() { Hyprland.refreshToplevels(); root.winTick++; }
    Connections {
        target: Hyprland
        // Solo con el modo abierto: cada refreshToplevels() es una consulta al
        // socket de Hyprland, y el 99 % del tiempo esta lista no se está mirando.
        enabled: root.panel === "launcher" && root.launcherMode === "win"
        function onRawEvent(ev) {
            const n = String(ev.name);
            if (n.indexOf("window") >= 0 || n.indexOf("title") >= 0 || n.indexOf("workspace") >= 0)
                winPoll.restart();
        }
    }

    readonly property var winItems: {
        root.winTick;   // dependencia a propósito: ver la nota de arriba
        const out = [];
        const ts = Hyprland.toplevels ? [...Hyprland.toplevels.values] : [];
        for (let i = 0; i < ts.length; i++) {
            const t = ts[i];
            if (!t || !t.workspace || t.workspace.id < 1) continue;   // fuera los especiales
            const c = t.lastIpcObject;
            const cls = c ? String(c["class"] || "") : "";
            out.push({
                kind: "win",
                // OJO: `address` viene SIN el "0x" y los despachadores de
                // Hyprland lo exigen. Sin el prefijo, focus contesta "no window"
                // y no pasa nada, en silencio. Misma trampa que en OverviewPanel.
                addr: (function () {
                    const s = String(t.address || "");
                    return s.startsWith("0x") ? s : "0x" + s;
                })(),
                ws: t.workspace.id,
                cls: cls,
                title: (t.title && t.title.length > 0) ? String(t.title) : cls,
                icon: root.iconForClass(cls),
                tl: t
            });
        }
        out.sort((a, b) => a.ws - b.ws || a.title.localeCompare(b.title));
        return out;
    }

    // El .desktop no se llama como la clase de la ventana casi nunca
    // ("org.gnome.Nautilus" vs "nautilus"), así que la búsqueda heurística de
    // Quickshell hace el trabajo; si no encuentra nada, la clase en minúsculas
    // suele ser un nombre de icono válido en el tema.
    function iconForClass(cls) {
        if (!cls) return "";
        try {
            const e = DesktopEntries.heuristicLookup(cls);
            if (e && e.icon) return e.icon;
        } catch (err) {}
        return cls.toLowerCase();
    }

    function searchWins(query) {
        const q = (query || "").trim().toLowerCase();
        if (q.length === 0) return root.winItems;
        const out = [];
        for (let i = 0; i < root.winItems.length; i++) {
            const w = root.winItems[i];
            if ((w.title + " " + w.cls + " " + w.ws).toLowerCase().indexOf(q) >= 0) out.push(w);
        }
        return out;
    }

    // Cerrar PRIMERO y pedir el foco DESPUÉS, con 60 ms de por medio. Al cerrar
    // el panel se suelta el HyprlandFocusGrab y Hyprland devuelve el foco a la
    // ventana que lo tenía antes; si nuestra petición va en el mismo instante no
    // está garantizado quién llega el último, y si llega la devolución te quedas
    // donde estabas — justo lo que acabas de pedir que no pase. Es el mismo
    // remedio (y la misma cifra) que usa OverviewPanel al saltar a una ventana.
    property string winPending: ""
    Timer {
        id: winFocusDefer
        interval: 60
        onTriggered: {
            if (root.winPending === "") return;
            Hyprland.dispatch('hl.dsp.focus({ window = "address:' + root.winPending + '" })');
            root.winPending = "";
        }
    }
    function focusWindow(w) {
        if (!w) return;
        root.winPending = w.addr;
        root.closePanel();
        winFocusDefer.restart();
    }

    // ═══════════════════════ calculadora del lanzador ═══════════════════════
    // Nombres permitidos. Cualquier otra palabra en la expresión la descarta:
    // así "7zip" o "firefox 2" no disparan la calculadora.
    readonly property var calcWords: ["sqrt", "abs", "sin", "cos", "tan", "asin", "acos", "atan",
        "log", "log2", "log10", "exp", "round", "floor", "ceil", "min", "max", "pow", "pi", "e"]

    function calcEval(q) {
        let e = (q || "").trim();
        if (e.startsWith("=")) e = e.slice(1);      // "=" fuerza modo calculadora
        if (e.length === 0) return null;
        if (!/\d/.test(e)) return null;                    // sin números no hay cuenta
        if (!/[+\-*\/^%()]/.test(e)) return null;           // sin operador tampoco: "5" no es una cuenta

        // solo caracteres de expresión, y las letras solo dentro de nombres conocidos
        if (!/^[0-9\s+\-*\/^%().,×÷a-zA-Z]+$/.test(e)) return null;
        const words = e.match(/[a-zA-Z]+/g) || [];
        for (let i = 0; i < words.length; i++)
            if (root.calcWords.indexOf(words[i].toLowerCase()) < 0) return null;

        // sintaxis amable -> JavaScript
        let x = e.replace(/×/g, "*").replace(/÷/g, "/").replace(/\^/g, "**");
        x = x.replace(/(\d),(\d)/g, "$1.$2");               // coma decimal
        x = x.replace(/\bpi\b/gi, "Math.PI").replace(/\be\b/gi, "Math.E");
        x = x.replace(/\b(sqrt|abs|sin|cos|tan|asin|acos|atan|log2|log10|log|exp|round|floor|ceil|min|max|pow)\b/gi,
                      function (m) { return "Math." + m.toLowerCase(); });
        try {
            const v = Function('"use strict"; return (' + x + ')')();
            if (typeof v !== "number" || !isFinite(v)) return null;
            return v;
        } catch (err) {
            return null;
        }
    }

    // Sin ruido de coma flotante: 0.1+0.2 debe dar 0.3, no 0.30000000000000004
    function calcFormat(v) {
        if (v === null || v === undefined) return "";
        const r = Math.round(v * 1e10) / 1e10;
        if (Number.isInteger(r) && Math.abs(r) < 1e15) return String(r);
        return String(parseFloat(r.toPrecision(12)));
    }

    function copyText(t) {
        Quickshell.clipboardText = String(t);
        root.toast("󰆏", I18n.tr("Copiado: {0}", t));
    }

    // Aviso breve dentro del notch. Aquí SÍ hace falta: copiar al portapapeles
    // no tiene ninguna otra señal de que haya ocurrido.
    property string toastIcon: ""
    property string toastText: ""
    function toast(icon, text) {
        root.toastIcon = icon;
        root.toastText = text;
        root.flash("toast");
    }

    function launchApp(app) {
        if (!app) return;
        root.closePanel();
        app.execute();
    }

    // ═══════════════════════ favoritos del lanzador ═══════════════════════
    // Se guardan por `id` de la entrada .desktop, que es constante, y NO por
    // nombre: renombrar la app o cambiar el idioma del escritorio no debe
    // perderte el favorito. Un id que ya no exista (app desinstalada) se ignora
    // al resolver, así que la lista se limpia sola sin avisar de nada.
    readonly property var favApps: {
        const out = [];
        const ids = Config.favApps;
        for (let i = 0; i < ids.length; i++) {
            const a = root.appById(ids[i]);
            if (a) out.push(a);
        }
        return out;
    }

    function appById(id) {
        const vs = root.allApps;
        for (let i = 0; i < vs.length; i++) if (vs[i].id === id) return vs[i];
        return null;
    }

    function isFav(app) { return !!app && Config.favApps.indexOf(app.id) >= 0; }

    function toggleFav(app) {
        if (!app) return;
        // slice() y no mutación en sitio: cambiar la lista por dentro no dispara
        // el cambio de propiedad, así que ni se repinta ni se guarda el fichero.
        const ids = Config.favApps.slice();
        const i = ids.indexOf(app.id);
        if (i >= 0) ids.splice(i, 1); else ids.push(app.id);
        Config.favApps = ids;
        Config.save();
    }

    // ═══════════════════════ emparejamiento bluetooth ═══════════════════════
    // Quickshell sabe emparejar (Bluetooth.pair()) pero NO sabe contestar a lo
    // que BlueZ pregunta a mitad del emparejamiento: "¿coincide este código?",
    // "teclea estos seis dígitos". Esas preguntas llegan a un objeto D-Bus que
    // hay que EXPORTAR, y QML no puede exportar objetos D-Bus. Por eso hay un
    // proceso aparte (scripts/bt-agent.py) que sí lo hace y que habla con el
    // notch por IPC. Aquí solo vive lo que hay que enseñar y la respuesta.
    //
    // Sin esto los auriculares emparejan igual (no preguntan nada) pero un
    // teclado o un mando falla EN SILENCIO, que es justo lo peor: no hay error,
    // simplemente no se empareja nunca.
    property string btKind: ""     // "" | "confirm" | "display" | "authorize"
    property string btName: ""     // nombre del aparato
    property string btCode: ""     // los seis dígitos, "" si no hay
    property int btEntered: -1     // dígitos ya tecleados (solo en "display")
    readonly property bool btAsking: root.btKind !== ""

    function btAsk(kind, name, code, entered) {
        root.btKind = kind;
        root.btName = name;
        root.btCode = code;
        root.btEntered = entered;
    }

    function btClear() {
        root.btKind = ""; root.btName = ""; root.btCode = ""; root.btEntered = -1;
    }

    function btReply(accept) {
        // Se limpia SIEMPRE, conteste el agente lo que conteste: si el proceso
        // se hubiera muerto, la cara se quedaría clavada en el notch tapando
        // todo lo demás (btpair va por delante hasta de los paneles).
        btReplyProc.command = ["busctl", "--user", "call",
            "org.quickshell.BtAgent", "/org/quickshell/btagent",
            "org.quickshell.BtAgent1", "Reply", "b", accept ? "true" : "false"];
        btReplyProc.running = true;
        root.btClear();
    }

    Process { id: btReplyProc }

    // Reordenar arrastrando: `to` es la RANURA de inserción (0..n), no el índice
    // de un elemento, por eso hay que descontar uno cuando se mueve hacia la
    // derecha (al sacar el elemento, todo lo de detrás se corre una posición).
    function moveFav(from, to) {
        const ids = Config.favApps.slice();
        if (from < 0 || from >= ids.length) return;
        let t = Math.max(0, Math.min(ids.length, to));
        if (t > from) t -= 1;
        if (t === from) return;
        ids.splice(t, 0, ids.splice(from, 1)[0]);
        Config.favApps = ids;
        Config.save();
    }
}
