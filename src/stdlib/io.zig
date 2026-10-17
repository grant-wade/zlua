const std = @import("std");
const builtin = @import("builtin");
const compile = @import("../compile.zig");
const runtime = @import("../runtime.zig");
const host = @import("../runtime/host.zig");
const rollback = @import("../runtime/rollback.zig");
const static_strings = @import("static_strings.zig");
const os_lib = @import("os.zig");
const entry_mod = @import("../runtime/entry.zig");
const io_mod = @import("../runtime/io.zig");
const metatable_mod = @import("../runtime/metatable.zig");
const system_mod = @import("../runtime/system.zig");

const bytecode = compile.bytecode;
const State = runtime.State;
const Thread = runtime.Thread;
const Value = runtime.Value;
const Table = runtime.Table;
const Userdata = runtime.Userdata;

const max_line_args = 250;

/// Payload of every `FILE*` userdata; buffers the whole file. Mutate only
/// through `writable` so rollback can copy it before the first change.
pub const File = struct {
    kind: Kind,
    /// Owned file path or popen command; empty otherwise.
    path: []const u8 = "",
    readable: bool,
    writable: bool,
    append: bool = false,
    closed: bool = false,
    buffer_mode: BufferMode = .full,
    /// C `fopen` succeeds on directories; reads then fail.
    is_directory: bool = false,
    device_pending: bool = false,
    content: std.ArrayList(u8) = .empty,
    pos: usize = 0,
    /// Prefix of `content` known to match the host file.
    synced: usize = 0,
    /// `State.file_generation` when the handle last matched the filesystem.
    generation: u64 = 0,
    popen_result: ?host.ProcessResult = null,
    /// Creation order on the scale of `Table.finalizer_order`.
    finalizer_order: u64 = 0,

    pub const Kind = enum {
        stdin,
        stdout,
        stderr,
        regular,
        popen,
        null_device,
        /// Linux and FreeBSD `/dev/full`: endless zero reads; flushing fails with `ENOSPC`.
        full_device,
        /// `io.tmpfile`: memory only.
        anonymous,
    };

    pub const BufferMode = enum { no, full, line };

    fn isStandard(self: *const File) bool {
        return switch (self.kind) {
            .stdin, .stdout, .stderr => true,
            else => false,
        };
    }

    fn hasUnflushedWrites(self: *const File) bool {
        return self.synced < self.content.items.len;
    }

    fn deinit(self: *File, allocator: std.mem.Allocator) void {
        self.content.deinit(allocator);
        if (self.path.len != 0) allocator.free(self.path);
    }
};

const Handle = struct {
    userdata: *Userdata,
    file: *File,

    fn value(self: Handle) Value {
        return .{ .userdata = self.userdata };
    }

    fn noteSize(self: Handle, state: *State) void {
        const payload = self.userdata.payload orelse return;
        const bytes = managedBytes(self.file);
        if (bytes > payload.managed_bytes) state.gc.noteAllocation(bytes - payload.managed_bytes) else state.gc.noteAllocationFreed(payload.managed_bytes - bytes);
        payload.managed_bytes = bytes;
    }
};

var file_type_token: u8 = 0;

pub fn fileTypeId() usize {
    return @intFromPtr(&file_type_token);
}

/// Read-only view of a handle's file; null for other values.
pub fn fileOf(value: Value) ?*const File {
    if (value != .userdata) return null;
    return fileOfUserdata(value.userdata);
}

fn fileOfUserdata(userdata: *Userdata) ?*const File {
    if (userdata.type_id != fileTypeId()) return null;
    return @ptrCast(@alignCast(userdata.ptr));
}

fn writable(userdata: *Userdata) !Handle {
    try rollback.userdataWritable(userdata);
    return .{ .userdata = userdata, .file = @ptrCast(@alignCast(userdata.ptr)) };
}

fn managedBytes(file: *const File) usize {
    return @sizeOf(File) + file.content.capacity + file.path.len;
}

fn fileFinalizer(_: *anyopaque, _: ?*const anyopaque) void {}

fn disposeFile(allocator: std.mem.Allocator, ptr: *anyopaque) void {
    const file: *File = @ptrCast(@alignCast(ptr));
    file.deinit(allocator);
    allocator.destroy(file);
}

fn copyFile(allocator: std.mem.Allocator, ptr: *const anyopaque) anyerror!*anyopaque {
    const source: *const File = @ptrCast(@alignCast(ptr));
    const copy = try allocator.create(File);
    errdefer allocator.destroy(copy);
    copy.* = source.*;
    copy.path = "";
    copy.content = .empty;
    errdefer copy.deinit(allocator);
    if (source.path.len != 0) copy.path = try allocator.dupe(u8, source.path);
    copy.content = try .initCapacity(allocator, source.content.items.len);
    copy.content.appendSliceAssumeCapacity(source.content.items);
    return copy;
}

fn ownedBuffer(bytes: []const u8) std.ArrayList(u8) {
    if (bytes.len == 0) return .empty;
    return .fromOwnedSlice(@constCast(bytes));
}

pub const FileOptions = struct {
    kind: File.Kind = .regular,
    path: []const u8 = "",
    mode: ParsedMode,
    /// Allocated by the state allocator; `newFile` takes ownership even on failure.
    contents: []const u8 = "",
    buffer_mode: File.BufferMode = .full,
    is_directory: bool = false,
    popen_result: ?host.ProcessResult = null,
    fs_methods: bool = false,
};

