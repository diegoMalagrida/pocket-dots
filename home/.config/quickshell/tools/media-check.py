#!/usr/bin/env python3
"""Check which media players are allowed to take over the notch's face.

A video in a browser tab registers an MPRIS session exactly like Spotify does,
so the notch used to widen to 268 px, hide the date and the battery and flash
for 4.2 s for anything that made a sound in a tab. `ShellState.isBrowser`
decides who gets to do that; this exercises it against the shapes real players
actually publish.

The function is lifted straight out of ShellState.qml and run in an offscreen
Qt process, the same trick `appearance-check.py` uses for the launcher ranking:
testing a copy would only prove the copy works.

Nothing here talks to the running shell or to the session bus.
"""
from pathlib import Path
import os
import shutil
import subprocess
import tempfile

SOURCE = Path(__file__).resolve().parent.parent

# (dbusName, desktopEntry, identity, should_be_treated_as_a_browser)
#
# The real shapes, not invented ones: Chromium numbers its bus name per
# process and leaves desktopEntry empty on some builds, Firefox identifies
# itself only by identity, and Spotify fills all three in.
CASES = [
    ("org.mpris.MediaPlayer2.chromium.instance2842", "", "Chromium", True),
    ("org.mpris.MediaPlayer2.chrome.instance1", "google-chrome", "Google Chrome", True),
    ("org.mpris.MediaPlayer2.brave.instance77", "brave-browser", "Brave", True),
    ("org.mpris.MediaPlayer2.chromium.instance9", "microsoft-edge", "Microsoft Edge", True),
    ("org.mpris.MediaPlayer2.opera.instance4", "opera", "Opera", True),
    ("org.mpris.MediaPlayer2.vivaldi.instance5", "vivaldi-stable", "Vivaldi", True),
    ("org.mpris.MediaPlayer2.firefox.instance_1_5", "", "Firefox", True),
    # Must NOT be caught: these are the ones the notch exists for.
    ("org.mpris.MediaPlayer2.spotify", "spotify", "Spotify", False),
    ("org.mpris.MediaPlayer2.vlc", "vlc", "VLC media player", False),
    ("org.mpris.MediaPlayer2.mpv", "mpv", "mpv", False),
    ("org.mpris.MediaPlayer2.Feishin", "feishin", "Feishin", False),
    ("org.mpris.MediaPlayer2.kdeconnect", "kdeconnect", "KDE Connect", False),
    # Degenerate input: a player that publishes nothing must not be guessed
    # into being a browser, or music with empty metadata would stop widening.
    ("", "", "", False),
]

QML = r"""import QtQuick
import Quickshell
Scope {
    id: root
    property int fallos: 0
    // CONFIG_STUB
    // ISBROWSER
    function check(ok, message) {
        if (!ok) { console.error("FAIL: " + message); root.fallos++; }
        else console.log("PASS: " + message);
    }
    // A Timer and not Component.onCompleted: Quickshell is still building the
    // scene when that one fires, and the Qt.exit inside never got to close the
    // process -- it hung until the timeout. Same pattern as
    // appearance-check.py.
    Timer {
    interval: 300; running: true; repeat: false
    onTriggered: {
        // CASES
        // A browser player does NOT rule the notch while the setting is off,
        // and DOES rule it as soon as it is switched on.
        const chrome = ({ dbusName: "org.mpris.MediaPlayer2.chromium.instance1",
                          desktopEntry: "", identity: "Chromium" });
        const spotify = ({ dbusName: "org.mpris.MediaPlayer2.spotify",
                           desktopEntry: "spotify", identity: "Spotify" });
        Config.browserMedia = false;
        root.check(!(Config.browserMedia || !root.isBrowser(chrome)),
                   "with the setting off, the browser cannot take over the notch");
        root.check(Config.browserMedia || !root.isBrowser(spotify),
                   "with the setting off, Spotify can take over the notch");
        Config.browserMedia = true;
        root.check(Config.browserMedia || !root.isBrowser(chrome),
                   "with the setting on, the browser can take over the notch again");
        root.check(Config.browserMedia || !root.isBrowser(spotify),
                   "with the setting on, Spotify can still take over the notch");

        if (root.fallos === 0) console.log("ALL CHECKS PASSED");
        Qt.exit(root.fallos === 0 ? 0 : 1);
    }
    }
}
"""


def main():
    executable = shutil.which("qs")
    if not executable:
        raise SystemExit("Quickshell (qs) is required")

    shell = (SOURCE / "ShellState.qml").read_text()
    begin = shell.index("    readonly property var browserHints:")
    end = shell.index("    // \"Hay reproductor Y", begin)
    lifted = shell[begin:end]

    casos = []
    for bus, entry, identity, esperado in CASES:
        etiqueta = identity or "(no data)"
        casos.append(
            '        root.check(root.isBrowser({{ dbusName: "{bus}", '
            'desktopEntry: "{entry}", identity: "{identity}" }}) === {esperado}, '
            '"{etiqueta} -> {palabra}");'.format(
                bus=bus, entry=entry, identity=identity,
                esperado="true" if esperado else "false",
                etiqueta=etiqueta.replace('"', ""),
                palabra="browser" if esperado else "media player"))
    # And that a `null` does not blow the function up: `player` is null with no players.
    casos.append('        root.check(root.isBrowser(null) === false, '
                 '"no player -> not a browser");')

    with tempfile.TemporaryDirectory(prefix="rice-media-check-") as temporary:
        dest = Path(temporary)
        (dest / "Config.qml").write_text(
            "pragma Singleton\nimport Quickshell\nSingleton "
            "{ property bool browserMedia: false }\n")
        (dest / "shell.qml").write_text(
            QML.replace("    // ISBROWSER", lifted)
               .replace("        // CASES", "\n".join(casos)))

        environment = dict(os.environ)
        environment.update(QT_QPA_PLATFORM="offscreen", QT_QUICK_BACKEND="software",
                           QT_QPA_PLATFORMTHEME="", QT_QUICK_CONTROLS_STYLE="Basic")
        for key in ["WAYLAND_DISPLAY", "DISPLAY", "HYPRLAND_INSTANCE_SIGNATURE"]:
            environment.pop(key, None)

        result = subprocess.run([executable, "-p", str(dest), "--no-color"],
                                env=environment, text=True, timeout=60,
                                stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        for line in result.stdout.splitlines():
            if "PASS:" in line or "FAIL:" in line or "ALL CHECKS" in line:
                print(line.split("qml: ")[-1])
        if result.returncode:
            raise SystemExit(result.stdout)


if __name__ == "__main__":
    main()
