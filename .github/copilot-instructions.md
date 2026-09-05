# Copilot instructions for MyQuickshell

## Build, run, and validation

This project is a Quickshell desktop shell, not a conventional app with a test runner.

- Run the shell in the foreground: `make run`
- Run it detached: `make run-detach`
- Stop the detached instance: `make stop`
- Lint the QML project: `make lint`
- Direct shell start: `quickshell -p .` or `quickshell -p . -d`

`make lint` is the repo's validation command. It runs `qmllint -I . shell.qml $(find . -name '*.qml' -not -path './.git/*')` and is the closest thing to a project-wide check.

There is no automated unit test suite in this repo. For a focused validation of a single file, use the same QML linter approach directly, for example:

```sh
qmllint -I . Modules/Bar/Widgets/BasePill.qml
```

## High-level architecture

- `shell.qml` is the entry point. It creates a `Bar` for each screen via `Quickshell.screens` and mounts the panel as a Wayland layer surface.
- `Common/` holds shared, singleton state. `Theme.qml` is the Material 3 theme layer and `SettingsData.qml` is the persisted settings store.
- `Services/` contains headless singletons that bridge to compositor/system state and external processes: workspace status, system stats, tray, clock, Matugen theme generation, and the DMS backend seam.
- `Modules/Bar/` contains the top bar UI. `Bar.qml` and `BarBody.qml` define the overall shell layout; `Modules/Bar/Widgets/` holds the reusable bar widgets.
- `BasePill.qml` is the UI convention for bar entries: most widgets are pill-shaped, theme-aware, and follow a consistent hover/transparent styling pattern.
- The project uses QML module exports via `qmldir` files. Imports follow `qs.Common`, `qs.Services`, `qs.Modules.Bar`, and `qs.Modules.Bar.Widgets` instead of ad hoc relative imports.

The important architecture constraint is to keep compositor-specific logic and shelling out to `hyprctl`/system commands in `Services/*.qml`, while keeping widgets declarative and data-driven.

## Key conventions

- Prefer `pragma Singleton` for shared state. Global state is intentionally centralized in the `Common` and `Services` singletons instead of scattered across widgets.
- Use `Theme.*` tokens instead of hardcoded colors or spacing values. The design relies on Material 3 token names such as `surfaceContainer`, `primary`, `onSurface`, and the color helpers in `Theme.qml`.
- Persist settings through `SettingsData.qml`, not by creating ad hoc config properties in UI files. New configuration keys belong in the declarative spec in `Common/Settings/SettingsSpec.js` and are surfaced via `SettingsData.qml`.
- Treat system integration as a backend seam: `Services/DMSService.qml` is intentionally a no-op interface for future IPC/backend work, and `WorkspacesService.qml` abstracts compositor-specific workspace state behind a stable API.
- Keep UI widgets focused on rendering and binding to `Theme`/service data. Avoid calling external commands or reading compositor details directly inside `Modules/Bar/Widgets/*`.
- The bar is per-screen and layer-shell based. New UI contributions should follow the existing `PanelWindow` + `BarBody` pattern rather than creating independent floating windows unless the feature truly requires it.

## Relevant repo notes

- README.md is the best source for the project shape and runtime requirements. It describes MyQuickshell as a self-contained Quickshell shell for Wayland compositors and notes the `hyprctl`/layer-shell dependency.
- The project is built around a DMS/omarchy-inspired architecture but is intentionally self-contained. The implementation details doc explains the intended design and is useful when adding new modules or matching existing conventions.
- There is no `.github/copilot-instructions.md` yet; this file should be the canonical place for repo-specific agent guidance.
