const std = @import("std");
const compile = @import("../compile.zig");
const errors = @import("../errors.zig");
const types = @import("types.zig");
const value_mod = @import("value.zig");

const proto_mod = compile.proto;
const Value = types.Value;
const Thread = types.Thread;
const CallFrame = types.CallFrame;

const appendFmt = value_mod.appendFmt;
const appendValue = value_mod.appendValue;
const localActiveAt = value_mod.localActiveAt;

const DebugStackSlot = struct {
    frame_index: usize,
    register: usize,
};

fn lineForFrame(frame: CallFrame) ?usize {
    if (frame.proto.line_info.items.len == 0) return null;
    const pc = if (frame.pc == 0) 0 else frame.pc - 1;
    if (pc >= frame.proto.line_info.items.len) return null;
    const line = frame.proto.line_info.items[pc].line;
    return if (line == 0) null else line;
}

fn debugStackRegister(thread: *Thread, stack_index: usize) ?DebugStackSlot {
    var frame_index = thread.frames.items.len;
    while (frame_index > 0) {
        frame_index -= 1;
        const frame = thread.frames.items[frame_index];
        const register_count: usize = @intCast(frame.proto.max_registers);
        if (stack_index >= frame.base and stack_index < frame.base + register_count) {
            return .{ .frame_index = frame_index, .register = stack_index - frame.base };
        }
    }
    return null;
}

fn debugValueTypeName(value: Value) []const u8 {
    return value_mod.debugValueTypeName(value);
}

pub fn appendUnhandledErrorDebugDump(comptime State: type, self: *State, thread: *Thread, err: anyerror) !void {
    const out = &self.stderr;
    const stats = self.allocationStats();
    try out.appendSlice(self.allocator, "\n[zlua debug] unhandled runtime exception\n");
    try appendFmt(self.allocator, out, "error={s}\n", .{@errorName(err)});
    try out.appendSlice(self.allocator, "error_value=");
    try appendDebugValue(State, self, out, self.currentErrorValue());
    try out.append(self.allocator, '\n');
    if (self.last_error) |payload| switch (payload) {
        .diagnostic => |message| try appendFmt(self.allocator, out, "last_error={s}\n", .{message}),
        .argument => |argument| {
            const rendered = try errors.renderArgumentError(self.allocator, argument);
            defer self.allocator.free(rendered);
            try appendFmt(self.allocator, out, "last_error={s}\n", .{rendered});
        },
        .lua_value => {},
    };
    try appendFmt(self.allocator, out, "allocations strings={d} tables={d} closures={d} upvalues={d} threads={d} bytes={d}\n", .{ stats.strings, stats.tables, stats.closures, stats.upvalues, stats.threads, stats.bytes });
    try appendFmt(self.allocator, out, "thread status={s} frames={d} stack={d} results={d}@{d} native_depth={d} protected_close_depth={d}\n", .{ @tagName(thread.status), thread.frames.items.len, thread.stack.items.len, thread.last_result_count, thread.last_result_base, thread.native_call_depth, thread.protected_close_depth });
    try appendFmt(self.allocator, out, "continuations protected={d} call_one={d} tail={d} generic_for={d} pairs={d}\n", .{ thread.protected_continuations.items.len, thread.call_one_continuations.items.len, thread.tail_call_continuations.items.len, thread.generic_for_continuations.items.len, thread.pairs_continuations.items.len });
    try appendDebugFrames(State, self, out, thread);
    try appendDebugStack(State, self, out, thread);
    try out.appendSlice(self.allocator, "[/zlua debug]\n");
}

pub fn appendDebugFrames(comptime State: type, self: *State, out: *std.ArrayList(u8), thread: *Thread) !void {
    try appendFmt(self.allocator, out, "frames newest-first ({d}):\n", .{thread.frames.items.len});
    var index = thread.frames.items.len;
    while (index > 0) {
        index -= 1;
        const frame = thread.frames.items[index];
        const pc = if (frame.pc == 0) @as(usize, 0) else frame.pc - 1;
        const line = lineForFrame(frame) orelse 0;
        const name = frame.proto.debug_name orelse "(anonymous)";
        const instruction = if (pc < frame.proto.instructions.items.len)
            @tagName(std.meta.activeTag(frame.proto.instructions.items[pc]))
        else
            "<end>";
        try appendFmt(self.allocator, out, "  frame {d}: {s}:{d} pc={d} op={s} func={s} base={d} return={d}@{d} registers={d}\n", .{ index, frame.proto.source_name, line, pc, instruction, name, frame.base, frame.return_count, frame.return_start, frame.proto.max_registers });
        try appendDebugLocals(State, self, out, thread, frame);
        try appendDebugVarargs(State, self, out, frame);
        try appendDebugUpvalues(State, self, out, frame);
    }
}

