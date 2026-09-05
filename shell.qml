//@ pragma UseQApplication
//@ pragma AppId com.myquickshell.shell

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Modules.Bar

// Entry point for the MyQuickshell shell. Wires shared singletons and mounts
// the bar. A future native backend can be started here (or spawned by dms).
ShellRoot {
  id: shell

  Bar { id: bar }
}
