// Config.qml — the rice's persistent settings.
//
// Everything that used to be constants baked into TopShell/ShellState lives
// here and is saved to ~/.config/quickshell-rice.json. The Settings app writes
// to this and the bar and the notch react live.
//
// MIND the path: the file lives OUTSIDE ~/.config/quickshell/ on purpose.
// Quickshell watches its configuration directory to hot-reload, and saving in
// there every time you move a slider would trigger a reload for every pixel.
pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick
import "AppearanceProfiles.js" as Profiles

Singleton {
    id: root

    // ───────── language ─────────
    // "es" | "en". I18n reads it and the whole interface hangs off that. The
    // installer writes it according to what you choose at install time
    // (./install.sh --lang en).
    property alias language: opts.language

    // Profiles per power source, independent of the appearance.
    property alias energyOnAC: opts.energyOnAC
    property alias energyOnBattery: opts.energyOnBattery
    property alias batteryAllowIdle: opts.batteryAllowIdle
    property alias dimOnSaver: opts.dimOnSaver
    property alias saverBrightness: opts.saverBrightness
    // Temporary state; it never modifies the saved appearance preference.
    property bool powerSaverActive: false
    onPowerSaverActiveChanged: root.applyEffects()

    // ───────── notch ─────────
    // "notch" = island stuck to the edge with inverted corners (MacBook).
    // "island" = floating pill detached from the edge (Dynamic Island).
    property alias notchStyle: opts.notchStyle
    property alias islandGap: opts.islandGap
    readonly property bool island: opts.notchStyle === "island"

    property alias notchColor: opts.notchColor
    property alias bandH: opts.bandH            // band height = notch height at rest
    property alias flare: opts.flare            // radius of the inverted top corner
    property alias roundMax: opts.roundMax      // maximum bottom radius
    property alias idleW: opts.idleW            // width at rest for the TIME ALONE; grows if you enable date or battery
    property alias hoverPreview: opts.hoverPreview
    property alias hoverDelay: opts.hoverDelay  // ms before the "peek" opens
    // Does a browser video count as "music playing"? Off: the notch only
    // changes face for real players. See ShellState.isBrowser.
    property alias browserMedia: opts.browserMedia
    property alias showDate: opts.showDate
    property alias showBattery: opts.showBattery
    property alias reserveSpace: opts.reserveSpace

    // ───────── bar ─────────
    property alias scrimAlpha: opts.scrimAlpha  // veil under the bar (0 = transparent)
    property alias sideMargin: opts.sideMargin
    property alias showArch: opts.showArch
    property alias showWorkspaces: opts.showWorkspaces
    property alias stageEnabled: opts.stageEnabled
    property alias showAppName: opts.showAppName
    property alias showTray: opts.showTray

    // ───────── launcher ─────────
    // Favourites, by .desktop entry `id` and IN ORDER: the position is what the
    // user arranges by dragging, so the list is the data, not a set.
    property alias favApps: opts.favApps
    property alias learnLauncher: opts.learnLauncher
    property alias appearanceProfiles: opts.appearanceProfiles

    // ───────── displays ─────────
    // One layout per SET of connected displays, not a global one: plugging in
    // the home monitor brings back the home layout, and unplugging it brings
    // back the laptop-alone one, without touching anything. The key is the set,
    // and displays go by description (manufacturer, model, serial number), not
    // by port: switching the cable from HDMI to DisplayPort should not lose the
    // arrangement. Displays.qml reads and writes it.
    property alias displays: opts.displays

    function appearanceSnapshot() { return Profiles.snapshot(root); }

    // TWO PROFILES WITH THE SAME NAME LOOK IDENTICAL, AND ONE GETS DELETED.
    //
    // saveProfile pushed without looking at the names in use and changeProfile
    // only required it not to be empty. The card does not show the id and the
    // notice says «Perfil guardado» (Profile saved) the same in both cases, so
    // you ended up with two identical «Focus» on screen and «Eliminar» (Delete)
    // could land on the wrong one. It is impasto's uniqueName from
    // ProfileService.qml:84-96, with the same numeric suffix and the same
    // lower-case comparison.
    function uniqueName(label, exceptId) {
        const usados = opts.appearanceProfiles
            .filter(p => p.id !== exceptId)
            .map(p => String(p.name || "").trim().toLowerCase());
        if (usados.indexOf(label.toLowerCase()) < 0) return label;
        for (let n = 2; n < 1000; n++) {
            const probe = (label + " " + n).slice(0, 48);
            if (usados.indexOf(probe.toLowerCase()) < 0) return probe;
        }
        return label;
    }

    function saveProfile(name) {
        if (!root.loaded) return false;
        const label = String(name || "").trim().slice(0, 48);
        if (!label) return false;
        const entries = opts.appearanceProfiles.slice();
        entries.push({ id: Date.now().toString(36) + Math.random().toString(36).slice(2, 8),
                       name: root.uniqueName(label, null), values: root.appearanceSnapshot() });
        opts.appearanceProfiles = entries;
        root.save();
        return true;
    }
    function changeProfile(id, name, replaceValues) {
        if (!root.loaded) return false;
        const entries = opts.appearanceProfiles.slice();
        const at = entries.findIndex(p => p.id === id);
        const label = String(name || "").trim().slice(0, 48);
        if (at < 0 || !label) return false;
        if (!replaceValues && entries[at].name === label) return true;
        entries[at] = { id: id, name: root.uniqueName(label, id),
            values: replaceValues ? root.appearanceSnapshot() : entries[at].values };
        opts.appearanceProfiles = entries;
        root.save();
        return true;
    }
    function removeProfile(id) {
        if (!root.loaded) return;
        opts.appearanceProfiles = opts.appearanceProfiles.filter(p => p.id !== id);
        root.save();
    }
    function applyProfile(values) {
        if (!root.loaded) return false;
        // complete(), not validate(), for the same reason as the thumbnail in
        // SettingsProfiles: whatever is missing is filled in with the factory
        // values instead of the whole profile silently failing to apply. What
        // gets applied is exactly what the thumbnail showed.
        const clean = Profiles.complete(values);
        if (!clean) return false;
        for (const key of Object.keys(clean)) root[key] = clean[key];
        root.applyEffects();
        root.save();
        return true;
    }

    // ───────── compositor effects ─────────
    // These two do not belong to the shell: they belong to Hyprland. They are
    // saved here like the rest so Settings stays a single place, but getting
    // them through to Hyprland is another matter entirely — see applyEffects()
    // further down.
    property alias windowRounding: opts.windowRounding
    property alias motionBlur: opts.motionBlur
    property alias motionBlurSamples: opts.motionBlurSamples

    // ───────── typography ─────────
    property alias fontUI: opts.fontUI
    property alias clockSize: opts.clockSize

    readonly property var fontChoices: [
        "Adwaita Sans", "Google Sans Flex", "Rubik", "Red Hat Text",
        "Space Grotesk", "Readex Pro", "Noto Sans"
    ]

    // Coalesce writes as Impasto does: serialising repeatedly in one QML turn
    // can read stale JsonAdapter lists and lose favourites or profile values.
    property bool loaded: false
    function save() { if (root.loaded) saver.restart(); }
    Timer { id: saver; interval: 0; onTriggered: file.writeAdapter() }

    // Hyprland does not read quickshell-rice.json, so the setting has to travel
    // by two routes, and BOTH are needed:
    //
    //   hyprctl eval    applies it live, so it shows when you flip the switch
    //                   and not on restart.
    //   efectos.lua     writes it down. hyprland.lua loads it at the end with a
    //                   protected dofile, so it survives `hyprctl reload`
    //                   —which would re-read the config and wipe out the
    //                   eval— and a session restart.
    //
    // The file is ALWAYS written, even if the eval fails: if Hyprland is not
    // listening, the setting is not lost, it just waits until the next start.
    // The other way round would not do.
    // The debounce lives here and not in the interface on purpose: the samples
    // slider emits on EVERY pixel of the drag and has no "released" signal, so
    // without this one drag launches a hundred processes and a hundred
    // rewrites of the file. The caller does not need to know — it just calls.
    function applyEffects() { debounce.restart(); }

    Timer {
        id: debounce
        interval: 180
        onTriggered: {
            // rounding_power is ALWAYS sent, and it is not filler: Hyprland
            // declares it with a minimum of 2 (ConfigValues.cpp:202, "2 is a
            // circle") and hyprland.lua had it at 0, out of range.
            // CWindow::roundingPower() clamps it to 1 when reading it, and with
            // power 1 the corner is not a quarter circle but a straight chamfer:
            // raising the rounding would have shown diamond-shaped corners. At
            // 0 px it went unnoticed because nothing was drawn.
            const lua = "hl.config({ decoration = { rounding = " + opts.windowRounding
                      + ", rounding_power = 2, motion_blur = { enabled = "
                      + (opts.motionBlur && !root.powerSaverActive ? "true" : "false")
                      + ", samples = " + opts.motionBlurSamples + " } } })";
            // The two values are a bool and an int from the JsonAdapter, never
            // free text from the user, so nobody can break these single quotes
            // by typing.
            fx.command = ["sh", "-c",
                "hyprctl eval '" + lua + "' >/dev/null 2>&1; "
                + "printf '%s\\n' "
                + "'-- Generated by Settings > Appearance > Effects. Rewritten automatically: do not edit by hand.' "
                + "'" + lua + "' > \"$HOME/.config/hypr/efectos.lua\""];
            fx.running = true;
        }
    }

    Process { id: fx }

    // THE RECONCILIATION GOES IN onLoaded, NOT IN Component.onCompleted.
    //
    // When the shell starts there is nothing to apply: hyprland.lua has already
    // read efectos.lua. This exists for when the JSON has been touched from
    // outside —by hand, or by the installer— and the two files have drifted
    // apart.
    //
    // But placed in Component.onCompleted it did exactly the opposite: that
    // handler runs BEFORE the FileView has read the JSON, so it rewrote
    // efectos.lua with the FACTORY values and wiped the saved ones on every
    // start. It went unnoticed because the only effect there was the motion
    // blur, whose factory value was the one the user had anyway; it showed up
    // when window rounding was added, which does differ. See `windowRounding`.

    function reset() {
        opts.notchStyle = "notch"; opts.islandGap = 4;
        opts.notchColor = "#000000";
        opts.bandH = 32; opts.flare = 13; opts.roundMax = 30; opts.idleW = 140;
        opts.hoverDelay = 240; opts.hoverPreview = true; opts.browserMedia = false;
        opts.showDate = false; opts.showBattery = false; opts.reserveSpace = true;
        opts.scrimAlpha = 0.0; opts.sideMargin = 16;
        opts.showArch = true; opts.showWorkspaces = true;
        opts.showAppName = true; opts.showTray = true;
        opts.fontUI = "Adwaita Sans"; opts.clockSize = 17;
        opts.windowRounding = 0;
        opts.motionBlur = true; opts.motionBlurSamples = 7;
        root.applyEffects();   // this one does not notice by itself: it has to be pushed to Hyprland
        // favApps and language are NOT touched on purpose: "restore defaults"
        // is for the appearance, and neither the favourites nor the language
        // you read the screen in are a default worth handing back.
        root.save();
    }

    FileView {
        id: file
        path: Quickshell.env("HOME") + "/.config/quickshell-rice.json"
        watchChanges: true
        onFileChanged: reload()
        onAdapterUpdated: root.save()
        onLoaded: { root.loaded = true; root.applyEffects(); }
        // First time: it does not exist -> it is created with the defaults.
        onLoadFailed: function (error) {
            if (error === FileViewError.FileNotFound) { root.loaded = true; root.save(); root.applyEffects(); }
        }

        JsonAdapter {
            id: opts

            property string language: "es"

            property string energyOnAC: "performance"
            property string energyOnBattery: "power-saver"
            property bool batteryAllowIdle: true
            property bool dimOnSaver: true
            property int saverBrightness: 40

            property string notchStyle: "notch"
            property int islandGap: 4
            property string notchColor: "#000000"
            property int bandH: 32
            property int flare: 13
            property int roundMax: 30
            property int idleW: 140
            property bool hoverPreview: true
            property int hoverDelay: 240
            property bool browserMedia: false
            property bool showDate: false   // at rest only time and battery; the full date appears on hover
            property bool showBattery: false
            property bool reserveSpace: true

            property real scrimAlpha: 0.0
            property int sideMargin: 16
            property bool showArch: true
            property bool showWorkspaces: true
            property bool stageEnabled: true
            property bool showAppName: true
            property bool showTray: true

            // On by default: it is one of the few things in the rice you see
            // without touching anything. The switch is there for the day the
            // battery matters more than the trail.
            // 0 = square corners, which is how this rice was born: focus is
            // expressed with light and not with a border, and roundness belonged
            // to the shell. It is still the factory value; now it can also be
            // changed.
            property int windowRounding: 0
            property bool motionBlur: true
            property int motionBlurSamples: 7

            property string fontUI: "Adwaita Sans"
            property int clockSize: 17

            property list<string> favApps: []
            property bool learnLauncher: true
            property var appearanceProfiles: []
            property var displays: ({})
        }
    }
}
