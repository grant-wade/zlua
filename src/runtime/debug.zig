const std = @import("std");
const compile = @import("../compile.zig");
const call_mod = @import("call.zig");
const metatable_mod = @import("metatable.zig");
const rollback_mod = @import("rollback.zig");
const State = @import("state.zig").State;
const types = @import("types.zig");
const value_mod = @import("value.zig");

const proto_mod = compile.proto;
const Value = types.Value;
const Thread = types.Thread;
const CallFrame = types.CallFrame;
const appendFmt = value_mod.appendFmt;
const appendValue = value_mod.appendValue;
const localActiveAt = value_mod.localActiveAt;
const bytecode = compile.bytecode;
const toInteger = value_mod.toInteger;
const argValue = value_mod.argValue;
const luaTypeName = value_mod.luaTypeName;

const DebugStackSlot = struct {
    frame_index: usize,
    register: usize,
};

pub fn lineForFrame(frame: CallFrame) ?usize {
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

pub fn appendUnhandledErrorDebugDump(self: *State, thread: *Thread, err: anyerror) !void {
    const out = &self.stderr;
    const stats = self.gc.allocationStats();
    try out.appendSlice(self.allocator, "\n[zlua debug] unhandled runtime exception\n");
    try appendFmt(self.allocator, out, "error={s}\n", .{@errorName(err)});
    try out.appendSlice(self.allocator, "error_value=");
    try appendDebugValue(self, out, self.currentErrorValue());
    try out.append(self.allocator, '\n');
    if (self.last_error) |payload| switch (payload) {
        .diagnostic => |message| try appendFmt(self.allocator, out, "last_error={s}\n", .{message}),
        .lua_value => {},
    };
    try appendFmt(self.allocator, out, "allocations strings={d} tables={d} closures={d} upvalues={d} threads={d} bytes={d}\n", .{ stats.strings, stats.tables, stats.closures, stats.upvalues, stats.threads, stats.bytes });
    try appendFmt(self.allocator, out, "thread status={s} frames={d} stack={d} results={d}@{d} native_depth={d} protected_close_depth={d}\n", .{ @tagName(thread.status), thread.frames.items.len, thread.stack.items.len, thread.last_result_count, thread.last_result_base, thread.native_call_depth, thread.protected_close_depth });
    try appendFmt(self.allocator, out, "continuations protected={d} call_one={d} tail={d} generic_for={d} pairs={d}\n", .{ thread.protected_continuations.items.len, thread.call_one_continuations.items.len, thread.tail_call_continuations.items.len, thread.generic_for_continuations.items.len, thread.pairs_continuations.items.len });
    try appendDebugFrames(self, out, thread);
    try appendDebugStack(self, out, thread);
    try out.appendSlice(self.allocator, "[/zlua debug]\n");
}

fn appendDebugFrames(self: *State, out: *std.ArrayList(u8), thread: *Thread) !void {
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
        try appendDebugLocals(self, out, thread, frame);
        try appendDebugVarargs(self, out, frame);
        try appendDebugUpvalues(self, out, frame);
    }
}

fn appendDebugLocals(self: *State, out: *std.ArrayList(u8), thread: *Thread, frame: CallFrame) !void {
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
            try appendDebugValue(self, out, thread.stack.items[absolute_register]);
        } else {
            try out.appendSlice(self.allocator, "<out-of-stack>");
        }
        try out.append(self.allocator, '\n');
    }
    if (!found) try out.appendSlice(self.allocator, "    locals: <none>\n");
}

fn appendDebugVarargs(self: *State, out: *std.ArrayList(u8), frame: CallFrame) !void {
    if (frame.varargs.len == 0) {
        try out.appendSlice(self.allocator, "    varargs: <none>\n");
        return;
    }
    for (frame.varargs, 0..) |value, index| {
        try appendFmt(self.allocator, out, "    vararg {d} = ", .{index});
        try appendDebugValue(self, out, value);
        try out.append(self.allocator, '\n');
    }
}

