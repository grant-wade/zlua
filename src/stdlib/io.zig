const std = @import("std");
const compile = @import("../compile.zig");
const runtime = @import("../runtime.zig");
const host = @import("../runtime/host.zig");
const os_lib = @import("os.zig");

const bytecode = compile.bytecode;
const State = runtime.State;
const Thread = runtime.Thread;
const Value = runtime.Value;

const max_line_args = 250;

pub fn read(state: *State, thread: *Thread, op: bytecode.Call) !void {
    const file = try currentFile(state, "__zlua_input");
    if (runtime.isClosedFileValue(.{ .table = file })) return state.fail(" input file is closed");
    try readFromFile(state, thread, op, file, 0);
}

pub fn write(state: *State, thread: *Thread, op: bytecode.Call) !void {
    const file = try currentFile(state, "__zlua_output");
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

fn setPopenResult(state: *State, file: *runtime.Table, result: host.ProcessResult) !void {
    try state.setTableRaw(file, .{ .string = try state.intern("__zlua_popen_status") }, .{ .string = try state.intern(@tagName(result.status)) });
    try state.setTableRaw(file, .{ .string = try state.intern("__zlua_popen_code") }, .{ .integer = result.code });
}

fn isPopenFile(file: *runtime.Table) bool {
    return file.get(.{ .string = "__zlua_file_popen" }) == .boolean;
}

/// Finishes a popen handle: write mode runs the command with the buffered
/// input now. Returns the command's termination status.
fn finishPopen(state: *State, file: *runtime.Table) !host.ProcessResult {
    if (file.get(.{ .string = "__zlua_popen_status" }) == .nil) {
        const command = try fileString(state, file, "__zlua_file_path");
        const pending_input = try fileString(state, file, "__zlua_file_content");
        const popen_result = try state.popenProcess(command, pending_input);
        state.allocator.free(popen_result.output);
        try setPopenResult(state, file, popen_result.result);
    }
    const status = try fileString(state, file, "__zlua_popen_status");
    return .{
        .status = if (std.mem.eql(u8, status, "signal")) .signal else .exit,
        .code = fileInteger(file, "__zlua_popen_code") orelse 0,
    };
}

pub fn fileTostring(state: *State, thread: *Thread, op: bytecode.Call) !void {
    const value = runtime.argValue(state, thread, op, 0);
    _ = try expectFileArgument(state, value, "file:__tostring", 1);
    try state.returnValues(thread, op.base, op.return_count, &.{.{ .string = try state.valueToString(thread, value) }});
}

pub fn input(state: *State, thread: *Thread, op: bytecode.Call) !void {
    try setCurrentFile(state, thread, op, "__zlua_input", "r");
}

pub fn output(state: *State, thread: *Thread, op: bytecode.Call) !void {
    try setCurrentFile(state, thread, op, "__zlua_output", "w");
}

pub fn close(state: *State, thread: *Thread, op: bytecode.Call) !void {
    const value = if (op.arg_count == 0 or runtime.argValue(state, thread, op, 0) == .nil)
        Value{ .table = try currentFile(state, "__zlua_output") }
    else
        runtime.argValue(state, thread, op, 0);
    try closeFileValue(state, thread, op, value, "io.close", false);
}

pub fn flush(state: *State, thread: *Thread, op: bytecode.Call) !void {
    const file = try currentFile(state, "__zlua_output");
    if (std.mem.eql(u8, try fileString(state, file, "__zlua_file_path"), "/dev/full")) {
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
        break :blk Value{ .table = try currentFile(state, "__zlua_input") };
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
    try state.returnValues(thread, op.base, op.return_count, &.{try newFile(state, path, "w+", "", parsed)});
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
    try refreshReadable(state, file);
    const whence = if (op.arg_count >= 2 and runtime.argValue(state, thread, op, 1) != .nil)
        try state.expectArgumentString(thread, op, "file:seek", 1)
    else
        "cur";
    const offset = if (op.arg_count >= 3 and runtime.argValue(state, thread, op, 2) != .nil)
        try state.argumentInteger(thread, op, "file:seek", 2)
    else
        0;
    const content = try fileString(state, file, "__zlua_file_content");
    const base: i64 = if (std.mem.eql(u8, whence, "set"))
        0
    else if (std.mem.eql(u8, whence, "cur"))
        (fileInteger(file, "__zlua_file_pos") orelse 1) - 1
    else if (std.mem.eql(u8, whence, "end"))
        @intCast(content.len)
    else
        return state.failArgumentMessage("file:seek", 2, "invalid whence");
    const new_pos = base + offset;
    if (new_pos < 0) {
        try state.returnValues(thread, op.base, op.return_count, &.{ .nil, .{ .string = try state.intern("invalid argument") }, .{ .integer = 22 } });
        return;
    }
    try state.setTableRaw(file, .{ .string = try state.intern("__zlua_file_pos") }, .{ .integer = new_pos + 1 });
    try state.returnValues(thread, op.base, op.return_count, &.{.{ .integer = new_pos }});
}

pub fn fileFlush(state: *State, thread: *Thread, op: bytecode.Call) !void {
    const file = try expectFileArgument(state, runtime.argValue(state, thread, op, 0), "file:flush", 1);
    try ensureOpen(state, file);
    if (std.mem.eql(u8, try fileString(state, file, "__zlua_file_path"), "/dev/full")) {
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
    try state.setTableRaw(file, .{ .string = try state.intern("__zlua_file_buffer_mode") }, .{ .string = try state.intern(mode) });
    if (std.mem.eql(u8, mode, "no")) try flushFile(state, file);
    try state.returnValues(thread, op.base, op.return_count, &.{.{ .boolean = true }});
}

pub fn linesIter(state: *State, thread: *Thread, op: bytecode.Call) !void {
    const values = try linesNext(state, runtime.argValue(state, thread, op, 0));
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

fn setCurrentFile(state: *State, thread: *Thread, op: bytecode.Call, key: []const u8, mode: []const u8) !void {
    const io_table = try state.expectTable(state.getGlobal("io"));
    if (op.arg_count == 0 or runtime.argValue(state, thread, op, 0) == .nil) {
        try state.returnValues(thread, op.base, op.return_count, &.{io_table.get(.{ .string = key })});
        return;
    }
    var value = runtime.argValue(state, thread, op, 0);
    if (value == .string) {
        value = try openCheckedFile(state, value.string, mode);
    } else {
        _ = try expectFileArgument(state, value, if (std.mem.eql(u8, key, "__zlua_output")) "io.output" else "io.input", 1);
    }
    if (std.mem.eql(u8, key, "__zlua_output")) {
        const old_value = io_table.get(.{ .string = key });
        switch (old_value) {
            .table => |old_file| if (old_file.get(.{ .string = "__zlua_file_standard" }) == .nil and !runtime.isClosedFileValue(old_value)) try closeFile(state, old_file, false),
            else => {},
        }
    }
    try state.setTableRaw(io_table, .{ .string = try state.intern(key) }, value);
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
fn markDirectoryHandle(state: *State, file: *runtime.Table) !void {
    try state.setTableRaw(file, .{ .string = try state.intern("__zlua_file_read_error") }, .{ .boolean = true });
}

fn readError(file: *runtime.Table) ?host.FileError {
    if (file.get(.{ .string = "__zlua_file_read_error" }) == .nil) return null;
    return host.fileError(error.IsDir);
}

/// Reads the rest of standard input for `dofile()` and `loadfile()`, sharing
/// the `io.stdin` position when the io library is open. The caller owns the bytes.
pub fn readAllStdin(state: *State) ![]u8 {
    const io_value = state.getGlobal("io");
    if (io_value == .table) {
        const stdin = io_value.table.get(.{ .string = "stdin" });
        if (runtime.isFileValue(stdin) and !runtime.isClosedFileValue(stdin)) {
            const value = try readOne(state, stdin.table, .{ .string = "a" });
            return state.allocator.dupe(u8, if (value == .string) value.string else "");
        }
    }
    const value = try state.readStdin("a");
    return state.allocator.dupe(u8, if (value == .string) value.string else "");
}

/// Reads one line, including its newline, from standard input; null at end of input.
pub fn readStdinLine(state: *State) !?[]const u8 {
    const io_value = state.getGlobal("io");
    const value = if (io_value == .table and runtime.isFileValue(io_value.table.get(.{ .string = "stdin" })) and !runtime.isClosedFileValue(io_value.table.get(.{ .string = "stdin" })))
        try readOne(state, io_value.table.get(.{ .string = "stdin" }).table, .{ .string = "L" })
    else
        try state.readStdin("l");
    return if (value == .string) value.string else null;
}

fn currentFile(state: *State, key: []const u8) !*runtime.Table {
    const io_table = try state.expectTable(state.getGlobal("io"));
    return expectFile(state, io_table.get(.{ .string = key }));
}

fn readFromFile(state: *State, thread: *Thread, op: bytecode.Call, file: *runtime.Table, first_arg: u16) !void {
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

fn readOne(state: *State, file: *runtime.Table, spec_value: Value) !Value {
    try ensureOpen(state, file);
    try ensureReadable(state, file);
    if (readError(file)) |info| return state.fail(info.message);
    try refreshReadable(state, file);
    const content = try fileString(state, file, "__zlua_file_content");
    var pos = fileInteger(file, "__zlua_file_pos") orelse 1;
    if (pos < 1) pos = 1;
    const start: usize = @intCast(@min(@as(i64, @intCast(content.len)), pos - 1));

    if (runtime.toInteger(spec_value)) |count_i64| {
        if (count_i64 < 0) return state.fail("invalid format");
        const count: usize = @intCast(count_i64);
        if (count == 0) return if (start < content.len) .{ .string = try state.intern("") } else .nil;
        if (start >= content.len) return .nil;
        const end = @min(content.len, start + count);
        try setPos(state, file, end + 1);
        return .{ .string = try state.intern(content[start..end]) };
    }

    var spec = try state.expectString(spec_value);
    if (spec.len != 0 and spec[0] == '*') spec = spec[1..];
    if (std.mem.eql(u8, spec, "a") or std.mem.eql(u8, spec, "all")) {
        try setPos(state, file, content.len + 1);
        return .{ .string = try state.intern(content[start..]) };
    }
    if (std.mem.eql(u8, spec, "l") or std.mem.eql(u8, spec, "L")) {
        if (start >= content.len) return .nil;
        var end = start;
        while (end < content.len and content[end] != '\n') end += 1;
        const include_newline = std.mem.eql(u8, spec, "L") and end < content.len;
        const slice_end = if (include_newline) end + 1 else end;
        try setPos(state, file, if (end < content.len) end + 2 else end + 1);
        return .{ .string = try state.intern(content[start..slice_end]) };
    }
    if (std.mem.eql(u8, spec, "n")) return readNumber(state, file, content, start);
    return state.fail("invalid format");
}

fn readNumber(state: *State, file: *runtime.Table, content: []const u8, start: usize) !Value {
    var pos = start;
    while (pos < content.len and std.ascii.isWhitespace(content[pos])) pos += 1;
    if (pos >= content.len) {
        try setPos(state, file, pos + 1);
        return .nil;
    }
    var token_end = pos;
    while (token_end < content.len and isNumberTokenByte(content[token_end])) token_end += 1;
    if (token_end - pos > 350) {
        try setPos(state, file, @min(token_end, pos + 4) + 1);
        return .nil;
    }
    if (invalidHexPrefix(content[pos..token_end])) {
        try setPos(state, file, pos + 3);
        return .nil;
    }
    if (invalidBareExponentToken(content[pos..token_end])) {
        try setPos(state, file, token_end + 1);
        return .nil;
    }
    const scan_end = @min(token_end, pos + 512);
    var end = scan_end;
    while (end > pos) : (end -= 1) {
        const slice = content[pos..end];
        if (runtime.parseIntegerStrict(slice)) |integer| {
            try setPos(state, file, end + 1);
            return .{ .integer = integer };
        }
        if (runtime.parseLuaNumber(slice)) |number| {
            try setPos(state, file, end + 1);
            return .{ .number = number };
        } else |_| {}
    }
    const consume = failedNumberPrefix(content[pos..]);
    try setPos(state, file, pos + consume + 1);
    return .nil;
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

fn writeToFile(state: *State, thread: *Thread, op: bytecode.Call, file: *runtime.Table, first_arg: u16, function_name: []const u8) !void {
    try ensureOpen(state, file);
    if (!fileWritable(file)) {
        try state.returnValues(thread, op.base, op.return_count, &.{ .nil, .{ .string = try state.intern("file is not writable") }, .{ .integer = 9 } });
        return;
    }
    var wrote_newline = false;
    var index = first_arg;
    while (index < op.arg_count) : (index += 1) {
        const value = runtime.argValue(state, thread, op, index);
        switch (value) {
            .string, .integer, .number => {},
            else => return state.failArgumentType(function_name, index + 1 - first_arg, "string", value),
        }
        var bytes = std.ArrayList(u8).empty;
        defer bytes.deinit(state.allocator);
        try runtime.appendLuaString(state.allocator, &bytes, value);
        if (std.mem.indexOfScalar(u8, bytes.items, '\n') != null) wrote_newline = true;
        try writeBytes(state, file, bytes.items);
    }
    const buffer_mode = try fileString(state, file, "__zlua_file_buffer_mode");
    if (std.mem.eql(u8, buffer_mode, "no") or (std.mem.eql(u8, buffer_mode, "line") and wrote_newline)) try flushFile(state, file);
    try state.returnValues(thread, op.base, op.return_count, &.{.{ .table = file }});
}

fn writeBytes(state: *State, file: *runtime.Table, bytes: []const u8) !void {
    const path = try fileString(state, file, "__zlua_file_path");
    if (!isPopenFile(file)) {
        if (std.mem.eql(u8, path, "stdout")) {
            try state.writeStdout(bytes);
            return;
        }
        if (std.mem.eql(u8, path, "stderr")) {
            try state.writeStderr(bytes);
            return;
        }
        if (std.mem.eql(u8, path, "/dev/null") or std.mem.eql(u8, path, "/dev/full")) return;
    }
    var content = std.ArrayList(u8).empty;
    defer content.deinit(state.allocator);
    try content.appendSlice(state.allocator, try fileString(state, file, "__zlua_file_content"));
    const mode = try fileString(state, file, "__zlua_file_mode");
    const pos: usize = if (std.mem.indexOfScalar(u8, mode, 'a') != null)
        content.items.len
    else
        @intCast(@max((fileInteger(file, "__zlua_file_pos") orelse 1) - 1, 0));
    if (pos > content.items.len) {
        const old_len = content.items.len;
        try content.resize(state.allocator, pos);
        @memset(content.items[old_len..], 0);
    }
    const end = pos + bytes.len;
    if (end > content.items.len) try content.resize(state.allocator, end);
    @memcpy(content.items[pos..end], bytes);
    try state.setTableRaw(file, .{ .string = try state.intern("__zlua_file_content") }, .{ .string = try state.intern(content.items) });
    try setPos(state, file, end + 1);
}

fn closeFileValue(state: *State, thread: *Thread, op: bytecode.Call, value: Value, function_name: []const u8, from_iterator: bool) !void {
    const file = try expectFileArgument(state, value, function_name, 1);
    if (runtime.isClosedFileValue(value)) {
        if (from_iterator) return;
        return state.fail("attempt to use a closed file");
    }
    if (file.get(.{ .string = "__zlua_file_standard" }) == .boolean and file.get(.{ .string = "__zlua_file_standard" }).boolean) {
        try state.returnValues(thread, op.base, op.return_count, &.{.nil});
        return;
    }
    if (isPopenFile(file)) {
        const result = try finishPopen(state, file);
        try state.setTableRaw(file, .{ .string = try state.intern("__zlua_file_closed") }, .{ .boolean = true });
        if (!from_iterator) try os_lib.returnProcessResult(state, thread, op, result);
        return;
    }
    try closeFile(state, file, from_iterator);
    if (!from_iterator) try state.returnValues(thread, op.base, op.return_count, &.{.{ .boolean = true }});
}

fn closeFile(state: *State, file: *runtime.Table, from_iterator: bool) !void {
    _ = from_iterator;
    if (isPopenFile(file)) {
        _ = try finishPopen(state, file);
    } else if (fileWritable(file)) try flushFile(state, file);
    try state.setTableRaw(file, .{ .string = try state.intern("__zlua_file_closed") }, .{ .boolean = true });
}

fn flushFile(state: *State, file: *runtime.Table) !void {
    if (isPopenFile(file)) return;
    const path = try fileString(state, file, "__zlua_file_path");
    if (std.mem.eql(u8, path, "stdout")) return state.flushStdout();
    if (std.mem.eql(u8, path, "stderr")) return state.flushStderr();
    if (std.mem.eql(u8, path, "/dev/null") or std.mem.eql(u8, path, "/dev/full")) return;
    if (fileWritable(file)) {
        try state.writeFile(path, try fileString(state, file, "__zlua_file_content"));
        try setGeneration(state, file);
    }
}

/// Reloads a readable handle's buffered contents after another handle or
/// path operation changed the filesystem.
pub fn refreshReadable(state: *State, file: *runtime.Table) !void {
    if (!fileReadable(file) or isPopenFile(file)) return;
    if (fileInteger(file, "__zlua_file_generation")) |generation| {
        if (generation == @as(i64, @bitCast(state.file_generation))) return;
    }
    const path = try fileString(state, file, "__zlua_file_path");
    if (std.mem.eql(u8, path, "stdin") or std.mem.eql(u8, path, "stdout") or std.mem.eql(u8, path, "stderr") or isSpecialDevice(path)) return;
    try setGeneration(state, file);
    const contents = state.readFileRaw(path) catch |err| {
        if (err == error.OutOfMemory) return err;
        return;
    };
    defer state.allocator.free(contents);
    try state.setTableRaw(file, .{ .string = try state.intern("__zlua_file_content") }, .{ .string = try state.intern(contents) });
}

fn setGeneration(state: *State, file: *runtime.Table) !void {
    try state.setTableRaw(file, .{ .string = try state.intern("__zlua_file_generation") }, .{ .integer = @bitCast(state.file_generation) });
}

pub fn newFile(state: *State, path: []const u8, mode: []const u8, contents: []const u8, parsed: ParsedMode) !Value {
    const value = try state.newTableWithHints(0, 8);
    const file = value.table;
    try setGeneration(state, file);
    try state.setTableRaw(file, .{ .string = try state.intern("__zlua_file") }, .{ .boolean = true });
    try state.setTableRaw(file, .{ .string = try state.intern("__zlua_file_path") }, .{ .string = try state.intern(path) });
    try state.setTableRaw(file, .{ .string = try state.intern("__zlua_file_mode") }, .{ .string = try state.intern(mode) });
    try state.setTableRaw(file, .{ .string = try state.intern("__zlua_file_content") }, .{ .string = try state.intern(contents) });
    try state.setTableRaw(file, .{ .string = try state.intern("__zlua_file_pos") }, .{ .integer = if (parsed.append) @as(i64, @intCast(contents.len + 1)) else 1 });
    try state.setTableRaw(file, .{ .string = try state.intern("__zlua_file_closed") }, .{ .boolean = false });
    try state.setTableRaw(file, .{ .string = try state.intern("__zlua_file_buffer_mode") }, .{ .string = try state.intern("full") });
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

fn expectFile(state: *State, value: Value) !*runtime.Table {
    if (!runtime.isFileValue(value)) return state.fail("file expected");
    return value.table;
}

fn expectFileArgument(state: *State, value: Value, function_name: []const u8, index: u16) !*runtime.Table {
    if (!runtime.isFileValue(value)) return state.failArgumentType(function_name, index, "FILE*", value);
    return value.table;
}

fn ensureOpen(state: *State, file: *runtime.Table) !void {
    const closed = file.get(.{ .string = "__zlua_file_closed" });
    if (closed == .boolean and closed.boolean) return state.fail("attempt to use a closed file");
}

fn ensureReadable(state: *State, file: *runtime.Table) !void {
    if (!fileReadable(file)) return state.fail("file is not readable");
}

fn fileReadable(file: *runtime.Table) bool {
    const mode = file.get(.{ .string = "__zlua_file_mode" });
    if (mode != .string or mode.string.len == 0) return false;
    return mode.string[0] == 'r' or std.mem.indexOfScalar(u8, mode.string, '+') != null;
}

fn fileWritable(file: *runtime.Table) bool {
    const mode = file.get(.{ .string = "__zlua_file_mode" });
    if (mode != .string or mode.string.len == 0) return false;
    return mode.string[0] == 'w' or mode.string[0] == 'a' or std.mem.indexOfScalar(u8, mode.string, '+') != null;
}

fn fileString(state: *State, file: *runtime.Table, name: []const u8) ![]const u8 {
    return state.expectString(file.get(.{ .string = name }));
}

fn fileInteger(file: *runtime.Table, comptime name: []const u8) ?i64 {
    return runtime.toInteger(file.get(.{ .string = name }));
}

fn setPos(state: *State, file: *runtime.Table, pos: usize) !void {
    try state.setTableRaw(file, .{ .string = try state.intern("__zlua_file_pos") }, .{ .integer = @intCast(pos) });
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
