# Shared agent instructions for MyQuickshell

All AI coding agents working in this repository must follow these shared UI
theming and spacing rules, in addition to any tool-specific instructions.

## Theming and spacing

- Use `Common/Theme.qml` tokens for colors, typography, and design spacing.
  Do not introduce hard-coded colors or pixel gaps where a theme token applies.
- Use `Theme.cornerRadius` for rounded-rectangle surfaces, `Theme.hoverRadius`
  for compact hover highlights, and `Theme.pillRadius` for pill/circular icon
  targets. Avoid one-off numeric corner radii on interactive highlights so
  their shape stays consistent.
- Use the same theme token for the same visual relationship throughout the
  shell. In particular, the standard gap between a bar and a popup, and between
  a popup and its directly nested popup, is `Theme.spaceXS` (4 px). Do not mix
  raw offsets such as `4` or `8` with theme spacing for these relationships.
- Keep hover highlights and their hit areas inside the visible bounds of their
  owning pill or button. Do not use negative anchor margins to enlarge them
  beyond the pill; add internal padding within the control instead. Match
  sibling controls' highlight color, opacity, corner treatment, and the
  weather button's content-based vertical inset (`Theme.hoverVerticalInset`).
  Segmented bar-pill highlights should use this same vertical inset.
- Respect popup anchor coordinates: `anchor.rect` is relative to
  `anchor.window`. When a popup is anchored to another popup, calculate its
  position in that popup's local coordinates and include its height when
  placing it below. Do not reuse bar-relative coordinates as popup-relative
  coordinates.
- When matching gaps, compare the visible edge-to-edge distance, not just the
  anchor origin. Include popup borders, margins, and implicit dimensions in the
  calculation.
- Before changing spacing, inspect nearby widgets for the established token
  and anchoring pattern. Afterward, lint the changed QML and review every
  affected popup placement so equivalent gaps remain equivalent.

## Qt Quick Controls styling

Never ship an unstyled `ComboBox`, `Popup`, or other Qt Quick Control: Qt's
default control style does not match the shell theme. For every such control:

- Always define `contentItem`, `indicator`, `background`, `popup`, and
  `delegate` explicitly, using `Common/Theme.qml` tokens only (no default
  style colors or hard-coded hex).
- In popup item delegates, keep the label's text color constant
  (`Theme.surfaceText`); highlight state is conveyed by the background pill
  (`Theme.withAlpha(Theme.primary, 0.2)` + `Theme.hoverRadius`) alone. Do not
  switch the label to `Theme.primaryText`/`Theme.primary` on hover — this
  creates low-contrast, washed-out text.
- Popup `ListView`s must set `highlightFollowsCurrentItem: false` when
  `currentIndex` is bound to the delegate highlight; otherwise hover can
  trigger unintended auto-scrolling.

## Project conventions

- Follow `.github/copilot-instructions.md` for the project architecture,
  build, validation, and QML conventions. This file is the shared source for
  cross-agent UI theming and popup-spacing behavior.
- Whenever you add or change a runtime/build dependency, document whether it is
  required or optional, what feature uses it, and its fallback behavior in
  `README.md`. Keep this rule for all AI agents and contributors.
- Keep UI widgets declarative and put compositor/system integration in
  `Services/`.
- Use `qmllint -I . <changed-files>` for focused QML validation and
  `git diff --check` for whitespace validation.
