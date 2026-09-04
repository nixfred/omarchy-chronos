import QtQuick

// The year and life rails: a labelled track with the filled part carrying a
// slow sheen along it.
//
// The sheen is the point. A static bar tells you the number once; a bar with
// something travelling down it keeps saying "this is still running", which is
// what a year-progress meter actually means. It is one clipped gradient
// rectangle animating its x — no shader, no repaint.
//
// Ticks divide the track into equal segments (twelve for a year), so the fill
// can be read against something instead of floating.
Item {
  id: root

  property string label: ""
  property string valueText: ""
  // 0..1.
  property real value: 0
  property color foreground: "#ffffff"
  property color accent: "#ffffff"
  property string fontFamily: ""
  property int fontSize: 11
  property int trackHeight: 6
  property int labelGap: 12
  property int tickCount: 0
  property bool animate: true
  property bool shimmer: true
  // Hidden while the panel is showing its inline editor in this slot.
  property bool contentVisible: true

  implicitHeight: Math.max(labelText.implicitHeight, trackHeight)

  Text {
    id: labelText
    textFormat: Text.PlainText
    visible: root.contentVisible
    anchors.left: parent.left
    anchors.verticalCenter: parent.verticalCenter
    text: root.label
    color: Qt.darker(root.foreground, 1.5)
    font.family: root.fontFamily
    font.pixelSize: root.fontSize
    font.letterSpacing: 1
  }

  Text {
    id: valueLabel
    textFormat: Text.PlainText
    visible: root.contentVisible
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    text: root.valueText
    color: root.foreground
    font.family: root.fontFamily
    font.pixelSize: root.fontSize
  }

  Rectangle {
    id: track
    visible: root.contentVisible
    anchors.left: labelText.right
    anchors.right: valueLabel.left
    anchors.leftMargin: root.labelGap
    anchors.rightMargin: root.labelGap
    anchors.verticalCenter: parent.verticalCenter
    height: root.trackHeight
    radius: height / 2
    color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.12)
    clip: true

    // ---- Segment ticks, sitting under the fill so the filled part reads as
    //      solid and only the empty part is divided up.
    Repeater {
      model: root.tickCount > 1 ? root.tickCount - 1 : 0

      Rectangle {
        required property int index
        x: Math.round(track.width * (index + 1) / root.tickCount)
        width: 1
        height: track.height
        color: root.foreground
        opacity: 0.18
      }
    }

    Rectangle {
      id: fill
      width: Math.round(track.width * Math.max(0, Math.min(1, root.value)))
      height: track.height
      radius: track.radius
      color: root.accent
      clip: true

      Behavior on width { NumberAnimation { duration: 420; easing.type: Easing.OutCubic } }

      // ---- The sheen. Travels the whole track width rather than the fill
      //      width, so it keeps a constant speed as the year fills instead
      //      of speeding up in December.
      Rectangle {
        id: sheen
        visible: root.shimmer
        width: Math.max(40, track.width * 0.22)
        height: parent.height
        y: 0
        opacity: 0.0

        gradient: Gradient {
          orientation: Gradient.Horizontal
          GradientStop { position: 0.0; color: "transparent" }
          GradientStop { position: 0.5; color: Qt.rgba(1, 1, 1, 0.55) }
          GradientStop { position: 1.0; color: "transparent" }
        }

        SequentialAnimation {
          running: root.animate && root.shimmer && fill.width > 2
          loops: Animation.Infinite

          ParallelAnimation {
            NumberAnimation {
              target: sheen; property: "x"
              from: -sheen.width; to: track.width
              duration: 2600; easing.type: Easing.InOutSine
            }
            SequentialAnimation {
              NumberAnimation { target: sheen; property: "opacity"; from: 0; to: 1; duration: 500 }
              PauseAnimation { duration: 1600 }
              NumberAnimation { target: sheen; property: "opacity"; from: 1; to: 0; duration: 500 }
            }
          }

          PauseAnimation { duration: 2400 }
        }
      }
    }

    // ---- Leading edge. A brighter cap where the fill stops, pulsing so the
    //      eye lands on "here" before it reads the number on the right.
    Rectangle {
      visible: fill.width > 2 && fill.width < track.width - 1
      x: Math.max(0, fill.width - width / 2)
      width: 2
      height: track.height
      color: Qt.lighter(root.accent, 1.4)

      SequentialAnimation on opacity {
        running: root.animate
        loops: Animation.Infinite
        NumberAnimation { from: 0.35; to: 1.0; duration: 1100; easing.type: Easing.InOutSine }
        NumberAnimation { from: 1.0; to: 0.35; duration: 1100; easing.type: Easing.InOutSine }
      }
    }
  }
}
