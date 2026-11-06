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
highlight_cache = {}
search_highlight_cache = {}
visible_highlight_ranges = {}
command_completion_query = ""
command_completion_visible = False

FULL_HIGHLIGHT_LINE_LIMIT = 2000
HIGHLIGHT_CHUNK_LINES = 200
MAX_CACHED_HIGHLIGHT_CHUNKS = 8


def buffer_text(buffer):
    text = "\n".join(buffer[:])
    return text + "\n" if buffer.options["endofline"] else text


def buffer_line(buffer, row):
    line = buffer[row]
    return line.decode("utf-8", errors="ignore") if isinstance(line, bytes) else line


def byte_column_to_character(line, byte_column):
    encoded = line.encode("utf-8")
    return len(encoded[:max(0, byte_column)].decode("utf-8", errors="ignore"))


def set_buffer_text(buffer, text):
    lines = text.split("\n")
    endofline = text.endswith("\n")
    if endofline:
        lines.pop()
    if not lines:
        lines = [""]
    buffer[:] = lines
    buffer.options["endofline"] = endofline


def set_buffer_filetype(nvim, buffer, filename, text):
    filetype = nvim.exec_lua("""
        local buffer, filename, text = ...
        local filetype = vim.filetype.match({
            filename = filename,
            contents = text,
        })
        if not filetype then
            filetype = filename:match("%.[^./]+$") and "text" or "markdown"
        end

        vim.cmd("syntax enable")
        vim.api.nvim_set_option_value("filetype", filetype, { buf = buffer })
        vim.api.nvim_buf_call(buffer, function()
            if vim.b.current_syntax ~= filetype then
                vim.cmd("syntax clear")
                vim.b.current_syntax = nil
                vim.api.nvim_cmd({
                    cmd = "runtime",
                    bang = true,
                    args = { "syntax/" .. filetype .. ".vim" },
                }, {})
            end
        end)
        return filetype
    """, buffer, filename, text)
    highlight_cache.pop(buffer, None)
    return filetype


def syntax_highlights(nvim, buffer, start_row, end_row):
    changedtick = nvim.api.buf_get_changedtick(buffer)
    line_count = nvim.api.buf_line_count(buffer)
    cached = highlight_cache.get(buffer)
    if cached is None or cached["changedtick"] != changedtick:
        cached = {"changedtick": changedtick, "chunks": {}}
        highlight_cache[buffer] = cached

    if line_count <= FULL_HIGHLIGHT_LINE_LIMIT:
        chunk_starts = [0]
        chunk_ends = {0: line_count}
    else:
        start_row = max(0, min(int(start_row), line_count - 1))
        end_row = max(start_row + 1, min(int(end_row), line_count))
        first_chunk = start_row // HIGHLIGHT_CHUNK_LINES * HIGHLIGHT_CHUNK_LINES
        last_chunk = (end_row - 1) // HIGHLIGHT_CHUNK_LINES * HIGHLIGHT_CHUNK_LINES
        chunk_starts = list(range(first_chunk, last_chunk + 1, HIGHLIGHT_CHUNK_LINES))
        chunk_ends = {
            chunk_start: min(chunk_start + HIGHLIGHT_CHUNK_LINES, line_count)
            for chunk_start in chunk_starts
        }

    for chunk_start in chunk_starts:
        cached_chunk = cached["chunks"].pop(chunk_start, None)
        if cached_chunk is not None:
            cached["chunks"][chunk_start] = cached_chunk
            continue
        chunk_end = chunk_ends[chunk_start]
        cached["chunks"][chunk_start] = nvim.exec_lua("""
            local buffer, first_row, last_row = ...
            local highlights = {}

            local function group_at(row, byte_column)
                if vim.inspect_pos then
                    local info = vim.inspect_pos(buffer, row, byte_column)
                    local groups = {}
                    for _, source in ipairs({
                        info.semantic_tokens or {},
                        info.treesitter or {},
                        info.syntax or {},
                    }) do
                        for index = 1, #source do
                            local item = source[index]
                            if item.hl_group and item.hl_group ~= "" then
                                table.insert(groups, item.hl_group)
                            end
                            if item.hl_group_link and item.hl_group_link ~= "" then
                                table.insert(groups, item.hl_group_link)
                            end
                        end
                    end
                    if #groups > 0 then
                        return table.concat(groups, " ")
                    end
                end
                local id = vim.fn.synID(row + 1, byte_column + 1, 1)
                if id == 0 then
                    return ""
                end
                local group = vim.fn.synIDattr(id, "name")
                local linked = vim.fn.synIDattr(vim.fn.synIDtrans(id), "name")
                return group .. " " .. linked
            end

            local lines = vim.api.nvim_buf_get_lines(buffer, first_row, last_row, false)
            for line_index, line in ipairs(lines) do
                local row = first_row + line_index - 1
                local run_group = nil
                local run_start = 0
                local column = 0
                for byte_column = 1, #line do
                    local byte = line:byte(byte_column)
                    if byte < 128 or byte >= 192 then
                        local group = group_at(row, byte_column - 1)
                        if group ~= run_group then
                            if run_group and run_group ~= "" then
                                table.insert(highlights, {
                                    row = row,
                                    start_column = run_start,
                                    end_column = column,
                                    group = run_group,
                                })
                            end
                            run_group = group
                            run_start = column
                        end
                        column = column + 1
                    end
                end
                if run_group and run_group ~= "" then
                    table.insert(highlights, {
                        row = row,
                        start_column = run_start,
                        end_column = column,
                        group = run_group,
                    })
                end
            end
            return highlights
        """, buffer, chunk_start, chunk_end)

    while len(cached["chunks"]) > max(MAX_CACHED_HIGHLIGHT_CHUNKS, len(chunk_starts)):
        oldest_chunk = next(iter(cached["chunks"]))
        if oldest_chunk in chunk_starts:
            cached["chunks"][oldest_chunk] = cached["chunks"].pop(oldest_chunk)
        else:
            cached["chunks"].pop(oldest_chunk)

    return [
        highlight
        for chunk_start in chunk_starts
        for highlight in cached["chunks"][chunk_start]
    ]


