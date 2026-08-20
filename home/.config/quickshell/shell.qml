// shell.qml — entrypoint. Instancia los componentes del sistema Quickshell.
// El dashboard/Sidebar se retiró: su contenido vive en el centro de control
// del notch (ControlPanel.qml). Super+N ahora cambia notch <-> isla.
//
// El Overview de pantalla completa TAMBIÉN se retiró (6-ago-2026): ahora es una
// cara más del notch (OverviewPanel.qml), así que ya no es una ventana suelta y
// no se instancia aquí. Su atajo, Super+Tab, no ha cambiado.
import Quickshell

Scope {
    id: root
    TopShell {}     // barra + notch en una sola superficie (sustituye a waybar)
    SettingsWindow {}   // app de Ajustes (ventana flotante, se lanza desde el notch)
    MediaControls {}
    WallpaperPicker {}
}
