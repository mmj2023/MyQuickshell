#!/usr/bin/env python3

import json
import signal
import sys


def emit(message):
    print(json.dumps(message, ensure_ascii=False), flush=True)


def snapshot(nvim, request_id):
    buffer = nvim.current.buffer
    text = "\n".join(buffer[:])
    if buffer.options["endofline"]:
        text += "\n"
    row, column = nvim.current.window.cursor
    current_line = buffer[row - 1]
    if isinstance(current_line, bytes):
        current_line = current_line.decode("utf-8", errors="ignore")
    return {
        "type": "snapshot",
        "id": request_id,
        "text": text,
        "row": row - 1,
        "column": len(current_line.encode("utf-8")[:column].decode("utf-8", errors="ignore")),
        "mode": nvim.eval("mode(1)"),
    }


def stop_bridge(signum, frame):
    raise SystemExit(0)


def install_term_handler():
    signal.signal(signal.SIGTERM, stop_bridge)


try:
    import pynvim

    nvim = pynvim.attach("child", argv=["nvim", "--embed", "--headless"])
    nvim.options["swapfile"] = False
    nvim.input("i")
    nvim.eval("1")
    install_term_handler()
    emit({"type": "ready"})
except Exception as error:
    emit({"type": "unavailable", "message": str(error)})
    sys.exit(0)

try:
    for line in sys.stdin:
        request = {}
        try:
            request = json.loads(line)
            request_id = request.get("id")
            operation = request.get("operation")

            if operation == "set_buffer":
                text = request.get("text", "")
                lines = text.split("\n")
                endofline = text.endswith("\n")
                if endofline:
                    lines.pop()
                if not lines:
                    lines = [""]
                nvim.current.buffer[:] = lines
                nvim.current.buffer.options["endofline"] = endofline
                nvim.current.window.cursor = (1, 0)
            elif operation == "input":
                nvim.input(request["keys"])
                nvim.eval("1")
            elif operation == "command":
                nvim.command(request["command"])
                nvim.eval("1")
            elif operation == "set_cursor":
                buffer = nvim.current.buffer
                row = max(0, min(int(request["row"]), len(buffer) - 1))
                line = buffer[row]
                if isinstance(line, bytes):
                    line = line.decode("utf-8", errors="ignore")
                column = max(0, min(int(request["column"]), len(line)))
                byte_column = len(line[:column].encode("utf-8"))
                nvim.current.window.cursor = (row + 1, byte_column)
            elif operation == "sync":
                pass
            else:
                raise ValueError(f"Unknown operation: {operation}")

            emit(snapshot(nvim, request_id))
            install_term_handler()
        except Exception as error:
            emit({"type": "error", "id": request.get("id"), "message": str(error)})
            install_term_handler()
finally:
    nvim.close()
