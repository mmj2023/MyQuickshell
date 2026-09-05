# MyQuickshell — Implementation Details

How DMS and omarchy do things, and what MyQuickshell will do. Reference for
Phases 0-4 (config store, dynamic matugen theming, DMS-style bar, tray fix,
omarchy-style launcher). The full settings app is a later phase.

---

## 1. Config store — DMS SPEC/JSON pattern

**How DMS does it.** `quickshell/Common/SettingsData.qml` is a `pragma
Singleton`. It is not hand-wired; it is driven by a declarative spec:
- `Common/settings/SettingsSpec.js` — one entry per setting key:
  `{ def, coerce?, onChange?, persist? }`, e.g.
  `cornerRadius: { def: 16, onChange: "updateCompositorLayout" }`.
- `Common/settings/SettingsStore.js` — generic `parse(root, json)` (reset every
  SPEC key to `cloneDef`, then apply JSON values running `coerce`) and
  `toJson(root)` (**only writes keys that differ from default** + emits
  `configVersion`), plus `migrateToVersion` for legacy migrations.
- `Common/settings/SpecUtil.js` — `isDefault`, `cloneDef`, shared helpers.
- Writes to `~/.config/DankMaterialShell/settings.json`.
- Public API: module-level QML `property` per key + `set(key, value)`, which
  sets `root[key]`, fires the `onChange` hook, and `saveSettings()`. `_loading`
  / `_selfWrite` guards prevent write-back loops during load.
- A parallel `SessionData` (same pattern) stores transient/runtime state in a
  separate `session.json`.

**How omarchy does it.** Split stores: `~/.config/omarchy/shell.json` (bar
layout + inline `settings` on each widget entry, written atomically via
`FileView`), theme `colors.toml`/`shell.toml`, and the menu `omarchy-menu.jsonc`
(user overlay merged over `default/`). If a user file exists it is
authoritative; no migration machinery.

**What MyQuickshell will do.** Replicate DMS's Spec/Store/SpecUtil trio as
self-contained files under `Common/Settings/` (no DMS import). `SettingsData.qml`
singleton exposes flat properties + `set(key, value)` and persists to
`~/.config/myquickshell/settings.json` with `settingsConfigVersion`. Declare a
subset of keys: cornerRadius, fontScale, monoFontFamily, clockFormat,
clockDateFormat, popupTransparency, widgetTransparency, widgetBackgroundColor,
matugenScheme, matugenSourceImage, matugenMode, showDock, currentThemeName, bar
layout lists, launcher settings. Defaults seeded from the user's current DMS
values.

---

## 2. Dynamic theming — full local matugen pipeline

**How DMS does it.** `quickshell/Common/Theme.qml` (2342 lines) has a
`dynamicColorsFileView` (a `FileView` on a JSON colors file). On file change the
colors reload live. Three theme categories: registry (stock), dynamic
(matugen), custom. The token props are **computed QML properties** derived from
`matugenColors`:
- `matugenColors` = JSON `{ dank16: {...}, mode, colors: { dark: {...}, light:
  {...} } }` — produced by the `dank.json` matugen template.
- Mapping helper `getMatugenColorForMode(mode, path, fallback)` walks
  `matugenColors.colors[mode][path]`.
- `buildExtractedDynamicMode`/`currentThemeData` map material keys to Dank
  tokens: `primary<-primary`, `surface<-surface`, `surfaceText<-on_background`,
  `surfaceVariant<-surface_variant`, `surfaceVariantText<-on_surface_variant`,
  `surfaceContainer*<-surface_container*`, `outline<-outline`, `tertiary<-tertiary`,
  `surfaceTint<-surface_tint`, `background<-background`.
- Switching theme runs the `dms matugen queue --state-dir ... --shell-dir ...
  --config-dir ... --kind ... --value <img> --mode ... --matugen-type
  scheme-content` Go subprocess, and the watcher re-reads the JSON.
- `matugenAvailable` checked via `command -v matugen`.

**How omarchy does it.** Custom non-M3 token system (not Material 3). Theme =
`themes/<name>/colors.toml` (semantic palette) + `shell.toml` templates. Applied
at runtime by rendering templates then calling shell IPC `applyTheme` with
base64 payloads → `Color.loadColors()` → binding re-evaluation. Light/dark is a
whole-theme switch (no single dark-mode toggle).

