const std = @import("std");
const compile = @import("../compile.zig");
const runtime = @import("../runtime.zig");
const host = @import("../runtime/host.zig");
const io_lib = @import("io.zig");
const io_mod = @import("../runtime/io.zig");
const metatable_mod = @import("../runtime/metatable.zig");

const bytecode = compile.bytecode;
const State = runtime.State;
const Thread = runtime.Thread;
const Value = runtime.Value;
const Table = runtime.Table;

pub fn read(state: *State, thread: *Thread, op: bytecode.Call) !void {
    const path = try state.expectArgumentString(thread, op, "fs.read", 0);
    const options = optionTable(state, thread, op, "fs.read", 1) catch |err| return err;
    const max_bytes = if (options) |table| try integerOption(state, table, "fs.read", "max_bytes", state.options.max_file_bytes) else state.options.max_file_bytes;
    const bytes = io_mod.fsReadFileAlloc(state, path, max_bytes) catch |err| return returnFailure(state, thread, op, "read", path, null, err);
    defer state.allocator.free(bytes);
    try state.returnValues(thread, op.base, op.return_count, &.{.{ .string = try state.strings.intern(bytes) }});
}

pub fn write(state: *State, thread: *Thread, op: bytecode.Call) !void {
    const path = try state.expectArgumentString(thread, op, "fs.write", 0);
    const data = try state.expectArgumentString(thread, op, "fs.write", 1);
    const options = try optionTable(state, thread, op, "fs.write", 2);
    const append = if (options) |table| try boolOption(state, table, "fs.write", "append", false) else false;
    const create_parents = if (options) |table| try boolOption(state, table, "fs.write", "create_parents", false) else false;
    const exclusive = if (options) |table| try boolOption(state, table, "fs.write", "exclusive", false) else false;
    const atomic = if (options) |table| try boolOption(state, table, "fs.write", "atomic", false) else false;
    if (create_parents) {
        if (std.fs.path.dirname(path)) |parent| if (parent.len != 0) io_mod.fsMakeDir(state, parent, true) catch |err| return returnFailure(state, thread, op, "mkdir", parent, null, err);
    }
    if (exclusive) {
        const already_exists = exists_check: {
            _ = io_mod.fsStat(state, path, false) catch |err| {
                if (err == error.FileNotFound) break :exists_check false;
                return returnFailure(state, thread, op, "write", path, null, err);
            };
            break :exists_check true;
        };
        if (already_exists) return returnFailure(state, thread, op, "write", path, null, error.PathAlreadyExists);
    }
    if (append) {
        const existing = io_mod.fsReadFileAlloc(state, path, state.options.max_file_bytes) catch |err| switch (err) {
            error.FileNotFound => try state.allocator.dupe(u8, ""),
            else => return returnFailure(state, thread, op, "read", path, null, err),
        };
        defer state.allocator.free(existing);
        const combined = try std.mem.concat(state.allocator, u8, &.{ existing, data });
        defer state.allocator.free(combined);
        writeBytes(state, path, combined, atomic) catch |err| return returnFailure(state, thread, op, "write", path, null, err);
    } else {
        writeBytes(state, path, data, atomic) catch |err| return returnFailure(state, thread, op, "write", path, null, err);
    }
    try state.returnValues(thread, op.base, op.return_count, &.{.{ .boolean = true }});
}

pub fn open(state: *State, thread: *Thread, op: bytecode.Call) !void {
    const path = try state.expectArgumentString(thread, op, "fs.open", 0);
    const mode = if (op.arg_count >= 2 and runtime.argValue(state, thread, op, 1) != .nil)
        try state.expectArgumentString(thread, op, "fs.open", 1)
    else
        "r";
    const parsed = io_lib.parseMode(mode) orelse return state.failArgumentMessage("fs.open", 2, "invalid mode");
    try openFile(state, thread, op, path, parsed);
}

fn openFile(state: *State, thread: *Thread, op: bytecode.Call, path: []const u8, parsed: io_lib.ParsedMode) !void {
    var contents: []const u8 = "";
    var found = true;
    if (parsed.reads_existing or parsed.append) {
        contents = io_mod.fsReadFileAlloc(state, path, state.options.max_file_bytes) catch |err| switch (err) {
            error.FileNotFound => if (parsed.kind == 'r') return returnFailure(state, thread, op, "open", path, null, err) else blk: {
                found = false;
                break :blk "";
            },
            else => return returnFailure(state, thread, op, "open", path, null, err),
        };
    }
    io_lib.prepareWrite(state, path, parsed, found) catch |err| {
        state.allocator.free(contents);
        return returnFailure(state, thread, op, "open", path, null, err);
    };
    const value = try io_lib.newFile(state, .{ .path = path, .mode = parsed, .contents = contents, .buffer_mode = .no, .fs_methods = true });
    try state.returnValues(thread, op.base, op.return_count, &.{value});
}

pub fn stat(state: *State, thread: *Thread, op: bytecode.Call) !void {
    const path = try state.expectArgumentString(thread, op, "fs.stat", 0);
    const options = try optionTable(state, thread, op, "fs.stat", 1);
    const follow = if (options) |table| try boolOption(state, table, "fs.stat", "follow_symlinks", true) else true;
    const value = io_mod.fsStat(state, path, follow) catch |err| return returnFailure(state, thread, op, "stat", path, null, err);
    try state.returnValues(thread, op.base, op.return_count, &.{try statValue(state, value)});
}

