#!/usr/bin/env python3
"""Exercise settings persistence, profiles and launcher ranking in an isolated Qt process.

Requires Quickshell. Uses a temporary HOME and a harmless hyprctl stub; no live
shell, compositor settings or user preferences are changed.
"""
from pathlib import Path
import json
import os
import shutil
import subprocess
import tempfile

SOURCE = Path(__file__).resolve().parent.parent
QML = r"""import QtQuick
import Quickshell
import Quickshell.Io
Scope {
    id: root
    property var allApps: [
        {id: "exact", name: "Code"}, {id: "prefix", name: "Code - Insiders"},
        {id: "other", name: "Firefox"}
    ]
    // SEARCH_FUNCTIONS
    property int phase: 0
    property var original: null
    property string profileId: ""
    function check(ok, message) { if (!ok) { console.error("FAIL: " + message); Qt.exit(1); } else console.log("PASS: " + message); }
    FloatingWindow {
        visible: true
        implicitWidth: 660; implicitHeight: 580
        color: "#0b0b0b"
        Item {
            id: canvas
            anchors.fill: parent
            Rectangle { anchors.fill: parent; color: "#0b0b0b" }
            SettingsAppearance { id: appearance; anchors.fill: parent; visible: root.phase < 5 }
            SettingsProfiles { id: profiles; anchors.fill: parent; visible: root.phase >= 5 && root.phase < 9 }
            SettingsLauncher { anchors.fill: parent; visible: root.phase >= 9 }
        }
    }
    Timer {
        interval: 400
        running: true
        repeat: true
        onTriggered: {
            if (root.phase === 0) {
                root.original = Config.appearanceSnapshot();
                Config.language = "en";
                Config.favApps = ["keep-me"];
                root.check(Config.saveProfile("Original"), "create profile");
            } else if (root.phase === 1) {
                root.check(Config.appearanceProfiles.length === 1, "profile is visible after persistence");
                root.profileId = Config.appearanceProfiles[0].id;
                Config.notchStyle = "island";
                Config.bandH = 40;
                Config.hoverPreview = false;
            } else if (root.phase === 2) {
                root.check(Config.applyProfile(root.original), "apply profile");
            } else if (root.phase === 3) {
                root.check(Config.bandH === root.original.bandH && Config.notchStyle === root.original.notchStyle && Config.hoverPreview, "restore appearance values");
                root.check(Config.language === "en" && Config.favApps[0] === "keep-me", "preserve language and favourites");
                const broken = Object.assign({}, root.original, { bandH: -100 });
                root.check(!Config.applyProfile(broken) && Config.bandH === root.original.bandH, "reject invalid profile without partial changes");
                root.check(Config.changeProfile(root.profileId, "Renamed", false), "rename profile");

            } else if (root.phase === 4) {
                root.check(Config.appearanceProfiles[0].name === "Renamed", "rename persists");
                LauncherUsage.record("test.app");
            } else if (root.phase === 5) {
                root.check(LauncherUsage.scoreOf("test.app") > 0.99, "record launch");
                LauncherUsage.record("test.app");
            } else if (root.phase === 6) {
                root.check(LauncherUsage.scoreOf("test.app") > 1.99, "accumulate launches without losing a write");
                root.check(LauncherUsage.scoreOf("missing.app") === 0, "unknown app has no usage score");

            } else if (root.phase === 7) {
                Config.changeProfile(root.profileId, "Updated", true);
            } else if (root.phase === 8) {
                root.check(Config.appearanceProfiles[0].name === "Updated", "update snapshot");
                Config.removeProfile(root.profileId);
                LauncherUsage.clear();
            } else if (root.phase === 9) {
                root.check(Config.appearanceProfiles.length === 0, "delete profile");
                root.check(LauncherUsage.count === 0, "clear launch history");
            } else if (root.phase === 10) {
                Config.saveProfile("Survives reload");
                LauncherUsage.record("survives.app");
                for (let i = 0; i < 12; i++) LauncherUsage.record("prefix");
            } else if (root.phase === 11) {
                root.check(LauncherUsage.scoreOf("prefix") > 11.99, "batch launches without losing increments");
                root.check(root.searchApps("code")[0].id === "exact", "exact search outranks frequently launched prefix");
                root.check(root.searchApps("")[0].id === "prefix", "frequent application comes first without a query");
                Config.learnLauncher = false;
            } else if (root.phase === 12) {
                root.check(root.searchApps("")[0].id === "exact", "turning learning off restores alphabetical order");
                console.log("ALL CHECKS PASSED"); Qt.quit();
            }
            root.phase++;
        }
    }
}
"""