pub fn newFile(state: *State, options: FileOptions) !Value {
    var content = ownedBuffer(options.contents);
    errdefer content.deinit(state.allocator);
    const metatable = if (options.fs_methods) try state.fsFileMetatable() else try state.fileMetatable();
    const file = try state.allocator.create(File);
    errdefer state.allocator.destroy(file);
    const path = if (options.path.len == 0) "" else try state.allocator.dupe(u8, options.path);
    errdefer if (path.len != 0) state.allocator.free(path);
    file.* = .{
        .kind = options.kind,
        .path = path,
        .readable = options.mode.readable(),
        .writable = options.mode.writable(),
        .append = options.mode.append,
        .buffer_mode = options.buffer_mode,
        .is_directory = options.is_directory,
        .content = content,
        .synced = content.items.len,
        .pos = if (options.mode.opensAtEnd()) content.items.len else 0,
        .generation = state.file_generation,
        .popen_result = options.popen_result,
        .finalizer_order = metatable_mod.nextFinalizerOrder(state),
    };
    const value = try state.newUserdata(file, fileTypeId(), static_strings.get("FILE*"), fileFinalizer, null, disposeFile);
    const userdata = value.userdata;
    const payload = userdata.payload.?;
    payload.snapshot_copy = copyFile;
    payload.snapshot_dispose = disposeFile;
    payload.snapshot_tracking = .scoped;
    payload.is_snapshot_copy = true;
    userdata.metatable = metatable;
    state.gc.writeBarrier(userdata, .{ .table = metatable });
    (Handle{ .userdata = userdata, .file = file }).noteSize(state);
    return value;
}

/// Collector finalizer: flushes and closes an open handle, ignoring failures like PUC's `__gc`.
pub fn finalizeFile(state: *State, userdata: *Userdata) void {
    const handle = writable(userdata) catch return;
    if (handle.file.closed or handle.file.isStandard()) return;
    closeQuietly(state, handle) catch {};
}

/// The finalization order of an open handle `State.deinit` must close, or null.
pub fn closeFinalizerOrder(userdata: *Userdata) ?u64 {
    const file = fileOfUserdata(userdata) orelse return null;
    if (file.closed or file.isStandard() or userdata.finalized) return null;
    return file.finalizer_order;
}

pub fn hasOpenFiles(state: *State) bool {
    for (state.userdata_allocations.items) |userdata| {
        if (closeFinalizerOrder(userdata) != null) return true;
    }
    return false;
}

/// Flushes and closes every open handle, newest first, like `lua_close` running their `__gc`.
pub fn closeOpenFiles(state: *State) void {
    var index = state.userdata_allocations.items.len;
    while (index > 0) {
        index -= 1;
        const userdata = state.userdata_allocations.items[index];
        const file = fileOfUserdata(userdata) orelse continue;
        if (file.closed or file.isStandard()) continue;
        finalizeFile(state, userdata);
    }
}

fn closeQuietly(state: *State, handle: Handle) !void {
    const saved_error = state.last_error;
    const saved_handled = state.error_handled;
    defer {
        state.last_error = saved_error;
        state.error_handled = saved_handled;
    }
    defer if (!handle.file.closed) markClosed(state, handle);
    _ = closeFile(state, handle) catch |err| switch (err) {
        error.RuntimeError => null,
        else => return err,
    };
}

pub fn read(state: *State, thread: *Thread, op: bytecode.Call) !void {
    const handle = try writable(try defaultFile(state, .input));
    try readFromFile(state, thread, op, handle, 0);
}

pub fn write(state: *State, thread: *Thread, op: bytecode.Call) !void {
    const handle = try writable(try defaultFile(state, .output));
    try writeToFile(state, thread, op, handle, 0, "io.write");
}

pub fn open(state: *State, thread: *Thread, op: bytecode.Call) !void {
    const path = try state.expectArgumentString(thread, op, "io.open", 0);
    const mode = if (op.arg_count >= 2 and runtime.argValue(state, thread, op, 1) != .nil)
        try state.expectArgumentString(thread, op, "io.open", 1)
    else
        "r";
    const parsed = parseMode(mode) orelse return state.failArgumentMessage("io.open", 2, "invalid mode");

    if (specialDevice(path)) |kind| return returnFile(state, thread, op, try newFile(state, .{ .kind = kind, .path = path, .mode = parsed }));

    var contents: []const u8 = "";
    var found = true;
    if (parsed.reads_existing or parsed.append) {
        contents = io_mod.readFileRaw(state, path) catch |err| switch (err) {
            error.OutOfMemory => return err,
            error.FileNotFound => if (parsed.kind == 'r') return os_lib.fileFailure(state, thread, op, path, err) else blk: {
                found = false;
                break :blk "";
            },
            error.IsDir => if (parsed.kind == 'r' and !parsed.plus)
                return returnFile(state, thread, op, try newFile(state, .{ .path = path, .mode = parsed, .is_directory = true }))
            else
                return os_lib.fileFailure(state, thread, op, path, err),
            else => return os_lib.fileFailure(state, thread, op, path, err),
        };
    }
    prepareWrite(state, path, parsed, found) catch |err| {
        state.allocator.free(contents);
        return os_lib.fileFailure(state, thread, op, path, err);
    };
    try returnFile(state, thread, op, try newFile(state, .{ .path = path, .mode = parsed, .contents = contents }));
}

/// Like `fopen`: "w" truncates; "a" creates the file or checks it is writable
/// without rewriting it, so concurrent appends by other writers survive.
pub fn prepareWrite(state: *State, path: []const u8, parsed: ParsedMode, exists: bool) anyerror!void {
    switch (parsed.kind) {
        'w' => try io_mod.fsWriteFile(state, path, ""),
        'a' => if (exists)
            try io_mod.fsCheckWritable(state, path)
        else
            io_mod.fsCreateFileExclusive(state, path) catch |err| if (err != error.PathAlreadyExists) return err,
        else => {},
    }
}

fn returnFile(state: *State, thread: *Thread, op: bytecode.Call, file: Value) !void {
    try state.returnValues(thread, op.base, op.return_count, &.{file});
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
        const popen_result = try system_mod.popenProcess(state, command, null);
        command_output = popen_result.output;
        result = popen_result.result;
    } else if (!system_mod.processEnabled(state)) {
        return state.fail("'popen' not supported");
    } else switch (state.options.process) {
        .custom => |process| if (process.popen == null) return state.fail("'popen' not supported"),
        else => {},
    }
    try returnFile(state, thread, op, try newFile(state, .{ .kind = .popen, .path = command, .mode = parsed, .contents = command_output, .popen_result = result }));
}

fn finishPopen(state: *State, file: *File) !host.ProcessResult {
    if (file.popen_result == null) {
        const popen_result = try system_mod.popenProcess(state, file.path, file.content.items);
        state.allocator.free(popen_result.output);
        file.popen_result = popen_result.result;
    }
    return file.popen_result.?;
}

