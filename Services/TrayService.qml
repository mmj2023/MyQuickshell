pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Services.SystemTray

// Status notifier / system tray access. Presents the SNI item model for the
// bar. Passthrough to Quickshell's own SystemTray service today; a future
// backend could substitute its own implementation behind the same interface.
QtObject {
  id: root

  readonly property var tray: SystemTray

  readonly property var items: SystemTray.items
}
