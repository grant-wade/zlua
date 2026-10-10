const std = @import("std");
const compile = @import("../compile.zig");
const runtime = @import("../runtime.zig");
const host = @import("../runtime/host.zig");
const static_strings = @import("static_strings.zig");
const os_lib = @import("os.zig");

const bytecode = compile.bytecode;
const State = runtime.State;
const Thread = runtime.Thread;
const Value = runtime.Value;
const Table = runtime.Table;

const max_line_args = 250;

// File handles are tables with hidden fields. Their logical bytes are
// `content[0..cut] ++ rope ++ content[cut + rope.len..]`, where the rope holds
// the strings written sequentially since `cut`. While a rope exists the
// position is its end, so its length is `pos - 1 - cut` (see `appendToRope`).
// Reads, seeks elsewhere, and non-sequential writes materialize the rope into
// `content` once, keeping sequential writes linear in the bytes written.
const field = struct {
    const file = key("__zlua_file");
    const path = key("__zlua_file_path");
    const mode = key("__zlua_file_mode");
    const content = key("__zlua_file_content");
    const pos = key("__zlua_file_pos");
    const cut = key("__zlua_file_cut");
    const chunks = key("__zlua_file_chunks");
    const blocks = key("__zlua_file_blocks");
    /// Bytes known to match the host file, which is no longer than that.
    /// The handle has unflushed writes while this is below the logical size.
    const synced = key("__zlua_file_synced");
    const generation = key("__zlua_file_generation");
    const closed = key("__zlua_file_closed");
    const standard = key("__zlua_file_standard");
    const buffer_mode = key("__zlua_file_buffer_mode");

    fn key(comptime name: []const u8) Value {
        return .{ .string = static_strings.get(name) };
    }
};

/// Rope strings merged into one string of the next level.
const chunks_per_block = 64;

pub fn read(state: *State, thread: *Thread, op: bytecode.Call) !void {
    const file = try currentFile(state, .input);
    if (runtime.isClosedFileValue(.{ .table = file })) return state.fail(" input file is closed");
    try readFromFile(state, thread, op, file, 0);
}

pub fn write(state: *State, thread: *Thread, op: bytecode.Call) !void {
    const file = try currentFile(state, .output);
    if (runtime.isClosedFileValue(.{ .table = file })) return state.fail(" output file is closed");
    try writeToFile(state, thread, op, file, 0, "io.write");
}

pub fn open(state: *State, thread: *Thread, op: bytecode.Call) !void {
    const path = try state.expectArgumentString(thread, op, "io.open", 0);
    const mode = if (op.arg_count >= 2 and runtime.argValue(state, thread, op, 1) != .nil)
        try state.expectArgumentString(thread, op, "io.open", 1)
    else
        "r";
    const parsed = parseMode(mode) orelse return state.failArgumentMessage("io.open", 2, "invalid mode");

    if (isSpecialDevice(path)) {
        try state.returnValues(thread, op.base, op.return_count, &.{try newFile(state, path, mode, "", parsed)});
        return;
    }

    const contents = if (parsed.reads_existing or parsed.append)
        state.readFileRaw(path) catch |err| switch (err) {
            error.OutOfMemory => return err,
            error.FileNotFound => if (parsed.kind == 'r') return os_lib.fileFailure(state, thread, op, path, err) else try state.allocator.dupe(u8, ""),
            error.IsDir => if (parsed.kind == 'r' and !parsed.plus) {
                // C `fopen` opens directories for reading; reads then fail.
                const file = try newFile(state, path, mode, "", parsed);
                try markDirectoryHandle(state, file.table);
                try state.returnValues(thread, op.base, op.return_count, &.{file});
                return;
            } else return os_lib.fileFailure(state, thread, op, path, err),
            else => return os_lib.fileFailure(state, thread, op, path, err),
        }
    else
        try state.allocator.dupe(u8, "");
    defer state.allocator.free(contents);
    if (parsed.kind != 'r') state.fsWriteFile(path, contents) catch |err| return os_lib.fileFailure(state, thread, op, path, err);
    try state.returnValues(thread, op.base, op.return_count, &.{try newFile(state, path, mode, contents, parsed)});
}

pub fn popen(state: *State, thread: *Thread, op: bytecode.Call) !void {
    const command = try state.expectArgumentString(thread, op, "io.popen", 0);
    const mode = if (op.arg_count >= 2 and runtime.argValue(state, thread, op, 1) != .nil)
        try state.expectArgumentString(thread, op, "io.popen", 1)
    else
        "r";
    if (!std.mem.eql(u8, mode, "r") and !std.mem.eql(u8, mode, "w")) return state.failArgumentMessage("io.popen", 2, "invalid mode");
    const parsed = parseMode(mode).?;

    var command_output: []const u8 = "";
    var result: ?host.ProcessResult = null;
    if (mode[0] == 'r') {
        const popen_result = try state.popenProcess(command, null);
        command_output = popen_result.output;
        result = popen_result.result;
    } else if (!state.processEnabled()) {
        return state.fail("'popen' not supported");
    } else switch (state.options.process) {
        .custom => |process| if (process.popen == null) return state.fail("'popen' not supported"),
        else => {},
    }
    defer state.allocator.free(command_output);

    const value = try newFile(state, command, mode, command_output, parsed);
    const file = value.table;
    try state.setTableRaw(file, .{ .string = try state.intern("__zlua_file_popen") }, .{ .boolean = true });
    if (result) |status| try setPopenResult(state, file, status);
    try state.returnValues(thread, op.base, op.return_count, &.{value});
}

fn setPopenResult(state: *State, file: *Table, result: host.ProcessResult) !void {
    try state.setTableRaw(file, .{ .string = try state.intern("__zlua_popen_status") }, .{ .string = try state.intern(@tagName(result.status)) });
    try state.setTableRaw(file, .{ .string = try state.intern("__zlua_popen_code") }, .{ .integer = result.code });
}

fn isPopenFile(file: *Table) bool {
    return file.get(.{ .string = "__zlua_file_popen" }) == .boolean;
}

/// Finishes a popen handle: write mode runs the command with the buffered
/// input now. Returns the command's termination status.
fn finishPopen(state: *State, file: *Table) !host.ProcessResult {
    if (file.get(.{ .string = "__zlua_popen_status" }) == .nil) {
        const command = try fileString(state, file, field.path);
        const pending_input = try fileContent(state, file);
        const popen_result = try state.popenProcess(command, pending_input);
        state.allocator.free(popen_result.output);
        try setPopenResult(state, file, popen_result.result);
    }
    const status = try fileString(state, file, .{ .string = "__zlua_popen_status" });
    return .{
        .status = if (std.mem.eql(u8, status, "signal")) .signal else .exit,
        .code = runtime.toInteger(file.get(.{ .string = "__zlua_popen_code" })) orelse 0,
    };
}