RELOAD_QML = """import QtQuick
import Quickshell
Scope {
    Timer {
        interval: 400; running: true; repeat: true
        onTriggered: {
            if (!Config.loaded || !LauncherUsage.ready) return;
            if (Config.appearanceProfiles.length !== 1
                || Config.appearanceProfiles[0].name !== "Survives reload"
                || Config.language !== "en" || Config.favApps[0] !== "keep-me"
                || LauncherUsage.scoreOf("survives.app") < 0.99) {
                console.error("FAIL: reload persisted data"); Qt.exit(1); return;
            }
            console.log("PASS: profiles, favourites, language and launch counts survive a fresh process");
            Qt.quit();
        }
    }
}
"""


def main():
    executable = shutil.which("qs")
    if not executable:
        raise SystemExit("Quickshell (qs) is required")
    with tempfile.TemporaryDirectory(prefix="rice-settings-check-") as temporary:
        dest = Path(temporary)
        for pattern in ["Settings*.qml", "AppearanceProfiles.js", "LauncherUsage.qml",
                        "Config.qml", "Appearance.qml", "I18n.qml", "translations-en.js", "Icons.qml"]:
            for path in SOURCE.glob(pattern):
                shutil.copy2(path, dest / path.name)
        (dest / "ShellState.qml").write_text("""pragma Singleton
import Quickshell
Singleton {
    property string settingsQuery: ""
    property string settingsHint: ""
    function settingsMatch(label, hint) {
        return (label + " " + hint).toLowerCase().includes(settingsQuery.trim().toLowerCase());
    }
}
""")
        (dest / "Colors.qml").write_text("""pragma Singleton
import Quickshell
import QtQuick
Singleton {
    property color bg: "#171b29"
    property color accent: "#b6c5ef"
    property color accent2: "#e0a458"
    property color fg: "#dcd8d1"
    property color onWallAccent: "#b6c5ef"
    property color crit: "#e05c5c"
    property string wallpaper: ""

    // The stub has to offer the same as the real singleton, or the bar
    // preview blows up with "is not a function" and the check blames the
    // wrong party. These three came with the fixes of 26 Sep 2026.
    property string notchTheme: "theme"
    function notchTint(v) { return (!v || String(v) === notchTheme) ? bg : v; }
    function inkOn(base) { return bg; }
    property color accentText: bg
    property color accent2Text: bg
}
""")
        (dest / "home/.config/hypr").mkdir(parents=True)
        (dest / "bin").mkdir()
        (dest / "bin/hyprctl").write_text("#!/bin/sh\nexit 0\n")
        (dest / "bin/hyprctl").chmod(0o755)
        environment = dict(os.environ)
        environment.update(HOME=str(dest / "home"), PATH=str(dest / "bin") + os.pathsep + os.defpath,
                           QT_QPA_PLATFORM="offscreen", QT_QUICK_BACKEND="software",
                           QT_QPA_PLATFORMTHEME="", QT_QUICK_CONTROLS_STYLE="Basic")
        for key in ["WAYLAND_DISPLAY", "DISPLAY", "HYPRLAND_INSTANCE_SIGNATURE"]:
            environment.pop(key, None)
        shell = (SOURCE / "ShellState.qml").read_text()
        begin = shell.index("    function scoreApp(")
        end = shell.index("    // ═", begin)
        qml = QML.replace("    // SEARCH_FUNCTIONS", shell[begin:end])
        for document in [qml, RELOAD_QML]:
            (dest / "shell.qml").write_text(document)
            result = subprocess.run([executable, "-p", str(dest), "--no-color"], env=environment,
                                    text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=15)
            failures = [line for line in result.stdout.splitlines()
                        if "FAIL:" in line or "ERROR" in line or "ReferenceError" in line or "TypeError" in line]
            if result.returncode or failures:
                raise SystemExit(result.stdout)
            for line in result.stdout.splitlines():
                if "PASS:" in line or "ALL CHECKS" in line:
                    print(line.split("qml: ")[-1])
        saved = json.loads((dest / "home/.config/quickshell-rice.json").read_text())
        assert saved["favApps"] == ["keep-me"] and saved["language"] == "en"
        assert saved["appearanceProfiles"][0]["name"] == "Survives reload"
        print("PASS: stored JSON agrees with the reloaded settings")


if __name__ == "__main__":
    main()