pub fn exists(state: *State, thread: *Thread, op: bytecode.Call) !void {
    const path = try state.expectArgumentString(thread, op, "fs.exists", 0);
    const options = try optionTable(state, thread, op, "fs.exists", 1);
    const follow = if (options) |table| try boolOption(state, table, "fs.exists", "follow_symlinks", true) else true;
    _ = io_mod.fsStat(state, path, follow) catch |err| {
        if (err == error.FileNotFound) {
            try state.returnValues(thread, op.base, op.return_count, &.{.{ .boolean = false }});
            return;
        }
        return returnFailure(state, thread, op, "stat", path, null, err);
    };
    try state.returnValues(thread, op.base, op.return_count, &.{.{ .boolean = true }});
}

pub fn list(state: *State, thread: *Thread, op: bytecode.Call) !void {
    const path = try state.expectArgumentString(thread, op, "fs.list", 0);
    const options = try optionTable(state, thread, op, "fs.list", 1);
    const sorted = if (options) |table| try boolOption(state, table, "fs.list", "sorted", true) else true;
    const entries = io_mod.fsReadDirAlloc(state, path) catch |err| return returnFailure(state, thread, op, "list", path, null, err);
    defer host.deinitDirectoryEntries(state.allocator, entries);
    if (sorted) std.mem.sort(host.DirectoryEntry, entries, {}, lessEntry);
    const result = try state.newTableWithHints(@intCast(entries.len), 0);
    for (entries, 0..) |entry, index| {
        const full_path = try joinTwo(state, path, entry.name);
        defer state.allocator.free(full_path);
        try state.setTableRaw(result.table, .{ .integer = @intCast(index + 1) }, try entryValue(state, entry, full_path, null));
    }
    try state.returnValues(thread, op.base, op.return_count, &.{result});
}

pub fn scandir(state: *State, thread: *Thread, op: bytecode.Call) !void {
    const path = try state.expectArgumentString(thread, op, "fs.scandir", 0);
    const entries = io_mod.fsReadDirAlloc(state, path) catch |err| return returnFailure(state, thread, op, "scandir", path, null, err);
    defer host.deinitDirectoryEntries(state.allocator, entries);
    const iterator = try newIterator(state, "scan");
    const queue = try state.newTableWithHints(@intCast(entries.len), 0);
    for (entries, 0..) |entry, index| {
        const full_path = try joinTwo(state, path, entry.name);
        defer state.allocator.free(full_path);
        try state.setTableRaw(queue.table, .{ .integer = @intCast(index + 1) }, try entryValue(state, entry, full_path, 1));
    }
    try set(iterator, state, "queue", queue);
    try set(iterator, state, "index", .{ .integer = 1 });
    try set(iterator, state, "count", .{ .integer = @intCast(entries.len) });
    try state.returnValues(thread, op.base, op.return_count, &.{iterator});
}

pub fn walk(state: *State, thread: *Thread, op: bytecode.Call) !void {
    const path = try state.expectArgumentString(thread, op, "fs.walk", 0);
    const options = try optionTable(state, thread, op, "fs.walk", 1);
    const max_depth = if (options) |table| try integerOption(state, table, "fs.walk", "max_depth", std.math.maxInt(i32)) else std.math.maxInt(i32);
    const entries = io_mod.fsReadDirAlloc(state, path) catch |err| return returnFailure(state, thread, op, "walk", path, null, err);
    defer host.deinitDirectoryEntries(state.allocator, entries);
    const iterator = try newIterator(state, "walk");
    const queue = try state.newTableWithHints(@intCast(entries.len), 0);
    for (entries, 0..) |entry, index| {
        const full_path = try joinTwo(state, path, entry.name);
        defer state.allocator.free(full_path);
        try state.setTableRaw(queue.table, .{ .integer = @intCast(index + 1) }, try entryValue(state, entry, full_path, 1));
    }
    try set(iterator, state, "queue", queue);
    try set(iterator, state, "index", .{ .integer = 1 });
    try set(iterator, state, "count", .{ .integer = @intCast(entries.len) });
    try set(iterator, state, "max_depth", .{ .integer = @intCast(max_depth) });
    try state.returnValues(thread, op.base, op.return_count, &.{iterator});
}

pub fn mkdir(state: *State, thread: *Thread, op: bytecode.Call) !void {
    const path = try state.expectArgumentString(thread, op, "fs.mkdir", 0);
    const options = try optionTable(state, thread, op, "fs.mkdir", 1);
    const parents = if (options) |table| try boolOption(state, table, "fs.mkdir", "parents", false) else false;
    const exist_ok = if (options) |table| try boolOption(state, table, "fs.mkdir", "exist_ok", false) else false;
    io_mod.fsMakeDir(state, path, parents) catch |err| {
        if (exist_ok and err == error.PathAlreadyExists) {
            try state.returnValues(thread, op.base, op.return_count, &.{.{ .boolean = true }});
            return;
        }
        return returnFailure(state, thread, op, "mkdir", path, null, err);
    };
    try state.returnValues(thread, op.base, op.return_count, &.{.{ .boolean = true }});
}

pub fn remove(state: *State, thread: *Thread, op: bytecode.Call) !void {
    const path = try state.expectArgumentString(thread, op, "fs.remove", 0);
    const options = try optionTable(state, thread, op, "fs.remove", 1);
    const recursive = if (options) |table| try boolOption(state, table, "fs.remove", "recursive", false) else false;
    const missing_ok = if (options) |table| try boolOption(state, table, "fs.remove", "missing_ok", false) else false;
    io_mod.fsRemovePath(state, path, recursive) catch |err| {
        if (missing_ok and err == error.FileNotFound) {
            try state.returnValues(thread, op.base, op.return_count, &.{.{ .boolean = true }});
            return;
        }
        return returnFailure(state, thread, op, "remove", path, null, err);
    };
    try state.returnValues(thread, op.base, op.return_count, &.{.{ .boolean = true }});
}

