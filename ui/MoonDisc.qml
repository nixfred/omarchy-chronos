import QtQuick
import "../Model.js" as Model

// Tonight's moon, drawn rather than looked up.
//
// The terminator on a real moon is the projection of a circle onto the disc,
// which is an ellipse — never the straight edge an eight-icon glyph set gives
// you. So the disc is painted: a lit half-circle, plus an ellipse half whose
// width is |cos(2·pi·phase)| and whose colour flips at the quarters. That one
// ellipse carries every shape from a hairline crescent through gibbous.
//
// The paint runs when the phase changes, not per frame — the phase moves
// about a percent a day, so this repaints on the hour at worst. The motion
// you actually see is the halo breathing behind it, which is a plain opacity
// animation and costs nothing.
Item {
  id: root

  property real phase: 0
  property color litColor: "#ffffff"
  property color darkColor: "#000000"
  property color haloColor: litColor
  // Gated by the panel so a closed popup animates nothing.
  property bool animate: true

  readonly property real illumination: Model.moonIllumination(phase)
  readonly property bool waxing: Model.moonWaxing(phase)
  readonly property string phaseName: Model.moonPhaseName(phase)

  implicitWidth: 22
  implicitHeight: 22

  // ---- Halo. Brighter the fuller the moon, so a new moon is a dim coal and
  //      a full one actually glows.
  Rectangle {
    id: halo
    anchors.centerIn: parent
    width: parent.width * 1.9
    height: width
    radius: width / 2
    color: "transparent"
    border.width: Math.max(1, root.width * 0.16)
    border.color: Qt.rgba(root.haloColor.r, root.haloColor.g, root.haloColor.b,
                          0.05 + 0.13 * root.illumination)
    opacity: 0.9

    SequentialAnimation on scale {
      running: root.animate && root.visible
      loops: Animation.Infinite
      NumberAnimation { from: 0.92; to: 1.06; duration: 3200; easing.type: Easing.InOutSine }
      NumberAnimation { from: 1.06; to: 0.92; duration: 3200; easing.type: Easing.InOutSine }
    }

    SequentialAnimation on opacity {
      running: root.animate && root.visible
      loops: Animation.Infinite
      NumberAnimation { from: 0.55; to: 1.0; duration: 3200; easing.type: Easing.InOutSine }
      NumberAnimation { from: 1.0; to: 0.55; duration: 3200; easing.type: Easing.InOutSine }
    }
  }

  Canvas {
    id: disc
    anchors.fill: parent
    antialiasing: true

    // Every input the painting depends on, so none of them can change
    // without the disc being redrawn — and nothing else can trigger one.
    readonly property real p: root.phase
    readonly property color lit: root.litColor
    readonly property color dark: root.darkColor

    onPChanged: requestPaint()
    onLitChanged: requestPaint()
    onDarkChanged: requestPaint()

    onPaint: {
      var ctx = getContext("2d")
      var w = width
      var h = height
      ctx.reset()
      ctx.clearRect(0, 0, w, h)

      var cx = w / 2
      var cy = h / 2
      var r = Math.min(w, h) / 2 - 0.5
      if (r <= 0) return

      // Unlit disc first — the crescent's dark side is a real part of the
      // moon, not the panel showing through.
      ctx.beginPath()
      ctx.arc(cx, cy, r, 0, Math.PI * 2)
      ctx.fillStyle = Qt.rgba(dark.r, dark.g, dark.b, 0.55)
      ctx.fill()

      var cosine = Math.cos(2 * Math.PI * p)
      var waxing = p < 0.5

      // The lit half. Waxing lights the right limb, waning the left.
      ctx.beginPath()
      ctx.arc(cx, cy, r, -Math.PI / 2, Math.PI / 2, !waxing)
      ctx.closePath()
      ctx.fillStyle = lit
      ctx.fill()

      // The terminator ellipse. Wider than a hairline it is the whole shape
      // of the phase; at the quarters it collapses to nothing and the disc
      // is a clean half.
      var ex = Math.abs(cosine) * r
      if (ex > 0.35) {
        ctx.beginPath()
        ctx.ellipse(cx - ex, cy - r, ex * 2, r * 2)
        // Before first quarter and after last, the ellipse eats into the lit
        // half (crescent); between them it adds to it (gibbous).
        var crescent = (p < 0.25) || (p > 0.75)
        ctx.fillStyle = crescent ? Qt.rgba(dark.r, dark.g, dark.b, 0.55) : lit
        ctx.fill()
      }

      // A rim keeps the dark limb readable against a dark panel.
      ctx.beginPath()
      ctx.arc(cx, cy, r, 0, Math.PI * 2)
      ctx.lineWidth = 1
      ctx.strokeStyle = Qt.rgba(lit.r, lit.g, lit.b, 0.35)
      ctx.stroke()
    }
  }
}
