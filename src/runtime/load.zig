const std = @import("std");
const compile = @import("../compile.zig");
const errors = @import("../errors.zig");
const frontend = @import("../frontend.zig");
const chunk_mod = @import("chunk.zig");
const io_mod = @import("io.zig");
const state_mod = @import("state.zig");
const types = @import("types.zig");
const value_mod = @import("value.zig");
const vm_mod = @import("vm.zig");

const State = state_mod.State;
const proto_mod = compile.proto;
const RuntimeError = types.RuntimeError;
const Value = types.Value;
const BinaryChunkReader = chunk_mod.BinaryChunkReader;
const binary_chunk_payload_magic = chunk_mod.binary_chunk_payload_magic;
const appendBinaryChunkHeader = chunk_mod.appendBinaryChunkHeader;
const hexValue = value_mod.hexValue;
const Closure = types.Closure;
const Upvalue = types.Upvalue;
const Thread = types.Thread;

pub fn loadSourceAsClosure(self: *State, source: []const u8) !Value {
    return loadSourceAsClosureNamed(self, source, null);
}

pub fn loadSourceAsClosureNamed(self: *State, source: []const u8, source_name: ?[]const u8) !Value {
    return loadSourceAsClosureNamedEnv(self, source, source_name, defaultEnvironment(self));
}

pub fn loadSourceAsClosureNamedEnv(self: *State, source: []const u8, source_name: ?[]const u8, environment: Value) !Value {
    var diagnostic: ?errors.Diagnostic = null;
    var tree = frontend.parseWithDiagnostic(self.allocator, source, &diagnostic) catch |err| switch (err) {
        error.OutOfMemory => return err,
        else => return failLoadDiagnostic(self, source_name, source, diagnostic, "cannot load source"),
    };
    defer tree.deinit();

    compile.resolver.resolveWithDiagnostic(self.allocator, &tree, &diagnostic) catch |err| switch (err) {
        error.OutOfMemory => return err,
        else => return failLoadDiagnostic(self, source_name, source, diagnostic, "cannot resolve source"),
    };
    const proto = try self.allocator.create(proto_mod.Proto);
    errdefer self.allocator.destroy(proto);
    proto.* = compile.compileWithDiagnostic(self.allocator, &tree, &diagnostic) catch |err| switch (err) {
        error.OutOfMemory => return err,
        else => return failLoadDiagnostic(self, source_name, source, diagnostic, "cannot compile source"),
    };
    errdefer proto.deinit();
    if (source_name) |name| try setProtoSourceName(proto, name);
    try value_mod.prepareProtoTree(proto);
    try self.registerAllocation("proto_allocations", proto);
    errdefer {
        const removed = self.proto_allocations.pop().?;
        if (self.rollback) |journal| journal.freed(@intFromPtr(removed));
    }
    const closure = try newRootClosureWithEnv(self, proto, environment);
    self.gc.notePrototype(proto);
    return .{ .closure = closure };
}

pub fn loadBinaryDump(self: *State, source: []const u8, environment: Value) !Value {
    var header = std.ArrayList(u8).empty;
    defer header.deinit(self.allocator);
    try appendBinaryChunkHeader(self.allocator, &header);

    if (source.len < header.items.len) return self.fail("truncated binary chunk");
    if (!std.mem.eql(u8, source[0..header.items.len], header.items)) return self.fail("bad binary chunk");

    var pos = header.items.len;
    if (source.len < pos + binary_chunk_payload_magic.len) return self.fail("truncated binary chunk");
    if (!std.mem.eql(u8, source[pos .. pos + binary_chunk_payload_magic.len], binary_chunk_payload_magic)) return self.fail("unsupported PUC Lua binary chunk");
    pos += binary_chunk_payload_magic.len;

    var reader = BinaryChunkReader{ .state = self, .source = source, .pos = pos };
    const stripped_debug = try reader.readBool();
    const proto = try reader.readProto(null);
    errdefer {
        proto.deinit();
        self.allocator.destroy(proto);
    }
    if (reader.pos != source.len) return self.fail("bad binary chunk");
    try value_mod.prepareProtoTree(proto);
    try self.registerAllocation("proto_allocations", proto);
    errdefer {
        _ = self.proto_allocations.pop();
        if (self.rollback) |journal| journal.freed(@intFromPtr(proto));
    }
    const closure = try newDumpedClosure(self, proto, environment, stripped_debug);
    self.gc.notePrototype(proto);
    return closure;
}