pub fn copy(state: *State, thread: *Thread, op: bytecode.Call) !void {
    const source = try state.expectArgumentString(thread, op, "fs.copy", 0);
    const destination = try state.expectArgumentString(thread, op, "fs.copy", 1);
    const options = try optionTable(state, thread, op, "fs.copy", 2);
    const overwrite = if (options) |table| try boolOption(state, table, "fs.copy", "overwrite", false) else false;
    const recursive = if (options) |table| try boolOption(state, table, "fs.copy", "recursive", false) else false;
    const source_stat = io_mod.fsStat(state, source, false) catch |err| return returnFailure(state, thread, op, "copy", source, destination, err);
    if (source_stat.kind == .directory) {
        if (!recursive) return returnFailure(state, thread, op, "copy", source, destination, error.IsDir);
        const destination_stat: ?host.FileStat = io_mod.fsStat(state, destination, false) catch |err| switch (err) {
            error.FileNotFound => null,
            else => return returnFailure(state, thread, op, "copy", source, destination, err),
        };
        if (destination_stat) |existing| {
            if (!overwrite) return returnFailure(state, thread, op, "copy", source, destination, error.PathAlreadyExists);
            if (existing.kind != .directory) io_mod.fsRemovePath(state, destination, false) catch |err| return returnFailure(state, thread, op, "copy", source, destination, err);
        }
        copyTree(state, source, destination, overwrite) catch |err| return returnFailure(state, thread, op, "copy", source, destination, err);
    } else {
        io_mod.fsCopyFile(state, source, destination, overwrite) catch |err| return returnFailure(state, thread, op, "copy", source, destination, err);
    }
    try state.returnValues(thread, op.base, op.return_count, &.{.{ .boolean = true }});
}

pub fn rename(state: *State, thread: *Thread, op: bytecode.Call) !void {
    const old_path = try state.expectArgumentString(thread, op, "fs.rename", 0);
    const new_path = try state.expectArgumentString(thread, op, "fs.rename", 1);
    io_mod.fsRenamePath(state, old_path, new_path) catch |err| return returnFailure(state, thread, op, "rename", old_path, new_path, err);
    try state.returnValues(thread, op.base, op.return_count, &.{.{ .boolean = true }});
}

pub fn move(state: *State, thread: *Thread, op: bytecode.Call) !void {
    const old_path = try state.expectArgumentString(thread, op, "fs.move", 0);
    const new_path = try state.expectArgumentString(thread, op, "fs.move", 1);
    io_mod.fsRenamePath(state, old_path, new_path) catch |rename_err| {
        if (!std.mem.eql(u8, @errorName(rename_err), "CrossDeviceLink")) return returnFailure(state, thread, op, "move", old_path, new_path, rename_err);
        io_mod.fsCopyFile(state, old_path, new_path, false) catch |err| return returnFailure(state, thread, op, "move", old_path, new_path, err);
        io_mod.fsRemovePath(state, old_path, false) catch |err| return returnFailure(state, thread, op, "move", old_path, new_path, err);
    };
    try state.returnValues(thread, op.base, op.return_count, &.{.{ .boolean = true }});
}

pub fn touch(state: *State, thread: *Thread, op: bytecode.Call) !void {
    const path = try state.expectArgumentString(thread, op, "fs.touch", 0);
    const existing = io_mod.fsReadFileAlloc(state, path, state.options.max_file_bytes) catch |err| switch (err) {
        error.FileNotFound => try state.allocator.dupe(u8, ""),
        else => return returnFailure(state, thread, op, "touch", path, null, err),
    };
    defer state.allocator.free(existing);
    io_mod.fsWriteFile(state, path, existing) catch |err| return returnFailure(state, thread, op, "touch", path, null, err);
    try state.returnValues(thread, op.base, op.return_count, &.{.{ .boolean = true }});
}

pub fn openDir(state: *State, thread: *Thread, op: bytecode.Call) !void {
    const path = try state.expectArgumentString(thread, op, "fs.open_dir", 0);
    const value = io_mod.fsStat(state, path, true) catch |err| return returnFailure(state, thread, op, "open_dir", path, null, err);
    if (value.kind != .directory) return returnFailure(state, thread, op, "open_dir", path, null, error.NotDir);
    const dir = try state.newTableWithHints(0, 12);
    try set(dir, state, "__zlua_fs_dir", .{ .boolean = true });
    try set(dir, state, "__zlua_fs_dir_path", .{ .string = try state.strings.intern(path) });
    try set(dir, state, "entries", .{ .native = .fs_dir_entries });
    try set(dir, state, "walk", .{ .native = .fs_dir_walk });
    try set(dir, state, "open", .{ .native = .fs_dir_open });
    try set(dir, state, "stat", .{ .native = .fs_dir_stat });
    try set(dir, state, "mkdir", .{ .native = .fs_dir_mkdir });
    try set(dir, state, "remove", .{ .native = .fs_dir_remove });
    try set(dir, state, "close", .{ .native = .fs_dir_close });
    const metatable = try state.newTableWithHints(0, 3);
    try set(metatable, state, "__close", .{ .native = .fs_dir_close });
    try set(metatable, state, "__metatable", .{ .string = try state.strings.intern("fs.Directory") });
    metatable_mod.setTableMetatableRaw(state, dir.table, metatable.table);
    try state.returnValues(thread, op.base, op.return_count, &.{dir});
}

