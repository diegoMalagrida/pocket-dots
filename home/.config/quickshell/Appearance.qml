pragma Singleton
import Quickshell

// Sistema de diseño compartido — como el Appearance/Config de end-4 y caelestia.
// Todo (bar, dashboard, osd, notis...) usará estos tokens => se ve cohesivo.
Singleton {
    id: root
    // Mono + Nerd Font: la barra y TODO lo que pinte iconos (los glifos solo
    // existen en esta familia).
    readonly property string font: "JetBrains Mono Nerd Font"

    // Proporcional, solo para el texto de dentro del notch (reloj, fechas,
    // títulos). Una fecha en monoespaciada queda desmadejada: las letras se
    // separan igual que los dígitos y "mar 4 ago" parece texto de terminal.
    readonly property string fontUI: Config.fontUI   // se elige en Ajustes › Apariencia

    // tamaños de fuente
    readonly property int fsXS: 11
    readonly property int fsS:  12
    readonly property int fsM:  13
    readonly property int fsL:  16
    readonly property int fsXXL: 42

    // redondeos
    readonly property int radS: 10
    readonly property int radM: 14
    readonly property int radL: 18
    readonly property int radPill: 999

    // espaciado
    readonly property int gapS: 6
    readonly property int gapM: 10
    readonly property int gapL: 14
    readonly property int pad:  16

    // ══════════════════════════════════════════════════════════════════════
    //  MOVIMIENTO — la escala completa está en ~/.config/motion-language.md
    //  Esos mismos cuatro números los usa Hyprland (en decisegundos) para las
    //  ventanas y los escritorios. Si algo se mueve y no está aquí, es un bug.
    //
    //    RESPUESTA  130 / 130   hover, pulsación, color, un toggle
    //    CONTENIDO  210 / 110   texto e iconos dentro de algo que ya está
    //    PANEL      320 / 170   una superficie que aparece
    //    FORMA      440 / 220   cambia la forma, o se mueve algo entero
    //
    //  Los eventos son asimétricos (sale en la mitad de tiempo que entra);
    //  los estados, como el hover, son simétricos.
    // ══════════════════════════════════════════════════════════════════════
    readonly property int mQuick: 130        // RESPUESTA: hover, color, press, knobs
    readonly property int mIn: 210           // CONTENIDO entrando (opacidad)
    readonly property int mOut: 110          // CONTENIDO saliendo: la mitad
    readonly property int mInScale: 320      // PANEL entrando (escala, elástica)
    readonly property int mOutScale: 170     // PANEL saliendo
    readonly property int mShape: 440        // FORMA: el morfeo del notch
    readonly property int mOutShape: 220     // FORMA saliendo

    // Aliases de la primera hornada de tokens. Existían en paralelo a los m*
    // con números casi iguales (120/220/320) — dos vocabularios para lo mismo
    // era justo lo que hacía que nada acabara de encajar. Ahora apuntan a la
    // escala buena; se conservan para no romper código que aún los use.
    readonly property int animFast: mQuick
    readonly property int animMed:  mIn
    readonly property int animSlow: mInScale

    // ─── Curvas ───
    // El rebote está prohibido en los DESPLAZAMIENTOS: algo que se desliza y
    // se pasa enseña el borde de la pantalla y delata el truco. Pero en las
    // ESCALAS no hay nada que enseñar — una cosa que se infla pasándose un
    // pelo de tamaño solo se siente viva. Ahí es donde va el carácter.
    // (Corregido 2026-08-05: la ley 5 prohibía ambos y dejaba el sistema
    // coherente pero soso. Ver ~/.config/motion-language.md)
    readonly property real mOvershoot: 1.3    // el morfeo de la forma
    readonly property real mInOvershoot: 1.05 // contenido y paneles entrando
    readonly property real mScaleFrom: 0.90   // de dónde crece lo que entra

    // Excepcion deliberada a la escala: una barra de reproduccion no es un
    // acento, es una senal continua. Si la transicion dura EXACTAMENTE lo que
    // el intervalo de refresco, la barra avanza a velocidad constante y se lee
    // como movimiento continuo en vez de dar saltitos cada medio segundo. Por
    // eso va en lineal y por eso 500 no esta en la escala (ley 7).
    readonly property int mTick: 500

    // El stagger es lo que evita el borrón: lo nuevo empieza a entrar justo
    // cuando lo viejo ha terminado de salir, no a la vez.
    readonly property int mStagger: 110      // = mOut

    // ══════════════════════════════════════════════════════════════════════
    //  MUELLES — la diferencia de categoría, no un ajuste
    //
    //  Una curva bézier tiene duración fija: no sabe dónde está, solo cuánto
    //  le queda. Si le cambias el destino a media animación tiene que CORTAR y
    //  empezar de cero, y por eso el sistema se siente de goma cuando haces
    //  dos cosas seguidas rápido.
    //
    //  Un muelle tiene ESTADO: posición y velocidad. Cambias el destino a
    //  medio vuelo y continúa desde donde iba, a la velocidad que llevaba. No
    //  hay corte porque no hay nada que reiniciar. Eso es lo que separa algo
    //  que parece físico de algo que parece programado.
    //
    //  Lo interesante: esto en Hyprland exige migrar a Lua (0.55+), pero Qt lo
    //  tiene desde siempre y NADIE en el mundo rice lo usa. Aquí sí.
    //
    //  Tres caracteres, uno por escalón espacial. 'spring' tira (más = más
    //  rápido) y 'damping' frena (menos = más rebote).
    // ══════════════════════════════════════════════════════════════════════
    readonly property real sprTight: 5.2      // RESPUESTA: llega y se queda, casi sin pasarse
    readonly property real dmpTight: 0.58

    readonly property real sprPanel: 4.0      // PANEL: una superficie que aparece
    readonly property real dmpPanel: 0.42

    readonly property real sprLoose: 3.1      // FORMA: el morfeo, con recorrido de sobra
    readonly property real dmpLoose: 0.34

    // LATIGAZO: rigidez alta, para lo que tiene que SOLTARSE DE GOLPE despues
    // de haber estado agarrado -- el borde de detras del indicador. Se combina
    // con dmpPanel: con una amortiguacion mas baja el borde se queda oscilando
    // y la pildora late despues de llegar.
    readonly property real sprSquash: 6.5

    // epsilon = cuándo se da por quieto. En píxeles, un cuarto de píxel es
    // invisible y corta la cola muerta del muelle; en escala (0..1) hace falta
    // mil veces menos o se planta a un 1 % del destino, que a 300 px se ve.
    readonly property real eppPx: 0.25
    readonly property real eppScale: 0.001

    // Lo que recorre de lado una cara del notch al entrar. El notch recorta
    // (clip), así que el contenido viaja POR DENTRO de la ranura: no se ve
    // aparecer, se ve llegar.
    readonly property int mTravel: 34
}
