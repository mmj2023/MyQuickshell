import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import qs.Services

Item {
  id: root

  Variants {
    model: Quickshell.screens

    delegate: Component {
      WallpaperBackground {
        required property var modelData
        targetScreen: modelData
      }
    }
  }

  Variants {
    model: Quickshell.screens

    delegate: Component {
      WallpaperOverlay {
        required property var modelData
        targetScreen: modelData
      }
    }
  }

  IpcHandler {
    target: "wallpaper"

    function open(): string {
      WallpaperService.openOverview(Quickshell.screens[0])
      return "Opened MyQuickshell wallpaper library"
    }

    function switcher(): string {
      WallpaperService.toggleSwitcher(Quickshell.screens[0])
      return "Toggled MyQuickshell wallpaper switcher"
    }

    function close(): string {
      WallpaperService.closeOverlay()
      return "Closed MyQuickshell wallpaper overlay"
    }
  }
}
