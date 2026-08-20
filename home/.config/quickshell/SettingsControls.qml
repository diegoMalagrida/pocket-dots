// SettingsControls.qml — los controles de la app de Ajustes.
// Se usan como tipos desde las secciones: `SettingsControls.Card_ { ... }`.
//
// DOS DECISIONES QUE EXPLICAN TODO LO DEMÁS:
//
// 1) La descripción de un ajuste NO va debajo de su etiqueta. Antes sí, y cada
//    fila medía tres líneas: en una ventana de 520 px de alto cabían siete
//    ajustes y Apariencia era un scroll infinito. Ahora la fila mide 42 px y la
//    descripción viaja a `ShellState.settingsHint`, que la ventana enseña en
//    una franja fija al pie. Cero reflow al pasar el ratón, nada tapando nada,
//    y no se pierde ni una palabra.
//
// 2) Los ajustes van en TARJETAS redondeadas (ley 1 de ~/.config/motion-language.md:
//    lo redondo es del shell). Antes era una lista plana con separadores de
//    1 px, que no agrupaba nada y no hablaba el idioma del resto del rice.
//
// Movimiento: aquí solo hay hover y pulsación, o sea RESPUESTA (130 ms), y
// simétrico porque el hover es un estado, no un evento (ley 3).
import QtQuick
import QtQuick.Layouts

