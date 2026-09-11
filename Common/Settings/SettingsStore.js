.pragma library

.import "./SettingsSpec.js" as SpecModule
.import "./SpecUtil.js" as Util

var CONFIG_VERSION = 1;

function parse(root, jsonObj) {
    var SPEC = SpecModule.SPEC;

    // Reset every persisted key to its default when absent from the JSON
    // (including when there is no settings file yet).
    for (var k in SPEC) {
        if (SPEC[k].persist === false) continue;
        if (!jsonObj || !(k in jsonObj)) {
            root[k] = Util.cloneDef(SPEC[k].def);
        }
    }

    // Apply present values, running coerce when given.
    if (jsonObj) {
        for (var k in jsonObj) {
            if (!SPEC[k]) continue;
            var raw = jsonObj[k];
            var spec = SPEC[k];
            var coerce = spec.coerce;
            root[k] = coerce ? (coerce(raw) !== undefined ? coerce(raw) : root[k]) : raw;
        }
    }
}

function toJson(root) {
    var SPEC = SpecModule.SPEC;
    var out = {};
    for (var k in SPEC) {
        if (SPEC[k].persist === false) continue;
        var value = root[k];
        if (Util.isDefault(value, SPEC[k].def)) continue;
        out[k] = value;
    }
    out.configVersion = root.settingsConfigVersion || CONFIG_VERSION;
    return out;
}

function migrateToVersion(obj, targetVersion) {
    if (!obj) return null;
    var settings = JSON.parse(JSON.stringify(obj));
    var currentVersion = settings.configVersion || 0;
    if (currentVersion >= targetVersion) return null;
    if (currentVersion < 2) {
        var rightWidgets = settings.barRightWidgets;
        if (Array.isArray(rightWidgets) && !rightWidgets.some(function(widget) {
            return widget && widget.id === "cpuTemperature";
        })) {
            var migratedWidgets = rightWidgets.slice();
            var cpuIndex = migratedWidgets.findIndex(function(widget) {
                return widget && widget.id === "cpuUsage";
            });
            migratedWidgets.splice(cpuIndex >= 0 ? cpuIndex + 1 : migratedWidgets.length, 0, {
                id: "cpuTemperature",
                enabled: true
            });
            settings.barRightWidgets = migratedWidgets;
        }
        if (currentVersion < 3) {
            var leftWidgets = settings.barLeftWidgets;
            if (Array.isArray(leftWidgets) && !leftWidgets.some(function(widget) {
                return widget && widget.id === "submap";
            })) {
                var migratedLeftWidgets = leftWidgets.slice();
                var launcherIndex = migratedLeftWidgets.findIndex(function(widget) {
                    return widget && widget.id === "launcherButton";
                });
                migratedLeftWidgets.splice(launcherIndex >= 0 ? launcherIndex + 1 : 0, 0, {
                    id: "submap",
                    enabled: true
                });
                settings.barLeftWidgets = migratedLeftWidgets;
            }
        }
    }
    if (currentVersion < 4) {
        var centerWidgets = settings.barCenterWidgets;
        if (Array.isArray(centerWidgets) && !centerWidgets.some(function(widget) {
            return widget && widget.id === "player";
        })) {
            var migratedCenterWidgets = centerWidgets.slice();
            var clockIndex = migratedCenterWidgets.findIndex(function(widget) {
                return widget && widget.id === "clock";
            });
            migratedCenterWidgets.splice(clockIndex >= 0 ? clockIndex : migratedCenterWidgets.length, 0, {
                id: "player",
                enabled: true
            });
            settings.barCenterWidgets = migratedCenterWidgets;
        }
    }
    settings.configVersion = targetVersion;
    return settings;
}