def search_highlights(nvim, buffer, command_type, command_line):
    changedtick = nvim.api.buf_get_changedtick(buffer)
    cached = search_highlight_cache.get(buffer)
    window = nvim.current.window
    if cached is not None and cached["changedtick"] == changedtick:
        cache_key = (
            command_type,
            command_line,
            bool(nvim.options["hlsearch"]),
            bool(nvim.options["incsearch"]),
            str(nvim.options["inccommand"]),
            int(nvim.eval("v:hlsearch")),
            str(nvim.call("getreg", "/")),
            bool(nvim.options["ignorecase"]),
            bool(nvim.options["smartcase"]),
            bool(nvim.options["magic"]),
            bool(window.options["number"]),
            bool(window.options["relativenumber"]),
            bool(window.options["wrap"]),
            bool(window.options["cursorline"]),
            bool(window.options["list"]),
            bool(window.options["spell"]),
            int(nvim.current.buffer.options["tabstop"]),
            int(nvim.current.buffer.options["shiftwidth"]),
            bool(nvim.current.buffer.options["expandtab"]),
        )
        if cached["key"] == cache_key:
            return cached["spans"], cached["options"]

    result = nvim.exec_lua("""
        local buffer, command_type, command_line = ...
        local window = vim.api.nvim_get_current_win()
        local options = {
            number = vim.wo[window].number,
            relativenumber = vim.wo[window].relativenumber,
            wrap = vim.wo[window].wrap,
            cursorline = vim.wo[window].cursorline,
            list = vim.wo[window].list,
            spell = vim.wo[window].spell,
            hlsearch = vim.o.hlsearch,
            incsearch = vim.o.incsearch,
            inccommand = vim.o.inccommand,
            ignorecase = vim.o.ignorecase,
            smartcase = vim.o.smartcase,
            tabstop = vim.bo[buffer].tabstop,
            shiftwidth = vim.bo[buffer].shiftwidth,
            expandtab = vim.bo[buffer].expandtab,
        }

        local pattern = nil
        local group = nil
        if (command_type == "/" or command_type == "?")
            and command_line ~= "" and options.incsearch then
            pattern = command_line
            group = "IncSearch"
        elseif command_type == ":" and options.inccommand ~= "" then
            local ok, parsed = pcall(vim.api.nvim_parse_cmd, command_line, {})
            if ok and (parsed.cmd == "substitute"
                or parsed.cmd == "smagic" or parsed.cmd == "snomagic") then
                local raw = parsed.args[1] or ""
                if raw ~= "" then
                    local delimiter = raw:sub(1, 1)
                    local escaped = false
                    local parts = {}
                    local part = {}
                    for index = 2, #raw do
                        local character = raw:sub(index, index)
                        if escaped then
                            if character ~= delimiter then
                                table.insert(part, "\\\\")
                            end
                            table.insert(part, character)
                            escaped = false
                        elseif character == "\\\\" then
                            escaped = true
                        elseif character == delimiter then
                            table.insert(parts, table.concat(part))
                            part = {}
                            if #parts == 2 then
                                break
                            end
                        else
                            table.insert(part, character)
                        end
                    end
                    if escaped then
                        table.insert(part, "\\\\")
                    end
                    if #parts > 0 then
                        pattern = parts[1] ~= "" and parts[1] or vim.fn.getreg("/")
                        group = "IncSearch"
                    else
                        pattern = table.concat(part)
                        if pattern == "" then
                            pattern = vim.fn.getreg("/")
                        end
                        group = "IncSearch"
                    end
                else
                    pattern = vim.fn.getreg("/")
                    group = "IncSearch"
                end
            end
        end

        if not pattern and options.hlsearch and vim.v.hlsearch ~= 0 then
            pattern = vim.fn.getreg("/")
            group = "Search"
        end

        local spans = {}
        if pattern and pattern ~= "" then
            local lines = vim.api.nvim_buf_get_lines(buffer, 0, -1, false)
            local text = table.concat(lines, "\\n")
            local line_starts = { 0 }
            for index = 1, #text do
                if text:byte(index) == 10 then
                    table.insert(line_starts, index)
                end
            end

            local function position_at(byte_offset)
                local low = 1
                local high = #line_starts
                while low < high do
                    local middle = math.floor((low + high + 1) / 2)
                    if line_starts[middle] <= byte_offset then
                        low = middle
                    else
                        high = middle - 1
                    end
                end
                local row = low - 1
                local byte_column = byte_offset - line_starts[low]
                local column = vim.str_utfindex(lines[low] or "", "utf-32", byte_column)
                return row, column
            end

            local offset = 0
            while offset <= #text do
                local ok, found = pcall(vim.fn.matchstrpos, text, pattern, offset)
                if not ok or not found or found[2] < 0 then
                    break
                end
                local start_byte = found[2]
                local end_byte = found[3]
                if end_byte > start_byte then
                    local start_row, start_column = position_at(start_byte)
                    local end_row, end_column = position_at(end_byte)
                    for row = start_row, end_row do
                        local first_column = row == start_row and start_column or 0
                        local last_column = row == end_row
                            and end_column
                            or vim.str_utfindex(lines[row + 1] or "", "utf-32")
                        if last_column > first_column then
                            table.insert(spans, {
                                row = row,
                                start_column = first_column,
                                end_column = last_column,
                                group = group,
                            })
                        end
                    end
                end
                offset = math.max(end_byte, start_byte + 1)
            end
        end
        return { spans = spans, options = options }
    """, buffer, command_type, command_line)
    spans = result["spans"]
    options = result["options"]

    cache_key = (
        command_type,
        command_line,
        bool(nvim.options["hlsearch"]),
        bool(nvim.options["incsearch"]),
        str(nvim.options["inccommand"]),
        int(nvim.eval("v:hlsearch")),
        str(nvim.call("getreg", "/")),
        bool(nvim.options["ignorecase"]),
        bool(nvim.options["smartcase"]),
        bool(nvim.options["magic"]),
        bool(window.options["number"]),
        bool(window.options["relativenumber"]),
        bool(window.options["wrap"]),
        bool(window.options["cursorline"]),
        bool(window.options["list"]),
        bool(window.options["spell"]),
        int(nvim.current.buffer.options["tabstop"]),
        int(nvim.current.buffer.options["shiftwidth"]),
        bool(nvim.current.buffer.options["expandtab"]),
    )
    search_highlight_cache[buffer] = {
        "changedtick": changedtick,
        "key": cache_key,
        "spans": spans,
        "options": options,
    }
    return spans, options


