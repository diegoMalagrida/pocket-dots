// Launch ranking and its local history, inspired by Impasto's LauncherSection.
// https://github.com/andreumassanet/impasto — GPL-3.0.
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Flickable {
    id: root
    property string note: I18n.tr("Solo se recuerdan las aplicaciones que abres desde el lanzador.")
    readonly property int matchCount: orderCard.visibleRows
    property bool clearing: false
    contentHeight: col.implicitHeight + 34
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded; width: 5 }
    onVisibleChanged: { clearing = false; if (visible) contentY = 0; }
    Timer { id: disarm; interval: 2500; onTriggered: root.clearing = false }
    ColumnLayout {
        id: col
        width: root.width - 48
        x: 24; y: 16
        spacing: 10
        SettingsControls.Card_ {
            id: orderCard
            title: I18n.tr("Aplicaciones")
            SettingsControls.Row_ {
                label: I18n.tr("Aprender de mi uso")
                hint: I18n.tr("Las aplicaciones habituales aparecen antes. Al buscar, las coincidencias exactas tienen prioridad; el uso antiguo pierde peso con el tiempo.")
                SettingsControls.Switch_ {
                    checked: Config.learnLauncher
                    onToggled: function (value) { Config.learnLauncher = value; }
                }
            }
            SettingsControls.Action_ {
                label: root.clearing ? I18n.tr("Confirmar") : I18n.tr("Borrar el aprendizaje")
                hint: I18n.tr("Reinicia el orden aprendido. Conserva tus favoritos y el historial del portapapeles.")
                value: I18n.tr("{0} aplicaciones", LauncherUsage.count)
                icon: "󰆴"
                onTriggered: {
                    if (!root.clearing) { root.clearing = true; disarm.restart(); return; }
                    LauncherUsage.clear(); root.clearing = false; disarm.stop();
                }
            }
        }
        SettingsControls.Note_ {
            text: I18n.tr("Los favoritos mantienen el orden que tú eliges. Puedes desactivar el aprendizaje para recuperar el orden alfabético.")
        }
    }
}
