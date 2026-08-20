// NAME: Terminal Greeting
// AUTHOR: fdeox
// DESCRIPTION: Terminal-style prompt on your home page — time-of-day greeting, live clock, blinking cursor, now-playing ticker, playing-track marker, optional night accent shift and a fake boot screen.

(function terminalGreeting() {
    /* ---- settings (plain localStorage: usable before Spicetify is ready) ---- */
    const STORAGE_KEY = "terminal-greeting:settings";
    const DEFAULTS = {
        name: "",          // empty -> resolved from the Spotify display name
        host: "termspot",  // the part after the @ in the prompt — change it to anything
        nowPlaying: true,  // rotate the prompt with the current track
        trackMarker: true, // mark the playing track green in tracklists
        nightShift: false, // amber accents between 22:00 and 05:00
        bootScreen: true,  // fake boot log on startup
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
            /* storage unavailable — keep going with in-memory settings */
        }
    }

    let settings = loadSettings();
    const userName = () => settings.name || "user";
    const hostName = () => settings.host || "spotify";
    const pad = (n) => String(n).padStart(2, "0");

    function greeting(hour) {
        if (hour >= 5 && hour < 12) return "good morning";
        if (hour >= 12 && hour < 17) return "good afternoon";
        if (hour >= 17 && hour < 22) return "good evening";
        return "good night";
    }
    const isNight = (hour) => hour >= 22 || hour < 5;

    /* ---- boot screen: needs only the DOM, so it runs before Spicetify ---- */
    function bootScreen() {
        if (!settings.bootScreen || document.getElementById("terminal-greeting-boot")) return;
        const LINES = [
            "spotifyOS booting for " + userName() + "...",
            "",
            "[  OK  ] loading audio drivers...",
            "[  OK  ] mounting ~/music...",
            "[  OK  ] starting playback daemon...",
            "[  OK  ] syncing ~/library...",
            "[  OK  ] welcome back, " + userName(),
        ];
        const overlay = document.createElement("div");
        overlay.id = "terminal-greeting-boot";
        overlay.style.cssText =
            "position:fixed;inset:0;z-index:99999;" +
            "background:var(--spice-main,#121212);color:var(--spice-text,#fff);" +
            'font-family:"JetBrains Mono","Cascadia Mono",Consolas,monospace;' +
            "font-size:14px;line-height:1.8;padding:48px;white-space:pre;" +
            "cursor:pointer;transition:opacity .4s ease;";
        document.body.appendChild(overlay);

        let i = 0;
        const timer = setInterval(() => {
            if (i < LINES.length) {
                const row = document.createElement("div");
                const text = LINES[i];
                if (text.startsWith("[  OK  ]")) {
                    const ok = document.createElement("span");
                    ok.style.color = "var(--spice-button-active,#1ed760)";
                    ok.textContent = "[  OK  ]";
                    row.appendChild(ok);
                    row.appendChild(document.createTextNode(text.slice(8) || " "));
                } else {
                    row.textContent = text || " ";
                }
                overlay.appendChild(row);
                i++;
            } else {
                clearInterval(timer);
                setTimeout(() => {
                    overlay.style.opacity = "0";
                    setTimeout(() => overlay.remove(), 450);
                }, 500);
            }
        }, 280);
        overlay.addEventListener("click", () => {
            clearInterval(timer);
            overlay.remove();
        });
    }

    if (document.body) {
        bootScreen();
    } else {
        document.addEventListener("DOMContentLoaded", bootScreen);
    }

    /* ---- everything else waits for the Spicetify APIs ---- */
    (function waitSpicetify() {
        // Menu.Item needs Spicetify.ReactJSX internally, so wait for React too —
        // registering before it loads throws "Cannot read properties of undefined (reading 'jsx')"
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
            setTimeout(waitSpicetify, 300);
            return;
        }
        try {
            main();
        } catch (e) {
            console.error("[terminal-greeting]", e);
        }
    })();

    function main() {
        // default the name to the Spotify display name once
        if (!settings.name) {
            try {
                Spicetify.Platform.UserAPI.getUser().then((u) => {
                    if (!settings.name && u && u.displayName) {
                        settings.name = u.displayName.toLowerCase().split(" ")[0];
                        saveSettings(settings);
                    }
                });
            } catch (e) {
                /* keep "user" */
            }
        }

        /* ---- static css ---- */
        const baseStyle = document.createElement("style");
        baseStyle.id = "terminal-greeting-style";
        baseStyle.textContent = [
            "#terminal-greeting-banner {",
            '  font-family: "JetBrains Mono", "Cascadia Mono", Consolas, monospace;',
            "  font-size: 14px; line-height: 1.4; padding: 24px 8px 8px;",
            "  color: var(--spice-text); white-space: pre; user-select: none;",
            "}",
            "#terminal-greeting-banner .tg-accent { color: var(--spice-button-active); }",
            "#terminal-greeting-banner .tg-dim { color: var(--spice-subtext); }",
            "#terminal-greeting-banner .tg-cursor {",
            "  color: var(--spice-button-active);",
            "  animation: tg-blink 1.1s steps(1) infinite;",
            "}",
            "@keyframes tg-blink { 50% { opacity: 0; } }",
            ".terminal-greeting-playing { color: var(--spice-button-active) !important; }",
            '.terminal-greeting-playing::before { content: "\\266A  "; }',
        ].join("\n");
        document.head.appendChild(baseStyle);

        /* ---- night shift ----
           set the variables inline on <html>: stylesheet order can't override
           an inline custom property, so this wins against any theme css */
        const NIGHT_VARS = {
            "--spice-accent": "#d9913d",
            "--spice-accent-active": "#ffb86c",
            "--spice-banner": "#ffb86c",
            "--spice-border-active": "#ffb86c",
            "--spice-button": "#d9913d",
            "--spice-button-active": "#ffb86c",
            "--spice-rgb-accent": "217,145,61",
            "--spice-rgb-accent-active": "255,184,108",
            "--spice-rgb-button": "217,145,61",
            "--spice-rgb-button-active": "255,184,108",
        };
        let nightOn = false;
        function applyNight(on) {
            if (on === nightOn) return;
            nightOn = on;
            const root = document.documentElement.style;
            for (const key of Object.keys(NIGHT_VARS)) {
                if (on) {
                    root.setProperty(key, NIGHT_VARS[key]);
                } else {
                    root.removeProperty(key);
                }
            }
        }

        /* ---- now playing ---- */
        function currentTitle() {
            try {
                const item = Spicetify.Player.data && (Spicetify.Player.data.item || Spicetify.Player.data.track);
                const t = item && item.metadata && item.metadata.title;
                if (t) return t;
            } catch (e) {
                /* fall through to DOM */
            }
            const el = document.querySelector(
                '[data-testid="context-item-info-title"], [data-testid="context-item-link"], .main-nowPlayingWidget-trackInfo a'
            );
            return el ? el.textContent : null;
        }

        function nowPlayingText() {
            try {
                if (!Spicetify.Player.isPlaying()) return null;
                const item = Spicetify.Player.data && (Spicetify.Player.data.item || Spicetify.Player.data.track);
                const meta = item && item.metadata;
                if (!meta || !meta.title) return null;
                let text = "now playing: " + meta.title;
                if (meta.artist_name) text += " — " + meta.artist_name;
                if (text.length > 70) text = text.slice(0, 67) + "...";
                return text;
            } catch (e) {
                return null;
            }
        }

        /* ---- banner ---- */
        // the prompt rotates: greeting -> now playing -> listening uptime
        let rot = 0;
        let lastBannerKey = "";

        let listenSec = 0;
        setInterval(() => {
            try {
                if (Spicetify.Player.isPlaying()) listenSec += 5;
            } catch (e) {
                /* player not ready yet */
            }
        }, 5000);

        function uptimeText() {
            if (listenSec < 60) return null;
            const h = (listenSec / 3600) | 0;
            const m = ((listenSec % 3600) / 60) | 0;
            return "uptime: " + (h ? h + "h " : "") + m + "m of music";
        }

        function bannerTarget() {
            return (
                document.querySelector(".view-homeShortcutsGrid-shortcuts") ||
                document.querySelector(".main-home-content > div") ||
                null
            );
        }

        function renderBanner() {
            const target = bannerTarget();
            let banner = document.getElementById("terminal-greeting-banner");
            if (!target) {
                if (banner) banner.remove();
                lastBannerKey = "";
                return;
            }
            let moved = false;
            if (!banner || banner.nextElementSibling !== target) {
                if (banner) banner.remove();
                banner = document.createElement("div");
                banner.id = "terminal-greeting-banner";
                banner.title = "Terminal Greeting settings";
                banner.style.cursor = "pointer";
                banner.addEventListener("click", openSettings);
                target.parentElement.insertBefore(banner, target);
                moved = true;
            }

            const now = new Date();
            const np = settings.nowPlaying && rot === 1 ? nowPlayingText() : null;
            const up = rot === 2 ? uptimeText() : null;
            const body = np ? "♪ " + np : up || greeting(now.getHours()) + ", " + userName();
            const time = "[" + pad(now.getHours()) + ":" + pad(now.getMinutes()) + "]";

            // rebuilding every tick would restart the cursor blink animation,
            // so skip the DOM work when nothing visible changed
            const key = userName() + "@" + hostName() + "|" + body + "|" + time;
            if (!moved && key === lastBannerKey) return;
            lastBannerKey = key;

            banner.textContent = "";
            const user = document.createElement("span");
            user.className = "tg-accent";
            user.textContent = userName() + "@" + hostName();
            const path = document.createTextNode(":~ $ ");
            const text = document.createElement("span");
            text.textContent = body + "  ";
            const clock = document.createElement("span");
            clock.className = "tg-dim";
            clock.textContent = time + " ";
            const cursor = document.createElement("span");
            cursor.className = "tg-cursor";
            cursor.textContent = "█";
            banner.append(user, path, text, clock, cursor);
        }

        /* ---- playing-track marker ---- */
        const normalize = (s) =>
            s
                .toLowerCase()
                .replace(/[‘’ʼ]/g, "'")
                .replace(/[“”]/g, '"')
                .replace(/\s+/g, " ")
                .trim();

        function titleMatches(rowText, title) {
            const r = normalize(rowText);
            const t = normalize(title);
            if (!r || !t) return false;
            return r === t || r.startsWith(t);
        }

        function markRows() {
            document
                .querySelectorAll(".terminal-greeting-playing")
                .forEach((el) => el.classList.remove("terminal-greeting-playing"));
            if (!settings.trackMarker) return;
            const title = currentTitle();
            if (!title) return;
            document
                .querySelectorAll('.main-trackList-trackListRow, [data-testid="tracklist-row"]')
                .forEach((row) => {
                    const cell =
                        row.querySelector(".main-trackList-rowTitle") ||
                        row.querySelector('[data-testid="internal-track-link"]') ||
                        row.querySelector('a[href*="/track/"]');
                    if (cell && titleMatches(cell.textContent, title)) {
                        cell.classList.add("terminal-greeting-playing");
                    }
                });
        }

        /* ---- settings ui ---- */
        function openSettings() {
            const wrap = document.createElement("div");
            wrap.style.cssText = "display:flex;flex-direction:column;gap:12px;font-size:14px;";

            const inputCss =
                "padding:6px 8px;background:var(--spice-highlight);color:var(--spice-text);" +
                "border:1px solid var(--spice-border-inactive,#555);border-radius:4px;";
            const nameLabel = document.createElement("label");
            nameLabel.textContent = "Name shown in the prompt:";
            const nameInput = document.createElement("input");
            nameInput.type = "text";
            nameInput.value = settings.name;
            nameInput.style.cssText = inputCss;
            nameLabel.appendChild(nameInput);

            const hostLabel = document.createElement("label");
            hostLabel.textContent = "Host shown after the @ (e.g. spotify, termspot):";
            const hostInput = document.createElement("input");
            hostInput.type = "text";
            hostInput.value = settings.host || "spotify";
            hostInput.style.cssText = inputCss;
            hostLabel.appendChild(hostInput);

            const boxes = [
                ["nowPlaying", "Rotate the prompt with the current track"],
                ["trackMarker", "Mark the playing track in tracklists"],
                ["nightShift", "Amber accent colors between 22:00 and 05:00"],
                ["bootScreen", "Fake boot log on startup"],
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

            const save = document.createElement("button");
            save.textContent = "Save";
            save.style.cssText =
                "margin-top:4px;padding:8px 24px;align-self:flex-start;cursor:pointer;" +
                "background:var(--spice-button-active);color:var(--spice-main);border:none;border-radius:4px;";
            save.addEventListener("click", () => {
                settings.name = nameInput.value.trim();
                settings.host = hostInput.value.trim() || "spotify";
                boxes.forEach((l) => {
                    const c = l.querySelector("input");
                    settings[c.dataset.key] = c.checked;
                });
                saveSettings(settings);
                applyNight(settings.nightShift && isNight(new Date().getHours()));
                markRows();
                lastBannerKey = "";
                renderBanner();
                Spicetify.PopupModal.hide();
                Spicetify.showNotification("Terminal Greeting: settings saved");
            });

            wrap.append(nameLabel, hostLabel, ...boxes, save);
            Spicetify.PopupModal.display({ title: "Terminal Greeting", content: wrap });
        }

        try {
            new Spicetify.Menu.Item("Terminal Greeting settings", false, openSettings).register();
        } catch (e) {
            console.error("[terminal-greeting] menu registration failed:", e);
        }

        /* ---- wiring: every callback guarded so one failure can't stop the rest ---- */
        const safely = (fn) => () => {
            try {
                fn();
            } catch (e) {
                console.error("[terminal-greeting]", e);
            }
        };

        const tick = safely(() => {
            applyNight(settings.nightShift && isNight(new Date().getHours()));
            renderBanner();
        });
        const mark = safely(markRows);

        tick();
        mark();
        setInterval(() => {
            rot = (rot + 1) % 3;
            tick();
        }, 8000);
        setInterval(tick, 1000);
        setInterval(mark, 1500);
        try {
            Spicetify.Player.addEventListener("songchange", () => {
                rot = 1;
                tick();
                mark();
            });
        } catch (e) {
            console.error("[terminal-greeting]", e);
        }
    }
})();
