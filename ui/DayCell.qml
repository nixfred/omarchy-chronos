import QtQuick
import qs.Commons
import qs.Ui
import "../Model.js" as Model

// One square of the month grid.
//
// The stock cell was a number in a box with a hairline round today. This one
// keeps that as the resting state — a calendar that shouts is a calendar you
// stop reading — and adds three things that move: the month arrives on a
// diagonal stagger, today breathes, and the square under the pointer lights
// up and says what it is.
Item {
  id: root

  property var cell: null
  property color foreground: "#ffffff"
  property color accent: "#ffffff"
  property string fontFamily: ""
  property int fontSize: 13
  property int cornerRadius: 4
  property bool animate: true
  property int enterDelay: 0
  // The day the whole panel calls "today", so the read-out can say how far
  // away this square is without each cell holding its own clock.
  property date todayDate: new Date()

  readonly property bool isToday: cell ? cell.today === true : false
  readonly property bool inMonth: cell ? cell.inMonth === true : false
  readonly property bool weekend: cell ? cell.weekend === true : false

  readonly property int dayDelta: cell
    ? Model.daysBetweenCells(todayDate.getFullYear(), todayDate.getMonth(), todayDate.getDate(),
                             cell.year, cell.month, cell.day)
    : 0

  // ---- Entrance. Opacity and a short lift, delayed along the diagonal by
  //      the grid. Delegates are rebuilt whenever the month changes, so this
  //      runs once per month step and never again.
  opacity: 0

  Component.onCompleted: if (root.animate) enterAnimation.start(); else { opacity = 1; contentShift.y = 0 }

  ParallelAnimation {
    id: enterAnimation
    PauseAnimation { duration: root.enterDelay }
    NumberAnimation { target: root; property: "opacity"; from: 0; to: 1; duration: 260; easing.type: Easing.OutCubic }
    NumberAnimation { target: contentShift; property: "y"; from: 7; to: 0; duration: 320; easing.type: Easing.OutBack }
  }

  Item {
    id: contentShift
    width: parent.width
    height: parent.height
    y: root.animate ? 7 : 0

    // ---- Hover fill. Scales in from the middle rather than appearing, so
    //      a fast sweep across the grid leaves a wake instead of a strobe.
    Rectangle {
      id: hoverFill
      anchors.fill: parent
      radius: root.cornerRadius
      color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.16)
      border.width: 0
      opacity: cellMouse.containsMouse ? 1 : 0
      scale: cellMouse.containsMouse ? 1 : 0.82

      Behavior on opacity { NumberAnimation { duration: 130; easing.type: Easing.OutCubic } }
      Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutBack } }
    }

    // ---- Today: a soft standing fill, so the square reads as marked even
    //      at a glance with the pulse caught mid-fade.
    Rectangle {
      anchors.fill: parent
      visible: root.isToday
      radius: root.cornerRadius
      color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.12)
      border.width: Style.spacing.hairline
      border.color: Style.normalBorderFor(root.foreground, root.accent)
    }

    // ---- Today: the pulse. An overlay ring rather than an animated border
    //      on the cell itself — animating a border repaints the thing it is
    //      drawn on, and this one has a number in it.
    Rectangle {
      id: todayPulse
      anchors.centerIn: parent
      width: parent.width
      height: parent.height
      visible: root.isToday && root.animate
      radius: root.cornerRadius
      color: "transparent"
      // Set explicitly: a Rectangle given only a border colour still draws a
      // one-pixel border, which would outline every cell in the grid.
      border.width: 1
      border.color: root.accent
      scale: 1.0
      opacity: 0.0

      SequentialAnimation {
        running: todayPulse.visible
        loops: Animation.Infinite

        ParallelAnimation {
          NumberAnimation { target: todayPulse; property: "scale"; from: 1.0; to: 1.34; duration: 1900; easing.type: Easing.OutCubic }
          NumberAnimation { target: todayPulse; property: "opacity"; from: 0.75; to: 0.0; duration: 1900; easing.type: Easing.OutCubic }
        }
        PauseAnimation { duration: 900 }
      }
    }

    Text {
      id: dayNumber
      textFormat: Text.PlainText
      anchors.centerIn: parent
      text: root.cell ? root.cell.day : ""
      color: cellMouse.containsMouse
        ? Style.hoverStateColor(root.foreground, root.accent)
        : (root.inMonth
            ? (root.weekend ? Qt.darker(root.foreground, 1.45) : root.foreground)
            : Qt.darker(root.foreground, 2.2))
      font.family: root.fontFamily
      font.pixelSize: root.fontSize
      font.bold: root.isToday

      // A hair of lift under the pointer. Enough to feel, not enough to
      // shift the grid's rhythm.
      scale: cellMouse.containsMouse ? 1.14 : 1.0
      Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutBack } }
      Behavior on color { ColorAnimation { duration: 130 } }
    }
  }

  MouseArea {
    id: cellMouse
    anchors.fill: parent
    hoverEnabled: true
    acceptedButtons: Qt.NoButton

    PanelToolTip {
      visible: cellMouse.containsMouse && root.cell !== null
      fontFamily: root.fontFamily
      text: root.cell
        ? Qt.formatDate(new Date(root.cell.year, root.cell.month, root.cell.day), "dddd d MMMM yyyy")
          + "  ·  day " + Model.cellDayOfYear(root.cell)
          + "  ·  " + Model.relativeDayText(root.dayDelta)
        : ""
    }
  }
}
