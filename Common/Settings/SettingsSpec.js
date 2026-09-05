.pragma library

function percentToUnit(v) {
    if (v === undefined || v === null) return undefined;
    return v > 1 ? v / 100 : v;
}

var SPEC = {
    // ---- theming -----------------------------------------------------------
    currentThemeName: { def: "dynamic" },
    currentThemeCategory: { def: "dynamic" },
    matugenScheme: { def: "scheme-content", onChange: "regenMatugen" },
    matugenSourceImage: { def: "/home/mdmmj/Pictures/Wallpapers/high_res_blue_green_space.jpg", onChange: "regenMatugen" },
    matugenSourceColor: { def: "217874", onChange: "regenMatugen" },
    matugenMode: { def: "dark", onChange: "regenMatugen" },
    popupTransparency: { def: 0.6, coerce: percentToUnit },
    widgetBackgroundColor: { def: "sc" },
    cornerRadius: { def: 11 },
    fontScale: { def: 0.94 },

    // ---- fonts / clock -----------------------------------------------------
    fontFamily: { def: "System Font" },
    monoFontFamily: { def: "JetBrainsMono NF" },
    clockFormat: { def: "24h" },
    clockDateFormat: { def: "yyyy-MM-dd" },

    // ---- dock --------------------------------------------------------------
    showDock: { def: true },
    dockAutoHide: { def: true },
    dockGroupByApp: { def: true },
    dockIconSize: { def: 45 },

    // ---- launcher ----------------------------------------------------------
    launcherLogoMode: { def: "os" },
    launcherLogoColorOverride: { def: "primary" },

    // ---- bar layout --------------------------------------------------------
    barLeftWidgets: {
        def: [
            { id: "launcherButton", enabled: true },
            { id: "workspaceSwitcher", enabled: true },
            { id: "runningApps", enabled: true },
            { id: "focusedWindow", enabled: true }
        ]
    },
    barCenterWidgets: {
        def: [
            { id: "clock", enabled: true },
            { id: "weather", enabled: true }
        ]
    },
    barRightWidgets: {
        def: [
            { id: "clipboard", enabled: true },
            { id: "notificationButton", enabled: true },
            { id: "systemTray", enabled: true },
            { id: "cpuUsage", enabled: true },
            { id: "cpuTemperature", enabled: true },
            { id: "memUsage", enabled: true },
            { id: "diskUsage", enabled: true },
            { id: "battery", enabled: true },
            { id: "controlCenterButton", enabled: true }
        ]
    },
    barTransparency: { def: 0 },
    barWidgetTransparency: { def: 0.65, coerce: percentToUnit },
    barSpacing: { def: 0 },
    barInnerPadding: { def: -2 },
    barPosition: { def: 1 },
    hiddenTrayIds: { def: [] }
};