pub fn iteratorNextNative(state: *State, thread: *Thread, op: bytecode.Call) !void {
    const value = runtime.argValue(state, thread, op, 0);
    const values = try iteratorNext(state, value);
    defer if (values.len != 0) state.allocator.free(values);
    try state.returnValues(thread, op.base, op.return_count, values);
}

pub fn iteratorNext(state: *State, iterator: Value) ![]const Value {
    if (iterator != .table) return state.fail("fs iterator expected");
    const table = iterator.table;
    if (truthyField(table, "closed")) return &.{};
    const kind = table.getLiteral("__zlua_fs_iterator");
    if (kind != .string) return state.fail("fs iterator expected");
    if (kind.string.eqlBytes("walk")) try expandPending(state, table);
    const queue_value = table.getLiteral("queue");
    if (queue_value != .table) return &.{};
    const index = integerField(table, "index") orelse 1;
    const count = integerField(table, "count") orelse 0;
    if (index > count) {
        try state.setTableRaw(table, .{ .string = try state.strings.intern("closed") }, .{ .boolean = true });
        return &.{};
    }
    const entry = queue_value.table.get(.{ .integer = index });
    try state.setTableRaw(table, .{ .string = try state.strings.intern("index") }, .{ .integer = index + 1 });
    try state.setTableRaw(queue_value.table, .{ .integer = index }, .nil);
    if (kind.string.eqlBytes("walk") and entry == .table) {
        const entry_kind = entry.table.getLiteral("kind");
        const depth = runtime.toInteger(entry.table.getLiteral("depth")) orelse 1;
        const max_depth = integerField(table, "max_depth") orelse std.math.maxInt(i32);
        if (entry_kind == .string and entry_kind.string.eqlBytes("directory") and depth < max_depth) {
            try state.setTableRaw(table, .{ .string = try state.strings.intern("pending_path") }, entry.table.getLiteral("path"));
            try state.setTableRaw(table, .{ .string = try state.strings.intern("pending_depth") }, .{ .integer = depth });
            try state.setTableRaw(table, .{ .string = try state.strings.intern("skip_current") }, .{ .boolean = false });
        }
    }
    const result = try state.allocator.alloc(Value, 1);
    result[0] = entry;
    return result;
}

pub fn iteratorClose(state: *State, thread: *Thread, op: bytecode.Call) !void {
    const table = try expectIteratorTable(state, runtime.argValue(state, thread, op, 0));
    try state.setTableRaw(table, .{ .string = try state.strings.intern("closed") }, .{ .boolean = true });
    try state.returnValues(thread, op.base, op.return_count, &.{.{ .boolean = true }});
}

pub fn iteratorSkip(state: *State, thread: *Thread, op: bytecode.Call) !void {
    const table = try expectIteratorTable(state, runtime.argValue(state, thread, op, 0));
    if (table.getLiteral("pending_path") == .nil) return state.fail("fs walker has no current directory to skip");
    try state.setTableRaw(table, .{ .string = try state.strings.intern("skip_current") }, .{ .boolean = true });
    try state.returnValues(thread, op.base, op.return_count, &.{.{ .boolean = true }});
}

pub fn errorTostring(state: *State, thread: *Thread, op: bytecode.Call) !void {
    const value = runtime.argValue(state, thread, op, 0);
    const message = if (value == .table and value.table.getLiteral("message") == .string) value.table.getLiteral("message").string.bytes() else "filesystem error";
    try state.returnValues(thread, op.base, op.return_count, &.{.{ .string = try state.strings.intern(message) }});
}

pub fn fileStat(state: *State, thread: *Thread, op: bytecode.Call) !void {
    const path = (try expectFsFile(state, runtime.argValue(state, thread, op, 0))).path;
    const value = io_mod.fsStat(state, path, true) catch |err| return returnFailure(state, thread, op, "stat", path, null, err);
    try state.returnValues(thread, op.base, op.return_count, &.{try statValue(state, value)});
}

pub fn fileTell(state: *State, thread: *Thread, op: bytecode.Call) !void {
    const file = try expectFsFile(state, runtime.argValue(state, thread, op, 0));
    try state.returnValues(thread, op.base, op.return_count, &.{.{ .integer = @intCast(file.pos) }});
}

pub fn fileTruncate(state: *State, thread: *Thread, op: bytecode.Call) !void {
    const value = runtime.argValue(state, thread, op, 0);
    const file = try expectFsFile(state, value);
    if (file.closed) return state.fail("attempt to use a closed file");
    if (!file.writable) return returnFailure(state, thread, op, "truncate", file.path, null, error.NotOpenForWriting);
    const size_i = try state.argumentInteger(thread, op, "fs file:truncate", 1);
    if (size_i < 0) return state.failArgumentMessage("fs file:truncate", 2, "non-negative size expected");
    const size: usize = @intCast(size_i);
    io_lib.truncateFile(state, value.userdata, size) catch |err| return returnFailure(state, thread, op, "truncate", file.path, null, err);
    try state.returnValues(thread, op.base, op.return_count, &.{.{ .boolean = true }});
}