def namespace_extmarks(nvim, buffer, namespace_name, namespaces):
    namespace = namespaces.get(namespace_name)
    if namespace is None:
        return []
    return nvim.api.buf_get_extmarks(
        buffer, namespace, 0, -1, {"details": True}
    )


def split_selection_by_line(buffer, start_row, start_column, end_row, end_column, kind):
    last_row = len(buffer) - 1
    start_row = max(0, min(start_row, last_row))
    end_row = max(start_row, min(end_row, last_row))
    selections = []
    for row in range(start_row, end_row + 1):
        line = buffer_line(buffer, row)
        line_length = len(line)
        if kind == "block":
            start = start_column
            end = end_column
        else:
            start = start_column if row == start_row else 0
            end = end_column if row == end_row else line_length
        start = max(0, start)
        end = max(start, end)
        if kind != "block":
            start = min(start, line_length)
            end = min(max(start, end), line_length)
        selections.append({
            "row": row,
            "start_column": start,
            "end_column": end,
            "kind": kind,
            "fill_to_end": kind == "line" or (kind == "char" and row < end_row),
        })
    return selections


def visual_selection(nvim, buffer, mode, row, byte_column):
    anchor = nvim.eval('getpos("v")')
    anchor_row = max(0, int(anchor[1]) - 1)
    anchor_byte_column = max(0, int(anchor[2]) - 1)
    current_row = max(0, row - 1)
    kind = "line" if mode.startswith("V") else "block" if mode == "\x16" else "char"
    anchor_line = buffer_line(buffer, anchor_row)
    current_line = buffer_line(buffer, current_row)
    anchor_column = byte_column_to_character(anchor_line, anchor_byte_column)
    current_column = byte_column_to_character(current_line, byte_column)

    if kind == "line":
        return split_selection_by_line(
            buffer, min(anchor_row, current_row), 0,
            max(anchor_row, current_row), len(buffer_line(buffer, max(anchor_row, current_row))),
            kind,
        )
    if kind == "block":
        return split_selection_by_line(
            buffer, min(anchor_row, current_row), min(anchor_column, current_column),
            max(anchor_row, current_row), max(anchor_column, current_column) + 1,
            kind,
        )

    start = (anchor_row, anchor_column)
    end = (current_row, current_column)
    if end < start:
        start, end = end, start
    return split_selection_by_line(
        buffer, start[0], start[1], end[0], end[1] + 1, kind
    )


