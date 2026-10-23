// Named appearance snapshots inspired by Impasto's settings/ProfilesPart.qml.
// https://github.com/andreumassanet/impasto — GPL-3.0.
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "AppearanceProfiles.js" as Profiles

Flickable {
    id: root
    property string note: I18n.tr("Los perfiles guardan la forma, la barra, la tipografía y los efectos.")
    readonly property bool matches: ShellState.settingsMatch(I18n.tr("Perfiles"), root.note)
    readonly property int matchCount: (root.matches ? 1 : 0) + filtered.length
    readonly property var filtered: Config.appearanceProfiles.filter(p =>
        root.matches || ShellState.settingsMatch(p.name, root.note))
    property string confirming: ""
    property string status: ""
    contentHeight: col.implicitHeight + 34
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded; width: 5 }
    onVisibleChanged: { confirming = ""; status = ""; if (visible) contentY = 0; }
    Timer { id: disarm; interval: 2500; onTriggered: root.confirming = "" }

    function confirm(action) {
        if (root.confirming !== action) { root.confirming = action; disarm.restart(); return false; }
        root.confirming = ""; disarm.stop(); return true;
    }
    ColumnLayout {
        id: col
        width: root.width - 48
        x: 24; y: 16
        spacing: 12

        SettingsControls.Note_ {
            text: I18n.tr("Guarda tu apariencia actual y recupérala cuando quieras. El idioma, los favoritos y el fondo de pantalla se mantienen.")
        }
        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            TextField {
                id: name
                Layout.fillWidth: true
                placeholderText: I18n.tr("Nombre del perfil")
                maximumLength: 48
                color: Colors.label
                placeholderTextColor: Colors.label4
                font { family: Appearance.fontUI; pixelSize: Appearance.fsS }
                selectByMouse: true
                background: Rectangle { radius: Appearance.radS; color: Colors.fill3; border.color: name.activeFocus ? Colors.accent : Colors.hairline }
                onAccepted: save.clicked()
            }
            SettingsControls.Btn_ {
                id: save
                text: I18n.tr("Guardar actual")
                enabled: name.text.trim().length > 0
                opacity: enabled ? 1 : 0.45
                onClicked: {
                    if (Config.saveProfile(name.text)) { name.clear(); root.status = I18n.tr("Perfil guardado"); }
                }
            }
        }
        Text {
            Layout.fillWidth: true
            visible: root.status.length > 0
            text: root.status
            color: Colors.accentInk
            wrapMode: Text.WordWrap
            font { family: Appearance.fontUI; pixelSize: Appearance.fsS }
            lineHeight: Appearance.leading(Appearance.fsS)
            lineHeightMode: Text.FixedHeight
        }
        SettingsControls.Note_ {
            visible: Config.appearanceProfiles.length === 0
            text: I18n.tr("Aún no hay perfiles. Ponle un nombre a tu apariencia para guardar el primero.")
        }
        Repeater {
            model: root.filtered
            Rectangle {
                id: card
                required property var modelData
                // complete(), not validate(): with validate() a profile missing a
                // key gave null, and the line below drew it with `|| Config`,
                // i.e. with YOUR current look — implying that the profile was
                // identical to what you already have, with Apply greyed out and
                // no reason given. Now whatever is missing is filled with the
                // factory values and the thumbnail shows what the profile will
                // really do.
                readonly property var validValues: Profiles.complete(modelData.values)
                Layout.fillWidth: true
                implicitHeight: body.implicitHeight + 24
                radius: Appearance.radM
                color: Colors.surface1
                border.color: Colors.hairline
                ColumnLayout {
                    id: body
                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
                    spacing: 10
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 12
                        SettingsBarPreview {
                            Layout.preferredWidth: 112
                            Layout.preferredHeight: 64
                            compact: true
                            values: card.validValues || Config
                        }
                        TextField {
                            id: rename

                            // ESC MUST BE ABLE TO UNDO, AND IT COULD NOT.
                            //
                            // There was only onEditingFinished here. You typed half a
                            // name, changed your mind, pressed Esc... and Settings
                            // closed entirely AND ON TOP OF THAT saved the half-typed
                            // name, with no way to undo it.
                            //
                            // The mechanism is not what it seems, and it was measured
                            // with qmltestrunner: the TextField does not consume
                            // Escape, it bubbles up to the Item at
                            // SettingsWindow.qml:221-223 and closes the window; but
                            // hiding it does NOT emit editingFinished nor take focus
                            // away from the field. The commit comes later, when
                            // SettingsWindow:204-206 calls search.forceActiveFocus()
                            // on showing it again and steals focus from the stale
                            // field. The delegate is still alive because the sections
                            // are not in a Loader (:603-608).
                            //
                            // That is why the flag has to survive the close: accepting
                            // the event is not enough. It is impasto's guard
                            // (settings/ProfilesPart.qml:209-219).
                            property bool leaving: false

                            Layout.fillWidth: true
                            text: card.modelData.name
                            maximumLength: 48
                            selectByMouse: true
                            color: Colors.label
                            font { family: Appearance.fontUI; pixelSize: 14; weight: Font.Medium }
                            background: Rectangle { radius: 8; color: rename.activeFocus ? Colors.fill2 : "transparent" }
                            onEditingFinished: {
                                if (rename.leaving) {
                                    rename.leaving = false;
                                    text = card.modelData.name;   // really undo
                                    return;
                                }
                                if (!Config.changeProfile(card.modelData.id, text, false)) text = card.modelData.name;
                            }
                            // The event is allowed to bubble on purpose: closing
                            // Settings with Esc is what you expect. What you do not
                            // expect is that it also saves.
                            Keys.onEscapePressed: function (event) {
                                rename.leaving = true;
                                rename.text = card.modelData.name;
                                event.accepted = false;
                            }
                        }
                        SettingsControls.Btn_ {
                            text: I18n.tr("Aplicar")
                            enabled: !!card.validValues
                            onClicked: {
                                if (Config.applyProfile(card.modelData.values))
                                    root.status = I18n.tr("Perfil aplicado: {0}", card.modelData.name);
                            }
                        }
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        SettingsControls.Btn_ {
                            text: root.confirming === "update:" + card.modelData.id ? I18n.tr("Confirmar") : I18n.tr("Actualizar con el aspecto actual")
                            onClicked: {
                                if (root.confirm("update:" + card.modelData.id)) {
                                    Config.changeProfile(card.modelData.id, card.modelData.name, true);
                                    root.status = I18n.tr("Perfil actualizado");
                                }
                            }
                        }
                        Item { Layout.fillWidth: true }
                        SettingsControls.Btn_ {
                            text: root.confirming === "delete:" + card.modelData.id ? I18n.tr("Confirmar") : I18n.tr("Eliminar")
                            danger: true
                            onClicked: if (root.confirm("delete:" + card.modelData.id)) Config.removeProfile(card.modelData.id)
                        }
                    }
                }
            }
        }
    }
}