pub fn fileTostring(state: *State, thread: *Thread, op: bytecode.Call) !void {
    const userdata = try expectFileArgument(state, runtime.argValue(state, thread, op, 0), "file:__tostring", 1);
    const name = if (fileOfUserdata(userdata).?.closed) try state.strings.intern("file (closed)") else name: {
        var buffer: [32]u8 = undefined;
        break :name try state.strings.intern(std.fmt.bufPrint(&buffer, "file (0x{x})", .{@intFromPtr(userdata)}) catch unreachable);
    };
    try state.returnValues(thread, op.base, op.return_count, &.{.{ .string = name }});
}

pub fn input(state: *State, thread: *Thread, op: bytecode.Call) !void {
    try setCurrentFile(state, thread, op, .input);
}

pub fn output(state: *State, thread: *Thread, op: bytecode.Call) !void {
    try setCurrentFile(state, thread, op, .output);
}

pub fn close(state: *State, thread: *Thread, op: bytecode.Call) !void {
    const value = if (op.arg_count == 0)
        Value{ .userdata = try currentFile(state, .output) }
    else
        runtime.argValue(state, thread, op, 0);
    try closeFileValue(state, thread, op, value, "io.close");
}

pub fn flush(state: *State, thread: *Thread, op: bytecode.Call) !void {
    const handle = try writable(try defaultFile(state, .output));
    try returnResult(state, thread, op, try flushReport(state, handle.file), .{ .boolean = true });
}

fn returnResult(state: *State, thread: *Thread, op: bytecode.Call, failure: ?host.FileError, success: Value) !void {
    const info = failure orelse return state.returnValues(thread, op.base, op.return_count, &.{success});
    try state.returnValues(thread, op.base, op.return_count, &.{ .nil, .{ .string = try state.strings.intern(info.message) }, .{ .integer = info.errno } });
}

pub fn lines(state: *State, thread: *Thread, op: bytecode.Call) !void {
    if (op.arg_count > max_line_args + 1) return state.fail("too many arguments");
    const from_path = op.arg_count >= 1 and runtime.argValue(state, thread, op, 0) != .nil;
    const file_value = if (from_path) blk: {
        const path = try state.expectArgumentString(thread, op, "io.lines", 0);
        break :blk try openCheckedFile(state, path, "r");
    } else blk: {
        const userdata = try currentFile(state, .input);
        try ensureOpen(state, fileOfUserdata(userdata).?);
        break :blk Value{ .userdata = userdata };
    };
    const first_format: u16 = if (op.arg_count >= 1) 1 else 0;
    const iterator = try newLinesIterator(state, thread, file_value, op, first_format, from_path);
    if (from_path) {
        try state.returnValues(thread, op.base, op.return_count, &.{ iterator, .nil, .nil, file_value });
    } else {
        try state.returnValues(thread, op.base, op.return_count, &.{iterator});
    }
}

pub fn tmpfile(state: *State, thread: *Thread, op: bytecode.Call) !void {
    try returnFile(state, thread, op, try newFile(state, .{ .kind = .anonymous, .mode = parseMode("w+b").? }));
}

pub fn typeValue(state: *State, thread: *Thread, op: bytecode.Call) !void {
    if (op.arg_count == 0) return state.failArgumentMessage("io.type", 1, "value expected");
    const userdata = checkedFile(state, runtime.argValue(state, thread, op, 0)) orelse {
        try state.returnValues(thread, op.base, op.return_count, &.{.nil});
        return;
    };
    const file = fileOfUserdata(userdata).?;
    const name = if (file.closed) "closed file" else "file";
    try state.returnValues(thread, op.base, op.return_count, &.{.{ .string = try state.strings.intern(name) }});
}

pub fn fileRead(state: *State, thread: *Thread, op: bytecode.Call) !void {
    const handle = try writable(try expectFileArgument(state, runtime.argValue(state, thread, op, 0), "file:read", 1));
    try readFromFile(state, thread, op, handle, 1);
}

pub fn fileWrite(state: *State, thread: *Thread, op: bytecode.Call) !void {
    const handle = try writable(try expectFileArgument(state, runtime.argValue(state, thread, op, 0), "file:write", 1));
    try writeToFile(state, thread, op, handle, 1, "file:write");
}

pub fn fileClose(state: *State, thread: *Thread, op: bytecode.Call) !void {
    if (op.arg_count == 0) return state.failArgumentMessage("file:close", 1, "FILE* expected, got no value");
    try closeFileValue(state, thread, op, runtime.argValue(state, thread, op, 0), "file:close");
}

/// `__gc` and `__close`, like PUC's `f_gc`.
pub fn fileGc(state: *State, thread: *Thread, op: bytecode.Call) !void {
    const handle = try writable(try expectFileArgument(state, runtime.argValue(state, thread, op, 0), "file:__gc", 1));
    if (!handle.file.closed and !handle.file.isStandard()) try closeQuietly(state, handle);
    try state.returnValues(thread, op.base, op.return_count, &.{});
}

pub fn fileSeek(state: *State, thread: *Thread, op: bytecode.Call) !void {
    const handle = try writable(try expectFileArgument(state, runtime.argValue(state, thread, op, 0), "file:seek", 1));
    const file = handle.file;
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

    if (file.kind == .stdin) {
        if (io_mod.stdinIsStream(state)) {
            try state.returnValues(thread, op.base, op.return_count, &.{ .nil, .{ .string = try state.strings.intern("Illegal seek") }, .{ .integer = 29 } });
            return;
        }
        const base: usize = switch (kind) {
            .set => 0,
            .cur => state.stdin_pos,
            .end => state.options.stdin.len,
        };
        const new_pos = seekPosition(base, offset) catch |err| return returnResult(state, thread, op, host.fileError(err), .nil);
        state.stdin_pos = new_pos;
        try state.returnValues(thread, op.base, op.return_count, &.{.{ .integer = @intCast(new_pos) }});
        return;
    }

    if (file.hasUnflushedWrites()) {
        if (try flushReport(state, file)) |failure| return returnResult(state, thread, op, failure, .nil);
    }
    try refreshReadable(state, handle);
    const base: usize = switch (kind) {
        .set => 0,
        .cur => file.pos,
        .end => file.content.items.len,
    };
    const new_pos = seekPosition(base, offset) catch |err| return returnResult(state, thread, op, host.fileError(err), .nil);
    file.pos = new_pos;
    try state.returnValues(thread, op.base, op.return_count, &.{.{ .integer = @intCast(new_pos) }});
}

