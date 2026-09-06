// WallpaperPicker.qml — coverflow ilyamiro (cartas en paralelogramo / skew)
// sobre un FONDO INMERSIVO: el wallpaper seleccionado, difuminado y oscurecido,
// llena la pantalla y hace crossfade al navegar. Así el picker no se pelea con
// el escritorio/terminal que haya detrás y las cartas destacan limpias.
//
// Motor de máxima fluidez: cada RANURA es de ANCHO FIJO (cero relayout al
// desplazar) y la carta, de TAMAÑO FIJO, solo se anima con `scale`+`opacity`
// (función continua de su distancia al centro). Sin Behaviors que se
// desincronicen, sin re-decodificar y SIN capas de sombra por carta (eso
// mataba el rendimiento). La imagen interior es de tamaño fijo y siempre cubre
// el paralelogramo -> jamás esquinas cortadas.
//
// Las cartas NO leen los wallpapers originales, sino las miniaturas de 500 px
// que mantiene scripts/wall-thumbs.sh en ~/.cache/wallpaper-thumbs: descomprimir
// los originales (hasta 6 MB) para pintar una carta pequeña costaba ~12x más.
// Cada miniatura conserva el nombre completo del original más ".jpg", así que
// la ruta real se recupera quitando ese sufijo (ver originalOf).
//
// Contrato conservado: GlobalShortcut "wallpaper" y el script set-wallpaper.sh.
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Io
import QtQuick
import QtQuick.Effects
import Qt.labs.folderlistmodel

