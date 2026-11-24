import QtQuick
import Quickshell

// Control Center glass (eqsh ui/controls/advanced/BoxGlass.qml + GlassRim.qml)
// copied for the dock: same grxframe rim shader, same values the Control
// Center panels use (Theme.glassColor Clear, glassRimColor,
// glassRimStrengthStrong, glassLightDirStrong). The refraction/blur behind it
// comes from the same hyprliquid "liquid_glass" rule as eqsh:blur.
Item {
    id: box

    property real  radius: 24
    property color color: "#06ffffff"             // clear glass: background shows through
    property color light: "#14ffffff"             // 1px inner light, ~+11 like the reference
    property real  rimStrength: 1.0
    property vector2d lightDir: Qt.vector2d(0, 1) // brightest on top/bottom
    property real  rimSize: 0.015                 // ~1.5px band
    property real  darkRim: 1                     // 1px outer line
    property color darkRimColor: Qt.rgba(0, 0, 0, 0.08)

    readonly property real smallerVal: Math.min(width, height)
    readonly property real r: Math.min(smallerVal / 2, radius)

    // Lightweight pure-QML frosted glass platter (zero ShaderEffect overhead)
    Rectangle {
        anchors.fill: parent
        radius: box.radius
        color: Qt.rgba(0.10, 0.10, 0.14, 0.58)
        border.width: 1
        border.color: Qt.rgba(box.light.r, box.light.g, box.light.b, Math.min(1.0, box.light.a * box.rimStrength * 2.0))
        clip: true

        Rectangle {
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 1 }
            height: parent.height * 0.45
            radius: Math.max(0, box.radius - 1)
            gradient: Gradient {
                GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.12) }
                GradientStop { position: 1.0; color: "transparent" }
            }
        }
    }

    // 1px dark line just outside the platter, on the background (as macOS)
    Rectangle {
        anchors.fill: parent
        anchors.margins: -box.darkRim
        radius: box.radius + box.darkRim
        color: "transparent"
        border.width: box.darkRim
        border.color: box.darkRimColor
        visible: box.darkRim > 0
    }
}