pub fn fileTostring(state: *State, thread: *Thread, op: bytecode.Call) !void {
    const value = runtime.argValue(state, thread, op, 0);
    _ = try expectFileArgument(state, value, "file:__tostring", 1);
    try state.returnValues(thread, op.base, op.return_count, &.{.{ .string = try state.valueToString(thread, value) }});
}

pub fn input(state: *State, thread: *Thread, op: bytecode.Call) !void {
    try setCurrentFile(state, thread, op, .input);
}

pub fn output(state: *State, thread: *Thread, op: bytecode.Call) !void {
    try setCurrentFile(state, thread, op, .output);
}

pub fn close(state: *State, thread: *Thread, op: bytecode.Call) !void {
    const value = if (op.arg_count == 0 or runtime.argValue(state, thread, op, 0) == .nil)
        Value{ .table = try currentFile(state, .output) }
    else
        runtime.argValue(state, thread, op, 0);
    try closeFileValue(state, thread, op, value, "io.close", false);
}

pub fn flush(state: *State, thread: *Thread, op: bytecode.Call) !void {
    const file = try currentFile(state, .output);
    if (std.mem.eql(u8, try fileString(state, file, field.path), "/dev/full")) {
        try state.returnValues(thread, op.base, op.return_count, &.{.nil});
        return;
    }
    try flushFile(state, file);
    try state.returnValues(thread, op.base, op.return_count, &.{.{ .boolean = true }});
}

pub fn lines(state: *State, thread: *Thread, op: bytecode.Call) !void {
    if (op.arg_count > max_line_args + 1) return state.fail("too many arguments");
    var start: u16 = 0;
    const file_value = if (op.arg_count >= 1 and runtime.argValue(state, thread, op, 0) != .nil) blk: {
        start = 1;
        const path = try state.expectArgumentString(thread, op, "io.lines", 0);
        break :blk try openCheckedFile(state, path, "r");
    } else blk: {
        if (op.arg_count >= 1) start = 1;
        break :blk Value{ .table = try currentFile(state, .input) };
    };
    const iterator = try newLinesIterator(state, thread, file_value, op, start, start == 1);
    if (start == 1) {
        try state.returnValues(thread, op.base, op.return_count, &.{ iterator, file_value, .nil, file_value });
    } else {
        try state.returnValues(thread, op.base, op.return_count, &.{iterator});
    }
}

pub fn tmpfile(state: *State, thread: *Thread, op: bytecode.Call) !void {
    const path = try tmpPath(state);
    defer state.allocator.free(path);
    const parsed = parseMode("w+").?;
    const file = try newFile(state, path, "w+", "", parsed);
    // The host file is created by the first flush or close, even when empty.
    try state.setTableRaw(file.table, field.synced, .{ .integer = -1 });
    try state.returnValues(thread, op.base, op.return_count, &.{file});
}

pub fn typeValue(state: *State, thread: *Thread, op: bytecode.Call) !void {
    const file = runtime.argValue(state, thread, op, 0);
    if (!runtime.isFileValue(file)) {
        try state.returnValues(thread, op.base, op.return_count, &.{.nil});
        return;
    }
    const name = if (runtime.isClosedFileValue(file)) "closed file" else "file";
    try state.returnValues(thread, op.base, op.return_count, &.{.{ .string = try state.intern(name) }});
}

pub fn fileRead(state: *State, thread: *Thread, op: bytecode.Call) !void {
    const file = try expectFileArgument(state, runtime.argValue(state, thread, op, 0), "file:read", 1);
    try readFromFile(state, thread, op, file, 1);
}

pub fn fileWrite(state: *State, thread: *Thread, op: bytecode.Call) !void {
    const file = try expectFileArgument(state, runtime.argValue(state, thread, op, 0), "file:write", 1);
    try writeToFile(state, thread, op, file, 1, "file:write");
}

pub fn fileClose(state: *State, thread: *Thread, op: bytecode.Call) !void {
    if (op.arg_count == 0) return state.failArgumentMessage("file:close", 1, "FILE* expected, got no value");
    if (runtime.isClosedFileValue(runtime.argValue(state, thread, op, 0))) {
        try state.returnValues(thread, op.base, op.return_count, &.{.nil});
        return;
    }
    try closeFileValue(state, thread, op, runtime.argValue(state, thread, op, 0), "file:close", false);
}

pub fn fileSeek(state: *State, thread: *Thread, op: bytecode.Call) !void {
    const file = try expectFileArgument(state, runtime.argValue(state, thread, op, 0), "file:seek", 1);
    try ensureOpen(state, file);
    const whence = if (op.arg_count >= 2 and runtime.argValue(state, thread, op, 1) != .nil)
        try state.expectArgumentString(thread, op, "file:seek", 1)
    else
        "cur";
    const offset = if (op.arg_count >= 3 and runtime.argValue(state, thread, op, 2) != .nil)
        try state.argumentInteger(thread, op, "file:seek", 2)
    else
        0;
    const Whence = enum { set, cur, end };
    const kind: Whence = if (std.mem.eql(u8, whence, "set"))
        .set
    else if (std.mem.eql(u8, whence, "cur"))
        .cur
    else if (std.mem.eql(u8, whence, "end"))
        .end
    else
        return state.failArgumentMessage("file:seek", 2, "invalid whence");

    if (isStandardStream(file, "stdin")) {
        // A host stdin stream is a pipe or terminal, like C stdin under `lua`.
        if (state.stdinIsStream()) {
            try state.returnValues(thread, op.base, op.return_count, &.{ .nil, .{ .string = try state.intern("Illegal seek") }, .{ .integer = 29 } });
            return;
        }
        const base: i64 = switch (kind) {
            .set => 0,
            .cur => @intCast(state.stdin_pos),
            .end => @intCast(state.options.stdin.len),
        };
        const new_pos = base + offset;
        if (new_pos < 0) return returnInvalidSeek(state, thread, op);
        state.stdin_pos = @intCast(new_pos);
        try state.returnValues(thread, op.base, op.return_count, &.{.{ .integer = new_pos }});
        return;
    }

    try refreshReadable(state, file);
    const current: i64 = @intCast(currentPos(file));
    const base: i64 = switch (kind) {
        .set => 0,
        .cur => current,
        .end => @intCast(logicalSize(file, try fileString(state, file, field.content))),
    };
    const new_pos = base + offset;
    if (new_pos < 0) return returnInvalidSeek(state, thread, op);
    if (new_pos != current) {
        // Moving away from the end of a write run ends it.
        _ = try fileContent(state, file);
        try setPos(state, file, @as(usize, @intCast(new_pos)) + 1);
    }
    try state.returnValues(thread, op.base, op.return_count, &.{.{ .integer = new_pos }});
}