**What MyQuickshell will do (self-contained, no DMS Go binary).**
- Bundle a matugen template (JSON, mirroring DMS `dank.json`: `dank16` + full
  `colors.dark/light` M3 keys).
- `Services/MatugenService.qml` runs the `matugen` CLI directly:
  `matugen image <img> --type <scheme> --mode <mode> --template <tpl-file>`
  (Quickshell `Process` + `StdioCollector`), writing
  `~/.cache/myquickshell/dms-colors.json`. Debounced re-run on wallpaper/scheme/
  mode change.
- `Common/Theme.qml` reads the JSON via `FileView`, maps `colors[mode]` → Dank
  tokens exactly like DMS's `getMatugenColor` + `currentThemeData` (this is the
  mapping our static Theme already anticipated; only the source becomes dynamic).
- Built-in fallback palette so the shell loads without `matugen`.
- Seeded: `matugenScheme: "scheme-content"`, `matugenSourceImage:
  ~/Pictures/Wallpapers/high_res_blue_green_space.jpg`, `matugenMode: "dark"`.

---

## 3. Bar — DMS BasePill convention

**How DMS does it.** Every bar widget is a `BasePill.qml`
(`quickshell/Modules/Plugins/BasePill.qml`):
- Sizing scales off a `widgetThickness`/`barThickness` ratio (padding =
  `snap((widgetConfig?.widgetPadding ?? 12) * (widgetThickness/30), dpr)`).
