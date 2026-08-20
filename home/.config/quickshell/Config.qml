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

    // ───────── tipografía ─────────
    property alias fontUI: opts.fontUI
    property alias clockSize: opts.clockSize

    readonly property var fontChoices: [
        "Adwaita Sans", "Google Sans Flex", "Rubik", "Red Hat Text",
        "Space Grotesk", "Readex Pro", "Noto Sans"
    ]

    function save() { file.writeAdapter(); }

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
        // favApps NO se toca a propósito: "restaurar valores" es para la
        // apariencia, y los favoritos son trabajo tuyo, no un ajuste por defecto.
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

            property string fontUI: "Adwaita Sans"
            property int clockSize: 17

            property list<string> favApps: []
        }
    }
}