pub fn filePath(state: *State, thread: *Thread, op: bytecode.Call) !void {
    const file = try expectFsFile(state, runtime.argValue(state, thread, op, 0));
    try state.returnValues(thread, op.base, op.return_count, &.{.{ .string = try state.strings.intern(file.path) }});
}

pub fn dirEntries(state: *State, thread: *Thread, op: bytecode.Call) !void {
    try dirIteratorDelegate(state, thread, op, false);
}
pub fn dirWalk(state: *State, thread: *Thread, op: bytecode.Call) !void {
    try dirIteratorDelegate(state, thread, op, true);
}

fn dirIteratorDelegate(state: *State, thread: *Thread, op: bytecode.Call, recursive: bool) !void {
    const dir = try expectDir(state, runtime.argValue(state, thread, op, 0));
    const path = try dirPath(state, dir);
    const entries = io_mod.fsReadDirAlloc(state, path) catch |err| return returnFailure(state, thread, op, if (recursive) "walk" else "scandir", path, null, err);
    defer host.deinitDirectoryEntries(state.allocator, entries);
    const iterator = try newIterator(state, if (recursive) "walk" else "scan");
    const queue = try state.newTableWithHints(@intCast(entries.len), 0);
    for (entries, 0..) |entry, index| {
        const full = try joinTwo(state, path, entry.name);
        defer state.allocator.free(full);
        try state.setTableRaw(queue.table, .{ .integer = @intCast(index + 1) }, try entryValue(state, entry, full, 1));
    }
    try set(iterator, state, "queue", queue);
    try set(iterator, state, "index", .{ .integer = 1 });
    try set(iterator, state, "count", .{ .integer = @intCast(entries.len) });
    try set(iterator, state, "max_depth", .{ .integer = std.math.maxInt(i32) });
    try state.returnValues(thread, op.base, op.return_count, &.{iterator});
}

pub fn dirOpen(state: *State, thread: *Thread, op: bytecode.Call) !void {
    const dir = try expectDir(state, runtime.argValue(state, thread, op, 0));
    const child = try state.expectArgumentString(thread, op, "fs directory:open", 1);
    const path = try joinTwo(state, try dirPath(state, dir), child);
    defer state.allocator.free(path);
    const mode = if (op.arg_count >= 3 and runtime.argValue(state, thread, op, 2) != .nil) try state.expectArgumentString(thread, op, "fs directory:open", 2) else "r";
    const parsed = io_lib.parseMode(mode) orelse return state.failArgumentMessage("fs directory:open", 3, "invalid mode");
    try openFile(state, thread, op, path, parsed);
}

pub fn dirStat(state: *State, thread: *Thread, op: bytecode.Call) !void {
    const dir = try expectDir(state, runtime.argValue(state, thread, op, 0));
    const child = if (op.arg_count >= 2 and runtime.argValue(state, thread, op, 1) != .nil) try state.expectArgumentString(thread, op, "fs directory:stat", 1) else "";
    const path = if (child.len == 0) try state.allocator.dupe(u8, try dirPath(state, dir)) else try joinTwo(state, try dirPath(state, dir), child);
    defer state.allocator.free(path);
    const value = io_mod.fsStat(state, path, true) catch |err| return returnFailure(state, thread, op, "stat", path, null, err);
    try state.returnValues(thread, op.base, op.return_count, &.{try statValue(state, value)});
}

pub fn dirMkdir(state: *State, thread: *Thread, op: bytecode.Call) !void {
    const dir = try expectDir(state, runtime.argValue(state, thread, op, 0));
    const child = try state.expectArgumentString(thread, op, "fs directory:mkdir", 1);
    const path = try joinTwo(state, try dirPath(state, dir), child);
    defer state.allocator.free(path);
    io_mod.fsMakeDir(state, path, true) catch |err| return returnFailure(state, thread, op, "mkdir", path, null, err);
    try state.returnValues(thread, op.base, op.return_count, &.{.{ .boolean = true }});
}

pub fn dirRemove(state: *State, thread: *Thread, op: bytecode.Call) !void {
    const dir = try expectDir(state, runtime.argValue(state, thread, op, 0));
    const child = try state.expectArgumentString(thread, op, "fs directory:remove", 1);
    const path = try joinTwo(state, try dirPath(state, dir), child);
    defer state.allocator.free(path);
    const recursive = op.arg_count >= 3 and runtime.argValue(state, thread, op, 2) == .boolean and runtime.argValue(state, thread, op, 2).boolean;
    io_mod.fsRemovePath(state, path, recursive) catch |err| return returnFailure(state, thread, op, "remove", path, null, err);
    try state.returnValues(thread, op.base, op.return_count, &.{.{ .boolean = true }});
}

pub fn dirClose(state: *State, thread: *Thread, op: bytecode.Call) !void {
    const value = runtime.argValue(state, thread, op, 0);
    if (value != .table or value.table.getLiteral("__zlua_fs_dir") == .nil) return state.fail("fs directory expected");
    const dir = value.table;
    try state.setTableRaw(dir, .{ .string = try state.strings.intern("__zlua_fs_dir_closed") }, .{ .boolean = true });
    try state.returnValues(thread, op.base, op.return_count, &.{.{ .boolean = true }});
}

pub fn pathJoin(state: *State, thread: *Thread, op: bytecode.Call) !void {
    var parts = std.ArrayList([]const u8).empty;
    defer parts.deinit(state.allocator);
    for (0..op.arg_count) |index| try parts.append(state.allocator, try state.expectArgumentString(thread, op, "fs.path.join", @intCast(index)));
    const joined = try std.fs.path.join(state.allocator, parts.items);
    defer state.allocator.free(joined);
    try state.returnValues(thread, op.base, op.return_count, &.{.{ .string = try state.strings.intern(joined) }});
}

