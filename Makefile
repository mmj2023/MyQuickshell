QS ?= quickshell

.PHONY: install-desktop run run-detach stop lint

DATA_HOME := $(if $(strip $(XDG_DATA_HOME)),$(XDG_DATA_HOME),$(HOME)/.local/share)
APP_ID := com.myquickshell.shell
DESKTOP_FILE := $(DATA_HOME)/applications/$(APP_ID).desktop

install-desktop:
	@mkdir -p "$(dir $(DESKTOP_FILE))"
	@printf '%s\n' \
		'[Desktop Entry]' \
		'Version=1.0' \
		'Type=Application' \
		'Name=MyQuickshell' \
		'Comment=Wayland desktop shell' \
		'Exec=$(QS) -p "$(CURDIR)"' \
		'Path=$(CURDIR)' \
		'Terminal=false' \
		'NoDisplay=true' \
		'DBusActivatable=false' \
		> "$(DESKTOP_FILE)"

run: install-desktop
	$(QS) -p .

run-detach: install-desktop
	$(QS) -p . -d

stop:
	pkill -f 'quickshell -p \. -d' || true

FILES := $(shell find . -name '*.qml' -not -path './.git/*')

lint:
	qmllint -I . shell.qml $(FILES)
