// Lyrics.qml — the lyrics of the current track, from LRCLIB (lrclib.net):
// synced (.lrc) when the song has them, plain text otherwise.
//
// Nothing goes out to the network until you ask: MediaPanel calls request()
// when you tap the cover art, and again on each track change while the lyrics
// are showing. Fetching in the background for every song played would send
// your whole listening history to a third party for lyrics nobody looked at,
// and the rice's rule is that the desktop does not depend on the network.
//
// What LRCLIB answered stays cached per track for the session, so going back
// and forth between the cover and the lyrics does not ask again.
pragma Singleton

import Quickshell
import QtQuick

Singleton {
    id: root

    readonly property var player: ShellState.player
    readonly property string title: player ? (player.trackTitle || "") : ""
    readonly property string artist: player ? (player.trackArtist || "") : ""
    readonly property string key: artist + "|" + title

    // key -> { lines: [{ time: seconds, text }], plain: "" }. An entry with
    // both empty means "asked, and LRCLIB has nothing for it".
    property var _cache: ({})
    // _cache is mutated in place, which notifies nobody: this counter does.
    property int _rev: 0
    property var _req: null
    property string _reqKey: ""

    readonly property var _entry: { root._rev; return root._cache[root.key]; }
    readonly property var lines: _entry ? _entry.lines : []
    readonly property string plain: _entry ? _entry.plain : ""
    readonly property bool synced: lines.length > 0
    readonly property bool hasLyrics: synced || plain !== ""
    // Asked and answered for THIS track (with or without lyrics).
    readonly property bool known: _entry !== undefined
    property bool loading: false
    // The last attempt for `failedKey` did not get an answer (no network,
    // LRCLIB down). Not cached, so the next request() tries again.
    property string failedKey: ""
    readonly property bool failed: failedKey !== "" && failedKey === key

    // Index of the line being sung right now (-1 before the first one).
    // ShellState.pos is refreshed every 500 ms while the notch is open.
    readonly property int current: indexAt(ShellState.pos)

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

    // Among the results, the synced ones first, and among those the one whose
    // duration is closest to the track's.
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

    // `now` for a tap, which asks at once. On a track change, title and artist
    // arrive one after the other: wait a moment, or the first request would go
    // out with the new title and the old artist.
    function request(now) {
        if (!root.title || root.known)
            return;
        if (now) {
            debounce.stop();
            root._fetch();
        } else {
            debounce.restart();
        }
    }
    Timer { id: debounce; interval: 400; onTriggered: root._fetch() }

    function _fetch() {
        if (!root.title || root.known)
            return;
        const k = root.key;
        if (root._req && root._reqKey === k)
            return;     // already on its way
        if (root._req) {
            // Forgotten BEFORE aborting: abort() fires its handler, and that
            // handler must not take the old track's silence for this one's.
            const viejo = root._req;
            root._req = null;
            viejo.abort();
        }
        root.loading = true;
        const xhr = new XMLHttpRequest();
        root._req = xhr;
        root._reqKey = k;
        xhr.onreadystatechange = function () {
            if (xhr.readyState !== XMLHttpRequest.DONE || xhr !== root._req)
                return;
            root._req = null;
            root.loading = false;
            let entry = null;
            if (xhr.status === 200) {
                try {
                    const best = root.pick(JSON.parse(xhr.responseText));
                    entry = {
                        lines: best && best.syncedLyrics ? root.parseLrc(best.syncedLyrics) : [],
                        plain: best ? (best.plainLyrics || "") : ""
                    };
                } catch (e) {}
            }
            if (entry) {
                root._cache[k] = entry;
                root._rev++;
                if (root.failedKey === k)
                    root.failedKey = "";
            } else {
                root.failedKey = k;
            }
        };
        xhr.open("GET", "https://lrclib.net/api/search?track_name="
            + encodeURIComponent(root.title) + "&artist_name=" + encodeURIComponent(root.artist));
        xhr.send();
    }
}
