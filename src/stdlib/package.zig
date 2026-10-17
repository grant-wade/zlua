const std = @import("std");
const compile = @import("../compile.zig");
const runtime = @import("../runtime.zig");
const io_lib = @import("io.zig");
const call_mod = @import("../runtime/call.zig");
const io_mod = @import("../runtime/io.zig");
const load_mod = @import("../runtime/load.zig");

const bytecode = compile.bytecode;
const State = runtime.State;
const Thread = runtime.Thread;
const Value = runtime.Value;

pub fn loadfile(state: *State, thread: *Thread, op: bytecode.Call) !void {
    const path = try optionalPath(state, thread, op, "loadfile");
    const mode = if (op.arg_count >= 2 and runtime.argValue(state, thread, op, 1) == .string) runtime.argValue(state, thread, op, 1).string else "bt";
    if (invalidLoadMode(mode)) return state.failArgumentMessage("loadfile", 2, "invalid mode");
    const environment = if (op.arg_count >= 3) runtime.argValue(state, thread, op, 2) else if (state.global_table) |table| Value{ .table = table } else state.getGlobal("_G");

    const closure = loadChunkFile(state, path, mode, environment) catch |err| switch (err) {
        error.RuntimeError => {
            const error_value = state.currentErrorValue();
            const message: Value = if (error_value == .string) error_value else .{ .string = try state.intern("cannot load source") };
            try state.returnValues(thread, op.base, op.return_count, &.{ .nil, message });
            return;
        },
        else => return err,
    };
    try state.returnValues(thread, op.base, op.return_count, &.{closure});
}

fn optionalPath(state: *State, thread: *Thread, op: bytecode.Call, function_name: []const u8) !?[]const u8 {
    if (op.arg_count == 0 or runtime.argValue(state, thread, op, 0) == .nil) return null;
    return try state.expectArgumentString(thread, op, function_name, 0);
}

fn loadChunkFile(state: *State, path: ?[]const u8, mode: []const u8, environment: Value) !Value {
    const source = if (path) |name| try io_mod.readFileAlloc(state, name) else try io_lib.readAllStdin(state);
    var keep_source = false;
    defer if (!keep_source) state.allocator.free(source);

    const chunk = fileChunkStart(source);
    const binary = looksLikeBinaryChunk(chunk);
    if (binary and std.mem.indexOfScalar(u8, mode, 'b') == null) return state.fail("attempt to load a binary chunk");
    if (!binary and std.mem.indexOfScalar(u8, mode, 't') == null) return state.fail("attempt to load a text chunk");
    if (binary) return load_mod.loadBinaryDump(state, chunk, environment);

    prepareTextFileSource(@constCast(source));
    const source_name = if (path) |name| try std.fmt.allocPrint(state.allocator, "@{s}", .{name}) else try state.allocator.dupe(u8, "=stdin");
    defer state.allocator.free(source_name);
    const closure = try load_mod.loadSourceAsClosureNamedEnv(state, source, source_name, environment);
    try state.registerAllocation("source_allocations", source);
    keep_source = true;
    return closure;
}

fn invalidLoadMode(mode: []const u8) bool {
    if (mode.len == 0) return true;
    for (mode) |byte| if (byte != 'b' and byte != 't') return true;
    return false;
}

fn looksLikeBinaryChunk(source: []const u8) bool {
    return (source.len > 0 and source[0] == 0x1b) or
        std.mem.startsWith(u8, source, runtime.binary_chunk_signature) or
        (source.len > 0 and std.mem.startsWith(u8, runtime.binary_chunk_signature, source));
}

fn fileChunkStart(source: []const u8) []const u8 {
    var index = initialBomLen(source);
    if (index < source.len and source[index] == '#') {
        while (index < source.len and source[index] != '\n') index += 1;
        if (index < source.len) index += 1;
    }
    return source[index..];
}

fn prepareTextFileSource(source: []u8) void {
    var index = initialBomLen(source);
    for (source[0..index]) |*byte| byte.* = ' ';
    if (index < source.len and source[index] == '#') {
        while (index < source.len and source[index] != '\n') : (index += 1) {
            source[index] = ' ';
        }
    }
}

fn initialBomLen(source: []const u8) usize {
    return if (std.mem.startsWith(u8, source, "\xEF\xBB\xBF")) 3 else 0;
}

