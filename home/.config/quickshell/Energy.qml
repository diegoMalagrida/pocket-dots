pragma Singleton

import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import QtQuick

Singleton {
    id: root
    readonly property bool onBattery: UPower.onBattery
    property bool available: false
    property string error: ""
    readonly property bool busy: change.running || probe.running
    readonly property string active: !available ? "" :
        PowerProfiles.profile === PowerProfile.PowerSaver ? "power-saver" :
        PowerProfiles.profile === PowerProfile.Performance ? "performance" : "balanced"
    readonly property var ids: ["power-saver", "balanced", "performance"]
    readonly property var labels: [I18n.tr("Ahorro"), I18n.tr("Equilibrado"), I18n.tr("Rendimiento")]

    function valid(value) { return root.ids.indexOf(value) >= 0; }
    function label(value) {
        const i = root.ids.indexOf(value);
        return i >= 0 ? root.labels[i] : I18n.tr("No disponible");
    }
    function choose(battery, label) {
        const i = root.labels.indexOf(label);
        if (i < 0 || !Config.loaded) return;
        if (battery) Config.energyOnBattery = root.ids[i];
        else Config.energyOnAC = root.ids[i];
        Config.save();
        if (battery === root.onBattery) settle.restart();
    }
    function apply() {
        if (!Config.loaded || !root.available) return;
        if (root.busy) { settle.restart(); return; }
        const selected = root.onBattery ? Config.energyOnBattery : Config.energyOnAC;
        if (!root.valid(selected)) return;
        root.error = "";
        change.command = ["tlpctl", "set", selected];
        change.running = true;
    }
    function refresh() {
        if (!root.busy) probe.running = true;
    }
    function syncDesktop() {
        if (!Config.loaded || !root.available) return;
        if (desktop.running) { desktopUpdate.restart(); return; }
        const saving = root.active === "power-saver";
        Config.powerSaverActive = saving;
        desktop.command = [Quickshell.env("HOME") + "/.local/bin/energy-desktop",
            saving && Config.dimOnSaver ? "on" : "off",
            String(Math.max(10, Math.min(80, Config.saverBrightness)))];
        desktop.running = true;
    }
    onActiveChanged: desktopUpdate.restart()
    // TLP also receives the charger event. We apply the session preference after
    // its boot profile, without polling continuously.
    onOnBatteryChanged: settle.restart()
    Component.onCompleted: root.refresh()
    Connections {
        target: Config
        function onLoadedChanged() {
            if (Config.loaded) { settle.restart(); desktopUpdate.restart(); }
        }
        function onDimOnSaverChanged() { desktopUpdate.restart(); }
        function onSaverBrightnessChanged() { desktopUpdate.restart(); }
    }
    Timer { id: desktopUpdate; interval: 250; onTriggered: root.syncDesktop() }
    Process {
        id: desktop
        stderr: StdioCollector {}
        onExited: function(code) {
            if (code !== 0) console.warn("Power saver desktop:", stderr.text.trim());
        }
    }
    Timer { id: settle; interval: 1500; onTriggered: root.apply() }
    IpcHandler {
        target: "energy"
        function status(): string {
            return JSON.stringify({ available: root.available, active: root.active,
                onBattery: root.onBattery, onAC: Config.energyOnAC,
                onBatteryProfile: Config.energyOnBattery, error: root.error });
        }
        function refresh(): void { root.refresh(); }
        function settings(): void { ShellState.openSettingsAt("system"); }
    }
    Process {
        id: probe
        command: ["sh", "-c", "command -v tlpctl >/dev/null 2>&1 && tlpctl get"]
        stdout: StdioCollector {}
        stderr: StdioCollector {}
        onExited: function(code) {
            const wasAvailable = root.available;
            root.available = code === 0 && root.valid(stdout.text.trim());
            if (root.available && !wasAvailable) settle.restart();
        }
    }
    Process {
        id: change
        stdout: StdioCollector {}
        stderr: StdioCollector {}
        onExited: function(code) {
            if (code !== 0) {
                root.error = I18n.tr("No se pudo cambiar el perfil. Pulsa Reintentar.");
                console.warn("TLP profile change failed:", stderr.text.trim());
            }
        }
    }
}
