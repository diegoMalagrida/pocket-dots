// SettingsAudio.qml — salida y entrada de audio (Pipewire nativo, sin pavucontrol).
//
// EL BUG QUE ARREGLA ESTA VERSIÓN: los cuatro dispositivos de salida de este
// portátil se llaman, literalmente:
//
//   "500 Series Chipset Family On-Package High Definition Audio (HD Audio) Speaker"
//   "500 Series Chipset Family On-Package High Definition Audio (HD Audio) HDMI / DisplayPort 1 Output"
//   …
//
// Lo que los distingue va AL FINAL, así que la lista enseñaba cuatro filas
// idénticas cortadas por el mismo sitio y era imposible elegir. Ahora:
//   1) si el nodo trae `nickname` (node.nick: "Speaker", "HDMI 1"), se usa ese;
//   2) si no, se le quita el prefijo común a todos los dispositivos, calculado
//      en vivo — así funciona con cualquier tarjeta, no solo con esta;
//   3) y se traducen los cuatro términos de siempre al castellano.
// El nombre completo no se pierde: sale en la franja del pie al pasar por
// encima de la fila.
import Quickshell
import Quickshell.Services.Pipewire
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Flickable {
    id: root

    property string note: "El dispositivo marcado es el predeterminado; pincha otro para cambiarlo."
    readonly property int matchCount: cVol.visibleRows + cSinks.visibleRows + cSources.visibleRows

    contentHeight: col.implicitHeight + 34
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded; width: 5 }
    onVisibleChanged: if (visible) contentY = 0

    function nodesOf(sink) {
        const vs = Pipewire.nodes ? Pipewire.nodes.values : [];
        const out = [];
        for (let i = 0; i < vs.length; i++) {
            const n = vs[i];
            if (n.isStream) continue;          // los streams son apps, no dispositivos
            if (!n.audio) continue;
            // los "Monitor of …" son la salida reinyectada, no un micrófono
            if (!n.isSink && String(n.name || "").indexOf(".monitor") >= 0) continue;
            if (n.isSink === sink) out.push(n);
        }
        return out;
    }

    readonly property var sinks: nodesOf(true)
    readonly property var sources: nodesOf(false)

    // Sin esto las propiedades de los nodos (descripción, volumen) no se pueblan.
    PwObjectTracker { objects: root.sinks.concat(root.sources) }

    // Prefijo común a TODOS los dispositivos: es el nombre de la tarjeta, y es
    // exactamente lo que sobra. Con un solo dispositivo no se quita nada.
    readonly property string commonPrefix: {
        const all = root.sinks.concat(root.sources).map(function (n) { return String(n.description || ""); });
        if (all.length < 2) return "";
        let p = all[0];
        for (let i = 1; i < all.length; i++) {
            let j = 0;
            while (j < p.length && j < all[i].length && p[j] === all[i][j]) j++;
            p = p.slice(0, j);
            if (p.length === 0) break;
        }
        return p;
    }

    function fullName(n) {
        return String(n.description || n.nickname || n.name || "");
    }

    function shortName(n) {
        const nick = String(n.nickname || "").trim();
        let s = "";
        if (nick.length > 0 && nick.length <= 28) {
            s = nick;
        } else {
            const full = root.fullName(n);
            s = (root.commonPrefix.length > 0 && full.indexOf(root.commonPrefix) === 0)
                ? full.slice(root.commonPrefix.length) : full;
            s = s.replace(/^[\s\-–·:,()]+/, "");
        }
        return root.toES(s.length > 0 ? s : root.fullName(n));
    }

    // Los nombres de ALSA vienen en inglés y siempre son los mismos cuatro.
    function toES(s) {
        return s
            .replace(/HDMI \/ DisplayPort (\d+) Output/i, "HDMI $1")
            .replace(/\bDigital Microphone\b/i, "Micrófono digital")
            .replace(/\bStereo Microphone\b/i, "Micrófono estéreo")
            .replace(/\bInternal Microphone\b/i, "Micrófono interno")
            .replace(/\bMicrophone\b/i, "Micrófono")
            .replace(/\bSpeakers?\b/i, "Altavoces")
            .replace(/\bHeadphones\b/i, "Auriculares")
            .replace(/\bHeadset\b/i, "Auriculares")
            .replace(/\bBuilt-?in\b/i, "Integrado")
            .replace(/\s+(Output|Input)\b/i, "")
            .trim();
    }

    ColumnLayout {
        id: col
        width: root.width - 48
        x: 24
        y: 16
        spacing: 10

        // ─────────────────── volumen ───────────────────
        SettingsControls.Card_ {
            id: cVol
            title: "SALIDA"

            SettingsControls.Row_ {
                label: "Volumen"
                hint: "El del dispositivo predeterminado. Es el mismo que mueven las teclas de volumen."
                SettingsControls.Slider_ {
                    value: ShellState.muted ? 0 : ShellState.vol
                    from: 0; to: 100; suffix: " %"
                    onMoved: function (v) { ShellState.setVolume(v); }
                }
            }
            SettingsControls.Row_ {
                label: "Silenciar"
                hint: "Silencia la salida sin perder el nivel al que la tenías."
                SettingsControls.Switch_ {
                    checked: ShellState.muted
                    onToggled: ShellState.toggleMute()
                }
            }
        }

        // ─────────────────── dispositivos de salida ───────────────────
        SettingsControls.Card_ {
            id: cSinks
            title: "DISPOSITIVO DE SALIDA"

            Repeater {
                model: root.sinks
                onItemAdded: cSinks.recount()
                onItemRemoved: cSinks.recount()
                DeviceRow { isSink: true }
            }
        }

        // ─────────────────── dispositivos de entrada ───────────────────
        SettingsControls.Card_ {
            id: cSources
            title: "DISPOSITIVO DE ENTRADA"

            Repeater {
                model: root.sources
                onItemAdded: cSources.recount()
                onItemRemoved: cSources.recount()
                DeviceRow { isSink: false }
            }
        }

        SettingsControls.Empty_ {
            Layout.topMargin: 10
            visible: ShellState.settingsQuery.length === 0
                && root.sinks.length === 0 && root.sources.length === 0
            icon: "󰕾"
            title: "No se ven dispositivos de audio"
            body: "Comprueba que PipeWire esté activo o vuelve a conectar el dispositivo."
        }

        SettingsControls.Note_ {
            Layout.topMargin: 10
            visible: ShellState.settingsQuery.length > 0
                     && !cVol.visible && !cSinks.visible && !cSources.visible
            text: "Nada de Sonido coincide con «" + ShellState.settingsQuery + "»."
        }
    }

    // ─────────── fila de dispositivo ───────────
    component DeviceRow: Rectangle {
        id: dev
        required property var modelData
        property bool isSink: true

        readonly property string short_: root.shortName(dev.modelData)
        readonly property string full_: root.fullName(dev.modelData)
        readonly property bool isDefault: dev.isSink
            ? (Pipewire.defaultAudioSink && Pipewire.defaultAudioSink.id === dev.modelData.id)
            : (Pipewire.defaultAudioSource && Pipewire.defaultAudioSource.id === dev.modelData.id)

        // contrato con Card_ y con el buscador
        readonly property bool isSettingsRow: true
        readonly property bool matches: ShellState.settingsMatch(dev.short_, dev.full_)
        function _recount() {
            let p = dev.parent;
            while (p) { if (p.isSettingsCard) { p.recount(); return; } p = p.parent; }
        }
        onMatchesChanged: dev._recount()
        Component.onCompleted: dev._recount()

        Layout.fillWidth: true
        Layout.preferredHeight: 42
        visible: dev.matches
        radius: Appearance.radS
        color: dev.isDefault ? Qt.rgba(Colors.accent.r, Colors.accent.g, Colors.accent.b, 0.18)
             : devMa.containsMouse ? Qt.rgba(1, 1, 1, 0.07) : "transparent"
        Behavior on color { ColorAnimation { duration: Appearance.mQuick; easing.type: Easing.OutQuad } }

        RowLayout {
            anchors { fill: parent; leftMargin: 12; rightMargin: 12 }
            spacing: 12

            Text {
                text: dev.isSink ? "󰓃" : "󰍬"
                color: dev.isDefault ? Colors.accent : "#9a9a9a"
                font.family: Appearance.font
                font.pixelSize: 15
            }
            Text {
                Layout.fillWidth: true
                text: dev.short_
                color: "#ffffff"
                elide: Text.ElideRight
                font.family: Appearance.fontUI
                font.pixelSize: Appearance.fsS
                font.weight: dev.isDefault ? Font.Medium : Font.Normal
            }
            Text {
                visible: dev.isDefault
                text: "predeterminado"
                color: Colors.accent
                font.family: Appearance.fontUI
                font.pixelSize: Appearance.fsXS
            }
            Text {
                visible: dev.isDefault
                text: "󰄬"
                color: Colors.accent
                font.family: Appearance.font
                font.pixelSize: 13
            }
        }

        MouseArea {
            id: devMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            // el nombre largo no se pierde: vive en el pie de la ventana
            onEntered: ShellState.settingsHint = dev.full_
            onExited: if (ShellState.settingsHint === dev.full_) ShellState.settingsHint = ""
            onClicked: {
                if (dev.isSink) Pipewire.preferredDefaultAudioSink = dev.modelData;
                else Pipewire.preferredDefaultAudioSource = dev.modelData;
            }
        }
    }
}
