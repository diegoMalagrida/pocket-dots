// WallpaperFx.qml — the wallpaper transitions, drawn by the shell instead of awww.
//
// awww's transitions (fade, wipe, grow, wave...) are the ones the rice used
// until 2026-10-30, picked at random, and Diego put it plainly: "they look like
// PowerPoint 2013". These are two of our own, in a shader (shaders/wallfx.frag),
// with the maps of ~/.local/bin/wallfx:
//
//   contagio  colonies landing at random places eat through the old wallpaper
//             in crisp 4 px cells, each one burning for an instant in the new
//             palette's most vivid colour.
//   perfil    if the new wallpaper has a character: a thin quiet line draws
//             its outline, it fills in, and the rest spreads out of it with
//             the same cells. Nonchalant on purpose ("less neon", Diego).
//
// HOW IT HANDS OVER WITH AWWW. awww keeps being the wallpaper: this only lives
// for the length of the change, in a layer ABOVE awww and below the windows
// (Bottom, empty in this rice). The order is what makes it seamless:
//   1. load both images and the maps, off the main thread (~130 ms);
//   2. start the transition and, at the same time, fade in over awww. At t≈0
//      the transition IS the old wallpaper, so the fade is between two renders
//      of the same image and nobody sees it;
//   3. once fully covered, switch awww instantly (transition none) underneath;
//   4. the transition ends on the new image, which awww now shows too;
//   5. fade out, and the textures are released.
// Switching awww in the middle instead of before is what removes the wait: it
// takes ~150 ms, and that used to be a frozen frame before anything moved.
// If anything fails to load within 2.5 s, awww changes on its own with a plain
// fade: the wallpaper must change even if the effect cannot be shown.
//
// IPC (set-wallpaper.sh calls it; `wallfx elige` picks the kind and its maps):
//   qs ipc call wallfx play OLD NEW contagio|perfil MAP LINE
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import QtQuick