pub fn dofile(state: *State, thread: *Thread, op: bytecode.Call) !void {
    const path = try optionalPath(state, thread, op, "dofile");
    const environment = if (state.global_table) |table| Value{ .table = table } else state.getGlobal("_G");
    const closure = try loadChunkFile(state, path, "bt", environment);
    const values = try call_mod.callCollect(state, thread, closure, &.{});
    defer state.allocator.free(values);
    const result_values = if (path != null and values.len >= 2 and values[0] == .native and values[0].native == .dofile and values[1] == .string and std.mem.eql(u8, values[1].string, path.?)) values[2..] else values;
    try state.returnValues(thread, op.base, op.return_count, result_values);
}

pub fn require(state: *State, thread: *Thread, op: bytecode.Call) !void {
    const name = try state.expectArgumentString(thread, op, "require", 0);
    const package = try packageTable(state);
    const loaded = try state.expectTable(package.get(.{ .string = try state.intern("loaded") }));
    const preload = try state.expectTable(package.get(.{ .string = try state.intern("preload") }));
    const name_key = Value{ .string = try state.intern(name) };

    const cached = loaded.get(name_key);
    if (cached != .nil and !(cached == .boolean and !cached.boolean)) {
        try state.returnValues(thread, op.base, op.return_count, &.{cached});
        return;
    }

    var loader = preload.get(name_key);
    var loader_data: Value = .nil;
    if (loader != .nil) {
        loader_data = .{ .string = try state.intern(":preload:") };
    } else {
        const path_value = package.get(.{ .string = try state.intern("path") });
        if (path_value != .string) return state.failArgumentType("require", 1, "package.path string", path_value);
        const path = path_value.string;
        const found = try searchPath(state, name, path, ".", "/") orelse {
            const message = try moduleNotFoundMessage(state, name, package, path);
            return state.fail(message);
        };
        defer state.allocator.free(found);
        loader = try load_mod.loadFileAsClosure(state, found);
        loader_data = .{ .string = try state.intern(found) };
    }

    const loader_data_root = try state.rootValue(loader_data);
    defer state.unrootValue(loader_data_root);
    const values = try call_mod.callCollect(state, thread, loader, &.{ name_key, loader_data });
    defer state.allocator.free(values);
    const module_value = if (values.len == 0 or values[0] == .nil) Value{ .boolean = true } else values[0];
    try state.setTableRaw(loaded, name_key, module_value);
    try state.returnValues(thread, op.base, op.return_count, &.{ module_value, loader_data });
}

pub fn searchpath(state: *State, thread: *Thread, op: bytecode.Call) !void {
    const name = try state.expectArgumentString(thread, op, "package.searchpath", 0);
    const path = try state.expectArgumentString(thread, op, "package.searchpath", 1);
    const sep_value = runtime.argValue(state, thread, op, 2);
    const rep_value = runtime.argValue(state, thread, op, 3);
    const sep = if (sep_value == .nil) "." else try state.expectArgumentString(thread, op, "package.searchpath", 2);
    const rep = if (rep_value == .nil) "/" else try state.expectArgumentString(thread, op, "package.searchpath", 3);

    if (try searchPath(state, name, path, sep, rep)) |found| {
        defer state.allocator.free(found);
        try state.returnValues(thread, op.base, op.return_count, &.{.{ .string = try state.intern(found) }});
        return;
    }

    const message = try searchPathError(state, name, path, sep, rep);
    defer state.allocator.free(message);
    try state.returnValues(thread, op.base, op.return_count, &.{ .nil, .{ .string = try state.intern(message) } });
}

/// Native C modules are not supported, matching a Lua build without dynamic libraries.
pub fn loadlib(state: *State, thread: *Thread, op: bytecode.Call) !void {
    _ = try state.expectArgumentString(thread, op, "package.loadlib", 0);
    _ = try state.expectArgumentString(thread, op, "package.loadlib", 1);
    try state.returnValues(thread, op.base, op.return_count, &.{
        .nil,
        .{ .string = try state.intern("dynamic libraries not enabled; check your Lua installation") },
        .{ .string = try state.intern("absent") },
    });
}

pub fn searcherPreload(state: *State, thread: *Thread, op: bytecode.Call) !void {
    const name = try state.expectArgumentString(thread, op, "package.searchers preload", 0);
    const preload = try state.expectTable((try packageTable(state)).get(.{ .string = try state.intern("preload") }));
    const loader = preload.get(.{ .string = try state.intern(name) });
    if (loader == .nil) {
        try state.returnValues(thread, op.base, op.return_count, &.{.{ .string = try state.intern("no field package.preload") }});
    } else {
        try state.returnValues(thread, op.base, op.return_count, &.{ loader, .{ .string = try state.intern(":preload:") } });
    }
}