fn seekPosition(base: usize, offset: i64) error{ InvalidArgument, ValueTooLarge }!usize {
    const start = std.math.cast(i64, base) orelse return error.ValueTooLarge;
    const target = std.math.add(i64, start, offset) catch return error.ValueTooLarge;
    if (target < 0) return error.InvalidArgument;
    return std.math.cast(usize, target) orelse error.ValueTooLarge;
}

pub fn fileFlush(state: *State, thread: *Thread, op: bytecode.Call) !void {
    const handle = try writable(try expectFileArgument(state, runtime.argValue(state, thread, op, 0), "file:flush", 1));
    try ensureOpen(state, handle.file);
    try returnResult(state, thread, op, try flushReport(state, handle.file), .{ .boolean = true });
}

pub fn fileLines(state: *State, thread: *Thread, op: bytecode.Call) !void {
    const file_value = runtime.argValue(state, thread, op, 0);
    const userdata = try expectFileArgument(state, file_value, "file:lines", 1);
    try ensureOpen(state, fileOfUserdata(userdata).?);
    if (op.arg_count > max_line_args + 1) return state.fail("too many arguments");
    const iterator = try newLinesIterator(state, thread, file_value, op, 1, false);
    try state.returnValues(thread, op.base, op.return_count, &.{iterator});
}

pub fn fileSetvbuf(state: *State, thread: *Thread, op: bytecode.Call) !void {
    const handle = try writable(try expectFileArgument(state, runtime.argValue(state, thread, op, 0), "file:setvbuf", 1));
    try ensureOpen(state, handle.file);
    const mode = try state.expectArgumentString(thread, op, "file:setvbuf", 1);
    const buffer_mode = std.meta.stringToEnum(File.BufferMode, mode) orelse return state.failArgumentMessage("file:setvbuf", 2, "invalid mode");
    if (try flushReport(state, handle.file)) |failure| return returnResult(state, thread, op, failure, .nil);
    handle.file.buffer_mode = buffer_mode;
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
    const userdata = try expectFile(state, table.get(.{ .string = "file" }));
    if (fileOfUserdata(userdata).?.closed) return state.fail("file is already closed");
    const handle = try writable(userdata);
    const specs = table.get(.{ .string = "specs" });
    var values = std.ArrayList(Value).empty;
    errdefer values.deinit(state.allocator);
    if (specs == .table and specs.table.array.items.len != 0) {
        for (specs.table.array.items) |spec| if (!try readInto(state, handle, &values, spec)) break;
    } else {
        _ = try readInto(state, handle, &values, .{ .string = try state.strings.intern("l") });
    }
    if (values.items.len == 0 or values.items[0] == .nil) {
        values.deinit(state.allocator);
        const auto_close = table.get(.{ .string = "auto_close" });
        if (auto_close == .boolean and auto_close.boolean) _ = try closeFile(state, handle);
        return &[_]Value{};
    }
    return try values.toOwnedSlice(state.allocator);
}

const CurrentFile = enum { input, output };

fn setCurrentFile(state: *State, thread: *Thread, op: bytecode.Call, which: CurrentFile) !void {
    if (op.arg_count == 0 or runtime.argValue(state, thread, op, 0) == .nil) {
        try state.returnValues(thread, op.base, op.return_count, &.{.{ .userdata = try currentFile(state, which) }});
        return;
    }
    var value = runtime.argValue(state, thread, op, 0);
    if (value == .string) {
        value = try openCheckedFile(state, value.string, if (which == .output) "w" else "r");
    } else {
        const userdata = try expectFileArgument(state, value, if (which == .output) "io.output" else "io.input", 1);
        try ensureOpen(state, fileOfUserdata(userdata).?);
    }
    switch (which) {
        .input => state.io_input = value.userdata,
        .output => state.io_output = value.userdata,
    }
    try state.returnValues(thread, op.base, op.return_count, &.{value});
}

fn openCheckedFile(state: *State, path: []const u8, mode: []const u8) !Value {
    const parsed = parseMode(mode).?;
    if (specialDevice(path)) |kind| return newFile(state, .{ .kind = kind, .path = path, .mode = parsed });
    if (parsed.kind != 'r') {
        io_mod.fsWriteFile(state, path, "") catch |err| return failOpenChecked(state, path, err);
        return newFile(state, .{ .path = path, .mode = parsed });
    }
    const contents = io_mod.readFileRaw(state, path) catch |err| {
        if (err != error.IsDir) return failOpenChecked(state, path, err);
        return newFile(state, .{ .path = path, .mode = parsed, .is_directory = true });
    };
    return newFile(state, .{ .path = path, .mode = parsed, .contents = contents });
}

fn failOpenChecked(state: *State, path: []const u8, err: anyerror) anyerror {
    if (err == error.OutOfMemory) return err;
    const message = try std.fmt.allocPrint(state.allocator, "cannot open file '{s}' ({s})", .{ path, host.fileError(err).message });
    defer state.allocator.free(message);
    return state.fail(try state.strings.intern(message));
}

/// Reads the rest of stdin, sharing the `io.stdin` position. Caller owns the bytes.
pub fn readAllStdin(state: *State) ![]u8 {
    var source = io_mod.stdinSource(state);
    defer source.finish();
    var bytes: std.ArrayList(u8) = .empty;
    errdefer bytes.deinit(state.allocator);
    try appendRemaining(state, source.reader(), &bytes);
    return bytes.toOwnedSlice(state.allocator);
}

/// Reads one line from stdin, keeping the newline; null at end of input.
pub fn readStdinLine(state: *State) !?[]const u8 {
    const value = try readStdinFormat(state, .{ .line = true });
    return if (value == .string) value.string else null;
}

