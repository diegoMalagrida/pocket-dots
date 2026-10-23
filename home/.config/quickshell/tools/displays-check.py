#!/usr/bin/env python3
"""Exercise the display arrangement end to end, against a fake compositor.

Two halves. The first drives `scripts/monitors.py` with a `hyprctl` stub that
actually keeps state: rules go in as Lua, come back as monitors, so validation,
ordering and the timed preview are checked for real rather than mocked away.
The second loads the Settings section in an offscreen Qt process to prove the
QML agrees with it.

Nothing here touches the running desktop: temporary HOME, stubbed hyprctl, no
compositor connection.
"""
from pathlib import Path
import json
import os
import re
import shutil
import subprocess
import tempfile
import time

SOURCE = Path(__file__).resolve().parent.parent
TOOL = SOURCE / "scripts" / "monitors.py"

MODES = ["1920x1080@60.00Hz", "1920x1080@144.00Hz", "1280x720@60.00Hz"]

SCREENS = [
    {"id": 0, "name": "eDP-1", "description": "BOE 0x08D5", "make": "BOE",
     "model": "0x08D5", "serial": "", "x": 0, "y": 0, "width": 1920, "height": 1080,
     "refreshRate": 60.0, "scale": 1.0, "transform": 0, "vrr": False,
     "mirrorOf": "none", "disabled": False, "dpmsStatus": True,
     "activeWorkspace": {"id": 1}, "focused": True, "availableModes": MODES},
    {"id": 1, "name": "DP-2", "description": "Dell U2720Q ABC123", "make": "Dell",
     "model": "U2720Q", "serial": "ABC123", "x": 1920, "y": 0, "width": 1920,
     "height": 1080, "refreshRate": 144.0, "scale": 1.0, "transform": 0,
     "vrr": False, "mirrorOf": "none", "disabled": False, "dpmsStatus": True,
     "activeWorkspace": {"id": 2}, "focused": False, "availableModes": MODES},
]

# A hyprctl that remembers. `eval` parses the `hl.monitor{...}` chunks the tool
# builds and writes the result back, so the next `monitors all -j` reflects it —
# which is what makes "the preview put it back" a real assertion.
STUB = r'''#!/usr/bin/env python3
import json, re, sys
from pathlib import Path

state = Path(__file__).resolve().parent.parent / "monitors.json"
rows = json.loads(state.read_text())

if sys.argv[1:3] == ["monitors", "all"]:
    print(json.dumps(rows))
    raise SystemExit(0)

if sys.argv[1] == "eval":
    lua = " ".join(sys.argv[2:])
    by_name = {row["name"]: row for row in rows}
    for chunk in re.findall(r"hl\.monitor\(\{(.*?)\}\)", lua):
        fields = {}
        for key, value in re.findall(r'(\w+)\s*=\s*("[^"]*"|[\d.]+|true|false)', chunk):
            if value.startswith('"'):
                fields[key] = value[1:-1]
            elif value in ("true", "false"):
                fields[key] = value == "true"
            else:
                fields[key] = float(value) if "." in value else int(value)
        row = by_name.get(fields.get("output"))
        if row is None:
            print("invalid output"); raise SystemExit(0)
        if "disabled" in fields:
            row["disabled"] = fields["disabled"]
        if "mode" in fields and fields["mode"] not in ("preferred", "highres", "highrr"):
            width, rest = fields["mode"].split("x")
            height, _, refresh = rest.partition("@")
            row["width"], row["height"] = int(width), int(height)
            row["refreshRate"] = float(refresh or row["refreshRate"])
        if "position" in fields and fields["position"] != "auto":
            x, y = fields["position"].split("x")
            row["x"], row["y"] = int(x), int(y)
        if "scale" in fields and fields["scale"] != "auto":
            row["scale"] = float(fields["scale"])
        if "transform" in fields:
            row["transform"] = int(fields["transform"])
        if "vrr" in fields:
            row["vrr"] = bool(fields["vrr"])
        if "mirror" in fields:
            target = by_name.get(fields["mirror"])
            row["mirrorOf"] = str(target["id"]) if target else "none"
    state.write_text(json.dumps(rows))
    print("ok")
    raise SystemExit(0)

print("ok")
'''

