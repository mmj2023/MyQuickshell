pragma Singleton
import QtCore
import QtQuick
import Qt.labs.platform
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Services

// Material 3 style singleton mapping the matugen-generated colors JSON to Dank
// tokens exactly like DMS Theme.qml. Colors are watched live via FileView so a
// matugen re-run re-themes instantly. widgetBackgroundColor etc. are read from
// SettingsData (guarded) matching DMS semantics.
Singleton {
  id: root

  // DMS remains the source of truth until MyQuickshell's own generator is
  // complete. Keep the local path ready as the future preferred source.
  readonly property string colorsPath: String(StandardPaths.writableLocation(StandardPaths.GenericCacheLocation)).replace(/^file:\/\//, "") + "/DankMaterialShell/dms-colors.json"
  readonly property string localColorsPath: String(StandardPaths.writableLocation(StandardPaths.GenericCacheLocation)).replace(/^file:\/\//, "") + "/MyQuickshell/mql-colors.json"

  property var matugenColors: ({})
  readonly property bool isLightMode: String(matugenColors.mode || "dark") === "light"

  FileView {
    id: colorsFile
    path: root.colorsPath
    atomicWrites: true
    watchChanges: true
    onLoaded: {
      root.loadColors(colorsFile.text())
    }
    onFileChanged: colorsFile.reload()
    onLoadFailed: localColorsFile.reload()
  }

  FileView {
    id: localColorsFile
    path: root.localColorsPath
    atomicWrites: true
    watchChanges: true
    onLoaded: {
      if (Object.keys(root.matugenColors).length === 0)
        root.loadColors(localColorsFile.text())
    }
    onFileChanged: localColorsFile.reload()
  }

  function loadColors(text) {
    try {
      if (text && text.trim())
        root.matugenColors = JSON.parse(text)
    } catch (e) {
      if (Object.keys(root.matugenColors).length === 0)
        root.matugenColors = ({})
    }
  }

  // Instantiate and drive MatugenService. Referencing it here (Theme is always
  // loaded) guarantees the colors pipeline is running from shell startup.
  readonly property var _ownedMatugen: MatugenService

  Connections {
    target: SettingsData
    function onMatugenRegenerationRequested() {
      MatugenService.reschedule()
    }
  }

  function getMatugenColor(path, fallback) {
    return getMatugenColorForMode(root.isLightMode ? "light" : "dark", path, fallback)
  }

  function getMatugenColorForMode(colorMode, path, fallback) {
    let cur = root.matugenColors && root.matugenColors.colors && root.matugenColors.colors[colorMode]
    for (const part of path.split(".")) {
      if (!cur || typeof cur !== "object" || !(part in cur))
        return fallback
      cur = cur[part]
    }
    return cur === undefined || cur === null || cur === "" ? fallback : cur
  }

  // ---- color helpers (DMS equivalents) -------------------------------------
  function withAlpha(c, a) {
    if (!c || c.r === undefined) return Qt.rgba(0, 0, 0, 0)
    return Qt.rgba(c.r, c.g, c.b, a)
  }

  function blendAlpha(c, a) {
    if (!c || c.r === undefined) return Qt.rgba(0, 0, 0, 0)
    return Qt.rgba(c.r, c.g, c.b, c.a * a)
  }

  function blend(c1, c2, r) {
    return Qt.rgba(c1.r * (1 - r) + c2.r * r, c1.g * (1 - r) + c2.g * r, c1.b * (1 - r) + c2.b * r, c1.a * (1 - r) + c2.a * r)
  }

  function hoverTint(base) {
    const factor = 1.2
    return root.isLightMode ? Qt.darker(base, factor) : Qt.lighter(base, factor)
  }

  function luminance(c) {
    if (!c || c.r === undefined) return 0
    return 0.299 * c.r + 0.587 * c.g + 0.114 * c.b
  }

  function isLightColor(c, threshold = 0.5) {
    return root.luminance(c) > threshold
  }

  function safeColor(value, fallback) {
    try {
      if (value === undefined || value === null || value === "") return fallback
      return Qt.color(value)
    } catch (e) {
      return fallback
    }
  }

  // ---- current theme data (exact DMS mapping) ------------------------------
  readonly property var currentThemeData: {
    "primary": getMatugenColor("primary", "#85d4cf"),
    "primaryText": getMatugenColor("on_primary", "#003735"),
    "primaryContainer": getMatugenColor("primary_container", "#217874"),
    "secondary": getMatugenColor("secondary", "#aecdca"),
    "secondaryContainer": getMatugenColor("secondary_container", getMatugenColor("surface_container_high", "#272b2a")),
    "tertiary": getMatugenColor("tertiary", "#d8bbf8"),
    "tertiaryContainer": getMatugenColor("tertiary_container", getMatugenColor("surface_container_high", "#272b2a")),
    "surface": getMatugenColor("surface", getMatugenColor("background", "#101414")),
    "surfaceText": getMatugenColor("on_background", "#e0e3e2"),
    "surfaceVariant": getMatugenColor("surface_variant", "#3e4948"),
    "surfaceVariantText": getMatugenColor("on_surface_variant", "#bec9c7"),
    "surfaceTint": getMatugenColor("surface_tint", "#85d4cf"),
    "background": getMatugenColor("background", "#101414"),
    "backgroundText": getMatugenColor("on_background", "#e0e3e2"),
    "outline": getMatugenColor("outline", "#889391"),
    "surfaceContainerLowest": getMatugenColor("surface_container_lowest", "#0b0f0f"),
    "surfaceContainerLow": getMatugenColor("surface_container_low", "#181c1c"),
    "surfaceContainer": getMatugenColor("surface_container", "#1c2020"),
    "surfaceContainerHigh": getMatugenColor("surface_container_high", "#272b2a"),
    "surfaceContainerHighest": getMatugenColor("surface_container_highest", "#313635"),
    "surfaceBright": getMatugenColor("surface_bright", "#313635"),
    "surfaceDim": getMatugenColor("surface_dim", "#101414"),
    "error": getMatugenColor("error", "#ffb4ab"),
    "warning": "#ff9800",
    "info": "#2196f3",
    "success": "#4caf50"
  }

  // ---- color tokens (from currentThemeData so mapping is DMS-identical) ----
  readonly property color primary: currentThemeData.primary
  readonly property color primaryText: currentThemeData.primaryText
  readonly property color onPrimary: primaryText
  readonly property color primaryContainer: currentThemeData.primaryContainer
  readonly property color secondary: currentThemeData.secondary
  readonly property color secondaryContainer: currentThemeData.secondaryContainer
  readonly property color tertiary: currentThemeData.tertiary
  readonly property color tertiaryContainer: currentThemeData.tertiaryContainer
  readonly property color error: currentThemeData.error
  readonly property color warning: currentThemeData.warning

  readonly property color surface: currentThemeData.surface
  readonly property color surfaceText: currentThemeData.surfaceText
  readonly property color onSurface: surfaceText
  readonly property color surfaceVariant: currentThemeData.surfaceVariant
  readonly property color surfaceVariantText: currentThemeData.surfaceVariantText
  readonly property color onSurfaceVariant: surfaceVariantText
  readonly property color surfaceTint: currentThemeData.surfaceTint
  readonly property color background: currentThemeData.background
  readonly property color backgroundText: currentThemeData.backgroundText
  readonly property color outline: currentThemeData.outline
  readonly property color outlineVariant: getMatugenColor("outline_variant", "#3e4948")

  readonly property color surfaceContainerLowest: currentThemeData.surfaceContainerLowest
  readonly property color surfaceContainerLow: currentThemeData.surfaceContainerLow
  readonly property color surfaceContainer: currentThemeData.surfaceContainer
  readonly property color surfaceContainerHigh: currentThemeData.surfaceContainerHigh
  readonly property color surfaceContainerHighest: currentThemeData.surfaceContainerHighest
  readonly property color surfaceBright: currentThemeData.surfaceBright
  readonly property color surfaceDim: currentThemeData.surfaceDim

  readonly property color inverseSurface: getMatugenColor("inverse_surface", "#e0e3e2")
  readonly property color inversePrimary: getMatugenColor("inverse_primary", "#056a66")
  readonly property color shadow: Qt.rgba(0, 0, 0, 0.4)
  readonly property color scrim: getMatugenColor("scrim", "#000000")

  readonly property color surfaceTextHover: withAlpha(surfaceText, 0.08)
  readonly property color surfaceText_8: withAlpha(surfaceText, 0.08)
  readonly property color surfaceText_12: withAlpha(surfaceText, 0.12)
  readonly property color surfaceText_38: withAlpha(surfaceText, 0.38)
  readonly property color primaryHover: withAlpha(primary, 0.12)
  readonly property color primaryPressed: withAlpha(primary, 0.16)
  readonly property color surfaceHover: withAlpha(surfaceVariant, 0.08)
  readonly property color surfacePressed: withAlpha(surfaceVariant, 0.12)
  readonly property color surfaceSelected: withAlpha(surfaceVariant, 0.15)

  // ---- widget background (reads SettingsData like DMS) ---------------------
  property var widgetBaseBackgroundColor: {
    const colorMode = typeof SettingsData !== "undefined" ? SettingsData.widgetBackgroundColor : "sc"
    switch (colorMode) {
    case "s": return surface
    case "sc": return surfaceContainer
    case "sch": return surfaceContainerHigh
    case "primaryContainer": return primaryContainer
    case "secondaryContainer": return secondaryContainer
    case "tertiaryContainer": return tertiaryContainer
    default: return surfaceContainer
    }
  }

  property color widgetBaseHoverColor: {
    const blended = root.blend(widgetBaseBackgroundColor, primary, 0.1)
    return withAlpha(blended, Math.max(0.3, blended.a))
  }

  property color widgetIconColor: surfaceText
  property color widgetInactiveIconColor: withAlpha(widgetIconColor, 0.6)
  property color widgetTextColor: surfaceText

  // ---- text / icon sizing (DMS logic scaled off barThickness/48) -----------
  readonly property real fontSizeSmall: Math.round(fontScale * 12)
  readonly property real fontSizeMedium: Math.round(fontScale * 14)
  readonly property real iconSize: 24
  readonly property real iconSizeSmall: 16
  readonly property real iconSizeLarge: 32

  function barIconSize(barThickness, offset, maximizeIcon, iconScale) {
    const defaultOffset = offset !== undefined ? offset : -6
    const size = (maximizeIcon ?? false) ? root.iconSizeLarge : root.iconSize
    const s = iconScale !== undefined ? iconScale : 1.0
    return Math.round((barThickness / 48) * (size + defaultOffset) * s)
  }

  function barTextSize(barThickness, fontScale, maximizeText) {
    const scale = barThickness / 48
    const dankBarScale = fontScale !== undefined ? fontScale : 1.0
    const maxScale = (maximizeText ?? false) ? 1.5 : 1.0
    if (scale <= 0.75)
      return Math.round(root.fontSizeSmall * 0.9 * dankBarScale * maxScale)
    if (scale >= 1.25)
      return Math.round(root.fontSizeMedium * dankBarScale * maxScale)
    return Math.round(root.fontSizeSmall * dankBarScale * maxScale)
  }

  // DMS-style DPR-aware rounding helpers.
  function screenScaleOf(screen) {
    if (!screen) return 1
    return (screen.scale || screen.devicePixelRatio || 1)
  }

  function snap(value, dpr) {
    const s = dpr !== undefined ? dpr : 1
    return Math.round(value * s) / s
  }

  function px(value) {
    return root.snap(value, 1)
  }

  // ---- layout / typography (from SettingsData when available) --------------
  readonly property string fontFamily: typeof SettingsData !== "undefined" ? SettingsData.fontFamily : "Inter Variable"
  readonly property string monoFontFamily: typeof SettingsData !== "undefined" ? SettingsData.monoFontFamily : "JetBrainsMono NF"
  readonly property real fontScale: typeof SettingsData !== "undefined" ? SettingsData.fontScale : 0.94
  readonly property int cornerRadius: typeof SettingsData !== "undefined" ? SettingsData.cornerRadius : 11
  readonly property int pillRadius: 999

  readonly property int barThickness: 28
  readonly property int barHeight: 16
  readonly property int widgetThickness: 26
  readonly property int barPosition: typeof SettingsData !== "undefined" ? SettingsData.barPosition : 1

  // ---- spacing --------------------------------------------------------------
  readonly property int spaceXXS: 2
  readonly property int spaceXS: 4
  readonly property int spaceS: 8
  readonly property int spaceM: 12
  readonly property int spaceL: 16
  readonly property int spaceXL: 24

  function space1() { return 4 }
  function space2() { return 8 }
  function space3() { return 12 }
  function space4() { return 16 }

  // ---- animation -------------------------------------------------------------
  readonly property int shortDuration: 150
  readonly property int mediumDuration: 250
  readonly property int longDuration: 400
  readonly property int standardEasing: Easing.OutCubic

  // ---- icon resolution helpers -----------------------------------------------
  function themedIconPath(name) {
    if (!name) return ""
    return Quickshell.iconPath(name, true)
  }

  function getAppIcon(appId) {
    if (!appId) return themedIconPath("application-x-executable")

    var directIcon = themedIconPath(appId)
    if (directIcon) return directIcon

    var lower = appId.toLowerCase()
    var lowerIcon = themedIconPath(lower)
    if (lowerIcon) return lowerIcon

    // Strip common prefixes or suffixes
    var parts = appId.split(".")
    var lastPart = parts[parts.length - 1]
    if (lastPart) {
      var lastIcon = themedIconPath(lastPart)
      if (lastIcon) return lastIcon
      var lastLowerIcon = themedIconPath(lastPart.toLowerCase())
      if (lastLowerIcon) return lastLowerIcon
    }

    return themedIconPath("application-x-executable")
  }
}
