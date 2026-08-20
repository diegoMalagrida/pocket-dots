// termspot theme.js — ASCII album art, ASCII progress bar, track-load log,
// monochrome phosphor covers, live CRT settings and a hidden command terminal.
// Press ":" anywhere (outside a text field) to open the terminal. Try `help`.
(function termspot() {
    if (
        !(
            window.Spicetify &&
            Spicetify.React &&
            Spicetify.ReactJSX &&
            Spicetify.Player &&
            Spicetify.Menu &&
            Spicetify.PopupModal
        )
    ) {
        setTimeout(termspot, 400);
        return;
    }

    /* ---- settings ---------------------------------------------------- */
    const STORAGE_KEY = "termspot:settings";
    const DEFAULTS = {
        ascii: true, // ASCII album art in the now playing view
        mono: true, // monochrome phosphor covers (hover restores color)
        asciiProgress: true, // [████░░░░] progress bar
        trackLog: true, // "reading: track.dat" toast on song change
        compact: false, // denser type for ls-style lists
        scanlines: true,
        vignette: true,
        poweron: true,
    };
    function loadSettings() {
        try {
            return { ...DEFAULTS, ...JSON.parse(window.localStorage.getItem(STORAGE_KEY) || "{}") };
        } catch (e) {
            return { ...DEFAULTS };
        }
    }
    function saveSettings(s) {
        try {
            window.localStorage.setItem(STORAGE_KEY, JSON.stringify(s));
        } catch (e) {
            /* keep in-memory */
        }
    }
    let settings = loadSettings();

    function applyCrtKnobs() {
        const root = document.documentElement.style;
        root.setProperty("--crt-scanlines", settings.scanlines ? "block" : "none");
        root.setProperty("--crt-vignette", settings.vignette ? "block" : "none");
        root.setProperty(
            "--crt-poweron",
            settings.poweron ? "termspot-power-on 0.9s ease-out 1" : "none"
        );
        document.body.classList.toggle("termspot-mono", settings.mono);
        document.body.classList.toggle("termspot-aprog", settings.asciiProgress);
        if (settings.compact) {
            root.setProperty("--font-size", "12px");
            root.setProperty("--line-height", "1.15");
        } else {
            root.removeProperty("--font-size");
            root.removeProperty("--line-height");
        }
    }

    /* ---- listening stats (per day, local only) ---- */
    const STATS_KEY = "termspot:stats";
    const todayKey = () => new Date().toISOString().slice(0, 10);
    function loadStats() {
        try {
            const s = JSON.parse(window.localStorage.getItem(STATS_KEY) || "{}");
            if (s.day === todayKey() && s.plays) return s;
        } catch (e) {
            /* fresh start */
        }
        return { day: todayKey(), sec: 0, plays: {} };
    }
    let stats = loadStats();
    function saveStats() {
        try {
            window.localStorage.setItem(STATS_KEY, JSON.stringify(stats));
        } catch (e) {
            /* storage unavailable */
        }
    }
    setInterval(() => {
        try {
            if (!Spicetify.Player.isPlaying()) return;
            if (stats.day !== todayKey()) stats = loadStats();
            stats.sec += 5;
            if (stats.sec % 15 === 0) saveStats();
        } catch (e) {
            /* player not ready */
        }
    }, 5000);

    /* ---- color schemes (for the `theme` command; session-only preview) ---- */
    const SPICE_KEYS = [
        "accent", "accent-active", "accent-inactive", "banner", "border-active",
        "border-inactive", "header", "highlight", "main", "notification",
        "notification-error", "subtext", "text",
    ];
    const SCHEMES = {
        Fdeox: ["2ee66b","58ff8f","0b0f0c","58ff8f","2ee66b","1e3327","3f5c4a","142119","0b0f0c","4aa3df","ff5555","8fbf9f","d2f0d8"],
        FdeoxAmber: ["e69500","ffb000","0f0b06","ffb000","e69500","332609","5c4a1f","211a0c","0f0b06","4aa3df","ff5555","bf9f6f","f0e0c2"],
        Synthwave: ["f92aad","ff6ac1","120b1e","ff6ac1","f92aad","2a1f47","6f5a9e","1e1433","120b1e","36f9f6","ff5555","9a8fbf","e8e3ff"],
        Arctic: ["2ec9ff","6fe3ff","0a1220","6fe3ff","2ec9ff","1a2c47","3f5c7a","12203a","0a1220","5e81ac","ff5c5c","7fa3bf","d8ecf7"],
        Bloodmoon: ["d43f3f","ff5c5c","120808","ff5c5c","d43f3f","331414","5c2f2f","211010","120808","4aa3df","ffb000","bf8f8f","f0d8d8"],
        Ultraviolet: ["8b5cf6","a78bfa","0e0a1a","a78bfa","8b5cf6","241a47","5a4a8f","191033","0e0a1a","4aa3df","ff5555","9a8fbf","e6ddff"],
        Paper: ["1b7a4a","0f5c38","f2ede4","1b7a4a","1b7a4a","d8cfc0","8a8070","e4dccc","f2ede4","286983","b4637a","6f675c","3b3630"],
        Matrix: ["00e63a","00ff41","050805","00ff41","00e63a","0f2913","2e5c38","0c1a0e","050805","4aa3df","ff3333","5c9e6b","c8facc"],
        Gold: ["d4af37","ffd700","0d0b06","ffd700","d4af37","33290f","5c521f","211c0c","0d0b06","4aa3df","ff5555","bfab6f","f0e8c2"],
        Frostbyte: ["88c0d0","8fbcbb","2e3440","8fbcbb","8fbcbb","3b4252","4c566a","4c566a","2e3440","5e81ac","bf616a","d8dee9","eceff4"],
        Nightbloom: ["cba6f7","cba6f7","1e1e2e","cba6f7","cba6f7","313244","585b70","585b70","1e1e2e","89b4fa","f38ba8","a6adc8","cdd6f4"],
        Fangs: ["50fa7b","50fa7b","282a36","50fa7b","50fa7b","44475a","44475a","44475a","282a36","8be9fd","ff5555","6272a4","f8f8f2"],
        Bios: ["ffd24d","ffe680","0a1550","ffe680","ffd24d","22337f","5566b3","132575","0a1550","66ccff","ff5555","9fb0e6","e6ecff"],
        Gruvbox: ["98971a","b8bb26","282828","b8bb26","b8bb26","3c3836","665c54","7c6f64","282828","458588","cc241d","bdae93","fbf1c7"],
        GruvboxHard: ["98971a","b8bb26","1d2021","b8bb26","b8bb26","3c3836","665c54","7c6f64","1d2021","458588","cc241d","bdae93","ebdbb2"],
        EverforestDarkHard: ["a7c080","a7c080","272e33","a7c080","a7c080","2e383c","414b50","3c4841","272e33","83c092","e67e80","859289","d3c6aa"],
        EverforestDarkMedium: ["a7c080","a7c080","2d353b","a7c080","a7c080","343f44","475258","425047","2d353b","83c092","e67e80","859289","d3c6aa"],
        EverforestDarkSoft: ["a7c080","a7c080","333c43","a7c080","a7c080","3a464c","4d5960","48584E","333c43","83c092","e67e80","859289","d3c6aa"],
    };
    SCHEMES.CatppuccinMocha = SCHEMES.Nightbloom; // alias, by popular demand (issue #1)
    const hexRgb = (h) =>
        [h.slice(0, 2), h.slice(2, 4), h.slice(4, 6)].map((x) => parseInt(x, 16)).join(",");

    function applyScheme(name) {
        const key = Object.keys(SCHEMES).find((k) => k.toLowerCase() === String(name).toLowerCase());
        if (!key) return null;
        const vals = SCHEMES[key];
        const r = document.documentElement.style;
        SPICE_KEYS.forEach((k, i) => {
            r.setProperty("--spice-" + k, "#" + vals[i]);
            r.setProperty("--spice-rgb-" + k, hexRgb(vals[i]));
        });
        const accent = vals[0], active = vals[1];
        r.setProperty("--spice-button", "#" + accent);
        r.setProperty("--spice-button-active", "#" + active);
        r.setProperty("--spice-rgb-button", hexRgb(accent));
        r.setProperty("--spice-rgb-button-active", hexRgb(active));
        return key;
    }
    function resetScheme() {
        const r = document.documentElement.style;
        SPICE_KEYS.forEach((k) => {
            r.removeProperty("--spice-" + k);
            r.removeProperty("--spice-rgb-" + k);
        });
        ["button", "button-active"].forEach((k) => {
            r.removeProperty("--spice-" + k);
            r.removeProperty("--spice-rgb-" + k);
        });
    }

    /* ---- shared css ---------------------------------------------------- */
    // note: the now-playing sidebar cover is deliberately NOT in this list —
    // that spot belongs to the ASCII art
    const COVERS =
        "img.main-image-image:not(.main-nowPlayingView-coverArt img)," +
        " .main-cardImage-image, .view-homeShortcutsGrid-imageContainer img," +
        " .main-trackList-rowImage, .main-coverSlotCollapsed-container img," +
        " .main-nowPlayingWidget-coverArt img, .x-entityImage-image," +
        " .main-entityHeader-image";

    const style = document.createElement("style");
    style.id = "termspot-js-style";
    style.textContent = [
        // ascii art: the hidden img keeps the cover box's size, the pre overlays it
        ".termspot-ascii-on .main-nowPlayingView-coverArt img { visibility: hidden !important; }",
        // spotify's placeholder note icon peeks out from under the hidden img
        ".termspot-ascii-on .main-nowPlayingView-coverArt .cover-art-icon { visibility: hidden !important; }",
        ".termspot-ascii-on .main-nowPlayingView-coverArt { position: relative; }",
        "#termspot-ascii {",
        "  position: absolute; inset: 0; z-index: 2;",
        "  display: flex; align-items: center; justify-content: center;",
        '  font-family: "JetBrains Mono", "Cascadia Mono", Consolas, monospace !important;',
        "  font-size: 10px !important; line-height: 10px !important; letter-spacing: 0;",
        "  color: var(--spice-accent-active); white-space: pre;",
        "  text-shadow: 0 0 4px currentColor; user-select: none;",
        "  overflow: hidden; pointer-events: none;",
        "  transition: opacity 0.2s ease;",
        "}",
        // hovering the ascii art reveals the original cover underneath
        ".termspot-ascii-on .main-nowPlayingView-coverArt:hover img { visibility: visible !important; }",
        ".termspot-ascii-on .main-nowPlayingView-coverArt:hover #termspot-ascii { opacity: 0; }",
        // monochrome phosphor covers, hover restores the original colors
        // (hover must sit on the clickable container: overlays swallow img:hover)
        // the filter itself follows the active accent — see updateMonoFilter()
        ".termspot-mono :is(" + COVERS + ") {",
        "  filter: var(--termspot-mono-filter, grayscale(1) sepia(1) hue-rotate(80deg) brightness(0.8));",
        "  transition: filter 0.25s ease;",
        "}",
        ".termspot-mono :is(" + COVERS + "):hover,",
        ".termspot-mono .termspot-reveal :is(" + COVERS + "),",
        ".termspot-mono :is(a, button, [role=\"button\"], .main-card-card, .main-trackList-trackListRow, .view-homeShortcutsGrid-imageContainer):hover :is(" + COVERS + ") {",
        "  filter: none;",
        "}",
        // ascii progress bar: hide the real bar's paint, keep its hit area
        '.termspot-aprog .playback-bar [data-testid="progress-bar"] { opacity: 0 !important; }',
        "#termspot-progress {",
        "  position: absolute; inset: 0; z-index: 5;",
        "  display: flex; align-items: center; justify-content: center;",
        '  font-family: "JetBrains Mono", "Cascadia Mono", Consolas, monospace !important;',
        "  font-size: 13px !important; line-height: 1 !important;",
        "  color: var(--spice-accent-active); white-space: pre;",
        "  text-shadow: 0 0 var(--crt-glow, 6px) currentColor;",
        "  pointer-events: none; user-select: none;",
        "}",
        // track load log
        "#termspot-tracklog {",
        "  position: fixed; left: 18px; bottom: 118px; z-index: 9998;",
        '  font-family: "JetBrains Mono", "Cascadia Mono", Consolas, monospace !important;',
        "  font-size: 12px !important; line-height: 1.5 !important;",
        "  color: var(--spice-accent-active); white-space: pre;",
        "  text-shadow: 0 0 4px currentColor; pointer-events: none; user-select: none;",
        "  background: rgba(var(--spice-rgb-main), 0.85); padding: 8px 12px;",
        "  border: 1px solid var(--spice-border-inactive);",
        "  transition: opacity 0.4s ease;",
        "}",
        // hidden command terminal
        "#termspot-terminal {",
        "  position: fixed; left: 50%; top: 10%; transform: translateX(-50%);",
        "  width: min(680px, 92vw); z-index: 100000;",
        "  background: rgba(var(--spice-rgb-main), 0.97);",
        "  border: 1px solid var(--spice-border-active);",
        "  box-shadow: 0 0 24px -6px var(--spice-border-active);",
        '  font-family: "JetBrains Mono", "Cascadia Mono", Consolas, monospace !important;',
        "  font-size: 13px !important; color: var(--spice-text);",
        "  display: none; flex-direction: column;",
        "}",
        "#termspot-terminal .t-out {",
        "  padding: 12px 14px 4px; max-height: 50vh; overflow-y: auto;",
        "  white-space: pre-wrap; line-height: 1.5 !important;",
        "}",
        "#termspot-terminal .t-dim { color: var(--spice-subtext); }",
        "#termspot-terminal .t-acc { color: var(--spice-accent-active); text-shadow: 0 0 4px currentColor; }",
        "#termspot-terminal .t-row {",
        "  display: flex; gap: 8px; padding: 6px 14px 12px; align-items: center;",
        "}",
        "#termspot-terminal .t-prompt { color: var(--spice-accent-active); text-shadow: 0 0 4px currentColor; }",
        "#termspot-terminal input {",
        "  flex: 1; background: transparent; border: none; outline: none;",
        "  color: var(--spice-text); font: inherit; caret-color: var(--spice-accent-active);",
        "}",
    ].join("\n");
    document.head.appendChild(style);

    /* ---- scheme-aware mono filter --------------------------------------- */
    // sepia lands around a 40deg amber hue; rotate from there to the accent's
    // hue so Synthwave tints pink, Gold tints gold, Fdeox stays phosphor green
    let lastAccent = "";
    function updateMonoFilter() {
        const accent = getComputedStyle(document.documentElement)
            .getPropertyValue("--spice-accent-active")
            .trim();
        if (!accent || accent === lastAccent) return;
        lastAccent = accent;
        let r, g, b;
        if (accent.startsWith("#")) {
            const h = accent.slice(1);
            const f = h.length === 3 ? h.split("").map((c) => c + c).join("") : h;
            r = parseInt(f.slice(0, 2), 16);
            g = parseInt(f.slice(2, 4), 16);
            b = parseInt(f.slice(4, 6), 16);
        } else {
            const m = accent.match(/\d+/g);
            if (!m || m.length < 3) return;
            r = +m[0]; g = +m[1]; b = +m[2];
        }
        const max = Math.max(r, g, b);
        const min = Math.min(r, g, b);
        let hue = 0;
        if (max !== min) {
            const d = max - min;
            if (max === r) hue = ((g - b) / d) % 6;
            else if (max === g) hue = (b - r) / d + 2;
            else hue = (r - g) / d + 4;
            hue = Math.round(hue * 60);
            if (hue < 0) hue += 360;
        }
        const sat = max === 0 ? 0 : (max - min) / max;
        document.documentElement.style.setProperty(
            "--termspot-mono-filter",
            "grayscale(1) sepia(1) hue-rotate(" + (hue - 40) + "deg) saturate(" +
                (0.6 + sat).toFixed(2) + ") brightness(0.8)"
        );
    }

    /* ---- ascii album art ------------------------------------------------ */
    const RAMP = " .'-:=+*#%@";
    const W = 60;
    const H = 34;
    let lastKey = "";
    let rendering = false;

    function currentItem() {
        try {
            return Spicetify.Player.data && (Spicetify.Player.data.item || Spicetify.Player.data.track);
        } catch (e) {
            return null;
        }
    }

    function coverUrl() {
        const item = currentItem();
        const meta = item && item.metadata;
        const raw = meta && (meta.image_url || meta.image_xlarge_url);
        if (!raw) return null;
        return raw.startsWith("spotify:image:")
            ? "https://i.scdn.co/image/" + raw.slice("spotify:image:".length)
            : raw;
    }

    async function toAscii(url) {
        const blob = await (await fetch(url)).blob();
        const bmp = await createImageBitmap(blob, { resizeWidth: W, resizeHeight: H });
        const cv = document.createElement("canvas");
        cv.width = W;
        cv.height = H;
        const ctx = cv.getContext("2d");
        ctx.drawImage(bmp, 0, 0, W, H);
        const d = ctx.getImageData(0, 0, W, H).data;
        let out = "";
        for (let y = 0; y < H; y++) {
            for (let x = 0; x < W; x++) {
                const i = (y * W + x) * 4;
                const lum = 0.2126 * d[i] + 0.7152 * d[i + 1] + 0.0722 * d[i + 2];
                out += RAMP[Math.min(RAMP.length - 1, ((lum / 256) * RAMP.length) | 0)];
            }
            out += "\n";
        }
        return out;
    }

    async function renderAscii() {
        if (rendering) return;
        const pre = document.getElementById("termspot-ascii");
        if (!settings.ascii) {
            if (pre) pre.remove();
            document.body.classList.remove("termspot-ascii-on");
            lastKey = "";
            return;
        }
        document.body.classList.add("termspot-ascii-on");

        const host = document.querySelector(".main-nowPlayingView-coverArt");
        const url = coverUrl();
        if (!host || !url) return;
        if (pre && url === lastKey && host.contains(pre)) return;

        rendering = true;
        try {
            const art = await toAscii(url);
            let target = document.getElementById("termspot-ascii");
            if (!target || !host.contains(target)) {
                if (target) target.remove();
                target = document.createElement("pre");
                target.id = "termspot-ascii";
                host.prepend(target);
            }
            target.textContent = art;
            lastKey = url;
        } catch (e) {
            /* cover fetch failed; try again on the next pass */
        } finally {
            rendering = false;
        }
    }

    /* ---- ascii progress bar ---------------------------------------------- */
    function renderProgress() {
        let el = document.getElementById("termspot-progress");
        if (!settings.asciiProgress) {
            if (el) el.remove();
            return;
        }
        const bar = document.querySelector('.playback-bar [data-testid="progress-bar"]');
        if (!bar) return;
        const host = bar.parentElement;
        if (!host) return;
        if (!el || el.parentElement !== host) {
            if (el) el.remove();
            host.style.position = "relative";
            el = document.createElement("div");
            el.id = "termspot-progress";
            host.appendChild(el);
        }
        // fill the whole gap between the time displays
        const cells = Math.max(24, Math.min(90, Math.floor((host.clientWidth || 300) / 7.9) - 2));
        let frac = 0;
        try {
            const dur = Spicetify.Player.getDuration();
            frac = dur ? Spicetify.Player.getProgress() / dur : 0;
        } catch (e) {
            frac = 0;
        }
        const filled = Math.round(Math.max(0, Math.min(1, frac)) * cells);
        el.textContent = "[" + "█".repeat(filled) + "░".repeat(cells - filled) + "]";
    }

    /* ---- track load log ----------------------------------------------------- */
    let logTimers = [];

    function showTrackLog() {
        if (!settings.trackLog) return;
        const item = currentItem();
        const meta = item && item.metadata;
        if (!meta || !meta.title) return;

        logTimers.forEach(clearTimeout);
        logTimers = [];
        document.getElementById("termspot-tracklog")?.remove();

        const fname =
            meta.title.toLowerCase().replace(/[^a-z0-9]+/g, "_").replace(/^_+|_+$/g, "").slice(0, 24) ||
            "track";
        const durSec = (((item && item.duration && item.duration.milliseconds) || 194000) / 1000) | 0;
        const LINES = [
            "reading: " + fname + "_" + durSec + ".dat ........ OK",
            "artist metadata loaded",
            "album artwork rendered",
        ];

        const box = document.createElement("div");
        box.id = "termspot-tracklog";
        document.body.appendChild(box);

        LINES.forEach((line, i) => {
            logTimers.push(
                setTimeout(() => {
                    box.appendChild(document.createTextNode(line + "\n"));
                }, 140 * (i + 1))
            );
        });
        logTimers.push(setTimeout(() => (box.style.opacity = "0"), 4500));
        logTimers.push(setTimeout(() => box.remove(), 5000));
    }

    /* ---- matrix rain ----------------------------------------------------------- */
    function startMatrix() {
        if (document.getElementById("termspot-matrix")) return;
        const cv = document.createElement("canvas");
        cv.id = "termspot-matrix";
        cv.style.cssText =
            "position:fixed;inset:0;z-index:100001;background:rgba(0,0,0,0.88);cursor:pointer;";
        document.body.appendChild(cv);
        cv.width = window.innerWidth;
        cv.height = window.innerHeight;
        const ctx = cv.getContext("2d");
        const CHARS = "アィウエオカキクケコサシスセソタチツテトナニヌネノ0123456789ABCDEF#$%*+";
        const fs = 16;
        const cols = Math.ceil(cv.width / fs);
        const drops = Array.from({ length: cols }, () => (Math.random() * -60) | 0);
        const accent =
            getComputedStyle(document.documentElement).getPropertyValue("--spice-accent-active").trim() ||
            "#58ff8f";
        const timer = setInterval(() => {
            ctx.fillStyle = "rgba(0,0,0,0.08)";
            ctx.fillRect(0, 0, cv.width, cv.height);
            ctx.fillStyle = accent;
            ctx.font = fs + "px monospace";
            for (let i = 0; i < cols; i++) {
                const ch = CHARS[(Math.random() * CHARS.length) | 0];
                ctx.fillText(ch, i * fs, drops[i] * fs);
                drops[i] = drops[i] * fs > cv.height && Math.random() > 0.975 ? 0 : drops[i] + 1;
            }
        }, 50);
        const stop = (e) => {
            e && e.preventDefault();
            clearInterval(timer);
            cv.remove();
            document.removeEventListener("keydown", stop, true);
        };
        cv.addEventListener("click", stop);
        document.addEventListener("keydown", stop, true);
    }

    /* ---- hidden command terminal ------------------------------------------------ */
    let termEl = null;
    let termOut = null;
    let termIn = null;

    function tprint(text, cls) {
        const line = document.createElement("div");
        if (cls) line.className = cls;
        line.textContent = text;
        termOut.appendChild(line);
        termOut.scrollTop = termOut.scrollHeight;
    }

    function toggleSetting(key, label) {
        settings[key] = !settings[key];
        saveSettings(settings);
        applyCrtKnobs();
        renderAscii();
        renderProgress();
        tprint(label + ": " + (settings[key] ? "on" : "off"), "t-acc");
    }

    /* music control helpers */
    let lastResults = [];

    async function searchTracks(q) {
        // 1) the client's own search query — works on all modern builds
        try {
            const r = await Spicetify.GraphQL.Request(
                Spicetify.GraphQL.Definitions.searchModalResults,
                {
                    searchTerm: q,
                    offset: 0,
                    limit: 10,
                    numberOfTopResults: 10,
                    includeAudiobooks: false,
                    includePreReleases: false,
                    includeArtistHasConcertsField: false,
                    includeLocalConcertsField: false,
                    includeAuthors: false,
                }
            );
            const raw = [];
            (function walk(n) {
                if (!n || typeof n !== "object") return;
                if (n.__typename === "TrackResponseWrapper" && n.data && n.data.uri) {
                    raw.push(n.data);
                    return;
                }
                Object.values(n).forEach(walk);
            })(r);
            if (raw.length) {
                return raw.slice(0, 5).map((d) => ({
                    name: d.name,
                    uri: d.uri,
                    artists: ((d.artists && d.artists.items) || []).map((a) => ({
                        name: (a.profile && a.profile.name) || "?",
                    })),
                    duration_ms: d.duration && d.duration.totalMilliseconds,
                }));
            }
        } catch (e) {
            /* fall through to the web api */
        }
        // 2) web api with the session token (older builds)
        const url =
            "https://api.spotify.com/v1/search?q=" + encodeURIComponent(q) + "&type=track&limit=5";
        const token =
            Spicetify.Platform && Spicetify.Platform.Session && Spicetify.Platform.Session.accessToken;
        if (token) {
            try {
                const r = await fetch(url, { headers: { Authorization: "Bearer " + token } });
                if (r.ok) {
                    const j = await r.json();
                    return (j.tracks && j.tracks.items) || [];
                }
            } catch (e) {
                /* fall through to cosmos */
            }
        }
        const r2 = await Spicetify.CosmosAsync.get(url);
        if (r2 && r2.tracks) return r2.tracks.items || [];
        throw new Error((r2 && r2.message) || "search backend unavailable");
    }

    const fmtTrack = (t) => {
        let s = t.name + " — " + (t.artists || []).map((a) => a.name).join(", ");
        if (t.duration_ms) {
            s +=
                " (" + Math.floor(t.duration_ms / 60000) + ":" +
                String(Math.floor((t.duration_ms % 60000) / 1000)).padStart(2, "0") + ")";
        }
        return s;
    };

    async function pickTrack(arg) {
        const n = parseInt(arg, 10);
        if (!isNaN(n) && String(n) === arg.trim() && lastResults[n - 1]) return lastResults[n - 1];
        const items = await searchTracks(arg);
        if (items.length) lastResults = items;
        return items[0] || null;
    }

    async function exec(raw) {
        const parts = raw.trim().split(/\s+/);
        const cmd = (parts[0] || "").toLowerCase();
        const arg = parts.slice(1).join(" ");
        if (!cmd) return;
        tprint(":" + raw, "t-dim");

        switch (cmd) {
            case "help":
                tprint(
                    [
                        "music:",
                        "  play <song>   search and play (play 2 = 2nd result, play = resume)",
                        "  search <q>    list top 5 matches",
                        "  queue <song>  add to the queue",
                        "  pause / next / prev",
                        "  vol <0-100>   set volume",
                        "  np            now playing",
                        "  lyrics        current track's lyrics, >> marks the live line",
                        "  stats         today's listening stats",
                        "  cowsay [text] the cow announces the current track",
                        "  shuffle       toggle shuffle",
                        "terminal:",
                        "  theme <name>  live-preview a scheme (theme list | theme reset)",
                        "  ascii / mono / progress / log / scanlines / vignette / compact",
                        "  matrix        follow the white rabbit (click/key to exit)",
                        "  about / coffee / 1994",
                        "  clear / exit  (Esc also closes)",
                        "  quit          shut Spotify down entirely",
                    ].join("\n")
                );
                break;
            case "play":
                if (!arg) {
                    try { Spicetify.Player.play(); tprint("resumed", "t-acc"); } catch (e) { tprint("could not resume", "t-dim"); }
                    break;
                }
                try {
                    const t = await pickTrack(arg);
                    if (!t) { tprint("no match for: " + arg, "t-dim"); break; }
                    Spicetify.Player.playUri(t.uri);
                    tprint("playing: " + fmtTrack(t), "t-acc");
                } catch (e) {
                    tprint("play failed: " + (e.message || e), "t-dim");
                }
                break;
            case "search":
            case "find":
                if (!arg) { tprint("usage: search <query>", "t-dim"); break; }
                try {
                    lastResults = await searchTracks(arg);
                    if (!lastResults.length) { tprint("no results", "t-dim"); break; }
                    lastResults.forEach((t, i) => tprint("  " + (i + 1) + ". " + fmtTrack(t)));
                    tprint("play <n> plays a result", "t-dim");
                } catch (e) {
                    tprint("search failed: " + (e.message || e), "t-dim");
                }
                break;
            case "queue":
                if (!arg) { tprint("usage: queue <song>", "t-dim"); break; }
                try {
                    const t = await pickTrack(arg);
                    if (!t) { tprint("no match for: " + arg, "t-dim"); break; }
                    await Spicetify.addToQueue([{ uri: t.uri }]);
                    tprint("queued: " + fmtTrack(t), "t-acc");
                } catch (e) {
                    tprint("queue failed: " + (e.message || e), "t-dim");
                }
                break;
            case "pause":
                try { Spicetify.Player.pause(); tprint("paused", "t-acc"); } catch (e) { tprint("could not pause", "t-dim"); }
                break;
            case "next":
                try { Spicetify.Player.next(); tprint("skipped", "t-acc"); } catch (e) { tprint("could not skip", "t-dim"); }
                break;
            case "prev":
                try { Spicetify.Player.back(); tprint("went back", "t-acc"); } catch (e) { tprint("could not go back", "t-dim"); }
                break;
            case "vol": {
                const v = parseInt(arg, 10);
                if (isNaN(v) || v < 0 || v > 100) { tprint("usage: vol <0-100>", "t-dim"); break; }
                try { Spicetify.Player.setVolume(v / 100); tprint("volume: " + v + "%", "t-acc"); } catch (e) { tprint("could not set volume", "t-dim"); }
                break;
            }
            case "np": {
                const item = currentItem();
                const meta = item && item.metadata;
                if (!meta || !meta.title) { tprint("nothing playing", "t-dim"); break; }
                tprint("now playing: " + meta.title + (meta.artist_name ? " — " + meta.artist_name : ""), "t-acc");
                break;
            }
            case "shuffle":
                try {
                    Spicetify.Player.toggleShuffle();
                    tprint("shuffle toggled", "t-acc");
                } catch (e) {
                    tprint("could not toggle shuffle", "t-dim");
                }
                break;
            case "lyrics": {
                const item = currentItem();
                const tid = item && item.uri && (item.uri.match(/track:([A-Za-z0-9]+)/) || [])[1];
                if (!tid) {
                    tprint("nothing playing", "t-dim");
                    break;
                }
                try {
                    const r = await Spicetify.CosmosAsync.get(
                        "https://spclient.wg.spotify.com/color-lyrics/v2/track/" + tid +
                            "?format=json&vocalRemoval=false&market=from_token"
                    );
                    const lines = r && r.lyrics && r.lyrics.lines;
                    if (!lines || !lines.length) {
                        tprint("no lyrics for this track", "t-dim");
                        break;
                    }
                    const synced = lines.some((l) => +l.startTimeMs > 0);
                    let prog = 0;
                    try {
                        prog = Spicetify.Player.getProgress();
                    } catch (e) {
                        /* unsynced view */
                    }
                    let liveIdx = -1;
                    if (synced) {
                        for (let i = 0; i < lines.length; i++) {
                            if (+lines[i].startTimeMs <= prog) liveIdx = i;
                        }
                    }
                    tprint("lyrics: " + ((item.metadata && item.metadata.title) || ""), "t-acc");
                    lines.forEach((l, i) => {
                        if (!l.words || !l.words.trim() || l.words === "♪") return;
                        tprint((i === liveIdx ? ">> " : "   ") + l.words, i === liveIdx ? "t-acc" : undefined);
                    });
                } catch (e) {
                    tprint("no lyrics for this track", "t-dim");
                }
                break;
            }
            case "stats": {
                const hh = (stats.sec / 3600) | 0;
                const mm = ((stats.sec % 3600) / 60) | 0;
                tprint("today: " + (hh ? hh + "h " : "") + mm + "m of music", "t-acc");
                const top = Object.entries(stats.plays).sort((a, b) => b[1] - a[1]).slice(0, 5);
                if (!top.length) {
                    tprint("no plays logged yet today — go press play", "t-dim");
                    break;
                }
                const max = top[0][1];
                top.forEach(([title, count]) => {
                    const bar = "█".repeat(Math.max(1, Math.round((count / max) * 12)));
                    tprint("  " + bar.padEnd(13) + count + "x  " + title.slice(0, 42));
                });
                break;
            }
            case "cowsay": {
                let text = arg;
                if (!text) {
                    const meta = currentItem() && currentItem().metadata;
                    text = meta && meta.title ? meta.title + " — " + (meta.artist_name || "") : "moo";
                }
                text = text.slice(0, 44);
                const border = "-".repeat(text.length + 2);
                tprint(
                    " " + border + "\n< " + text + " >\n " + border +
                        "\n        \\   ^__^\n         \\  (oo)\\_______\n            (__)\\       )\\/\\\n                ||----w |\n                ||     ||",
                    "t-acc"
                );
                break;
            }
            case "compact":
                toggleSetting("compact", "compact mode");
                break;
            case "clear":
                termOut.textContent = "";
                break;
            case "exit":
                closeTerminal();
                break;
            case "quit":
                tprint("stopping playback daemon...", "t-dim");
                tprint("unmounting ~/music...", "t-dim");
                tprint("spotifyOS halted. goodbye.", "t-acc");
                setTimeout(() => {
                    try {
                        Spicetify.Platform.LifecycleAPI.shutdown();
                    } catch (e) {
                        tprint("could not shut down (LifecycleAPI missing)", "t-dim");
                    }
                }, 900);
                break;
            case "matrix":
                closeTerminal();
                startMatrix();
                break;
            case "theme":
                if (!arg || arg === "list") {
                    tprint("schemes: " + Object.keys(SCHEMES).join(", "));
                    tprint("note: live preview only — permanent switch: spicetify config color_scheme <name>", "t-dim");
                } else if (arg === "reset") {
                    resetScheme();
                    tprint("scheme reset to the applied one", "t-acc");
                } else {
                    const applied = applyScheme(arg);
                    tprint(applied ? "scheme: " + applied + " (live preview)" : "unknown scheme: " + arg, applied ? "t-acc" : "t-dim");
                }
                break;
            case "ascii":
                toggleSetting("ascii", "ASCII album art");
                break;
            case "mono":
                toggleSetting("mono", "monochrome covers");
                break;
            case "progress":
                toggleSetting("asciiProgress", "ASCII progress bar");
                break;
            case "log":
                toggleSetting("trackLog", "track load log");
                break;
            case "scanlines":
                toggleSetting("scanlines", "scanlines");
                break;
            case "vignette":
                toggleSetting("vignette", "vignette");
                break;
            case "about":
                tprint("termspot — CRT phosphor terminal theme for Spotify", "t-acc");
                tprint("by fdeox — github.com/fdeox/termspot\npairs with the Terminal Greeting extension");
                break;
            case "coffee":
                tprint("   ( (\n    ) )\n  ........\n  |      |]\n  \\      /\n   `----'", "t-acc");
                tprint("brew complete. back to the music.");
                break;
            case "1994":
                applyScheme("FdeoxAmber");
                settings.scanlines = true;
                saveSettings(settings);
                applyCrtKnobs();
                tprint("dialing up... carrier detected. welcome to 1994.", "t-acc");
                tprint("(`theme reset` brings you home)", "t-dim");
                break;
            default:
                tprint("command not found: " + cmd + "  (try: help)", "t-dim");
        }
    }

    function ensureTerminal() {
        if (termEl) return;
        termEl = document.createElement("div");
        termEl.id = "termspot-terminal";
        termOut = document.createElement("div");
        termOut.className = "t-out";
        const row = document.createElement("div");
        row.className = "t-row";
        const prompt = document.createElement("span");
        prompt.className = "t-prompt";
        // match the Terminal Greeting banner: <name>@termspot
        let promptName = "user";
        try {
            promptName =
                JSON.parse(window.localStorage.getItem("terminal-greeting:settings") || "{}").name ||
                "user";
        } catch (e) {
            /* keep "user" */
        }
        prompt.textContent = promptName + "@termspot:~ $";
        termIn = document.createElement("input");
        termIn.type = "text";
        termIn.spellcheck = false;
        termIn.addEventListener("keydown", (e) => {
            e.stopPropagation();
            if (e.key === "Enter") {
                exec(termIn.value);
                termIn.value = "";
            } else if (e.key === "Escape") {
                closeTerminal();
            }
        });
        row.append(prompt, termIn);
        termEl.append(termOut, row);
        document.body.appendChild(termEl);
    }

    function openTerminal() {
        ensureTerminal();
        if (termEl.style.display !== "flex") {
            termEl.style.display = "flex";
            if (!termOut.childElementCount) {
                tprint("termspot terminal — type `help` for commands, Esc to close", "t-dim");
            }
        }
        setTimeout(() => termIn.focus(), 0);
    }

    function closeTerminal() {
        if (termEl) termEl.style.display = "none";
    }

    document.addEventListener(
        "keydown",
        (e) => {
            const t = e.target;
            const typing =
                t && (t.tagName === "INPUT" || t.tagName === "TEXTAREA" || t.isContentEditable);
            if (!typing && e.key === ":") {
                e.preventDefault();
                e.stopPropagation();
                openTerminal();
            }
        },
        true
    );

    /* ---- settings ui ------------------------------------------------------ */
    function openSettings() {
        const wrap = document.createElement("div");
        wrap.style.cssText = "display:flex;flex-direction:column;gap:12px;font-size:14px;";

        const boxes = [
            ["ascii", "ASCII album art in the now playing view"],
            ["mono", "Monochrome phosphor covers (hover = color)"],
            ["asciiProgress", "ASCII progress bar [████░░░░]"],
            ["trackLog", "Track load log on song change"],
            ["compact", "Compact mode (denser, smaller type)"],
            ["scanlines", "CRT scanlines"],
            ["vignette", "CRT vignette"],
            ["poweron", "Power-on warm-up animation"],
        ].map(([key, label]) => {
            const l = document.createElement("label");
            l.style.cssText = "display:flex;gap:8px;align-items:center;cursor:pointer;";
            const c = document.createElement("input");
            c.type = "checkbox";
            c.checked = settings[key];
            c.dataset.key = key;
            l.append(c, document.createTextNode(label));
            return l;
        });

        const hint = document.createElement("div");
        hint.style.cssText = "color:var(--spice-subtext);font-size:12px;";
        hint.textContent = 'psst: press ":" anywhere for the hidden terminal';

        const save = document.createElement("button");
        save.textContent = "Save";
        save.style.cssText =
            "margin-top:4px;padding:8px 24px;align-self:flex-start;cursor:pointer;" +
            "background:var(--spice-button-active);color:var(--spice-main);border:none;";
        save.addEventListener("click", () => {
            boxes.forEach((l) => {
                const c = l.querySelector("input");
                settings[c.dataset.key] = c.checked;
            });
            saveSettings(settings);
            applyCrtKnobs();
            renderAscii();
            renderProgress();
            Spicetify.PopupModal.hide();
            Spicetify.showNotification("termspot: settings saved");
        });

        wrap.append(...boxes, hint, save);
        Spicetify.PopupModal.display({ title: "termspot", content: wrap });
    }

    try {
        new Spicetify.Menu.Item("termspot settings", false, openSettings).register();
    } catch (e) {
        console.error("[termspot] menu registration failed:", e);
    }

    /* ---- wiring -------------------------------------------------------------- */
    const safely = (fn) => () => {
        try {
            fn();
        } catch (e) {
            console.error("[termspot]", e);
        }
    };
    const tick = safely(() => {
        updateMonoFilter();
        renderAscii();
        renderProgress();
    });

    // hover-to-reveal for mono covers: CSS :hover is unreliable here because
    // overlay layers swallow it, so track the pointer and mark the hovered
    // clickable container instead
    let revealEl = null;
    const REVEAL_ROOTS =
        "a, button, [role='button'], [role='row'], [role='gridcell'], " +
        ".main-card-card, [class*='listRow' i], [class*='interactive' i], [draggable='true']";
    document.addEventListener(
        "pointerover",
        (e) => {
            if (!settings.mono || !e.target || !e.target.closest) return;
            let root = e.target.closest(REVEAL_ROOTS);
            // climb until the container actually holds a cover image
            while (root && !root.querySelector("img")) {
                root = root.parentElement ? root.parentElement.closest(REVEAL_ROOTS) : null;
            }
            if (root === revealEl) return;
            if (revealEl) revealEl.classList.remove("termspot-reveal");
            revealEl = root;
            if (revealEl) revealEl.classList.add("termspot-reveal");
        },
        true
    );
    document.addEventListener(
        "pointerleave",
        () => {
            if (revealEl) {
                revealEl.classList.remove("termspot-reveal");
                revealEl = null;
            }
        },
        true
    );

    applyCrtKnobs();
    tick();
    setInterval(safely(renderProgress), 500);
    setInterval(safely(updateMonoFilter), 1000);
    let obsTimer = 0;
    new MutationObserver(() => {
        clearTimeout(obsTimer);
        obsTimer = setTimeout(tick, 250);
    }).observe(document.body, { childList: true, subtree: true });
    try {
        Spicetify.Player.addEventListener("songchange", () => {
            setTimeout(tick, 250);
            showTrackLog();
            try {
                const meta = currentItem() && currentItem().metadata;
                if (meta && meta.title) {
                    if (stats.day !== todayKey()) stats = loadStats();
                    stats.plays[meta.title] = (stats.plays[meta.title] || 0) + 1;
                    saveStats();
                }
            } catch (e) {
                /* stats are best-effort */
            }
        });
    } catch (e) {
        /* observer covers it */
    }
})();
