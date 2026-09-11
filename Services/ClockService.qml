pragma Singleton
import QtQuick

// Time-of-day service. A single ticking source of the current date/time so
// any widget can bind to it without each running its own timer.
QtObject {
  id: root

  property string dateString: ""
  property string weekdayString: ""
  property string timeString: ""

  readonly property bool showSeconds: false

  property Timer ticker: Timer {
    id: ticker
    interval: 1000
    running: true
    repeat: true
    onTriggered: root.tick()
    Component.onCompleted: root.tick()
  }

  function tick() {
    var now = new Date()
    // Force 24-hour time and ISO date regardless of system locale
    var h = now.getHours().toString().padStart(2, "0")
    var m = now.getMinutes().toString().padStart(2, "0")
    var s = now.getSeconds().toString().padStart(2, "0")
    timeString = root.showSeconds ? (h + ":" + m + ":" + s) : (h + ":" + m)
    var yr  = now.getFullYear().toString()
    var mo  = (now.getMonth() + 1).toString().padStart(2, "0")
    var day = now.getDate().toString().padStart(2, "0")
    dateString = yr + "-" + mo + "-" + day

    var weekdays = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
    weekdayString = weekdays[now.getDay()]
  }
}