/// Consumes the unread bytes of a file; they stay valid until the handle is next used.
pub fn readRemaining(state: *State, userdata: *Userdata) ![]const u8 {
    const handle = try writable(userdata);
    const file = handle.file;
    if (file.kind == .stdin) {
        const value = try readStdinFormat(state, .all);
        return if (value == .string) value.string else "";
    }
    if (file.kind == .full_device) return state.fail("File too large");
    try refreshReadable(state, handle);
    const content = file.content.items;
    const start = @min(content.len, file.pos);
    file.pos = content.len;
    return content[start..];
}

/// Resizes the file through the filesystem capability; the handle is unchanged on failure.
pub fn truncateFile(state: *State, userdata: *Userdata, size: usize) !void {
    const handle = try writable(userdata);
    const file = handle.file;
    const bytes = try state.allocator.alloc(u8, size);
    var owned = true;
    defer if (owned) state.allocator.free(bytes);
    const copied = @min(size, file.content.items.len);
    @memcpy(bytes[0..copied], file.content.items[0..copied]);
    @memset(bytes[copied..], 0);
    try io_mod.fsWriteFile(state, file.path, bytes);
    file.content.deinit(state.allocator);
    file.content = ownedBuffer(bytes);
    owned = false;
    file.synced = size;
    file.generation = state.file_generation;
    handle.noteSize(state);
}

/// Flushes every open handle, as C `exit` does; errors are ignored.
pub fn flushOpenFiles(state: *State) void {
    var index: usize = 0;
    while (index < state.userdata_allocations.items.len) : (index += 1) {
        const userdata = state.userdata_allocations.items[index];
        const file = fileOfUserdata(userdata) orelse continue;
        if (file.closed or file.kind != .regular or !file.writable or !file.hasUnflushedWrites()) continue;
        const handle = writable(userdata) catch continue;
        flushFile(state, handle.file) catch {};
    }
}

fn currentFile(state: *State, which: CurrentFile) !*Userdata {
    return switch (which) {
        .input => state.io_input,
        .output => state.io_output,
    } orelse state.fail("file expected");
}

fn defaultFile(state: *State, which: CurrentFile) !*Userdata {
    const userdata = try currentFile(state, which);
    if (fileOfUserdata(userdata).?.closed) return state.fail(switch (which) {
        .input => "default input file is closed",
        .output => "default output file is closed",
    });
    return userdata;
}

fn readFromFile(state: *State, thread: *Thread, op: bytecode.Call, handle: Handle, first_arg: u32) !void {
    const file = handle.file;
    try ensureOpen(state, file);
    if (!file.readable) {
        try state.returnValues(thread, op.base, op.return_count, &.{ .nil, .{ .string = try state.strings.intern("file is not readable") }, .{ .integer = 9 } });
        return;
    }
    if (file.is_directory) {
        const info = host.fileError(error.IsDir);
        try state.returnValues(thread, op.base, op.return_count, &.{ .nil, .{ .string = try state.strings.intern(info.message) }, .{ .integer = info.errno } });
        return;
    }
    var values = std.ArrayList(Value).empty;
    defer values.deinit(state.allocator);
    if (op.arg_count <= first_arg) {
        _ = try readInto(state, handle, &values, .{ .string = try state.strings.intern("l") });
    } else {
        var index = first_arg;
        while (index < op.arg_count) : (index += 1) {
            if (!try readInto(state, handle, &values, runtime.argValue(state, thread, op, index))) break;
        }
    }
    try state.returnValues(thread, op.base, op.return_count, values.items);
}

/// Returns false when the format fails; like `g_read`, later formats are then skipped.
fn readInto(state: *State, handle: Handle, values: *std.ArrayList(Value), spec: Value) !bool {
    const value = try readOne(state, handle, spec);
    try values.append(state.allocator, value);
    return value != .nil;
}

const ReadFormat = union(enum) {
    count: usize,
    all,
    /// True for "L", which keeps the newline.
    line: bool,
    number,
};

fn parseReadFormat(state: *State, spec_value: Value) !ReadFormat {
    if (runtime.toInteger(spec_value)) |count| {
        if (count < 0) return state.fail("invalid format");
        return .{ .count = std.math.cast(usize, count) orelse std.math.maxInt(usize) };
    }
    var spec = try state.expectString(spec_value);
    if (spec.len != 0 and spec[0] == '*') spec = spec[1..];
    if (spec.len == 0) return state.fail("invalid format");
    return switch (spec[0]) {
        'a' => .all,
        'l' => .{ .line = false },
        'L' => .{ .line = true },
        'n' => .number,
        else => state.fail("invalid format"),
    };
}

fn readOne(state: *State, handle: Handle, spec_value: Value) !Value {
    const file = handle.file;
    try ensureOpen(state, file);
    if (!file.readable) return state.fail("file is not readable");
    if (file.is_directory) return state.fail(host.fileError(error.IsDir).message);
    const format = try parseReadFormat(state, spec_value);
    if (file.kind == .stdin) return readStdinFormat(state, format);
    if (file.kind == .full_device) return readFullDevice(state, format);
    try refreshReadable(state, handle);
    const content = file.content.items;
    const start = @min(content.len, file.pos);

    switch (format) {
        .count => |count| {
            if (count == 0) return if (start < content.len) .{ .string = try state.strings.intern("") } else .nil;
            if (start >= content.len) return .nil;
            const end = start + @min(content.len - start, count);
            file.pos = end;
            return .{ .string = try state.strings.intern(content[start..end]) };
        },
        .all => {
            file.pos = content.len;
            return .{ .string = try state.strings.intern(content[start..]) };
        },
        .line => |keep_newline| {
            if (start >= content.len) return .nil;
            const end = std.mem.indexOfScalarPos(u8, content, start, '\n') orelse content.len;
            const include_newline = keep_newline and end < content.len;
            const slice_end = if (include_newline) end + 1 else end;
            file.pos = if (end < content.len) end + 1 else end;
            return .{ .string = try state.strings.intern(content[start..slice_end]) };
        },
        .number => {
            const scanned = scanNumber(content, start);
            file.pos = scanned.next;
            return scanned.value;
        },
    }
}