QML = r"""import QtQuick
import Quickshell
Scope {
    id: root
    property int phase: 0
    property string other: "Some Other Screen"
    function check(ok, message) { if (!ok) { console.error("FAIL: " + message); Qt.exit(1); } else console.log("PASS: " + message); }
    FloatingWindow {
        visible: true
        implicitWidth: 700; implicitHeight: 620
        color: "#0b0b0b"
        SettingsDisplays { id: section; anchors.fill: parent }
    }
    Timer {
        interval: 500
        running: true
        repeat: true
        onTriggered: {
            if (root.phase === 0) {
                root.check(Displays.loaded && Displays.monitors.length === 2, "the shell reads both screens");
                root.check(Displays.setKey.indexOf("BOE") >= 0 && Displays.setKey.indexOf("Dell") >= 0,
                           "the set key names both screens");
                root.check(Displays.setKey === Displays.monitors.map(m => m.key).sort().join(" · "),
                           "and is sorted, so it does not depend on enumeration order");
                root.check(!Displays.arranged, "nothing is arranged on a fresh profile");
                const rules = Displays.layout("", null);
                root.check(rules.length === 2, "a layout carries one rule per connected screen");
                root.check(rules.every(r => !Displays.differs(r)),
                           "and taken from the current state it asks for no changes");
            } else if (root.phase === 1) {
                Displays.remember("Dell U2720Q ABC123", { position: "0x0" });
            } else if (root.phase === 2) {
                root.check(Displays.arranged, "remembering marks the set as arranged");
                root.check(!!Config.displays[Displays.setKey], "and it is stored under the set key");
                const rule = Displays.layout("", null).find(r => r.output === "DP-2");
                root.check(rule.position === "0x0", "the stored position reaches the layout");
                // Faked so that forgetting can be shown to leave other sets alone.
                const all = Object.assign({}, Config.displays);
                all[root.other] = { mirror: false, monitors: ({}) };
                Config.displays = all;
                Config.save();
            } else if (root.phase === 3) {
                root.check(section.matchCount > 0, "the section reports matches for the search");
                root.check(section.current !== null, "and has a screen selected without being asked");
                root.check(!section.onlyLit, "with two lit screens, switching one off is allowed");
                const extra = Displays.layout("BOE 0x08D5", { scale: 2 }).find(r => r.output === "eDP-1");
                root.check(extra.scale === 2, "a trial change reaches the layout without being stored");
                root.check(!Config.displays[Displays.setKey].monitors["BOE 0x08D5"],
                           "and really is not stored");
            } else if (root.phase === 4) {
                Displays.forget();
            } else if (root.phase === 5) {
                root.check(!Displays.arranged, "forgetting drops this set");
                root.check(!!Config.displays[root.other], "and leaves the other set alone");
                console.log("ALL QML CHECKS PASSED");
                Qt.exit(0);
            }
            root.phase++;
        }
    }
}
"""

STATE_QML = """pragma Singleton
import Quickshell
Singleton {
    property string settingsQuery: ""
    property string settingsHint: ""
    property bool settingsOpen: true
    function settingsMatch(label, hint) {
        return (label + " " + hint).toLowerCase().includes(settingsQuery.trim().toLowerCase());
    }
}
"""

COLORS_QML = """pragma Singleton
import Quickshell
import QtQuick
Singleton {
    property color bg: "#171b29"
    property color accent: "#b6c5ef"
    property color onWallAccent: "#b6c5ef"
    property color crit: "#e05c5c"
    property color warn: "#e0a75c"
    property string wallpaper: ""
}
"""

passed = 0


def check(ok, message):
    global passed
    if not ok:
        raise SystemExit("FAIL: " + message)
    passed += 1
    print("PASS: " + message)


def run(home, *arguments, stdin=None, timeout=40):
    environment = dict(os.environ)
    environment["PATH"] = str(home / "bin") + os.pathsep + os.defpath
    environment["XDG_RUNTIME_DIR"] = str(home / "run")
    return subprocess.run(["python3", str(TOOL), *arguments], input=stdin, env=environment,
                          text=True, capture_output=True, timeout=timeout)


def screens(home):
    return json.loads(run(home, "get").stdout)


def rules_for(rows, **changes):
    """A whole-layout rule set, as Displays.qml builds it."""
    out = []
    for row in rows:
        rule = {"output": row["name"], "disabled": row["disabled"], "mode": row["mode"],
                "position": row["position"], "scale": row["scale"],
                "transform": row["transform"], "vrr": row["vrr"], "mirror": "none"}
        rule.update(changes.get(row["name"], {}))
        out.append(rule)
    return out