pub fn appendDebugLocals(comptime State: type, self: *State, out: *std.ArrayList(u8), thread: *Thread, frame: CallFrame) !void {
    const pc = if (frame.pc == 0) @as(usize, 0) else frame.pc - 1;
    var found = false;
    for (frame.proto.locals.items) |local| {
        if (!localActiveAt(local, pc)) continue;
        found = true;
        try appendFmt(self.allocator, out, "    local {s} r{d}", .{ local.name, local.register });
        if (local.to_close) try out.appendSlice(self.allocator, " <close>");
        try out.appendSlice(self.allocator, " = ");
        const absolute_register = frame.base + local.register;
        if (absolute_register < thread.stack.items.len) {
            try appendDebugValue(State, self, out, thread.stack.items[absolute_register]);
        } else {
            try out.appendSlice(self.allocator, "<out-of-stack>");
        }
        try out.append(self.allocator, '\n');
    }
    if (!found) try out.appendSlice(self.allocator, "    locals: <none>\n");
}

pub fn appendDebugVarargs(comptime State: type, self: *State, out: *std.ArrayList(u8), frame: CallFrame) !void {
    if (frame.varargs.len == 0) {
        try out.appendSlice(self.allocator, "    varargs: <none>\n");
        return;
    }
    for (frame.varargs, 0..) |value, index| {
        try appendFmt(self.allocator, out, "    vararg {d} = ", .{index});
        try appendDebugValue(State, self, out, value);
        try out.append(self.allocator, '\n');
    }
}

pub fn appendDebugUpvalues(comptime State: type, self: *State, out: *std.ArrayList(u8), frame: CallFrame) !void {
    if (frame.closure.upvalues.len == 0) {
        try out.appendSlice(self.allocator, "    upvalues: <none>\n");
        return;
    }
    for (frame.closure.upvalues, 0..) |upvalue, index| {
        const name = if (index < frame.proto.upvalues.items.len) frame.proto.upvalues.items[index].name else "?";
        const value = if (upvalue.is_open) upvalue.owner.stack.items[upvalue.stack_index] else upvalue.closed;
        try appendFmt(self.allocator, out, "    upvalue U{d} {s} {s}", .{ index, name, if (upvalue.is_open) "open" else "closed" });
        if (upvalue.is_open) try appendFmt(self.allocator, out, " stack={d}", .{upvalue.stack_index});
        try out.appendSlice(self.allocator, " = ");
        try appendDebugValue(State, self, out, value);
        try out.append(self.allocator, '\n');
    }
}

pub fn appendDebugStack(comptime State: type, self: *State, out: *std.ArrayList(u8), thread: *Thread) !void {
    try appendFmt(self.allocator, out, "stack ({d} slots):\n", .{thread.stack.items.len});
    for (thread.stack.items, 0..) |value, stack_index| {
        try appendFmt(self.allocator, out, "  [{d}]", .{stack_index});
        if (debugStackRegister(thread, stack_index)) |slot| {
            try appendFmt(self.allocator, out, " frame={d} r{d}", .{ slot.frame_index, slot.register });
        }
        try out.appendSlice(self.allocator, " = ");
        try appendDebugValue(State, self, out, value);
        try out.append(self.allocator, '\n');
    }
}

pub fn appendDebugValue(comptime State: type, self: *State, out: *std.ArrayList(u8), value: Value) !void {
    try appendFmt(self.allocator, out, "({s}) ", .{debugValueTypeName(value)});
    if (value == .table and !self.isTrackedTable(value.table)) {
        try appendFmt(self.allocator, out, "table: 0x{x}", .{@intFromPtr(value.table)});
        return;
    }
    try appendValue(self.allocator, out, value);
}

const traceback_levels_head = 10;
const traceback_levels_tail = 11;
const chunk_id_size = 60;

const TracebackEntry = union(enum) {
    /// A Lua frame, by index into `thread.frames`.
    lua: usize,
    /// A native function, named from its call site when known.
    native: NativeEntry,
    /// A native function called as a generic `for` iterator.
    native_iterator,
};

const NativeEntry = struct {
    origin: ?proto_mod.OperandOrigin = null,
    callee: Value = .nil,
};

