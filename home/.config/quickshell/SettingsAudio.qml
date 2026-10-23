// SettingsAudio.qml — audio output and input (native Pipewire, no pavucontrol).
//
// THE BUG THIS VERSION FIXES: the four output devices on this laptop are
// literally called:
//
//   "500 Series Chipset Family On-Package High Definition Audio (HD Audio) Speaker"
//   "500 Series Chipset Family On-Package High Definition Audio (HD Audio) HDMI / DisplayPort 1 Output"
//   …
//
// What tells them apart comes AT THE END, so the list showed four identical
// rows cut off at the same point and it was impossible to choose. Now:
//   1) if the node carries `nickname` (node.nick: "Speaker", "HDMI 1"), use it;
//   2) if not, strip the prefix common to all devices, worked out live — so
//      it works with any card, not just this one;
//   3) and translate the usual four terms into the shell's language.
// The full name is not lost: it appears in the footer strip when you hover
// over the row.
import Quickshell
import Quickshell.Services.Pipewire
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Flickable {
    id: root

    property string note: I18n.tr("El dispositivo marcado es el predeterminado; pincha otro para cambiarlo.")
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
            if (n.isStream) continue;          // streams are apps, not devices
            if (!n.audio) continue;
            // "Monitor of …" nodes are the output fed back in, not a microphone
            if (!n.isSink && String(n.name || "").indexOf(".monitor") >= 0) continue;
            if (n.isSink === sink) out.push(n);
        }
        return out;
    }

    readonly property var sinks: nodesOf(true)
    readonly property var sources: nodesOf(false)

    // Without this the node properties (description, volume) are not populated.
    PwObjectTracker { objects: root.sinks.concat(root.sources) }

    // Prefix common to ALL devices: it is the card's name, and it is exactly
    // what is surplus. With a single device nothing is stripped.
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

    // ALSA names come in English and are always the same four. The device name
    // is data and is respected; what gets translated are these generic terms,
    // into the shell's language.
    function toES(s) {
        return s
            .replace(/HDMI \/ DisplayPort (\d+) Output/i, "HDMI $1")
            .replace(/\bDigital Microphone\b/i, I18n.tr("Micrófono digital"))
            .replace(/\bStereo Microphone\b/i, I18n.tr("Micrófono estéreo"))
            .replace(/\bInternal Microphone\b/i, I18n.tr("Micrófono interno"))
            .replace(/\bMicrophone\b/i, I18n.tr("Micrófono"))
            .replace(/\bSpeakers?\b/i, I18n.tr("Altavoces"))
            .replace(/\bHeadphones\b/i, I18n.tr("Auriculares"))
            .replace(/\bHeadset\b/i, I18n.tr("Auriculares"))
            .replace(/\bBuilt-?in\b/i, I18n.tr("Integrado"))
            .replace(/\s+(Output|Input)\b/i, "")
            .trim();
    }

    ColumnLayout {
        id: col
        width: root.width - 48
        x: 24
        y: 16
        spacing: 10

        // ─────────────────── volume ───────────────────
        SettingsControls.Card_ {
            id: cVol
            title: I18n.tr("Salida")

            SettingsControls.Row_ {
                label: I18n.tr("Volumen")
                hint: I18n.tr("El del dispositivo predeterminado. Es el mismo que mueven las teclas de volumen.")
                SettingsControls.Slider_ {
                    value: ShellState.muted ? 0 : ShellState.vol
                    from: 0; to: 100; suffix: " %"
                    onMoved: function (v) { ShellState.setVolume(v); }
                }
            }
            SettingsControls.Row_ {
                label: I18n.tr("Silenciar")
                hint: I18n.tr("Silencia la salida sin perder el nivel al que la tenías.")
                SettingsControls.Switch_ {
                    checked: ShellState.muted
                    onToggled: ShellState.toggleMute()
                }
            }
        }

        // ─────────────────── output devices ───────────────────
        SettingsControls.Card_ {
            id: cSinks
            title: I18n.tr("Dispositivo de salida")

            Repeater {
                model: root.sinks
                onItemAdded: cSinks.recount()
                onItemRemoved: cSinks.recount()
                DeviceRow { isSink: true }
            }
        }

        // ─────────────────── input devices ───────────────────
        SettingsControls.Card_ {
            id: cSources
            title: I18n.tr("Dispositivo de entrada")

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
            title: I18n.tr("No se ven dispositivos de audio")
            body: I18n.tr("Comprueba que PipeWire esté activo o vuelve a conectar el dispositivo.")
        }

        SettingsControls.Note_ {
            Layout.topMargin: 10
            visible: ShellState.settingsQuery.length > 0
                     && !cVol.visible && !cSinks.visible && !cSources.visible
            text: I18n.tr("Nada de Sonido coincide con «{0}».", ShellState.settingsQuery)
        }
    }

    // ─────────── device row ───────────
    component DeviceRow: Rectangle {
        id: dev
        required property var modelData
        property bool isSink: true

        readonly property string short_: root.shortName(dev.modelData)
        readonly property string full_: root.fullName(dev.modelData)
        readonly property bool isDefault: dev.isSink
            ? (Pipewire.defaultAudioSink && Pipewire.defaultAudioSink.id === dev.modelData.id)
            : (Pipewire.defaultAudioSource && Pipewire.defaultAudioSource.id === dev.modelData.id)

        // contract with Card_ and with the search box
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
             : devMa.containsMouse ? Colors.fill2 : "transparent"
        Behavior on color { ColorAnimation { duration: Appearance.mQuick; easing.type: Easing.OutQuad } }

        RowLayout {
            anchors { fill: parent; leftMargin: 12; rightMargin: 12 }
            spacing: 12

            Text {
                text: dev.isSink ? "󰓃" : "󰍬"
                color: dev.isDefault ? Colors.accentInk : Colors.label2
                font.family: Appearance.font
                font.pixelSize: 15
            }
            Text {
                Layout.fillWidth: true
                text: dev.short_
                color: Colors.label
                elide: Text.ElideRight
                font.family: Appearance.fontUI
                font.pixelSize: Appearance.fsS
                font.weight: dev.isDefault ? Font.Medium : Font.Normal
            }
            Text {
                visible: dev.isDefault
                text: I18n.tr("predeterminado")
                color: Colors.accentInk
                font.family: Appearance.fontUI
                font.pixelSize: Appearance.fsXS
            }
            Text {
                visible: dev.isDefault
                text: "󰄬"
                color: Colors.accentInk
                font.family: Appearance.font
                font.pixelSize: Appearance.fsM
            }
        }

        MouseArea {
            id: devMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            // the long name is not lost: it lives in the window footer
            onEntered: ShellState.settingsHint = dev.full_
            onExited: if (ShellState.settingsHint === dev.full_) ShellState.settingsHint = ""
            onClicked: {
                if (dev.isSink) Pipewire.preferredDefaultAudioSink = dev.modelData;
                else Pipewire.preferredDefaultAudioSource = dev.modelData;
            }
        }
    }
}