def compositor(home):
    (home / "bin").mkdir(parents=True, exist_ok=True)
    (home / "run").mkdir(parents=True, exist_ok=True)
    (home / "monitors.json").write_text(json.dumps(SCREENS))
    stub = home / "bin" / "hyprctl"
    stub.write_text(STUB)
    stub.chmod(0o755)


def main():
    with tempfile.TemporaryDirectory(prefix="rice-displays-check-") as temporary:
        home = Path(temporary)
        compositor(home)

        # ── reading ──
        rows = screens(home)
        check(len(rows) == 2, "both screens are read")
        check(rows[0]["key"] == "BOE 0x08D5", "the key is the description, not the port")
        check(rows[0]["mode"] == "1920x1080@60.00", "the current mode is in the same shape as the offered ones")
        check([r["mode"] for r in rows[0]["modes"]].count("1920x1080@60.00") == 1,
              "duplicate modes are collapsed")
        check(rows[0]["resolutions"][0]["refreshes"] == [144.0, 60.0],
              "the refresh rates of a resolution come highest first")

        # ── what must never be applied ──
        both_off = rules_for(rows, **{"eDP-1": {"disabled": True}, "DP-2": {"disabled": True}})
        result = run(home, "apply", json.dumps(both_off))
        check(result.returncode == 1 and "encendida" in result.stdout,
              "refuses to switch every screen off")
        check(not screens(home)[0]["disabled"], "and nothing was applied when it refused")

        result = run(home, "apply", json.dumps(rules_for(rows, **{"DP-2": {"mode": "3840x2160@60.00"}})))
        check(result.returncode == 1 and "modo" in result.stdout,
              "refuses a mode the monitor does not advertise")

        loop = rules_for(rows, **{"eDP-1": {"mirror": "DP-2"}, "DP-2": {"mirror": "eDP-1"}})
        result = run(home, "apply", json.dumps(loop))
        check(result.returncode == 1, "refuses a mirror that loops back on itself")

        result = run(home, "apply", json.dumps([{"output": "eDP-1", "gamma": 2}]))
        check(result.returncode == 1, "refuses a field that is not on the list")

        half = [{"output": "eDP-1", "disabled": False, "mode": "1920x1080@60.00"}]
        result = run(home, "apply", json.dumps(half))
        check(result.returncode == 1, "refuses a layout that leaves a connected screen out")

        # ── what must be applied ──
        moved = rules_for(rows, **{"DP-2": {"position": "0x0"}, "eDP-1": {"position": "1920x0"}})
        check(run(home, "apply", json.dumps(moved)).returncode == 0, "applies a swap of sides")
        after = screens(home)
        check(next(r for r in after if r["name"] == "eDP-1")["position"] == "1920x0",
              "and the compositor ends up with the screens swapped")

        off = rules_for(after, **{"DP-2": {"disabled": True}})
        check(run(home, "apply", json.dumps(off)).returncode == 0, "switches one screen off")
        check(next(r for r in screens(home) if r["name"] == "DP-2")["disabled"],
              "and it stays off")

        back = rules_for(screens(home), **{"DP-2": {"disabled": False}})
        check(run(home, "apply", json.dumps(back)).returncode == 0, "switches it back on")
        check(not next(r for r in screens(home) if r["name"] == "DP-2")["disabled"],
              "and it is lit again")

        # ── the preview goes back on its own ──
        rows = screens(home)
        before = {r["name"]: r["mode"] for r in rows}
        risky = rules_for(rows, **{"DP-2": {"mode": "1280x720@60.00"}})

        # Closed stdin means whoever asked for the trial is gone — a reloaded or
        # killed shell — and there is nobody left to confirm. It goes back at
        # once rather than leaving a screen the user cannot see for 20 seconds.
        started = time.monotonic()
        result = run(home, "preview", json.dumps(risky), stdin="")
        events = [json.loads(line) for line in result.stdout.splitlines() if line.startswith("{")]
        check(any(e["event"] == "preview" for e in events), "the preview announces itself")
        check(any(e["event"] == "reverted" for e in events),
              "and goes back at once if the shell that asked for it is gone")
        check(time.monotonic() - started < 5, "without making anyone wait out the timer")
        check({r["name"]: r["mode"] for r in screens(home)} == before,
              "the screens are exactly as they were")

        # And with stdin held open and nothing said, the timer is what ends it.
        started = time.monotonic()
        waiting = subprocess.Popen(
            ["python3", str(TOOL), "preview", json.dumps(risky)],
            env={**os.environ, "PATH": str(home / "bin") + os.pathsep + os.defpath,
                 "XDG_RUNTIME_DIR": str(home / "run")},
            text=True, stdin=subprocess.PIPE, stdout=subprocess.PIPE)
        # Read to EOF instead of communicate(): communicate closes stdin, which
        # is the case just above, not this one. The pipe has to stay open.
        out = waiting.stdout.read()
        waiting.wait(timeout=40)
        events = [json.loads(line) for line in out.splitlines() if line.startswith("{")]
        check(any(e["event"] == "reverted" for e in events), "silence reverts it too")
        check(time.monotonic() - started >= 19, "after the full twenty seconds, not before")
        check({r["name"]: r["mode"] for r in screens(home)} == before,
              "and again the screens are as they were")

        # ── and stays when it is confirmed ──
        result = run(home, "preview", json.dumps(risky), stdin="keep\n")
        events = [json.loads(line) for line in result.stdout.splitlines() if line.startswith("{")]
        check(any(e["event"] == "kept" for e in events), "the preview can be kept")
        check(next(r for r in screens(home) if r["name"] == "DP-2")["mode"] == "1280x720@60.00",
              "and the change stays")

        # ── a second edit cannot run over the first ──
        slow = subprocess.Popen(
            ["python3", str(TOOL), "preview", json.dumps(rules_for(screens(home)))],
            env={**os.environ, "PATH": str(home / "bin") + os.pathsep + os.defpath,
                 "XDG_RUNTIME_DIR": str(home / "run")},
            text=True, stdin=subprocess.PIPE, stdout=subprocess.PIPE)
        time.sleep(1.5)
        second = run(home, "apply", json.dumps(rules_for(screens(home))))
        check(second.returncode == 1, "a second edit is refused while one is on trial")
        slow.communicate("keep\n", timeout=30)

        shell(home)
        print(f"\nALL CHECKS PASSED ({passed} + the QML ones)")