pub const TracebackOptions = struct {
    /// Text placed before `stack traceback:`.
    message: ?[]const u8 = null,
    /// First level shown. Level 0 is the function producing the traceback.
    level: usize = 1,
    /// Level 0 is the native function called by the top frame's current
    /// instruction. Otherwise it is not on the thread, as for a message
    /// handler, and `level_zero` names it.
    level_zero_is_callee: bool = false,
    level_zero: Value = .nil,
    /// End with the `[C]: in ?` entry that the standalone interpreter
    /// reports for its own call.
    host_frame: bool = false,
};

/// Formats a `luaL_traceback`-style traceback of `thread` without a message,
/// starting at level 1 as a message handler sees it. See `formatTracebackWith`.
pub fn formatTraceback(comptime State: type, self: *State, thread: *Thread, host_frame: bool) ![]u8 {
    return formatTracebackWith(State, self, thread, .{ .host_frame = host_frame });
}

/// Formats a `luaL_traceback`-style traceback: `stack traceback:` followed
/// by one line per level, innermost first. Called at an error point it shows
/// the native function that raised the error and the Lua frames that were
/// active. Names come from the calling instruction, as in Lua 5.5, or else
/// from the global and loaded-module tables. The caller owns the returned
/// slice, allocated with `self.allocator`.
pub fn formatTracebackWith(comptime State: type, self: *State, thread: *Thread, options: TracebackOptions) ![]u8 {
    var entries = std.ArrayList(TracebackEntry).empty;
    defer entries.deinit(self.allocator);
    const frames = thread.frames.items;
    if (!options.level_zero_is_callee) try entries.append(self.allocator, .{ .native = .{ .callee = options.level_zero } });
    if (frames.len != 0) {
        try appendNativeMarks(self.allocator, &entries, thread, frames.len);
        if (nativeCallee(thread, frames.len - 1)) |entry| try entries.append(self.allocator, entry);
    }
    var index = frames.len;
    while (index > 0) {
        index -= 1;
        try entries.append(self.allocator, .{ .lua = index });
        if (index > 0 and !isDirectCallee(frames, index)) {
            try appendNativeMarks(self.allocator, &entries, thread, index);
            if (nativeCallee(thread, index - 1)) |entry| try entries.append(self.allocator, entry);
        }
    }
    if (options.host_frame) try entries.append(self.allocator, .{ .native = .{} });

    var out = std.ArrayList(u8).empty;
    errdefer out.deinit(self.allocator);
    if (options.message) |message| {
        try out.appendSlice(self.allocator, message);
        try out.append(self.allocator, '\n');
    }
    try out.appendSlice(self.allocator, "stack traceback:");
    const last = entries.items.len -| 1;
    var level = options.level;
    var limit: isize = if (level <= last and last - level > traceback_levels_head + traceback_levels_tail) traceback_levels_head else -1;
    while (level <= last and entries.items.len != 0) {
        const current = level;
        level += 1;
        const show_skip = limit == 0;
        limit -= 1;
        if (show_skip) {
            const skipped = last - level - traceback_levels_tail + 1;
            try appendFmt(self.allocator, &out, "\n\t...\t(skipping {d} levels)", .{skipped});
            level += skipped;
            continue;
        }
        switch (entries.items[current]) {
            .native => |native| {
                try out.appendSlice(self.allocator, "\n\t[C]: in ");
                const named = if (native.origin) |value| originNamewhat(value) else null;
                if (named) |namewhat| {
                    try appendFmt(self.allocator, &out, "{s} '{s}'", .{ namewhat, originName(native.origin.?) });
                } else if (!try appendGlobalName(State, self, &out, native.callee)) {
                    try out.append(self.allocator, '?');
                }
            },
            .native_iterator => try out.appendSlice(self.allocator, "\n\t[C]: in for iterator 'for iterator'"),
            .lua => |frame_index| try appendTracebackFrame(State, self, &out, frames, frame_index),
        }
    }
    return out.toOwnedSlice(self.allocator);
}

fn appendNativeMarks(allocator: std.mem.Allocator, entries: *std.ArrayList(TracebackEntry), thread: *Thread, frame_count: usize) !void {
    var index: usize = thread.native_mark_count;
    while (index > 0) {
        index -= 1;
        const mark = thread.native_marks[index];
        if (mark.frame_count == frame_count) try entries.append(allocator, .{ .native = .{ .callee = mark.callee } });
    }
}

