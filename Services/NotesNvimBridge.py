#!/usr/bin/env python3

import json
import os
import queue
import signal
import sys
import tempfile
import threading
import time


def emit(message):
    with output_lock:
        print(json.dumps(message, ensure_ascii=False), flush=True)


output_lock = threading.Lock()
snapshot_tasks = queue.Queue()


document_buffers = {}
buffer_documents = {}
pending_reuse_buffer = None
last_snapshot_buffer = None


def buffer_text(buffer):
    text = "\n".join(buffer[:])
    return text + "\n" if buffer.options["endofline"] else text


def set_buffer_text(buffer, text):
    lines = text.split("\n")
    endofline = text.endswith("\n")
    if endofline:
        lines.pop()
    if not lines:
        lines = [""]
    buffer[:] = lines
    buffer.options["endofline"] = endofline


def snapshot(nvim, request_id, operation):
    global last_snapshot_buffer

    buffer = nvim.current.buffer
    buffer_number = buffer.number
    buffer_changed = (
        last_snapshot_buffer is not None and buffer_number != last_snapshot_buffer
    )
    last_snapshot_buffer = buffer_number
    text = buffer_text(buffer)
    row, column = nvim.current.window.cursor
    current_line = buffer[row - 1]
    if isinstance(current_line, bytes):
        current_line = current_line.decode("utf-8", errors="ignore")
    return {
        "type": "snapshot",
        "id": request_id,
        "operation": operation,
        "buffer_changed": buffer_changed,
        "document_id": buffer_documents.get(buffer.number, -1),
        "text": text,
        "row": row - 1,
        "column": len(current_line.encode("utf-8")[:column].decode("utf-8", errors="ignore")),
        "mode": nvim.eval("mode(1)"),
    }


def select_document(nvim, document_id, text):
    global pending_reuse_buffer

    buffer = document_buffers.get(document_id)
    if buffer is not None and not nvim.api.buf_is_valid(buffer):
        document_buffers.pop(document_id, None)
        buffer_documents.pop(buffer, None)
        buffer = None

    if buffer is None:
        if pending_reuse_buffer is not None and nvim.api.buf_is_valid(pending_reuse_buffer):
            buffer = pending_reuse_buffer
        elif not buffer_documents:
            buffer = nvim.current.buffer.number
        else:
            buffer = nvim.api.create_buf(True, False).number
        target = nvim.buffers[buffer]
        target.options["buftype"] = "nofile"
        target.options["bufhidden"] = "hide"
        target.options["swapfile"] = False
        nvim.api.buf_set_name(buffer, f"MyQuickshell-{document_id}")
        document_buffers[document_id] = buffer
        buffer_documents[buffer] = document_id
        set_buffer_text(target, text)
    elif buffer_text(nvim.buffers[buffer]) != text:
        set_buffer_text(nvim.buffers[buffer], text)

    nvim.api.set_current_buf(buffer)
    if pending_reuse_buffer is not None:
        if pending_reuse_buffer != buffer and nvim.api.buf_is_valid(pending_reuse_buffer):
            nvim.api.buf_delete(pending_reuse_buffer, {"force": True})
        pending_reuse_buffer = None


def close_document(nvim, document_id):
    global pending_reuse_buffer

    buffer = document_buffers.pop(document_id, None)
    if buffer is None or not nvim.api.buf_is_valid(buffer):
        return
    buffer_documents.pop(buffer, None)
    if buffer == nvim.current.buffer.number:
        pending_reuse_buffer = buffer
    else:
        nvim.api.buf_delete(buffer, {"force": True})


def stop_bridge(signum, frame):
    raise SystemExit(0)


def install_term_handler():
    signal.signal(signal.SIGTERM, stop_bridge)


def run_snapshot_worker(nvim):
    while True:
        task = snapshot_tasks.get()
        if task is None:
            return

        operation, request = task
        request_id = request.get("id")
        try:
            if operation == "select_document":
                select_document(nvim, int(request["document_id"]), request.get("text", ""))
            elif operation == "close_document":
                close_document(nvim, int(request["document_id"]))
            elif operation == "command":
                nvim.command(request["command"])
            elif operation == "set_cursor":
                buffer = nvim.current.buffer
                row = max(0, min(int(request["row"]), len(buffer) - 1))
                line = buffer[row]
                if isinstance(line, bytes):
                    line = line.decode("utf-8", errors="ignore")
                column = max(0, min(int(request["column"]), len(line)))
                byte_column = len(line[:column].encode("utf-8"))
                nvim.current.window.cursor = (row + 1, byte_column)
            elif operation not in {"input", "sync"}:
                raise ValueError(f"Unknown operation: {operation}")

            emit(snapshot(nvim, request_id, operation))
        except Exception as error:
            emit({"type": "error", "id": request_id, "message": str(error)})


socket_directory = None
socket_path = None
input_nvim = None
nvim = None


def cleanup():
    for client in (input_nvim, nvim):
        if client is not None:
            try:
                client.close()
            except Exception as error:
                print(f"Neovim RPC connection cleanup failed: {error}", file=sys.stderr)
    if socket_path and os.path.exists(socket_path):
        try:
            os.unlink(socket_path)
        except OSError as error:
            print(f"Neovim socket cleanup failed: {error}", file=sys.stderr)
    if socket_directory:
        try:
            os.rmdir(socket_directory)
        except OSError as error:
            print(f"Neovim temporary directory cleanup failed: {error}", file=sys.stderr)


try:
    import pynvim

    socket_directory = tempfile.mkdtemp(prefix="myqs-nvim-")
    socket_path = os.path.join(socket_directory, "nvim.sock")
    input_nvim = pynvim.attach(
        "child",
        argv=["nvim", "--embed", "--headless", "--listen", socket_path],
    )
    for _ in range(100):
        if os.path.exists(socket_path):
            break
        time.sleep(0.01)
    else:
        raise RuntimeError("Neovim RPC socket did not start.")
    nvim = pynvim.attach("socket", path=socket_path)
    nvim.options["swapfile"] = False
    input_nvim.input("i")
    snapshot_thread = threading.Thread(
        target=run_snapshot_worker, args=(nvim,), daemon=True
    )
    snapshot_thread.start()
    install_term_handler()
    emit({"type": "ready"})
except Exception as error:
    emit({"type": "unavailable", "message": str(error)})
    cleanup()
    sys.exit(0)

try:
    for line in sys.stdin:
        request = {}
        try:
            request = json.loads(line)
            request_id = request.get("id")
            operation = request.get("operation")

            if operation == "input":
                input_nvim.input(request["keys"])
            elif operation not in {"select_document", "close_document", "set_cursor", "sync", "command"}:
                raise ValueError(f"Unknown operation: {operation}")
            snapshot_tasks.put((operation, request))
        except Exception as error:
            emit({"type": "error", "id": request.get("id"), "message": str(error)})
            install_term_handler()
finally:
    snapshot_tasks.put(None)
    cleanup()
