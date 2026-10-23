// ShinySparkle.qml — the burst of sparkles for a shiny.
//
// A shiny turns up 1 time in 64: it is THE rare thing that can happen to you in
// the team, and until today it was announced with a 9 px ✦ in a row of the
// panel. This is the moment it was missing.
//
// Three decisions, and none of them is "more particles":
//
// 1. IT IS AN EVENT, NOT A LOOP. It has a beginning and an end: the sparks
//    leave the centre, fade out and nothing is left. Law 7 of the motion
//    language forbids things that move just because, and a constellation
//    twinkling forever on top of the sprite would be exactly that. Here it
//    fires and it is over.
//
// 2. NO QtQuick.Particles. A particle system brings its own timing engine
//    —lifetimes, emitters, bursts per second— and that engine knows nothing
//    about this house's duration scale. Fifteen Items with ordinary animations
//    CAN speak in 130/210/320/440, which is the only way for the sparkle to
//    feel like a sibling of the rest of the shell and not a bolted-on plugin.
//
// 3. THE BOUNCE ONLY ON THE SCALE. The sparks MOVE outwards, so their travel
//    runs on OutCubic and lands without overshooting (law 5); what overshoots
//    a hair is the size of the glyph, which has no edge to show.
//
// The idea comes from ShinySparkle.qml in omarchy-lock-pokemon (MIT). From
// there we keep the shape of the glyph —two crossed diamonds, which at 13 px
// reads as a sparkle and not as a dot— and nothing else: there the durations
// are 900/160/340 and two sparks stay twinkling in a loop forever. Here the
// numbers come from Appearance.qml's motion scale and the burst ends.
import QtQuick