fn appendGlobalName(comptime State: type, self: *State, out: *std.ArrayList(u8), callee: Value) !bool {
    if (callee == .nil) return false;
    const start = out.items.len;
    try out.appendSlice(self.allocator, "function '");
    if (!try self.appendGlobalFunctionName(out, callee)) {
        out.items.len = start;
        return false;
    }
    try out.append(self.allocator, '\'');
    return true;
}

fn appendTracebackFrame(comptime State: type, self: *State, out: *std.ArrayList(u8), frames: []const CallFrame, index: usize) !void {
    const allocator = self.allocator;
    const frame = frames[index];
    if (isNativeEntryFrame(frame)) {
        try out.appendSlice(allocator, "\n\t[C]: in ?");
        return;
    }
    var id_buffer: [chunk_id_size]u8 = undefined;
    const stripped = frame.closure.stripped_debug;
    const source = if (stripped) "?" else chunkId(&id_buffer, frame.proto.source_name);
    if (if (stripped) null else lineForFrame(frame)) |line| {
        try appendFmt(allocator, out, "\n\t{s}:{d}: in ", .{ source, line });
    } else {
        try appendFmt(allocator, out, "\n\t{s}: in ", .{source});
    }
    if (frame.debug_namewhat_override != null and frame.debug_name_override != null) {
        try appendFmt(allocator, out, "{s} '{s}'", .{ frame.debug_namewhat_override.?, frame.debug_name_override.? });
    } else if (callSiteName(frames, index)) |name| {
        try appendFmt(allocator, out, "{s} '{s}'", .{ name.namewhat, name.name });
    } else if (frame.proto.defined_line == 0) {
        try out.appendSlice(allocator, "main chunk");
    } else if (!try appendGlobalName(State, self, out, .{ .closure = frame.closure })) {
        try appendFmt(allocator, out, "function <{s}:{d}>", .{ source, frame.proto.defined_line });
    }
    if (frame.is_tail_call) try out.appendSlice(allocator, "\n\t(...tail calls...)");
}

pub const CallName = struct { namewhat: []const u8, name: []const u8 };

/// Frames from `start` up that Lua would have entered through a C call,
/// such as a metamethod or a message handler, rather than a call instruction.
pub fn indirectFrameCount(thread: *Thread, start: usize) usize {
    const frames = thread.frames.items;
    var count: usize = 0;
    for (@max(start, 1)..frames.len) |index| {
        if (!isDirectCallee(frames, index)) count += 1;
    }
    return count;
}

/// True when Lua code in the top frame raised the current error, rather
/// than a native function it called.
pub fn errorRaisedByLuaCode(thread: *Thread) bool {
    const frames = thread.frames.items;
    if (frames.len == 0) return false;
    const top = frames[frames.len - 1];
    if (isNativeEntryFrame(top) or top.closure.stripped_debug) return false;
    for (thread.native_marks[0..thread.native_mark_count]) |mark| {
        if (mark.frame_count == frames.len) return false;
    }
    return nativeCallee(thread, frames.len - 1) == null;
}

/// Names a message handler called at an error point the way Lua names a
/// function from its caller's current instruction (`funcnamefromcode`).
/// An error raised inside a native function leaves the handler unnamed.
pub fn messageHandlerCallName(thread: *Thread) ?CallName {
    const frames = thread.frames.items;
    if (frames.len == 0) return null;
    const top = frames.len - 1;
    const frame = frames[top];
    if (isNativeEntryFrame(frame) or frame.closure.stripped_debug) return null;
    if (nativeCallee(thread, top) != null) return null;
    const instruction = currentInstruction(frame) orelse return null;
    const event: []const u8 = switch (instruction) {
        .call, .tail_call => {
            const origin = callOrigin(frame) orelse return null;
            return .{ .namewhat = originNamewhat(origin) orelse return null, .name = originName(origin) };
        },
        .tfor_call => return .{ .namewhat = "for iterator", .name = "for iterator" },
        .get_global, .get_table, .get_field => "index",
        .set_global, .set_table, .set_array, .set_field => "newindex",
        .concat, .concat_range => "concat",
        .compare_branch => |op| @tagName(op.op),
        .close, .ret => "close",
        inline .add, .sub, .mul, .div, .idiv, .mod, .pow, .unm, .band, .bor, .bxor, .bnot, .shl, .shr, .eq, .lt, .le, .len => |_, tag| @tagName(tag),
        else => return null,
    };
    return .{ .namewhat = "metamethod", .name = event };
}