Scope {
    id: root

    // ─── test hooks: a second qs on a headless output, without awww ───
    readonly property string onlyScreen: Quickshell.env("WALLFX_ONLY") || ""
    readonly property bool dry: Quickshell.env("WALLFX_DRY") === "1"

    // ─── tuning ───
    // Scene changes are not in the motion scale's steps (those are for things
    // INSIDE a scene). They are registered in motion-language.md as ESCENA.
    property int msContagio: 1800
    property int msPerfil: 2000
    property int msFade: 130          // RESPUESTA: the hand-over is a cross-fade between
                                      // two renders of the same image, i.e. invisible
    property real glow: 0.9
    property real lineW: 1.5

    // ─── one change ───
    property string oldPath: ""
    property string newPath: ""
    property string kind: "contagio"
    property string fieldPath: ""
    property string linePath: ""
    property bool autoGo: true
    // idle → loading → run (→ held, until awww has switched) → fadeout → idle;
    // in the lab (dry) loading → ready, held there until `go`.
    property string phase: "idle"
    property real t: 0
    property real fade: 0
    property bool swapped: false
    property int gen: 0               // one per change: late news from an older one is ignored
    property int swapGen: -1
    // Captured from the new palette when the change starts: the contagion's
    // burning edge (its most vivid colour) and the outline's line (its
    // lightest tone).
    property color ember: "orange"
    property color ink: "white"
    property real seed: 0
    property int readyCount: 0
    readonly property int screenCount: screens.instances.length
    readonly property bool active: phase !== "idle"
    function lifted(c) {
        // A palette colour can be dark; the burning edge has to light up.
        return Qt.hsla(c.hslHue, Math.max(c.hslSaturation, 0.55),
                       Math.min(Math.max(c.hslLightness, 0.62), 0.82), 1)
    }

    function prepare(o, n, k, f, l, go) {
        if (root.active) root.finish()
        root.oldPath = o; root.newPath = n
        root.kind = k === "perfil" ? "perfil" : "contagio"
        root.fieldPath = f; root.linePath = l || f
        root.autoGo = go
        root.t = 0; root.fade = 0; root.readyCount = 0; root.swapped = false
        root.gen++
        root.phase = "loading"
        watchdog.restart()
    }
    function screenReady() {
        if (root.phase !== "loading") return
        root.readyCount++
        if (root.readyCount < root.screenCount) return
        watchdog.stop()
        if (root.dry) { root.fade = 1; root.phase = "ready"; if (root.autoGo) root.go(); return }
        root.go()
    }
    function go() {
        if (root.phase !== "ready" && root.phase !== "loading") return
        // Captured now, not bound: Colors repaints when pywal writes, and the
        // front must not change colour halfway through.
        const pal = [Colors.bg, Colors.c1, Colors.c2, Colors.c3, Colors.c4, Colors.c5, Colors.dim, Colors.fg]
        const chroma = c => c.hslSaturation * (1 - Math.abs(2 * c.hslLightness - 1))
        const light = c => 0.299 * c.r + 0.587 * c.g + 0.114 * c.b
        // the most vivid colour, not the accent: the accent can be a cream
        // that vanishes on a cream sky
        root.ember = root.lifted(pal.reduce((a, b) => chroma(b) > chroma(a) ? b : a))
        root.ink = pal.reduce((a, b) => light(b) > light(a) ? b : a)
        root.seed = Math.random() * 100
        root.phase = "run"
        run.duration = root.kind === "perfil" ? root.msPerfil : root.msContagio
        run.restart()
        if (!root.dry) fadeIn.restart()
    }
    // Uncover only when the transition has ended AND awww shows the new one.
    function maybeFinish() {
        if (root.dry) { if (!run.running) root.phase = "done"; return }
        if (run.running) return
        if (!root.swapped) { root.phase = "held"; watchdog.restart(); return }
        root.phase = "fadeout"
        fadeOut.restart()
    }
    // In the lab (WALLFX_ONLY) awww may only touch that output: the others are
    // the real desktop.
    function awwwImg(path, extra) {
        return ["awww", "img", path].concat(root.onlyScreen ? ["--outputs", root.onlyScreen] : [], extra)
    }
    function swap() {
        root.swapGen = root.gen
        awww.command = root.awwwImg(root.newPath, ["--transition-type", "none"])
        awww.running = true
    }
    function finish() {
        fadeIn.stop(); run.stop(); fadeOut.stop(); watchdog.stop(); settle.stop()
        root.phase = "idle"; root.fade = 0; root.t = 0
        root.oldPath = ""; root.newPath = ""; root.fieldPath = ""; root.linePath = ""
    }

    NumberAnimation { id: fadeIn; target: root; property: "fade"; from: 0; to: 1
        duration: root.msFade; easing.type: Easing.OutQuad
        onFinished: root.swap() }
    // `t` is TIME, so it runs linear; each phase eases its own stretch in the
    // shader with the motion language's curves.
    NumberAnimation { id: run; target: root; property: "t"; from: 0; to: 1
        easing.type: Easing.Linear
        onFinished: root.maybeFinish() }
    // How the last transition ran: `qs ipc call wallfx stats`. A scene change
    // that stutters is worse than the plain fade it replaced, so this is
    // measured on the real screen, not assumed.
    property int statFrames: 0
    property real statWorst: 0
    property string lastStats: ""
    FrameAnimation {
        running: root.phase === "run"
        onRunningChanged: if (running) { root.statFrames = 0; root.statWorst = 0 }
                          else if (root.statFrames > 0)
                              root.lastStats = root.kind + ": " + root.statFrames + " fotogramas en "
                                  + run.duration + " ms (" + Math.round(root.statFrames * 1000 / run.duration)
                                  + " fps), el peor de " + Math.round(root.statWorst * 1000) + " ms"
        onTriggered: { root.statFrames++; if (root.statFrames > 2) root.statWorst = Math.max(root.statWorst, frameTime) }
    }

    NumberAnimation { id: fadeOut; target: root; property: "fade"; from: 1; to: 0
        duration: root.msFade; easing.type: Easing.OutQuad
        onFinished: root.finish() }

    Process {
        id: awww
        // If awww did not switch, uncovering would bring the OLD one back at the
        // end: better to stop here and let awww try on its own.
        // An awww from a change that has since been replaced is left to finish
        // on its own: killing it, or reacting to it, would cut the new one.
        onExited: (code) => {
            if (root.swapGen !== root.gen) return
            if (code === 0) { settle.restart(); return }
            const n = root.newPath
            root.finish()
            Quickshell.execDetached(root.awwwImg(n, ["--transition-type", "fade", "--transition-duration", "0.5"]))
        }
    }
    // awww has the new image; give it two frames to present it before anything
    // can uncover it.
    Timer { id: settle; interval: 40; onTriggered: { root.swapped = true; root.maybeFinish() } }

    // Two ways to get stuck, two ways out: the images never load (awww changes
    // on its own), or awww never answers (the layer, already showing the new
    // wallpaper, steps aside anyway instead of staying on top for good).
    Timer {
        id: watchdog; interval: 2500
        onTriggered: {
            const n = root.newPath, loading = root.phase === "loading"
            root.finish()
            if (loading && !root.dry && n)
                Quickshell.execDetached(root.awwwImg(n, ["--transition-type", "fade", "--transition-duration", "0.5"]))
        }
    }

    IpcHandler {
        target: "wallfx"
        function play(oldImg: string, newImg: string, kind: string, field: string, line: string): string {
            root.prepare(oldImg, newImg, kind, field, line, true); return "ok"
        }
        // For tests: load and hold the first frame; `go` starts it.
        function prepare(oldImg: string, newImg: string, kind: string, field: string, line: string): string {
            root.prepare(oldImg, newImg, kind, field, line, false); return "ok"
        }
        function go(): string { root.go(); return root.phase }
        function state(): string { return root.phase }
        function stats(): string { return root.lastStats }
        function stop(): string { root.finish(); return "ok" }
        function tune(key: string, value: string): string {
            root[key] = Number(value)
            return key + "=" + root[key]
        }
    }

    Variants {
        id: screens
        model: Quickshell.screens.filter(s => !root.onlyScreen || s.name === root.onlyScreen)

        PanelWindow {
            id: win
            required property var modelData
            screen: modelData
            visible: root.active
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            anchors { top: true; bottom: true; left: true; right: true }
            mask: Region {}                       // clicks go through to the desktop
            WlrLayershell.layer: WlrLayer.Bottom
            WlrLayershell.namespace: "quickshell:wallfx"

            readonly property bool loaded: oldImg.status === Image.Ready && newImg.status === Image.Ready
                && fieldImg.status === Image.Ready && lineImg.status === Image.Ready
            onLoadedChanged: if (loaded) root.screenReady()

            // Decoded at the size of the screen (covering it), not at the size
            // of the file: a 6 MB wallpaper does not need 24 MB of texture.
            Image { id: oldImg; visible: false; asynchronous: true; cache: false
                source: root.oldPath ? "file://" + root.oldPath : ""
                sourceSize: Qt.size(win.width, win.height); fillMode: Image.PreserveAspectCrop }
            Image { id: newImg; visible: false; asynchronous: true; cache: false
                source: root.newPath ? "file://" + root.newPath : ""
                sourceSize: Qt.size(win.width, win.height); fillMode: Image.PreserveAspectCrop }
            // The maps hold numbers, not colours: contagion's are read texel by
            // texel (no filtering), the outline's are interpolated on purpose.
            Image { id: fieldImg; visible: false; asynchronous: true; cache: false
                smooth: root.kind === "perfil"
                source: root.fieldPath ? "file://" + root.fieldPath : "" }
            Image { id: lineImg; visible: false; asynchronous: true; cache: false
                source: root.linePath ? "file://" + root.linePath : "" }

            // awww's "crop": scale to cover the screen, centred.
            function crop(img) {
                const iw = Math.max(img.implicitWidth, 1), ih = Math.max(img.implicitHeight, 1)
                const s = Math.max(win.width / iw, win.height / ih)
                const w = win.width / (iw * s), h = win.height / (ih * s)
                return Qt.vector4d((1 - w) / 2, (1 - h) / 2, w, h)
            }

            ShaderEffect {
                anchors.fill: parent
                visible: win.loaded
                opacity: root.fade
                property var oldTex: oldImg
                property var newTex: newImg
                property var fieldTex: fieldImg
                property var lineTex: lineImg
                property real t: root.t
                property real mode: root.kind === "perfil" ? 1 : 0
                property real sw: win.width
                property real sh: win.height
                property real fw: Math.max(fieldImg.implicitWidth, 1)
                property real fh: Math.max(fieldImg.implicitHeight, 1)
                property real lw: Math.max(lineImg.implicitWidth, 1)
                property real lh: Math.max(lineImg.implicitHeight, 1)
                property real glow: root.glow
                property real lineW: root.lineW
                property real sdRange: 16
                property real seed: root.seed
                property vector4d cropOld: win.crop(oldImg)
                property vector4d cropNew: win.crop(newImg)
                property color ember: root.ember
                property color ink: root.ink
                // Versioned name: Qt caches compiled shaders by URL (see TopShell).
                fragmentShader: Qt.resolvedUrl("shaders/wallfx.v15.frag.qsb")
            }
        }
    }
}