fn returnInvalidSeek(state: *State, thread: *Thread, op: bytecode.Call) !void {
    try state.returnValues(thread, op.base, op.return_count, &.{ .nil, .{ .string = try state.intern("invalid argument") }, .{ .integer = 22 } });
}

pub fn fileFlush(state: *State, thread: *Thread, op: bytecode.Call) !void {
    const file = try expectFileArgument(state, runtime.argValue(state, thread, op, 0), "file:flush", 1);
    try ensureOpen(state, file);
    if (std.mem.eql(u8, try fileString(state, file, field.path), "/dev/full")) {
        try state.returnValues(thread, op.base, op.return_count, &.{.nil});
        return;
    }
    try flushFile(state, file);
    try state.returnValues(thread, op.base, op.return_count, &.{.{ .boolean = true }});
}

pub fn fileLines(state: *State, thread: *Thread, op: bytecode.Call) !void {
    const file_value = runtime.argValue(state, thread, op, 0);
    _ = try expectFileArgument(state, file_value, "file:lines", 1);
    if (op.arg_count > max_line_args + 1) return state.fail("too many arguments");
    const iterator = try newLinesIterator(state, thread, file_value, op, 1, false);
    try state.returnValues(thread, op.base, op.return_count, &.{iterator});
}

pub fn fileSetvbuf(state: *State, thread: *Thread, op: bytecode.Call) !void {
    const file = try expectFileArgument(state, runtime.argValue(state, thread, op, 0), "file:setvbuf", 1);
    try ensureOpen(state, file);
    const mode = try state.expectArgumentString(thread, op, "file:setvbuf", 1);
    if (!std.mem.eql(u8, mode, "no") and !std.mem.eql(u8, mode, "full") and !std.mem.eql(u8, mode, "line")) return state.failArgumentMessage("file:setvbuf", 2, "invalid mode");
    // Like C `setvbuf`, changing the mode first writes any buffered output.
    try flushFile(state, file);
    try state.setTableRaw(file, field.buffer_mode, .{ .string = try state.intern(mode) });
    try state.returnValues(thread, op.base, op.return_count, &.{.{ .boolean = true }});
}

pub fn linesIter(state: *State, thread: *Thread, op: bytecode.Call) !void {
    const values = try linesNext(state, runtime.argValue(state, thread, op, 0));
    defer if (values.len != 0) state.allocator.free(values);
    try state.returnValues(thread, op.base, op.return_count, values);
}

pub fn linesNext(state: *State, iterator: Value) ![]const Value {
    if (iterator != .table) return state.fail("file is already closed");
    const table = iterator.table;
    const file_value = table.get(.{ .string = "file" });
    if (runtime.isClosedFileValue(file_value)) return state.fail("file is already closed");
    const file = try expectFile(state, file_value);
    const specs = table.get(.{ .string = "specs" });
    var values = std.ArrayList(Value).empty;
    errdefer values.deinit(state.allocator);
    if (specs == .table and specs.table.array.items.len != 0) {
        for (specs.table.array.items) |spec| try values.append(state.allocator, try readOne(state, file, spec));
    } else {
        try values.append(state.allocator, try readOne(state, file, .{ .string = try state.intern("l") }));
    }
    if (values.items.len == 0 or values.items[0] == .nil) {
        values.deinit(state.allocator);
        if (table.get(.{ .string = "auto_close" }) == .boolean and table.get(.{ .string = "auto_close" }).boolean) {
            try closeFile(state, file, true);
        }
        return &[_]Value{};
    }
    return try values.toOwnedSlice(state.allocator);
}

const CurrentFile = enum { input, output };

fn setCurrentFile(state: *State, thread: *Thread, op: bytecode.Call, which: CurrentFile) !void {
    if (op.arg_count == 0 or runtime.argValue(state, thread, op, 0) == .nil) {
        try state.returnValues(thread, op.base, op.return_count, &.{.{ .table = try currentFile(state, which) }});
        return;
    }
    var value = runtime.argValue(state, thread, op, 0);
    if (value == .string) {
        value = try openCheckedFile(state, value.string, if (which == .output) "w" else "r");
    } else {
        _ = try expectFileArgument(state, value, if (which == .output) "io.output" else "io.input", 1);
    }
    // Like `g_iofile`, the previous file stays open; `__gc` or process exit
    // flushes it if nothing else does.
    switch (which) {
        .input => state.io_input = value.table,
        .output => state.io_output = value.table,
    }
    try state.returnValues(thread, op.base, op.return_count, &.{value});
}

/// Opens a file for `io.lines`, `io.input`, and `io.output`, raising
/// "cannot open file '<path>' (<message>)" like Lua's `opencheckfile`.
fn openCheckedFile(state: *State, path: []const u8, mode: []const u8) !Value {
    const parsed = parseMode(mode).?;
    if (isSpecialDevice(path)) return newFile(state, path, mode, "", parsed);
    if (parsed.kind != 'r') {
        state.fsWriteFile(path, "") catch |err| return failOpenChecked(state, path, err);
        return newFile(state, path, mode, "", parsed);
    }
    const contents = state.readFileRaw(path) catch |err| {
        if (err != error.IsDir) return failOpenChecked(state, path, err);
        const file = try newFile(state, path, mode, "", parsed);
        try markDirectoryHandle(state, file.table);
        return file;
    };
    defer state.allocator.free(contents);
    return newFile(state, path, mode, contents, parsed);
}

fn failOpenChecked(state: *State, path: []const u8, err: anyerror) anyerror {
    if (err == error.OutOfMemory) return err;
    const message = try std.fmt.allocPrint(state.allocator, "cannot open file '{s}' ({s})", .{ path, host.fileError(err).message });
    defer state.allocator.free(message);
    return state.fail(try state.intern(message));
}

/// Marks a handle that opened a directory: C `fopen` succeeds, then reads fail.
fn markDirectoryHandle(state: *State, file: *Table) !void {
    try state.setTableRaw(file, .{ .string = try state.intern("__zlua_file_read_error") }, .{ .boolean = true });
}

fn readError(file: *Table) ?host.FileError {
    if (file.get(.{ .string = "__zlua_file_read_error" }) == .nil) return null;
    return host.fileError(error.IsDir);
}

/// Reads the rest of standard input for `dofile()` and `loadfile()`, sharing
/// the `io.stdin` position. The caller owns the bytes.
pub fn readAllStdin(state: *State) ![]u8 {
    var source = state.stdinSource();
    defer source.finish();
    var bytes: std.ArrayList(u8) = .empty;
    errdefer bytes.deinit(state.allocator);
    try appendRemaining(state, source.reader(), &bytes);
    return bytes.toOwnedSlice(state.allocator);
}