fn callSiteName(frames: []const CallFrame, index: usize) ?CallName {
    if (index == 0 or frames[index].is_tail_call or !isDirectCallee(frames, index)) return null;
    const caller = frames[index - 1];
    if (caller.closure.stripped_debug) return null;
    const instruction = currentInstruction(caller) orelse return null;
    if (instruction == .tfor_call) return .{ .namewhat = "for iterator", .name = "for iterator" };
    const origin = callOrigin(caller) orelse return null;
    return .{ .namewhat = originNamewhat(origin) orelse return null, .name = originName(origin) };
}

fn isDirectCallee(frames: []const CallFrame, index: usize) bool {
    const caller = frames[index - 1];
    const callee = frames[index];
    return switch (currentInstruction(caller) orelse return false) {
        .call => |op| callee.base == caller.base + op.base + 1,
        .tfor_call => |op| callee.base > caller.base + op.base and callee.base <= caller.base + caller.proto.max_registers,
        else => false,
    };
}

fn nativeCallee(thread: *Thread, index: usize) ?TracebackEntry {
    const frame = thread.frames.items[index];
    const instruction = currentInstruction(frame) orelse return null;
    const register = switch (instruction) {
        .call, .tail_call => |op| op.base,
        .tfor_call => |op| op.base,
        else => return null,
    };
    const slot = frame.base + register;
    if (slot >= thread.stack.items.len) return null;
    const callee = thread.stack.items[slot];
    if (callee == .closure or !std.mem.eql(u8, debugValueTypeName(callee), "function")) return null;
    if (instruction == .tfor_call) return .native_iterator;
    return .{ .native = .{ .origin = if (frame.closure.stripped_debug) null else callOrigin(frame), .callee = callee } };
}

fn currentInstruction(frame: CallFrame) ?compile.bytecode.Instruction {
    if (frame.pc == 0 or frame.pc > frame.proto.instructions.items.len) return null;
    return frame.proto.instructions.items[frame.pc - 1];
}

fn callOrigin(frame: CallFrame) ?proto_mod.OperandOrigin {
    const site = frame.proto.errorSiteAt(frame.pc - 1) orelse return null;
    if (site.call_name) |origin| return origin;
    if (site.operands.len != 0) return site.operands[0];
    return null;
}

fn isNativeEntryFrame(frame: CallFrame) bool {
    return frame.proto.instructions.items.len == 0 and std.mem.eql(u8, frame.proto.source_name, "=[C]");
}

fn originNamewhat(origin: proto_mod.OperandOrigin) ?[]const u8 {
    return switch (origin) {
        .temporary, .constant => null,
        .local => "local",
        .upvalue => "upvalue",
        .global => "global",
        .field => "field",
        .method => "method",
        .metamethod => "metamethod",
    };
}

fn originName(origin: proto_mod.OperandOrigin) []const u8 {
    return switch (origin) {
        .temporary => "?",
        .local, .upvalue, .global, .field, .method, .metamethod, .constant => |name| name,
    };
}

/// Formats a chunk name for messages, as `luaO_chunkid` does.
pub fn chunkId(buffer: *[chunk_id_size]u8, source: []const u8) []const u8 {
    const max = chunk_id_size - 1;
    if (source.len > 0 and source[0] == '=') {
        const rest = source[1..];
        return rest[0..@min(rest.len, max)];
    }
    if (source.len > 0 and source[0] == '@') {
        const rest = source[1..];
        if (rest.len <= max) return rest;
        const tail_len = max - 3;
        @memcpy(buffer[0..3], "...");
        @memcpy(buffer[3 .. 3 + tail_len], rest[rest.len - tail_len ..]);
        return buffer[0 .. 3 + tail_len];
    }
    const prefix = "[string \"";
    const suffix = "\"]";
    const limit = chunk_id_size - (prefix.len + 3 + suffix.len) - 1;
    const newline = std.mem.indexOfScalar(u8, source, '\n');
    var len: usize = 0;
    @memcpy(buffer[0..prefix.len], prefix);
    len += prefix.len;
    if (source.len < limit and newline == null) {
        @memcpy(buffer[len .. len + source.len], source);
        len += source.len;
    } else {
        const kept = @min(newline orelse source.len, limit);
        @memcpy(buffer[len .. len + kept], source[0..kept]);
        len += kept;
        @memcpy(buffer[len .. len + 3], "...");
        len += 3;
    }
    @memcpy(buffer[len .. len + suffix.len], suffix);
    len += suffix.len;
    return buffer[0..len];
}
