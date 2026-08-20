// NotchLayer.qml — una "cara" del notch (reposo, hover, OSD, panel...).
//
// Aquí se decide cómo entra y sale TODO lo que vive dentro del notch: son once
// caras y todas cruzan por este fichero. Cambiar esto cambia el shell entero.
//
// Dos ideas, y ninguna es "una curva más bonita":
//
// 1. LA CARA ENTRA POR EL LADO DEL BOTÓN QUE LA INVOCA. El launcher nace a la
//    izquierda porque su botón está a la izquierda; el panel de control y los
//    de red, bluetooth y apagado nacen a la derecha, que es donde están sus
//    iconos. Lo ambiental (reloj, música, notificaciones) no viaja: crece en el
//    centro, porque no lo has pedido tú desde ningún sitio.
//    Como el notch RECORTA (clip en TopShell), el contenido viaja por dentro de
//    la ranura: no lo ves aparecer, lo ves llegar.
//
// 2. LA ESCALA Y EL VIAJE VAN CON MUELLE, no con duración fija. Un muelle
//    guarda velocidad, así que si abres un panel mientras otro aún se está
//    yendo, el segundo CONTINÚA el movimiento del primero en vez de cortarlo y
//    empezar de cero. Es justo el momento en que un shell se delata, y es
//    donde antes se sentía de goma.
//
// La opacidad se queda en bézier a propósito: un muelle en la opacidad se
// pasaría de 1 y provocaría un parpadeo. Y conserva el desfase (mStagger) que
// evita el borrón de dos caras visibles a la vez — lo nuevo empieza a entrar
// cuando lo viejo ya se ha ido.
import QtQuick

Item {
    id: layer
    property bool active: false

    // -1 nace a la izquierda · 0 crece en el centro · +1 nace a la derecha
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

    // El viaje lateral. Al salir vuelve hacia su lado, así que una cara se
    // retira por donde vino: el gesto se lee igual de ida que de vuelta.
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
