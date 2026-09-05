QS ?= quickshell

.PHONY: run run-detach stop lint

run:
	$(QS) -p .

run-detach:
	$(QS) -p . -d

stop:
	pkill -f 'quickshell -p \. -d' || true

FILES := $(shell find . -name '*.qml' -not -path './.git/*')

lint:
	qmllint -I . shell.qml $(FILES)