QtObject {
    id: root

    // ─────────── tarjeta de grupo ───────────
    // Se esconde sola si el buscador no deja ninguna fila dentro. El recuento
    // NO puede mirar el `visible` de los hijos: en QML `visible` es efectiva,
    // así que al ocultarse la tarjeta sus filas dirían false y ya no volvería a
    // aparecer nunca. Por eso cada fila publica `matches` aparte.
    component Card_: ColumnLayout {
        id: card
        property string title: ""
        readonly property bool isSettingsCard: true
        property int visibleRows: 0
        default property alias rows: inner.data

        function recount() {
            let n = 0;
            const cs = inner.children;
            for (let i = 0; i < cs.length; i++)
                if (cs[i] && cs[i].isSettingsRow && cs[i].matches) n++;
            card.visibleRows = n;
        }

        Layout.fillWidth: true
        Layout.topMargin: 4
        spacing: 7
        visible: card.visibleRows > 0

        Text {
            Layout.leftMargin: 3
            visible: card.title.length > 0
            text: card.title
            color: Colors.accent
            font.family: Appearance.fontUI
            font.pixelSize: Appearance.fsXS
            font.weight: Font.DemiBold
            font.letterSpacing: 0.6
        }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: inner.implicitHeight + 10
            radius: Appearance.radM
            color: Qt.rgba(1, 1, 1, 0.045)
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.075)

            ColumnLayout {
                id: inner
                anchors { fill: parent; topMargin: 5; bottomMargin: 5; leftMargin: 4; rightMargin: 4 }
                spacing: 0
            }
        }
    }

    // ─────────── fila: etiqueta + control ───────────
    component Row_: Rectangle {
        id: r
        property string label: ""
        property string hint: ""
        property bool active: true                  // false = atenuada (p. ej. bluetooth bloqueado)
        property bool shown: true                   // false = no aplica ahora (p. ej. ajustes de isla en modo notch)
        readonly property bool isSettingsRow: true
        // OJO: quien use la fila NO debe tocar `visible` (rompería el buscador);
        // para condicionar una fila está `shown`.
        readonly property bool matches: r.shown && ShellState.settingsMatch(r.label, r.hint)
        default property alias content: inner.data

        function _recount() {
            let p = r.parent;
            while (p) { if (p.isSettingsCard) { p.recount(); return; } p = p.parent; }
        }
        onMatchesChanged: r._recount()
        Component.onCompleted: r._recount()

        Layout.fillWidth: true
        // 42 px es el SUELO, no el alto. Estaba cocido, y el selector de fuentes
        // —siete opciones en un Flow de 270 px— parte en tres líneas: esas
        // líneas se salían de la fila y se pintaban ENCIMA del ajuste de abajo y
        // del borde de la tarjeta (el slider de "Tamaño de la hora" quedaba
        // tachado por las pastillas). Un control que crece tiene que empujar la
        // fila, no derramarse fuera de ella.
        Layout.preferredHeight: Math.max(42, inner.implicitHeight + 14)
        visible: r.matches
        radius: Appearance.radS
        color: hh.hovered ? Qt.rgba(1, 1, 1, 0.065) : "transparent"
        opacity: r.active ? 1 : 0.42
        Behavior on color { ColorAnimation { duration: Appearance.mQuick; easing.type: Easing.OutQuad } }
        Behavior on opacity { NumberAnimation { duration: Appearance.mQuick } }

        // HoverHandler y no MouseArea: no bloquea, así que la fila sabe que
        // tiene el ratón encima aunque el puntero esté justo sobre el slider, y
        // el slider sigue recibiendo sus clics.
        HoverHandler {
            id: hh
            onHoveredChanged: {
                if (hovered) ShellState.settingsHint = r.hint;
                else if (ShellState.settingsHint === r.hint) ShellState.settingsHint = "";
            }
        }

        RowLayout {
            id: inner
            anchors { fill: parent; leftMargin: 12; rightMargin: 12 }
            spacing: 14

            Text {
                Layout.fillWidth: true
                Layout.minimumWidth: 120
                text: r.label
                color: "#ffffff"
                elide: Text.ElideRight
                font.family: Appearance.fontUI
                font.pixelSize: Appearance.fsS
            }
        }
    }

    // ─────────── fila entera clicable (lleva a otro sitio) ───────────
    component Action_: Rectangle {
        id: a
        property string label: ""
        property string hint: ""
        property string value: ""
        property string icon: ""
        property bool shown: true
        signal triggered

        readonly property bool isSettingsRow: true
        readonly property bool matches: a.shown && ShellState.settingsMatch(a.label, a.hint)
        function _recount() {
            let p = a.parent;
            while (p) { if (p.isSettingsCard) { p.recount(); return; } p = p.parent; }
        }
        onMatchesChanged: a._recount()
        Component.onCompleted: a._recount()

        Layout.fillWidth: true
        Layout.preferredHeight: 42
        visible: a.matches
        radius: Appearance.radS
        color: aMa.containsMouse ? Qt.rgba(1, 1, 1, 0.07) : "transparent"
        Behavior on color { ColorAnimation { duration: Appearance.mQuick; easing.type: Easing.OutQuad } }

        RowLayout {
            anchors { fill: parent; leftMargin: 12; rightMargin: 12 }
            spacing: 12
            Text {
                visible: a.icon.length > 0
                text: a.icon
                color: "#9a9a9a"
                font.family: Appearance.font
                font.pixelSize: 14
            }
            Text {
                Layout.fillWidth: true
                text: a.label
                color: "#ffffff"
                elide: Text.ElideRight
                font.family: Appearance.fontUI
                font.pixelSize: Appearance.fsS
            }
            Text {
                text: a.value
                color: "#8a8a8a"
                elide: Text.ElideRight
                font.family: Appearance.fontUI
                font.pixelSize: Appearance.fsXS
            }
            Text {
                text: "›"
                color: aMa.containsMouse ? "#ffffff" : "#6a6a6a"
                font.family: Appearance.fontUI
                font.pixelSize: 15
            }
        }

        MouseArea {
            id: aMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onEntered: ShellState.settingsHint = a.hint
            onExited: if (ShellState.settingsHint === a.hint) ShellState.settingsHint = ""
            onClicked: a.triggered()
        }
    }

    // ─────────── interruptor ───────────
    component Switch_: Rectangle {
        id: sw
        property bool checked: false
        property bool live: true                    // false = no responde (y se ve apagado)
        signal toggled(bool value)

        implicitWidth: 38; implicitHeight: 21
        radius: 11
        color: sw.checked ? Colors.accent : Qt.rgba(1, 1, 1, 0.14)
        opacity: sw.live ? 1 : 0.45
        Behavior on color { ColorAnimation { duration: Appearance.mQuick; easing.type: Easing.OutQuad } }

        Rectangle {
            width: 15; height: 15; radius: 8
            color: "#ffffff"
            y: 3
            x: sw.checked ? parent.width - width - 3 : 3
            Behavior on x { NumberAnimation { duration: Appearance.mQuick; easing.type: Easing.OutCubic } }
        }
        MouseArea {
            anchors.fill: parent
            anchors.margins: -6
            enabled: sw.live
            cursorShape: Qt.PointingHandCursor
            onClicked: sw.toggled(!sw.checked)
        }
    }

    // ─────────── deslizador con valor ───────────
    component Slider_: RowLayout {
        id: sl
        property real value: 0
        property real from: 0
        property real to: 100
        property int decimals: 0
        property string suffix: ""
        signal moved(real v)

        // igual que en NotchSlider: se anima el valor, nunca el ancho derivado
        property real shown: sl.value
        Behavior on shown {
            enabled: !drag.pressed
            NumberAnimation { duration: Appearance.mQuick; easing.type: Easing.OutCubic }
        }

        spacing: 10
        Layout.preferredWidth: 270
        Layout.fillWidth: false

        Rectangle {
            id: track
            Layout.fillWidth: true
            Layout.preferredHeight: 5
            radius: 3
            color: "#2c2c2c"

            Rectangle {
                id: fill
                width: track.width * Math.max(0, Math.min(1, (sl.shown - sl.from) / (sl.to - sl.from)))
                height: parent.height; radius: parent.radius
                color: Colors.accent
            }
            Rectangle {
                width: 13; height: 13; radius: 7
                color: "#ffffff"
                x: Math.max(0, Math.min(track.width - width, fill.width - width / 2))
                anchors.verticalCenter: parent.verticalCenter
                scale: drag.pressed ? 1.15 : 1
                Behavior on scale { NumberAnimation { duration: Appearance.mQuick; easing.type: Easing.OutCubic } }
            }
            MouseArea {
                id: drag
                anchors.fill: parent
                anchors.margins: -9
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                function emit(x) {
                    const f = Math.max(0, Math.min(1, (x + 9) / track.width));
                    sl.moved(sl.from + f * (sl.to - sl.from));
                }
                onPressed: function (m) { emit(m.x); }
                onPositionChanged: function (m) { if (pressed) emit(m.x); }
                // La rueda hace SCROLL de la página, no mueve el deslizador. Los
                // sliders ocupan la mitad derecha de cada fila, así que bajando
                // por Apariencia el puntero pasa por encima de uno sin querer y
                // acababas cambiando el alto de la banda creyendo que scrolleabas.
                // Con Ctrl sí ajusta: sirve para afinar de uno en uno sin arrastrar.
                //
                // accepted = false es lo que deja que el evento suba hasta el
                // Flickable de la página; sin esa línea el MouseArea se lo queda
                // (onWheel acepta por defecto) y la página no se mueve.
                onWheel: function (w) {
                    if (!(w.modifiers & Qt.ControlModifier)) {
                        w.accepted = false;
                        return;
                    }
                    const step = (sl.to - sl.from) / 40;
                    sl.moved(Math.max(sl.from, Math.min(sl.to, sl.value + (w.angleDelta.y > 0 ? step : -step))));
                }
            }
        }

        Text {
            Layout.preferredWidth: 44
            horizontalAlignment: Text.AlignRight
            text: sl.shown.toFixed(sl.decimals) + sl.suffix
            color: "#9a9a9a"
            font.family: Appearance.fontUI
            font.pixelSize: Appearance.fsXS
            font.features: ({ "tnum": 1 })
        }
    }

    // ─────────── selector de opciones ───────────
    component Choice_: Flow {
        id: ch
        property var options: []
        property string current: ""
        signal picked(string value)

        Layout.preferredWidth: 270
        Layout.fillWidth: false
        spacing: 6

        Repeater {
            model: ch.options
            Rectangle {
                required property var modelData
                readonly property bool sel: String(modelData) === ch.current
                implicitWidth: t.implicitWidth + 20
                implicitHeight: 26
                radius: 9
                color: sel ? Qt.rgba(Colors.accent.r, Colors.accent.g, Colors.accent.b, 0.28)
                     : cMa.containsMouse ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(1, 1, 1, 0.05)
                Behavior on color { ColorAnimation { duration: Appearance.mQuick; easing.type: Easing.OutQuad } }
                Text {
                    id: t
                    anchors.centerIn: parent
                    text: modelData
                    color: parent.sel ? "#ffffff" : "#9a9a9a"
                    font.family: Appearance.fontUI
                    font.pixelSize: Appearance.fsXS
                    font.weight: parent.sel ? Font.Medium : Font.Normal
                }
                MouseArea {
                    id: cMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: ch.picked(String(modelData))
                }
            }
        }
    }

    // ─────────── botón pequeño ───────────
    component Btn_: Rectangle {
        id: b
        property string text: ""
        property bool danger: false
        signal clicked

        implicitWidth: bt.implicitWidth + 26
        implicitHeight: 28
        radius: 9
        color: bMa.containsMouse
             ? (b.danger ? Qt.rgba(Colors.crit.r, Colors.crit.g, Colors.crit.b, 0.30) : Qt.rgba(1, 1, 1, 0.13))
             : Qt.rgba(1, 1, 1, 0.06)
        Behavior on color { ColorAnimation { duration: Appearance.mQuick; easing.type: Easing.OutQuad } }

        Text {
            id: bt
            anchors.centerIn: parent
            text: b.text
            color: bMa.containsMouse ? "#ffffff" : "#9a9a9a"
            font.family: Appearance.fontUI
            font.pixelSize: Appearance.fsXS
        }
        MouseArea {
            id: bMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: b.clicked()
        }
    }

    // ─────────── valor de solo lectura (Acerca de) ───────────
    component Val_: Text {
        Layout.maximumWidth: 310
        color: "#b9b9b9"
        elide: Text.ElideRight
        horizontalAlignment: Text.AlignRight
        font.family: Appearance.fontUI
        font.pixelSize: Appearance.fsS
    }

    // ─────────── texto suelto (estados vacíos, notas) ───────────
    component Note_: Text {
        Layout.fillWidth: true
        wrapMode: Text.Wrap
        color: "#777777"
        font.family: Appearance.fontUI
        font.pixelSize: Appearance.fsXS
    }

    // ─────────── estado vacío con intención, no un hueco que parece roto ───────────
    component Empty_: Rectangle {
        id: empty
        property string icon: ""
        property string title: ""
        property string body: ""

        Layout.fillWidth: true
        Layout.preferredHeight: 126
        radius: Appearance.radM
        color: Qt.rgba(1, 1, 1, 0.025)
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.055)

        ColumnLayout {
            anchors.centerIn: parent
            width: Math.min(parent.width - 40, 380)
            spacing: 5
            Text {
                Layout.alignment: Qt.AlignHCenter
                text: empty.icon
                color: "#777777"
                font.family: Appearance.font
                font.pixelSize: 22
            }
            Text {
                Layout.fillWidth: true
                text: empty.title
                color: "#c9c9c9"
                horizontalAlignment: Text.AlignHCenter
                font.family: Appearance.fontUI
                font.pixelSize: Appearance.fsS
                font.weight: Font.Medium
            }
            Text {
                Layout.fillWidth: true
                text: empty.body
                color: "#707070"
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                font.family: Appearance.fontUI
                font.pixelSize: Appearance.fsXS
            }
        }
    }
}
