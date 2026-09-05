# MyQuickshell — Tasks

## Goal

Make MyQuickshell a real shell, not a toy bar. Deliver this session:

1. **Bar** that matches the user's **actual current DMS look** (dynamic matugen,
   teal palette derived from `high_res_blue_green_space.jpg`, scheme-content).
2. **Fix system tray clickability** (currently broken).
3. **Omarchy-style universal launcher** (data-driven, with inline settings and
   toggles), rendered in a DMS-spotlight-style modal, and styled like DMS.

The full DMS-style **settings app** is a documented **later phase** (out of
session scope, per user decision). The launcher gets a settings button that will
summon that future settings app.

Architecture follows a **hybrid** model:
- **Launcher**: omarchy's data-driven menu engine (JSONC entries, `action` /
  `checked` / `when` semantics, submenu drilldown, batched guard eval) blended
  with DMS's window/frame style and DMS trigger prefixes.
- **Config**: DMS's SPEC-driven JSON store (`settings.json`, defaults /
  coerce / onChange hooks, version + migration).
- **Theming**: full local matugen pipeline — run the `matugen` CLI directly
  (self-contained, no dependency on DMS's `dms matugen` Go binary), write a
  colors JSON, watch it, map to tokens exactly like DMS `Theme.qml`.

## Reference facts (verified this session)

- DMS is currently **running** on Hyprland (`dms run` + `qs`), eDP-1
  1920x1080 @ scale 1.25, bottom bar reserved 34px.
- Current live palette (`~/.cache/quickshell/DankMaterialShell/dms-colors.json`):
  primary `#85d4cf`, surface `#101414`, surfaceContainer `#1c2020`,
  surfaceContainerHigh `#272b2a`, Highest `#313635`, onSurface `#e0e3e2`,
  surfaceVariant `#3e4948`, onSurfaceVariant `#bec9c7`, outline `#889391`,
  tertiary `#d8bbf8`.
- Matugen source: `~/Pictures/Wallpapers/high_res_blue_green_space.jpg`,
  `matugenType: "scheme-content"`, mode dark. `matugen` 4.2.0 is installed.
- DMS `settings.json` (user's real config) shows: cornerRadius 11, fontScale
  0.94, monoFontFamily JetBrainsMono NF, 24h clock, `yyyy-MM-dd`, widgetBg "sc",
  widgetTransparency 0.65, dock enabled (auto-hide, group-by-app), launcher logo
  OS-mode/primary color.

---

## Phase 0 — Foundation: DMS-style SPEC/JSON config store

- [ ] Add `Common/Settings/SettingsSpec.js`, `SettingsStore.js`, `SpecUtil.js`
      reproducing DMS's declarative-spec config pattern (self-contained, no
      DMS dependency).
- [ ] Add `Common/SettingsData.qml` (`pragma Singleton`) exposing module-level
      properties + `set(key, value)`, backed by
      `~/.config/myquickshell/settings.json` with `configVersion` + migration.
- [ ] Keys needed now: `cornerRadius`, `fontScale`, `monoFontFamily`,
      `clockFormat`, `clockDateFormat`, `popupTransparency`,
      `widgetTransparency`, `widgetBackgroundColor`, `matugenScheme`,
      `matugenSourceImage`, `matugenMode`, `showDock`, `currentThemeName`,
      bar layout (left/center/right widget lists), launcher settings.

## Phase 1 — Dynamic matugen theming (full local pipeline)

- [ ] Add a matugen template (JSON) mirroring DMS `dank.json` shape: `dank16` +
      full `colors.dark/light` Material-M3 keys (so mapping matches DMS).
- [ ] `Services/MatugenService.qml`: run `matugen image <img> --type <scheme>
      --mode <mode> --template <tpl>` as a subprocess writing
      `~/.cache/myquickshell/dms-colors.json`; debounced re-run on wallpaper /
      scheme / mode change; `matugenAvailable` from `command -v matugen`.
- [ ] `Common/Theme.qml`: replace static palette with a `FileView`-watched color
      source; `getMatugenColor(path, fallback)` maps `colors[mode]` material
      keys -> Dank tokens exactly like DMS (primary, surface, surfaceContainer*,
      onSurface, surfaceVariant, onSurfaceVariant, outline, tertiary, tint).
- [ ] Keep a built-in fallback palette so the shell still loads without matugen.

## Phase 2 — DMS-style Bar

- [ ] Build a `BasePill`-style bar widget base: rounded pill, hover color =
      blend(base, primary, ~0.1), ripple, transparency blend from
      `widgetTransparency`, optional outline, `barIconSize/barTextSize` scaling
      off `barThickness`.
- [ ] Bar content mirrors the user's DMS `barConfigs` layout:
      - left: launcher button, workspace switcher, running apps, focused window
      - center: clock, weather placeholder, system tray
      - right: clipboard, notifications, cpu/mem/disk, battery, control-center
        button (a `settings` entry point)
- [ ] Widget order/model driven by SettingsData left/center/right lists.
- [ ] Theme token scaling (`fontScale`, barHeight 34-ish vs DMS 48 — match the
      user's look via `widgetThickness`/`barThickness` ratio).

## Phase 3 — Fix tray clickability

- [ ] Debug current Repeater over `SystemTray.items`; switch to iterating
      `SystemTray.items.values` (DMS pattern) so each delegate gets the real SNI
      item object with its methods.
- [ ] Wire left-click `activate()`, right-click menu via `display()`/fallback,
      `onlyMenu` handling; hover/pressed states.
- [ ] (Stretch) overflow popup when too many items — keep simple first.

## Phase 4 — Omarchy-style data-driven launcher

- [ ] `Modals/Launcher/` — one modal surface: `PanelWindow` overlay (like
      omarchy `Menu.qml`) inside a DMS-spotlight-style centered card.
- [ ] Data-driven menu: JSONC `menu.jsonc` (dotted IDs, `action`/`checked`/
      `when`/`disabled`, `aliases`, `icon`), parse it with
      `watchChanges: true`.
- [ ] `MenuModel.js` (pure JS, `.pragma library`) replicating omarchy scoring:
      substring filter (every whitespace term must match name/alias/desc),
      tiered `searchScore`, depth/order tiebreaks.
- [ ] Search merges menu items + DesktopEntries apps (via
      `Quickshell.Services.DesktopEntries`) (+ providers later).
- [ ] Providers: batched bash guard evaluation like omarchy `guardScript()`;
      `apps` provider natively.
- [ ] Keyboard: keyCatcher with Up/Down/PgUp/PgDn/Enter/Esc/Delete, drilldown
      navStack, `revealCursor`.
- [ ] Inline settings sections: Style > Theme / Background / Bar position &
      transparency; Toggle > nightlight / top bar / window gaps / touchpad;
      Setup > default browser / terminal.
- [ ] Launcher opens via keybind + a launcher button on the bar; has a
      `settings` button summoning the future full settings app.
- [ ] (Stretch) DMS trigger prefixes (`@` web, `=` calc, `.` emoji, `>` shell).

## Phase 5 — DEFERRED to a future session (documented here for reference)

- [ ] Full DMS-style settings app: sidebar Modal + per-tab Settings pages,
      `SettingsToggleRow` pattern, settings search.
- [ ] Dock, control center, notifications, OSD, lock modules.
- [ ] Plugins system (DMS `PLUGINS/`).
