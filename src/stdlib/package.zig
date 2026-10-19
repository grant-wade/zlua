const std = @import("std");
const compile = @import("../compile.zig");
const stdlib = @import("../stdlib.zig");
const runtime = @import("../runtime.zig");
const io_lib = @import("io.zig");
const call_mod = @import("../runtime/call.zig");
const io_mod = @import("../runtime/io.zig");
const index_mod = @import("../runtime/index.zig");
const load_mod = @import("../runtime/load.zig");
const value_mod = @import("../runtime/value.zig");

const bytecode = compile.bytecode;
const State = runtime.State;
const Thread = runtime.Thread;
const Value = runtime.Value;
const RuntimeError = runtime.RuntimeError;

pub fn loadfile(state: *State, thread: *Thread, op: bytecode.Call) !void {
    const path = try optionalPath(state, thread, op, "loadfile");
    const mode = if (op.arg_count >= 2 and runtime.argValue(state, thread, op, 1) == .string) runtime.argValue(state, thread, op, 1).string.bytes() else "bt";
    if (invalidLoadMode(mode)) return state.failArgumentMessage("loadfile", 2, "invalid mode");
    const environment = if (op.arg_count >= 3) runtime.argValue(state, thread, op, 2) else globalEnvironment(state);

    const closure = loadChunkFile(state, path, mode, environment) catch |err| switch (err) {
        error.RuntimeError => {
            const error_value = state.currentErrorValue();
            const message: Value = if (error_value == .string) error_value else .{ .string = try state.strings.intern("cannot load source") };
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
    const closure = try loadChunkFile(state, path, "bt", globalEnvironment(state));
    const values = try call_mod.callCollect(state, thread, closure, &.{});
    defer state.allocator.free(values);
    const result_values = if (path != null and values.len >= 2 and values[0] == .native and values[0].native == .dofile and values[1] == .string and values[1].string.eqlBytes(path.?)) values[2..] else values;
    try state.returnValues(thread, op.base, op.return_count, result_values);
}

pub fn require(state: *State, thread: *Thread, op: bytecode.Call) !void {
    const name_string = try state.expectArgumentStringObject(thread, op, "require", 0);
    const name_key = Value{ .string = name_string };
    const loaded = Value{ .table = try packageTable(state, .package_loaded) };

    const cached = try index_mod.getTableFromThread(state, thread, loaded, name_key);
    if (runtime.truthy(cached)) {
        try state.returnValues(thread, op.base, op.return_count, &.{cached});
        return;
    }

    var rooted = RequireRoots.initFill(.nil);
    rooted.set(.loaded, loaded);
    var roots: runtime.ValueRoots = undefined;
    state.pushValueRoots(&roots, &rooted.values);
    defer state.popValueRoots(&roots);

    try findLoader(state, thread, name_string.bytes(), name_key, &rooted);
    const values = try call_mod.callCollect(state, thread, rooted.get(.loader), &.{ name_key, rooted.get(.loader_data) });
    rooted.set(.module, if (values.len > 0) values[0] else .nil);
    state.allocator.free(values);
    if (rooted.get(.module) != .nil) try index_mod.setTableFromThread(state, thread, loaded, name_key, rooted.get(.module));
    rooted.set(.module, try index_mod.getTableFromThread(state, thread, loaded, name_key));
    if (rooted.get(.module) == .nil) {
        rooted.set(.module, .{ .boolean = true });
        try index_mod.setTableFromThread(state, thread, loaded, name_key, rooted.get(.module));
    }
    try state.returnValues(thread, op.base, op.return_count, &.{ rooted.get(.module), rooted.get(.loader_data) });
}

/// Values `require` keeps rooted while searchers and the loader run.
const RequireRoots = std.EnumArray(enum { loaded, searchers, loader, loader_data, module }, Value);

fn findLoader(state: *State, thread: *Thread, name: []const u8, name_key: Value, rooted: *RequireRoots) !void {
    const searchers = (try packageTable(state, .package)).getLiteral("searchers");
    if (searchers != .table) return state.fail("'package.searchers' must be a table");
    rooted.set(.searchers, searchers);

    var message = std.ArrayList(u8).empty;
    defer message.deinit(state.allocator);
    var index: i64 = 1;
    while (true) : (index += 1) {
        const searcher = searchers.table.get(.{ .integer = index });
        if (searcher == .nil) {
            const text = try std.fmt.allocPrint(state.allocator, "module '{s}' not found:{s}", .{ name, message.items });
            defer state.allocator.free(text);
            return state.fail(text);
        }
        const values = try call_mod.callCollect(state, thread, searcher, &.{name_key});
        defer state.allocator.free(values);
        const first = if (values.len > 0) values[0] else .nil;
        if (value_mod.functionLike(first)) {
            rooted.set(.loader, first);
            rooted.set(.loader_data, if (values.len > 1) values[1] else .nil);
            return;
        }
        if (value_mod.luaStringLike(first)) {
            try message.appendSlice(state.allocator, "\n\t");
            try runtime.appendLuaString(state.allocator, &message, first);
        }
    }
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
        try state.returnValues(thread, op.base, op.return_count, &.{.{ .string = try state.strings.intern(found) }});
        return;
    }

    const message = try searchPathError(state, name, path, sep, rep);
    defer state.allocator.free(message);
    try state.returnValues(thread, op.base, op.return_count, &.{ .nil, .{ .string = try state.strings.intern(message) } });
}

/// Native C modules are not supported, matching a Lua build without dynamic libraries.
pub fn loadlib(state: *State, thread: *Thread, op: bytecode.Call) !void {
    _ = try state.expectArgumentString(thread, op, "package.loadlib", 0);
    _ = try state.expectArgumentString(thread, op, "package.loadlib", 1);
    try state.returnValues(thread, op.base, op.return_count, &.{
        .nil,
        .{ .string = try state.strings.intern("dynamic libraries not enabled; check your Lua installation") },
        .{ .string = try state.strings.intern("absent") },
    });
}

pub fn searcherPreload(state: *State, thread: *Thread, op: bytecode.Call) !void {
    const name = try state.expectArgumentStringObject(thread, op, "package.searchers preload", 0);
    const preload = Value{ .table = try packageTable(state, .package_preload) };
    const loader = try index_mod.getTableFromThread(state, thread, preload, .{ .string = name });
    if (loader == .nil) {
        const message = try std.fmt.allocPrint(state.allocator, "no field package.preload['{s}']", .{name.bytes()});
        defer state.allocator.free(message);
        try state.returnValues(thread, op.base, op.return_count, &.{.{ .string = try state.strings.intern(message) }});
    } else {
        try state.returnValues(thread, op.base, op.return_count, &.{ loader, .{ .string = try state.strings.intern(":preload:") } });
    }
}

pub fn searcherLua(state: *State, thread: *Thread, op: bytecode.Call) !void {
    const name = try state.expectArgumentString(thread, op, "package.searchers Lua", 0);
    const filename = try findFile(state, thread, op, name, "path") orelse return;
    defer state.allocator.free(filename);
    const loader = loadChunkFile(state, filename, "bt", globalEnvironment(state)) catch |err| switch (err) {
        error.RuntimeError => {
            var detail = std.ArrayList(u8).empty;
            defer detail.deinit(state.allocator);
            const error_value = state.currentErrorValue();
            if (value_mod.luaStringLike(error_value)) try runtime.appendLuaString(state.allocator, &detail, error_value);
            return failLoadingModule(state, name, filename, detail.items);
        },
        else => return err,
    };
    try state.returnValues(thread, op.base, op.return_count, &.{ loader, .{ .string = try state.strings.intern(filename) } });
}

pub fn searcherC(state: *State, thread: *Thread, op: bytecode.Call) !void {
    const name = try state.expectArgumentString(thread, op, "package.searchers C", 0);
    const filename = try findFile(state, thread, op, name, "cpath") orelse return;
    defer state.allocator.free(filename);
    return failLoadingModule(state, name, filename, dynamic_libraries_message);
}

pub fn searcherCroot(state: *State, thread: *Thread, op: bytecode.Call) !void {
    const name = try state.expectArgumentString(thread, op, "package.searchers Croot", 0);
    const dot = std.mem.indexOfScalar(u8, name, '.') orelse return state.returnValues(thread, op.base, op.return_count, &.{});
    const filename = try findFile(state, thread, op, name[0..dot], "cpath") orelse return;
    defer state.allocator.free(filename);
    return failLoadingModule(state, name, filename, dynamic_libraries_message);
}

const dynamic_libraries_message = "dynamic libraries not enabled; check your Lua installation";

/// Returns the owned path of the first readable file, or null after returning the not-found message to Lua.
fn findFile(state: *State, thread: *Thread, op: bytecode.Call, name: []const u8, comptime field: []const u8) !?[]const u8 {
    const path_value = (try packageTable(state, .package)).getLiteral(field);
    if (!value_mod.luaStringLike(path_value)) return state.fail("'package." ++ field ++ "' must be a string");
    var path = std.ArrayList(u8).empty;
    defer path.deinit(state.allocator);
    try runtime.appendLuaString(state.allocator, &path, path_value);

    if (try searchPath(state, name, path.items, ".", "/")) |found| return found;
    const message = try searchPathError(state, name, path.items, ".", "/");
    defer state.allocator.free(message);
    try state.returnValues(thread, op.base, op.return_count, &.{.{ .string = try state.strings.intern(message) }});
    return null;
}

fn failLoadingModule(state: *State, name: []const u8, filename: []const u8, detail: []const u8) RuntimeError {
    const message = std.fmt.allocPrint(state.allocator, "error loading module '{s}' from file '{s}':\n\t{s}", .{ name, filename, detail }) catch return error.OutOfMemory;
    defer state.allocator.free(message);
    return state.fail(message);
}

fn globalEnvironment(state: *State) Value {
    return if (state.global_table) |table| Value{ .table = table } else state.getGlobal("_G");
}

fn packageTable(state: *State, which: stdlib.LibraryTable) !*runtime.Table {
    return state.library_tables.get(which) orelse state.fail("package library is not open");
}

fn searchPath(state: *State, name: []const u8, path: []const u8, sep: []const u8, rep: []const u8) !?[]const u8 {
    const candidates = try pathCandidates(state, name, path, sep, rep);
    defer state.allocator.free(candidates);

    var iterator = std.mem.splitScalar(u8, candidates, ';');
    while (iterator.next()) |candidate| {
        const contents = io_mod.readFileRaw(state, candidate) catch |err| {
            if (err == error.OutOfMemory) return error.OutOfMemory;
            continue;
        };
        state.allocator.free(contents);
        return try state.allocator.dupe(u8, candidate);
    }
    return null;
}

fn searchPathError(state: *State, name: []const u8, path: []const u8, sep: []const u8, rep: []const u8) ![]u8 {
    const candidates = try pathCandidates(state, name, path, sep, rep);
    defer state.allocator.free(candidates);

    var out = std.ArrayList(u8).empty;
    errdefer out.deinit(state.allocator);
    var iterator = std.mem.splitScalar(u8, candidates, ';');
    var first = true;
    while (iterator.next()) |candidate| : (first = false) {
        if (!first) try out.appendSlice(state.allocator, "\n\t");
        try runtime.appendFmt(state.allocator, &out, "no file '{s}'", .{candidate});
    }
    return out.toOwnedSlice(state.allocator);
}

/// Returns `path` with every `?` replaced by `name` after its `sep` occurrences become `rep`.
fn pathCandidates(state: *State, name: []const u8, path: []const u8, sep: []const u8, rep: []const u8) ![]u8 {
    const module_path = try modulePath(state, name, sep, rep);
    defer state.allocator.free(module_path);
    return std.mem.replaceOwned(u8, state.allocator, path, "?", module_path);
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
