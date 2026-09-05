pragma Singleton
import QtCore
import QtQuick
import Quickshell
import Quickshell.Io
import "Settings/SettingsSpec.js" as Spec
import "Settings/SettingsStore.js" as Store
import "Settings/SpecUtil.js" as Util

// DMS-style SPEC-driven settings store. Declarative spec (SettingsSpec.js)
// drives a flat set of properties plus set(key, value), persisted to
// ~/.config/myquickshell/settings.json. Only non-default values are written;
// configVersion enables future migrations.
Singleton {
  id: root

  readonly property int settingsConfigVersion: 1
  readonly property string _configDir: StandardPaths.writableLocation(StandardPaths.ConfigLocation) + "/myquickshell"
  readonly property string settingsPath: _configDir + "/settings.json"

  property bool _loading: false
  property bool _selfWrite: false
  property bool _hasLoaded: false
  property bool _parseError: false

  // ---- declarative spec keys become live properties ----------------------
  // Initialised to SPEC defaults so the shell is visible before settings.json loads.
  property string currentThemeName: "dynamic"
  property string currentThemeCategory: "dynamic"
  property string matugenScheme: "scheme-content"
  property string matugenSourceImage: "/home/mdmmj/Pictures/Wallpapers/high_res_blue_green_space.jpg"
  property string matugenSourceColor: "217874"
  property string matugenMode: "dark"
  property real popupTransparency: 0.6
  property string widgetBackgroundColor: "sc"
  property int cornerRadius: 11
  property real fontScale: 0.94
  property string fontFamily: "System Font"
  property string monoFontFamily: "JetBrainsMono NF"
  property string clockFormat: "24h"
  property string clockDateFormat: "yyyy-MM-dd"
  property bool showDock: true
  property bool dockAutoHide: true
  property bool dockGroupByApp: true
  property int dockIconSize: 45
  property string launcherLogoMode: "os"
  property string launcherLogoColorOverride: "primary"
  property var barLeftWidgets: Util.cloneDef(Spec.SPEC["barLeftWidgets"].def)
  property var barCenterWidgets: Util.cloneDef(Spec.SPEC["barCenterWidgets"].def)
  property var barRightWidgets: Util.cloneDef(Spec.SPEC["barRightWidgets"].def)
  property int barTransparency: 0
  property real barWidgetTransparency: 0.65
  property int barSpacing: 0
  property int barInnerPadding: -2
  property int barPosition: 1

  // ---- helper accessors ---------------------------------------------------
  function isBarWidgetEnabled(list, id) {
    for (var i = 0; i < list.length; i++)
      if (list[i].id === id) return list[i].enabled !== false
    return false
  }

  function set(key, value) {
    if (_loading || _parseError || !_hasLoaded) return
    const spec = Spec.SPEC[key]
    if (!spec) return
    if (typeof value === "string" && spec.coerce)
      value = spec.coerce(value)
    root[key] = value
    _applyOnChange(key)
    saveSettings()
  }

  function setNoPersist(key, value) {
    if (_loading) return
    const spec = Spec.SPEC[key]
    if (!spec) return
    root[key] = value
    _applyOnChange(key)
  }

  signal matugenRegenerationRequested()
  signal settingsApplied()

  function _applyOnChange(key) {
    const spec = Spec.SPEC[key]
    const hook = spec ? spec.onChange : undefined
    if (hook === "regenMatugen") matugenRegenerationRequested()
  }

  function loadSettings() {
    _loading = true
    try {
      const txt = root._file.text()
      let obj = (txt && txt.trim()) ? JSON.parse(txt) : null
      if (obj && (obj.configVersion || 0) < settingsConfigVersion) {
        obj = Store.migrateToVersion(obj, settingsConfigVersion) || obj
      }
      Store.parse(root, obj)
      _hasLoaded = true
      _parseError = false
      _applyOnLoad()
      root.settingsApplied()
    } catch (e) {
      _parseError = true
      console.error("Failed to parse settings.json:", e.message)
    } finally {
      _loading = false
    }
  }

  function _applyOnLoad() {
    matugenRegenerationRequested()
  }

  function saveSettings() {
    if (_loading || _parseError || !_hasLoaded) return
    _selfWrite = true
    root._file.setText(JSON.stringify(Store.toJson(root), null, 2))
    _selfWrite = false
  }

  FileView {
    id: _file
    path: root.settingsPath
    atomicWrites: true
    watchChanges: true
    onLoaded: {
      if (root._selfWrite) return
      root.loadSettings()
    }
  }
}