pub fn searcherLua(state: *State, thread: *Thread, op: bytecode.Call) !void {
    const name = try state.expectArgumentString(thread, op, "package.searchers Lua", 0);
    const package = try packageTable(state);
    const path = try state.expectString(package.get(.{ .string = try state.intern("path") }));
    const found = try searchPath(state, name, path, ".", "/") orelse {
        try state.returnValues(thread, op.base, op.return_count, &.{.{ .string = try state.intern("no matching file") }});
        return;
    };
    defer state.allocator.free(found);
    const loader = load_mod.loadFileAsClosure(state, found) catch {
        try state.returnValues(thread, op.base, op.return_count, &.{.{ .string = try state.intern("cannot load file") }});
        return;
    };
    try state.returnValues(thread, op.base, op.return_count, &.{ loader, .{ .string = try state.intern(found) } });
}

fn packageTable(state: *State) !*runtime.Table {
    return state.expectTable(state.getGlobal("package"));
}

fn searchPath(state: *State, name: []const u8, path: []const u8, sep: []const u8, rep: []const u8) !?[]const u8 {
    const module_path = try modulePath(state, name, sep, rep);
    defer state.allocator.free(module_path);

    var iterator = std.mem.splitScalar(u8, path, ';');
    while (iterator.next()) |template| {
        var candidate = try applyTemplate(state.allocator, template, module_path);
        defer candidate.deinit(state.allocator);
        const contents = io_mod.readFileRaw(state, candidate.items) catch |err| {
            if (err == error.OutOfMemory) return error.OutOfMemory;
            continue;
        };
        state.allocator.free(contents);
        const found = try state.allocator.dupe(u8, candidate.items);
        return found;
    }
    return null;
}

fn moduleNotFoundMessage(state: *State, name: []const u8, package: *runtime.Table, path: []const u8) ![]const u8 {
    var out = std.ArrayList(u8).empty;
    defer out.deinit(state.allocator);
    try runtime.appendFmt(state.allocator, &out, "module '{s}' not found:\n\tno field package.preload['{s}']", .{ name, name });
    try appendSearchPathError(state, &out, name, path, ".", "/");
    const cpath_value = package.get(.{ .string = try state.intern("cpath") });
    if (cpath_value == .string) try appendSearchPathError(state, &out, name, cpath_value.string, ".", "/");
    return state.intern(out.items);
}

fn searchPathError(state: *State, name: []const u8, path: []const u8, sep: []const u8, rep: []const u8) ![]u8 {
    var out = std.ArrayList(u8).empty;
    errdefer out.deinit(state.allocator);
    try appendSearchPathError(state, &out, name, path, sep, rep);
    return out.toOwnedSlice(state.allocator);
}

fn appendSearchPathError(state: *State, out: *std.ArrayList(u8), name: []const u8, path: []const u8, sep: []const u8, rep: []const u8) !void {
    const module_path = try modulePath(state, name, sep, rep);
    defer state.allocator.free(module_path);

    var iterator = std.mem.splitScalar(u8, path, ';');
    while (iterator.next()) |template| {
        var candidate = try applyTemplate(state.allocator, template, module_path);
        defer candidate.deinit(state.allocator);
        try runtime.appendFmt(state.allocator, out, "\n\tno file '{s}'", .{candidate.items});
    }
}

fn modulePath(state: *State, name: []const u8, sep: []const u8, rep: []const u8) ![]u8 {
    if (sep.len == 0) return state.allocator.dupe(u8, name);
    var out = std.ArrayList(u8).empty;
    errdefer out.deinit(state.allocator);
    var rest = name;
    while (std.mem.indexOf(u8, rest, sep)) |index| {
        try out.appendSlice(state.allocator, rest[0..index]);
        try out.appendSlice(state.allocator, rep);
        rest = rest[index + sep.len ..];
    }
    try out.appendSlice(state.allocator, rest);
    return out.toOwnedSlice(state.allocator);
}

fn applyTemplate(allocator: std.mem.Allocator, template: []const u8, module_path: []const u8) !std.ArrayList(u8) {
    var candidate = std.ArrayList(u8).empty;
    errdefer candidate.deinit(allocator);
    for (template) |byte| {
        if (byte == '?') {
            try candidate.appendSlice(allocator, module_path);
        } else {
            try candidate.append(allocator, byte);
        }
    }
    return candidate;
}
