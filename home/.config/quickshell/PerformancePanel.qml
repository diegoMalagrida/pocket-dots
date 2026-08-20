// PerformancePanel.qml — «Tu equipo», desplegado DESDE el notch.
//
// Hermano de NetworkPanel y BluetoothPanel, y construido igual que ellos:
// cabecera (icono · título · subtítulo · un control a la derecha), filete de
// 1 px en #1e1e1e, y cuerpo. Nada más.
//
// La cara anterior se salía de eso por todos lados y por eso cantaba tanto:
// colaba el wallpaper de fondo con un degradado negro encima —era el único
// sitio del shell con superficie propia—, se inventaba una escala de grises
// entera (#f2f2f2, #efefef, #bcbcbc, #a8a8a8, #858585, #747474, #686868,
// #555555) que no usa nadie más, titulaba en minúsculas («actividad
// reciente», «ahora mismo») mientras el resto del notch dice «Red» o
// «Notificaciones», y abría con una frase de ánimo. Abrirlo se sentía como
// saltar a otra aplicación.
//
// Aquí no hay superficie propia: el panel se pinta sobre la del notch como los
// demás, y lo único que flota encima son las mismas tarjetas de radM con
// relleno al 4,5 % y filete al 7,5 % que usa la ventana de Ajustes. La escala
// de grises es la de la casa: #ffffff · #cfcfcf · #9a9a9a · #8a8a8a · #7d7d7d.
//
// LAS CURVAS MANDAN. Es lo único que este panel enseña y no se puede ver en
// ningún otro sitio del escritorio, así que se lleva la carta grande entera y
// la temperatura tiene la suya. La batería, en cambio, YA ESTÁ SIEMPRE en el
// notch en reposo: repetirla aquí con tarjeta, barra y estimación era gastar
// un tercio del panel en un dato que se ve sin abrir nada. Ahora es media
// línea en el subtítulo, y solo sube de tono cuando de verdad queda poca.
//
// Y las curvas se rigen por tres decisiones que están explicadas donde viven,
// pero conviene saber que existen antes de tocar nada:
//   · UNA BANDA POR SERIE, cada una con su techo (ver `ceilFor`). Compartir eje
//     entre procesador y memoria condenaba a una de las dos a arrastrarse por
//     el suelo, y de paso invitaba a comparar dos porcentajes que no significan
//     lo mismo.
//   · EL TECHO SE ANUNCIA, arriba a la izquierda de cada banda. Un eje que se
//     mueve solo y no lo dice es un eje que miente.
//   · LAS MARCAS SON FINAS (ver la cabecera de HistoryGraph.qml): trazo de 2 px,
//     relleno al 10 % —velo, no bloque—, punto de 8 px con anillo de superficie
//     y ni una rejilla. Eso es lo que separa un gráfico tranquilo de un panel de
//     monitorización, y no es cuestión de gusto: son medidas.
import QtQuick
import QtQuick.Layouts

