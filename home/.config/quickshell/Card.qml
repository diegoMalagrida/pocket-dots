import QtQuick

// A surface for grouping, with a genuinely raised background and a single
// hairline.
//
// It used to be `color: Colors.bgAlt`, and the comment promised a "raised
// background". It was not one: `bgAlt` comes from pywal's color0 and `bg` from
// special.background, and with today's palette they are the SAME colour
// (#132125, 1.00:1). So the card leaned entirely on a border of fg at 6 %,
// i.e. 1.2:1: for grouping, which is its only job, that was not enough.
//
// `Colors.surface1` is computed from the background with a guaranteed
// luminance delta, so it exists with any palette. It is the "elevated" set the
// HIG asks for in dark mode: "the elevated colors are brighter, making
// foreground interfaces appear to advance" (dark-mode.md).
Rectangle {
    radius: Appearance.radM
    color: Colors.surface1
    border.width: 1
    border.color: Colors.hairline
}
