import QtQuick

// Superficie/tarjeta reutilizable (fondo elevado + borde sutil).
Rectangle {
    radius: Appearance.radM
    color: Colors.bgAlt
    border.width: 1
    border.color: Qt.rgba(Colors.fg.r, Colors.fg.g, Colors.fg.b, 0.06)
}
