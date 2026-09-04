import QtQuick
import QtQuick.Shapes

// A ring that fills clockwise from twelve o'clock, with the day number (or
// anything else) sitting inside it.
//
// Shapes rather than Canvas on purpose: the sweep is a plain animatable
// number, so the arc can be driven straight off a binding with a Behavior on
// it instead of asking for a repaint sixty times a second.
Item {
  id: root

  // 0..1.
  property real value: 0
  property color trackColor: "#333333"
  property color fillColor: "#ffffff"
  property real thickness: 3
  property bool animate: true
  // The leading dot marks where "now" is on the ring. Worth having on a
  // day-length arc, noise on anything that moves faster.
  property bool showHead: true

  implicitWidth: 64
  implicitHeight: 64

  readonly property real radius: Math.min(width, height) / 2 - thickness / 2
  // Not readonly: the Behavior below has to be able to drive it when the
  // binding re-evaluates.
  property real sweep: Math.max(0, Math.min(1, value)) * 360

  Behavior on sweep { NumberAnimation { duration: 520; easing.type: Easing.OutCubic } }

  Shape {
    anchors.fill: parent
    antialiasing: true
    preferredRendererType: Shape.CurveRenderer

    ShapePath {
      strokeColor: root.trackColor
      strokeWidth: root.thickness
      fillColor: "transparent"
      capStyle: ShapePath.RoundCap

      PathAngleArc {
        centerX: root.width / 2
        centerY: root.height / 2
        radiusX: root.radius
        radiusY: root.radius
        startAngle: -90
        sweepAngle: 360
      }
    }

    ShapePath {
      strokeColor: root.fillColor
      strokeWidth: root.thickness
      fillColor: "transparent"
      capStyle: ShapePath.RoundCap

      PathAngleArc {
        centerX: root.width / 2
        centerY: root.height / 2
        radiusX: root.radius
        radiusY: root.radius
        startAngle: -90
        sweepAngle: root.sweep
      }
    }
  }

  // ---- Head. Parked on the arc's leading edge by rotating a full-size
  //      container, so the dot follows the sweep without any trigonometry
  //      of its own.
  Item {
    anchors.fill: parent
    visible: root.showHead && root.value > 0.004 && root.value < 0.999
    rotation: root.sweep

    Rectangle {
      x: parent.width / 2 - width / 2
      y: parent.height / 2 - root.radius - height / 2
      width: root.thickness * 1.9
      height: width
      radius: width / 2
      color: root.fillColor

      Rectangle {
        anchors.centerIn: parent
        width: parent.width * 2.6
        height: width
        radius: width / 2
        color: "transparent"
        border.width: 1
        border.color: Qt.rgba(root.fillColor.r, root.fillColor.g, root.fillColor.b, 0.35)

        SequentialAnimation on scale {
          running: root.animate && root.visible
          loops: Animation.Infinite
          NumberAnimation { from: 0.7; to: 1.35; duration: 1600; easing.type: Easing.OutCubic }
          NumberAnimation { from: 1.35; to: 0.7; duration: 0 }
        }

        SequentialAnimation on opacity {
          running: root.animate && root.visible
          loops: Animation.Infinite
          NumberAnimation { from: 0.9; to: 0.0; duration: 1600; easing.type: Easing.OutCubic }
          NumberAnimation { from: 0.0; to: 0.9; duration: 0 }
        }
      }
    }
  }

  // No default-property alias here on purpose: aliasing the default onto a
  // nested item would swallow this component's own children too, since a
  // definition file's direct children go through the same default property.
  // Callers just anchor into the ring, which is already the right box.
}
