pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// Lee la paleta pywal (~/.cache/wal/colors.json) y se actualiza en vivo
// cada vez que cambias de fondo (set-wallpaper.sh regenera ese archivo).
Singleton {
    id: root

    // Fallbacks (gruvbox-ish) por si aún no hay pywal generado
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

    // Colores SEMÁNTICOS: fijos a propósito. c1..c5 salen de pywal y cambian con
    // el fondo (color2 no tiene por qué ser verde), así que no valen para decir
    // "cargando" o "crítico" — con según qué fondo la batería cargando salía
    // roja y parecía una alarma.
    readonly property color ok:   "#6dbd7a"
    readonly property color warn: "#e0a458"
    readonly property color crit: "#e05c5c"

    // Ruta del fondo de pantalla actual. Vive aquí y no en Config porque el que
    // manda es pywal: colors.json trae la ruta del fondo del que salió la paleta,
    // así que color y fondo NUNCA se pueden desincronizar. Guardarla aparte en el
    // JSON del rice sería tener dos fuentes de verdad para lo mismo.
    // La usa el overview para pintar cada escritorio.
    property string wallpaper: ""

    // ══════════════════════════════════════════════════════════════════════
    //  TINTA PARA LO QUE FLOTA SOBRE EL FONDO DE PANTALLA
    //
    //  La barra no tiene superficie propia —el velo va a 0 por defecto—, así
    //  que sus cuerpos se pintan DIRECTAMENTE sobre el wallpaper. Y como
    //  pywal saca la paleta de ese mismo wallpaper, con un fondo monocromo el
    //  acento vuelve teñido del mismo tono que el fondo y con una luminosidad
    //  parecida: se retematiza bien y aun así no se ve.
    //
    //  Medido sobre el indicador de escritorios con un fondo azul: la píldora
    //  activa (#366ca3) estaba a 1.6:1 de los puntos inactivos, y los puntos
    //  —blanco al 50 %— eran LO MÁS CLARO del grupo. O sea, lo apagado
    //  destacaba más que lo encendido, y encima la píldora salía más oscura
    //  que trozos del propio fondo.
    //
    //  Se mide contra `wallStrip`, que es un trozo DE VERDAD del wallpaper
    //  (ver más abajo), no contra el fondo de pywal. Y se resuelve así:
    //    · activo   → 3.5:1 contra la franja. Por encima del 3:1 que pide un
    //      elemento gráfico, porque es EL indicador.
    //    · inactivo → justo en el PUNTO MEDIO entre la franja y el activo, o
    //      sea a la raíz del contraste de este (~1.9:1 por cada lado). Un punto
    //      medio no puede fundirse ni con el fondo ni con la píldora, que son
    //      las dos maneras de perderse; y como sale de la píldora, la jerarquía
    //      se cumple sola sin ajustar números a mano.
    //
    //  Solo se mueve la LUMINOSIDAD: el tono sigue siendo el de pywal, así que
    //  el retematizado se conserva entero.
    // ══════════════════════════════════════════════════════════════════════
    readonly property bool darkWall: wallStrip.hslLightness < 0.5

    readonly property color onWallAccent: {
        const h = accent.hslHue < 0 ? 0 : accent.hslHue;
        // Un acento gris es gris: forzarle saturación le inventaría un tono
        // (con una paleta acromática el indicador salía rojo de la nada).
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

    // OPACO a propósito. Con tinta translúcida el color final lo acababa
    // poniendo el wallpaper: los mismos puntos medían 0.19 o 0.31 de luminancia
    // según el trozo de fondo que les tocara detrás, así que sobre una zona
    // clara volvían a fundirse con ella. Un cuerpo opaco se calcula una vez y
    // se cumple siempre.
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

    // El color REAL de la franja de arriba del wallpaper, que es lo que hay
    // DETRÁS de los cuerpos de la barra. Lo muestrea set-wallpaper.sh con
    // magick; si ese fichero no existe (o magick falló) esto se queda en el
    // fondo de pywal, que es lo que había antes.
    property color wallStrip: bg
    FileView {
        id: stripFile
        path: Quickshell.env("HOME") + "/.cache/wal/bar-strip.txt"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            const t = stripFile.text().trim();
            if (/^#[0-9a-fA-F]{6}$/.test(t)) root.wallStrip = t;
        }
    }

    function _lin(x) { return x <= 0.03928 ? x / 12.92 : Math.pow((x + 0.055) / 1.055, 2.4); }
    function luminance(c) { return 0.2126 * _lin(c.r) + 0.7152 * _lin(c.g) + 0.0722 * _lin(c.b); }
    // Contraste WCAG entre dos colores opacos, 1:1 (iguales) a 21:1 (negro/blanco).
    function contrast(a, b) {
        const x = luminance(a), y = luminance(b);
        return (Math.max(x, y) + 0.05) / (Math.min(x, y) + 0.05);
    }

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
            // "file://" explícito: Image lo pide como URL y una ruta suelta se
            // resolvería relativa al .qml, no a la raíz.
            if (j.wallpaper && String(j.wallpaper).length > 0)
                root.wallpaper = "file://" + j.wallpaper;
        } catch (e) { /* mantiene fallbacks */ }
    }
}
