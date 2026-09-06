// Config.qml — ajustes persistentes del rice.
//
// Todo lo que hasta ahora eran constantes cocidas en TopShell/ShellState vive
// aquí y se guarda en ~/.config/quickshell-rice.json. La app de Ajustes escribe
// sobre esto y la barra y el notch reaccionan en vivo.
//
// OJO con la ruta: el fichero va FUERA de ~/.config/quickshell/ a propósito.
// Quickshell vigila su directorio de configuración para recargar en caliente, y
// guardar ahí dentro cada vez que mueves un slider dispararía una recarga por
// cada píxel.
pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: root

    // ───────── idioma ─────────
    // "es" | "en". Lo lee I18n y de ahí cuelga toda la interfaz. El instalador
    // lo deja escrito según lo que elijas al instalar (./install.sh --lang en).
    property alias language: opts.language

    // ───────── notch ─────────
    // "notch" = isla pegada al borde con esquinas invertidas (MacBook).
    // "island" = píldora flotante despegada del borde (Dynamic Island).
    property alias notchStyle: opts.notchStyle
    property alias islandGap: opts.islandGap
    readonly property bool island: opts.notchStyle === "island"

    property alias notchColor: opts.notchColor
    property alias bandH: opts.bandH            // alto de la banda = alto del notch en reposo
    property alias flare: opts.flare            // radio de la esquina superior invertida
    property alias roundMax: opts.roundMax      // radio inferior máximo
    property alias idleW: opts.idleW            // ancho en reposo para la HORA SOLA; crece si activas fecha o batería
    property alias hoverDelay: opts.hoverDelay  // ms antes de abrir el "peek"
    property alias showDate: opts.showDate
    property alias showBattery: opts.showBattery
    property alias reserveSpace: opts.reserveSpace

    // ───────── barra ─────────
    property alias scrimAlpha: opts.scrimAlpha  // velo bajo la barra (0 = transparente)
    property alias sideMargin: opts.sideMargin
    property alias showArch: opts.showArch
    property alias showWorkspaces: opts.showWorkspaces
    property alias showAppName: opts.showAppName
    property alias showTray: opts.showTray

    // ───────── lanzador ─────────
    // Favoritos, por `id` de entrada .desktop y EN ORDEN: la posición es lo que
    // el usuario coloca arrastrando, así que la lista es el dato, no un conjunto.
    property alias favApps: opts.favApps

    // ───────── efectos del compositor ─────────
    // Estos dos no son del shell: son de Hyprland. Se guardan aquí igual que el
    // resto para que Ajustes siga siendo un solo sitio, pero llegar hasta
    // Hyprland es harina de otro costal — ver applyEffects() más abajo.
    property alias motionBlur: opts.motionBlur
    property alias motionBlurSamples: opts.motionBlurSamples

    // ───────── tipografía ─────────
    property alias fontUI: opts.fontUI
    property alias clockSize: opts.clockSize

    readonly property var fontChoices: [
        "Adwaita Sans", "Google Sans Flex", "Rubik", "Red Hat Text",
        "Space Grotesk", "Readex Pro", "Noto Sans"
    ]

    function save() { file.writeAdapter(); }

    // Hyprland no lee quickshell-rice.json, así que el ajuste tiene que viajar
    // por dos caminos, y hacen falta LOS DOS:
    //
    //   hyprctl eval    lo aplica en caliente, para que se note al soltar el
    //                   interruptor y no al reiniciar.
    //   efectos.lua     lo deja escrito. hyprland.lua lo carga al final con un
    //                   dofile protegido, así que sobrevive a `hyprctl reload`
    //                   —que releería la config y se llevaría por delante el
    //                   eval— y a reiniciar la sesión.
    //
    // El fichero se escribe SIEMPRE, también si el eval falla: si Hyprland no
    // está escuchando, el ajuste no se pierde, solo tarda hasta el siguiente
    // arranque. Al revés no valdría.
    // El rebote vive aquí y no en la interfaz a propósito: el deslizador de
    // muestras emite en CADA píxel del arrastre y no tiene señal de "soltado",
    // así que sin esto un arrastre lanza cien procesos y cien reescrituras del
    // fichero. Quien llame no tiene que saberlo — llama y ya.
    function applyEffects() { debounce.restart(); }

    Timer {
        id: debounce
        interval: 180
        onTriggered: {
            const lua = "hl.config({ decoration = { motion_blur = { enabled = "
                      + (opts.motionBlur ? "true" : "false")
                      + ", samples = " + opts.motionBlurSamples + " } } })";
            // Los dos valores son un bool y un int del JsonAdapter, nunca texto
            // libre del usuario, así que estas comillas simples no las puede
            // romper nadie escribiendo.
            fx.command = ["sh", "-c",
                "hyprctl eval '" + lua + "' >/dev/null 2>&1; "
                + "printf '%s\\n' "
                + "'-- Generado por Ajustes > Apariencia > Efectos. Se reescribe solo: no lo edites a mano.' "
                + "'" + lua + "' > \"$HOME/.config/hypr/efectos.lua\""];
            fx.running = true;
        }
    }

    Process { id: fx }

    // Al arrancar el shell no hay que aplicar nada: hyprland.lua ya ha leído
    // efectos.lua. Esto es solo para cuando el JSON se toca por fuera —a mano,
    // o por el instalador— y los dos ficheros se han ido separando.
    Component.onCompleted: root.applyEffects()

    function reset() {
        opts.notchStyle = "notch"; opts.islandGap = 4;
        opts.notchColor = "#000000";
        opts.bandH = 32; opts.flare = 13; opts.roundMax = 30; opts.idleW = 140;
        opts.hoverDelay = 240;
        opts.showDate = false; opts.showBattery = false; opts.reserveSpace = true;
        opts.scrimAlpha = 0.0; opts.sideMargin = 16;
        opts.showArch = true; opts.showWorkspaces = true;
        opts.showAppName = true; opts.showTray = true;
        opts.fontUI = "Adwaita Sans"; opts.clockSize = 17;
        opts.motionBlur = true; opts.motionBlurSamples = 7;
        root.applyEffects();   // este no se entera solo: hay que empujarlo a Hyprland
        // favApps y language NO se tocan a propósito: "restaurar valores" es
        // para la apariencia, y ni los favoritos ni el idioma en el que lees la
        // pantalla son un ajuste por defecto que convenga devolver.
        root.save();
    }

    FileView {
        id: file
        path: Quickshell.env("HOME") + "/.config/quickshell-rice.json"
        watchChanges: true
        onFileChanged: reload()
        onAdapterUpdated: writeAdapter()
        // Primera vez: no existe -> se crea con los valores por defecto.
        onLoadFailed: function (error) {
            if (error === FileViewError.FileNotFound) writeAdapter();
        }

        JsonAdapter {
            id: opts

            property string language: "es"

            property string notchStyle: "notch"
            property int islandGap: 4
            property string notchColor: "#000000"
            property int bandH: 32
            property int flare: 13
            property int roundMax: 30
            property int idleW: 140
            property int hoverDelay: 240
            property bool showDate: false   // en reposo solo hora y batería; la fecha entera sale al pasar el ratón
            property bool showBattery: false
            property bool reserveSpace: true

            property real scrimAlpha: 0.0
            property int sideMargin: 16
            property bool showArch: true
            property bool showWorkspaces: true
            property bool showAppName: true
            property bool showTray: true

            // Encendido de fábrica: es de las pocas cosas del rice que se ven
            // sin tocar nada. El interruptor está para el día que la batería
            // importe más que la estela.
            property bool motionBlur: true
            property int motionBlurSamples: 7

            property string fontUI: "Adwaita Sans"
            property int clockSize: 17

            property list<string> favApps: []
        }
    }
}