/// Reads one line, including its newline, from standard input; null at end of input.
pub fn readStdinLine(state: *State) !?[]const u8 {
    const value = try readStdinFormat(state, .{ .line = true });
    return if (value == .string) value.string else null;
}

/// Returns the unread bytes of a readable file and moves it to the end, for
/// decoders that accept a FILE*.
pub fn readRemaining(state: *State, file: *Table) ![]const u8 {
    if (isStandardStream(file, "stdin")) {
        const value = try readStdinFormat(state, .all);
        return if (value == .string) value.string else "";
    }
    try refreshReadable(state, file);
    const content = try fileContent(state, file);
    const start = @min(content.len, currentPos(file));
    try setPos(state, file, content.len + 1);
    return content[start..];
}

/// Writes the buffered output of every open file handle, as C `exit` flushes
/// all streams. Used by the CLI before the process ends; errors are ignored.
pub fn flushOpenFiles(state: *State) void {
    var index: usize = 0;
    while (index < state.table_allocations.items.len) : (index += 1) {
        const table = state.table_allocations.items[index];
        const value: Value = .{ .table = table };
        if (!runtime.isFileValue(value) or runtime.isClosedFileValue(value) or isPopenFile(table)) continue;
        if (!fileWritable(table) or !hasUnflushedWrites(table)) continue;
        flushFile(state, table) catch {};
    }
}

fn currentFile(state: *State, which: CurrentFile) !*Table {
    return switch (which) {
        .input => state.io_input,
        .output => state.io_output,
    } orelse state.fail("file expected");
}

fn readFromFile(state: *State, thread: *Thread, op: bytecode.Call, file: *Table, first_arg: u16) !void {
    try ensureOpen(state, file);
    if (!fileReadable(file)) {
        try state.returnValues(thread, op.base, op.return_count, &.{ .nil, .{ .string = try state.intern("file is not readable") }, .{ .integer = 9 } });
        return;
    }
    if (readError(file)) |info| {
        try state.returnValues(thread, op.base, op.return_count, &.{ .nil, .{ .string = try state.intern(info.message) }, .{ .integer = info.errno } });
        return;
    }
    var values = std.ArrayList(Value).empty;
    defer values.deinit(state.allocator);
    if (op.arg_count <= first_arg) {
        try values.append(state.allocator, try readOne(state, file, .{ .string = try state.intern("l") }));
    } else {
        var index = first_arg;
        while (index < op.arg_count) : (index += 1) {
            const value = try readOne(state, file, runtime.argValue(state, thread, op, index));
            try values.append(state.allocator, value);
            if (value == .nil) break;
        }
    }
    try state.returnValues(thread, op.base, op.return_count, values.items);
}

const ReadFormat = union(enum) {
    count: usize,
    all,
    /// Keeps the newline for "L".
    line: bool,
    number,
};

fn parseReadFormat(state: *State, spec_value: Value) !ReadFormat {
    if (runtime.toInteger(spec_value)) |count| {
        if (count < 0) return state.fail("invalid format");
        return .{ .count = @intCast(count) };
    }
    var spec = try state.expectString(spec_value);
    if (spec.len != 0 and spec[0] == '*') spec = spec[1..];
    // Like `g_read`, only the first letter selects the format.
    if (spec.len == 0) return state.fail("invalid format");
    return switch (spec[0]) {
        'a' => .all,
        'l' => .{ .line = false },
        'L' => .{ .line = true },
        'n' => .number,
        else => state.fail("invalid format"),
    };
}

fn readOne(state: *State, file: *Table, spec_value: Value) !Value {
    try ensureOpen(state, file);
    try ensureReadable(state, file);
    if (readError(file)) |info| return state.fail(info.message);
    const format = try parseReadFormat(state, spec_value);
    if (isStandardStream(file, "stdin")) return readStdinFormat(state, format);
    try refreshReadable(state, file);
    const content = try fileContent(state, file);
    const start = @min(content.len, currentPos(file));

    switch (format) {
        .count => |count| {
            if (count == 0) return if (start < content.len) .{ .string = try state.intern("") } else .nil;
            if (start >= content.len) return .nil;
            const end = start + @min(content.len - start, count);
            try setPos(state, file, end + 1);
            return .{ .string = try state.intern(content[start..end]) };
        },
        .all => {
            try setPos(state, file, content.len + 1);
            return .{ .string = try state.intern(content[start..]) };
        },
        .line => |keep_newline| {
            if (start >= content.len) return .nil;
            const end = std.mem.indexOfScalarPos(u8, content, start, '\n') orelse content.len;
            const include_newline = keep_newline and end < content.len;
            const slice_end = if (include_newline) end + 1 else end;
            try setPos(state, file, if (end < content.len) end + 2 else end + 1);
            return .{ .string = try state.intern(content[start..slice_end]) };
        },
        .number => {
            const scanned = scanNumber(content, start);
            try setPos(state, file, scanned.next + 1);
            return scanned.value;
        },
    }
}

/// Reads standard input incrementally through the state's stdin source, so
/// interactive input is consumed as needed instead of up to end of file.
fn readStdinFormat(state: *State, format: ReadFormat) !Value {
    var source = state.stdinSource();
    defer source.finish();
    const reader = source.reader();
    switch (format) {
        .count => |count| {
            const available = peekSome(reader) orelse return .nil;
            if (count == 0) return .{ .string = try state.intern("") };
            if (available.len >= count) {
                const value = try state.intern(available[0..count]);
                reader.toss(count);
                return .{ .string = value };
            }
            var bytes: std.ArrayList(u8) = .empty;
            defer bytes.deinit(state.allocator);
            while (bytes.items.len < count) {
                const more = peekSome(reader) orelse break;
                const take = @min(more.len, count - bytes.items.len);
                try bytes.appendSlice(state.allocator, more[0..take]);
                reader.toss(take);
            }
            return .{ .string = try state.intern(bytes.items) };
        },
        .all => {
            var bytes: std.ArrayList(u8) = .empty;
            defer bytes.deinit(state.allocator);
            try appendRemaining(state, reader, &bytes);
            return .{ .string = try state.intern(bytes.items) };
        },
        .line => |keep_newline| {
            var bytes: std.ArrayList(u8) = .empty;
            defer bytes.deinit(state.allocator);
            while (peekSome(reader)) |available| {
                if (std.mem.indexOfScalar(u8, available, '\n')) |newline| {
                    const end = if (keep_newline) newline + 1 else newline;
                    const value = if (bytes.items.len == 0) try state.intern(available[0..end]) else blk: {
                        try bytes.appendSlice(state.allocator, available[0..end]);
                        break :blk try state.intern(bytes.items);
                    };
                    reader.toss(newline + 1);
                    return .{ .string = value };
                }
                try bytes.appendSlice(state.allocator, available);
                reader.toss(available.len);
            }
            if (bytes.items.len == 0) return .nil;
            return .{ .string = try state.intern(bytes.items) };
        },
        .number => {
            while (true) {
                const available = peekSome(reader) orelse return .nil;
                const skip = whitespacePrefix(available);
                reader.toss(skip);
                if (skip < available.len) break;
            }
            // Look ahead through one numeral and the byte that ends it.
            const window_limit = @min(reader.buffer.len, 600);
            var window: []const u8 = reader.buffered();
            var len: usize = 0;
            while (len < window_limit) {
                window = reader.peek(len + 1) catch {
                    window = reader.buffered();
                    break;
                };
                len += 1;
                if (!isNumberTokenByte(window[len - 1])) break;
            }
            const scanned = scanNumber(window, 0);
            reader.toss(scanned.next);
            return scanned.value;
        },
    }
}

