# Claude instructions

Follow the shared repository guidance in [`AGENTS.md`](AGENTS.md) and the
project conventions in [`.github/copilot-instructions.md`](.github/copilot-instructions.md).

For Notes editing, follow the Neovim authority contract in `AGENTS.md`: active
headless Neovim owns buffer and editor state; QML documents are persistence
mirrors, and the editable Qt Quick text editor is only the unavailable-backend
fallback.