pub fn loadFileAsClosure(self: *State, path: []const u8) !Value {
    return loadFileAsClosureNamed(self, path, null);
}

fn loadFileAsClosureNamed(self: *State, path: []const u8, source_name: ?[]const u8) !Value {
    const source = try io_mod.readFileAlloc(self, path);
    errdefer self.allocator.free(source);
    const allocated_source_name = if (source_name == null) try std.fmt.allocPrint(self.allocator, "@{s}", .{path}) else null;
    defer if (allocated_source_name) |name| self.allocator.free(name);
    const closure = try loadSourceAsClosureNamed(self, source, source_name orelse allocated_source_name.?);
    try self.registerAllocation("source_allocations", source);
    return closure;
}

pub fn setRootThreadArgs(self: *State, thread: *Thread, args: []const Value) !void {
    const proto = thread.frames.items[0].proto;
    const param_count = @min(args.len, proto.param_count);
    for (args[0..param_count], 0..) |arg, index| thread.stack.items[index] = arg;

    if (!proto.is_vararg or args.len <= proto.param_count) return;
    const owned_args = try self.allocator.dupe(Value, args[proto.param_count..]);
    thread.frames.items[0].varargs = owned_args;
    thread.frames.items[0].owns_varargs = true;
    thread.frame_storage_bytes += owned_args.len * @sizeOf(Value);
}

pub fn decodeStringLiteral(self: *State, lexeme: []const u8) ![]const u8 {
    if (lexeme.len < 2) return self.strings.intern(lexeme);
    if (lexeme[0] == '\'' or lexeme[0] == '"') return decodeShortString(self, lexeme);
    if (lexeme[0] == '[') return decodeLongString(self, lexeme);
    return self.strings.intern(lexeme);
}

fn decodeShortString(self: *State, lexeme: []const u8) ![]const u8 {
    var out = std.ArrayList(u8).empty;
    errdefer out.deinit(self.allocator);

    var index: usize = 1;
    while (index + 1 < lexeme.len) {
        const byte = lexeme[index];
        index += 1;
        if (byte != '\\') {
            try out.append(self.allocator, byte);
            continue;
        }
        if (index >= lexeme.len - 1) return self.fail("unfinished string escape");
        const escaped = lexeme[index];
        index += 1;
        switch (escaped) {
            'a' => try out.append(self.allocator, 0x07),
            'b' => try out.append(self.allocator, 0x08),
            'f' => try out.append(self.allocator, 0x0c),
            'n' => try out.append(self.allocator, '\n'),
            'r' => try out.append(self.allocator, '\r'),
            't' => try out.append(self.allocator, '\t'),
            'v' => try out.append(self.allocator, 0x0b),
            '\\', '"', '\'' => try out.append(self.allocator, escaped),
            'x' => {
                if (index + 1 >= lexeme.len) return self.fail("invalid hexadecimal escape");
                const value = hexValue(lexeme[index]) * 16 + hexValue(lexeme[index + 1]);
                index += 2;
                try out.append(self.allocator, @intCast(value));
            },
            '0'...'9' => {
                var value: u32 = escaped - '0';
                var count: usize = 1;
                while (count < 3 and index < lexeme.len - 1 and std.ascii.isDigit(lexeme[index])) : (count += 1) {
                    value = value * 10 + lexeme[index] - '0';
                    index += 1;
                }
                if (value > 255) return self.fail("decimal escape too large");
                try out.append(self.allocator, @intCast(value));
            },
            'z' => while (index < lexeme.len - 1 and std.ascii.isWhitespace(lexeme[index])) : (index += 1) {},
            'u' => {
                if (index >= lexeme.len - 1 or lexeme[index] != '{') return self.fail("invalid unicode escape");
                index += 1;
                var value: u32 = 0;
                var count: usize = 0;
                while (index < lexeme.len - 1 and lexeme[index] != '}') : (index += 1) {
                    value = appendUnicodeEscapeDigit(value, hexValue(lexeme[index]));
                    count += 1;
                }
                if (count == 0 or index >= lexeme.len - 1 or lexeme[index] != '}' or value > max_lua_utf8_codepoint) return self.fail("invalid unicode escape");
                index += 1;
                var encoded: [6]u8 = undefined;
                const len = encodeLuaUtf8(value, &encoded) orelse return self.fail("invalid unicode escape");
                try out.appendSlice(self.allocator, encoded[0..len]);
            },
            '\n' => {
                if (index < lexeme.len - 1 and lexeme[index] == '\r') index += 1;
                try out.append(self.allocator, '\n');
            },
            '\r' => {
                if (index < lexeme.len - 1 and lexeme[index] == '\n') index += 1;
                try out.append(self.allocator, '\n');
            },
            else => return self.fail("invalid string escape"),
        }
    }

    const bytes = try self.strings.internConstant(out.items);
    out.deinit(self.allocator);
    return bytes;
}

