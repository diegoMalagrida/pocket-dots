// hyprisland — SDDM theme that replicates hyprlock's island.
//
// Goal: that the login screen at boot be INDISTINGUISHABLE from the lock screen
// the notch launches. Every number here comes from ~/.config/hypr/hyprlock.conf;
// if you change one there, change it here. The durations and curves are those
// of quickshell/Appearance.qml (PANEL 320, CONTENIDO 210, RESPUESTA 130).
//
// The glyphs are escaped (\u{F033E}) on purpose: they are Nerd Font Private Use
// Area and do not survive every editor. Do not paste them literally.

import QtQuick
import QtQuick.Effects

Item {
    id: root

    // Focus is critical: if the field does not get it, there is no way in.
    // forceActiveFocus() in Component.onCompleted is NOT enough — the item does
    // not hang from the window yet and the call is lost silently. Hence the
    // focus: true here, the retry with a Timer and the key forwarding.
    focus: true
    Keys.forwardTo: [password]

    // ---- Palette: mirror of ~/.cache/wal/colors-hyprlock.conf ----------------
    // The accent is written by login-sync.sh to /var/lib/sddm-hyprisland/accent
    // every time the wallpaper changes. It is NOT readonly on purpose: it is
    // read from disk at startup (see Component.onCompleted) and assigned. What
    // theme.conf carries is only the starting point -the theme installer seeds
    // it with the accent of the moment- so the colour is not seen to jump
    // while the island comes in. The rest is fixed, just as in the notch: the
    // surface is black and pywal only contributes the accent.
    property color accent:              config.accent || "#8cd8c2"

    // Login language. It comes from theme.conf because there is no user
    // session here yet and the rice's JSON cannot be read: SDDM runs before
    // anybody's $HOME exists. The installer writes it.
    // If the key is missing, Spanish, which is what there always was.
    readonly property string uiLang:    config.language || "es"
    readonly property bool english:     uiLang === "en"
    readonly property color surface:    Qt.rgba(0, 0, 0, 0.941)   // rgba(000000f0)
    readonly property color surfaceAlt: "#181818"
    readonly property color outline:    Qt.rgba(1, 1, 1, 0.094)   // rgba(ffffff18)
    readonly property color textColor:  "#ffffff"
    readonly property color muted:      "#b0b0b0"
    readonly property color dim:        "#7d7d7d"
    readonly property color okColor:    "#6dbd7a"
    readonly property color warnColor:  "#e0a458"
    readonly property color failColor:  "#e05c5c"

    // ---- Island geometry (hyprlock: shape 520x340, rounding 32) -------------
    readonly property int islandW: 520
    readonly property int islandH: 340
    readonly property int fieldW:  360
    readonly property int fieldH:  50

    // ---- Login state --------------------------------------------------------
    property int  attempts: 0
    property bool checking: false
    property bool failed: false
    // RememberLastUser=true in /etc/sddm.conf, so lastUser is usually enough;
    // firstUser covers the first boot and test mode, where it comes empty.
    property string firstUser: ""
    property string userName: userModel.lastUser || firstUser

    Repeater {
        model: userModel
        delegate: Item {
            required property string name
            required property int index
            Component.onCompleted: if (index === 0) root.firstUser = name
        }
    }

    // ---- User portrait --------------------------------------------------------
    // The photo comes from the model's `icon` role, which SDDM already resolves
    // against FacesDir (/usr/share/sddm/faces/<user>.face.icon, with
    // EnableAvatars in /etc/sddm.conf). No path is built by hand here. It is the
    // same file hyprlock reads, and it is there and not in $HOME because the
    // greeter runs as its own user and cannot get into /home/diego, which is
    // 0700.
    //
    // The whole model is walked before knowing who was the last to log in, so
    // the photos are stored by name and the portrait is chosen afterwards.
    property var userIcons: ({})
    readonly property string userFace: faceOf(userName)

    function faceOf(user) {
        var p = userIcons[user] || "";
        if (p === "")
            return "";
        return p.indexOf("file:") === 0 ? p : "file://" + p;
    }

    // The whole object is reassigned, as in rememberSession: mutating it in place
    // does not notify the binding and the portrait would be left without a photo.
    function rememberFace(user, facePath) {
        var m = {};
        for (var k in userIcons)
            m[k] = userIcons[k];
        m[user] = facePath;
        userIcons = m;
    }

    // A separate Repeater from the one above on purpose. If the `icon` role
    // disappeared in some SDDM version, the whole delegate fails: this way it
    // takes down the portrait and nothing else, not the name you log in with.
    Repeater {
        model: userModel
        delegate: Item {
            required property string name
            required property string icon
            Component.onCompleted: root.rememberFace(name, icon)
        }
    }

    // ---- Sessions -----------------------------------------------------------
    // It used to ALWAYS log into sessionModel.lastIndex and there was no way to
    // pick another. The day Hyprland did not start, that left the machine locked
    // from the inside: Plasma was installed and there was no way to reach it
    // without editing the kernel line from the boot manager.
    //
    // The default behaviour does NOT change: sessionPick is -1 as long as nobody
    // touches the selector, and in that case sddm.login() is given the same
    // sessionModel.lastIndex as always.
    //
    // This Repeater draws nothing: it only copies the names from the model.
    // They are read by role ("name", just as in userModel) and not with
    // sessionModel.data(idx, 260) as the `silent` theme does, because that 260
    // is the raw number of SDDM's enum and breaks silently if it is reordered.
    property var sessionNames: []
    property int sessionPick: -1
    readonly property int sessionCurrent: sessionPick >= 0 ? sessionPick
                                                           : sessionModel.lastIndex
    readonly property string sessionName:
        (sessionCurrent >= 0 && sessionCurrent < sessionNames.length)
            ? sessionNames[sessionCurrent] : ""

    Repeater {
        id: sessionProbe
        model: sessionModel
        delegate: Item {
            required property string name
            required property int index
            Component.onCompleted: root.rememberSession(index, name)
        }
    }

    // The whole array is reassigned on purpose: mutating one in place does not
    // notify the bindings and the label would be left empty.
    function rememberSession(i, sessionTitle) {
        var a = sessionNames.slice();
        while (a.length <= i)
            a.push("");
        a[i] = sessionTitle;
        sessionNames = a;
    }

    // Cycle, do not drop down. A Qt ComboBox brings its own frame and its own
    // popup on top of the island, and an open popup can cover the field or steal
    // its focus, which is the bug that cost the most while building this theme.
    // Cycling, there is nothing that can be left open.
    function cycleSession(step) {
        var n = sessionProbe.count;
        if (n <= 1)
            return;
        var cur = (sessionCurrent >= 0 && sessionCurrent < n) ? sessionCurrent : 0;
        sessionPick = (cur + step + n) % n;
        password.forceActiveFocus();      // focus goes back to the field, always
    }

    // The `softOut` curve from hyprlock.conf. It is the sister of the motion
    // language's `forma`: 90 % of the travel in the first third, long landing.
    readonly property var softOut: [0.16, 1.0, 0.3, 1.0, 1.0, 1.0]

    // ---- Points to pixels ---------------------------------------------------
    // hyprlock draws with pango, and the `font_size` in hyprlock.conf is in
    // POINTS at 96 dpi. Qt measures in pixels. Copying the number as it is
    // -which is what this theme used to do- leaves all the login typography 25 %
    // smaller than the lock screen's: measured on screenshots of both screens,
    // the date is 253 px wide in hyprlock and 190 in the login, exactly 4/3.
    //
    // So the numbers from hyprlock.conf are copied here AS THEY ARE and
    // converted with this. If some day you change a font_size there, bring the
    // same number over and do not touch it.
    readonly property real pt: 4 / 3

    // =========================================================================
    // Background: the current wallpaper, blurred and dimmed just like hyprlock
    // (blur_passes 2, blur_size 4, brightness 0.68, contrast 0.92, vibrancy).
    // =========================================================================
    Rectangle {
        anchors.fill: parent
        color: "black"
    }

    Image {
        id: wallpaper
        anchors.fill: parent
        // Fixed, absolute path: that is where login-sync.sh, which runs as your
        // user, leaves the wallpaper. If the file is not there -theme just
        // installed, or wallpaper not changed yet- Qt sets status Error and we
        // fall back to the one shipped inside the theme, which is the last one
        // published with sudo.
        source: "file:///var/lib/sddm-hyprisland/current.jpg"
        onStatusChanged: if (status === Image.Error && source != fallback)
                             source = fallback
        readonly property url fallback: config.background || "backgrounds/current.jpg"
        fillMode: Image.PreserveAspectCrop
        asynchronous: false
        cache: false
        visible: false
        layer.enabled: true
    }

    MultiEffect {
        anchors.fill: parent
        source: wallpaper
        blurEnabled: true
        blur: 1.0
        // blur_passes 2 with blur_size 4 is a GENTLE blur: in hyprlock the
        // wallpaper's scene can still be recognised. Here there used to be
        // blurMax 40, which is a 40 px radius and wiped out the whole image.
        // Calibrated against a hyprlock screenshot by measuring the background's
        // mean gradient (how much detail survives) until the two numbers matched.
        blurMax: 13
        blurMultiplier: 1.0
        contrast: -0.08       // hyprlock contrast 0.92
        saturation: 0.14      // hyprlock vibrancy 0.14
        // brightness is NOT touched here: MultiEffect's is ADDITIVE (-0.32
        // subtracts 82 of each channel's 255 and crushes the background to
        // black), whereas hyprlock's is a MULTIPLIER. The scrim below does the
        // real multiplication.
    }

    // hyprlock brightness 0.68, which is a multiplication. A 32 % black on top
    // gives exactly that: pixel * (1 - 0.32). Measured: with the additive
    // brightness the login background had a mean brightness of 3.6 out of 255
    // against the lock screen's 49.3 -fourteen times darker-; this way both
    // come out the same.
    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.22)
    }

    // =========================================================================
    // The island
    // =========================================================================

    // Shadow (hyprlock: shadow_passes 3, shadow_size 18, rgba(000000a6)).
    // It is drawn as a gradient of rings and not with MultiEffect on purpose:
    // a layer.effect clips the shadow to the item's edge, and feeding it a
    // `visible: false` source gave a LIGHT GREY halo instead of a shadow.
    // 1 px rings with decreasing alpha: predictable and no odd effects.
    //
    // NO VERTICAL OFFSET. Here there used to be a `verticalCenterOffset: 6` that
    // moved the rings down 6 px, like one of those drop shadows that "fall"
    // downwards. hyprlock does not do that: its shape only has shadow_passes,
    // shadow_size, shadow_color and shadow_boost -- there is no shadow_offset,
    // and the shadow surrounds the shape evenly on all four sides.
    //
    // The effect was what Diego saw and described as "something extra under the
    // black": at the top the island itself covered the rings, but at the bottom
    // they came apart and let SIX PIXELS of clean background show between the
    // island and its shadow, which read as a coloured rim. Measured on the
    // greeter screenshot: at the bottom edge it went (9,4,4) inside -> 1 px of
    // border -> y=710..715 at (155,68,69), that is, the background -> y=716 the
    // shadow starting abruptly at (54,24,24). At the left edge, on the other
    // hand, the shadow met the island with no such gap.
    Repeater {
        model: 18                                  // shadow_size
        delegate: Rectangle {
            required property int index
            anchors.centerIn: island
            width: island.width + (index + 1) * 2
            height: island.height + (index + 1) * 2
            radius: island.radius + index + 1
            color: "transparent"
            border.width: 1
            border.color: Qt.rgba(0, 0, 0, 0.65 * Math.pow(1 - index / 18, 2))
            opacity: island.opacity
        }
    }

    Rectangle {
        id: island
        anchors.centerIn: parent
        width: root.islandW
        height: root.islandH
        radius: 32
        color: root.surface
        border.width: 1
        border.color: root.outline

        // PANEL enters: 320 ms.
        opacity: 0
        Component.onCompleted: opacity = 1
        Behavior on opacity {
            NumberAnimation {
                duration: 320
                easing.type: Easing.Bezier
                easing.bezierCurve: root.softOut
            }
        }

        // ---- Lock medallion (42x42, +130 above the centre) ------------------
        // 44 and not 42: hyprlock draws the 42 shape and adds the 1 px border
        // OUTSIDE it, whereas Qt paints it inside. With 44 the circle measures
        // the same 44 px edge to edge as on the lock screen.
        Rectangle {
            width: 44
            height: 44
            radius: 22
            color: root.surfaceAlt
            border.width: 1
            border.color: root.accent
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: -130

            Text {
                anchors.centerIn: parent
                text: "\u{F033E}"                     // nf-md-lock
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: Math.round(17 * root.pt)
                color: root.accent
            }
        }

        // ---- Portrait (the same medallion, with a photo) --------------------
        // 50 and not 48: hyprlock declares `size = 48` and adds its 1 px border
        // OUTSIDE it, just as with the shape above.
        //
        // It sits on top of the medallion, so it covers the padlock when there
        // is a photo. If there is none -or SDDM returns a default.face.icon that
        // does not exist- this stays entirely invisible and the usual padlock is
        // still underneath: this screen cannot be left with a hole.
        //
        // `clip` cuts to a rectangle, never to a circle; hence the disc and the
        // MultiEffect, which is also how the lock screen solves it.
        Item {
            id: portrait

            width: 50
            height: 50
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: -130
            visible: face.status === Image.Ready

            Rectangle {
                anchors.fill: parent
                radius: width / 2
                color: root.surfaceAlt
                border.width: 1
                border.color: root.accent

                Behavior on border.color {
                    ColorAnimation {
                        duration: 130                 // RESPUESTA
                        easing.type: Easing.Bezier
                        easing.bezierCurve: root.softOut
                    }
                }
            }

            Image {
                id: face

                anchors.fill: parent
                anchors.margins: 1
                source: root.userFace
                visible: false                        // the MultiEffect draws it
                asynchronous: true
                fillMode: Image.PreserveAspectCrop
                sourceSize.width: 128
                sourceSize.height: 128
            }

            Rectangle {
                id: faceDisc

                anchors.fill: face
                radius: width / 2
                visible: false
                layer.enabled: true
            }

            MultiEffect {
                anchors.fill: face
                source: face
                maskEnabled: true
                maskSource: faceDisc
            }
        }

        // ---- Clock (68 px, tabular figures so they do not jiggle) -----------
        Text {
            id: clock
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: -58
            font.family: "Adwaita Sans"
            font.pixelSize: Math.round(68 * root.pt)
            font.features: ({ "tnum": 1 })
            color: root.textColor
            text: Qt.formatDateTime(new Date(), "HH:mm")
        }

        // ---- Date in Spanish, independent of the system locale --------------
        Text {
            id: dateLabel
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: -4
            font.family: "Adwaita Sans"
            font.pixelSize: Math.round(15 * root.pt)
            color: root.muted
            text: root.localDate()
        }

        // ---- Pill field -----------------------------------------------------
        Rectangle {
            id: field
            // fieldW/fieldH are the INTERIOR, which is what hyprlock declares in
            // `size`; its outline_thickness goes outside and Qt paints it
            // inside, hence the +4. The password dots are still measured
            // against fieldH, which is what hyprlock does with dots_size.
            width: root.fieldW + 4
            height: root.fieldH + 4
            radius: height / 2                        // hyprlock rounding -1
            color: root.surfaceAlt
            border.width: 2                           // outline_thickness
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: 58

            // The border colour IS the message: accent at rest, amber with
            // caps lock, green while checking, red on failure.
            border.color: root.checking ? root.okColor
                        : root.failed ? root.failColor
                        : keyboard.capsLock ? root.warnColor
                        : root.accent

            Behavior on border.color {
                ColorAnimation {
                    duration: 130                     // RESPUESTA
                    easing.type: Easing.Bezier
                    easing.bezierCurve: root.softOut
                }
            }

            // Captures the keystrokes; the dots are drawn by hand below to nail
            // hyprlock's size (dots_size 0.20, spacing 0.38).
            TextInput {
                id: password
                anchors.fill: parent
                focus: true
                echoMode: TextInput.Password
                passwordCharacter: " "
                color: "transparent"
                selectionColor: "transparent"
                enabled: !root.checking

                onTextChanged: {
                    root.failed = false;
                }

                Keys.onPressed: function (event) {
                    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                        root.doLogin();
                        event.accepted = true;
                    }
                    // Keyboard route for the selector, in case the mouse does
                    // not respond: F1 moves to the next session, Shift+F1 to the
                    // previous one. F1 types nothing, so it cannot end up inside
                    // the password.
                    if (event.key === Qt.Key_F1) {
                        root.cycleSession((event.modifiers & Qt.ShiftModifier) ? -1 : 1);
                        event.accepted = true;
                    }
                }
            }

            // Status as text, centred, replaces the placeholder.
            Text {
                anchors.centerIn: parent
                font.family: "Adwaita Sans"
                // The input-field in hyprlock.conf does not declare font_size, so
                // it uses its default of 12 pt. Measured on both screenshots: the
                // placeholder is 161 px wide on the lock screen and 142 with the
                // 14 px there used to be here; 12 pt gives the same 161.
                font.pixelSize: Math.round(12 * root.pt)
                visible: text !== ""
                color: root.checking ? root.okColor
                     : root.failed ? root.failColor
                     : Qt.rgba(1, 1, 1, 0.55)         // placeholder alpha 55 %
                text: root.checking ? (root.english ? "Checking…" : "Comprobando…")
                    : root.failed ? (root.english ? "No match · attempt " : "No coincide · intento ") + root.attempts
                    : password.text.length === 0 ? (root.english ? "Enter your password" : "Escribe tu contraseña")
                    : ""
            }

            // The dots. Diameter = 0.20 * height, gap = 0.38 * diameter.
            Row {
                anchors.centerIn: parent
                spacing: root.fieldH * 0.20 * 0.38
                visible: !root.checking && !root.failed && password.text.length > 0

                Repeater {
                    model: password.text.length
                    delegate: Rectangle {
                        width: root.fieldH * 0.20
                        height: width
                        radius: width / 2
                        color: root.textColor

                        // CONTENIDO enters: 210 ms.
                        scale: 0
                        Component.onCompleted: scale = 1
                        Behavior on scale {
                            NumberAnimation {
                                duration: 210
                                easing.type: Easing.Bezier
                                easing.bezierCurve: root.softOut
                            }
                        }
                    }
                }
            }
        }

        // ---- Footer: identity on the left, battery on the right ------------
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.horizontalCenterOffset: -154
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: 124
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: Math.round(12 * root.pt)
            color: root.dim
            text: "\u{F0004}  " + root.userName      // nf-md-account
        }

        Text {
            id: batteryLabel
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.horizontalCenterOffset: 154
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: 124
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: Math.round(12 * root.pt)
            color: root.dim
            text: ""
        }

        // ---- Session selector: the one thing the lock screen does not have ----
        // hyprlock does not have this, and the island has to be the same screen.
        // But removing it is not an option either: the day Hyprland did not
        // start, always logging into the last session left the machine locked
        // from the inside, with Plasma installed and no way to reach it.
        //
        // The compromise is to show only the little monitor icon in the centre
        // of the footer -12 px of grey, between two gaps of 100- and bring out
        // the session name only on hover. At rest the footer is "user ... o ...
        // battery", which is hyprlock's with a speck in the middle; as soon as
        // you look for it, it is all there. The keyboard does not depend on the
        // mouse: F1 still cycles.
        //
        // If the model gave no name at all, this is not drawn and the island is
        // left EXACTLY like the lock screen. That is the failure mode we want.
        Text {
            id: sessionLabel
            visible: root.sessionName !== ""
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: 124
            // Width cap in case some .desktop carries a mile-long name: it is
            // cut before it touches the user or the battery.
            width: Math.min(implicitWidth, 232)
            elide: Text.ElideRight
            horizontalAlignment: Text.AlignHCenter
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: Math.round(12 * root.pt)
            // The name and the chevron only on hover. The chevron, moreover,
            // only if there is somewhere to go: with a single session this is a
            // piece of information, not a button, and must not suggest otherwise.
            text: "\u{F0379}"                                   // nf-md-monitor
                + (sessionArea.containsMouse
                     ? "  " + root.sessionName
                       + (sessionProbe.count > 1 ? "  \u{F0140}" : "")  // chevron
                     : "")
            color: sessionArea.containsMouse ? root.accent : root.dim

            Behavior on color {
                ColorAnimation {
                    duration: 130                 // RESPUESTA
                    easing.type: Easing.Bezier
                    easing.bezierCurve: root.softOut
                }
            }

            // The mouse area does NOT hang from the Text: if it did, the text
            // would shrink when the pointer left, the area would shrink with it
            // and the hover would switch off and on in a loop. It is fixed and
            // the size of the icon with some slack, so it does not move when the
            // label grows.
            MouseArea {
                id: sessionArea
                anchors.centerIn: parent
                width: 44
                height: 28
                enabled: sessionProbe.count > 1
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                onClicked: function (mouse) {
                    root.cycleSession(mouse.button === Qt.RightButton ? -1 : 1);
                }
            }
        }
    }

    // =========================================================================
    // Clocks and data
    // =========================================================================
    Timer {
        interval: 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            clock.text = Qt.formatDateTime(new Date(), "HH:mm");
            dateLabel.text = root.localDate();
        }
    }

    Timer {
        interval: 30000
        running: true
        repeat: true
        onTriggered: root.refreshBattery()
    }

    // Same format as ~/.config/hypr/scripts/lock-info.sh, and for the same
    // reason: the session runs with LC_TIME=C but the interface speaks Spanish.
    //
    // In English that table is NOT reused, nor is the session locale trusted:
    // Qt is asked for the en_GB locale explicitly. Relying on LC_TIME=C would
    // give the same result today, but the day someone touches SDDM's
    // environment the date would change language without anyone having
    // touched the theme.
    function localDate() {
        var d = new Date();
        if (root.english)
            return d.toLocaleDateString(Qt.locale("en_GB"), "dddd") + " · " +
                   d.toLocaleDateString(Qt.locale("en_GB"), "d MMMM");
        var days = ["Domingo", "Lunes", "Martes", "Miércoles",
                    "Jueves", "Viernes", "Sábado"];
        var months = ["enero", "febrero", "marzo", "abril", "mayo", "junio",
                      "julio", "agosto", "septiembre", "octubre",
                      "noviembre", "diciembre"];
        return days[d.getDay()] + " · " + d.getDate() +
               " de " + months[d.getMonth()];
    }

    // CAREFUL: QML's XMLHttpRequest **does not support synchronous mode**. With
    // open(..., false) send() throws "Error: Invalid state" and you are left
    // with no data and no clue. Every file reader here goes through a callback.
    function readFile(path, done) {
        var xhr = new XMLHttpRequest();
        xhr.onreadystatechange = function () {
            if (xhr.readyState === XMLHttpRequest.DONE)
                done(xhr.responseText ? xhr.responseText.trim() : "");
        };
        try {
            xhr.open("GET", "file://" + path, true);
            xhr.send();
        } catch (e) {
            done("");
        }
    }

    // Which battery it is gets discovered once, and then only its data is re-read.
    property string batteryPath: ""

    function findBattery(i) {
        if (i > 2)
            return;
        var base = "/sys/class/power_supply/BAT" + i;
        readFile(base + "/capacity", function (cap) {
            if (cap === "") {
                root.findBattery(i + 1);
            } else {
                root.batteryPath = base;
                root.refreshBattery();
            }
        });
    }

    function refreshBattery() {
        if (batteryPath === "")
            return;
        readFile(batteryPath + "/capacity", function (cap) {
            if (cap === "") {
                batteryLabel.text = "";
                return;
            }
            root.readFile(root.batteryPath + "/status", function (st) {
                var icon = (st === "Charging" || st === "Full")
                         ? "\u{F0084}"                // nf-md-battery_charging
                         : "\u{F0079}";               // nf-md-battery
                batteryLabel.text = icon + "  " + cap + "%";
            });
        });
    }

    // =========================================================================
    // Login
    // =========================================================================
    function doLogin() {
        if (checking || password.text.length === 0)
            return;
        checking = true;
        failed = false;
        // sessionCurrent IS sessionModel.lastIndex as long as nobody touches the
        // footer selector, so without touching anything this behaves the same
        // as when it said plain lastIndex here.
        sddm.login(userName, password.text, sessionCurrent);
    }

    Connections {
        target: sddm

        function onLoginFailed() {
            root.checking = false;
            root.failed = true;
            root.attempts += 1;
            password.text = "";
            password.forceActiveFocus();
        }

        function onLoginSucceeded() {
            root.checking = false;
            island.opacity = 0;
        }
    }

    // Self-repairing focus. Measured: neither Component.onCompleted nor a single
    // deferred retry grabs the focus — the window is activated later and Qt
    // gives it to nobody, so the field stays mute until you click.
    // This timer keeps insisting while the field does NOT have focus and stops
    // by itself as soon as it gets it, so it also recovers it if it is lost.
    Timer {
        interval: 200
        running: !password.activeFocus
        repeat: true
        triggeredOnStart: true
        onTriggered: password.forceActiveFocus()
    }

    // Last resort: a click anywhere gives the focus back to the field.
    MouseArea {
        anchors.fill: parent
        z: -1
        onClicked: password.forceActiveFocus()
    }

    Component.onCompleted: {
        password.forceActiveFocus();
        findBattery(0);
        // The live accent. The file is written by your user, not root, so it is
        // validated before use: only exactly #rrggbb is accepted. If it is
        // missing or does not pass, the one from theme.conf stays and nothing
        // shows.
        readFile("/var/lib/sddm-hyprisland/accent", function (txt) {
            if (/^#[0-9a-fA-F]{6}$/.test(txt))
                root.accent = txt;
        });
    }
}
