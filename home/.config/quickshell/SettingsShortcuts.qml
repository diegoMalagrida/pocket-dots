// SettingsShortcuts.qml — the keyboard shortcuts, read live from
// ~/.config/hypr/hyprland.conf.
//
// WHY READ THEM RATHER THAN WRITE THEM BY HAND: a list written here falls out
// of sync the first day you touch a bind. This parses the real file
// (resolving $mainMod) and reloads only when it changes, so it cannot lie.
//
// This is NOW the only list of shortcuts: Super+K used to open a separate rofi
// (~/.config/hypr/list_keybinds.sh) that did this same parsing of the same
// file, i.e. two lists that only agreed as long as nobody touched either.
// Since 2026-08-19 that key comes straight here (GlobalShortcut "keybinds" in
// SettingsWindow.qml) and the script was archived.
//
// For now it is READ-ONLY: reassigning keys would mean rewriting the .conf
// with the risk of mangling comments and order, and that file is the rice's
// source of truth.
import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Flickable {
    id: root

    property string note: I18n.tr("Se leen de ~/.config/hypr/hyprland.conf. Super+K abre esta misma lista.")
    property var binds: []
    readonly property int matchCount: cShell.visibleRows + cWin.visibleRows + cWs.visibleRows
        + cApps.visibleRows + cSys.visibleRows

    contentHeight: col.implicitHeight + 34
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded; width: 5 }
    onVisibleChanged: if (visible) contentY = 0

    FileView {
        id: conf
        path: ShellState.home + "/.config/hypr/hyprland.conf"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.binds = root.parseConf(text())
    }

    // The list is built ONCE, when the file is read: it is not a binding.
    // Since the key and dispatcher labels ARE translated, a language change
    // has to parse again, or they would stay in the previous language until
    // someone touched hyprland.conf.
    Connections {
        target: I18n
        function onLangChanged() {
            const t = conf.text();
            if (t && t.length > 0) root.binds = root.parseConf(t);
        }
    }

    // ─────────── parsing ──────────
    function parseConf(txt) {
        if (!txt || txt.length === 0) return [];
        const vars = {};
        const out = [];
        const lines = txt.split("\n");
        for (let i = 0; i < lines.length; i++) {
            const line = lines[i].trim();
            let m = line.match(/^\$(\w+)\s*=\s*(.+)$/);
            if (m) { vars[m[1]] = m[2].split("#")[0].trim(); continue; }
            m = line.match(/^(bind[a-z]*)\s*=\s*(.+)$/);
            if (!m) continue;

            let rest = m[2];
            let comment = "";
            const h = rest.indexOf("#");
            if (h >= 0) { comment = rest.slice(h + 1).trim(); rest = rest.slice(0, h); }

            const parts = rest.split(",");
            if (parts.length < 3) continue;
            let mods = parts[0].trim();
            const key = parts[1].trim();
            const disp = parts[2].trim();
            const args = parts.slice(3).join(",").trim();
            for (const k in vars) mods = mods.replace("$" + k, vars[k]);

            out.push({
                combo: root.comboLabel(mods, key),
                // The comment comes from hyprland.conf itself, in Spanish, and is
                // translated here: that way the bind comments -the one part of
                // that file left in Spanish, on purpose- do not have to be touched
                // to change language. The dictionary key is the literal comment.
                what: comment.length > 0 ? I18n.tr(comment) : root.dispLabel(disp, args),
                group: root.groupOf(disp, args)
            });
        }
        return out;
    }

    readonly property var modNames: ({
        "SUPER": "Super", "SHIFT": "Shift", "CTRL": "Ctrl", "CONTROL": "Ctrl", "ALT": "Alt"
    })
    readonly property var keyNames: ({
        "comma": ",", "period": ".", "slash": "/", "space": I18n.tr("Espacio"), "TAB": "Tab",
        "Print": I18n.tr("Impr Pant"), "return": I18n.tr("Intro"), "escape": "Esc",
        "left": "←", "right": "→", "up": "↑", "down": "↓",
        "mouse_down": I18n.tr("rueda ↓"), "mouse_up": I18n.tr("rueda ↑"),
        "mouse:272": I18n.tr("clic izq."), "mouse:273": I18n.tr("clic der."),
        "XF86AudioRaiseVolume": I18n.tr("Subir volumen"), "XF86AudioLowerVolume": I18n.tr("Bajar volumen"),
        "XF86AudioMute": I18n.tr("Silenciar"), "XF86AudioMicMute": I18n.tr("Silenciar micro"),
        "XF86AudioNext": I18n.tr("Siguiente"), "XF86AudioPrev": I18n.tr("Anterior"),
        "XF86AudioPlay": I18n.tr("Reproducir"), "XF86AudioPause": I18n.tr("Pausa"),
        "XF86MonBrightnessUp": I18n.tr("Subir brillo"), "XF86MonBrightnessDown": I18n.tr("Bajar brillo"),
        "XF86PowerOff": I18n.tr("Botón de encendido")
    })

    function comboLabel(mods, key) {
        const out = [];
        const ms = mods.split(/\s+/);
        for (let i = 0; i < ms.length; i++) {
            const t = ms[i].trim().toUpperCase();
            if (t.length === 0) continue;
            out.push(root.modNames[t] !== undefined ? root.modNames[t] : ms[i].trim());
        }
        const k = key.trim();
        out.push(root.keyNames[k] !== undefined ? root.keyNames[k]
               : (k.length === 1 ? k.toUpperCase() : k));
        return out.join(" + ");
    }

    readonly property var dispNames: ({
        "killactive": I18n.tr("cerrar la ventana"), "exit": I18n.tr("salir de Hyprland"),
        "togglefloating": I18n.tr("flotante sí/no"), "fullscreen": I18n.tr("pantalla completa"),
        "pseudo": "pseudo-tile", "togglesplit": I18n.tr("cambiar el split"),
        "movefocus": I18n.tr("mover el foco"), "movewindow": I18n.tr("mover la ventana"),
        "resizeactive": I18n.tr("redimensionar"), "workspace": I18n.tr("ir al escritorio"),
        "movetoworkspace": I18n.tr("llevar al escritorio"), "layoutmsg": "layout",
        "togglespecialworkspace": I18n.tr("escritorio especial")
    })

    function dispLabel(disp, args) {
        if (disp === "exec") return args;
        if (disp === "global") return args.replace("quickshell:", "");
        const base = root.dispNames[disp] !== undefined ? root.dispNames[disp] : disp;
        return args.length > 0 ? base + " " + args : base;
    }

    function groupOf(disp, args) {
        if (disp === "global") return "shell";
        if (disp === "exec") return "apps";
        if (disp.indexOf("workspace") >= 0) return "ws";
        if (disp.indexOf("window") >= 0 || disp.indexOf("focus") >= 0
            || disp === "killactive" || disp === "togglefloating"
            || disp === "fullscreen" || disp === "pseudo" || disp === "togglesplit"
            || disp === "layoutmsg" || disp === "resizeactive") return "win";
        return "sys";
    }

    function ofGroup(g) {
        const out = [];
        for (let i = 0; i < root.binds.length; i++) if (root.binds[i].group === g) out.push(root.binds[i]);
        return out;
    }

    ColumnLayout {
        id: col
        width: root.width - 48
        x: 24
        y: 16
        spacing: 10

        SettingsControls.Card_ {
            id: cShell
            title: I18n.tr("El shell")
            Repeater {
                model: root.ofGroup("shell")
                onItemAdded: cShell.recount()
                onItemRemoved: cShell.recount()
                KeyRow {}
            }
        }

        SettingsControls.Card_ {
            id: cWin
            title: I18n.tr("Ventanas")
            Repeater {
                model: root.ofGroup("win")
                onItemAdded: cWin.recount()
                onItemRemoved: cWin.recount()
                KeyRow {}
            }
        }

        SettingsControls.Card_ {
            id: cWs
            title: I18n.tr("Escritorios")
            Repeater {
                model: root.ofGroup("ws")
                onItemAdded: cWs.recount()
                onItemRemoved: cWs.recount()
                KeyRow {}
            }
        }

        SettingsControls.Card_ {
            id: cApps
            title: I18n.tr("Apps y scripts")
            Repeater {
                model: root.ofGroup("apps")
                onItemAdded: cApps.recount()
                onItemRemoved: cApps.recount()
                KeyRow {}
            }
        }

        SettingsControls.Card_ {
            id: cSys
            title: I18n.tr("Sistema")
            Repeater {
                model: root.ofGroup("sys")
                onItemAdded: cSys.recount()
                onItemRemoved: cSys.recount()
                KeyRow {}
            }
        }

        SettingsControls.Note_ {
            Layout.topMargin: 10
            visible: root.binds.length === 0
            text: I18n.tr("No se ha podido leer ningún atajo de hyprland.conf.")
        }

        SettingsControls.Note_ {
            Layout.topMargin: 10
            visible: root.binds.length > 0 && ShellState.settingsQuery.length > 0
                     && !cShell.visible && !cWin.visible && !cWs.visible && !cApps.visible && !cSys.visible
            text: I18n.tr("Ningún atajo coincide con «{0}».", ShellState.settingsQuery)
        }
    }

    // ─────────── shortcut row ────────────
    component KeyRow: Rectangle {
        id: kr
        required property var modelData

        readonly property bool isSettingsRow: true
        readonly property bool matches: ShellState.settingsMatch(kr.modelData.combo, kr.modelData.what)
        function _recount() {
            let p = kr.parent;
            while (p) { if (p.isSettingsCard) { p.recount(); return; } p = p.parent; }
        }
        onMatchesChanged: kr._recount()
        Component.onCompleted: kr._recount()

        Layout.fillWidth: true
        Layout.preferredHeight: 34
        visible: kr.matches
        radius: Appearance.radS
        color: krHover.hovered ? Colors.fill2 : "transparent"
        Behavior on color { ColorAnimation { duration: Appearance.mQuick; easing.type: Easing.OutQuad } }

        HoverHandler {
            id: krHover
            onHoveredChanged: {
                if (hovered) ShellState.settingsHint = kr.modelData.what;
                else if (ShellState.settingsHint === kr.modelData.what) ShellState.settingsHint = "";
            }
        }

        RowLayout {
            anchors { fill: parent; leftMargin: 12; rightMargin: 12 }
            spacing: 14

            Rectangle {
                Layout.preferredWidth: 152
                Layout.preferredHeight: 22
                radius: 7
                color: Colors.fill3
                Text {
                    anchors { fill: parent; leftMargin: 8; rightMargin: 8 }
                    verticalAlignment: Text.AlignVCenter
                    text: kr.modelData.combo
                    color: Colors.label
                    elide: Text.ElideRight
                    font.family: Appearance.fontUI
                    font.pixelSize: Appearance.fsXS
                }
            }

            Text {
                Layout.fillWidth: true
                text: kr.modelData.what
                color: Colors.label2
                elide: Text.ElideRight
                font.family: Appearance.fontUI
                font.pixelSize: Appearance.fsXS
            }
        }
    }
}
