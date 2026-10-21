pragma Singleton
import QtQuick

// Time-of-day service. A single ticking source of the current date/time so
// any widget can bind to it without each running its own timer.
QtObject {
  id: root

  property string dateString: ""
  property string weekdayString: ""
  property string timeString: ""
  property string timeWithSecondsString: ""
  property string timeWithMillisecondsString: ""

  property Timer ticker: Timer {
    id: ticker
    interval: 1000
    running: true
    repeat: true
    onTriggered: root.tick()
    Component.onCompleted: root.tick()
  }

  property Timer millisecondTicker: Timer {
    interval: 10
    running: true
    repeat: true
    onTriggered: root.updateTimeWithMilliseconds()
    Component.onCompleted: root.updateTimeWithMilliseconds()
  }

  function updateTimeWithMilliseconds() {
    var now = new Date()
    var h = now.getHours().toString().padStart(2, "0")
    var m = now.getMinutes().toString().padStart(2, "0")
    var s = now.getSeconds().toString().padStart(2, "0")
    var ms = now.getMilliseconds().toString().padStart(3, "0")
    timeWithMillisecondsString = h + ":" + m + ":" + s + "." + ms
  }

  function tick() {
    var now = new Date()
    // Force 24-hour time and ISO date regardless of system locale
    var h = now.getHours().toString().padStart(2, "0")
    var m = now.getMinutes().toString().padStart(2, "0")
    var s = now.getSeconds().toString().padStart(2, "0")
    timeString = h + ":" + m
    timeWithSecondsString = h + ":" + m + ":" + s
    var yr  = now.getFullYear().toString()
    var mo  = (now.getMonth() + 1).toString().padStart(2, "0")
    var day = now.getDate().toString().padStart(2, "0")
    dateString = yr + "-" + mo + "-" + day

    var weekdays = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
    weekdayString = weekdays[now.getDay()]
  }
}
