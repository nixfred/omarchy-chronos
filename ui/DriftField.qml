import QtQuick

// Ambient motion behind the panel: a slow upward drift of faint motes.
//
// Kept deliberately near the noise floor — this is meant to be noticed on
// the second look, not the first. Each mote owns its own animation with its
// own duration, so nothing beats in unison and the field never reads as a
// loop. Everything stops the moment the panel closes.
Item {
  id: root

  property int count: 26
  property color tint: "#ffffff"
  property real maxOpacity: 0.09
  property bool animate: true

  clip: true

  Repeater {
    model: root.animate ? root.count : 0

    Rectangle {
      id: mote
      required property int index

      // Fixed per-mote so a rebuild does not reshuffle the field under a
      // resize; the index is a stable enough seed for something this faint.
      readonly property real seed: (Math.sin(index * 12.9898) * 43758.5453) % 1
      readonly property real seed2: (Math.sin(index * 78.233) * 43758.5453) % 1
      readonly property real span: 9000 + Math.abs(seed) * 11000

      width: 1 + Math.abs(seed2) * 1.8
      height: width
      radius: width / 2
      color: root.tint
      x: Math.abs(seed) * root.width
      opacity: 0

      SequentialAnimation {
        running: root.animate && root.visible
        loops: Animation.Infinite

        PauseAnimation { duration: Math.abs(mote.seed2) * 6000 }

        ParallelAnimation {
          NumberAnimation {
            target: mote; property: "y"
            from: root.height + 4; to: -4
            duration: mote.span; easing.type: Easing.Linear
          }
          SequentialAnimation {
            NumberAnimation {
              target: mote; property: "opacity"
              from: 0; to: root.maxOpacity * (0.4 + Math.abs(mote.seed2) * 0.6)
              duration: mote.span * 0.3; easing.type: Easing.InOutSine
            }
            NumberAnimation {
              target: mote; property: "opacity"
              to: 0
              duration: mote.span * 0.7; easing.type: Easing.InOutSine
            }
          }
          // A little lateral wander, so the field is a drift and not a
          // column of lifts.
          SequentialAnimation {
            NumberAnimation {
              target: mote; property: "x"
              to: Math.abs(mote.seed) * root.width + (mote.seed2 * 26)
              duration: mote.span * 0.5; easing.type: Easing.InOutSine
            }
            NumberAnimation {
              target: mote; property: "x"
              to: Math.abs(mote.seed) * root.width
              duration: mote.span * 0.5; easing.type: Easing.InOutSine
            }
          }
        }
      }
    }
  }
}