def multicursor_selections(nvim, buffer, kind, namespaces):
    if kind is None:
        return []
    selections = []
    for mark in namespace_extmarks(
        nvim, buffer, "nvim.multicursor.visual", namespaces
    ):
        details = mark[3]
        start_row, start_column = mark[1], mark[2]
        end_row = details.get("end_row", start_row)
        end_column = details.get("end_col", start_column)
        if start_row >= len(buffer) or end_row >= len(buffer):
            continue
        selections.extend(split_selection_by_line(
            buffer,
            start_row,
            byte_column_to_character(buffer_line(buffer, start_row), start_column),
            end_row,
            byte_column_to_character(buffer_line(buffer, end_row), end_column),
            kind,
        ))
    return selections


def visual_kind(mode):
    if mode.startswith("V"):
        return "line"
    if mode == "\x16":
        return "block"
    return "char"


def multicursor_positions(nvim, buffer, mode, row, byte_column, namespaces):
    visual = mode.startswith(("v", "V")) or mode == "\x16"
    marks = namespace_extmarks(
        nvim, buffer, "nvim.multicursor.cursor" if visual else "nvim.multicursor",
        namespaces,
    )
    if visual and not marks:
        marks = namespace_extmarks(nvim, buffer, "nvim.multicursor", namespaces)
    current_position = (
        row - 1,
        byte_column_to_character(buffer_line(buffer, row - 1), byte_column),
    )
    positions = []
    for mark in marks:
        mark_row, mark_byte_column = mark[1], mark[2]
        if mark_row >= len(buffer):
            continue
        column = byte_column_to_character(
            buffer_line(buffer, mark_row), mark_byte_column
        )
        if (mark_row, column) == current_position:
            continue
        positions.append({"row": mark_row, "column": column})
    return positions


