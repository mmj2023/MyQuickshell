pragma Singleton

import QtCore
import QtQuick
import Quickshell
import Quickshell.Io
import "../Common/Settings/SettingsSpec.js" as Spec

// Runs the matugen CLI to generate the Material-3 colors JSON used by
// Theme.qml. Like DMS, colors are generated from a source color via
// `matugen color hex` (the simplest faithful path that reproduces the current
// DMS palette). Watches settings.json for matugenSourceColor / scheme / mode
// changes and re-runs on demand, debounced while a run is in flight.
Singleton {
  id: root

  readonly property string shellDir: Quickshell.shellDir
  readonly property string templatePath: localPath(shellDir) + "/assets/matugen/dank.json"
  readonly property string cacheDir: localPath(StandardPaths.writableLocation(StandardPaths.CacheLocation)) + "/myquickshell"
  readonly property string colorsPath: cacheDir + "/dms-colors.json"
  readonly property string configPath: cacheDir + "/matugen.toml"
  readonly property string settingsPath: localPath(StandardPaths.writableLocation(StandardPaths.ConfigLocation)) + "/myquickshell/settings.json"

  property bool _running: false
  property bool _pending: false

  function localPath(u) {
    return String(u).replace(/^file:\/\//, "")
  }

  // Merge settings.json with SPEC defaults so a fresh install (no settings.json
  // yet) still generates colors.
  function _params() {
    const spec = Spec.SPEC
    let obj = {}
    try {
      const txt = settingsFile.text()
      if (txt && txt.trim()) obj = JSON.parse(txt)
    } catch (e) { }
    return {
      sourceColor: obj.matugenSourceColor || spec.matugenSourceColor.def,
      scheme: obj.matugenScheme || spec.matugenScheme.def,
      mode: obj.matugenMode || spec.matugenMode.def
    }
  }

  // Public entry point used by Theme/Settings to (re)generate colors. Sets up
  // the config file, then chains matugen through a single bash invocation so
  // there is no race between writing the TOML and matugen reading it.
  function reschedule() {
    if (root._running) { root._pending = true; return }
    const p = root._params()
    if (!p.sourceColor) return
    root._running = true
    const toml =
      "[config]\n\n"
      + "[templates.dank]\n"
      + "input_path = '" + root.templatePath + "'\n"
      + "output_path = '" + root.colorsPath + "'\n"
    const script =
      "mkdir -p '" + root.cacheDir + "'\n"
      + "cat > '" + root.configPath + "' <<'DMS_MATGEN_EOF'\n"
      + toml
      + "DMS_MATGEN_EOF\n"
      + "matugen color hex " + p.sourceColor + " --config '" + root.configPath + "' --type " + p.scheme + " --mode " + p.mode
    matugenProc.command = ["bash", "-c", script]
    matugenProc.running = true
  }

  Process {
    id: matugenProc
    stdout: SplitParser {}
    onRunningChanged: {
      if (!matugenProc.running) {
        root._running = false
        if (root._pending) {
          root._pending = false
          root.reschedule()
        }
      }
    }
    onExited: function(status, exitStatus) {
      if (status !== 0)
        console.error("matugen failed with status " + status)
    }
  }

  FileView {
    id: settingsFile
    path: root.settingsPath
    watchChanges: true
    atomicWrites: true
    onLoaded: root.reschedule()
  }

  // Startup: a Timer is the reliable trigger for singleton services (the same
  // pattern WorkspacesService uses); Component.onCompleted is unreliable with
  // pragma Singleton.
  Timer {
    interval: 300
    running: true
    triggeredOnStart: true
    repeat: false
    onTriggered: root.reschedule()
  }
}
