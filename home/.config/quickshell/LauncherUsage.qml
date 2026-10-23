// ╭──────────────────────────────────────────────────────────────────────────╮
// │                                                                          │
// │   L A U N C H E R   S E R V I C E                                        │
// │   application index · search and activation                              │
// │                                                                          │
// │   github.com/andreumassanet/impasto                                      │
// │                                                                          │
// ╰──────────────────────────────────────────────────────────────────────────╯

// Launch history adapted from services/LauncherService.qml in Impasto.
// https://github.com/andreumassanet/impasto — Copyright 2026 Andreu Massanet.
// GPL-3.0. Counts decay with a 30-day half-life; only desktop entry IDs are kept.
pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root
    readonly property real halfLife: 30 * 24 * 3600 * 1000
    property var launches: ({})
    property bool ready: false
    property var pending: []
    readonly property int count: Object.keys(launches).length

    function clean(rows) {
        const out = {};
        if (!rows || typeof rows !== "object" || Array.isArray(rows)) return out;
        for (const id of Object.keys(rows).slice(0, 2000)) {
            const row = rows[id];
            if (id === "__proto__" || id === "constructor" || !row) continue;
            if (typeof row.count === "number" && isFinite(row.count) && row.count > 0
                && typeof row.last === "number" && isFinite(row.last) && row.last > 0)
                out[id] = { count: Math.min(row.count, 10000), last: Math.min(row.last, Date.now()) };
        }
        return out;
    }
    function scoreOf(id) {
        const row = root.launches[id];
        if (!row || !row.count) return 0;
        return row.count * Math.pow(0.5, Math.max(0, Date.now() - row.last) / root.halfLife);
    }
    function record(id) {
        if (!id || id === "__proto__" || id === "constructor") return;
        if (!root.ready) { root.pending = root.pending.concat([id]); return; }
        const next = Object.assign({}, root.launches);
        next[id] = { count: root.scoreOf(id) + 1, last: Date.now() };
        root.launches = root.clean(next);
        history.launches = root.launches;
        saver.restart();
    }
    function clear() {
        root.launches = ({});
        history.launches = ({});
        saver.restart();
    }
    function finishLoading(rows) {
        root.launches = root.clean(rows);
        root.ready = true;
        const waiting = root.pending;
        root.pending = [];
        for (const id of waiting) root.record(id);
    }
    Timer { id: saver; interval: 0; onTriggered: historyFile.writeAdapter() }
    FileView {
        id: historyFile
        // Outside the watched shell directory; writes must not reload the shell.
        path: Quickshell.env("HOME") + "/.config/quickshell-launch-history.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.finishLoading(history.launches)
        onLoadFailed: function (error) {
            if (error === FileViewError.FileNotFound) root.finishLoading({});
        }
        JsonAdapter { id: history; property var launches: ({}) }
    }
}