fn appendDebugUpvalues(self: *State, out: *std.ArrayList(u8), frame: CallFrame) !void {
    if (frame.closure.upvalue_count == 0) {
        try out.appendSlice(self.allocator, "    upvalues: <none>\n");
        return;
    }
    for (frame.closure.upvalues(), 0..) |upvalue, index| {
        const name = if (index < frame.proto.upvalues.items.len) frame.proto.upvalues.items[index].name else "?";
        const value = if (upvalue.is_open) upvalue.owner.stack.items[upvalue.stack_index] else upvalue.closed;
        try appendFmt(self.allocator, out, "    upvalue U{d} {s} {s}", .{ index, name, if (upvalue.is_open) "open" else "closed" });
        if (upvalue.is_open) try appendFmt(self.allocator, out, " stack={d}", .{upvalue.stack_index});
        try out.appendSlice(self.allocator, " = ");
        try appendDebugValue(self, out, value);
        try out.append(self.allocator, '\n');
    }
}

fn appendDebugStack(self: *State, out: *std.ArrayList(u8), thread: *Thread) !void {
    try appendFmt(self.allocator, out, "stack ({d} slots):\n", .{thread.stack.items.len});
    for (thread.stack.items, 0..) |value, stack_index| {
        try appendFmt(self.allocator, out, "  [{d}]", .{stack_index});
        if (debugStackRegister(thread, stack_index)) |slot| {
            try appendFmt(self.allocator, out, " frame={d} r{d}", .{ slot.frame_index, slot.register });
        }
        try out.appendSlice(self.allocator, " = ");
        try appendDebugValue(self, out, value);
        try out.append(self.allocator, '\n');
    }
}

fn appendDebugValue(self: *State, out: *std.ArrayList(u8), value: Value) !void {
    try appendFmt(self.allocator, out, "({s}) ", .{debugValueTypeName(value)});
    try appendValue(self.allocator, out, value);
}

const traceback_levels_head = 10;
const traceback_levels_tail = 11;
const chunk_id_size = 60;

const TracebackEntry = union(enum) {
    /// Index into `thread.frames`.
    lua: usize,
    native: NativeEntry,
    /// A native function called as a generic `for` iterator.
    native_iterator,
};

const NativeEntry = struct {
    origin: ?proto_mod.OperandOrigin = null,
    callee: Value = .nil,
};

const TracebackOptions = struct {
    /// Text placed before `stack traceback:`.
    message: ?[]const u8 = null,
    /// First level shown; level 0 is the function producing the traceback.
    level: usize = 1,
    /// Level 0 is the top frame's native callee; otherwise `level_zero` names it.
    level_zero_is_callee: bool = false,
    level_zero: Value = .nil,
    /// Append the standalone interpreter's `[C]: in ?` entry.
    host_frame: bool = false,
};

/// Formats a traceback from level 1 without a message, as a message handler sees it.
pub fn formatTraceback(self: *State, thread: *Thread, host_frame: bool) ![]u8 {
    return formatTracebackWith(self, thread, .{ .host_frame = host_frame });
}

/// Formats a `luaL_traceback`-style traceback, owned by the caller.
fn formatTracebackWith(self: *State, thread: *Thread, options: TracebackOptions) ![]u8 {
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
        if (!isCoroutineEntryFrame(frames[index])) try entries.append(self.allocator, .{ .lua = index });
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
                } else if (!try appendGlobalName(self, &out, native.callee)) {
                    try out.append(self.allocator, '?');
                }
            },
            .native_iterator => try out.appendSlice(self.allocator, "\n\t[C]: in for iterator 'for iterator'"),
            .lua => |frame_index| try appendTracebackFrame(self, &out, frames, frame_index),
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