pub fn pathNormalize(state: *State, thread: *Thread, op: bytecode.Call) !void {
    const path = try state.expectArgumentString(thread, op, "fs.path.normalize", 0);
    const normalized = try normalizeLexical(state.allocator, path);
    defer state.allocator.free(normalized);
    try state.returnValues(thread, op.base, op.return_count, &.{.{ .string = try state.strings.intern(normalized) }});
}

pub fn pathBasename(state: *State, thread: *Thread, op: bytecode.Call) !void {
    try returnPathSlice(state, thread, op, "fs.path.basename", std.fs.path.basename);
}
pub fn pathExtension(state: *State, thread: *Thread, op: bytecode.Call) !void {
    try returnPathSlice(state, thread, op, "fs.path.extension", std.fs.path.extension);
}
pub fn pathStem(state: *State, thread: *Thread, op: bytecode.Call) !void {
    try returnPathSlice(state, thread, op, "fs.path.stem", std.fs.path.stem);
}

pub fn pathDirname(state: *State, thread: *Thread, op: bytecode.Call) !void {
    const path = try state.expectArgumentString(thread, op, "fs.path.dirname", 0);
    const value = if (std.fs.path.dirname(path)) |result| Value{ .string = try state.strings.intern(result) } else Value.nil;
    try state.returnValues(thread, op.base, op.return_count, &.{value});
}

pub fn pathIsAbsolute(state: *State, thread: *Thread, op: bytecode.Call) !void {
    const path = try state.expectArgumentString(thread, op, "fs.path.is_absolute", 0);
    try state.returnValues(thread, op.base, op.return_count, &.{.{ .boolean = std.fs.path.isAbsolute(path) }});
}

pub fn pathRelative(state: *State, thread: *Thread, op: bytecode.Call) !void {
    const from = try state.expectArgumentString(thread, op, "fs.path.relative", 0);
    const to = try state.expectArgumentString(thread, op, "fs.path.relative", 1);
    const relative = try std.fs.path.relative(state.allocator, ".", null, from, to);
    defer state.allocator.free(relative);
    try state.returnValues(thread, op.base, op.return_count, &.{.{ .string = try state.strings.intern(relative) }});
}

fn returnPathSlice(state: *State, thread: *Thread, op: bytecode.Call, name: []const u8, function: *const fn ([]const u8) []const u8) !void {
    const path = try state.expectArgumentString(thread, op, name, 0);
    try state.returnValues(thread, op.base, op.return_count, &.{.{ .string = try state.strings.intern(function(path)) }});
}

fn newIterator(state: *State, kind: []const u8) !Value {
    const iterator = try state.newTableWithHints(0, 12);
    try set(iterator, state, "__zlua_fs_iterator", .{ .string = try state.strings.intern(kind) });
    try set(iterator, state, "next", .{ .native = .fs_iterator_next });
    try set(iterator, state, "close", .{ .native = .fs_iterator_close });
    try set(iterator, state, "skip", .{ .native = .fs_iterator_skip });
    const metatable = try state.newTableWithHints(0, 3);
    try set(metatable, state, "__call", .{ .native = .fs_iterator_next });
    try set(metatable, state, "__close", .{ .native = .fs_iterator_close });
    try set(metatable, state, "__metatable", .{ .string = try state.strings.intern("fs.Iterator") });
    metatable_mod.setTableMetatableRaw(state, iterator.table, metatable.table);
    return iterator;
}

fn expandPending(state: *State, iterator: *Table) !void {
    const pending = iterator.getLiteral("pending_path");
    if (pending != .string) return;
    defer if (state.strings.intern("pending_path")) |key| state.setTableRaw(iterator, .{ .string = key }, .nil) catch {} else |_| {};
    if (truthyField(iterator, "skip_current")) return;
    const depth = integerField(iterator, "pending_depth") orelse 1;
    const entries = io_mod.fsReadDirAlloc(state, pending.string.bytes()) catch |err| return state.failValue(try failureValue(state, "walk", pending.string.bytes(), null, err));
    defer host.deinitDirectoryEntries(state.allocator, entries);
    const queue = try state.expectTable(iterator.getLiteral("queue"));
    var count = integerField(iterator, "count") orelse 0;
    for (entries) |entry| {
        const full = try joinTwo(state, pending.string.bytes(), entry.name);
        defer state.allocator.free(full);
        count += 1;
        try state.setTableRaw(queue, .{ .integer = count }, try entryValue(state, entry, full, @intCast(depth + 1)));
    }
    try state.setTableRaw(iterator, .{ .string = try state.strings.intern("count") }, .{ .integer = count });
}

fn writeBytes(state: *State, path: []const u8, data: []const u8, atomic: bool) !void {
    if (!atomic) return io_mod.fsWriteFile(state, path, data);
    const temporary = try std.fmt.allocPrint(state.allocator, "{s}.zlua-tmp-{x}", .{ path, @intFromPtr(state) });
    defer state.allocator.free(temporary);
    io_mod.fsWriteFile(state, temporary, data) catch |err| return err;
    errdefer io_mod.fsRemovePath(state, temporary, false) catch {};
    try io_mod.fsRenamePath(state, temporary, path);
}

