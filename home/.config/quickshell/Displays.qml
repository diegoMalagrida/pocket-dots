// Displays.qml — the displays: what is connected and how you want it arranged.
//
// Adapted from Impasto's services/MonitorService.qml
// (https://github.com/andreumassanet/impasto, GPL-3.0), with two differences
// that come from how this rice is built:
//
//   · There is NO "primary display". The bar and the notch are created once
//     PER DISPLAY (Variants over Quickshell.screens in TopShell), so there is
//     nothing here to put on a single one: Impasto's option would make no sense.
//
//   · Changes that can leave you in the dark —resolution, scale, rotation,
//     mirroring— are NOT simply applied. They go on trial for 20 seconds and
//     revert by themselves if you do not confirm. A mode the monitor advertises
//     but does not display leaves you with no way to undo it, and the place to
//     undo it is the display you have just broken.
//
// NONE of this writes to hypr/*.lua. The catch-all rule in hyprland.lua
// (`output = ""`, preferred/auto) is still the floor for any display you plug
// in, and your settings live in quickshell-rice.json and are pushed again every
// time Hyprland loses them: on config reload and on plug-in.
//
// The whole conversation with Hyprland goes through scripts/monitors.py: it
// validates the fields before they reach `hyprctl eval` (with a Lua config,
// `hyprctl keyword` fails silently) and sends the WHOLE layout at once,
// because `position = "auto"` is resolved against what the previous line left.
pragma Singleton

import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import QtQuick