- Background `Rectangle` radius `Theme.cornerRadius`, color from
  `Theme.widgetBaseBackgroundColor` (switched by `SettingsData.widgetBackgroundColor`
  mode; our user's = `"sc"` → surfaceContainer), blended by
  `widgetTransparency`; hover = `Theme.widgetBaseHoverColor`
  (`blend(base, primary, 0.1)`).
- Optional outline (`widgetOutlineEnabled/Color/Opacity`), `DankRipple`, MouseArea
  with clicked/rightClicked/wheel, blur registration.
- Icon/text sizes from `Theme.barIconSize(barThickness,...)` /
  `Theme.barTextSize(barThickness, fontScale, maximizeText)` scaling off
  `barThickness/48`.
- Bar host (`DankBarBody`/`DankBarContent`) lays out BasePills into
  left/center/right from `SettingsData` lists.

**What MyQuickshell will do.** Build a small `BasePill.qml` replica (rounded
pill, transparency blend, hover, optional outline, scaling helpers). Bar
(`Modules/Bar/Bar.qml` + `BarBody`) renders per-screen, layout driven by
SettingsData left/center/right lists mirroring the user's DMS barConfigs:
- left: launcher button, workspace switcher, running apps, focused window
- center: clock, weather placeholder, system tray
- right: clipboard, notifications, cpu/mem/disk, battery, control-center button

---

## 4. Tray clickability fix

**How DMS does it.** `SystemTrayBar.qml` iterates `SystemTray.items.values` (the
real SNI item objects), filters `DMS_HIDE_TRAYIDS`, renders each icon in
`IconImage`, left-click `trayItem.activate()`, right-click opens the SNI menu
via `showForTrayItem` (a `DankPopout`), handles `onlyMenu` (if only-menu, left
click opens the menu directly).

**Why ours is broken.** MyQuickshell `SystemTrayWidget.qml` uses a `Repeater`
over `model: TrayService.items` (`= SystemTray.items`) and reads `modelData` as
the item. The Repeater's `modelData` may not be the SNI object exposing
`activate()`/`display()`, so clicks call methods on the wrong thing → no-op.

**What MyQuickshell will do.** Iterate `SystemTray.items.values` explicitly and
give each delegate the real item. Wire left-click `activate()` (falling back to
menu when `onlyMenu`), right-click `display()`-style SNI menu, hover/pressed
pill states. Keep a simple overflow popup as a stretch goal.

---

## 5. Launcher — data-driven (omarchy) in a DMS frame

**How omarchy does it.** One `omarchy.menu` plugin IS launcher + palette +
settings. Everything is data in `omarchy-menu.jsonc`:
- Dotted IDs imply submenu tree (`style.bar.transparency` nests under
  `style.bar`). Kind inferred: `action`=action, `target`=link, children=submenu.
- Fields: `label`, `icon`, `aliases`, `description`, `action` (shell cmd),
  `checked` (bash condition; append ✓), `when` (bash; hide row), `disabled`
  (bash; dim + ✓ + unselectable), `provider` (lazy submenu source), `title`.
- `MenuModel.js` (pure JS): `nameSearchText()` = label+aliases+id;
  `matchesQuery()` requires **every** whitespace term to appear; `searchScore()`
  is tiered (exact 2/0, word 0, prefix 10, infix 30, nameText 40, desc 60;
  menus -2, apps -5; `score*1000 + depth*25 + order`).
- `Menu.qml` renders a `PanelWindow` overlay + centered `BorderSurface` card with
  a `ListView`; drilldown via `navStack`/`activeMenu`/`goBack()`; `keyCatcher`
  handles Up/Down/PgUp/PgDn/Enter/Esc/Delete/Backspace and printable→filter.
- Providers load rows lazily via bash (`fonts`, `power-profiles`) or natively
  (`apps` via AppLibrary). Guards (`when`/`checked`/`disabled`) are **batched
  into one bash process** (`guardScript()`) then cached.
- Inline settings = menu rows calling commands: `style.theme`,
  `style.background`, `style.bar.position.top`, `style.bar.transparency`,
  `trigger.toggle.nightlight`, `trigger.toggle.window-gaps`, `setup.network.dns.*`,
  etc. `checked:` radio rows show current value (DHCP/Cloudflare, etc.).

**How DMS does it.** `DankLauncherV2/` is controller/model split: headless
`Controller.qml` + `Scorer.js` (relevance scoring with tokenize / word boundary /
levenshtein / frecency type bonuses) + `ResultsList`/`ResultItem` rendering, with
a **trigger-prefix** system (`@` web, `=` calc, `>` shell, `.` emoji, `?`
settings, `cb` clipboard, `qrg` qr) and frecency-ranked `AppSearchService`
(DesktopEntries). Rendered in several modal *frames* (Spotlight/Standalone/
Island/Connected) sharing one controller.

**What MyQuickshell will do (hybrid).**
- `Modals/Launcher/` — one modal: `PanelWindow` overlay (omarchy) inside a
  centered DMS-spotlight-style card.
- Data-driven engine: bundled `menu.jsonc` with dotted IDs + `action`/`checked`/
  `when`/`disabled`/`aliases`; parse with `FileView` `watchChanges: true`,
  merged with a user overlay if present.
- `MenuModel.js` (pure JS `.pragma library`) replicating omarchy matching +
  tiered scoring.
- Search merges menu items + DesktopEntries apps (Quickshell `DesktopEntries` /
  AppLibrary-style). Providers (fonts, power-profiles) as stretch.
- Batched guard evaluation like `guardScript()`.
- keyboard drilldown nav, `revealCursor`.
- Inline settings sections: **Style** (Theme → switch matugen way, Background →
  set wallpaper→re-theme, Bar position/transparency), **Toggle** (nightlight,
  top bar, window gaps, touchpad), **Setup** (default browser/terminal), System
  (lock/logout/reboot/power).
- Opens via keybind (global shortcut) + bar launcher button; `settings` button
  scaffolds the future full DMS-style settings app (Phase 5).
- Stretch: DMS trigger prefixes (`@` `=` `>` `.`).

---

## 6. Future settings app (Phase 5, not this session)

**How DMS does it.** `Modals/Settings/` shell (sidebar Modal + per-tab `Loader`)
+ `Modules/Settings/*Tab.qml` pages + `Modules/Settings/Widgets/` reusable rows
(`SettingsToggleRow` extends `DankToggle` with `settingKey`/`tags` and registers
with a settings-search service; `SettingsSliderRow`, `SettingsCard`, `ColorDropdownRow`,
`SettingsButtonGroupRow`). Data binding is explicit: `checked: SettingsData.x` /
`onToggled: v => SettingsData.set("x", v)`.
This will be built in a later session following the same pattern.