/// Buffered stdin bytes, reading more when none are buffered; null at end of
/// input. A read failure ends input like C `fread` does.
fn peekSome(reader: *std.Io.Reader) ?[]u8 {
    return reader.peekGreedy(1) catch null;
}

fn appendRemaining(state: *State, reader: *std.Io.Reader, bytes: *std.ArrayList(u8)) !void {
    while (peekSome(reader)) |available| {
        if (bytes.items.len + available.len > state.options.max_file_bytes) return state.fail("File too large");
        try bytes.appendSlice(state.allocator, available);
        reader.toss(available.len);
    }
}

fn whitespacePrefix(bytes: []const u8) usize {
    var index: usize = 0;
    while (index < bytes.len and std.ascii.isWhitespace(bytes[index])) index += 1;
    return index;
}

const NumberScan = struct {
    value: Value,
    /// Offset after the bytes the read consumes.
    next: usize,
};

/// Scans a numeral like `read_number`: on failure the bytes Lua would have
/// consumed are still skipped.
fn scanNumber(content: []const u8, start: usize) NumberScan {
    const pos = start + whitespacePrefix(content[start..]);
    if (pos >= content.len) return .{ .value = .nil, .next = pos };
    var token_end = pos;
    while (token_end < content.len and isNumberTokenByte(content[token_end])) token_end += 1;
    if (token_end - pos > 350) return .{ .value = .nil, .next = @min(token_end, pos + 4) };
    if (invalidHexPrefix(content[pos..token_end])) return .{ .value = .nil, .next = pos + 2 };
    if (invalidBareExponentToken(content[pos..token_end])) return .{ .value = .nil, .next = token_end };
    var end = @min(token_end, pos + 512);
    while (end > pos) : (end -= 1) {
        const slice = content[pos..end];
        if (runtime.parseIntegerStrict(slice)) |integer| return .{ .value = .{ .integer = integer }, .next = end };
        if (runtime.parseLuaNumber(slice)) |number| {
            return .{ .value = .{ .number = number }, .next = end };
        } else |_| {}
    }
    return .{ .value = .nil, .next = pos + failedNumberPrefix(content[pos..]) };
}

fn failedNumberPrefix(text: []const u8) usize {
    if (text.len >= 2 and (text[0] == '+' or text[0] == '-') and text[1] == '-') return 1;
    if (text.len >= 2 and text[0] == '0' and (text[1] == 'x' or text[1] == 'X')) return 2;
    if (text.len != 0 and (text[0] == '.' or text[0] == '+' or text[0] == '-')) return 1;
    return 0;
}

fn isNumberTokenByte(byte: u8) bool {
    return std.ascii.isAlphanumeric(byte) or byte == '+' or byte == '-' or byte == '.';
}

fn invalidBareExponentToken(token: []const u8) bool {
    if (token.len < 2) return false;
    const last = token[token.len - 1];
    if (last != 'e' and last != 'E') return false;
    if (std.mem.indexOfScalar(u8, token, 'p') != null or std.mem.indexOfScalar(u8, token, 'P') != null) return false;
    return std.mem.indexOfScalar(u8, token[0 .. token.len - 1], 'e') == null and
        std.mem.indexOfScalar(u8, token[0 .. token.len - 1], 'E') == null;
}

fn invalidHexPrefix(token: []const u8) bool {
    if (token.len < 3) return false;
    const unsigned = if (token[0] == '+' or token[0] == '-') token[1..] else token;
    return unsigned.len >= 3 and unsigned[0] == '0' and (unsigned[1] == 'x' or unsigned[1] == 'X') and !std.ascii.isHex(unsigned[2]);
}

const WriteTarget = enum { stdout, stderr, discard, buffer };

fn writeTarget(state: *State, file: *Table) !WriteTarget {
    if (isPopenFile(file)) return .buffer;
    const path = try fileString(state, file, field.path);
    if (file.get(field.standard) != .nil) {
        if (std.mem.eql(u8, path, "stdout")) return .stdout;
        if (std.mem.eql(u8, path, "stderr")) return .stderr;
    }
    if (isSpecialDevice(path)) return .discard;
    return .buffer;
}

fn writeToFile(state: *State, thread: *Thread, op: bytecode.Call, file: *Table, first_arg: u16, function_name: []const u8) !void {
    try ensureOpen(state, file);
    const mode = file.get(field.mode);
    if (!modeWritable(mode)) {
        try state.returnValues(thread, op.base, op.return_count, &.{ .nil, .{ .string = try state.intern("file is not writable") }, .{ .integer = 9 } });
        return;
    }
    const append_mode = mode.string[0] == 'a';
    const target = try writeTarget(state, file);
    const buffer_mode = try fileString(state, file, field.buffer_mode);
    const line_buffered = std.mem.eql(u8, buffer_mode, "line");
    var wrote_newline = false;
    var formatted: std.ArrayList(u8) = .empty;
    defer formatted.deinit(state.allocator);
    var index = first_arg;
    while (index < op.arg_count) : (index += 1) {
        const value = runtime.argValue(state, thread, op, index);
        const bytes = switch (value) {
            .string => |string| string,
            .integer, .number => blk: {
                formatted.clearRetainingCapacity();
                try runtime.appendLuaString(state.allocator, &formatted, value);
                break :blk formatted.items;
            },
            else => return state.failArgumentType(function_name, index + 1 - first_arg, "string", value),
        };
        if (line_buffered and !wrote_newline and std.mem.indexOfScalar(u8, bytes, '\n') != null) wrote_newline = true;
        switch (target) {
            .stdout => try state.writeStdout(bytes),
            .stderr => try state.writeStderr(bytes),
            .discard => {},
            .buffer => try writeBytes(state, file, if (value == .string) value.string else try state.intern(bytes), append_mode),
        }
    }
    if (std.mem.eql(u8, buffer_mode, "no") or wrote_newline) try flushFile(state, file);
    try state.returnValues(thread, op.base, op.return_count, &.{.{ .table = file }});
}