fn copyTree(state: *State, source: []const u8, destination: []const u8, overwrite: bool) !void {
    io_mod.fsMakeDir(state, destination, true) catch |err| if (err != error.PathAlreadyExists) return err;
    const entries = try io_mod.fsReadDirAlloc(state, source);
    defer host.deinitDirectoryEntries(state.allocator, entries);
    for (entries) |entry| {
        const src = try joinTwo(state, source, entry.name);
        defer state.allocator.free(src);
        const dst = try joinTwo(state, destination, entry.name);
        defer state.allocator.free(dst);
        if (entry.kind == .directory) try copyTree(state, src, dst, overwrite) else try io_mod.fsCopyFile(state, src, dst, overwrite);
    }
}

fn statValue(state: *State, stat_value: host.FileStat) !Value {
    const value = try state.newTableWithHints(0, 12);
    try set(value, state, "kind", .{ .string = try state.strings.intern(@tagName(stat_value.kind)) });
    try set(value, state, "size", integerFromUnsigned(stat_value.size));
    try set(value, state, "inode", integerFromUnsigned(stat_value.inode));
    try set(value, state, "nlink", integerFromUnsigned(stat_value.nlink));
    try set(value, state, "permissions", integerFromUnsigned(stat_value.permissions));
    try set(value, state, "readonly", .{ .boolean = (stat_value.permissions & 0o222) == 0 });
    try set(value, state, "block_size", .{ .integer = stat_value.block_size });
    try set(value, state, "mtime", try timestampValue(state, stat_value.mtime));
    try set(value, state, "ctime", try timestampValue(state, stat_value.ctime));
    if (stat_value.atime) |atime| try set(value, state, "atime", try timestampValue(state, atime));
    return value;
}

fn timestampValue(state: *State, timestamp: std.Io.Timestamp) !Value {
    const value = try state.newTableWithHints(0, 2);
    const seconds_i96 = @divFloor(timestamp.nanoseconds, std.time.ns_per_s);
    const nanos_i96 = @mod(timestamp.nanoseconds, std.time.ns_per_s);
    const seconds: i64 = std.math.cast(i64, seconds_i96) orelse if (seconds_i96 < 0) @as(i64, std.math.minInt(i64)) else @as(i64, std.math.maxInt(i64));
    try set(value, state, "seconds", .{ .integer = seconds });
    try set(value, state, "nanoseconds", .{ .integer = @intCast(nanos_i96) });
    return value;
}

fn entryValue(state: *State, entry: host.DirectoryEntry, path: []const u8, depth: ?usize) !Value {
    const value = try state.newTableWithHints(0, 5);
    try set(value, state, "name", .{ .string = try state.strings.intern(entry.name) });
    try set(value, state, "path", .{ .string = try state.strings.intern(path) });
    try set(value, state, "kind", .{ .string = try state.strings.intern(@tagName(entry.kind)) });
    try set(value, state, "inode", integerFromUnsigned(entry.inode));
    if (depth) |actual| try set(value, state, "depth", .{ .integer = @intCast(actual) });
    return value;
}

fn failureValue(state: *State, operation: []const u8, path: []const u8, destination: ?[]const u8, err: anyerror) !Value {
    const value = try state.newTableWithHints(0, 7);
    const system = @errorName(err);
    const code = normalizedErrorCode(system);
    const message = if (destination) |dest|
        try std.fmt.allocPrint(state.allocator, "{s} '{s}' -> '{s}': {s}", .{ operation, path, dest, system })
    else
        try std.fmt.allocPrint(state.allocator, "{s} '{s}': {s}", .{ operation, path, system });
    defer state.allocator.free(message);
    try set(value, state, "code", .{ .string = try state.strings.intern(code) });
    try set(value, state, "system", .{ .string = try state.strings.intern(system) });
    try set(value, state, "operation", .{ .string = try state.strings.intern(operation) });
    try set(value, state, "path", .{ .string = try state.strings.intern(path) });
    if (destination) |dest| try set(value, state, "destination", .{ .string = try state.strings.intern(dest) });
    try set(value, state, "message", .{ .string = try state.strings.intern(message) });
    const metatable = try state.newTableWithHints(0, 2);
    try set(metatable, state, "__tostring", .{ .native = .fs_error_tostring });
    try set(metatable, state, "__metatable", .{ .string = try state.strings.intern("fs.Error") });
    metatable_mod.setTableMetatableRaw(state, value.table, metatable.table);
    return value;
}

fn returnFailure(state: *State, thread: *Thread, op: bytecode.Call, operation: []const u8, path: []const u8, destination: ?[]const u8, err: anyerror) !void {
    if (err == error.OutOfMemory) return err;
    try state.returnValues(thread, op.base, op.return_count, &.{ .nil, try failureValue(state, operation, path, destination, err) });
}

fn normalizedErrorCode(name: []const u8) []const u8 {
    if (std.mem.eql(u8, name, "FileNotFound")) return "not_found";
    if (std.mem.eql(u8, name, "PathAlreadyExists")) return "already_exists";
    if (std.mem.eql(u8, name, "NotDir")) return "not_directory";
    if (std.mem.eql(u8, name, "IsDir")) return "is_directory";
    if (std.mem.eql(u8, name, "AccessDenied") or std.mem.eql(u8, name, "PermissionDenied")) return "access_denied";
    if (std.mem.eql(u8, name, "FilesystemReadOnly") or std.mem.eql(u8, name, "ReadOnlyFileSystem")) return "read_only";
    if (std.mem.eql(u8, name, "NoSpaceLeft") or std.mem.eql(u8, name, "QuotaExceeded")) return "no_space";
    if (std.mem.eql(u8, name, "InvalidPath") or std.mem.eql(u8, name, "BadPathName")) return "invalid_path";
    if (std.mem.eql(u8, name, "PathTooLong") or std.mem.eql(u8, name, "NameTooLong")) return "name_too_long";
    if (std.mem.eql(u8, name, "SymLinkLoop")) return "symlink_loop";
    if (std.mem.eql(u8, name, "CrossDeviceLink")) return "cross_device";
    if (std.mem.eql(u8, name, "Canceled")) return "canceled";
    if (std.mem.eql(u8, name, "OperationUnsupported") or std.mem.eql(u8, name, "FilesystemDisabled")) return "unsupported";
    return "io";
}

