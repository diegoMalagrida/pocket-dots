pragma Singleton
import Quickshell
import QtQuick   // FontMetrics, to centre the clock by its real metrics

// Shared design system — like end-4's and caelestia's Appearance/Config.
// Everything (bar, dashboard, osd, notifications...) uses these tokens => it looks cohesive.
Singleton {
    id: root
    // Mono + Nerd Font: the bar and EVERYTHING that paints icons (the glyphs
    // only exist in this family).
    readonly property string font: "JetBrains Mono Nerd Font"

    // Proportional, only for the text inside the notch (clock, dates,
    // titles). A date in a monospaced font looks gangly: the letters are spaced
    // like the digits and "mar 4 ago" (Tue 4 Aug) looks like terminal text.
    readonly property string fontUI: Config.fontUI   // chosen in Settings › Appearance

    // Font for the notch clock ONLY. It is kept apart from fontUI on purpose:
    // the Pokémon Game Boy font is 10 px pixel art and works for four digits,
    // not for the whole interface.
    // To go back to the usual one: put Config.fontUI here and that is all.
    //
    // BUT IT MAY NOT BE THERE, AND THAT IS NOT AN INSTALLATION FAILURE.
    //
    // The .ttf does not travel in the repo and cannot: the original project
    // (PascalPixel/pokemon-font) was published WITHOUT a licence file, and
    // without an explicit licence the default that applies is "all rights
    // reserved". Its successor, Johto Mono, is paid and its licence says
    // "exclusively for personal projects". There is a fork with the OFL out
    // there, but a third party put it on an original that did not have it, so
    // it does not count.
    //
    // It is resolved by asking the system instead of taking it for granted: if
    // the family is not installed, this returns the interface font, and then
    // `fontClock === fontUI` switches off, by itself, all the machinery below
    // —the quantisation to multiples of 8, the vertical nudge, the quantum of
    // the Settings slider—, which exists only because of this font's odd
    // metrics. The clock simply shows in the same typeface as everything else.
    readonly property string fontClock: Qt.fontFamilies().indexOf("pokemon-font") >= 0
                                      ? "pokemon-font" : Config.fontUI

    // Pixel art only looks clean at integer scale. This font's README says
    // "10 px and multiples of 10", but the actual file does not work in tens:
    // its em is 320 units and ALL its outlines fall on a grid of 40, i.e. 8
    // design pixels per em. The sizes that come out crisp are the multiples
    // of 8 -- at 16 px each design pixel takes exactly 2 px. At 20, which is
    // where I had it because I listened to the README, it took 2.5 and that is
    // why the strokes came out uneven.
    //
    // It is only quantised when the clock uses a font different from the
    // interface's; with the usual one the size from Settings is kept as is.
    function clockPixelSize(base) {
        if (fontClock === fontUI)
            return base;
        return Math.max(8, Math.round(base / 8) * 8);
    }

    // The smallest step the clock NOTICES. It is published here because the
    // quantisation above is a decision of this font, and Settings has no
    // business knowing it: the clock-size slider relies on this to move
    // between sizes that really exist instead of showing thirteen positions
    // of which the clock only knows two. If one day fontClock goes back to
    // being fontUI, this becomes 1 by itself and the slider is continuous
    // again without touching anything else.
    readonly property int clockQuantum: fontClock === fontUI ? 1 : 8

    // Centring a clock with verticalCenter leaves the text HIGH, and the more
    // distinctive the font, the more it shows: verticalCenter centres the
    // text's BOX, and that box reserves room for the descender -- the tail of
    // the "g" or the "p" -- which digits never use. Measured on the Game Boy
    // font at 20 px: 10 px of air above against 16 below.
    //
    // This corrects it with the font's real metrics instead of an eyeballed
    // number, so it still holds if you change the clock size in Settings. It
    // is measured at 100 px and stored as a ratio, which is what lets it scale
    // to any size.
    FontMetrics {
        id: clockMetrics
        font.family: root.fontClock
        font.pixelSize: 100
    }

    // Distance between the centre of the digits and the centre of the box, per
    // pixel of size. Negative = the text has to move up.
    //
    // Where it comes from: text is centred by its box, which runs from -ascent
    // to +descent relative to the baseline. Digits stand upwards from that
    // line and come nowhere near the bottom edge, so their centre and the
    // box's do not coincide. This font takes it to the extreme: ascent 400
    // against descent 40, on an em of 320.
    //
    // It is measured with tightBoundingRect, i.e. the REAL box of the glyphs,
    // and not with capitalHeight: this font DECLARES a cap height of 280 when
    // its numbers really measure 240, and trusting the declared value leaves
    // the clock a pixel and a half too low.
    readonly property real clockNudgeRatio: {
        var r = clockMetrics.tightBoundingRect("0123456789:");
        var centroDigitos = r.y + r.height / 2;                        // < 0: above the baseline
        var centroCaja = (clockMetrics.descent - clockMetrics.ascent) / 2;
        return (centroCaja - centroDigitos) / 100;
    }

    // How far to lower the clock, in pixels. With the interface font it returns
    // 0 on purpose: if one day you go back, the notch stays exactly as it was
    // and this plays no part.
    function clockNudge(base) {
        if (fontClock === fontUI)
            return 0;
        return Math.round(clockPixelSize(base) * clockNudgeRatio);
    }

    // font sizes
    //
    // fsXXS is the FLOOR, and it exists because 22 places were writing at 9 px:
    // MediaPanel, GithubPanel, ControlPanel, the notch and ten corners of the
    // team panel. The HIG give the minimum per platform in a table
    // (typography.md → Ensuring legibility): macOS 10 pt, iOS 11 pt. 9 does not
    // reach even the more permissive of the two, and on top of that several of
    // those places wrote in dim grey, which is the least forgiving combination.
    //
    // fsXL plugs the other hole: the scale jumped from 16 to 42, which is why
    // 17, 18, 19 and 22 had been set by hand. 22 is macOS's Title 1.
    readonly property int fsXXS: 10
    readonly property int fsXS: 11
    readonly property int fsS:  12
    readonly property int fsM:  13
    readonly property int fsL:  16
    readonly property int fsXL: 22
    readonly property int fsXXL: 42

    // ─── Line height ───
    // The literal macOS table (typography.md → macOS built-in text styles):
    // 10→13, 11→14, 12→15, 13→16, 15→20, 17→22, 22→26, 26→32. It is NOT a smooth
    // function —15→20 is 1.33 and 22→26 is 1.18, so the trend breaks twice—
    // and that is why it is copied as is instead of multiplying by a ratio.
    //
    // It was needed because `lineHeight` did not appear once in the 52 .qml
    // files: line spacing came from the font, and the font is chosen in
    // Settings. In other words, the air between the lines of a description
    // changed when you changed font, and nobody had decided that.
    readonly property var _leadTable: [[10,13],[11,14],[12,15],[13,16],[15,20],[17,22],[22,26],[26,32]]
    function leading(px) {
        const t = _leadTable;
        if (px <= t[0][0])
            return Math.round(px * t[0][1] / t[0][0]);
        for (let i = 1; i < t.length; i++) {
            if (px === t[i][0])
                return t[i][1];
            if (px < t[i][0]) {
                const a = t[i - 1], b = t[i];
                return Math.round(a[1] + (b[1] - a[1]) * (px - a[0]) / (b[0] - a[0]));
            }
        }
        const ult = t[t.length - 1];
        return Math.round(px * ult[1] / ult[0]);
    }

    // ─── Weights ───
    // Hierarchy is built with WEIGHT as well as size: on macOS the Headline
    // style is Bold at the SAME size as Body (13/16 both), i.e. a heading is
    // not bigger text, it is heavier text. Without this, everything that was
    // meant to stand out did so by lowering the opacity, which is what leaves
    // the interface flat and below the minimum contrast at the same time.
    //
    // Ultralight, Thin and Light are left OUT on purpose: "In general, avoid
    // light font weights […] which can be difficult to see, especially when
    // text is small" (typography.md).
    readonly property int wRegular: Font.Normal
    readonly property int wMedium:  Font.Medium     // selected, soft emphasis
    readonly property int wSemi:    Font.DemiBold   // Apple's "emphasized"
    readonly property int wBold:    Font.Bold       // heading at body size

    // corner radii
    readonly property int radS: 10
    readonly property int radM: 14
    readonly property int radL: 18
    readonly property int radPill: 999

    // ─── Concentric radii ───
    // The radius of whatever goes INSIDE is not a token, it is a calculation:
    // the parent's radius minus the margin. "match its corner radius to the
    // outer corner radius […] by subtracting the margin" (live-activities.md),
    // and the reason is on the page next door: "the shape of the hardware
    // informs the curvature, size, and shape of nested interface elements"
    // (adopting-liquid-glass.md). A curve that is not concentric with its
    // container's leaves a crescent of uneven thickness between the two, and
    // that shows even if you do not know why.
    //
    // There were 75 `radius:` with a hand-typed number, choosing between 10,
    // 14 and 18 by whatever looked right, without looking at the padding. With
    // this the function is the token and the result is not: inside radL 18
    // with pad 16 it gives 2, inside radM 14 with gapM 10 it gives 4.
    //
    // Floor at 2 and not 0: a square corner inside something rounded does not
    // read as a decision, it reads as something forgotten.
    function radInner(radOuter, margin) {
        return Math.max(2, radOuter - margin);
    }

    // spacing
    readonly property int gapS: 6
    readonly property int gapM: 10
    readonly property int gapL: 14
    readonly property int pad:  16

    // ══════════════════════════════════════════════════════════════════════
    //  MOTION — the whole scale, shared with Hyprland
    //  Hyprland uses these same four numbers (in deciseconds) for windows
    //  and workspaces. If something moves and is not here, it is a bug.
    //
    //    RESPONSE   130 / 130   hover, press, colour, a toggle
    //    CONTENT    210 / 110   text and icons inside something already there
    //    PANEL      320 / 170   a surface that appears
    //    SHAPE      440 / 220   the shape changes, or something moves as a whole
    //
    //  Events are asymmetric (out in half the time it takes to come in);
    //  states, like hover, are symmetric.
    // ══════════════════════════════════════════════════════════════════════
    readonly property int mQuick: 130        // RESPONSE: hover, colour, press, knobs
    readonly property int mIn: 210           // CONTENT coming in (opacity)
    readonly property int mOut: 110          // CONTENT going out: half
    readonly property int mInScale: 320      // PANEL coming in (scale, elastic)
    readonly property int mOutScale: 170     // PANEL going out
    readonly property int mShape: 440        // SHAPE: the notch morph
    readonly property int mOutShape: 220     // SHAPE going out

    // Aliases from the first batch of tokens. They existed alongside the m*
    // ones with almost identical numbers (120/220/320) — two vocabularies for
    // the same thing was exactly what kept anything from quite fitting. Now
    // they point at the good scale; they are kept so as not to break code
    // that still uses them.
    readonly property int animFast: mQuick
    readonly property int animMed:  mIn
    readonly property int animSlow: mInScale

    // ─── Curves ───
    // Bounce is forbidden on DISPLACEMENTS: something that slides and
    // overshoots shows the edge of the screen and gives the trick away. But
    // on SCALES there is nothing to show — a thing that inflates, overshooting
    // its size by a hair, only feels alive. That is where the character goes.
    // (Corrected 2026-08-05: law 5 forbade both and left the system coherent
    // but bland.)
    readonly property real mOvershoot: 1.3    // the shape morph
    readonly property real mInOvershoot: 1.05 // content and panels coming in
    readonly property real mScaleFrom: 0.90   // where incoming things grow from

    // Deliberate exception to the scale: a playback bar is not an accent, it
    // is a continuous signal. If the transition lasts EXACTLY as long as the
    // refresh interval, the bar advances at constant speed and reads as
    // continuous movement instead of hopping every half second. That is why
    // it is linear and why 500 is not on the scale (law 7).
    readonly property int mTick: 500

    // The stagger is what prevents the smear: the new thing starts coming in
    // just as the old one has finished going out, not at the same time.
    readonly property int mStagger: 110      // = mOut

    // ══════════════════════════════════════════════════════════════════════
    //  SPRINGS — a difference in kind, not a tweak
    //
    //  A Bézier curve has a fixed duration: it does not know where it is, only
    //  how much it has left. If you change its target mid-animation it has to
    //  CUT and start from zero, and that is why the system feels rubbery when
    //  you do two things quickly in a row.
    //
    //  A spring has STATE: position and velocity. You change the target in
    //  mid-flight and it carries on from where it was, at the speed it had.
    //  There is no cut because there is nothing to restart. That is what
    //  separates something that feels physical from something that feels
    //  programmed.
    //
    //  The interesting part: in Hyprland this requires migrating to Lua
    //  (0.55+), but Qt has always had it and NOBODY in the rice world uses it.
    //  Here we do.
    //
    //  Three characters, one per spatial step. 'spring' pulls (more = faster)
    //  and 'damping' brakes (less = more bounce).
    // ══════════════════════════════════════════════════════════════════════
    readonly property real sprTight: 5.2      // RESPONSE: arrives and stays, barely overshooting
    readonly property real dmpTight: 0.58

    readonly property real sprPanel: 4.0      // PANEL: a surface that appears
    readonly property real dmpPanel: 0.42

    readonly property real sprLoose: 3.1      // SHAPE: the morph, with travel to spare
    readonly property real dmpLoose: 0.34

    // WHIP: high stiffness, for whatever has to LET GO ALL AT ONCE after
    // having been held -- the edge behind the indicator. It is paired with
    // dmpPanel: with lower damping the edge keeps oscillating and the pill
    // throbs after it arrives.
    readonly property real sprSquash: 6.5

    // epsilon = when it counts as at rest. In pixels, a quarter of a pixel is
    // invisible and cuts off the spring's dead tail; in scale (0..1) it needs
    // to be a thousand times smaller or it stops 1 % short of the target,
    // which at 300 px is visible.
    readonly property real eppPx: 0.25
    readonly property real eppScale: 0.001

    // How far a face of the notch travels sideways on entry. The notch clips,
    // so the content travels INSIDE the slot: you do not see it appear, you
    // see it arrive.
    readonly property int mTravel: 34
}
