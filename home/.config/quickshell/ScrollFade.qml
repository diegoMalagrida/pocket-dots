import QtQuick

// The edge of a scrolling list: the content is not cut off, it fades out.
//
// The shell's lists use `clip: true`, so whatever sticks out is cut along a
// straight line: half a letter at the top, half a row at the bottom. That is
// not just ugly -- it reads as the end of the list. A clean cut does not tell
// "it ends here" apart from "it carries on and does not fit", which are the
// two things you need to know when you look at a list.
//
// The HIG give it a name of its own: "Optimize for legibility when content
// scrolls beneath controls. Scroll views offer a scrollEdgeEffectStyle that
// helps maintain sufficient legibility and contrast for controls by obscuring
// content that scrolls beneath them" (adopting-liquid-glass.md). In the
// system's bars it comes as standard; here it has to be added.
//
// It is done with a gradient from the panel colour to transparent, not with a
// blur: the panel is opaque, so the gradient IS the fade, and it costs one
// rectangle instead of a shader pass. On a laptop with an iGPU that difference
// is battery.
//
// And it appears ONLY when there is something to reveal: at the very top, the
// top gradient does not exist. That way the edge also informs -- if you see
// mist, there is more. Just as the HIG ask the material to say where you are,
// not to decorate.
//
//     ScrollFade { lista: myListView; tinta: Colors.bg }
//
Item {
    id: root

    // The Flickable/ListView it sticks to. It anchors itself.
    property Flickable lista: null
    // The colour it fades into: the background of the panel behind it.
    property color tinta: Colors.bg
    // Height of the mist. 14 = gapL, just enough to swallow a line of small
    // text without eating a whole row.
    property int alto: Appearance.gapL

    anchors.fill: lista
    // Above the content, but with no MouseArea: there is nothing to capture,
    // so the list can still be dragged through the mist.
    z: 10
    visible: lista !== null

    // How much content is left outside on each side, in pixels.
    readonly property real arriba: lista ? Math.max(0, lista.contentY) : 0
    readonly property real abajo: lista
        ? Math.max(0, lista.contentHeight - lista.contentY - lista.height) : 0

    Rectangle {
        anchors { left: parent.left; right: parent.right; top: parent.top }
        height: root.alto
        // Proportional to what is hidden and capped at 1: over the first pixels
        // of scroll the mist comes in by itself, with no need to animate
        // anything. Animating it would mean moving because of something that is
        // already moving (law 9: one animation, one owner).
        opacity: Math.min(1, root.arriba / root.alto)
        gradient: Gradient {
            GradientStop { position: 0.0; color: root.tinta }
            GradientStop { position: 1.0; color: Qt.rgba(root.tinta.r, root.tinta.g, root.tinta.b, 0) }
        }
    }

    Rectangle {
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        height: root.alto
        opacity: Math.min(1, root.abajo / root.alto)
        gradient: Gradient {
            GradientStop { position: 0.0; color: Qt.rgba(root.tinta.r, root.tinta.g, root.tinta.b, 0) }
            GradientStop { position: 1.0; color: root.tinta }
        }
    }
}