fn readFullDevice(state: *State, format: ReadFormat) !Value {
    switch (format) {
        .count => |count| {
            if (count > state.options.max_file_bytes) return state.fail("File too large");
            const bytes = try state.allocator.alloc(u8, count);
            defer state.allocator.free(bytes);
            @memset(bytes, 0);
            return .{ .string = try state.strings.intern(bytes) };
        },
        .number => return .nil,
        .all, .line => return state.fail("File too large"),
    }
}

fn readStdinFormat(state: *State, format: ReadFormat) !Value {
    var source = io_mod.stdinSource(state);
    defer source.finish();
    const reader = source.reader();
    switch (format) {
        .count => |count| {
            const available = peekSome(reader) orelse return .nil;
            if (count == 0) return .{ .string = try state.strings.intern("") };
            if (available.len >= count) {
                const value = try state.strings.intern(available[0..count]);
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
            return .{ .string = try state.strings.intern(bytes.items) };
        },
        .all => {
            var bytes: std.ArrayList(u8) = .empty;
            defer bytes.deinit(state.allocator);
            try appendRemaining(state, reader, &bytes);
            return .{ .string = try state.strings.intern(bytes.items) };
        },
        .line => |keep_newline| {
            var bytes: std.ArrayList(u8) = .empty;
            defer bytes.deinit(state.allocator);
            while (peekSome(reader)) |available| {
                if (std.mem.indexOfScalar(u8, available, '\n')) |newline| {
                    const end = if (keep_newline) newline + 1 else newline;
                    const value = if (bytes.items.len == 0) try state.strings.intern(available[0..end]) else blk: {
                        try bytes.appendSlice(state.allocator, available[0..end]);
                        break :blk try state.strings.intern(bytes.items);
                    };
                    reader.toss(newline + 1);
                    return .{ .string = value };
                }
                try bytes.appendSlice(state.allocator, available);
                reader.toss(available.len);
            }
            if (bytes.items.len == 0) return .nil;
            return .{ .string = try state.strings.intern(bytes.items) };
        },
        .number => {
            while (true) {
                const available = peekSome(reader) orelse return .nil;
                const skip = whitespacePrefix(available);
                reader.toss(skip);
                if (skip < available.len) break;
            }
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
    next: usize,
};

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

const WriteTarget = enum { stdout, stderr, discard, full_device, buffer };

fn writeTarget(file: *const File) WriteTarget {
    return switch (file.kind) {
        .stdout => .stdout,
        .stderr => .stderr,
        .null_device => .discard,
        .full_device => .full_device,
        .stdin, .regular, .popen, .anonymous => .buffer,
    };
}

fn writeToFile(state: *State, thread: *Thread, op: bytecode.Call, handle: Handle, first_arg: u32, function_name: []const u8) !void {
    const file = handle.file;
    try ensureOpen(state, file);
    if (!file.writable) {
        try state.returnValues(thread, op.base, op.return_count, &.{ .nil, .{ .string = try state.strings.intern("file is not writable") }, .{ .integer = 9 } });
        return;
    }
    const target = writeTarget(file);
    // The Windows CRT treats `_IOLBF` as full buffering.
    const line_buffered = file.buffer_mode == .line and builtin.os.tag != .windows;
    var wrote_newline = false;
    var total: usize = 0;
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
            else => return state.failArgumentType(function_name, index + 1, "string", value),
        };
        if (line_buffered and !wrote_newline and std.mem.indexOfScalar(u8, bytes, '\n') != null) wrote_newline = true;
        switch (target) {
            .stdout => try io_mod.writeStdout(state, bytes),
            .stderr => try io_mod.writeStderr(state, bytes),
            .discard => {},
            .full_device => if (bytes.len != 0) {
                if (file.buffer_mode == .no) return returnWriteFailure(state, thread, op, host.fileError(error.NoSpaceLeft), total);
                file.device_pending = true;
                if (builtin.os.tag == .freebsd and line_buffered and std.mem.indexOfScalar(u8, bytes, '\n') != null)
                    return returnWriteFailure(state, thread, op, host.fileError(error.NoSpaceLeft), total);
            },
            .buffer => writeBytes(state, handle, bytes) catch |err| switch (err) {
                error.FileTooBig => return returnWriteFailure(state, thread, op, host.fileError(err), total),
                else => return err,
            },
        }
        total += bytes.len;
    }
    if (file.buffer_mode == .no) {
        if (try flushReport(state, file)) |failure| return returnWriteFailure(state, thread, op, failure, 0);
    } else if (wrote_newline) _ = try flushReport(state, file);
    try state.returnValues(thread, op.base, op.return_count, &.{handle.value()});
}

fn returnWriteFailure(state: *State, thread: *Thread, op: bytecode.Call, info: host.FileError, total: usize) !void {
    try state.returnValues(thread, op.base, op.return_count, &.{ .nil, .{ .string = try state.strings.intern(info.message) }, .{ .integer = info.errno }, .{ .integer = @intCast(total) } });
}

fn writeBytes(state: *State, handle: Handle, bytes: []const u8) !void {
    if (bytes.len == 0) return;
    const file = handle.file;
    const content = &file.content;
    const pos = if (file.append) content.items.len else file.pos;
    const end = std.math.add(usize, pos, bytes.len) catch return error.FileTooBig;
    if (end > state.options.max_file_bytes) return error.FileTooBig;
    defer handle.noteSize(state);
    if (pos < file.synced) file.synced = pos;
    if (pos > content.items.len) try content.appendNTimes(state.allocator, 0, pos - content.items.len);
    const overlap = @min(content.items.len - pos, bytes.len);
    @memcpy(content.items[pos..][0..overlap], bytes[0..overlap]);
    try content.appendSlice(state.allocator, bytes[overlap..]);
    file.pos = end;
}

fn closeFileValue(state: *State, thread: *Thread, op: bytecode.Call, value: Value, function_name: []const u8) !void {
    const handle = try writable(try expectFileArgument(state, value, function_name, 1));
    const file = handle.file;
    try ensureOpen(state, file);
    if (file.isStandard()) {
        try state.returnValues(thread, op.base, op.return_count, &.{ .nil, .{ .string = try state.strings.intern("cannot close standard file") } });
        return;
    }
    if (file.kind == .popen) {
        const result = try finishPopen(state, file);
        markClosed(state, handle);
        try os_lib.returnProcessResult(state, thread, op, result);
        return;
    }
    try returnResult(state, thread, op, try closeFile(state, handle), .{ .boolean = true });
}

fn closeFile(state: *State, handle: Handle) !?host.FileError {
    var failure: ?host.FileError = null;
    if (handle.file.kind == .popen) {
        _ = try finishPopen(state, handle.file);
    } else failure = try flushReport(state, handle.file);
    markClosed(state, handle);
    return failure;
}

fn flushReport(state: *State, file: *File) error{OutOfMemory}!?host.FileError {
    if (file.kind == .full_device) {
        if (!file.device_pending) return null;
        // FreeBSD retains failed output for subsequent flush/close attempts.
        if (builtin.os.tag != .freebsd) file.device_pending = false;
        return host.fileError(error.NoSpaceLeft);
    }
    flushFile(state, file) catch |err| {
        if (err == error.OutOfMemory) return error.OutOfMemory;
        return host.fileError(err);
    };
    return null;
}

fn markClosed(state: *State, handle: Handle) void {
    handle.file.closed = true;
    handle.file.content.clearAndFree(state.allocator);
    handle.noteSize(state);
}

fn flushFile(state: *State, file: *File) anyerror!void {
    switch (file.kind) {
        .stdout => return io_mod.flushStdout(state),
        .stderr => return io_mod.flushStderr(state),
        .regular => {},
        .full_device => {
            file.device_pending = false;
            return;
        },
        .stdin, .popen, .null_device, .anonymous => return,
    }
    if (!file.writable or !file.hasUnflushedWrites()) return;

    const content = file.content.items;
    if (file.append) {
        io_mod.fsAppendFile(state, file.path, content[file.synced..]) catch |err| switch (err) {
            error.FileNotFound => try io_mod.fsWriteFile(state, file.path, content),
            else => return err,
        };
        file.synced = content.len;
        return;
    }
    var written = false;
    if (file.generation == state.file_generation) {
        if (io_mod.fsWriteFileAt(state, file.path, file.synced, content[file.synced..])) {
            written = true;
        } else |err| switch (err) {
            error.OutOfMemory => return err,
            else => {},
        }
    }
    if (!written) try io_mod.fsWriteFile(state, file.path, content);
    file.synced = content.len;
    file.generation = state.file_generation;
}

fn refreshReadable(state: *State, handle: Handle) !void {
    const file = handle.file;
    if (!file.readable or file.kind != .regular) return;
    if (file.generation == state.file_generation) return;
    if (file.hasUnflushedWrites()) return;
    file.generation = state.file_generation;
    const contents = io_mod.readFileRaw(state, file.path) catch |err| {
        if (err == error.OutOfMemory) return err;
        return;
    };
    file.content.deinit(state.allocator);
    file.content = ownedBuffer(contents);
    file.synced = contents.len;
    handle.noteSize(state);
}

fn newLinesIterator(state: *State, thread: *Thread, file_value: Value, op: bytecode.Call, first_arg: u32, auto_close: bool) !Value {
    const value = try state.newTableWithHints(0, 4);
    const table = value.table;
    try state.setTableRaw(table, .{ .string = try state.strings.intern("__zlua_lines_iterator") }, .{ .boolean = true });
    try state.setTableRaw(table, .{ .string = try state.strings.intern("file") }, file_value);
    try state.setTableRaw(table, .{ .string = try state.strings.intern("auto_close") }, .{ .boolean = auto_close });
    if (op.arg_count > first_arg) {
        const specs = try state.newTableWithHints(op.arg_count - first_arg, 0);
        var index = first_arg;
        while (index < op.arg_count) : (index += 1) try state.setTableRaw(specs.table, .{ .integer = @intCast(index - first_arg + 1) }, runtime.argValue(state, thread, op, index));
        try state.setTableRaw(table, .{ .string = try state.strings.intern("specs") }, specs);
    }
    return .{ .gmatch_iterator = table };
}

fn expectFile(state: *State, value: Value) !*Userdata {
    if (fileOf(value) == null) return state.fail("file expected");
    return value.userdata;
}

fn expectFileArgument(state: *State, value: Value, function_name: []const u8, index: u32) !*Userdata {
    return checkedFile(state, value) orelse state.failArgumentType(function_name, index, "FILE*", value);
}

/// Like `luaL_testudata(L, i, "FILE*")`: a handle whose metatable was replaced is not a file.
pub fn checkedFile(state: *State, value: Value) ?*Userdata {
    if (fileOf(value) == null) return null;
    const metatable = value.userdata.metatable orelse return null;
    if (state.file_metatable == metatable or state.fs_file_metatable == metatable) return value.userdata;
    return null;
}

fn ensureOpen(state: *State, file: *const File) !void {
    if (file.closed) return state.fail("attempt to use a closed file");
}

pub const ParsedMode = struct {
    kind: u8,
    append: bool,
    reads_existing: bool,
    plus: bool = false,

    pub fn readable(self: ParsedMode) bool {
        return self.kind == 'r' or self.plus;
    }

    pub fn writable(self: ParsedMode) bool {
        return self.kind != 'r' or self.plus;
    }

    /// Whether the host's `fopen` starts at the end: BSD for every append mode,
    /// glibc only for "a", musl and the Windows CRT never.
    pub fn opensAtEnd(self: ParsedMode) bool {
        if (!self.append) return false;
        if (builtin.os.tag == .windows) return false;
        if (builtin.os.tag == .linux) return !self.plus and !builtin.abi.isMusl();
        return true;
    }
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

fn specialDevice(path: []const u8) ?File.Kind {
    if (std.mem.eql(u8, path, "/dev/null")) return .null_device;
    if ((builtin.os.tag == .linux or builtin.os.tag == .freebsd) and std.mem.eql(u8, path, "/dev/full")) return .full_device;
    return null;
}

/// Unbuffered handle over the state's stdin source or output writers.
pub fn newStandardFile(state: *State, kind: File.Kind) !Value {
    std.debug.assert(kind == .stdin or kind == .stdout or kind == .stderr);
    return newFile(state, .{ .kind = kind, .mode = parseMode(if (kind == .stdin) "r" else "w").? });
}

test "host stdin reader is consumed only as far as each read needs" {
    var reader: std.Io.Reader = .fixed("first\n12 rest\nabcdef\nlast");
    var state = try State.initWithOptions(std.testing.allocator, .{ .stdlib = .full, .stdin_reader = &reader });
    defer state.deinit();
    try entry_mod.executeSourceChunk(&state, "a = io.read()");
    try std.testing.expectEqualStrings("first", state.getGlobal("a").string);
    try std.testing.expectEqual(@as(usize, 6), reader.seek);
    try entry_mod.executeSourceChunk(&state,
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

test "stdin seeks past the integer limits fail without moving" {
    var state = try State.initWithOptions(std.testing.allocator, .{ .stdlib = .full, .stdin = "abc" });
    defer state.deinit();
    try entry_mod.executeSourceChunk(&state,
        \\assert(io.read(1) == 'a')
        \\local ok, message, code = io.stdin:seek('cur', math.maxinteger)
        \\assert(ok == nil and message:find('^Value too large') and (code == 75 or code == 84 or code == 132))
        \\assert(select(3, io.stdin:seek('end', math.maxinteger)) == code)
        \\assert(select(3, io.stdin:seek('cur', math.mininteger)) == 22)
        \\assert(select(2, io.stdin:seek('set', -1)) == 'Invalid argument')
        \\assert(io.stdin:seek('set', math.maxinteger) == math.maxinteger and io.read(1) == nil)
        \\assert(io.stdin:seek('set', 1) == 1 and io.read('a') == 'bc')
    );
}

test "output flush policies follow C stdio buffering" {
    inline for (.{ .{ OutputFlushCase.print, 0, 5 }, .{ OutputFlushCase.line, 3, 5 }, .{ OutputFlushCase.explicit, 0, 0 } }) |case| {
        var buffer: [64]u8 = undefined;
        var sink: std.Io.Writer.Discarding = .init(&buffer);
        var state = try State.initWithOptions(std.testing.allocator, .{ .stdlib = .full, .stdout = &sink.writer, .stdout_flush = case[0], .capture_output = false });
        defer state.deinit();
        try entry_mod.executeSourceChunk(&state, "io.write('ab\\n')");
        try std.testing.expectEqual(@as(u64, case[1]), sink.count);
        try entry_mod.executeSourceChunk(&state, "print('x')");
        try std.testing.expectEqual(@as(u64, case[2]), sink.count);
        try std.testing.expectEqual(@as(u64, 5), sink.fullCount());
        try std.testing.expectEqual(@as(usize, 0), state.stdout.items.len);
        try entry_mod.executeSourceChunk(&state, "io.stdout:write('y') io.flush()");
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

test "Linux /dev/full emulation follows glibc stream results" {
    if (builtin.os.tag == .windows or builtin.os.tag == .freebsd) return error.SkipZigTest;
    var state = try State.initWithOptions(std.testing.allocator, .{ .stdlib = .full });
    defer state.deinit();
    const device = try newFile(&state, .{ .kind = .full_device, .path = "/dev/full", .mode = parseMode("w").? });
    try state.setTableRaw(state.global_table.?, .{ .string = try state.strings.intern("full") }, device);
    const second = try newFile(&state, .{ .kind = .full_device, .path = "/dev/full", .mode = parseMode("w").? });
    try state.setTableRaw(state.global_table.?, .{ .string = try state.strings.intern("other") }, second);
    const third = try newFile(&state, .{ .kind = .full_device, .path = "/dev/full", .mode = parseMode("w").? });
    try state.setTableRaw(state.global_table.?, .{ .string = try state.strings.intern("third") }, third);
    const reader = try newFile(&state, .{ .kind = .full_device, .path = "/dev/full", .mode = parseMode("r").? });
    try state.setTableRaw(state.global_table.?, .{ .string = try state.strings.intern("reader") }, reader);
    try entry_mod.executeSourceChunk(&state,
        \\local enospc = 'No space left on device'
        \\-- Full buffering: writes succeed, a flush fails once and discards them.
        \\assert(full:write('abcd') == full)
        \\local ok, message, code = full:flush()
        \\assert(ok == nil and message == enospc and code == 28)
        \\assert(full:flush() == true)
        \\assert(full:write('abcd') == full)
        \\ok, message, code = full:close()
        \\assert(ok == nil and message == enospc and code == 28 and io.type(full) == 'closed file')
        \\-- Unbuffered writes fail at once with the bytes written so far.
        \\assert(other:setvbuf('no'))
        \\local _, _, err, count = other:write('abcd')
        \\assert(err == 28 and count == 0)
        \\assert(select(4, other:write('', 'xy', 'z')) == 0)
        \\assert(other:write('') == other)
        \\-- Line buffering: glibc ignores the failed flush at a newline.
        \\assert(other:setvbuf('line'))
        \\assert(other:write('no newline') == other and other:write('line\n') == other)
        \\assert(other:close() == true)
        \\-- The default output reports through io.flush and io.close.
        \\io.output(third)
        \\assert(io.write('abcd') == third)
        \\ok, message, code = io.flush()
        \\assert(ok == nil and message == enospc and code == 28)
        \\assert(io.flush() == true)
        \\io.write('pending')
        \\ok, message, code = io.close()
        \\assert(ok == nil and message == enospc and code == 28)
        \\io.output(io.stdout)
        \\-- Reads see endless zero bytes.
        \\assert(reader:read(4) == '\0\0\0\0' and reader:read(0) == '')
        \\local a, b, c = reader:read(2, 'n', 1)
        \\assert(a == '\0\0' and b == nil and c == nil)
        \\assert(reader:read(1) == '\0')
        \\for _, format in ipairs({ 'a', 'l', 'L' }) do
        \\  assert(select(2, pcall(reader.read, reader, format)) == 'File too large')
        \\end
        \\assert(select(2, pcall(reader.read, reader, 1 << 40)) == 'File too large')
    );
}