/// Writes an interned string at the handle's position, or at the end in
/// append mode. Continuing the current write run only appends to the rope;
/// any other write first folds the run into `content` and starts a new one.
fn writeBytes(state: *State, file: *Table, bytes: []const u8, append_mode: bool) !void {
    if (bytes.len == 0) return;
    const position = currentPos(file);
    if (file.get(field.cut) != .nil) {
        // The run ends at `position`; appends continue it while it ends the file.
        if (!append_mode or position >= (try fileString(state, file, field.content)).len) {
            try appendToRope(state, file, bytes);
            return setPos(state, file, position + bytes.len + 1);
        }
        _ = try fileContent(state, file);
    }
    const content = try fileString(state, file, field.content);
    const pos = if (append_mode) content.len else position;
    if (pos > content.len) {
        // Writing past the end fills the gap with zero bytes.
        var grown: std.ArrayList(u8) = try .initCapacity(state.allocator, pos);
        defer grown.deinit(state.allocator);
        grown.appendSliceAssumeCapacity(content);
        grown.appendNTimesAssumeCapacity(0, pos - content.len);
        try state.setTableRaw(file, field.content, .{ .string = try state.intern(grown.items) });
    }
    try state.setTableRaw(file, field.cut, .{ .integer = @intCast(pos) });
    const synced = fileInteger(file, field.synced) orelse 0;
    if (pos < synced) try state.setTableRaw(file, field.synced, .{ .integer = @intCast(pos) });
    try appendToRope(state, file, bytes);
    try setPos(state, file, pos + bytes.len + 1);
}

/// Adds a string to the rope. `chunks` holds the newest strings; `blocks[i]`
/// holds strings that each merge `chunks_per_block` strings of the level
/// below. Merging a full level like a base-64 counter copies each byte a
/// logarithmic number of times while every rope table stays small, so the
/// collector never rescans a long, growing list.
fn appendToRope(state: *State, file: *Table, bytes: []const u8) !void {
    var chunks = file.get(field.chunks);
    if (chunks == .nil) {
        chunks = try state.newTableWithHints(chunks_per_block, 0);
        try state.setTableRaw(file, field.chunks, chunks);
    }
    try appendPiece(state, chunks.table, .{ .string = bytes });
    if (chunks.table.array.items.len < chunks_per_block) return;

    var merged = try mergePieces(state, chunks.table);
    try state.setTableRaw(file, field.chunks, .nil);
    var levels = file.get(field.blocks);
    if (levels == .nil) {
        levels = try state.newTableWithHints(4, 0);
        try state.setTableRaw(file, field.blocks, levels);
    }
    var level: usize = 0;
    while (true) : (level += 1) {
        if (level == levels.table.array.items.len) try appendPiece(state, levels.table, try state.newTableWithHints(chunks_per_block, 0));
        const pieces = levels.table.array.items[level].table;
        try appendPiece(state, pieces, merged);
        if (pieces.array.items.len < chunks_per_block) return;
        merged = try mergePieces(state, pieces);
        try state.setTableRaw(levels.table, .{ .integer = @intCast(level + 1) }, try state.newTableWithHints(chunks_per_block, 0));
    }
}

fn appendPiece(state: *State, list: *Table, value: Value) !void {
    try state.setTableRaw(list, .{ .integer = @intCast(list.array.items.len + 1) }, value);
}

fn mergePieces(state: *State, list: *Table) !Value {
    var size: usize = 0;
    for (list.array.items) |piece| size += piece.string.len;
    var merged: std.ArrayList(u8) = try .initCapacity(state.allocator, size);
    defer merged.deinit(state.allocator);
    for (list.array.items) |piece| merged.appendSliceAssumeCapacity(piece.string);
    return .{ .string = try state.intern(merged.items) };
}

/// Calls `visit` on each rope string in logical order: the highest block
/// level holds the oldest bytes and `chunks` the newest.
fn forEachRopePiece(file: *Table, context: anytype, comptime visit: fn (@TypeOf(context), []const u8) anyerror!void) !void {
    const levels = file.get(field.blocks);
    if (levels == .table) {
        var level = levels.table.array.items.len;
        while (level > 0) {
            level -= 1;
            for (levels.table.array.items[level].table.array.items) |piece| try visit(context, piece.string);
        }
    }
    const chunks = file.get(field.chunks);
    if (chunks == .table) for (chunks.table.array.items) |piece| try visit(context, piece.string);
}

/// Logical length of a handle's bytes, including an unmerged write run.
fn logicalSize(file: *Table, content: []const u8) usize {
    if (file.get(field.cut) == .nil) return content.len;
    return @max(content.len, currentPos(file));
}

fn hasUnflushedWrites(file: *Table) bool {
    const content = file.get(field.content);
    if (content != .string) return false;
    return (fileInteger(file, field.synced) orelse 0) < logicalSize(file, content.string);
}

/// Appends the logical bytes from offset `from` without materializing them.
fn appendLogicalFrom(state: *State, file: *Table, content: []const u8, from: usize, out: *std.ArrayList(u8)) !void {
    const Appender = struct {
        state: *State,
        out: *std.ArrayList(u8),
        offset: usize = 0,
        from: usize,

        fn add(self: *@This(), bytes: []const u8) anyerror!void {
            const end = self.offset + bytes.len;
            if (end > self.from) try self.out.appendSlice(self.state.allocator, bytes[self.from -| self.offset..]);
            self.offset = end;
        }
    };
    var appender: Appender = .{ .state = state, .out = out, .from = from };
    const cut_value = file.get(field.cut);
    if (cut_value == .nil) return appender.add(content);
    const cut: usize = @intCast(cut_value.integer);
    const rope_end = currentPos(file);
    try appender.add(content[0..cut]);
    try forEachRopePiece(file, &appender, Appender.add);
    std.debug.assert(appender.offset == rope_end);
    if (rope_end < content.len) try appender.add(content[rope_end..]);
}