fn decodeLongString(self: *State, lexeme: []const u8) ![]const u8 {
    var level: usize = 0;
    while (1 + level < lexeme.len and lexeme[1 + level] == '=') level += 1;
    const content_start = level + 2;
    const content_end = lexeme.len - level - 2;
    var content = lexeme[content_start..content_end];
    if (std.mem.startsWith(u8, content, "\r\n") or std.mem.startsWith(u8, content, "\n\r")) {
        content = content[2..];
    } else if (std.mem.startsWith(u8, content, "\n") or std.mem.startsWith(u8, content, "\r")) {
        content = content[1..];
    }
    if (std.mem.indexOfScalar(u8, content, '\r')) |_| {
        const normalized = try normalizeLongStringLineEnds(self, content);
        defer self.allocator.free(normalized);
        return self.strings.internConstant(normalized);
    }
    return self.strings.internConstant(content);
}

fn normalizeLongStringLineEnds(self: *State, content: []const u8) ![]const u8 {
    var out = std.ArrayList(u8).empty;
    errdefer out.deinit(self.allocator);
    var index: usize = 0;
    while (index < content.len) {
        const byte = content[index];
        if (byte == '\r') {
            try out.append(self.allocator, '\n');
            index += if (index + 1 < content.len and content[index + 1] == '\n') 2 else 1;
        } else if (byte == '\n' and index + 1 < content.len and content[index + 1] == '\r') {
            try out.append(self.allocator, '\n');
            index += 2;
        } else {
            try out.append(self.allocator, byte);
            index += 1;
        }
    }
    return out.toOwnedSlice(self.allocator);
}

pub fn newRootClosure(self: *State, proto: *const proto_mod.Proto) !*Closure {
    return newRootClosureWithEnv(self, proto, defaultEnvironment(self));
}

fn newRootClosureWithEnv(self: *State, proto: *const proto_mod.Proto, environment: Value) !*Closure {
    var upvalues: []*Upvalue = if (proto.upvalues.items.len == 0)
        &.{}
    else
        try self.allocator.alloc(*Upvalue, proto.upvalues.items.len);
    errdefer if (upvalues.len != 0) self.allocator.free(upvalues);

    for (proto.upvalues.items, 0..) |desc, index| {
        const upvalue = try self.allocator.create(Upvalue);
        errdefer self.allocator.destroy(upvalue);
        upvalue.* = .{
            .owner = undefined,
            .stack_index = 0,
            .closed = if (std.mem.eql(u8, desc.name, "_ENV")) environment else .nil,
            .is_open = false,
        };
        try self.registerAllocation("upvalue_allocations", upvalue);
        self.gc.noteAllocation(@sizeOf(Upvalue));
        upvalues[index] = upvalue;
    }

    const closure = try self.allocator.create(Closure);
    errdefer self.allocator.destroy(closure);
    vm_mod.assertProtoPrepared(proto);
    closure.* = .{ .proto = proto, .upvalues = upvalues };
    try self.registerAllocation("closure_allocations", closure);
    self.gc.noteAllocation(@sizeOf(Closure));
    return closure;
}

fn defaultEnvironment(self: *State) Value {
    return if (self.global_table) |table| .{ .table = table } else self.getGlobalValue("_G");
}