def shell(home):
    """The Settings section, in an offscreen Qt process, over the same stub."""
    executable = shutil.which("qs")
    if not executable:
        print("SKIP: Quickshell (qs) is not installed, the QML half did not run")
        return

    dest = home / "shell"
    dest.mkdir()
    for pattern in ["Displays.qml", "DisplayCanvas.qml", "SettingsDisplays.qml",
                    "SettingsControls.qml", "Config.qml", "Appearance.qml", "I18n.qml",
                    "Icons.qml", "translations-en.js", "AppearanceProfiles.js"]:
        for path in SOURCE.glob(pattern):
            shutil.copy2(path, dest / path.name)
    (dest / "ShellState.qml").write_text(STATE_QML)
    (dest / "Colors.qml").write_text(COLORS_QML)
    (dest / "shell.qml").write_text(QML)

    # Displays.qml looks for the tool under $HOME, so the fake home gets its own
    # copy, reading through the same hyprctl stub as the first half.
    fake = home / "qmlhome"
    (fake / ".config" / "quickshell" / "scripts").mkdir(parents=True)
    shutil.copy2(TOOL, fake / ".config" / "quickshell" / "scripts" / "monitors.py")
    (fake / ".config" / "hypr").mkdir(parents=True)

    environment = dict(os.environ)
    environment.update(HOME=str(fake), PATH=str(home / "bin") + os.pathsep + os.defpath,
                       XDG_RUNTIME_DIR=str(home / "run"),
                       QT_QPA_PLATFORM="offscreen", QT_QUICK_BACKEND="software",
                       QT_QPA_PLATFORMTHEME="", QT_QUICK_CONTROLS_STYLE="Basic")
    for key in ["WAYLAND_DISPLAY", "DISPLAY", "HYPRLAND_INSTANCE_SIGNATURE"]:
        environment.pop(key, None)

    result = subprocess.run([executable, "-p", str(dest), "--no-color"], env=environment,
                            text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                            timeout=60)
    noise = [line for line in result.stdout.splitlines()
             if "FAIL:" in line or "ReferenceError" in line or "TypeError" in line
             or "is not a type" in line or "Unable to assign" in line]
    if result.returncode or noise:
        raise SystemExit(result.stdout)
    for line in result.stdout.splitlines():
        if "PASS:" in line or "ALL QML CHECKS" in line:
            print(line.split("qml: ")[-1])


if __name__ == "__main__":
    main()
