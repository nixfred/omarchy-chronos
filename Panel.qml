import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "Model.js" as Model
import "ui" as Ui

// Chronos — the calendar popup, forked from omarchy.clock.
//
// The stock panel is a good, quiet read-out: a month grid, ISO weeks, a year
// rail. This keeps every bit of that behaviour — same keys, same IPC, same
// settings — and gives it a pulse.
//
// What moves, and why it earns the frames:
//   · the hero ring drains as today does, with the head marking now
//   · the year and life rails carry a sheen, so a progress bar keeps saying
//     "still running" instead of stating a number once
//   · the month arrives on a diagonal stagger and slides in the direction
//     you stepped, so you can see which way you went
//   · today breathes; the square under the pointer lights up and names itself
//   · tonight's moon is drawn from the real phase, not picked from an icon set
//   · a drift of faint motes behind it all, near the noise floor
//
// All of it is gated on the panel being open, and all of it switches off in
// one line: "sizzle": false in shell.json.
Panel {
  id: root
  moduleName: "nixfred.chronos"
  ipcTarget: "nixfred.chronos"
  manageIpc: false

  property var anchorItem: null

  // The bar tracks the widget mounted in its slot — BarWidget.qml — not this
  // nested panel. Everything the bar identifies a panel by has to be that
  // widget: the popout coordinator (and with it the open-panel dot under the
  // pill) compares against `slot.activeItem`, and switchPanelFrom looks the
  // slot up the same way.
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  // ---- Today. SystemClock keeps this honest across midnight so the
  //      highlight rolls over without the panel being reopened.
  property date today: new Date()
  readonly property string todayKey: Model.keyForDate(today)

  // The month on screen. Stepping moves this and nothing else: the grid is
  // a read-out, not a picker, so there is no per-day cursor to keep in sync.
  property int viewYear: today.getFullYear()
  property int viewMonth: today.getMonth()

  // Which way the last step went, so the grid can slide in from that side.
  // Zero for a jump home, which crossfades in place instead.
  property int stepDirection: 0

  readonly property date viewDate: new Date(viewYear, viewMonth, 1)
  readonly property bool viewingCurrentMonth: viewYear === today.getFullYear() && viewMonth === today.getMonth()

  // ---- The one switch over every moving part. Off leaves a panel that is
  //      the stock read-out plus the drawn moon, at zero animation cost.
  readonly property bool sizzle: setting("sizzle", true) !== false
  readonly property bool animating: root.sizzle && root.opened
  readonly property bool showMoon: setting("moon", true) !== false
  readonly property bool showDrift: root.sizzle && setting("drift", true) !== false
  readonly property bool showLiveTime: setting("liveTime", true) !== false

  // Pinned to now, not to the month being browsed — stepping through the
  // calendar does not change how much of the year is gone. Read off the clock
  // rather than `today` because `today` only moves at midnight, and the
  // read-outs below resolve far finer than a day.
  readonly property real yearDone: Model.yearProgressAt(clock.date)
  readonly property string yearDoneText: Model.yearProgressPercentText(clock.date, root.yearPercentDecimals)

  // The same question at the grain you actually live at. The hero ring is
  // this number; the rail below is the year's.
  readonly property real dayDone: Model.dayProgressAt(clock.date)

  readonly property real moonPhaseValue: Model.moonPhase(clock.date)

  // Two decimals by default. One hundredth of a percent of a year is ~53
  // minutes, so the figure reads differently between any two visits to the
  // panel while never moving under the eye; a single decimal is 8.8 hours and
  // would show the same number at breakfast and at dinner. Raise it toward 6
  // in shell.json to watch the year drain in closer to real time.
  readonly property int yearPercentDecimals: Model.clampYearPercentDecimals(setting("yearPercentDecimals", 2))

  // Memento mori, for anyone who goes looking: double-tapping the year bar
  // asks for a birth year and a life expectancy, and a second bar tracks one
  // against the other. A birth year rather than an age, so it keeps counting
  // on its own. Without one the bar stays hidden.
  readonly property int birthYear: Model.parseBirthYear(setting("birthYear", 0), today.getFullYear())
  readonly property int age: Model.ageFromBirthYear(birthYear, today.getFullYear())
  readonly property int lifeExpectancy: Model.parseLifeExpectancy(setting("lifeExpectancy", 0))
  readonly property real lifeDone: Model.lifeProgress(age, lifeExpectancy)
  readonly property int lifeDonePercent: Model.lifeProgressPercent(age, lifeExpectancy)
  property bool editingLife: false

  // Unset falls through to the locale's own first day, so a fresh install
  // starts out matching the rest of the desktop rather than a hardcoded
  // convention. Clicking the grid's "W" heading writes the choice back to
  // shell.json.
  readonly property int weekStart: Model.normalizedWeekStart(setting("weekStartDay", null), Qt.locale().firstDayOfWeek)
  // The interface is English throughout, so day names are not taken from the
  // system locale. Where the week starts still is: that is a regional
  // convention rather than a translation, and it stays overridable above.
  readonly property var labelLocale: Qt.locale("en_US")
  readonly property string nextWeekStartLabel: labelLocale.dayName(Model.toggledWeekStart(weekStart), Locale.LongFormat)
  readonly property var weekdays: Model.weekdayOrder(weekStart)
  readonly property var weeks: Model.monthGrid(viewYear, viewMonth, weekStart, todayKey)

  // Guarded so the widget renders before the bar is injected (the bar-widget
  // contract instantiates it bare).
  readonly property color contentForeground: bar ? bar.foreground : Color.foreground
  readonly property string contentFontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property color contentAccent: Style.selectedStateColor(contentForeground, Color.accent)

  readonly property int cellWidth: Style.space(52)
  readonly property int cellHeight: Style.space(34)
  readonly property int cellSpacing: Style.space(2)
  readonly property int weekColumnWidth: Style.space(32)
  readonly property int gutterWidth: Style.space(14)

  function open() {
    refresh()
    root.controller.show()
    // Set after showing, not before: showing hands the popout coordinator
    // over, which closes whichever panel was open, and that close clears the
    // shared flag. Deferring means the panel taking over always wins, while
    // a handoff to a panel that does not manage the flag still leaves it
    // cleared rather than stuck on.
    Qt.callLater(function() {
      if (root.opened) setCenterHoverRevealSuppressed(true)
    })
  }

  function close() {
    setCenterHoverRevealSuppressed(false)
    // Dismissing the panel mid-edit would otherwise leave the inputs up,
    // waiting behind a closed popup for the next time it opens.
    if (root.editingLife) root.cancelEditingLife()
    root.controller.hide()
  }

  function toggle() {
    if (root.opened) root.close()
    else root.open()
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  // Summoning by hotkey moves no pointer, so a hover the bar was still
  // holding must not keep the center indicators revealed behind the panel.
  function setCenterHoverRevealSuppressed(value) {
    if (root.bar && "centerHoverRevealSuppressed" in root.bar)
      root.bar.centerHoverRevealSuppressed = value
  }

  function refresh() {
    root.today = new Date()
    root.goToToday()
  }

  function goToToday() {
    root.stepDirection = 0
    root.viewYear = today.getFullYear()
    root.viewMonth = today.getMonth()
  }

  function moveMonth(delta) {
    var next = Model.stepMonth(viewYear, viewMonth, delta)
    root.stepDirection = delta > 0 ? 1 : (delta < 0 ? -1 : 0)
    root.viewYear = next.year
    root.viewMonth = next.month
  }

  function moveYear(delta) {
    moveMonth(delta * 12)
  }

  // Applied locally first so the panel redraws on the click itself; the
  // shell.json write comes back through the bar as the same value. With no
  // writable entry (the widget is not in the layout) it stays a session-only
  // preference rather than doing nothing. The host widget builds its own
  // entry when the label format is cycled, so it has to be kept in step or
  // it would write this key straight back out from a stale copy.
  function persistSettings(values) {
    var entry = { id: root.moduleName }
    for (var existing in root.settings) if (existing !== "id") entry[existing] = root.settings[existing]
    for (var key in values) entry[key] = values[key]

    root.settings = entry
    if (root.hostWidget && "settings" in root.hostWidget) root.hostWidget.settings = entry
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

  function setWeekStart(day) {
    var next = Model.normalizedWeekStart(day, root.weekStart)
    if (next === root.weekStart) return
    persistSettings({ weekStartDay: Model.weekStartSettingName(next) })
  }

  function startEditingLife() {
    root.editingLife = true
    Qt.callLater(function() {
      bornField.text = root.birthYear > 0 ? String(root.birthYear) : ""
      expectancyField.text = String(root.lifeExpectancy)
      bornField.selectAll()
      bornField.forceActiveFocus()
    })
  }

  function cancelEditingLife() {
    root.editingLife = false
    Qt.callLater(function() { if (keyCatcher) keyCatcher.forceActiveFocus() })
  }

  // Shared by both fields: Tab hops to the other one, Enter commits the pair,
  // Escape drops the lot.
  function handleLifeKey(event, other) {
    if (event.key === Qt.Key_Escape) {
      root.cancelEditingLife()
      event.accepted = true
    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
      root.commitLife()
      event.accepted = true
    } else if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
      other.selectAll()
      other.forceActiveFocus()
      event.accepted = true
    }
  }

  // Double-tapping the life bar puts it away again. The expectancy stays in
  // the config so setting a birth year again brings your own number back
  // rather than the default.
  function clearLife() {
    if (root.birthYear <= 0) return
    persistSettings({ birthYear: 0 })
  }

  function commitLife() {
    var born = Model.parseBirthYear(bornField.text, today.getFullYear())
    var span = Model.parseLifeExpectancy(expectancyField.text)
    if (born !== root.birthYear || span !== root.lifeExpectancy)
      persistSettings({ birthYear: born, lifeExpectancy: span })
    cancelEditingLife()
  }

  function toggleWeekStart() {
    setWeekStart(Model.toggledWeekStart(root.weekStart))
  }

  // English short day names, matching the rest of the interface.
  function weekdayLabel(weekday) {
    return String(labelLocale.dayName(weekday, Locale.ShortFormat)).toUpperCase()
  }

  SystemClock {
    id: clock
    // Per-second only while there is something on screen that resolves that
    // finely: the live time under the hero, or a year figure with enough
    // decimals to move faster than a minute. A closed panel ticks per minute,
    // which is all the midnight rollover below needs.
    precision: (root.opened && root.showLiveTime) || Model.yearPercentNeedsSeconds(root.yearPercentDecimals)
      ? SystemClock.Seconds
      : SystemClock.Minutes
    onDateChanged: {
      if (Model.keyForDate(clock.date) === String(root.todayKey)) return
      var followToday = root.viewingCurrentMonth
      root.today = clock.date
      if (followToday) root.goToToday()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    centerOnBar: true
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(560))
    contentHeight: panel.fittedContentHeight(calendarColumn.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: root.editingLife
      onMoveRequested: function(dx, dy) {
        if (dx !== 0) root.moveMonth(dx)
        if (dy !== 0) root.moveYear(dy)
      }
      onActivateRequested: root.goToToday()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (t === "[") root.moveMonth(-1)
        else if (t === "]") root.moveMonth(1)
        else if (t === "{") root.moveYear(-1)
        else if (t === "}") root.moveYear(1)
        else if (t === "t" || t === "T") root.goToToday()
        else if (t === "w" || t === "W") root.toggleWeekStart()
      }

      // ---- Ambient drift, behind everything and outside the Flickable so
      //      scrolling the panel does not drag the field with it.
      Ui.DriftField {
        anchors.fill: parent
        visible: root.showDrift
        animate: root.showDrift && root.opened
        tint: root.contentForeground
        count: 26
      }

      Flickable {
        id: calendarScroll
        anchors.fill: parent
        contentWidth: calendarColumn.width
        contentHeight: calendarColumn.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height || contentWidth > width

        Column {
          id: calendarColumn
          // Never narrower than the grid. The popup width is capped to what
          // the screen allows, and a fixed seven-column grid would otherwise
          // lose its last days off the edge instead of scrolling.
          width: Math.max(calendarScroll.width, gridColumn.width)
          spacing: Style.space(8)

          // ═══ Hero ═══════════════════════════════════════════════════════
          // Today, centred: the day inside a ring that drains as the day
          // does, the date beside it, and tonight's moon at the end. Once
          // the view has stepped away it is also the way home — clicking the
          // date you are looking for beats hunting for a reset button.
          Item {
            width: parent.width
            height: heroRow.height + Style.space(4)

            Row {
              id: heroRow
              anchors.horizontalCenter: parent.horizontalCenter
              spacing: Style.space(18)

              // ---- Day ring.
              Ui.ProgressRing {
                id: dayRing
                anchors.verticalCenter: parent.verticalCenter
                width: Style.space(74)
                height: width
                thickness: Style.space(4)
                value: root.dayDone
                animate: root.animating
                trackColor: Qt.rgba(root.contentForeground.r, root.contentForeground.g,
                                    root.contentForeground.b, 0.13)
                fillColor: heroMouse.containsMouse
                  ? Style.hoverStateColor(root.contentForeground, Color.accent)
                  : root.contentAccent

                Text {
                  textFormat: Text.PlainText
                  anchors.centerIn: parent
                  text: root.today.getDate()
                  color: root.contentForeground
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.space(30)
                  font.bold: true
                }

                MouseArea {
                  id: ringMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  acceptedButtons: Qt.NoButton

                  PanelToolTip {
                    visible: ringMouse.containsMouse
                    fontFamily: root.contentFontFamily
                    text: Math.round(root.dayDone * 1000) / 10 + "% of today gone  ·  "
                      + Math.round((1 - root.dayDone) * 24 * 10) / 10 + "h left"
                  }
                }
              }

              // ---- Date block.
              Column {
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(2)

                Text {
                  id: heroDate
                  textFormat: Text.PlainText
                  text: Qt.formatDate(root.today, "MMMM")
                  color: heroMouse.containsMouse
                    ? Style.hoverStateColor(root.contentForeground, Color.accent)
                    : root.contentForeground
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.space(40)
                  font.bold: true

                  Behavior on color { ColorAnimation { duration: 140 } }
                }

                Row {
                  spacing: Style.space(8)

                  Text {
                    textFormat: Text.PlainText
                    anchors.verticalCenter: parent.verticalCenter
                    text: Qt.formatDate(root.today, "dddd").toUpperCase()
                    color: Qt.darker(root.contentForeground, 1.5)
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.bodySmall
                    font.letterSpacing: 1.4
                  }

                  Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: Style.space(3)
                    height: width
                    radius: width / 2
                    color: root.contentAccent
                    visible: root.showLiveTime

                    // The one-second heartbeat, sat between the weekday and
                    // the clock where a colon would be. It is the panel's
                    // smallest moving part and the only one that keeps time.
                    SequentialAnimation on opacity {
                      running: root.animating && root.showLiveTime
                      loops: Animation.Infinite
                      NumberAnimation { from: 1.0; to: 0.15; duration: 500; easing.type: Easing.InOutSine }
                      NumberAnimation { from: 0.15; to: 1.0; duration: 500; easing.type: Easing.InOutSine }
                    }
                  }

                  Text {
                    textFormat: Text.PlainText
                    anchors.verticalCenter: parent.verticalCenter
                    visible: root.showLiveTime
                    text: Qt.formatDateTime(clock.date, "h:mm:ss AP")
                    color: Qt.darker(root.contentForeground, 1.3)
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.bodySmall
                    font.letterSpacing: 0.6
                  }
                }
              }

              // ---- Tonight's moon.
              Item {
                visible: root.showMoon
                anchors.verticalCenter: parent.verticalCenter
                width: root.showMoon ? Style.space(34) : 0
                height: Style.space(34)

                Ui.MoonDisc {
                  anchors.centerIn: parent
                  width: Style.space(30)
                  height: width
                  phase: root.moonPhaseValue
                  animate: root.animating
                  litColor: root.contentForeground
                  darkColor: Qt.rgba(0, 0, 0, 1)
                  haloColor: root.contentAccent
                }

                MouseArea {
                  id: moonMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  acceptedButtons: Qt.NoButton

                  PanelToolTip {
                    visible: moonMouse.containsMouse
                    fontFamily: root.contentFontFamily
                    text: Model.moonPhaseName(root.moonPhaseValue)
                      + "  ·  " + Math.round(Model.moonIllumination(root.moonPhaseValue) * 100) + "% lit"
                      + "  ·  full in " + Math.round(Model.moonDaysToPhase(root.moonPhaseValue, 0.5)) + "d"
                  }
                }
              }
            }

            MouseArea {
              id: heroMouse
              x: heroRow.x
              y: heroRow.y
              width: heroRow.width
              height: heroRow.height
              enabled: !root.viewingCurrentMonth
              hoverEnabled: enabled
              cursorShape: Qt.PointingHandCursor
              onClicked: root.goToToday()

              PanelToolTip {
                visible: heroMouse.containsMouse
                text: "Back to today"
                fontFamily: root.contentFontFamily
              }
            }
          }

          // ═══ Year rail ══════════════════════════════════════════════════
          // Doubling as the rule under the hero: a plain hairline said
          // nothing, and the year draining says the same thing louder.
          Item {
            width: parent.width
            height: yearBlock.y + yearBlock.height

            Item {
              id: yearBlock
              y: Style.space(6)
              anchors.horizontalCenter: parent.horizontalCenter
              width: gridColumn.width
              height: Math.max(yearRail.implicitHeight, Style.space(10))

              TapHandler {
                enabled: !root.editingLife
                onDoubleTapped: root.startEditingLife()
              }

              Ui.SizzleRail {
                id: yearRail
                anchors.fill: parent
                contentVisible: !root.editingLife
                label: String(root.today.getFullYear())
                valueText: root.yearDoneText + "%"
                value: root.yearDone
                foreground: root.contentForeground
                accent: root.contentAccent
                fontFamily: root.contentFontFamily
                fontSize: Style.font.bodySmall
                trackHeight: Style.space(6)
                labelGap: Style.space(12)
                // One notch a month, so the fill lands against something the
                // grid below already taught you to read.
                tickCount: 12
                animate: root.animating
              }

              MouseArea {
                id: yearMouse
                anchors.fill: parent
                hoverEnabled: !root.editingLife
                acceptedButtons: Qt.NoButton

                PanelToolTip {
                  visible: yearMouse.containsMouse && !root.editingLife
                  fontFamily: root.contentFontFamily
                  text: "Day " + Model.dayOfYear(root.today.getFullYear(), root.today.getMonth(), root.today.getDate())
                    + " of " + Model.daysInYear(root.today.getFullYear())
                    + "  ·  double-click for memento mori"
                }
              }

              // ---- Inline editor, in the rail's own slot.
              Row {
                visible: root.editingLife
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(10)

                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  text: "BORN"
                  color: Qt.darker(root.contentForeground, 1.5)
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.bodySmall
                  font.letterSpacing: 1
                }

                TextField {
                  id: bornField
                  width: Style.space(70)
                  anchors.verticalCenter: parent.verticalCenter
                  placeholderText: "year"
                  foreground: root.contentForeground
                  font.family: root.contentFontFamily
                  inputMethodHints: Qt.ImhDigitsOnly

                  Keys.onPressed: function(event) { root.handleLifeKey(event, expectancyField) }
                }

                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  leftPadding: Style.space(6)
                  text: "LIVE TO"
                  color: Qt.darker(root.contentForeground, 1.5)
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.bodySmall
                  font.letterSpacing: 1
                }

                TextField {
                  id: expectancyField
                  width: Style.space(60)
                  anchors.verticalCenter: parent.verticalCenter
                  placeholderText: "90"
                  foreground: root.contentForeground
                  font.family: root.contentFontFamily
                  inputMethodHints: Qt.ImhDigitsOnly

                  Keys.onPressed: function(event) { root.handleLifeKey(event, bornField) }
                }
              }
            }
          }

          // ═══ Memento mori ═══════════════════════════════════════════════
          // Only here once someone has gone looking and given a birth year;
          // the same rail as the one above it, measured against a nominal
          // lifetime rather than a calendar year.
          Item {
            visible: root.birthYear > 0
            width: parent.width
            height: visible ? lifeBlock.height : 0

            Item {
              id: lifeBlock
              anchors.horizontalCenter: parent.horizontalCenter
              width: gridColumn.width
              height: Math.max(lifeRail.implicitHeight, Style.space(10))

              Ui.SizzleRail {
                id: lifeRail
                anchors.fill: parent
                label: "LIFE"
                valueText: root.lifeDonePercent + "%"
                value: root.lifeDone
                foreground: root.contentForeground
                accent: root.contentAccent
                fontFamily: root.contentFontFamily
                fontSize: Style.font.bodySmall
                trackHeight: Style.space(6)
                labelGap: Style.space(12)
                // A decade a notch.
                tickCount: root.lifeExpectancy >= 10 ? Math.round(root.lifeExpectancy / 10) : 0
                animate: root.animating
              }

              TapHandler {
                onDoubleTapped: root.clearLife()
              }

              MouseArea {
                id: lifeMouse
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.NoButton

                PanelToolTip {
                  visible: lifeMouse.containsMouse
                  fontFamily: root.contentFontFamily
                  text: "Memento Mori  ·  " + root.age + " of " + root.lifeExpectancy
                    + "  ·  " + (root.lifeExpectancy - root.age) + " years left"
                }
              }
            }
          }

          // ═══ Month grid ═════════════════════════════════════════════════
          // Week numbers down a gutter on the left, then the seven day
          // columns. Always six rows, so the popup is exactly as tall in
          // February as it is in August.
          Item {
            width: parent.width
            height: gridColumn.y + gridColumn.height

            WheelHandler {
              onWheel: function(event) {
                // Horizontal wheels and touchpad side-scrolls report y === 0;
                // without this they would every one read as "next month".
                if (event.angleDelta.y === 0) return
                root.moveMonth(event.angleDelta.y > 0 ? -1 : 1)
              }
            }

            Column {
              id: gridColumn
              // The rail above is a solid rule; the grid needs room to read
              // as its own block rather than hanging off it.
              y: Style.space(18)
              anchors.horizontalCenter: parent.horizontalCenter
              spacing: Style.space(3)

              Row {
                id: headerRow
                spacing: root.cellSpacing

                // The week-number heading doubles as the week-start toggle.
                // It is the one control in the panel whose meaning is not
                // self-evident, so it carries a tooltip naming the day the
                // click will switch to.
                Rectangle {
                  width: root.weekColumnWidth
                  height: Style.space(16)
                  radius: Style.cornerRadius
                  color: weekStartMouse.containsMouse
                    ? Style.hoverFillFor(root.contentForeground, Color.accent)
                    : "transparent"

                  Behavior on color { ColorAnimation { duration: 130 } }

                  Text {
                    anchors.centerIn: parent
                    text: "W"
                    color: weekStartMouse.containsMouse
                      ? Style.hoverStateColor(root.contentForeground, Color.accent)
                      : Qt.darker(root.contentForeground, 1.9)
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.caption
                    font.letterSpacing: 1
                    font.bold: true
                  }

                  MouseArea {
                    id: weekStartMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.toggleWeekStart()
                  }

                  PanelToolTip {
                    visible: weekStartMouse.containsMouse
                    text: "Start weeks on " + root.nextWeekStartLabel
                    fontFamily: root.contentFontFamily
                  }
                }

                Item {
                  width: root.gutterWidth
                  height: Style.space(16)
                }

                Repeater {
                  model: root.weekdays

                  // Today's column heading is lit. On a grid where only one
                  // square is marked, naming the column too is what lets you
                  // find the day without counting across.
                  Item {
                    required property var modelData
                    readonly property bool isTodayColumn: modelData === root.today.getDay()
                    width: root.cellWidth
                    height: Style.space(16)

                    Text {
                      textFormat: Text.PlainText
                      anchors.fill: parent
                      horizontalAlignment: Text.AlignHCenter
                      verticalAlignment: Text.AlignVCenter
                      text: root.weekdayLabel(parent.modelData)
                      color: parent.isTodayColumn
                        ? root.contentAccent
                        : Qt.darker(root.contentForeground, 1.5)
                      font.family: root.contentFontFamily
                      font.pixelSize: Style.font.caption
                      font.letterSpacing: 1
                      font.bold: true

                      Behavior on color { ColorAnimation { duration: 220 } }
                    }

                    // A short underscore rather than a fill: the heading band
                    // is a label row, and a filled chip up there would compete
                    // with the marked square below it.
                    Rectangle {
                      anchors.horizontalCenter: parent.horizontalCenter
                      anchors.bottom: parent.bottom
                      width: parent.isTodayColumn ? Style.space(16) : 0
                      height: Style.spacing.hairline * 2
                      radius: height / 2
                      color: root.contentAccent
                      opacity: 0.8

                      Behavior on width { NumberAnimation { duration: 260; easing.type: Easing.OutBack } }
                    }
                  }
                }
              }

              // ---- The rows themselves, in a wrapper that slides in from
              //      whichever side you stepped from. The cells inside are
              //      rebuilt on every month change, which is what lets each
              //      one stagger its own way in.
              Item {
                id: weekStack
                width: headerRow.width
                height: root.weeks.length * root.cellHeight + (root.weeks.length - 1) * gridColumn.spacing

                Column {
                  id: weekColumn
                  width: parent.width
                  spacing: gridColumn.spacing
                  // Set by the slide below, not bound — an animation writing
                  // a bound property would drop the binding on first run.
                  x: 0

                  Repeater {
                    model: root.weeks

                    Row {
                      required property var modelData
                      required property int index
                      readonly property int weekIndex: index
                      spacing: root.cellSpacing

                      // The week you are in, called out the same way as the
                      // column above. Two faint marks bracket today rather
                      // than one square carrying the whole job.
                      Text {
                        textFormat: Text.PlainText
                        readonly property bool isTodayWeek: {
                          for (var i = 0; i < modelData.days.length; i++)
                            if (modelData.days[i].today) return true
                          return false
                        }
                        width: root.weekColumnWidth
                        height: root.cellHeight
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        text: modelData.week
                        color: isTodayWeek ? root.contentAccent : Qt.darker(root.contentForeground, 1.9)
                        font.bold: isTodayWeek
                        font.family: root.contentFontFamily
                        font.pixelSize: Style.font.caption

                        Behavior on color { ColorAnimation { duration: 220 } }
                      }

                      Item {
                        width: root.gutterWidth
                        height: root.cellHeight
                      }

                      Repeater {
                        model: modelData.days

                        Ui.DayCell {
                          required property var modelData
                          required property int index

                          width: root.cellWidth
                          height: root.cellHeight
                          cell: modelData
                          todayDate: root.today
                          foreground: root.contentForeground
                          accent: root.contentAccent
                          fontFamily: root.contentFontFamily
                          fontSize: Style.font.body
                          cornerRadius: Style.cornerRadius
                          animate: root.animating
                          enterDelay: Model.cellStaggerDelay(weekIndex, index, 13)
                        }
                      }
                    }
                  }
                }
              }
            }

            // Hairline down the week-number gutter, drawn only beside the
            // day rows so it does not cut through the header band.
            Rectangle {
              x: gridColumn.x + root.weekColumnWidth + root.cellSpacing + Math.round((root.gutterWidth - width) / 2)
              y: gridColumn.y + headerRow.height + gridColumn.spacing
              width: Style.spacing.hairline
              height: gridColumn.height - headerRow.height - gridColumn.spacing
              color: root.contentForeground
              opacity: 0.1
            }
          }

          // ═══ Month rail ═════════════════════════════════════════════════
          // Month stepping, spanning the grid it drives. The chevrons sit on
          // the grid's outer bounds, the same edges the year rail above uses,
          // so the row reads as the panel's other full-width rail instead of
          // a cluster floating in space. The label is centered and
          // fixed-width, so it holds still from "MAY" to "SEPTEMBER".
          Item {
            width: parent.width
            height: monthNav.height

            Item {
              id: monthNav
              anchors.horizontalCenter: parent.horizontalCenter
              width: gridColumn.width
              height: monthLabel.implicitHeight + Style.space(10)

              Text {
                id: monthLabel
                textFormat: Text.PlainText
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter: parent.verticalCenter
                // Fixed width so the chevrons hold still between a
                // "MAY 2026" and a "SEPTEMBER 2026".
                width: Style.space(180)
                horizontalAlignment: Text.AlignHCenter
                text: Qt.formatDate(root.viewDate, "MMMM yyyy").toUpperCase()
                  + (root.viewingCurrentMonth ? "" : "   ·   Q" + Model.quarterOf(root.viewMonth))
                color: root.viewingCurrentMonth
                  ? Qt.darker(root.contentForeground, 1.4)
                  : root.contentAccent
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.body
                font.letterSpacing: 1

                Behavior on color { ColorAnimation { duration: 200 } }
              }

              PanelActionButton {
                // Pulled out by the button's own padding so the glyph, not
                // its hit box, lines up with the "2026" on the year rail.
                anchors.left: parent.left
                anchors.leftMargin: -Style.space(8)
                anchors.verticalCenter: parent.verticalCenter
                iconText: "󰅁"
                tooltipText: "Previous month"
                foreground: root.contentForeground
                fontFamily: root.contentFontFamily
                onClicked: root.moveMonth(-1)
              }

              PanelActionButton {
                anchors.right: parent.right
                anchors.rightMargin: -Style.space(8)
                anchors.verticalCenter: parent.verticalCenter
                iconText: "󰅂"
                tooltipText: "Next month"
                foreground: root.contentForeground
                fontFamily: root.contentFontFamily
                onClicked: root.moveMonth(1)
              }
            }
          }
        }
      }
    }
  }

  // ---- The month slide. Driven off the month actually changing rather than
  //      from inside moveMonth, so a step from the keyboard, the wheel, the
  //      chevrons or a midnight rollover all animate the same way.
  onViewMonthChanged: monthSlide.restart()
  onViewYearChanged: monthSlide.restart()

  NumberAnimation {
    id: monthSlide
    target: weekColumn
    property: "x"
    from: root.stepDirection === 0 ? 0 : root.stepDirection * Style.space(34)
    to: 0
    duration: root.animating ? 340 : 0
    easing.type: Easing.OutCubic
  }
}