fn newDumpedClosure(self: *State, proto: *const proto_mod.Proto, environment: Value, stripped_debug: bool) !Value {
    var upvalues: []*Upvalue = if (proto.upvalues.items.len == 0)
        &.{}
    else
        try self.allocator.alloc(*Upvalue, proto.upvalues.items.len);
    errdefer if (upvalues.len != 0) self.allocator.free(upvalues);

    for (proto.upvalues.items, 0..) |desc, index| {
        const upvalue = try self.allocator.create(Upvalue);
        errdefer self.allocator.destroy(upvalue);
        upvalue.* = .{
            .owner = undefined,
            .stack_index = 0,
            .closed = if (std.mem.eql(u8, desc.name, "_ENV")) environment else .nil,
            .is_open = false,
        };
        try self.registerAllocation("upvalue_allocations", upvalue);
        self.gc.noteAllocation(@sizeOf(Upvalue));
        upvalues[index] = upvalue;
    }

    const closure = try self.allocator.create(Closure);
    vm_mod.assertProtoPrepared(proto);
    closure.* = .{ .proto = proto, .upvalues = upvalues, .stripped_debug = stripped_debug };
    errdefer self.allocator.destroy(closure);
    try self.registerAllocation("closure_allocations", closure);
    self.gc.noteAllocation(@sizeOf(Closure));
    return .{ .closure = closure };
}

fn failLoadDiagnostic(self: *State, source_name: ?[]const u8, source_text: []const u8, diagnostic: ?errors.Diagnostic, fallback: []const u8) RuntimeError {
    const rendered = if (diagnostic) |diag|
        errors.renderLoadDiagnostic(self.allocator, source_name, source_text, diag) catch return self.fail(fallback)
    else
        return self.fail(fallback);
    defer self.allocator.free(rendered);
    return self.fail(self.strings.intern(rendered) catch return self.fail(fallback));
}

pub fn runtimeSourceName(name: []const u8) []const u8 {
    if (name.len > 0 and (name[0] == '@' or name[0] == '=')) return name[1..];
    return name;
}

fn setProtoSourceName(proto: *proto_mod.Proto, name: []const u8) !void {
    proto.source_name = try proto.arena.allocator().dupe(u8, name);
    for (proto.children.items) |child| try setProtoSourceName(child, name);
}

pub const max_lua_utf8_codepoint: u32 = 0x7fffffff;

pub fn appendUnicodeEscapeDigit(value: u32, digit: u32) u32 {
    if (value > max_lua_utf8_codepoint / 16) return max_lua_utf8_codepoint + 1;
    const next = value * 16 + digit;
    if (next > max_lua_utf8_codepoint) return max_lua_utf8_codepoint + 1;
    return next;
}

fn encodeLuaUtf8(code: u32, out: *[6]u8) ?usize {
    if (code <= 0x7f) {
        out[0] = @intCast(code);
        return 1;
    }
    if (code <= 0x7ff) {
        out[0] = 0xc0 | @as(u8, @intCast(code >> 6));
        out[1] = 0x80 | @as(u8, @intCast(code & 0x3f));
        return 2;
    }
    if (code <= 0xffff) {
        out[0] = 0xe0 | @as(u8, @intCast(code >> 12));
        out[1] = 0x80 | @as(u8, @intCast((code >> 6) & 0x3f));
        out[2] = 0x80 | @as(u8, @intCast(code & 0x3f));
        return 3;
    }
    if (code <= 0x1fffff) {
        out[0] = 0xf0 | @as(u8, @intCast(code >> 18));
        out[1] = 0x80 | @as(u8, @intCast((code >> 12) & 0x3f));
        out[2] = 0x80 | @as(u8, @intCast((code >> 6) & 0x3f));
        out[3] = 0x80 | @as(u8, @intCast(code & 0x3f));
        return 4;
    }
    if (code <= 0x3ffffff) {
        out[0] = 0xf8 | @as(u8, @intCast(code >> 24));
        out[1] = 0x80 | @as(u8, @intCast((code >> 18) & 0x3f));
        out[2] = 0x80 | @as(u8, @intCast((code >> 12) & 0x3f));
        out[3] = 0x80 | @as(u8, @intCast((code >> 6) & 0x3f));
        out[4] = 0x80 | @as(u8, @intCast(code & 0x3f));
        return 5;
    }
    if (code <= max_lua_utf8_codepoint) {
        out[0] = 0xfc | @as(u8, @intCast(code >> 30));
        out[1] = 0x80 | @as(u8, @intCast((code >> 24) & 0x3f));
        out[2] = 0x80 | @as(u8, @intCast((code >> 18) & 0x3f));
        out[3] = 0x80 | @as(u8, @intCast((code >> 12) & 0x3f));
        out[4] = 0x80 | @as(u8, @intCast((code >> 6) & 0x3f));
        out[5] = 0x80 | @as(u8, @intCast(code & 0x3f));
        return 6;
    }
    return null;
}
