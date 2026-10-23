// shell.qml — entrypoint. Instantiates the components of the Quickshell system.
// The dashboard/Sidebar was retired: its content lives in the notch's Control
// Centre (ControlPanel.qml). Super+N now toggles notch <-> island.
//
// The full-screen Overview was ALSO retired (6 Aug 2026): it is now one more
// face of the notch (OverviewPanel.qml), so it is no longer a separate window
// and is not instantiated here. Its shortcut, Super+Tab, has not changed.
import Quickshell

Scope {
    id: root
    TopShell {}     // bar + notch on a single surface (replaces waybar)
    StageWindow {} // alternate visual workspace organiser
    SettingsWindow {}   // Settings app (floating window, launched from the notch)
    MediaControls {}
    WallpaperPicker {}
}