/// Returns a handle's complete bytes, folding any write run into `content`.
pub fn fileContent(state: *State, file: *Table) ![]const u8 {
    const content = try fileString(state, file, field.content);
    if (file.get(field.cut) == .nil) return content;
    var bytes: std.ArrayList(u8) = .empty;
    defer bytes.deinit(state.allocator);
    try bytes.ensureTotalCapacity(state.allocator, logicalSize(file, content));
    try appendLogicalFrom(state, file, content, 0, &bytes);
    const merged = try state.intern(bytes.items);
    try state.setTableRaw(file, field.content, .{ .string = merged });
    try state.setTableRaw(file, field.cut, .nil);
    try state.setTableRaw(file, field.chunks, .nil);
    try state.setTableRaw(file, field.blocks, .nil);
    return merged;
}

fn closeFileValue(state: *State, thread: *Thread, op: bytecode.Call, value: Value, function_name: []const u8, from_iterator: bool) !void {
    const file = try expectFileArgument(state, value, function_name, 1);
    if (runtime.isClosedFileValue(value)) {
        if (from_iterator) return;
        return state.fail("attempt to use a closed file");
    }
    if (file.get(field.standard) == .boolean and file.get(field.standard).boolean) {
        try state.returnValues(thread, op.base, op.return_count, &.{.nil});
        return;
    }
    if (isPopenFile(file)) {
        const result = try finishPopen(state, file);
        try state.setTableRaw(file, field.closed, .{ .boolean = true });
        if (!from_iterator) try os_lib.returnProcessResult(state, thread, op, result);
        return;
    }
    try closeFile(state, file, from_iterator);
    if (!from_iterator) try state.returnValues(thread, op.base, op.return_count, &.{.{ .boolean = true }});
}

fn closeFile(state: *State, file: *Table, from_iterator: bool) !void {
    _ = from_iterator;
    if (isPopenFile(file)) {
        _ = try finishPopen(state, file);
    } else if (fileWritable(file)) try flushFile(state, file);
    try state.setTableRaw(file, field.closed, .{ .boolean = true });
}

/// Writes a handle's unflushed bytes. When this handle made the last
/// filesystem change, only the bytes after `synced` are written in place;
/// otherwise, or without positional writes, the whole file is rewritten.
fn flushFile(state: *State, file: *Table) !void {
    if (isPopenFile(file)) return;
    const path = try fileString(state, file, field.path);
    if (file.get(field.standard) != .nil) {
        if (std.mem.eql(u8, path, "stdout")) return state.flushStdout();
        if (std.mem.eql(u8, path, "stderr")) return state.flushStderr();
        return;
    }
    if (isSpecialDevice(path) or !fileWritable(file) or !hasUnflushedWrites(file)) return;

    var content = try fileString(state, file, field.content);
    const size = logicalSize(file, content);
    const synced: usize = @intCast(@max(fileInteger(file, field.synced) orelse 0, 0));
    const current_generation = fileInteger(file, field.generation) == @as(i64, @bitCast(state.file_generation));
    var written = false;
    if (current_generation and synced <= size) {
        var tail: std.ArrayList(u8) = .empty;
        defer tail.deinit(state.allocator);
        try appendLogicalFrom(state, file, content, synced, &tail);
        if (state.fsWriteFileAt(path, synced, tail.items)) {
            written = true;
        } else |err| switch (err) {
            error.OutOfMemory => return err,
            // Rewrite the whole file through the ordinary path, which also
            // reports any real failure.
            else => {},
        }
    }
    if (!written) {
        content = try fileContent(state, file);
        try state.writeFile(path, content);
    }
    try state.setTableRaw(file, field.synced, .{ .integer = @intCast(size) });
    try setGeneration(state, file);
}

/// Reloads a readable handle's buffered contents after another handle or
/// path operation changed the filesystem. Handles with unflushed writes keep
/// their own bytes, as a C stream keeps its buffer.
pub fn refreshReadable(state: *State, file: *Table) !void {
    if (!fileReadable(file) or isPopenFile(file)) return;
    if (fileInteger(file, field.generation)) |generation| {
        if (generation == @as(i64, @bitCast(state.file_generation))) return;
    }
    const path = try fileString(state, file, field.path);
    if (file.get(field.standard) != .nil or isSpecialDevice(path)) return;
    if (hasUnflushedWrites(file)) return;
    try setGeneration(state, file);
    const contents = state.readFileRaw(path) catch |err| {
        if (err == error.OutOfMemory) return err;
        return;
    };
    defer state.allocator.free(contents);
    // A flushed write run is replaced by the reloaded bytes.
    try state.setTableRaw(file, field.cut, .nil);
    try state.setTableRaw(file, field.chunks, .nil);
    try state.setTableRaw(file, field.blocks, .nil);
    try state.setTableRaw(file, field.content, .{ .string = try state.intern(contents) });
    try state.setTableRaw(file, field.synced, .{ .integer = @intCast(contents.len) });
}

fn setGeneration(state: *State, file: *Table) !void {
    try state.setTableRaw(file, field.generation, .{ .integer = @bitCast(state.file_generation) });
}

pub fn newFile(state: *State, path: []const u8, mode: []const u8, contents: []const u8, parsed: ParsedMode) !Value {
    const value = try state.newTableWithHints(0, 10);
    const file = value.table;
    try setGeneration(state, file);
    try state.setTableRaw(file, field.file, .{ .boolean = true });
    try state.setTableRaw(file, field.path, .{ .string = try state.intern(path) });
    try state.setTableRaw(file, field.mode, .{ .string = try state.intern(mode) });
    try state.setTableRaw(file, field.content, .{ .string = try state.intern(contents) });
    // Opening wrote or read these bytes, so they match the host file.
    try state.setTableRaw(file, field.synced, .{ .integer = @intCast(contents.len) });
    try state.setTableRaw(file, field.pos, .{ .integer = if (parsed.append) @as(i64, @intCast(contents.len + 1)) else 1 });
    try state.setTableRaw(file, field.closed, .{ .boolean = false });
    try state.setTableRaw(file, field.buffer_mode, .{ .string = static_strings.get("full") });
    state.setTableMetatableRaw(file, try state.fileMetatable());
    return value;
}

fn newLinesIterator(state: *State, thread: *Thread, file_value: Value, op: bytecode.Call, first_arg: u16, auto_close: bool) !Value {
    const value = try state.newTableWithHints(0, 4);
    const table = value.table;
    try state.setTableRaw(table, .{ .string = try state.intern("__zlua_lines_iterator") }, .{ .boolean = true });
    try state.setTableRaw(table, .{ .string = try state.intern("file") }, file_value);
    try state.setTableRaw(table, .{ .string = try state.intern("auto_close") }, .{ .boolean = auto_close });
    if (op.arg_count > first_arg) {
        const specs = try state.newTableWithHints(op.arg_count - first_arg, 0);
        var index = first_arg;
        while (index < op.arg_count) : (index += 1) try state.setTableRaw(specs.table, .{ .integer = @intCast(index - first_arg + 1) }, runtime.argValue(state, thread, op, index));
        try state.setTableRaw(table, .{ .string = try state.intern("specs") }, specs);
    }
    return .{ .gmatch_iterator = table };
}

