// CalendarPanel.qml — cara de calendario desplegada DESDE el notch.
//
// Un mes y nada más: cabecera con mes/año y navegación, iniciales de los
// días de la semana según el locale (ShellState.loc.firstDayOfWeek), y
// rejilla fija de 6 filas × 7 columnas para que la altura del notch nunca
// pegue saltos al cambiar de mes. Hoy va marcado con Colors.accent.
// Es un calendario para mirarlo: ni notas, ni eventos, ni festivos.
import Quickshell
import QtQuick
import QtQuick.Layouts

Item {
    id: root

    readonly property bool active: ShellState.panel === "calendar"

    property int viewYear: ShellState.now.getFullYear()
    property int viewMonth: ShellState.now.getMonth()

    readonly property bool isCurrentMonth: root.viewYear === ShellState.now.getFullYear()
        && root.viewMonth === ShellState.now.getMonth()

    function goToToday() {
        root.viewYear = ShellState.now.getFullYear();
        root.viewMonth = ShellState.now.getMonth();
    }

    function prevMonth() {
        if (root.viewMonth === 0) {
            root.viewMonth = 11;
            root.viewYear--;
        } else {
            root.viewMonth--;
        }
    }

    function nextMonth() {
        if (root.viewMonth === 11) {
            root.viewMonth = 0;
            root.viewYear++;
        } else {
            root.viewMonth++;
        }
    }

    // Al abrir el panel volvemos siempre a hoy y tomamos el foco para
    // poder cerrar con Escape o cambiar de mes con las flechas del teclado.
    onActiveChanged: {
        if (root.active) {
            root.goToToday();
            keys.forceActiveFocus();
        }
    }

    // Absorbe clics en zonas vacías y añade navegación rápida de mes con la rueda
    MouseArea {
        anchors.fill: parent
        onWheel: function (w) {
            if (w.angleDelta.y > 0) root.prevMonth();
            else if (w.angleDelta.y < 0) root.nextMonth();
        }
    }

    Item {
        id: keys
        anchors.fill: parent
        focus: true
        Keys.onEscapePressed: ShellState.closePanel()
        Keys.onLeftPressed: root.prevMonth()
        Keys.onRightPressed: root.nextMonth()
        Keys.onReturnPressed: if (!root.isCurrentMonth) root.goToToday()
        Keys.onEnterPressed: if (!root.isCurrentMonth) root.goToToday()
    }

    // Rejilla fija de 42 celdas (6 semanas completas).
    // La primera columna sigue siempre a ShellState.loc.firstDayOfWeek.
    // Los días fuera del mes en curso se marcan como isCurrentMonth: false
    // para pintarlos atenuados.
    readonly property var gridCells: {
        const y = root.viewYear;
        const m = root.viewMonth;
        const firstDow = ShellState.loc.firstDayOfWeek;
        const now = ShellState.now;
        const todayY = now.getFullYear();
        const todayM = now.getMonth();
        const todayD = now.getDate();

        const firstOfMonth = new Date(y, m, 1).getDay();
        const leadDays = (firstOfMonth - firstDow + 7) % 7;

        const cells = [];
        for (let i = 0; i < 42; i++) {
            const d = new Date(y, m, 1 - leadDays + i);
            const cellY = d.getFullYear();
            const cellM = d.getMonth();
            const cellD = d.getDate();
            cells.push({
                day: cellD,
                isCurrentMonth: cellM === m,
                isToday: cellY === todayY && cellM === todayM && cellD === todayD
            });
        }
        return cells;
    }

    ColumnLayout {
        anchors {
            fill: parent
            leftMargin: 21
            rightMargin: 21
            topMargin: 20
            bottomMargin: 16
        }
        spacing: 0

        // ─────────────── cabecera: mes, año y controles ───────────────
        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 32
            spacing: 8

            // Al pinchar en el título cuando estás en otro mes, vuelve a hoy
            Text {
                text: ShellState.capitalize(new Date(root.viewYear, root.viewMonth, 1).toLocaleDateString(ShellState.loc, "MMMM yyyy"))
                color: "#ffffff"
                font.family: Appearance.fontUI
                font.pixelSize: 15
                font.weight: Font.DemiBold

                MouseArea {
                    anchors.fill: parent
                    cursorShape: !root.isCurrentMonth ? Qt.PointingHandCursor : Qt.ArrowCursor
                    enabled: !root.isCurrentMonth
                    onClicked: root.goToToday()
                }
            }

            Item { Layout.fillWidth: true }

            Row {
                Layout.alignment: Qt.AlignVCenter
                spacing: 6

                // Botón "Hoy": aparece solo al salir del mes actual para no dejar un botón inútil
                Rectangle {
                    id: todayBtn
                    visible: !root.isCurrentMonth
                    height: 26
                    width: todayLbl.implicitWidth + 16
                    radius: Appearance.radS
                    color: todayMa.pressed
                        ? Qt.rgba(Colors.accent.r, Colors.accent.g, Colors.accent.b, 0.35)
                        : todayMa.containsMouse
                        ? Qt.rgba(Colors.accent.r, Colors.accent.g, Colors.accent.b, 0.20)
                        : Qt.rgba(1, 1, 1, 0.07)
                    Behavior on color { ColorAnimation { duration: Appearance.mQuick } }
                    scale: todayMa.pressed ? 0.95 : 1
                    Behavior on scale { NumberAnimation { duration: Appearance.mQuick; easing.type: Easing.OutCubic } }

                    Text {
                        id: todayLbl
                        anchors.centerIn: parent
                        text: I18n.tr("Hoy")
                        color: Colors.accent
                        font.family: Appearance.fontUI
                        font.pixelSize: Appearance.fsXS
                        font.weight: Font.Medium
                    }

                    MouseArea {
                        id: todayMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.goToToday()
                    }
                }

                // Flecha mes anterior
                Rectangle {
                    id: prevBtn
                    width: 26
                    height: 26
                    radius: Appearance.radS
                    color: prevMa.pressed
                        ? Qt.rgba(1, 1, 1, 0.16)
                        : prevMa.containsMouse
                        ? Qt.rgba(1, 1, 1, 0.10)
                        : Qt.rgba(1, 1, 1, 0.05)
                    Behavior on color { ColorAnimation { duration: Appearance.mQuick } }
                    scale: prevMa.pressed ? 0.95 : 1
                    Behavior on scale { NumberAnimation { duration: Appearance.mQuick; easing.type: Easing.OutCubic } }

                    Text {
                        anchors.centerIn: parent
                        text: "‹"
                        color: prevMa.containsMouse ? "#ffffff" : "#c0c0c0"
                        font.family: Appearance.fontUI
                        font.pixelSize: 18
                        Behavior on color { ColorAnimation { duration: Appearance.mQuick } }
                    }

                    MouseArea {
                        id: prevMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.prevMonth()
                    }
                }

                // Flecha mes siguiente
                Rectangle {
                    id: nextBtn
                    width: 26
                    height: 26
                    radius: Appearance.radS
                    color: nextMa.pressed
                        ? Qt.rgba(1, 1, 1, 0.16)
                        : nextMa.containsMouse
                        ? Qt.rgba(1, 1, 1, 0.10)
                        : Qt.rgba(1, 1, 1, 0.05)
                    Behavior on color { ColorAnimation { duration: Appearance.mQuick } }
                    scale: nextMa.pressed ? 0.95 : 1
                    Behavior on scale { NumberAnimation { duration: Appearance.mQuick; easing.type: Easing.OutCubic } }

                    Text {
                        anchors.centerIn: parent
                        text: "›"
                        color: nextMa.containsMouse ? "#ffffff" : "#c0c0c0"
                        font.family: Appearance.fontUI
                        font.pixelSize: 18
                        Behavior on color { ColorAnimation { duration: Appearance.mQuick } }
                    }

                    MouseArea {
                        id: nextMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.nextMonth()
                    }
                }
            }
        }

        Item { Layout.preferredHeight: 14 }

        // ─────────────── fila de iniciales de los días ───────────────
        Row {
            Layout.fillWidth: true
            Layout.preferredHeight: 18

            Repeater {
                model: 7
                Item {
                    width: 44
                    height: 18
                    Text {
                        anchors.centerIn: parent
                        text: ShellState.loc.dayName((ShellState.loc.firstDayOfWeek + index) % 7, Locale.NarrowFormat).toUpperCase()
                        color: "#707070"
                        font.family: Appearance.fontUI
                        font.pixelSize: 11
                        font.weight: Font.Medium
                    }
                }
            }
        }

        Item { Layout.preferredHeight: 8 }

        // ─────────────── rejilla de 6 filas × 7 columnas ───────────────
        Grid {
            Layout.fillWidth: true
            columns: 7
            rows: 6
            rowSpacing: 4
            columnSpacing: 0

            Repeater {
                model: root.gridCells

                Item {
                    id: cell
                    required property var modelData
                    width: 44
                    height: 32

                    // Círculo de acento para el día de hoy
                    Rectangle {
                        anchors.centerIn: parent
                        width: 28
                        height: 28
                        radius: 14
                        color: Colors.accent
                        visible: cell.modelData.isToday
                    }

                    Text {
                        anchors.centerIn: parent
                        text: String(cell.modelData.day)
                        font.family: Appearance.fontUI
                        font.pixelSize: 13
                        font.weight: cell.modelData.isToday ? Font.Bold : Font.Normal
                        font.features: ({ "tnum": 1 })
                        color: cell.modelData.isToday
                            ? Colors.bg
                            : cell.modelData.isCurrentMonth
                            ? "#ffffff"
                            : Qt.rgba(1, 1, 1, 0.22)
                    }
                }
            }
        }
    }
}