Item {
    id: raiz

    // The trigger. Bumping this number fires a burst; a counter is used rather
    // than a `bool activo` because two shinies in a row (ShellState's queue) have
    // to be able to relaunch the same component without going through false
    // first, which is a frame in which nothing would be seen.
    property int disparo: 0

    // Two alternating tones. The accent comes from pywal, so the burst changes
    // colour with the wallpaper like everything else; the second is almost white
    // so the sparks also read over a dark accent.
    property color tono: Colors.accent
    property color tono2: Colors.fg

    property int chispas: 15
    property int anillos: 3       // outgoing waves, offset by one mStagger
    property int tam: 14          // side of the glyph, in px

    Repeater {
        model: raiz.chispas

        delegate: Item {
            id: chispa
            required property int index

            readonly property int anillo: index % raiz.anillos

            // The angle and the reach are recalculated ON EVERY burst because the
            // expression reads `raiz.disparo`: without that dependency QML would
            // evaluate Math.random() only once, when the delegate is created, and the
            // hundred bursts after it would be carbon copies.
            readonly property real angulo: {
                raiz.disparo;
                return (index / raiz.chispas) * 2 * Math.PI + (Math.random() - 0.5) * 0.45;
            }
            // How much of its radius this spark travels. The reach is measured
            // separately in X and in Y —that is, an ellipse and not a circle—
            // because the box it is given is the one there is: on a notch face there
            // is width to spare and height in short supply, and a circle the size of
            // the width would spill out over the top while leaving the sides empty.
            readonly property real trecho: {
                raiz.disparo;
                return 0.55 + Math.random() * 0.45;
            }

            property real avance: 0   // 0 at the centre · 1 at the end of the trip

            width: 1
            height: 1
            x: raiz.width / 2 + Math.cos(angulo) * raiz.width * 0.5 * trecho * avance
            y: raiz.height / 2 + Math.sin(angulo) * raiz.height * 0.5 * trecho * avance

            // The glyph: four points made with two crossed bars plus another two
            // at 45°. A star drawn with a Canvas would cost one texture per spark;
            // with four 2 px rectangles the result at this size is the same and the
            // GPU paints it without thinking.
            Item {
                id: glifo
                anchors.centerIn: parent
                width: raiz.tam
                height: raiz.tam
                opacity: 0            // at rest there is nothing to see
                scale: 0.4
                // two out of three take the accent; the third, almost white
                readonly property color color: (chispa.index % 3 === 2) ? raiz.tono2 : raiz.tono

                Rectangle {
                    anchors.centerIn: parent
                    width: parent.width; height: 2; radius: 1
                    color: glifo.color
                }
                Rectangle {
                    anchors.centerIn: parent
                    width: 2; height: parent.height; radius: 1
                    color: glifo.color
                }
                Rectangle {
                    anchors.centerIn: parent
                    width: parent.width * 0.66; height: 2; radius: 1
                    color: glifo.color
                    rotation: 45
                }
                Rectangle {
                    anchors.centerIn: parent
                    width: 2; height: parent.height * 0.66; radius: 1
                    color: glifo.color
                    rotation: 45
                }
            }

            // The whole life of a spark: it waits for its wave, goes out, and fades.
            // With three waves (220 of offset) and a spark that lives 560, the whole
            // burst fits in 780 ms: the time it takes to read an accent, without
            // turning into a circus act.
            SequentialAnimation {
                id: vuelo
                PauseAnimation { duration: chispa.anillo * Appearance.mStagger }
                ParallelAnimation {
                    // SHAPE: the trip. No bounce, since it is a displacement.
                    NumberAnimation {
                        target: chispa; property: "avance"
                        from: 0; to: 1
                        duration: Appearance.mShape
                        easing.type: Easing.OutCubic
                    }
                    // PANEL coming in: here yes, because a scale shows no edge
                    // when it overshoots (law 5).
                    NumberAnimation {
                        target: glifo; property: "scale"
                        from: 0.4; to: 1
                        duration: Appearance.mInScale
                        easing.type: Easing.OutBack
                        easing.overshoot: Appearance.mInOvershoot
                    }
                    // The spin goes with the trip and stops with it: a quarter
                    // turn is enough for the star not to look like a stamp.
                    NumberAnimation {
                        target: glifo; property: "rotation"
                        from: 0; to: 90
                        duration: Appearance.mShape
                        easing.type: Easing.OutCubic
                    }
                    // Lights up at RESPONSE speed (a spark does not fade in, it
                    // appears), holds for as long as a CONTENT lasts and leaves at
                    // SHAPE-out speed: the fade-out is the only part anyone really
                    // watches.
                    SequentialAnimation {
                        NumberAnimation {
                            target: glifo; property: "opacity"
                            to: 1; duration: Appearance.mQuick
                            easing.type: Easing.OutQuad
                        }
                        PauseAnimation { duration: Appearance.mIn }
                        NumberAnimation {
                            target: glifo; property: "opacity"
                            to: 0; duration: Appearance.mOutShape
                            easing.type: Easing.OutQuad
                        }
                    }
                }
            }

            Connections {
                target: raiz
                function onDisparoChanged() { vuelo.restart(); }
            }
        }
    }

    // The flash at the centre: the ring of light the sparks come out of.
    // Without it the burst looks as if it comes from the outside in, because
    // the first thing the eye sees is the sparks already apart from the centre.
    //
    // It has to OVERTAKE the sparks and leave the box: tried with the ring
    // stopping at 1.35 of its size, and at that distance it is not a wave, it is
    // a ring around the sprite —that is, a state («this is selected») instead of
    // an event. What makes it a wave is that it leaves completely.
    Rectangle {
        id: fogonazo
        anchors.centerIn: parent
        // 0.45 of the short side and no more: at 1.8 scale the ring already
        // measures almost as much as the box, and beyond that it spills over the
        // top of the notch face —which clips— and what you see is a circle cut
        // by a straight line. A clipped ring does not look like a wave, it looks
        // like a bug.
        width: Math.min(raiz.width, raiz.height) * 0.45
        height: width
        radius: width / 2
        color: "transparent"
        border.width: 2
        border.color: raiz.tono
        opacity: 0
        scale: 0.4

        ParallelAnimation {
            id: destello
            NumberAnimation {
                target: fogonazo; property: "scale"
                from: 0.5; to: 1.8
                duration: Appearance.mShape
                easing.type: Easing.OutCubic
            }
            SequentialAnimation {
                NumberAnimation {
                    target: fogonazo; property: "opacity"
                    to: 0.55; duration: Appearance.mQuick
                    easing.type: Easing.OutQuad
                }
                NumberAnimation {
                    target: fogonazo; property: "opacity"
                    to: 0; duration: Appearance.mShape
                    easing.type: Easing.OutQuad
                }
            }
        }

        Connections {
            target: raiz
            function onDisparoChanged() { destello.restart(); }
        }
    }
}
