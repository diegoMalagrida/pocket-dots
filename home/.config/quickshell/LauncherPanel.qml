// LauncherPanel.qml — the command centre, unfolded FROM the notch.
//
// It opens with Super+R or by clicking the Arch logo, and the notch stretches
// until it becomes it. Keyboard: typing filters, ↑/↓ (or Ctrl+J/K) moves, Enter
// runs, Esc closes.
//
// It no longer searches only applications. The FIRST CHARACTER decides what is
// searched:
//
//   (none)  applications · calculator · timer · favourites
//   #       clipboard history (text and images)
//   >       system actions
//   @       open windows
//
// The prefix is CONSUMED: typing it makes it disappear from the field and a
// label with the mode's name comes up in its place. If it stayed written there
// would be two things saying the same, and the field would start with a
// character that is not part of what you are looking for. You leave with a
// backspace on the empty field, which is where the hand goes by itself when
// you want to undo.
//
// The logic and data of each mode live in ShellState (that is the house rule:
// this file is interface). Here there is only how it looks and how it is
// navigated.
//
// Keyboard focus is given by TopShell setting the layer to WlrKeyboardFocus
// .OnDemand while this panel is open.
import Quickshell
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Item {
    id: root

    // IS IT OPEN ON THIS SCREEN? With two monitors there are TWO live copies of
    // this: TopShell instantiates NotchContent inside its Variants,
    // NotchContent puts a LauncherPanel straight inside a NotchLayer, and
    // NotchLayer is NOT a Loader -it only animates opacity/scale/slide-, so the
    // Item always exists on both.
    //
    // With a global `active` both handled everything. And since `field.text`
    // only fills in on the copy with focus (WlrLayershell.keyboardFocus gives it
    // only to win.primary, TopShell.qml:243), the MUTE copy computed
    // searchWins("") and published the UNFILTERED count in
    // ShellState.launcherRows. Result on the tower: you opened windows mode,
    // typed to filter, and the notch kept the height of the whole list —seven
    // rows for two results—. The trigger was constant: winTick goes up every
    // 90 ms with any window event.
    //
    // Whoever instantiates us decides it, because NotchContent's `mode` comes
    // from win.faceMode and on screens without focus that is never "launcher".
    property bool enPantalla: true
    readonly property bool active: enPantalla && ShellState.panel === "launcher"

    // The mode lives in ShellState and not here because some callers decide it
    // from outside: Super+Shift+V opens straight into the clipboard, and the
    // "Portapapeles" (Clipboard) action of the ">" mode jumps to the "#" mode
    // without closing the panel.
    readonly property string mode: ShellState.launcherMode
    readonly property var modeInfo: ShellState.launcherModeInfo(root.mode)
    readonly property bool isApps: root.mode === "apps"

    property var results: []

    // WHO CHOOSES THE DELEGATE. THE DATA choose it, not the mode, and the
    // difference is not theoretical: `mode` is a binding declared at the very
    // top and the results are reloaded by a Connections declared further down,
    // so when the mode changes Qt updates the binding first and the handler
    // afterwards. In that one-frame gap the list was repainted with the NEW
    // delegate and the OLD data: the windows delegate received applications and
    // asked for fields that do not exist. Five warnings came out in the log for
    // every "@" you typed.
    //
    // Asking the first row, this cannot happen, because the answer changes
    // exactly at the same time as the data. The entries of the three new modes
    // are tagged in ShellState; a .desktop entry carries no `kind`, and that is
    // why the default case is "apps".
    readonly property string listKind: root.results.length > 0
        ? (root.results[0].kind || "apps") : root.mode

    // Calculator: if what you typed is a sum, it comes out at the top and is
    // what is selected by default. Enter copies the result to the clipboard.
    property var calc: null
    readonly property bool hasCalc: root.calc !== null

    // Timer: if what you typed is a duration ("10m", "1h30", "90s"), the SAME
    // row at the top offers a countdown and Enter starts it.
    //
    // Neither the calculator nor the timer has a prefix, and that is not an
    // oversight: they are not a mode. They are what happens when what you type
    // turns out to be a sum or a duration. They were the ones that opened the
    // door to typing things in the launcher that are not application names; the
    // modes just finish that idea.
    property int timerSec: -1
    readonly property bool hasTimer: root.timerSec > 0

    // There is only one highlighted row and it can only be one thing: "10m" is
    // not a sum and "2+2" is not a duration, so they never compete.
    readonly property bool hasSpecial: root.hasCalc || root.hasTimer
    property bool calcSelected: false

    // ─────────────── favourites ───────────────
    // The pinned row at the top. The ON-SCREEN order belongs to the panel and
    // not to Config on purpose: while you drag, what is saved does not change.
    // If the file were written on every pixel, the whole list would be repainted
    // and the delegates recreated right under your finger, killing the gesture
    // halfway. It is only committed on release.
    property var favShown: []
    property int favDrag: -1         // index being dragged, -1 = none
    property bool favMoving: false   // already past the threshold: a drag, not a click
    property int favSlot: -1         // insertion slot (0..n) under the pointer
    property real favGhostX: 0
    property real favGhostY: 0
    property string favHover: ""     // name of the favourite under the mouse

    // Only in applications mode and with the field empty: as soon as you type,
    // the search takes over, and the row disappears so as not to steal its room.
    readonly property bool favVisible: root.isApps && field.text.length === 0
                                       && root.favShown.length > 0

    function syncFavs() { if (root.favDrag < 0) root.favShown = ShellState.favApps; }

    // The three hints on the right: only with the field empty in applications
    // mode. It is the only sign that the modes exist, and that is why it is
    // where you are looking when you open the launcher and have not typed
    // anything yet.
    readonly property bool hintsVisible: root.isApps && field.text.length === 0
                                         && root.favHover.length === 0

    Connections {
        target: ShellState

        function onFavAppsChanged() {
            root.syncFavs();
            ShellState.launcherFavs = root.favVisible;
        }

        // Changing mode is starting from scratch: the text that was there was
        // looking for something else. It holds equally for the typed prefix,
        // for Super+Shift+V and for the "Portapapeles" (Clipboard) action.
        function onLauncherModeChanged() {
            // Empty the list BEFORE anything else, and do it even if the panel
            // is closed. The delegate is chosen by the mode, so it changes at the
            // same instant `mode` changes, but the results are still those of the
            // previous mode: during that gap the clipboard delegate receives
            // system actions and asks for fields that do not exist (`thumb`,
            // `image`). It showed up as three TypeError warnings in the log every
            // time Super+Shift+V opened the panel while it was closed, because
            // there the `return` below skipped the refresh.
            root.results = [];
            if (!root.active) return;
            field.text = "";
            root.enterMode();
        }

        // The data of these two modes arrive late (a process, a query to
        // Hyprland's socket), so the list is filtered again when they land.
        function onClipItemsChanged() { if (root.active && root.mode === "clip") root.refresh(); }
        function onWinItemsChanged() { if (root.active && root.mode === "win") root.refresh(); }
    }

    // Is the keyboard or the mouse in charge? On opening the keyboard is in
    // charge, ALWAYS. Otherwise the pointer that happened to be over a row
    // hijacks the selection; and worse: while typing, the list is re-filtered
    // and the rows move under a still cursor, firing onEntered and stealing the
    // focus on every keystroke. The mouse only takes back control if it really
    // MOVES.
    property bool mouseNav: false
    property point lastMouse: Qt.point(-1, -1)

    // The only criterion for handing control to the mouse: the POINTER has
    // moved. It tells apart the two cases that were a nuisance:
    //   · on opening, Wayland sends an event for "entering" the new surface
    //     even though the mouse is still -> the first one only sets the reference;
    //   · while typing, the list is re-filtered and the rows pass under a still
    //     cursor -> same point, so it does not count.
    function pointerMoved(px, py) {
        if (root.lastMouse.x < 0) { root.lastMouse = Qt.point(px, py); return false; }
        if (px === root.lastMouse.x && py === root.lastMouse.y) return false;
        root.lastMouse = Qt.point(px, py);
        return true;
    }

    // Entering a mode: ask for its data and re-filter. The clipboard is re-read
    // ALWAYS (it costs hundredths of a second and an out-of-date copy list is no
    // use at all); ShellState already ignores the request if one is in flight.
    function enterMode() {
        if (root.mode === "clip") ShellState.clipRefresh();
        else if (root.mode === "win") ShellState.winRefresh();
        root.refresh();
    }

    function refresh() {
        root.mouseNav = false;
        // Outside applications mode there are no sums or durations: "2+2" in
        // the clipboard is text to search for, not an addition.
        root.calc = root.isApps ? ShellState.calcEval(field.text) : null;
        root.timerSec = root.isApps ? ShellState.parseDuration(field.text) : -1;

        switch (root.mode) {
        case "clip": root.results = ShellState.searchClip(field.text); break;
        case "cmd":  root.results = ShellState.searchActions(field.text); break;
        case "win":  root.results = ShellState.searchWins(field.text); break;
        default:     root.results = ShellState.searchApps(field.text); break;
        }

        root.calcSelected = root.hasSpecial;
        list.currentIndex = (!root.hasSpecial && root.results.length > 0) ? 0 : -1;
        // Go back to the top by hand. The model reset used to do it: when the
        // array changed, the list rewound by itself. With ScriptModel the rows
        // are reused and the view stays where it was, so a new search could be
        // born scrolled, with the highlighted row off screen.
        // Only here: deleteCurrent() wants exactly the opposite (stay where it
        // was so three can be deleted in a row) and now at last it can.
        list.positionViewAtBeginning();
        root.syncFavs();

        // so the notch fits what there is
        ShellState.launcherRows = root.waiting ? ShellState.launcherMaxRows : root.results.length;
        ShellState.launcherCalc = root.hasSpecial;
        ShellState.launcherFavs = root.favVisible;
    }

    // While the clipboard process answers, it is not known how many rows there
    // will be. If 0 were published, the panel would be born the size of "Sin
    // resultados" (No results) and would jump downwards when the data arrived.
    // The maximum is requested and it shrinks, which is its usual gesture and
    // also happens inside the opening animation.
    readonly property bool waiting: root.mode === "clip" && ShellState.clipLoading
                                    && root.results.length === 0

    function jump(i) {
        if (root.results.length === 0) return;
        root.mouseNav = false;
        list.currentIndex = Math.max(0, Math.min(root.results.length - 1, i));
        list.positionViewAtIndex(list.currentIndex, ListView.Contain);
    }

    // What Enter does. Each mode knows its own business; the highlighted row
    // (calculator or timer) comes before everything because it only exists in
    // apps mode.
    function launchCurrent() {
        if (root.calcSelected && root.hasTimer) {
            ShellState.timerStart(root.timerSec);
            ShellState.closePanel();
            return;
        }
        if (root.calcSelected && root.hasCalc) {
            ShellState.copyText(ShellState.calcFormat(root.calc));
            ShellState.closePanel();
            return;
        }
        if (list.currentIndex < 0 || list.currentIndex >= root.results.length) return;
        const it = root.results[list.currentIndex];
        switch (root.mode) {
        case "clip": ShellState.clipCopy(it); break;
        case "cmd":  ShellState.runAction(it); break;
        case "win":  ShellState.focusWindow(it); break;
        default:     ShellState.launchApp(it); break;
        }
    }

    // Delete removes the clipboard entry without closing the panel: cleaning up
    // the history is exactly the task during which you want to keep looking at
    // it. Rofi could not do it (choosing an entry closed the menu), so this is
    // something new in the native mode.
    function deleteCurrent() {
        if (root.mode !== "clip") return;
        if (list.currentIndex < 0 || list.currentIndex >= root.results.length) return;
        const i = list.currentIndex;
        ShellState.clipDelete(root.results[i]);
        root.results = ShellState.searchClip(field.text);
        ShellState.launcherRows = root.results.length;
        // Stay where it was, do not go back to the top: deleting three in a row
        // is a normal gesture, and jumping to the start after each one prevents it.
        list.currentIndex = root.results.length === 0 ? -1
            : Math.min(i, root.results.length - 1);
    }

    function move(delta) {
        root.mouseNav = false;
        // the calculator row behaves as one more position, above the list
        if (root.calcSelected && delta > 0) {
            if (root.results.length === 0) return;
            root.calcSelected = false;
            list.currentIndex = 0;
            return;
        }
        if (root.hasSpecial && !root.calcSelected && delta < 0 && list.currentIndex === 0) {
            root.calcSelected = true;
            list.currentIndex = -1;
            return;
        }
        if (root.results.length === 0) return;
        let i = list.currentIndex + delta;
        if (i < 0) i = root.results.length - 1;
        if (i >= root.results.length) i = 0;
        list.currentIndex = i;
        list.positionViewAtIndex(i, ListView.Contain);
    }

    // On opening: empty field, focus on the field and the keyboard in charge.
    // The mode is NOT touched here: whoever opened it has decided (togglePanel
    // always enters "apps", openLauncher enters whichever it is asked for).
    onActiveChanged: {
        if (root.active) {
            field.text = "";
            // A half-finished drag that was left hanging when the panel closed
            // must not reappear when it is opened again.
            root.favDrag = -1; root.favMoving = false; root.favSlot = -1; root.favHover = "";
            root.enterMode();
            field.forceActiveFocus();
            refocus.restart();   // safety: the layer takes an instant to accept focus
            root.lastMouse = Qt.point(-1, -1);
        }
    }
    Timer {
        id: refocus
        interval: 120
        onTriggered: if (root.active) field.forceActiveFocus()
    }

    // Swallows clicks and wheel in the gap so they do not reach the notch below
    // (otherwise clicking on the panel's background would close it).
    MouseArea {
        anchors.fill: parent
        onWheel: function (w) { w.accepted = true; }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.topMargin: 4
        spacing: 0

        // ─────────────── search box ───────────────
        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 22
            Layout.rightMargin: 22
            Layout.preferredHeight: 50
            spacing: 12

            // The icon on the left is the MODE's: the magnifying glass only when
            // applications are really being searched.
            Text {
                text: root.modeInfo.icon
                color: (field.text.length > 0 || !root.isApps) ? Colors.accentInk : Colors.label4
                font.family: Appearance.font
                font.pixelSize: 17
                Behavior on color { ColorAnimation { duration: Appearance.mQuick; easing.type: Easing.OutQuad } }
            }

            // The mode label, in the exact spot where the prefix that created it
            // was. It is what makes deleting it from the field honest: the
            // character disappears but leaves something in its place.
            Rectangle {
                visible: !root.isApps
                Layout.preferredWidth: modeChip.implicitWidth + 20
                Layout.preferredHeight: 26
                radius: 9
                color: Qt.rgba(Colors.accent.r, Colors.accent.g, Colors.accent.b, 0.16)

                RowLayout {
                    id: modeChip
                    anchors.centerIn: parent
                    spacing: 6
                    Text {
                        text: root.modeInfo.prefix
                        color: Colors.accentInk
                        font.family: Appearance.font; font.pixelSize: Appearance.fsM; font.weight: Font.Bold
                    }
                    Text {
                        text: root.modeInfo.name
                        color: Colors.label
                        font.family: Appearance.fontUI; font.pixelSize: Appearance.fsS; font.weight: Font.Medium
                    }
                }
            }

            TextField {
                id: field
                Layout.fillWidth: true
                placeholderText: root.modeInfo.hint
                color: Colors.label
                placeholderTextColor: Colors.label4
                selectionColor: Colors.accent
                selectedTextColor: "#000000"
                font.family: Appearance.fontUI
                font.pixelSize: Appearance.fsL
                background: null
                padding: 0

                onTextChanged: {
                    // A prefix at the START of the field is not text: it is a
                    // mode change. It is checked here and not in Keys.onPressed so
                    // that it also works when pasting ("#factura" pastes and enters
                    // the clipboard searching for "factura").
                    if (root.isApps && field.text.length > 0) {
                        const m = ShellState.launcherModeOf(field.text.charAt(0));
                        if (m !== "") {
                            const rest = field.text.slice(1);
                            ShellState.launcherMode = m;   // empties the field and refreshes
                            field.text = rest;             // what came after is kept
                            return;
                        }
                    }
                    root.refresh();
                }

                Keys.onEscapePressed: ShellState.closePanel()
                Keys.onDownPressed: root.move(1)
                Keys.onUpPressed: root.move(-1)
                Keys.onReturnPressed: root.launchCurrent()
                Keys.onEnterPressed: root.launchCurrent()
                Keys.onTabPressed: root.move(1)
                Keys.onBacktabPressed: root.move(-1)
                Keys.onPressed: function (e) {
                    // Backspace on the ALREADY empty field leaves the mode. It is
                    // the way out the hand finds by itself: if the prefix was
                    // erased when typed, carrying on erasing has to undo it.
                    if (e.key === Qt.Key_Backspace && !root.isApps && field.text.length === 0) {
                        ShellState.launcherMode = "apps";
                        e.accepted = true;
                        return;
                    }
                    if (e.key === Qt.Key_Delete && root.mode === "clip") {
                        root.deleteCurrent();
                        e.accepted = true;
                        return;
                    }
                    if (e.modifiers & Qt.ControlModifier) {
                        if (e.key === Qt.Key_J || e.key === Qt.Key_N) { root.move(1); e.accepted = true; }
                        else if (e.key === Qt.Key_K || e.key === Qt.Key_P) { root.move(-1); e.accepted = true; }
                        // Ctrl+D pins or unpins whatever you have selected, without the mouse.
                        else if (e.key === Qt.Key_D && root.isApps) {
                            if (!root.calcSelected && list.currentIndex >= 0 && list.currentIndex < root.results.length)
                                ShellState.toggleFav(root.results[list.currentIndex]);
                            e.accepted = true;
                        }
                        // Ctrl+1..9 launches favourite N. It is the reason the
                        // row is ORDERED and can be reordered: the position
                        // becomes a shortcut your fingers learn.
                        else if (root.isApps && e.key >= Qt.Key_1 && e.key <= Qt.Key_9) {
                            const n = e.key - Qt.Key_1;
                            if (n < ShellState.favApps.length) ShellState.launchApp(ShellState.favApps[n]);
                            e.accepted = true;
                        }
                    } else if (e.key === Qt.Key_Home) { root.jump(0); e.accepted = true; }
                    else if (e.key === Qt.Key_End) { root.jump(root.results.length - 1); e.accepted = true; }
                    else if (e.key === Qt.Key_PageDown) { root.move(7); e.accepted = true; }
                    else if (e.key === Qt.Key_PageUp) { root.move(-7); e.accepted = true; }
                }
            }

            // Name of the favourite under the mouse. The icons in the pinned row
            // carry no label underneath (it does not fit in 58 px and would
            // triple the height), so the name comes out here: a place that
            // already existed and that you are already looking at.
            Text {
                visible: root.favHover.length > 0
                Layout.maximumWidth: 170
                text: root.favHover
                color: Colors.label2
                elide: Text.ElideRight
                font.family: Appearance.fontUI
                font.pixelSize: Appearance.fsS
            }

            // The mode hints, where the counter used to be. The counter said
            // "there are 49 applications", which is not a fact anybody needs;
            // this takes the same slot and DOES teach something. As soon as you
            // type a letter the counter comes back, and there it does mean
            // something.
            RowLayout {
                visible: root.hintsVisible
                spacing: 12
                Repeater {
                    model: ShellState.launcherModes
                    RowLayout {
                        required property var modelData
                        spacing: 4
                        Text {
                            text: modelData.prefix
                            color: Colors.accentInk
                            font.family: Appearance.font; font.pixelSize: Appearance.fsS; font.weight: Font.Bold
                        }
                        Text {
                            text: modelData.name
                            color: Colors.label3
                            font.family: Appearance.fontUI; font.pixelSize: Appearance.fsXS
                        }
                    }
                }
            }

            Text {
                visible: !root.hintsVisible && root.favHover.length === 0
                text: String(root.results.length)
                color: Colors.label3
                font.family: Appearance.fontUI
                font.pixelSize: Appearance.fsS
                // Tabular figures: the count is redone on every keystroke and
                // without this the width jiggles going from 9 to 10 results.
                font.features: ({ "tnum": 1 })
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.leftMargin: 18
            Layout.rightMargin: 18
            Layout.bottomMargin: 6
            height: 1
            color: Colors.hairline
        }

        // ─────────────── pinned favourites ───────────────
        // Dragging reorders. Click launches. Right click removes from favourites.
        // Ctrl+1..9 launches favourite N without lifting your hand off the keyboard.
        Item {
            id: favRow
            Layout.fillWidth: true
            Layout.leftMargin: 12
            Layout.rightMargin: 12
            Layout.bottomMargin: root.favVisible ? 12 : 0
            Layout.preferredHeight: root.favVisible ? 58 : 0
            visible: root.favVisible
            clip: true

            readonly property int cellW: 58

            ListView {
                id: favList
                anchors.fill: parent
                orientation: ListView.Horizontal
                // ScriptModel: when a reordered favourite is dropped, `favShown`
                // is a new array, and with the bare array all eight icons were
                // recreated (and their images reloaded) just to move one. They
                // are the same .desktop entries, so by identity the delegate that
                // already exists is moved. Along the way, the row whose
                // onReleased is running stops being destroyed.
                model: ScriptModel {
                    values: root.favShown
                    comparisonMode: ObjectComparison.Identity
                }
                spacing: 0
                boundsBehavior: Flickable.StopAtBounds
                // It can only scroll if they really do not fit; otherwise any
                // horizontal drag would move the list instead of the icon.
                interactive: contentWidth > width

                delegate: Item {
                    id: favCell
                    required property var modelData
                    required property int index

                    width: favRow.cellW
                    height: favRow.height

                    readonly property bool dragged: root.favDrag === favCell.index && root.favMoving

                    Rectangle {
                        anchors.centerIn: parent
                        width: 50; height: 50
                        radius: 15
                        color: favMa.containsMouse && !root.favMoving ? Colors.fill2 : "transparent"
                        Behavior on color { ColorAnimation { duration: Appearance.mQuick; easing.type: Easing.OutQuad } }
                    }

                    Image {
                        anchors.centerIn: parent
                        width: 34; height: 34
                        sourceSize.width: 34; sourceSize.height: 34
                        source: Quickshell.iconPath(favCell.modelData.icon, "application-x-executable")
                        fillMode: Image.PreserveAspectFit
                        // the gap it comes out of, while you carry it
                        opacity: favCell.dragged ? 0.18 : 1
                        Behavior on opacity { NumberAnimation { duration: Appearance.mQuick } }
                    }

                    MouseArea {
                        id: favMa
                        anchors.fill: parent
                        hoverEnabled: true
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        cursorShape: Qt.PointingHandCursor
                        // Otherwise the list's Flickable steals the gesture as
                        // soon as the pointer moves horizontally, which is exactly
                        // what is needed to reorder.
                        preventStealing: true

                        property real pressX: 0
                        property real pressY: 0

                        onEntered: root.favHover = favCell.modelData.name || ""
                        onExited: if (root.favHover === (favCell.modelData.name || "")) root.favHover = ""

                        onPressed: function (m) {
                            if (m.button !== Qt.LeftButton) return;
                            favMa.pressX = m.x; favMa.pressY = m.y;
                            root.favDrag = favCell.index;
                            root.favMoving = false;
                        }

                        onPositionChanged: function (m) {
                            if (root.favDrag < 0) return;
                            // Threshold: without it, the hand's tremor when
                            // clicking would already count as a drag and would not
                            // launch the app.
                            if (!root.favMoving) {
                                if (Math.abs(m.x - favMa.pressX) < 6 && Math.abs(m.y - favMa.pressY) < 6) return;
                                root.favMoving = true;
                            }
                            const p = favMa.mapToItem(favRow, m.x, m.y);
                            root.favGhostX = p.x;
                            root.favGhostY = p.y;
                            // Insertion slot, not element index: rounding (and not
                            // truncating) makes the marker jump at the MIDDLE of
                            // each cell, which is where the eye expects the cut.
                            const cx = favList.contentX + p.x;
                            root.favSlot = Math.max(0, Math.min(root.favShown.length,
                                                                Math.round(cx / favRow.cellW)));
                        }

                        onReleased: function (m) {
                            if (m.button !== Qt.LeftButton) return;
                            const moved = root.favMoving;
                            const from = root.favDrag;
                            const to = root.favSlot;
                            // Clean up BEFORE touching Config: committing changes
                            // ShellState.favApps, and syncFavs() only repaints if
                            // there is no longer a drag in progress.
                            root.favDrag = -1; root.favMoving = false; root.favSlot = -1;
                            if (moved) { if (to >= 0) ShellState.moveFav(from, to); }
                            else ShellState.launchApp(favCell.modelData);
                        }

                        onCanceled: { root.favDrag = -1; root.favMoving = false; root.favSlot = -1; }

                        onClicked: function (m) {
                            // The left one is handled by onReleased, which is the
                            // one that can tell a click from a drag.
                            if (m.button === Qt.RightButton) ShellState.toggleFav(favCell.modelData);
                        }
                    }
                }
            }

            // Where what you are carrying is going to land. Taller than the ghost
            // icon (40 px) on purpose: the cursor is right over the marker, so if
            // they measured the same the icon would cover it completely.
            Rectangle {
                visible: root.favMoving && root.favSlot >= 0
                width: 2
                height: 52
                radius: 1
                color: Colors.accent
                y: (favRow.height - height) / 2
                x: root.favSlot * favRow.cellW - favList.contentX - 1
            }

            // The icon that follows the pointer.
            Image {
                visible: root.favMoving && root.favDrag >= 0 && root.favDrag < root.favShown.length
                width: 40; height: 40
                sourceSize.width: 40; sourceSize.height: 40
                x: root.favGhostX - width / 2
                y: root.favGhostY - height / 2
                opacity: 0.92
                fillMode: Image.PreserveAspectFit
                source: (root.favDrag >= 0 && root.favDrag < root.favShown.length)
                        ? Quickshell.iconPath(root.favShown[root.favDrag].icon, "application-x-executable")
                        : ""
            }
        }

        // ─────────────── calculator result ───────────────
        Rectangle {
            id: calcRow
            Layout.fillWidth: true
            Layout.leftMargin: 12
            Layout.rightMargin: 12
            Layout.bottomMargin: 6
            Layout.preferredHeight: root.hasSpecial ? 56 : 0
            visible: root.hasSpecial
            radius: 12
            color: root.calcSelected ? Qt.rgba(Colors.accent.r, Colors.accent.g, Colors.accent.b, 0.20)
                 : calcMa.containsMouse ? Colors.fill2 : "transparent"
            Behavior on color { ColorAnimation { duration: Appearance.mQuick; easing.type: Easing.OutQuad } }

            RowLayout {
                anchors { fill: parent; leftMargin: 14; rightMargin: 14 }
                spacing: 13

                Text {
                    text: root.hasTimer ? Icons.timer : "󰪚"
                    color: Colors.accentInk
                    font.family: Appearance.font; font.pixelSize: Appearance.fsXL
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    Text {
                        Layout.fillWidth: true
                        text: root.hasTimer ? ShellState.timerClock(root.timerSec)
                                            : ShellState.calcFormat(root.calc)
                        color: Colors.label; elide: Text.ElideRight
                        font.family: Appearance.fontUI; font.pixelSize: 19; font.weight: Font.DemiBold
                        font.features: ({ "tnum": 1 })
                    }
                    Text {
                        Layout.fillWidth: true
                        text: root.hasTimer ? I18n.tr("Enter arranca el temporizador")
                                            : I18n.tr("Enter copia al portapapeles")
                        color: Colors.label3; elide: Text.ElideRight
                        font.family: Appearance.fontUI; font.pixelSize: Appearance.fsXXS
                    }
                }
                Text {
                    visible: root.calcSelected
                    text: root.hasTimer ? Icons.play : "󰆏"
                    color: Colors.accentInk
                    font.family: Appearance.font; font.pixelSize: 14
                }
            }

            MouseArea {
                id: calcMa
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    if (root.hasTimer) ShellState.timerStart(root.timerSec);
                    else ShellState.copyText(ShellState.calcFormat(root.calc));
                    ShellState.closePanel();
                }
            }
        }

        // ─────────────── results ───────────────
        // One delegate per mode, chosen by the list itself. The alternative was a
        // single delegate with four branches inside, which is the same code but
        // without being able to read any of the four at a glance.
        ListView {
            id: list
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.leftMargin: 12
            Layout.rightMargin: 12
            Layout.bottomMargin: 12
            clip: true
            // ScriptModel: every key redoes `results`, and with the bare array
            // that is a reset — the fifty rows were destroyed and recreated on
            // every keystroke even if the result was almost the same. Between
            // keystrokes the entries are the SAME objects (searchApps takes them
            // from allApps, searchClip from clipItems, searchActions from
            // sysActions, searchWins from winItems), so by identity whatever is
            // still there is reused. CAREFUL with windows mode: every winTick
            // rebuilds winItems with NEW objects, so there a poll still redoes
            // the whole list; nothing is lost, but do not expect rows to be
            // reused between polls.
            model: ScriptModel {
                values: root.results
                comparisonMode: ObjectComparison.Identity
            }
            currentIndex: 0
            highlightMoveDuration: Appearance.mQuick
            boundsBehavior: Flickable.StopAtBounds

            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded; width: 4 }

            delegate: root.listKind === "clip" ? clipDelegate
                    : root.listKind === "cmd" ? cmdDelegate
                    : root.listKind === "win" ? winDelegate
                    : appDelegate

            // no results
            Text {
                anchors.centerIn: parent
                visible: root.results.length === 0
                text: root.waiting ? I18n.tr("Leyendo el portapapeles…")
                    : field.text.length > 0 ? I18n.tr("Sin resultados")
                    : root.mode === "clip" ? I18n.tr("El portapapeles está vacío")
                    : root.mode === "win" ? I18n.tr("No hay ventanas abiertas")
                    : I18n.tr("Sin resultados")
                color: Colors.label3
                font.family: Appearance.fontUI
                font.pixelSize: Appearance.fsM
            }
        }
    }

    // ═══════════════════════ delegados ═══════════════════════
    // The background, the highlight and the "mouse in charge" criterion are
    // identical in all four, so they live in a base component and each mode only
    // supplies what goes inside. RowBase publishes `sel` so the content can paint
    // the Enter arrow without looking at the index again.
    // CAREFUL: each mode's content is declared AFTER the MouseArea, with no
    // `default property alias` to a container Item. A default property alias on
    // the type itself also swallows the children declared in the type's
    // definition, that is, the MouseArea, and the result is a container that
    // contains itself. The order also matters for the mouse: coming after, the
    // star and bin zones sit ABOVE the row's zone and take its click, which is
    // exactly what is wanted.
    component RowBase: Rectangle {
        id: base
        required property int index

        readonly property bool sel: base.index === list.currentIndex
        readonly property bool hovered: baseMa.containsMouse
        signal activated(int button)

        width: list.width
        height: ShellState.launcherRowH
        radius: 12
        color: base.sel ? Qt.rgba(Colors.accent.r, Colors.accent.g, Colors.accent.b, 0.20)
             : (baseMa.containsMouse && root.mouseNav) ? Colors.fill2
             : "transparent"
        Behavior on color { ColorAnimation { duration: Appearance.mQuick; easing.type: Easing.OutQuad } }

        MouseArea {
            id: baseMa
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            cursorShape: Qt.PointingHandCursor
            // Same criterion on enter and on move: the mouse is only in charge if
            // the pointer has really moved.
            onPositionChanged: function (m) {
                const p = baseMa.mapToItem(null, m.x, m.y);
                if (root.pointerMoved(p.x, p.y)) { root.mouseNav = true; root.calcSelected = false; list.currentIndex = base.index; }
            }
            onEntered: {
                const p = baseMa.mapToItem(null, baseMa.mouseX, baseMa.mouseY);
                if (root.pointerMoved(p.x, p.y)) { root.mouseNav = true; root.calcSelected = false; list.currentIndex = base.index; }
            }
            onClicked: function (m) { base.activated(m.button); }
        }
    }

    // The Enter arrow, the same in all four modes.
    component EnterMark: Text {
        text: "󰌑"
        color: Colors.accentInk
        font.family: Appearance.font
        font.pixelSize: Appearance.fsM
    }

    // ─── applications ───
    Component {
        id: appDelegate

        RowBase {
            id: appRow
            required property var modelData

            onActivated: function (button) {
                if (button === Qt.RightButton) ShellState.toggleFav(appRow.modelData);
                else ShellState.launchApp(appRow.modelData);
            }

            RowLayout {
                anchors { fill: parent; leftMargin: 12; rightMargin: 14 }
                spacing: 13

                Image {
                    Layout.preferredWidth: 30
                    Layout.preferredHeight: 30
                    source: Quickshell.iconPath(appRow.modelData.icon, "application-x-executable")
                    sourceSize.width: 30
                    sourceSize.height: 30
                    fillMode: Image.PreserveAspectFit
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    Text {
                        Layout.fillWidth: true
                        text: appRow.modelData.name || ""
                        color: Colors.label
                        elide: Text.ElideRight
                        font.family: Appearance.fontUI
                        font.pixelSize: Appearance.fsM
                        font.weight: Font.Medium
                    }
                    Text {
                        Layout.fillWidth: true
                        visible: text.length > 0
                        text: appRow.modelData.comment || appRow.modelData.genericName || ""
                        color: Colors.label2
                        elide: Text.ElideRight
                        font.family: Appearance.fontUI
                        font.pixelSize: Appearance.fsXS
                    }
                }

                // Star: filled if it is already a favourite, hollow only on
                // hover. That way an ordinary row carries no noise, but the way
                // to pin it is always one click away.
                Text {
                    visible: ShellState.isFav(appRow.modelData) || starMa.containsMouse || appRow.hovered
                    text: ShellState.isFav(appRow.modelData) ? Icons.star : Icons.starOff
                    color: ShellState.isFav(appRow.modelData) ? Colors.accent2Ink
                         : starMa.containsMouse ? Colors.label : Colors.label4
                    font.family: Appearance.font
                    font.pixelSize: 14
                    Behavior on color { ColorAnimation { duration: Appearance.mQuick; easing.type: Easing.OutQuad } }

                    MouseArea {
                        id: starMa
                        anchors.fill: parent
                        anchors.margins: -7      // comfortable click zone without enlarging the icon
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: ShellState.toggleFav(appRow.modelData)
                    }
                }

                EnterMark { visible: appRow.sel }
            }
        }
    }

    // ─── # clipboard ───
    Component {
        id: clipDelegate

        RowBase {
            id: clipRow
            required property var modelData

            onActivated: function (button) {
                // The right one deletes, just as in the applications row the
                // right one is "this row's secondary action".
                if (button === Qt.RightButton) { list.currentIndex = clipRow.index; root.deleteCurrent(); }
                else ShellState.clipCopy(clipRow.modelData);
            }

            RowLayout {
                anchors { fill: parent; leftMargin: 10; rightMargin: 14 }
                spacing: 13

                // The real thumbnail for images; a document icon for text. Both
                // go in a slot of the SAME size so that the text column always
                // starts on the same vertical: if each row started wherever it
                // happened to, the list would be an unreadable zigzag.
                Rectangle {
                    Layout.preferredWidth: 46
                    Layout.preferredHeight: 40
                    radius: 8
                    color: clipRow.modelData.image ? "#111111" : "transparent"
                    clip: true

                    Image {
                        anchors.fill: parent
                        visible: clipRow.modelData.image && clipRow.modelData.thumb.length > 0
                        source: clipRow.modelData.thumb.length > 0 ? "file://" + clipRow.modelData.thumb : ""
                        // Cropped and not fitted: filling the slot shows the
                        // CONTENT of the screenshot; fitting it leaves it 12 px
                        // high surrounded by black and nothing can be made out.
                        fillMode: Image.PreserveAspectCrop
                        sourceSize.width: 92
                        sourceSize.height: 80
                        asynchronous: true
                        cache: true
                    }

                    Text {
                        anchors.centerIn: parent
                        visible: !clipRow.modelData.image
                        text: Icons.textBox
                        color: Colors.label3
                        font.family: Appearance.font
                        font.pixelSize: 20
                    }
                }

                Text {
                    Layout.fillWidth: true
                    text: clipRow.modelData.label
                    color: clipRow.modelData.image ? Colors.label2 : Colors.label
                    // Two lines: what gets copied hardly ever fits in one, and
                    // with a single line half the list looked like the same
                    // entry repeated (everything starts with the same paragraph).
                    maximumLineCount: 2
                    wrapMode: Text.Wrap
                    elide: Text.ElideRight
                    font.family: Appearance.fontUI
                    font.pixelSize: Appearance.fsS
                    // Here there ARE two lines, so the air between them is set by
                    // the scale and not by whichever font happens to be chosen in
                    // Ajustes (Settings).
                    lineHeight: Appearance.leading(Appearance.fsS)
                    lineHeightMode: Text.FixedHeight
                    font.weight: clipRow.modelData.image ? Font.Normal : Font.Medium
                }

                // The bin only appears on the highlighted row: it is destructive
                // and there is no reason for it to be on offer in all fifteen at
                // once.
                Text {
                    visible: clipRow.sel
                    text: Icons.trash
                    color: trashMa.containsMouse ? "#ff6b6b" : Colors.label3
                    font.family: Appearance.font
                    font.pixelSize: 15
                    Behavior on color { ColorAnimation { duration: Appearance.mQuick; easing.type: Easing.OutQuad } }

                    MouseArea {
                        id: trashMa
                        anchors.fill: parent
                        anchors.margins: -7
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: { list.currentIndex = clipRow.index; root.deleteCurrent(); }
                    }
                }

                EnterMark { visible: clipRow.sel }
            }
        }
    }

    // ─── > actions ───
    Component {
        id: cmdDelegate

        RowBase {
            id: cmdRow
            required property var modelData

            onActivated: ShellState.runAction(cmdRow.modelData)

            RowLayout {
                anchors { fill: parent; leftMargin: 16; rightMargin: 14 }
                spacing: 15

                Text {
                    Layout.preferredWidth: 24
                    text: cmdRow.modelData.icon
                    color: cmdRow.sel ? Colors.accentInk : Colors.label2
                    horizontalAlignment: Text.AlignHCenter
                    font.family: Appearance.font
                    font.pixelSize: 18
                    Behavior on color { ColorAnimation { duration: Appearance.mQuick; easing.type: Easing.OutQuad } }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    Text {
                        Layout.fillWidth: true
                        text: cmdRow.modelData.name
                        color: Colors.label
                        elide: Text.ElideRight
                        font.family: Appearance.fontUI
                        font.pixelSize: Appearance.fsM
                        font.weight: Font.Medium
                    }
                    Text {
                        Layout.fillWidth: true
                        text: cmdRow.modelData.desc
                        color: Colors.label2
                        elide: Text.ElideRight
                        font.family: Appearance.fontUI
                        font.pixelSize: Appearance.fsXS
                    }
                }

                EnterMark { visible: cmdRow.sel }
            }
        }
    }

    // ─── @ windows ───
    Component {
        id: winDelegate

        RowBase {
            id: winRow
            required property var modelData

            onActivated: ShellState.focusWindow(winRow.modelData)

            RowLayout {
                anchors { fill: parent; leftMargin: 12; rightMargin: 14 }
                spacing: 13

                Image {
                    Layout.preferredWidth: 28
                    Layout.preferredHeight: 28
                    source: Quickshell.iconPath(winRow.modelData.icon, "application-x-executable")
                    sourceSize.width: 28
                    sourceSize.height: 28
                    fillMode: Image.PreserveAspectFit
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    Text {
                        Layout.fillWidth: true
                        // The title is read from the LIVE toplevel and not from
                        // the model's copy: switching tabs in the browser has to
                        // change the row without waiting for the next refresh.
                        text: (winRow.modelData.tl && winRow.modelData.tl.title)
                              ? winRow.modelData.tl.title : winRow.modelData.title
                        color: Colors.label
                        elide: Text.ElideRight
                        font.family: Appearance.fontUI
                        font.pixelSize: Appearance.fsM
                        font.weight: Font.Medium
                    }
                    Text {
                        Layout.fillWidth: true
                        text: winRow.modelData.cls
                        color: Colors.label2
                        elide: Text.ElideRight
                        font.family: Appearance.fontUI
                        font.pixelSize: Appearance.fsXS
                    }
                }

                // Which workspace you are going to. It is the only information
                // the window list has and the compositor's Alt+Tab does not:
                // jumping from here can switch your workspace, and it is worth
                // knowing that beforehand.
                Rectangle {
                    Layout.preferredWidth: 22
                    Layout.preferredHeight: 20
                    radius: 7
                    color: winRow.modelData.ws === ShellState.activeWs
                           ? Qt.rgba(Colors.accent.r, Colors.accent.g, Colors.accent.b, 0.22)
                           : Colors.fill3

                    Text {
                        anchors.centerIn: parent
                        text: String(winRow.modelData.ws)
                        color: winRow.modelData.ws === ShellState.activeWs ? Colors.accentInk : Colors.label3
                        font.family: Appearance.fontUI
                        font.pixelSize: Appearance.fsXS
                        font.weight: Font.DemiBold
                    }
                }

                EnterMark { visible: winRow.sel }
            }
        }
    }
}