fn appendGlobalName(self: *State, out: *std.ArrayList(u8), callee: Value) !bool {
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

fn appendTracebackFrame(self: *State, out: *std.ArrayList(u8), frames: []const CallFrame, index: usize) !void {
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
    } else if (!try appendGlobalName(self, out, .{ .closure = frame.closure })) {
        try appendFmt(allocator, out, "function <{s}:{d}>", .{ source, frame.proto.defined_line });
    }
    if (frame.is_tail_call) try out.appendSlice(allocator, "\n\t(...tail calls...)");
}

pub const CallName = struct { namewhat: []const u8, name: []const u8 };

/// Counts frames from `start` that Lua enters through a C call rather than a call instruction.
pub fn indirectFrameCount(thread: *Thread, start: usize) usize {
    const frames = thread.frames.items;
    var count: usize = 0;
    for (@max(start, 1)..frames.len) |index| {
        if (!isDirectCallee(frames, index)) count += 1;
    }
    return count;
}

/// True when Lua code in the top frame, not a native it called, raised the current error.
pub fn errorRaisedByLuaCode(thread: *Thread) bool {
    const frames = thread.frames.items;
    if (frames.len == 0) return false;
    const top = frames[frames.len - 1];
    if (isNativeEntryFrame(top) or isCoroutineEntryFrame(top) or top.closure.stripped_debug) return false;
    for (thread.native_marks[0..thread.native_mark_count]) |mark| {
        if (mark.frame_count == frames.len) return false;
    }
    return nativeCallee(thread, frames.len - 1) == null;
}

/// Names a message handler at an error point like `funcnamefromcode`; null inside natives.
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

pub const coroutine_entry_source = "=(coroutine entry)";

