// NotchLayer.qml — one "face" of the notch (rest, hover, OSD, panel...).
//
// This is where it is decided how EVERYTHING that lives inside the notch comes
// in and goes out: there are eleven faces and all of them pass through this
// file. Changing this changes the whole shell.
//
// Two ideas, and neither of them is "a prettier curve":
//
// 1. THE FACE COMES IN FROM THE SIDE OF THE BUTTON THAT SUMMONS IT. The
//    launcher is born on the left because its button is on the left; the
//    control panel and the network, bluetooth and power panels are born on the
//    right, which is where their icons are. The ambient stuff (clock, music,
//    notifications) does not travel: it grows in the centre, because you did
//    not ask for it from anywhere.
//    Since the notch CLIPS (clip in TopShell), the content travels inside the
//    slot: you do not see it appear, you see it arrive.
//
// 2. SCALE AND TRAVEL RUN ON A SPRING, not on a fixed duration. A spring keeps
//    its velocity, so if you open a panel while another one is still leaving,
//    the second one CONTINUES the movement of the first instead of cutting it
//    off and starting from zero. That is exactly the moment a shell gives
//    itself away, and it is where it used to feel rubbery.
//
// Opacity stays on a bézier on purpose: a spring on opacity would overshoot 1
// and cause a flicker. And it keeps the offset (mStagger) that avoids the smear
// of two faces visible at once — the new one starts coming in when the old one
// has already gone.
import QtQuick

Item {
    id: layer
    property bool active: false

    // -1 born on the left · 0 grows in the centre · +1 born on the right
    property int origin: 0

    visible: opacity > 0.01
    transformOrigin: Item.Center

    opacity: active ? 1 : 0
    Behavior on opacity {
        SequentialAnimation {
            PauseAnimation { duration: layer.active ? Appearance.mStagger : 0 }
            NumberAnimation {
                duration: layer.active ? Appearance.mIn : Appearance.mOut
                easing.type: layer.active ? Easing.OutCubic : Easing.InQuad
            }
        }
    }

    scale: active ? 1 : Appearance.mScaleFrom
    Behavior on scale {
        SequentialAnimation {
            PauseAnimation { duration: layer.active ? Appearance.mStagger : 0 }
            SpringAnimation {
                spring: Appearance.sprPanel
                damping: Appearance.dmpPanel
                epsilon: Appearance.eppScale
            }
        }
    }

    // The sideways travel. On the way out it goes back towards its side, so a
    // face withdraws the way it came: the gesture reads the same going as coming.
    property real slide: active ? 0 : origin * Appearance.mTravel
    Behavior on slide {
        SequentialAnimation {
            PauseAnimation { duration: layer.active ? Appearance.mStagger : 0 }
            SpringAnimation {
                spring: Appearance.sprPanel
                damping: Appearance.dmpPanel
                epsilon: Appearance.eppPx
            }
        }
    }
    transform: Translate { x: layer.slide }
}
