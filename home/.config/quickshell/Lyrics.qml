// Lyrics.qml — lyrics for the current track, fetched from LRCLIB (lrclib.net).
// Synced (.lrc) lyrics when available, plain text otherwise.
pragma Singleton

import Quickshell
import QtQuick

Singleton {
    id: root

    readonly property var player: ShellState.player
    readonly property string title: player ? (player.trackTitle || "") : ""
    readonly property string artist: player ? (player.trackArtist || "") : ""

    property var lines: []          // [{ time: seconds, text: "..." }]
    property string plain: ""
    property bool loading: false
    readonly property bool synced: lines.length > 0
    readonly property bool hasLyrics: synced || plain !== ""
    // Index of the line being sung right now (-1 before the first one).
    readonly property int current: indexAt(ShellState.pos)

    property var _cache: ({})
    property var _req: null

    // Title and artist change one after the other: wait a moment.
    onTitleChanged: debounce.restart()
    onArtistChanged: debounce.restart()
    Timer { id: debounce; interval: 400; onTriggered: root.fetchLyrics() }

    function indexAt(pos) {
        let idx = -1;
        for (let i = 0; i < lines.length; i++) {
            if (lines[i].time <= pos) idx = i; else break;
        }
        return idx;
    }

    function parseLrc(text) {
        const out = [], re = /^\[(\d+):(\d+(?:\.\d+)?)\]\s*(.*)$/;
        text.split("\n").forEach(function (l) {
            const m = re.exec(l.trim());
            if (m) out.push({ time: parseInt(m[1]) * 60 + parseFloat(m[2]), text: m[3] });
        });
        return out;
    }

    // Among the results, prefer synced ones whose duration is closest to ours.
    function pick(arr) {
        let best = null, bestScore = -1e9;
        for (const r of arr) {
            if (r.instrumental) continue;
            const d = ShellState.len > 0 ? Math.abs((r.duration || 0) - ShellState.len) : 0;
            const s = (r.syncedLyrics ? 100 : 0) - d;
            if (s > bestScore) { best = r; bestScore = s; }
        }
        return best;
    }

    function apply(d) {
        lines = d.synced ? parseLrc(d.synced) : [];
        plain = d.plain || "";
    }

    function fetchLyrics() {
        lines = []; plain = "";
        if (!title) return;

        const k = artist + "|" + title;
        if (_cache[k]) { apply(_cache[k]); return; }

        if (_req) _req.abort();
        loading = true;
        const xhr = new XMLHttpRequest();
        _req = xhr;
        xhr.onreadystatechange = function () {
            if (xhr.readyState !== XMLHttpRequest.DONE || xhr !== root._req) return;
            root.loading = false;
            if (xhr.status !== 200) return;
            try {
                const best = root.pick(JSON.parse(xhr.responseText));
                if (!best) return;
                const d = { synced: best.syncedLyrics || "", plain: best.plainLyrics || "" };
                root._cache[k] = d;
                root.apply(d);
            } catch (e) {}
        };
        xhr.open("GET", "https://lrclib.net/api/search?track_name="
            + encodeURIComponent(title) + "&artist_name=" + encodeURIComponent(artist));
        xhr.send();
    }
}