Item {
    id: root

    readonly property bool active: ShellState.panel === "system"

    // ─────────────── lo que de verdad hay que avisar ───────────────
    // Sin frase de ánimo: si no pasa nada, el subtítulo cuenta desde cuándo
    // está encendido y cómo va la batería, que son datos. Solo cuando pasa
    // algo, el subtítulo (y el icono de la cabecera) cambian de color.
    readonly property bool battLow: ShellState.batt >= 0 && ShellState.batt < 18 && !ShellState.ac
    readonly property bool hot: ShellState.cpuTemp >= 78
    readonly property color headTone: root.battLow ? Colors.crit
        : root.hot ? Colors.warn : Colors.accent

    function decimal(v, digits) { return Number(v).toFixed(digits).replace(".", ","); }
    function gibFromKib(v) { return root.decimal(v / 1048576, 1); }
    function gibFromBytes(v) { return root.decimal(v / 1073741824, 1); }
    function uptime(seconds) {
        const mins = Math.max(0, Math.floor(seconds / 60));
        const days = Math.floor(mins / 1440);
        const hours = Math.floor((mins % 1440) / 60);
        const rest = mins % 60;
        if (days > 0) return days + " d " + hours + " h";
        if (hours > 0) return hours + " h " + rest + " min";
        return rest + " min";
    }

    // ══════════════════════════════════════════════════════════════════════
    //  LAS ESCALAS SE AJUSTAN A LO QUE HAY
    //
    //  Con el eje clavado en 0..100 las curvas pasaban la vida arrastrándose
    //  por el borde de abajo: en reposo el procesador va al 4 % y la memoria al
    //  21 %, así que tres cuartas partes de la carta eran hueco y la señal, un
    //  temblor de dos píxeles. Un gráfico que no usa su alto no es un gráfico,
    //  es un adorno.
    //
    //  Pero autoescalar a pelo tampoco vale: el techo bailaría en cada muestra
    //  y la curva se movería aunque el equipo no hiciera nada. Por eso el techo
    //  SALTA ENTRE CUATRO VALORES (25 · 50 · 75 · 100) y se anuncia arriba a la
    //  izquierda, en el sitio donde un eje lleva su etiqueta. Así la banda está
    //  siempre llena, el salto ocurre pocas veces y nunca hay que adivinar
    //  contra qué se está midiendo.
    //
    //  Y CADA SERIE TIENE SU BANDA. Compartir eje entre procesador y memoria
    //  era el error de fondo: en reposo la memoria va cuatro o cinco veces más
    //  alta que el procesador, así que un eje que dejara respirar a una
    //  aplastaba a la otra contra el suelo, hiciera lo que hiciera. Dos bandas
    //  apiladas con techo propio caben en el mismo alto, se llenan las dos, y
    //  además dejan de invitar a comparar dos cosas que no se comparan (un 20 %
    //  de RAM y un 20 % de CPU no significan ni de lejos lo mismo).
    // ══════════════════════════════════════════════════════════════════════
    //  La escalera baja hasta 5 a propósito. Con el primer peldaño en 25 —que
    //  es lo que parece razonable al escribirlo— un procesador en reposo al 4 %
    //  seguía siendo una raya a un tercio de altura: se había cambiado el eje
    //  pero no el problema. Los peldaños son números que se leen de un vistazo
    //  (5·10·20·30·50·75·100), y el 1,25 es aire por arriba: sin él la serie se
    //  pega al borde superior de su banda y parece estar tocando techo.
    //  Los peldaños van apretados por abajo y sueltos por arriba a propósito:
    //  entre 5 y 20 es donde vive un portátil en reposo y un salto de 10 a 20
    //  deja media banda vacía, mientras que arriba dar el salto de 50 a 75 no
    //  se nota porque a esas alturas lo que se mira es la forma del pico, no el
    //  número exacto.
    readonly property var ceilSteps: [5, 10, 15, 20, 30, 40, 50, 75, 100]
    function ceilFor(series) {
        let m = 0;
        if (series) for (let i = 0; i < series.length; i++) if (series[i] > m) m = series[i];
        m *= 1.25;
        for (let i = 0; i < root.ceilSteps.length; i++)
            if (m <= root.ceilSteps[i]) return root.ceilSteps[i];
        return 100;
    }

    // La temperatura no tiene escala redonda que valga: entre 38 y 44 °C hay
    // seis grados de recorrido real y en 0..100 —o incluso en 35..95— eso es
    // una raya recta. Aquí la ventana se ciñe a lo que ha pasado en el último
    // minuto y medio, con un mínimo de 10 grados para que dos décimas de nada
    // no se vean como una montaña. El grado exacto lo canta la cifra grande;
    // la curva está para enseñar la FORMA.
    readonly property var tempRange: {
        const h = ShellState.tempHistory;
        if (!h || h.length === 0) return { lo: 35, hi: 55 };
        let lo = h[0], hi = h[0];
        for (let i = 1; i < h.length; i++) {
            if (h[i] < lo) lo = h[i];
            if (h[i] > hi) hi = h[i];
        }
        const mid = (lo + hi) / 2;
        const span = Math.max(10, (hi - lo) * 1.6);
        return { lo: Math.max(0, mid - span / 2), hi: mid + span / 2 };
    }

    // ─────────────── lectura al vuelo ───────────────
    // sysstats.sh escupe una muestra cada 1,5 s (ver ShellState): de ahí sale
    // tanto el «hace 90 s» del rótulo como esta cuenta atrás.
    readonly property real samplePeriod: 1.5

    // Índice de la muestra más cercana a una X. Se redondea en vez de truncar
    // porque la cruz se engancha al punto MÁS PRÓXIMO: apuntas a un instante,
    // no tienes que cazar una línea de dos píxeles.
    function sampleAt(x, w, series) {
        const n = series ? series.length : 0;
        if (n < 2 || w <= 0) return -1;
        return Math.max(0, Math.min(n - 1, Math.round(x / w * (n - 1))));
    }
    function agoText(stepsBack) {
        const secs = Math.round(stepsBack * root.samplePeriod);
        if (secs <= 0) return "ahora mismo";
        if (secs < 60) return "hace " + secs + " s";
        const mins = Math.floor(secs / 60), rest = secs % 60;
        return "hace " + mins + " min" + (rest > 0 ? " " + rest + " s" : "");
    }

    // ══════════════════════════════════════════════════════════════════════
    //  EL TONO DE LAS CURVAS NO ES Colors.accent A SECAS
    //
    //  El acento sale de pywal, o sea del fondo de pantalla, y con un fondo
    //  oscuro vuelve oscuro: sobre la superficie de la tarjeta (casi negra) una
    //  curva así se pierde. Aquí no vale «suele verse bien» — un trazo de 2 px
    //  es un elemento gráfico y pide 3:1 contra su fondo. Se sube la
    //  luminosidad del acento, y SOLO la luminosidad, hasta llegar a ese 3:1:
    //  el tono sigue siendo el de pywal, así que el retematizado se conserva
    //  entero. Es la misma receta que Colors.onWallAccent usa para la barra,
    //  pero medida contra la tarjeta en vez de contra el wallpaper.
    // ══════════════════════════════════════════════════════════════════════
    readonly property color plotSurface: "#101010"   // tarjeta (4,5 % sobre el notch)
    function readable(c) {
        const h = c.hslHue < 0 ? 0 : c.hslHue;
        const s = c.hslSaturation;
        let l = c.hslLightness;
        let out = Qt.hsla(h, s, l, 1);
        for (let i = 0; i < 60 && Colors.contrast(out, root.plotSurface) < 3.0; i++) {
            l = Math.min(l + 0.02, 1);
            out = Qt.hsla(h, s, l, 1);
        }
        return out;
    }
    readonly property color plotTone: root.readable(Colors.accent)
    readonly property color tempTone: root.readable(ShellState.cpuTemp >= 80 ? Colors.crit
        : ShellState.cpuTemp >= 68 ? Colors.warn : Colors.accent)
    readonly property color diskTone: root.readable(ShellState.disk >= 92 ? Colors.crit
        : ShellState.disk >= 82 ? Colors.warn : Colors.accent)

    MouseArea { anchors.fill: parent }   // el hueco pertenece al panel

    Item {
        id: keys
        anchors.fill: parent
        focus: true
        Keys.onEscapePressed: function (e) {
            ShellState.closePanel();
            e.accepted = true;
        }
    }
    onActiveChanged: if (root.active) keys.forceActiveFocus()

    // ─────────────── una tarjeta de las de la casa ───────────────
    // La misma cascada que los conmutadores del centro de control: es el gesto
    // propio de este shell y no había razón para que aquí no lo hubiera. Como
    // allí, NO se toca la opacidad — de eso ya se encarga el NotchLayer, y dos
    // fundidos encadenados se multiplican.
    component Card: Rectangle {
        id: card
        property int idx: 0
        radius: Appearance.radM
        color: Qt.rgba(1, 1, 1, 0.045)
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.075)

        property real ent: ShellState.mode === "system" ? 1 : 0
        Behavior on ent {
            SequentialAnimation {
                PauseAnimation { duration: ShellState.mode === "system" ? card.idx * 32 : 0 }
                SpringAnimation {
                    spring: Appearance.sprPanel
                    damping: Appearance.dmpPanel
                    epsilon: Appearance.eppScale
                }
            }
        }
        scale: 0.92 + 0.08 * card.ent
        transform: Translate { y: (1 - card.ent) * 10 }
    }

    // ─────────────── una banda: cabecera de la serie + su curva ───────────────
    //
    // LECTURA AL VUELO, SIN GLOBO. Pasar el ratón por la curva engancha una
    // cruz a la muestra más cercana, y el valor que ya estaba en la cabecera se
    // convierte EN la lectura: la cifra grande pasa a ser la de ese instante y
    // la nota de al lado dice hace cuánto fue. Un globo flotante habría sido
    // otra superficie encima de un panel que ya es una superficie encima del
    // notch, y además taparía justo el trozo de curva que se está mirando.
    // Nada queda escondido detrás del ratón: en reposo la cifra es la de ahora,
    // que es el dato que importa.
    component Lane: ColumnLayout {
        id: lane
        property string label: ""
        property string value: ""
        property string note: ""
        property string aside: ""          // solo la primera banda lleva el «últimos 90 s»
        property string unit: " %"
        property color tone: Colors.accent
        property var series: []
        readonly property int ceil: root.ceilFor(lane.series)

        property int hover: -1             // muestra señalada, o -1
        readonly property bool reading: lane.hover >= 0 && lane.hover < (lane.series ? lane.series.length : 0)

        spacing: 5

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Rectangle {
                Layout.alignment: Qt.AlignVCenter
                width: 6; height: 6; radius: 3
                color: lane.tone
            }
            Text {
                Layout.alignment: Qt.AlignBaseline
                text: lane.label
                color: "#9a9a9a"
                font.family: Appearance.fontUI; font.pixelSize: 11
            }
            Text {
                Layout.alignment: Qt.AlignBaseline
                Layout.leftMargin: 3
                text: lane.reading
                    ? Math.round(lane.series[lane.hover]) + lane.unit
                    : lane.value
                color: "#ffffff"
                font.family: Appearance.fontUI; font.pixelSize: 18
                font.weight: Font.DemiBold
            }
            Text {
                Layout.alignment: Qt.AlignBaseline
                Layout.fillWidth: true
                text: lane.reading ? root.agoText(lane.series.length - 1 - lane.hover) : lane.note
                color: "#7d7d7d"; elide: Text.ElideRight
                font.family: Appearance.fontUI; font.pixelSize: 10
                font.features: ({ "tnum": 1 })
            }
            Text {
                Layout.alignment: Qt.AlignBaseline
                visible: lane.aside.length > 0
                text: lane.aside
                color: "#5e5e5e"
                font.family: Appearance.fontUI; font.pixelSize: 10
            }
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            // Sitio para que el punto vivo del extremo no se coma el filete.
            Layout.rightMargin: 4

            HistoryGraph {
                id: laneGraph
                anchors.fill: parent
                values: lane.series
                ceiling: lane.ceil
                lineColor: lane.tone
                fillTop: Qt.rgba(lane.tone.r, lane.tone.g, lane.tone.b, 0.10)
                fillBottom: Qt.rgba(lane.tone.r, lane.tone.g, lane.tone.b, 0.004)
                showGrid: false
                showBaseline: true
                showPoint: true
                fadeIn: 0.12
                markIndex: lane.hover
            }

            // acceptedButtons: NoButton — este ratón solo escucha. Si aceptara
            // clics se comería el que cierra el panel, que lo atiende el
            // MouseArea de la raíz.
            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.NoButton
                onPositionChanged: function (m) { lane.hover = root.sampleAt(m.x, width, lane.series); }
                onExited: lane.hover = -1
            }

            // La etiqueta del eje, donde va la etiqueta de un eje.
            Text {
                anchors { left: parent.left; top: parent.top }
                text: lane.ceil + " %"
                color: "#4f4f4f"
                font.family: Appearance.fontUI; font.pixelSize: 9
                font.features: ({ "tnum": 1 })
            }
        }
    }


    ColumnLayout {
        anchors { fill: parent; leftMargin: 22; rightMargin: 20; topMargin: 20; bottomMargin: 18 }
        spacing: 12

        // ─────────────── cabecera ───────────────
        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            Text {
                text: Icons.cpu
                color: root.headTone
                font.family: Appearance.font; font.pixelSize: 18
                Behavior on color { ColorAnimation { duration: Appearance.mIn; easing.type: Easing.OutCubic } }
            }
            ColumnLayout {
                spacing: 0
                Text {
                    // El mismo nombre que la puerta por la que se entra desde el
                    // centro de control. Una puerta y una habitación con nombres
                    // distintos son dos sitios.
                    text: "Tu equipo"
                    color: "#ffffff"
                    font.family: Appearance.fontUI; font.pixelSize: 13; font.weight: Font.DemiBold
                }
                Text {
                    text: root.battLow ? "Batería baja · " + ShellState.battEstimateText
                        : root.hot ? "El procesador está caliente · " + Math.round(ShellState.cpuTemp) + " °C"
                        : "Encendido desde hace " + root.uptime(ShellState.uptimeSeconds)
                            + (ShellState.batt >= 0
                                ? "  ·  Batería " + ShellState.batt + " %" + (ShellState.ac ? ", cargando" : "")
                                : "")
                    color: root.battLow ? Colors.crit : root.hot ? Colors.warn : "#8a8a8a"
                    elide: Text.ElideRight
                    font.family: Appearance.fontUI; font.pixelSize: 11
                    Behavior on color { ColorAnimation { duration: Appearance.mIn; easing.type: Easing.OutCubic } }
                }
            }
            Item { Layout.fillWidth: true }

            // Donde Red y Bluetooth ponen su interruptor. Aquí no hay nada que
            // encender, pero sí de dónde se viene: un botón de verdad, no un
            // texto gris suelto.
            Rectangle {
                implicitWidth: backRow.implicitWidth + 24
                implicitHeight: 29
                radius: Appearance.radS
                color: backMa.containsMouse ? Qt.rgba(Colors.accent.r, Colors.accent.g, Colors.accent.b, 0.16)
                                            : Qt.rgba(1, 1, 1, 0.05)
                Behavior on color { ColorAnimation { duration: Appearance.mQuick; easing.type: Easing.OutQuad } }

                Row {
                    id: backRow
                    anchors.centerIn: parent
                    spacing: 7
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "‹"
                        color: backMa.containsMouse ? Colors.accent : "#8a8a8a"
                        font.family: Appearance.fontUI; font.pixelSize: 15
                        Behavior on color { ColorAnimation { duration: Appearance.mQuick; easing.type: Easing.OutQuad } }
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Centro de control"
                        color: backMa.containsMouse ? Colors.accent : "#cfcfcf"
                        font.family: Appearance.fontUI; font.pixelSize: 11
                        Behavior on color { ColorAnimation { duration: Appearance.mQuick; easing.type: Easing.OutQuad } }
                    }
                }
                MouseArea {
                    id: backMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: ShellState.togglePanel("control")
                }
            }
        }

        Rectangle { Layout.fillWidth: true; height: 1; color: "#1e1e1e" }

        // ─────────────── cuerpo ───────────────
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 14

            // ── izquierda: minuto y medio de actividad ──
            // La leyenda ya dice qué es cada línea, así que no lleva encima un
            // título («actividad reciente») que repita lo mismo en minúsculas.
            Card {
                idx: 0
                Layout.fillWidth: true
                Layout.fillHeight: true

                ColumnLayout {
                    anchors { fill: parent; leftMargin: 18; rightMargin: 18; topMargin: 14; bottomMargin: 14 }
                    spacing: 14

                    Lane {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        label: "Procesador"
                        value: ShellState.cpu + " %"
                        note: "carga " + root.decimal(ShellState.cpuLoad, 2) + " · " + ShellState.cpuThreads + " hilos"
                        aside: "últimos 90 s"
                        tone: root.plotTone
                        series: ShellState.cpuHistory
                    }
                    // La memoria NO reparte alto a partes iguales con el
                    // procesador. En noventa segundos la RAM se mueve dos o
                    // tres puntos: darle media carta era dedicar el mismo
                    // espacio a una recta que a la única serie que de verdad
                    // pasa cosas. Una franja baja dice «esto está aquí y está
                    // tranquilo» sin gritar, y el procesador se queda con el
                    // alto que necesita para que se le vea la forma.
                    // (Alto clavado por los tres lados por lo mismo que la
                    // columna derecha: Lane es un ColumnLayout, y un layout
                    // dentro de otro se rellena por defecto — con solo
                    // preferredHeight se quedaba con la carta entera y dejaba
                    // al procesador en una rendija.)
                    Lane {
                        Layout.fillWidth: true
                        Layout.fillHeight: false
                        Layout.minimumHeight: 96
                        Layout.preferredHeight: 96
                        Layout.maximumHeight: 96
                        label: "Memoria"
                        value: ShellState.mem + " %"
                        note: ShellState.memTotalKib > 0
                            ? root.gibFromKib(ShellState.memUsedKib) + " de " + root.gibFromKib(ShellState.memTotalKib) + " GiB"
                            : ""
                        // Mismo acento que el procesador, no la tinta del
                        // wallpaper: cuando las dos series compartían carta
                        // hacía falta distinguirlas por color, pero ahora cada
                        // una tiene su banda rotulada y el segundo tono solo
                        // servía para que media tarjeta saliera de un gris
                        // lavado que no es de ninguna parte. Un acento, como en
                        // el resto del shell.
                        tone: root.plotTone
                        series: ShellState.memHistory
                    }
                }
            }

            // ── derecha: lo que cambia despacio ──
            // Ancho clavado por los tres lados: un ColumnLayout anidado dentro
            // de un RowLayout se rellena por defecto (para los layouts fillWidth
            // vale true, no como en el resto de items) y se comía entera la
            // columna de la izquierda.
            ColumnLayout {
                Layout.fillWidth: false
                Layout.minimumWidth: 272
                Layout.preferredWidth: 272
                Layout.maximumWidth: 272
                Layout.fillHeight: true
                spacing: 12

                // ── temperatura: también tiene curva ──
                Card {
                    id: tempCard
                    idx: 1
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    // Misma lectura al vuelo que las bandas de la izquierda.
                    property int hover: -1
                    readonly property bool reading: tempCard.hover >= 0
                        && tempCard.hover < ShellState.tempHistory.length

                    ColumnLayout {
                        anchors { fill: parent; leftMargin: 16; rightMargin: 16; topMargin: 13; bottomMargin: 13 }
                        spacing: 2

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 9
                            Text {
                                text: "󰔏"
                                color: root.tempTone
                                font.family: Appearance.font; font.pixelSize: 15
                                Behavior on color { ColorAnimation { duration: Appearance.mIn; easing.type: Easing.OutCubic } }
                            }
                            Text {
                                Layout.fillWidth: true
                                text: "Temperatura"
                                color: "#9a9a9a"
                                font.family: Appearance.fontUI; font.pixelSize: 11
                            }
                            Text {
                                text: tempCard.reading
                                    ? Math.round(ShellState.tempHistory[tempCard.hover]) + " °C"
                                    : ShellState.cpuTemp >= 0 ? Math.round(ShellState.cpuTemp) + " °C" : "—"
                                color: "#ffffff"
                                font.family: Appearance.fontUI; font.pixelSize: 18
                                font.weight: Font.DemiBold
                            }
                        }

                        // El estado va con PALABRA además de con color: el acento
                        // sale de pywal y con una paleta de croma bajo el salto a
                        // «aviso» es casi invisible. Un color de estado no puede
                        // ser el único canal que dice el estado.
                        Text {
                            Layout.fillWidth: true
                            Layout.leftMargin: 24
                            text: tempCard.reading
                                ? root.agoText(ShellState.tempHistory.length - 1 - tempCard.hover)
                                : ShellState.cpuTemp < 0 ? "Sin lectura"
                                : ShellState.cpuTemp < 52 ? "Fresco"
                                : ShellState.cpuTemp < 68 ? "Templado"
                                : ShellState.cpuTemp < 80 ? "Caliente" : "Muy caliente"
                            color: "#7d7d7d"
                            font.family: Appearance.fontUI; font.pixelSize: 10
                        }

                        Item {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            Layout.topMargin: 6
                            Layout.rightMargin: 4

                            HistoryGraph {
                                anchors.fill: parent
                                values: ShellState.tempHistory
                                floor: root.tempRange.lo
                                ceiling: root.tempRange.hi
                                lineColor: root.tempTone
                                fillTop: Qt.rgba(lineColor.r, lineColor.g, lineColor.b, 0.10)
                                fillBottom: Qt.rgba(lineColor.r, lineColor.g, lineColor.b, 0.004)
                                showGrid: false
                                showBaseline: true
                                showPoint: true
                                fadeIn: 0.12
                                markIndex: tempCard.hover
                            }
                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                acceptedButtons: Qt.NoButton
                                onPositionChanged: function (m) {
                                    tempCard.hover = root.sampleAt(m.x, width, ShellState.tempHistory);
                                }
                                onExited: tempCard.hover = -1
                            }
                        }
                    }
                }

                // ── espacio en disco: aquí no hay historia que contar ──
                // El disco no se mueve en noventa segundos, así que una curva
                // sería una raya recta fingiendo ser un gráfico. Una barra dice
                // lo mismo y no miente sobre lo que hay debajo.
                Card {
                    idx: 2
                    Layout.fillWidth: true
                    Layout.preferredHeight: 92

                    ColumnLayout {
                        anchors { fill: parent; leftMargin: 16; rightMargin: 16; topMargin: 13; bottomMargin: 13 }
                        spacing: 9

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 9
                            Text {
                                text: "󰋊"
                                color: ShellState.disk >= 92 ? Colors.crit
                                    : ShellState.disk >= 82 ? Colors.warn : Colors.accent
                                font.family: Appearance.font; font.pixelSize: 15
                                Behavior on color { ColorAnimation { duration: Appearance.mIn; easing.type: Easing.OutCubic } }
                            }
                            Text {
                                Layout.fillWidth: true
                                text: "Almacenamiento"
                                color: "#9a9a9a"
                                font.family: Appearance.fontUI; font.pixelSize: 11
                            }
                            Text {
                                text: ShellState.disk + " %"
                                color: "#ffffff"
                                font.family: Appearance.fontUI; font.pixelSize: 15
                                font.weight: Font.DemiBold
                            }
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 3
                            radius: 2
                            // La pista es un escalón claro del MISMO tono que
                            // el relleno, no un gris de la casa: así el estado
                            // (acento / aviso / crítico) se lee a lo largo de
                            // toda la barra y no solo en el trozo lleno.
                            color: Qt.rgba(root.diskTone.r, root.diskTone.g, root.diskTone.b, 0.18)
                            Rectangle {
                                height: parent.height
                                radius: parent.radius
                                width: parent.width * Math.max(0, Math.min(1, ShellState.disk / 100))
                                color: root.diskTone
                                Behavior on width { NumberAnimation { duration: Appearance.mTick; easing.type: Easing.Linear } }
                                Behavior on color { ColorAnimation { duration: Appearance.mIn; easing.type: Easing.OutCubic } }
                            }
                        }

                        Text {
                            Layout.fillWidth: true
                            text: ShellState.diskTotalBytes > 0
                                ? root.gibFromBytes(Math.max(0, ShellState.diskTotalBytes - ShellState.diskUsedBytes))
                                  + " GiB libres de " + root.gibFromBytes(ShellState.diskTotalBytes)
                                : ""
                            color: "#7d7d7d"; elide: Text.ElideRight
                            font.family: Appearance.fontUI; font.pixelSize: 10
                        }
                    }
                }
            }
        }
    }
}
