pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// Reads the pywal palette (~/.cache/wal/colors.json) and updates live
// every time you change wallpaper (set-wallpaper.sh regenerates that file).
Singleton {
    id: root

    // Fallbacks (gruvbox-ish) in case pywal has not generated anything yet
    property color bg:      "#1d2021"
    property color bgAlt:   "#282828"
    property color fg:      "#ebdbb2"
    property color accent:  "#61afef"
    property color accent2: "#fe8019"
    property color dim:     "#928374"
    property color c1: "#fb4934"
    property color c2: "#b8bb26"
    property color c3: "#fabd2f"
    property color c4: "#83a598"
    property color c5: "#d3869b"

    // SEMANTIC colours: fixed on purpose. c1..c5 come from pywal and change with
    // the wallpaper (color2 has no reason to be green), so they are no good for
    // saying "charging" or "critical" — with certain wallpapers the charging
    // battery came out red and looked like an alarm.
    readonly property color ok:   "#6dbd7a"
    readonly property color warn: "#e0a458"
    readonly property color crit: "#e05c5c"

    // Path of the current wallpaper. It lives here and not in Config because
    // pywal is in charge: colors.json carries the path of the wallpaper the
    // palette came from, so colour and wallpaper can NEVER fall out of sync.
    // Keeping it separately in the rice's JSON would mean two sources of truth
    // for the same thing.
    // The overview uses it to paint each workspace.
    property string wallpaper: ""

    // ══════════════════════════════════════════════════════════════════════
    //  INK FOR WHAT FLOATS OVER THE WALLPAPER
    //
    //  The bar has no surface of its own —the scrim is at 0 by default—, so
    //  its bodies are painted STRAIGHT onto the wallpaper. And since pywal
    //  takes the palette from that same wallpaper, with a monochrome wallpaper
    //  the accent comes back tinted the same hue as the background and with a
    //  similar lightness: it re-themes correctly and still cannot be seen.
    //
    //  Measured on the workspace indicator with a blue wallpaper: the active
    //  pill (#366ca3) was at 1.6:1 from the inactive dots, and the dots
    //  —white at 50 %— were THE LIGHTEST thing in the group. In other words,
    //  what was off stood out more than what was on, and on top of that the
    //  pill came out darker than parts of the wallpaper itself.
    //
    //  It is measured against `wallStrip`, which is a REAL piece of the
    //  wallpaper (see below), not against pywal's background. And it is solved
    //  like this:
    //    · active   → 3.5:1 against the strip. Above the 3:1 a graphical
    //      element calls for, because it is THE indicator.
    //    · inactive → right at the MIDPOINT between the strip and the active
    //      one, that is, at the square root of its contrast (~1.9:1 on each
    //      side). A midpoint cannot blend into either the wallpaper or the
    //      pill, which are the two ways of getting lost; and since it derives
    //      from the pill, the hierarchy holds by itself without tuning numbers
    //      by hand.
    //
    //  Only the LIGHTNESS moves: the hue is still pywal's, so the re-theming
    //  is kept whole.
    // ══════════════════════════════════════════════════════════════════════
    readonly property bool darkWall: wallStrip.hslLightness < 0.5

    readonly property color onWallAccent: {
        const h = accent.hslHue < 0 ? 0 : accent.hslHue;
        // A grey accent is grey: forcing saturation on it would invent a hue
        // (with an achromatic palette the indicator came out red out of nowhere).
        const s = accent.hslSaturation < 0.08
            ? accent.hslSaturation : Math.max(accent.hslSaturation, 0.6);
        let l = accent.hslLightness;
        let out = Qt.hsla(h, s, l, 1);
        for (let i = 0; i < 60 && contrast(out, wallStrip) < 3.5; i++) {
            l = darkWall ? Math.min(l + 0.02, 1) : Math.max(l - 0.02, 0);
            out = Qt.hsla(h, s, l, 1);
        }
        return out;
    }

    // OPAQUE on purpose. With translucent ink the final colour ended up being
    // set by the wallpaper: the same dots measured 0.19 or 0.31 luminance
    // depending on the piece of wallpaper that happened to be behind them, so
    // over a light area they blended into it again. An opaque body is computed
    // once and holds always.
    readonly property color onWallDim: {
        const h = accent.hslHue < 0 ? 0 : accent.hslHue;
        const target = Math.sqrt(contrast(onWallAccent, wallStrip));
        let l = wallStrip.hslLightness;
        let out = Qt.hsla(h, 0.12, l, 1);
        for (let i = 0; i < 60 && contrast(out, wallStrip) < target; i++) {
            l = darkWall ? Math.min(l + 0.02, 1) : Math.max(l - 0.02, 0);
            out = Qt.hsla(h, 0.12, l, 1);
        }
        return out;
    }

    // The REAL colour of the top strip of the wallpaper, which is what lies
    // BEHIND the bar's bodies. set-wallpaper.sh samples it with magick; if that
    // file does not exist (or magick failed) this stays on pywal's background,
    // which is what there was before.
    property color wallStrip: bg
    FileView {
        id: stripFile
        path: Quickshell.env("HOME") + "/.cache/wal/bar-strip.txt"
        watchChanges: true
        onFileChanged: reload()
        // The comment above promised that if magick failed this stayed on
        // pywal's background, and it was not true: without the two `= root.bg`
        // below, an unreadable strip left the PREVIOUS wallpaper's colour stuck,
        // and the bar computed its contrast against a background that was no
        // longer on screen. That is exactly the case where it has to show.
        printErrors: false            // the file being missing is not an error
        onLoaded: {
            const t = stripFile.text().trim();
            root.wallStrip = /^#[0-9a-fA-F]{6}$/.test(t) ? t : root.bg;
        }
        onLoadFailed: root.wallStrip = root.bg
    }

    function _lin(x) { return x <= 0.03928 ? x / 12.92 : Math.pow((x + 0.055) / 1.055, 2.4); }
    function luminance(c) { return 0.2126 * _lin(c.r) + 0.7152 * _lin(c.g) + 0.0722 * _lin(c.b); }
    // WCAG contrast between two opaque colours, 1:1 (equal) to 21:1 (black/white).
    function contrast(a, b) {
        const x = luminance(a), y = luminance(b);
        return (Math.max(x, y) + 0.05) / (Math.min(x, y) + 0.05);
    }

    // ══════════════════════════════════════════════════════════════════════
    //  INK ON THE ACCENT
    //
    //  Whatever was filled with the accent was written over with `Colors.bg`,
    //  and both come from the SAME photo: `bg` is special.background and
    //  `accent` is color4. Nothing guaranteed they could be told apart.
    //  Measured by regenerating the palette with its flags in an isolated HOME,
    //  5 of the 21 wallpapers dropped below 4.5:1 on the active tab of Ajustes
    //  (Settings) — and the one in use was one of them (art-sukhoi, 3.82:1).
    //  dark-vpdvq3 got down to 2.48:1.
    //
    //  The THEME's ink is preferred as long as it is enough to be read, so on
    //  most wallpapers nothing changes and the ricing is kept; only when neither
    //  `bg` nor `fg` makes it does it fall back to black or white, which is the
    //  floor. impasto solves it more briefly (theme_manager.py:3809, a luminance
    //  threshold at 0.45) but always with #11111b or #ffffff; here the palette
    //  is tried first.
    // ══════════════════════════════════════════════════════════════════════
    function inkOn(base) {
        const cand = [bg, fg, Qt.rgba(0, 0, 0, 1), Qt.rgba(1, 1, 1, 1)];
        let mejor = cand[0], mejorC = 0;
        for (let i = 0; i < cand.length; i++) {
            const k = contrast(cand[i], base);
            if (k >= 4.5) return cand[i];       // the first one from the theme that makes it
            if (k > mejorC) { mejorC = k; mejor = cand[i]; }
        }
        return mejor;
    }
    readonly property color accentText:  inkOn(accent)
    readonly property color accent2Text: inkOn(accent2)

    // ══════════════════════════════════════════════════════════════════════
    //  THE NOTCH COLOUR IS STORED AS AN INTENTION, NOT AS A HEX
    //
    //  SettingsAppearance stored the ALREADY RESOLVED hex: choosing «Tema»
    //  (Theme) wrote `Colors.bg.toString()` into Config. And there it stayed.
    //  This singleton is live on ~/.cache/wal/colors.json, but nobody asked it
    //  again: you changed wallpaper with Super+Shift+W, everything re-themed
    //  except the notch —which kept the old palette's colour— and Ajustes
    //  (Settings) still showed «Tema» selected. The hint on that very row
    //  promised the opposite.
    //
    //  Worse still: a profile saved with «Tema» froze that hex inside its
    //  values, so applying it months later gave you back a colour from another
    //  palette under the wrong label.
    //
    //  With a sentinel, what gets stored is «follow the theme», and whoever
    //  paints resolves it. It is the pattern the rice already uses for the
    //  cursor colour (`cursorColor: "palette"` in impasto, SettingsService.qml:722,
    //  resolved in CompositorService.qml:286-288). Old hexes are still valid
    //  as they are, so neither saved profiles nor the JSON need migrating.
    // ══════════════════════════════════════════════════════════════════════
    // ══════════════════════════════════════════════════════════════════════
    //  THE COLOURS OF A SERIES, ALL CARRYING THE SAME WEIGHT
    //
    //  The eighteen Pokémon types come with their usual hex and have very
    //  different weights: Dark (#705746) sinks into a dark background and
    //  Electric (#F7D02C) shouts; together in a list they look like stickers
    //  from different sources. The work is split: the series sets the HUE,
    //  the house sets the WEIGHT — all at the same lightness, the one needed
    //  to be read on THIS background, which changes with pywal.
    //
    //  It lives here and not in the team panel because two places paint it:
    //  the panel's labels and bars, and the drop in the Control Centre strip.
    //  That drop used the raw hex, so the same types came out with one weight
    //  in one place and another in the other.
    // ══════════════════════════════════════════════════════════════════════
    function typeInk(hex) {
        if (!hex)
            return dim;
        const c = Qt.color(hex);
        const oscuro = bg.hslLightness < 0.5;
        const luz = oscuro ? Math.max(c.hslLightness, 0.66)
                           : Math.min(c.hslLightness, 0.38);
        return Qt.hsla(c.hslHue < 0 ? 0 : c.hslHue, Math.max(c.hslSaturation, 0.45), luz, 1);
    }

    readonly property string notchTheme: "theme"
    function notchTint(v) {
        return (!v || String(v) === root.notchTheme) ? root.bg : v;
    }

    // ══════════════════════════════════════════════════════════════════════
    //  FOUR INK LEVELS, BY CONTRAST AND NOT BY ALPHA
    //
    //  The shell had 129 hard-coded greys —#8a8a8a, #7d7d7d, #666666…— in 25
    //  files and 32 different shades. Two problems, and the second is the big
    //  one:
    //
    //    · 15 of those 32 did not reach the 4.5:1 minimum. #666666 measured
    //      2.88:1 against this background, below even the 3:1 a graphical
    //      element calls for, and that makes four labels that simply cannot
    //      be read.
    //    · None of them re-themes. You change wallpaper, pywal repaints the
    //      whole shell and these 129 stay EXACTLY the same: dead neutral greys
    //      in the middle of a tinted interface.
    //
    //  Twelve of the 32 shades meant the same thing («main text»), six
    //  «secondary» and ten «dimmed». The HIG have it solved with four label
    //  levels (color.md → Specifications), and the fourth is reserved for what
    //  is INACTIVE: "Use tertiaryLabel for inactive elements, and only when
    //  text doesn't need high legibility" (materials.md). Using the faint level
    //  for «secondary text because it looks more discreet» is exactly the
    //  shortcut that flattens the hierarchy.
    //
    //  It is solved by mixing `fg` towards `bg` —the same mechanism the shell
    //  already used with eyeballed alphas— but with the alpha COMPUTED by
    //  bisection until it gives the requested contrast. That way the theme's
    //  tint comes in by itself, the hierarchy does not depend on whichever
    //  wallpaper is on, and the result is opaque: an alpha lets whatever is
    //  behind decide the final colour, and then the same label measures
    //  differently from row to row.
    //
    //  The targets (7 / 5 / 3.5) are a hair above the minimums on purpose:
    //  with 4.5 and 3 there were twelve uses that would have got WORSE compared
    //  with the grey they had. This way 68 improve and none crosses a threshold
    //  downwards.
    // ══════════════════════════════════════════════════════════════════════
    function _mixFg(a) {
        return Qt.rgba(bg.r + (fg.r - bg.r) * a,
                       bg.g + (fg.g - bg.g) * a,
                       bg.b + (fg.b - bg.b) * a, 1);
    }

    // Bisection and not a sweep in steps of 0.01: 40 steps give the exact alpha
    // for any palette, and a sweep falls short when `fg` and `bg` are close
    // (a low-contrast palette needs very fine alphas).
    function inkLevel(target) {
        let lo = 0, hi = 1;
        for (let i = 0; i < 40; i++) {
            const mid = (lo + hi) / 2;
            if (contrast(_mixFg(mid), bg) < target) lo = mid; else hi = mid;
        }
        return _mixFg((lo + hi) / 2);
    }

    readonly property color label:  fg                 // the datum
    readonly property color label2: inkLevel(7.0)      // what goes with the datum
    readonly property color label3: inkLevel(5.0)      // labels, units, notes
    readonly property color label4: inkLevel(3.5)      // disabled ONLY

    // ══════════════════════════════════════════════════════════════════════
    //  SURFACES ARE COMPUTED; TAKING THEM FROM THE PALETTE DOES NOT WORK
    //
    //  `bgAlt` comes from `colors.color0` and `bg` from `special.background`.
    //  Nothing forces them to differ, and with today's palette they are THE
    //  SAME COLOUR (#132125, 1.00:1). So `Card.qml`, which promised in its
    //  comment «fondo elevado + borde sutil» (raised background + subtle
    //  border), had no raised background at all: just a border of `fg` at 6 %,
    //  that is, 1.2:1. A card that cannot be seen groups nothing, and grouping
    //  is precisely what it was there for.
    //
    //  In dark mode the HIG ask for two sets of backgrounds, base and elevated,
    //  and the elevated ones are LIGHTER: "the elevated colors are brighter,
    //  making foreground interfaces appear to advance" (dark-mode.md). Plus
    //  three grouping levels at most (color.md), not four: the fourth level of
    //  nesting carries no surface, it carries air (boxes.md).
    //
    //  The delta is in HSL lightness and not in a white alpha because pure
    //  white ignores the theme: 63 of the shell's fills were Qt.rgba(1,1,1,α)
    //  and with a greenish wallpaper they pull the panel towards neutral grey
    //  while their neighbours —the ones using `fg`— pull towards cream.
    // ══════════════════════════════════════════════════════════════════════
    function surface(n) {
        if (n <= 0)
            return bg;
        const paso = 0.045 * n;
        const l = darkTheme ? Math.min(bg.hslLightness + paso, 1)
                            : Math.max(bg.hslLightness - paso, 0);
        return Qt.hsla(bg.hslHue < 0 ? 0 : bg.hslHue, bg.hslSaturation, l, 1);
    }
    readonly property bool darkTheme: bg.hslLightness < 0.5
    readonly property color surface1: surface(1)       // group within the view
    readonly property color surface2: surface(2)       // group within the group

    // ══════════════════════════════════════════════════════════════════════
    //  THE ACCENT AS INK, WHICH IS NOT THE ACCENT AS FILL
    //
    //  `accent` is pywal's color4 and with this palette it measures 3.82:1
    //  against the background. As a FILL that is fine —a graphical element is
    //  asked for 3:1— but there are 34 places that use it as a text colour,
    //  and there the minimum is 4.5:1 and the target 7:1 "especially in small
    //  text" (dark-mode.md). The shell writes at fsXS 11 and fsS 12: that is
    //  small text.
    //
    //  The same trick `onWallAccent` uses for the bar, but against the panel
    //  surface instead of the wallpaper strip: the lightness is pushed until it
    //  gets there, the hue does not move, and the ricing is kept. With most
    //  palettes nothing changes because they already got there.
    // ══════════════════════════════════════════════════════════════════════
    function _inkAccent(base, sobre) {
        const h = base.hslHue < 0 ? 0 : base.hslHue;
        const s = base.hslSaturation < 0.08
            ? base.hslSaturation : Math.max(base.hslSaturation, 0.45);
        let l = base.hslLightness;
        let out = Qt.hsla(h, s, l, 1);
        const subir = sobre.hslLightness < 0.5;
        for (let i = 0; i < 80 && contrast(out, sobre) < 4.5; i++) {
            l = subir ? Math.min(l + 0.01, 1) : Math.max(l - 0.01, 0);
            out = Qt.hsla(h, s, l, 1);
        }
        return out;
    }
    readonly property color accentInk:  _inkAccent(accent, bg)
    readonly property color accent2Ink: _inkAccent(accent2, bg)

    // ══════════════════════════════════════════════════════════════════════
    //  FILLS AND BORDER: THREE AND ONE
    //
    //  There were 192 Qt.rgba in the shell with 37 different alphas. Seven of
    //  them —0.055, 0.06, 0.07, 0.075, 0.10, 0.12, 0.14— were all «subtle
    //  border», and twelve more, between 0.045 and 0.14, all «subtle fill». The
    //  eye cannot tell 0.06 from 0.07 looking at them one by one; what it does
    //  see is that two adjacent panels do not carry the same line weight.
    //
    //  The HIG close the vocabulary: three fill levels and ONE separator
    //  —"The system provides a single, default vibrancy value for a separator,
    //  which works well on all materials" (materials.md)—. Just as the scale
    //  of durations is closed in Appearance.qml.
    //
    //  On `fg` and not on white, for the same reason as the surfaces.
    // ══════════════════════════════════════════════════════════════════════
    function _fg(a) { return Qt.rgba(fg.r, fg.g, fg.b, a) }
    readonly property color fill1:  _fg(0.14)   // pressed, selected
    readonly property color fill2:  _fg(0.09)   // hover
    readonly property color fill3:  _fg(0.055)  // rest state of a body with a background
    readonly property color hairline: _fg(0.10) // the border and the separator, a single one

    function _c(hex, fb) { return (hex && String(hex).length > 0) ? hex : fb }

    FileView {
        id: wal
        path: Quickshell.env("HOME") + "/.cache/wal/colors.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.apply()
    }

    function apply() {
        var t = wal.text();
        if (!t || t.length === 0) return;
        try {
            var j = JSON.parse(t);
            var s = j.special, c = j.colors;
            root.bg      = _c(s.background, root.bg);
            root.fg      = _c(s.foreground, root.fg);
            root.bgAlt   = _c(c.color0,  root.bgAlt);
            root.accent  = _c(c.color4,  root.accent);
            root.accent2 = _c(c.color1,  root.accent2);
            root.dim     = _c(c.color8,  root.dim);
            root.c1 = _c(c.color1, root.c1);
            root.c2 = _c(c.color2, root.c2);
            root.c3 = _c(c.color3, root.c3);
            root.c4 = _c(c.color4, root.c4);
            root.c5 = _c(c.color5, root.c5);
            // Explicit "file://": Image wants it as a URL, and a bare path would
            // be resolved relative to the .qml, not to the root.
            if (j.wallpaper && String(j.wallpaper).length > 0)
                root.wallpaper = "file://" + j.wallpaper;
        } catch (e) { /* keeps the fallbacks */ }
    }
}