Scope {
    id: root
    property bool open: false
    readonly property string home: Quickshell.env("HOME")
    readonly property string wallsDir:  home + "/Pictures/wallpapers"
    readonly property string thumbsDir: home + "/.cache/wallpaper-thumbs"

    // "anime-9o9yw1.jpg.jpg" -> "~/Pictures/wallpapers/anime-9o9yw1.jpg"
    function originalOf(thumbName) { return root.wallsDir + "/" + String(thumbName).replace(/\.jpg$/, "") }
    function apply(thumbName) {
        Quickshell.execDetached([root.home + "/.config/hypr/set-wallpaper.sh", root.originalOf(thumbName)])
        root.open = false
    }

    // Refresca la caché de miniaturas: al arrancar la shell y cada vez que se
    // abre el picker. En caliente son ~30 ms (solo comprueba fechas).
    Process {
        id: thumbsProc
        command: ["bash", root.home + "/.config/quickshell/scripts/wall-thumbs.sh"]
        onExited: {
            // Si la caché aún no existía, el watcher del modelo no llega a verla
            // nacer y hay que reapuntarlo a mano una vez.
            if (wallModel.count === 0) { wallModel.folder = ""; wallModel.folder = "file://" + root.thumbsDir }
        }
    }
    function refreshThumbs() { thumbsProc.running = false; thumbsProc.running = true }
    Component.onCompleted: root.refreshThumbs()

    GlobalShortcut { name: "wallpaper"; description: "Wallpaper picker"; onPressed: root.open = !root.open }
    HyprlandFocusGrab { windows: [win]; active: root.open; onCleared: root.open = false }

    FolderListModel {
        id: wallModel
        folder: "file://" + root.thumbsDir
        nameFilters: ["*.jpg"]
        showDirs: false
        sortField: FolderListModel.Name
    }

    PanelWindow {
        id: win
        // Solo en la pantalla que estas mirando, no siempre en la primera.
        screen: ShellState.focusedScreen
        // Mapeada hasta que el fundido de salida termina: con visible ligado
        // solo a open, la ventana se desmapeaba en el mismo frame y la
        // animación de cierre no se veía nunca (el no_anim de hyprland.lua
        // confía en que este stage se funde solo).
        visible: root.open || stage.opacity > 0
        anchors { top: true; bottom: true; left: true; right: true }
        exclusiveZone: 0
        color: "transparent"
        WlrLayershell.layer: WlrLayer.Overlay
        // Exclusive solo mientras está abierto: durante los ~110 ms del
        // fundido de salida la ventana sigue mapeada y no debe retener nada.
        WlrLayershell.keyboardFocus: root.open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
        // Sin namespace no hay layerrule posible: es el asa por la que
        // Hyprland anima ESTA superficie y no todas por igual.
        WlrLayershell.namespace: "quickshell:wallpaper"

        Item {
            id: stage
            anchors.fill: parent
            focus: true
            opacity: root.open ? 1 : 0
            // Entrada 210/OutCubic; salida 110 ms (mOut) con InCubic, que es
            // la curva `sale`: acelera y no frena. Ley 3: lo que sale se va
            // en la mitad de tiempo.
            Behavior on opacity { NumberAnimation { duration: root.open ? Appearance.animMed : Appearance.mOut; easing.type: root.open ? Easing.OutCubic : Easing.InCubic } }

            Connections {
                target: root
                function onOpenChanged() {
                    if (!root.open) return
                    stage.forceActiveFocus()
                    root.refreshThumbs()
                }
            }

            Keys.onEscapePressed: root.open = false
            Keys.onLeftPressed:   carousel.decrementCurrentIndex()
            Keys.onRightPressed:  carousel.incrementCurrentIndex()
            Keys.onReturnPressed: carousel.applyCurrent()
            Keys.onEnterPressed:  carousel.applyCurrent()
            WheelHandler {
                onWheel: (e) => {
                    if (e.angleDelta.y > 0 || e.angleDelta.x > 0) carousel.decrementCurrentIndex()
                    else carousel.incrementCurrentIndex()
                }
            }

            // SIN FONDO: el picker flota transparente sobre el escritorio (sin
            // wallpaper difuminado ni velo). Las cartas son opacas y el cromo
            // lleva halo de sombra para leerse sobre cualquier fondo.
            // Clic en zona vacía cierra.
            MouseArea { anchors.fill: parent; z: -1; onClicked: root.open = false }

            // ----- Coverflow ilyamiro (cartas en paralelogramo / skew) -----
            ListView {
                id: carousel
                anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; verticalCenterOffset: 12 }
                height: 560
                orientation: ListView.Horizontal
                model: wallModel
                property real iw: 720                            // ancho base del hero (fijo)
                property real ih: 406                            // alto base del hero (~16:9, fijo)
                property real skew: -0.35
                property real bw: 3
                property real slotW: 360                         // paso de scroll FIJO
                property real sideBase: 0.56                     // escala del 1.er vecino
                readonly property real imgW: iw + ih * Math.abs(skew) + 12
                spacing: 0; clip: false; cacheBuffer: 2500
                highlightRangeMode: ListView.StrictlyEnforceRange
                preferredHighlightBegin: (width - slotW) / 2
                preferredHighlightEnd:   (width + slotW) / 2
                highlightMoveDuration: 420
                highlightMoveVelocity: 3000
                snapMode: ListView.SnapToItem
                boundsBehavior: Flickable.StopAtBounds
                maximumFlickVelocity: 6000

                function applyCurrent() {
                    if (currentIndex < 0 || wallModel.count <= currentIndex) return
                    root.apply(wallModel.get(currentIndex, "fileName"))
                }

                delegate: Item {
                    id: slot
                    width: carousel.slotW
                    height: carousel.height
                    // distancia continua al centro del viewport, en ranuras.
                    readonly property real d: (x + width / 2 - (carousel.contentX + carousel.width / 2)) / carousel.slotW
                    readonly property real ad: Math.abs(d)
                    // Escala: 1.0 en el centro (hero nítido a tamaño real) y baja
                    // suave hacia el fondo, simétrica a ambos lados.
                    readonly property real sc: ad <= 1
                        ? carousel.sideBase + (1 - carousel.sideBase) * Math.pow(1 - ad, 1.35)
                        : carousel.sideBase * Math.pow(0.86, ad - 1)
                    z: Math.round(100 - ad * 10)
                    opacity: Math.max(0, Math.min(1, 1.15 - 0.34 * ad))

                    Item {
                        id: card
                        anchors.centerIn: parent
                        width: carousel.iw
                        height: carousel.ih
                        scale: slot.sc                           // solo transform GPU
                        transformOrigin: Item.Center
                        // Cizalla referida al CENTRO vertical -> se centra sola.
                        transform: Matrix4x4 { matrix: Qt.matrix4x4(1, carousel.skew, 0, -carousel.skew * carousel.ih / 2,  0, 1, 0, 0,  0, 0, 1, 0,  0, 0, 0, 1) }

                        // Marco: base oscura + filo sutil.
                        Rectangle {
                            anchors.fill: parent
                            color: Colors.bg
                            border.width: 1
                            border.color: Qt.rgba(1, 1, 1, 0.14)
                        }
                        // Contenido recto (cizalla inversa) + PreserveAspectCrop.
                        // Tamaño y sourceSize FIJOS -> cubre siempre el
                        // paralelogramo (sin esquinas cortadas) y mismo encuadre.
                        Item {
                            anchors.fill: parent; anchors.margins: carousel.bw; clip: true
                            Image {
                                anchors.centerIn: parent
                                width: carousel.imgW
                                height: carousel.ih
                                fillMode: Image.PreserveAspectCrop
                                source: model.fileUrl
                                asynchronous: true; cache: true; mipmap: true
                                sourceSize: Qt.size(carousel.imgW, carousel.ih)
                                transform: Matrix4x4 { matrix: Qt.matrix4x4(1, -carousel.skew, 0, carousel.skew * carousel.ih / 2,  0, 1, 0, 0,  0, 0, 1, 0,  0, 0, 0, 1) }
                            }
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: slot.ad < 0.5 ? carousel.applyCurrent() : (carousel.currentIndex = index)
                        }
                    }
                }
            }

            // Estado vacío.
            StyledText {
                anchors.centerIn: parent
                visible: wallModel.count === 0
                text: I18n.tr("No hay wallpapers en {0}", "~/Pictures/wallpapers")
                color: "#fafafa"
                font.pixelSize: Appearance.fsL
                opacity: 0.85
                layer.enabled: true
                layer.effect: MultiEffect {
                    shadowEnabled: true
                    shadowColor: "#000000"
                    shadowBlur: 1.0
                    blurMax: 16
                    shadowVerticalOffset: 0
                }
            }
        }
    }
}