Singleton {
    id: root

    readonly property string home: Quickshell.env("HOME")
    readonly property string tool: root.home + "/.config/quickshell/scripts/monitors.py"

    // Everything plugged in, on or not, exactly as monitors.py reports it.
    property var monitors: []
    property bool loaded: false

    // The last thing the script said when something went wrong. The section
    // shows it instead of failing silently.
    property string problem: ""

    readonly property var lit: root.monitors.filter(m => !m.disabled)
    readonly property bool several: root.monitors.length > 1

    function monitorFor(key) {
        return root.monitors.find(m => m.key === key) || null;
    }

    // ───────── which set of displays there is now ─────────
    //
    // The key is the SET, sorted so it does not depend on the order Hyprland
    // enumerates them in. That way the home monitor brings its layout back
    // when plugged in, and unplugging it brings back the laptop-alone one,
    // without you touching anything. Each display goes by its description
    // (manufacturer, model and serial), not by port: moving the cable is not
    // changing monitor. Two identical monitors with no serial number cannot be
    // told apart, and only in that case does monitors.py fall back to the port.
    readonly property string setKey: root.monitors.map(m => m.key).sort().join(" · ")

    readonly property var saved: (Config.displays || ({}))[root.setKey] || null
    readonly property bool arranged: !!root.saved
    readonly property bool mirroring: !!(root.saved && root.saved.mirror)

    function savedRule(key) {
        return ((root.saved && root.saved.monitors) || ({}))[key] || null;
    }

    // ───────── read ─────────

    Process {
        id: reader
        command: [root.tool, "get"]
        stdout: StdioCollector {
            onStreamFinished: {
                if (!text || text.trim() === "") return;
                let rows = [];
                try { rows = JSON.parse(text); } catch (e) { return; }
                if (!Array.isArray(rows)) return;
                root.monitors = rows;
                root.loaded = true;
                if (root.rescue()) return;
                root.push();
            }
        }
    }

    function load() { reader.running = true; }

    // ───────── save ─────────
    //
    // The controls only write here; pushing to Hyprland is push()'s job.
    // A single path to the compositor, and the file is the truth.

    function remember(key, fields) {
        const all = Object.assign({}, Config.displays || ({}));
        const set = Object.assign({ mirror: false, monitors: ({}) }, all[root.setKey] || ({}));
        const screens = Object.assign({}, set.monitors || ({}));
        screens[key] = Object.assign({}, screens[key] || ({}), fields);
        set.monitors = screens;
        all[root.setKey] = set;
        Config.displays = all;
        Config.save();
    }

    function rememberMirror(on) {
        const all = Object.assign({}, Config.displays || ({}));
        const set = Object.assign({ mirror: false, monitors: ({}) }, all[root.setKey] || ({}));
        set.mirror = !!on;
        all[root.setKey] = set;
        Config.displays = all;
        Config.save();
    }

    // Returns these displays to Hyprland's automatic placement. The reload is
    // needed: Hyprland keeps whatever was last pushed to it, so deleting the
    // memory without reloading undoes nothing.
    function forget() {
        const all = Object.assign({}, Config.displays || ({}));
        delete all[root.setKey];
        Config.displays = all;
        Config.save();
        reloader.running = true;
    }

    Process {
        id: reloader
        command: ["hyprctl", "reload"]
        onExited: root.load()
    }

    // ───────── the whole layout ─────────
    //
    // monitors.py demands one rule per connected display, no more and no
    // fewer: the layout is a transaction, and that way it can validate it whole
    // (that something stays on, that mirroring does not form a cycle) before
    // sending anything. What is saved wins; whatever is not saved is filled in
    // with what is set right now, so saving only one display's resolution does
    // not move the others.
    //
    // `extra` lets you work out how things WOULD end up with a change that is
    // not saved yet, which is what gets put on trial.
    function layout(extraKey, extra) {
        const rules = [];
        // The mirroring target: the first one that is on, which Hyprland
        // enumerates first and does not change by itself between reads.
        const target = root.lit.length > 0 ? root.lit[0] : null;
        for (const m of root.monitors) {
            const kept = Object.assign({}, root.savedRule(m.key) || ({}));
            if (extra && m.key === extraKey) Object.assign(kept, extra);
            const off = kept.disabled !== undefined ? !!kept.disabled : m.disabled;
            // A display being turned off goes alone: `disabled` and nothing
            // else. Giving it mode, scale and position too is describing the
            // geometry of something that will draw nothing, and a display that
            // is off reports zeros, so those numbers would not even be its own.
            if (off) {
                rules.push({ output: m.name, disabled: true });
                continue;
            }
            const rule = {
                output: m.name,
                disabled: false,
                mode: kept.mode !== undefined ? kept.mode : m.mode,
                scale: kept.scale !== undefined ? kept.scale : m.scale,
                transform: kept.transform !== undefined ? kept.transform : m.transform,
                vrr: kept.vrr !== undefined ? kept.vrr : m.vrr
            };
            // Mirroring belongs to the set, not to each display: it is saved
            // once and handed out here. A mirrored display carries no position
            // —Hyprland would ignore it— so it is not compared later either.
            const mirror = (extra && extraKey === "*" && extra.mirror !== undefined)
                         ? !!extra.mirror : root.mirroring;
            if (mirror && target && m.name !== target.name) {
                rule.mirror = target.name;
            } else {
                rule.mirror = "none";
                rule.position = kept.position !== undefined ? kept.position : m.position;
            }
            rules.push(rule);
        }
        return rules;
    }

    // Does this rule say something different from what the display is already
    // doing? Besides saving work, this is the loop's brake: turning a display
    // on fires `monitoradded`, which reads again and here finds nothing left
    // to change.
    function differs(rule) {
        const m = root.monitors.find(x => x.name === rule.output);
        if (!m) return false;
        if (rule.disabled !== m.disabled) return true;
        // A display that is off has no geometry to compare: hyprctl reports it
        // as zero and any comparison would always say yes.
        if (m.disabled) return false;
        return rule.mode !== m.mode
            || Number(rule.scale) !== Number(m.scale)
            || Number(rule.transform) !== Number(m.transform)
            || Number(rule.vrr) !== Number(m.vrr)
            || rule.mirror !== m.mirror
            || (rule.position !== undefined && rule.position !== m.position);
    }

    // ───────── push ─────────

    // Drags on the map and the file load arrive all at once; this gathers them
    // into a single push.
    Timer { id: soon; interval: 120; onTriggered: root.push() }

    // THE BRAKE. The normal cycle is: I push, Hyprland changes, the event makes
    // me re-read, and on re-reading there is nothing left to change. But if
    // Hyprland says "ok" and does nothing —it happens with a scale that does
    // not fit the resolution, and it does not count it as an error—, the cycle
    // never ends: re-read, still differs, push again, every 600 ms, forever.
    // After three identical attempts it gives up and says why. It tries again
    // as soon as you change something, because the signature changes.
    property string lastPush: ""
    property int tries: 0

    function push() {
        if (!root.loaded || root.trying || settling.running) return;
        if (!root.arranged) return;      // with nothing saved, hyprland.lua is in charge
        const rules = root.layout("", null);
        if (!rules.some(r => root.differs(r))) {
            root.lastPush = "";
            root.tries = 0;
            root.problem = "";   // whatever the brake had set is now applied
            return;
        }
        const signature = JSON.stringify(rules);
        if (signature === root.lastPush) {
            if (root.tries >= 3) return;
            root.tries++;
        } else {
            root.lastPush = signature;
            root.tries = 1;
        }
        if (root.tries === 3)
            root.problem = I18n.tr("Hyprland acepta la distribución pero no la aplica. Revisa la escala o el modo de vídeo de esa pantalla.");
        settling.restart();
        applier.command = [root.tool, "apply", signature];
        applier.running = true;
    }

    Process {
        id: applier
        stdout: SplitParser {
            onRead: function (line) {
                let msg = null;
                try { msg = JSON.parse(line); } catch (e) { return; }
                if (msg && msg.event === "error") root.problem = I18n.tr(String(msg.message || ""));
            }
        }
    }

    // Turning an output on releases a burst of events. While this runs nothing
    // is pushed, and the read at the end sees the state already settled.
    Timer {
        id: settling
        interval: 600
        onTriggered: root.load()
    }

    // ───────── on trial, with rollback ─────────
    //
    // Resolution, scale, rotation and mirroring go through here. The script
    // applies the change, waits for a line on its standard input and, if "keep"
    // does not arrive before time runs out, restores what was there. The
    // countdown is kept by the PROCESS, not the interface: if the shell reloads
    // or closes mid-trial, the display reverts all the same.

    property bool trying: false
    property int trySeconds: 0
    property string tryKey: ""
    property var tryFields: null

    signal tried(bool kept)

    function tryOut(key, fields) {
        if (root.trying || !root.loaded) return;
        root.problem = "";
        root.tryKey = key;
        root.tryFields = fields;
        trier.command = [root.tool, "preview", JSON.stringify(root.layout(key, fields))];
        trier.running = true;
    }

    function keep() {
        if (!root.trying) return;
        trier.write("keep\n");
    }

    function revert() {
        if (!root.trying) return;
        trier.write("no\n");
    }

    Timer {
        id: countdown
        interval: 1000
        repeat: true
        onTriggered: {
            root.trySeconds = Math.max(0, root.trySeconds - 1);
            if (root.trySeconds === 0) countdown.stop();
        }
    }

    Process {
        id: trier
        stdinEnabled: true
        stdout: SplitParser {
            onRead: function (line) {
                let msg = null;
                try { msg = JSON.parse(line); } catch (e) { return; }
                if (!msg) return;
                if (msg.event === "preview") {
                    root.trying = true;
                    root.trySeconds = Number(msg.seconds) || 20;
                    countdown.restart();
                    return;
                }
                if (msg.event === "kept") {
                    // Only what is confirmed gets saved. If the trial is
                    // undone, the file never learns it existed.
                    if (root.tryKey === "*") root.rememberMirror(!!(root.tryFields || ({})).mirror);
                    else if (root.tryKey) root.remember(root.tryKey, root.tryFields || ({}));
                    root.tried(true);
                    return;
                }
                if (msg.event === "reverted") { root.tried(false); return; }
                if (msg.event === "error") root.problem = I18n.tr(String(msg.message || ""));
            }
        }
        onExited: {
            root.trying = false;
            root.trySeconds = 0;
            countdown.stop();
            root.load();
        }
    }

    // ───────── never be left without a display ─────────
    //
    // Deliberately narrow: only if NONE is on are they all turned on. A display
    // that is off next to one that is on is left alone, because that is
    // exactly what closing the lid does.
    //
    // The case it covers: unplugging the external monitor takes you to another
    // set, maybe one you never arranged, and the panel you turned off under the
    // previous set stays off. Hyprland only knows how to fall back to displays
    // that are on, and with none there is no shell left to fix it from.
    function rescue() {
        if (!root.loaded || root.monitors.length === 0) return false;
        if (root.monitors.some(m => !m.disabled)) return false;
        const rules = root.monitors.map(m => ({
            output: m.name, disabled: false, mode: "preferred", position: "auto", scale: 1
        }));
        console.warn(I18n.tr("Displays: no hay ninguna pantalla encendida, se encienden todas."));
        settling.restart();
        applier.command = [root.tool, "apply", JSON.stringify(rules)];
        applier.running = true;
        return true;
    }

    // ───────── finding out ─────────
    //
    // Reloading the config returns the monitors to what hyprland.lua says, and
    // plugging or unplugging can change the set. In both cases: read again and
    // reconcile.
    Connections {
        target: Hyprland
        function onRawEvent(ev) {
            switch (ev.name) {
            case "configreloaded":
            case "monitoradded":
            case "monitoraddedv2":
            case "monitorremoved":
            case "monitorremovedv2":
                hotplug.restart();
                break;
            }
        }
    }

    // One read per burst of events.
    Timer { id: hotplug; interval: 250; onTriggered: root.load() }

    // The store changes when a display is dropped on the map and when the file
    // loads; in both cases a push is needed.
    readonly property var store: Config.displays
    onStoreChanged: soon.restart()

    Component.onCompleted: root.load()
}