def snapshot(nvim, request_id, operation):
    global command_completion_query, command_completion_visible, last_snapshot_buffer

    buffer = nvim.current.buffer
    buffer_number = buffer.number
    buffer_changed = (
        last_snapshot_buffer is not None and buffer_number != last_snapshot_buffer
    )
    last_snapshot_buffer = buffer_number
    text = buffer_text(buffer)
    row, column = nvim.current.window.cursor
    current_line = buffer_line(buffer, row - 1)
    mode = nvim.eval("mode(1)")
    recording_register = nvim.call("reg_recording")
    command_type = nvim.eval("getcmdtype()") if mode.startswith("c") else ""
    command_line = nvim.eval("getcmdline()") if mode.startswith("c") else ""
    command_position = max(0, int(nvim.eval("getcmdpos()")) - 1) if mode.startswith("c") else 0
    completion_candidates = []
    completion_index = -1
    if mode.startswith("c") and command_completion_visible:
        completion_candidates = nvim.call(
            "getcompletion", command_completion_query, "cmdline"
        )
        try:
            completion_index = completion_candidates.index(command_line)
        except ValueError:
            pass
    elif not mode.startswith("c"):
        command_completion_query = ""
        command_completion_visible = False
    visual = mode.startswith(("v", "V")) or mode == "\x16"
    namespaces = nvim.api.get_namespaces()
    selections = multicursor_selections(
        nvim, buffer, visual_kind(mode) if visual else None, namespaces
    )
    if not selections and visual:
        selections = visual_selection(nvim, buffer, mode, row, column)
    search_spans, editor_options = search_highlights(
        nvim, buffer.number, command_type, command_line
    )
    return {
        "type": "snapshot",
        "id": request_id,
        "operation": operation,
        "buffer_changed": buffer_changed,
        "document_id": buffer_documents.get(buffer.number, -1),
        "text": text,
        "row": row - 1,
        "column": byte_column_to_character(current_line, column),
        "mode": mode,
        "recording_register": recording_register,
        "editor_options": editor_options,
        "search_highlights": search_spans,
        "command_type": command_type,
        "command_line": command_line,
        "command_position": command_position,
        "completion_query": command_completion_query if command_completion_visible else "",
        "completion_visible": bool(completion_candidates),
        "completion_candidates": completion_candidates,
        "completion_index": completion_index,
        "selections": selections,
        "highlights": syntax_highlights(
            nvim, buffer.number,
            *visible_highlight_ranges.get(buffer.number, (0, HIGHLIGHT_CHUNK_LINES)),
        ),
        "cursors": multicursor_positions(
            nvim, buffer, mode, row, column, namespaces
        ),
    }


def ensure_document_buffer(nvim, document_id, text, filename):
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
        visible_highlight_ranges[buffer] = (0, HIGHLIGHT_CHUNK_LINES)
        set_buffer_text(target, text)
    set_buffer_filetype(nvim, buffer, filename, buffer_text(nvim.buffers[buffer]))
    if pending_reuse_buffer is not None:
        if pending_reuse_buffer != buffer and nvim.api.buf_is_valid(pending_reuse_buffer):
            nvim.api.buf_delete(pending_reuse_buffer, {"force": True})
        pending_reuse_buffer = None
    return buffer


def select_document(nvim, document_id, text, filename):
    buffer = ensure_document_buffer(nvim, document_id, text, filename)
    nvim.api.set_current_buf(buffer)


def register_documents(nvim, documents, active_document_id):
    global pending_reuse_buffer

    active_document_id = int(active_document_id)
    for document in documents:
        ensure_document_buffer(
            nvim,
            int(document["document_id"]),
            document.get("text", ""),
            document.get("filename", ""),
        )

    active_buffer = document_buffers.get(active_document_id)
    if active_buffer is None:
        raise ValueError(f"Unknown active Notes document: {active_document_id}")
    nvim.api.set_current_buf(active_buffer)