fn expectFile(state: *State, value: Value) !*Table {
    if (!runtime.isFileValue(value)) return state.fail("file expected");
    return value.table;
}

fn expectFileArgument(state: *State, value: Value, function_name: []const u8, index: u16) !*Table {
    if (!runtime.isFileValue(value)) return state.failArgumentType(function_name, index, "FILE*", value);
    return value.table;
}

fn ensureOpen(state: *State, file: *Table) !void {
    const closed = file.get(field.closed);
    if (closed == .boolean and closed.boolean) return state.fail("attempt to use a closed file");
}

fn ensureReadable(state: *State, file: *Table) !void {
    if (!fileReadable(file)) return state.fail("file is not readable");
}

fn isStandardStream(file: *Table, comptime name: []const u8) bool {
    if (file.get(field.standard) == .nil) return false;
    const path = file.get(field.path);
    return path == .string and std.mem.eql(u8, path.string, name);
}

fn fileReadable(file: *Table) bool {
    const mode = file.get(field.mode);
    if (mode != .string or mode.string.len == 0) return false;
    return mode.string[0] == 'r' or std.mem.indexOfScalar(u8, mode.string, '+') != null;
}

fn fileWritable(file: *Table) bool {
    return modeWritable(file.get(field.mode));
}

fn modeWritable(mode: Value) bool {
    if (mode != .string or mode.string.len == 0) return false;
    return mode.string[0] == 'w' or mode.string[0] == 'a' or std.mem.indexOfScalar(u8, mode.string, '+') != null;
}

fn fileString(state: *State, file: *Table, name: Value) ![]const u8 {
    return state.expectString(file.get(name));
}

fn fileInteger(file: *Table, name: Value) ?i64 {
    return runtime.toInteger(file.get(name));
}

/// Zero-based handle position.
fn currentPos(file: *Table) usize {
    return @intCast(@max((fileInteger(file, field.pos) orelse 1) - 1, 0));
}

fn setPos(state: *State, file: *Table, pos: usize) !void {
    try state.setTableRaw(file, field.pos, .{ .integer = @intCast(pos) });
}

pub const ParsedMode = struct {
    kind: u8,
    append: bool,
    reads_existing: bool,
    plus: bool = false,
};

pub fn parseMode(mode: []const u8) ?ParsedMode {
    if (mode.len == 0) return null;
    const kind = mode[0];
    if (kind != 'r' and kind != 'w' and kind != 'a') return null;
    var index: usize = 1;
    const plus = index < mode.len and mode[index] == '+';
    if (plus) index += 1;
    if (index < mode.len and mode[index] == 'b') index += 1;
    if (index != mode.len) return null;
    return .{ .kind = kind, .append = kind == 'a', .reads_existing = kind == 'r', .plus = plus };
}

fn isSpecialDevice(path: []const u8) bool {
    return std.mem.eql(u8, path, "/dev/null") or std.mem.eql(u8, path, "/dev/full");
}

fn tmpPath(state: *State) ![]const u8 {
    const timestamp = state.currentTime() catch 0;
    return std.fmt.allocPrint(state.allocator, "zlua_tmp_{d}_{d}.tmp", .{ timestamp, state.table_allocations.items.len });
}

test "host stdin reader is consumed only as far as each read needs" {
    var reader: std.Io.Reader = .fixed("first\n12 rest\nabcdef\nlast");
    var state = try State.initWithOptions(std.testing.allocator, .{ .stdlib = .full, .stdin_reader = &reader });
    defer state.deinit();
    try state.executeSourceChunk("a = io.read()");
    try std.testing.expectEqualStrings("first", state.getGlobal("a").string);
    try std.testing.expectEqual(@as(usize, 6), reader.seek);
    try state.executeSourceChunk(
        \\b = io.read('n') c = io.read(5) d = io.stdin:read('L')
        \\for line in io.lines() do e = line end
        \\f = io.read('a') g = io.read() _, h, i = io.stdin:seek()
    );
    try std.testing.expectEqual(@as(i64, 12), state.getGlobal("b").integer);
    try std.testing.expectEqualStrings(" rest", state.getGlobal("c").string);
    try std.testing.expectEqualStrings("\n", state.getGlobal("d").string);
    try std.testing.expectEqualStrings("last", state.getGlobal("e").string);
    try std.testing.expectEqualStrings("", state.getGlobal("f").string);
    try std.testing.expect(state.getGlobal("g") == .nil);
    try std.testing.expectEqualStrings("Illegal seek", state.getGlobal("h").string);
    try std.testing.expectEqual(@as(i64, 29), state.getGlobal("i").integer);
}

test "output flush policies follow C stdio buffering" {
    inline for (.{ .{ OutputFlushCase.print, 0, 5 }, .{ OutputFlushCase.line, 3, 5 }, .{ OutputFlushCase.explicit, 0, 0 } }) |case| {
        var buffer: [64]u8 = undefined;
        var sink: std.Io.Writer.Discarding = .init(&buffer);
        var state = try State.initWithOptions(std.testing.allocator, .{ .stdlib = .full, .stdout = &sink.writer, .stdout_flush = case[0], .capture_output = false });
        defer state.deinit();
        try state.executeSourceChunk("io.write('ab\\n')");
        try std.testing.expectEqual(@as(u64, case[1]), sink.count);
        try state.executeSourceChunk("print('x')");
        try std.testing.expectEqual(@as(u64, case[2]), sink.count);
        try std.testing.expectEqual(@as(u64, 5), sink.fullCount());
        try std.testing.expectEqual(@as(usize, 0), state.stdout.items.len);
        try state.executeSourceChunk("io.stdout:write('y') io.flush()");
        try std.testing.expectEqual(@as(u64, 6), sink.count);
    }
}

const OutputFlushCase = runtime.OutputFlush;

test "number scanning matches read_number consumption" {
    const cases = [_]struct { text: []const u8, value: Value, next: usize }{
        .{ .text = "  42 rest", .value = .{ .integer = 42 }, .next = 4 },
        .{ .text = "0x1p4\n", .value = .{ .number = 16 }, .next = 5 },
        .{ .text = "--1", .value = .nil, .next = 1 },
        .{ .text = "0xg", .value = .nil, .next = 2 },
        .{ .text = "   ", .value = .nil, .next = 3 },
    };
    for (cases) |case| {
        const scanned = scanNumber(case.text, 0);
        try std.testing.expectEqual(case.next, scanned.next);
        try std.testing.expect(std.meta.eql(case.value, scanned.value));
    }
}