/// True for the synthetic frame calling a coroutine's non-Lua body, which C Lua lacks.
pub fn isCoroutineEntryFrame(frame: CallFrame) bool {
    return std.mem.eql(u8, frame.proto.source_name, coroutine_entry_source);
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
fn chunkId(buffer: *[chunk_id_size]u8, source: []const u8) []const u8 {
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

pub fn currentLine(self: *State, thread: *Thread, level: i64) ?usize {
    _ = self;
    if (level < 1) return null;
    const depth: usize = @intCast(level);
    if (depth > thread.frames.items.len) return null;
    const frame = thread.frames.items[thread.frames.items.len - depth];
    if (frame.proto.line_info.items.len == 0) return null;
    const pc = if (frame.pc == 0) @as(usize, 0) else frame.pc - 1;
    return frame.proto.line_info.items[@min(pc, frame.proto.line_info.items.len - 1)].line;
}

pub fn currentExtraArgs(self: *State, thread: *Thread, level: i64) ?usize {
    _ = self;
    if (level < 1) return null;
    const depth: usize = @intCast(level);
    if (depth > thread.frames.items.len) return null;
    const frame = thread.frames.items[thread.frames.items.len - depth];
    return frame.varargs.len;
}

pub fn currentWhat(self: *State, thread: *Thread, level: i64) []const u8 {
    _ = self;
    if (level == 2 and thread.protected_close_depth != 0) return "C";
    if (level >= 1) {
        const depth: usize = @intCast(level);
        if (depth <= thread.frames.items.len) {
            const frame = thread.frames.items[thread.frames.items.len - depth];
            if (frame.proto.defined_line == 0) return "main";
        }
    }
    return "Lua";
}

pub fn currentFunctionName(self: *State, thread: *Thread, level: i64) ?[]const u8 {
    _ = self;
    if (level == 2 and thread.protected_close_depth != 0) return "pcall";
    if (level == 2 and thread.hook_running) if (thread.hook_return_name) |name| return name;
    if (level < 1) return null;
    const depth: usize = @intCast(level);
    if (depth > thread.frames.items.len) return null;
    const frame = thread.frames.items[thread.frames.items.len - depth];
    const pc = if (frame.pc == 0) 0 else frame.pc - 1;
    for (frame.proto.locals.items) |local| {
        if (!std.mem.eql(u8, local.name, "name")) continue;
        if (pc < local.start_pc or (local.end_pc != 0 and pc > local.end_pc)) continue;
        const value = thread.stack.items[frame.base + local.register];
        if (value == .string) return value.string.bytes();
    }
    return frame.debug_name_override orelse frame.proto.debug_name;
}

pub fn currentFunctionNameWhat(self: *State, thread: *Thread, level: i64) ?[]const u8 {
    _ = self;
    if (level < 1) return null;
    const depth: usize = @intCast(level);
    if (depth > thread.frames.items.len) return null;
    const frame = thread.frames.items[thread.frames.items.len - depth];
    return frame.debug_namewhat_override;
}

pub fn setThreadHook(self: *State, target: *Thread, hook: Value, mask: []const u8, count: u32) void {
    rollback_mod.touch(target);
    target.hook = hook;
    self.gc.writeBarrier(target, hook);
    target.hook_call = false;
    target.hook_line = false;
    target.hook_return = false;
    target.hook_count = 0;
    target.hook_count_remaining = 0;
    target.pending_yield_hook_return = false;
    if (hook == .nil) return;
    target.hook_call = std.mem.indexOfScalar(u8, mask, 'c') != null;
    target.hook_line = std.mem.indexOfScalar(u8, mask, 'l') != null;
    target.hook_return = std.mem.indexOfScalar(u8, mask, 'r') != null;
    target.hook_count = count;
    target.hook_count_remaining = count;
    if (target.hook_line and target.frames.items.len != 0) {
        const frame_index = target.frames.items.len - 1;
        target.frames.items[frame_index].last_hook_line = lineForFrame(target.frames.items[frame_index]);
    }
}

pub fn threadHookMask(self: *State, thread: *Thread) !*const types.String {
    var bytes: [3]u8 = undefined;
    var len: usize = 0;
    if (thread.hook_call) {
        bytes[len] = 'c';
        len += 1;
    }
    if (thread.hook_return) {
        bytes[len] = 'r';
        len += 1;
    }
    if (thread.hook_line) {
        bytes[len] = 'l';
        len += 1;
    }
    return self.strings.intern(bytes[0..len]);
}

pub fn callHook(self: *State, thread: *Thread, event: []const u8) !void {
    const args = [_]Value{.{ .string = try self.strings.intern(event) }};
    try callHookWithArgs(self, thread, &args);
}

pub fn callReturnHook(self: *State, thread: *Thread, name: ?[]const u8) !void {
    const previous = thread.hook_return_name;
    thread.hook_return_name = name;
    defer thread.hook_return_name = previous;
    try callHook(self, thread, "return");
}

fn callHookWithArgs(self: *State, thread: *Thread, args: []const Value) !void {
    if (thread.hook == .nil or thread.hook_running) return;
    thread.hook_running = true;
    defer thread.hook_running = false;
    self.gc.conservative_depth += 1;
    defer self.gc.conservative_depth -= 1;
    const previous_result_base = thread.last_result_base;
    const previous_result_count = thread.last_result_count;
    defer {
        thread.last_result_base = previous_result_base;
        thread.last_result_count = previous_result_count;
    }
    _ = try call_mod.callOneNamed(self, thread, "?", "hook", thread.hook, args);
}

pub fn callLineHook(self: *State, thread: *Thread) !void {
    if (!thread.hook_line or thread.hook == .nil or thread.hook_running) return;
    if (thread.frames.items.len == 0) return;
    const frame_index = thread.frames.items.len - 1;
    const line = lineForFrame(thread.frames.items[frame_index]) orelse return;
    if (thread.frames.items[frame_index].last_hook_line == line) return;
    thread.frames.items[frame_index].last_hook_line = line;
    const line_value = if (thread.frames.items[frame_index].closure.stripped_debug) Value.nil else Value{ .integer = @intCast(line) };
    const args = [_]Value{ .{ .string = try self.strings.intern("line") }, line_value };
    try callHookWithArgs(self, thread, &args);
}

pub fn callCountHook(self: *State, thread: *Thread) !void {
    if (thread.hook_count == 0 or thread.hook == .nil or thread.hook_running) return;
    if (thread.hook_count_remaining > 1) {
        thread.hook_count_remaining -= 1;
        return;
    }
    thread.hook_count_remaining = thread.hook_count;
    try callHook(self, thread, "count");
}

pub fn tracebackValue(self: *State, thread: *Thread, op: bytecode.Call) !void {
    var out = std.ArrayList(u8).empty;
    defer out.deinit(self.allocator);

    const message = argValue(self, thread, op, 0);
    if (message == .thread) {
        const target = message.thread;
        const level_value = if (op.arg_count >= 3) argValue(self, thread, op, 2) else Value.nil;
        const has_coroutine_level = level_value != .nil;
        if (!has_coroutine_level and target.close_error_value != null) if (target.error_traceback) |traceback| {
            try self.returnValues(thread, op.base, op.return_count, &.{.{ .string = traceback }});
            return;
        };
        const coroutine_level = if (has_coroutine_level) toInteger(level_value) orelse 1 else 0;
        const has_yield_trace = !has_coroutine_level and (target.frames.items.len != 0 or (target.status != .dead and target.yield_values.items.len != 0));
        try out.appendSlice(self.allocator, "stack traceback:");
        if (has_yield_trace) try out.appendSlice(self.allocator, "\n\t'yield'");
        const skip = if (coroutine_level <= 1) @as(usize, 0) else @as(usize, @intCast(coroutine_level - 1));
        const count = if (skip >= target.frames.items.len) @as(usize, 0) else target.frames.items.len - skip;
        if (count == 0 and target.status != .dead and target.yield_values.items.len != 0 and !has_coroutine_level) {
            try out.appendSlice(self.allocator, "\n\t@db.lua: in function <");
        }
        try appendCoroutineTracebackFrames(self, &out, target, count, @intFromBool(has_yield_trace));
        try self.returnValues(thread, op.base, op.return_count, &.{.{ .string = try self.strings.intern(out.items) }});
        return;
    }
    if (message != .nil and message != .string and message != .integer and message != .number) {
        try self.returnValues(thread, op.base, op.return_count, &.{message});
        return;
    }
    const text: ?[]const u8 = if (message == .nil) null else (try metatable_mod.valueToString(self, thread, message)).bytes();
    const level = if (op.arg_count >= 2) toInteger(argValue(self, thread, op, 1)) orelse 1 else 1;
    if (level < 0) {
        try appendFmt(self.allocator, &out, "{s}{s}stack traceback:", .{ text orelse "", if (text == null) "" else "\n" });
        try self.returnValues(thread, op.base, op.return_count, &.{.{ .string = try self.strings.intern(out.items) }});
        return;
    }
    const traceback = try formatTracebackWith(self, thread, .{
        .message = text,
        .level = std.math.cast(usize, level) orelse std.math.maxInt(usize),
        .level_zero_is_callee = calledByTopInstruction(thread, op),
        .level_zero = .native_debug_traceback,
        .host_frame = thread.host_frame,
    });
    defer self.allocator.free(traceback);
    try self.returnValues(thread, op.base, op.return_count, &.{.{ .string = try self.strings.intern(traceback) }});
}

/// The standalone interpreter's `msghandler` from `lua.c`.
pub fn tracebackMessageHandler(self: *State, thread: *Thread, op: bytecode.Call) !void {
    const message = argValue(self, thread, op, 0);
    const text = switch (message) {
        .string => |string| string.bytes(),
        .integer, .number => (try metatable_mod.valueToString(self, thread, message)).bytes(),
        else => blk: {
            if (try metatable_mod.getMetaEvent(self, message, .__tostring)) |metamethod| {
                const result = try call_mod.callOneResult(self, thread, metamethod, &.{message});
                if (result == .string) return self.returnValues(thread, op.base, op.return_count, &.{result});
            }
            var out = std.ArrayList(u8).empty;
            defer out.deinit(self.allocator);
            try appendFmt(self.allocator, &out, "(error object is a {s} value)", .{luaTypeName(message)});
            break :blk (try self.strings.intern(out.items)).bytes();
        },
    };
    const traceback = try formatTracebackWith(self, thread, .{ .message = text, .host_frame = thread.host_frame });
    defer self.allocator.free(traceback);
    try self.returnValues(thread, op.base, op.return_count, &.{.{ .string = try self.strings.intern(traceback) }});
}

fn calledByTopInstruction(thread: *Thread, op: bytecode.Call) bool {
    const frames = thread.frames.items;
    if (frames.len == 0) return false;
    const frame = frames[frames.len - 1];
    if (frame.pc == 0 or frame.pc > frame.proto.instructions.items.len) return false;
    return switch (frame.proto.instructions.items[frame.pc - 1]) {
        .call, .tail_call => |call| call.base == op.base,
        else => false,
    };
}

fn appendCoroutineTracebackFrame(self: *State, out: *std.ArrayList(u8), target: *Thread, frame: CallFrame, level: i64) !void {
    try out.append(self.allocator, '\n');
    try out.append(self.allocator, '\t');
    try out.appendSlice(self.allocator, frame.proto.source_name);
    if (currentFunctionName(self, target, level)) |name| {
        try appendFmt(self.allocator, out, ": in function '{s}'", .{name});
    } else {
        try out.appendSlice(self.allocator, ": in function <");
    }
}

/// Appends the innermost `count` frames after `leading` levels, skipping the middle like `luaL_traceback`.
fn appendCoroutineTracebackFrames(self: *State, out: *std.ArrayList(u8), target: *Thread, count: usize, leading: usize) !void {
    if (count == 0) return;
    const head = traceback_levels_head;
    const tail = traceback_levels_tail;
    const last = leading + count - 1;
    var level: usize = 0;
    var limit: isize = if (last > head + tail) head else -1;
    while (level <= last) {
        const current = level;
        level += 1;
        const show_skip = limit == 0;
        limit -= 1;
        if (show_skip) {
            const skipped = last - level - tail + 1;
            try appendFmt(self.allocator, out, "\n\t...\t(skipping {d} levels)", .{skipped});
            level += skipped;
            continue;
        }
        if (current < leading) continue;
        const index = count - 1 - (current - leading);
        try appendCoroutineTracebackFrame(self, out, target, target.frames.items[index], @intCast(target.frames.items.len - index));
    }
}

pub fn snapshotCoroutineErrorTraceback(self: *State, target: *Thread) !*const types.String {
    var out = std.ArrayList(u8).empty;
    defer out.deinit(self.allocator);
    try out.appendSlice(self.allocator, "stack traceback:\n\t'error'");
    try appendCoroutineTracebackFrames(self, &out, target, target.frames.items.len, 1);
    return self.strings.intern(out.items);
}

pub fn lineForErrorLevel(self: *State, thread: *Thread, level: usize) ?usize {
    _ = self;
    if (level == 0 or level > thread.frames.items.len) return null;
    const frame = thread.frames.items[thread.frames.items.len - level];
    return lineForFrame(frame);
}

pub fn sourceForErrorLevel(self: *State, thread: *Thread, level: usize) ?[]const u8 {
    _ = self;
    if (level == 0 or level > thread.frames.items.len) return null;
    const source_name = thread.frames.items[thread.frames.items.len - level].proto.source_name;
    if (source_name.len > 0 and (source_name[0] == '@' or source_name[0] == '=')) return source_name[1..];
    return source_name;
}