def close_document(nvim, document_id):
    global pending_reuse_buffer

    buffer = document_buffers.pop(document_id, None)
    if buffer is None or not nvim.api.buf_is_valid(buffer):
        return
    buffer_documents.pop(buffer, None)
    highlight_cache.pop(buffer, None)
    search_highlight_cache.pop(buffer, None)
    visible_highlight_ranges.pop(buffer, None)
    if buffer == nvim.current.buffer.number:
        pending_reuse_buffer = buffer
    else:
        nvim.api.buf_delete(buffer, {"force": True})


def stop_bridge(signum, frame):
    raise SystemExit(0)


def install_term_handler():
    signal.signal(signal.SIGTERM, stop_bridge)


def run_snapshot_worker(nvim):
    global command_completion_query, command_completion_visible
    while True:
        task = snapshot_tasks.get()
        if task is None:
            return

        operation, request = task
        request_id = request.get("id")
        try:
            if operation == "input":
                keys = request.get("keys", "")
                if keys in {"<Tab>", "<S-Tab>"} and request.get("completion_query") is not None:
                    if not command_completion_visible:
                        command_completion_query = str(request["completion_query"])
                    command_completion_visible = True
                elif not keys.startswith(("<Up>", "<Down>")):
                    command_completion_query = ""
                    command_completion_visible = False

            if operation == "select_document":
                select_document(
                    nvim,
                    int(request["document_id"]),
                    request.get("text", ""),
                    request.get("filename", ""),
                )
            elif operation == "register_documents":
                register_documents(
                    nvim,
                    request.get("documents", []),
                    request["active_document_id"],
                )
            elif operation == "set_filetype":
                document_id = int(request["document_id"])
                buffer = document_buffers.get(document_id)
                if buffer is None or not nvim.api.buf_is_valid(buffer):
                    raise ValueError(f"Unknown Notes document: {document_id}")
                set_buffer_filetype(
                    nvim,
                    buffer,
                    request.get("filename", ""),
                    buffer_text(nvim.buffers[buffer]),
                )
            elif operation == "set_highlight_range":
                document_id = int(request["document_id"])
                buffer = document_buffers.get(document_id)
                if buffer is None or not nvim.api.buf_is_valid(buffer):
                    raise ValueError(f"Unknown Notes document: {document_id}")
                line_count = nvim.api.buf_line_count(buffer)
                start_row = max(0, min(int(request["start_row"]), line_count - 1))
                end_row = max(start_row + 1, min(int(request["end_row"]), line_count))
                visible_highlight_ranges[buffer] = (start_row, end_row)
            elif operation == "close_document":
                close_document(nvim, int(request["document_id"]))
            elif operation == "add_command_history":
                nvim.call("histadd", ":", request["command"])
            elif operation == "set_cursor":
                buffer = nvim.current.buffer
                row = max(0, min(int(request["row"]), len(buffer) - 1))
                line = buffer[row]
                if isinstance(line, bytes):
                    line = line.decode("utf-8", errors="ignore")
                column = max(0, min(int(request["column"]), len(line)))
                byte_column = len(line[:column].encode("utf-8"))
                nvim.current.window.cursor = (row + 1, byte_column)
            elif operation not in {"input", "sync", "command_state"}:
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
    nvim.options["hlsearch"] = False
    nvim.current.window.options["number"] = True
    nvim.current.window.options["relativenumber"] = True
    input_nvim.input("i")
    snapshot_thread = threading.Thread(
        target=run_snapshot_worker, args=(nvim,), daemon=True
    )
    snapshot_thread.start()
    install_term_handler()
    emit({
        "type": "ready",
        "highlight_line_limit": FULL_HIGHLIGHT_LINE_LIMIT,
        "highlight_chunk_lines": HIGHLIGHT_CHUNK_LINES,
    })
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
            elif operation not in {
                "select_document", "register_documents", "set_filetype",
                "close_document", "set_cursor", "set_highlight_range", "sync",
                "command_state", "add_command_history",
            }:
                raise ValueError(f"Unknown operation: {operation}")
            snapshot_tasks.put((operation, request))
        except Exception as error:
            emit({"type": "error", "id": request.get("id"), "message": str(error)})
            install_term_handler()
finally:
    snapshot_tasks.put(None)
    cleanup()