fn expectFsFile(state: *State, value: Value) !*const io_lib.File {
    if (io_lib.checkedFile(state, value) == null) return state.fail("fs file expected");
    return io_lib.fileOf(value).?;
}

fn expectIteratorTable(state: *State, value: Value) !*Table {
    const table = if (value == .table) value.table else if (value == .gmatch_iterator) value.gmatch_iterator else return state.fail("fs iterator expected");
    if (table.getLiteral("__zlua_fs_iterator") == .nil) return state.fail("fs iterator expected");
    return table;
}

fn expectDir(state: *State, value: Value) !*Table {
    if (value != .table or value.table.getLiteral("__zlua_fs_dir") == .nil) return state.fail("fs directory expected");
    if (truthyField(value.table, "__zlua_fs_dir_closed")) return state.fail("closed fs directory");
    return value.table;
}

fn dirPath(state: *State, dir: *Table) ![]const u8 {
    return state.expectString(dir.getLiteral("__zlua_fs_dir_path"));
}

fn optionTable(state: *State, thread: *Thread, op: bytecode.Call, function_name: []const u8, index: u32) !?*Table {
    if (op.arg_count <= index or runtime.argValue(state, thread, op, index) == .nil) return null;
    const value = runtime.argValue(state, thread, op, index);
    if (value != .table) return state.failArgumentType(function_name, index + 1, "table", value);
    return value.table;
}

fn boolOption(state: *State, table: *Table, operation: []const u8, name: []const u8, default: bool) !bool {
    const value = table.getBytes(name);
    if (value == .nil) return default;
    if (value != .boolean) return state.failArgumentMessage(operation, 2, "boolean option expected");
    return value.boolean;
}

fn integerOption(state: *State, table: *Table, operation: []const u8, name: []const u8, default: usize) !usize {
    const value = table.getBytes(name);
    if (value == .nil) return default;
    const integer = runtime.toInteger(value) orelse return state.failArgumentMessage(operation, 2, "integer option expected");
    if (integer < 0) return state.failArgumentMessage(operation, 2, "non-negative option expected");
    return std.math.cast(usize, integer) orelse state.failArgumentMessage(operation, 2, "option out of range");
}

fn normalizeLexical(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    if (path.len == 0) return allocator.dupe(u8, ".");
    const absolute = std.fs.path.isAbsolute(path);
    var parts = std.ArrayList([]const u8).empty;
    defer parts.deinit(allocator);
    var iterator = std.mem.tokenizeAny(u8, path, "/\\");
    while (iterator.next()) |part| {
        if (std.mem.eql(u8, part, ".")) continue;
        if (std.mem.eql(u8, part, "..")) {
            if (parts.items.len != 0 and !std.mem.eql(u8, parts.items[parts.items.len - 1], "..")) _ = parts.pop() else if (!absolute) try parts.append(allocator, part);
        } else try parts.append(allocator, part);
    }
    var out = std.ArrayList(u8).empty;
    errdefer out.deinit(allocator);
    if (absolute) try out.append(allocator, std.fs.path.sep);
    for (parts.items, 0..) |part, index| {
        if (index != 0) try out.append(allocator, std.fs.path.sep);
        try out.appendSlice(allocator, part);
    }
    if (out.items.len == 0) try out.append(allocator, if (absolute) std.fs.path.sep else '.');
    return out.toOwnedSlice(allocator);
}

fn joinTwo(state: *State, parent: []const u8, child: []const u8) ![]u8 {
    if (parent.len == 0 or std.mem.eql(u8, parent, ".")) return state.allocator.dupe(u8, child);
    // These capabilities validate '/'-separated paths on every OS; native joins would add backslashes.
    return switch (state.options.filesystem) {
        .memory, .memory_rw, .host_dir => std.fmt.allocPrint(state.allocator, "{s}/{s}", .{ std.mem.trimEnd(u8, parent, "/"), std.mem.trimStart(u8, child, "/") }),
        else => std.fs.path.join(state.allocator, &.{ parent, child }),
    };
}

fn set(table_value: Value, state: *State, name: []const u8, value: Value) !void {
    try state.setTableRaw(table_value.table, .{ .string = try state.strings.intern(name) }, value);
}

fn truthyField(table: *Table, name: []const u8) bool {
    const value = table.getBytes(name);
    return value == .boolean and value.boolean;
}

fn integerField(table: *Table, name: []const u8) ?i64 {
    return runtime.toInteger(table.getBytes(name));
}
fn integerFromUnsigned(value: u64) Value {
    return .{ .integer = @intCast(@min(value, @as(u64, std.math.maxInt(i64)))) };
}
fn lessEntry(_: void, left: host.DirectoryEntry, right: host.DirectoryEntry) bool {
    return std.mem.lessThan(u8, left.name, right.name);
}
