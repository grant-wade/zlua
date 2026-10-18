const std = @import("std");
const compile = @import("../compile.zig");
const debug_mod = @import("debug.zig");
const io_mod = @import("io.zig");
const load_mod = @import("load.zig");
const metatable_mod = @import("metatable.zig");
const operators_mod = @import("operators.zig");
const state_mod = @import("state.zig");
const types = @import("types.zig");
const value_mod = @import("value.zig");
const vm_mod = @import("vm.zig");

const State = state_mod.State;
const proto_mod = compile.proto;
const RuntimeError = types.RuntimeError;
const Value = types.Value;
const toNumberMaybe = value_mod.toNumberMaybe;
const luaStringLike = value_mod.luaStringLike;
const indexErrorMessage = value_mod.indexErrorMessage;
const callErrorMessage = value_mod.callErrorMessage;
const appendFmt = value_mod.appendFmt;
const luaTypeName = value_mod.luaTypeName;
const Thread = types.Thread;

pub fn throwStringWithLocation(self: *State, thread: *Thread, message_text: *const types.String, requested_level: usize) !void {
    var level = requested_level;
    if (State.activeNativeCall(thread)) |call| {
        if (call.from_native) {
            if (level == 1) return self.throwValue(.{ .string = message_text });
            level -= 1;
        } else if (level >= 2 and call.outer_frame_count != null and call.outer_frame_count.? + 1 == call.frame_count) {
            if (level == 2) return self.throwValue(.{ .string = message_text });
            level -= 1;
        }
    }
    const line = debug_mod.lineForErrorLevel(self, thread, level) orelse return self.throwValue(.{ .string = message_text });
    const source = debug_mod.sourceForErrorLevel(self, thread, level) orelse "zlua";
    const message = try std.fmt.allocPrint(self.allocator, "{s}:{d}: {s}", .{ source, line, message_text.bytes() });
    defer self.allocator.free(message);
    return self.throwValue(.{ .string = try self.strings.intern(message) });
}

pub fn failRuntimeDetail(self: *State, thread: ?*Thread, detail: []const u8) RuntimeError {
    var out = std.ArrayList(u8).empty;
    defer out.deinit(self.allocator);
    appendRuntimeErrorPrefix(self, &out, thread) catch return self.fail(detail);
    out.appendSlice(self.allocator, detail) catch return self.fail(detail);
    return self.failString(self.strings.intern(out.items) catch return self.fail(detail));
}

pub fn failDivisionByZero(self: *State, thread: *Thread, lhs: Value, rhs: Value, op: operators_mod.BinaryOp) RuntimeError {
    const message = if (op == .mod) "attempt to perform 'n%0'" else "attempt to divide by zero";
    if (lhs == .string or rhs == .string) return self.fail(message);
    return failRuntimeDetail(self, thread, message);
}

fn failNoIntegerRepresentation(self: *State, thread: *Thread, lhs: Value) RuntimeError {
    var detail = std.ArrayList(u8).empty;
    defer detail.deinit(self.allocator);
    const operand_index: usize = if (operators_mod.toBitwiseInteger(lhs) == null) 0 else 1;
    detail.appendSlice(self.allocator, "number") catch return self.fail("number has no integer representation");
    appendSiteOrigin(self, &detail, currentErrorSite(self, thread), operand_index, false) catch return self.fail("number has no integer representation");
    detail.appendSlice(self.allocator, " has no integer representation") catch return self.fail("number has no integer representation");
    return failRuntimeDetail(self, thread, detail.items);
}

pub fn failBinaryTypeError(self: *State, thread: *Thread, lhs: Value, rhs: Value, op: operators_mod.BinaryOp) RuntimeError {
    var detail = std.ArrayList(u8).empty;
    defer detail.deinit(self.allocator);
    const site = currentErrorSite(self, thread);
    switch (op) {
        .add, .sub, .mul, .div, .idiv, .mod, .pow => {
            if (lhs == .string or rhs == .string) {
                appendFmt(self.allocator, &detail, "attempt to {s} a '{s}' with a '{s}'", .{ operators_mod.arithmeticVerb(op), luaTypeName(lhs), luaTypeName(rhs) }) catch return self.fail("attempt to perform operation on unsupported values");
                return failRuntimeDetail(self, thread, detail.items);
            }
            const operand_index: usize = if (toNumberMaybe(lhs) == null) 0 else 1;
            const bad_value = if (operand_index == 0) lhs else rhs;
            appendFmt(self.allocator, &detail, "attempt to perform arithmetic on a {s} value", .{metatable_mod.luaTypeNameForError(self, bad_value)}) catch return self.fail("attempt to perform operation on unsupported values");
            appendSiteOrigin(self, &detail, site, operand_index, false) catch return self.fail("attempt to perform operation on unsupported values");
        },
        .band, .bor, .bxor, .shl, .shr => {
            if (operators_mod.isNumber(lhs) and operators_mod.isNumber(rhs)) return failNoIntegerRepresentation(self, thread, lhs);
            const operand_index: usize = if (!operators_mod.isNumber(lhs)) 0 else 1;
            const bad_value = if (operand_index == 0) lhs else rhs;
            appendFmt(self.allocator, &detail, "attempt to perform bitwise operation on a {s} value", .{metatable_mod.luaTypeNameForError(self, bad_value)}) catch return self.fail("attempt to perform operation on unsupported values");
            appendSiteOrigin(self, &detail, site, operand_index, true) catch return self.fail("attempt to perform operation on unsupported values");
        },
        .concat => {
            const operand_index: usize = if (!luaStringLike(lhs)) 0 else 1;
            const bad_value = if (operand_index == 0) lhs else rhs;
            appendFmt(self.allocator, &detail, "attempt to concatenate a {s} value", .{metatable_mod.luaTypeNameForError(self, bad_value)}) catch return self.fail("attempt to perform operation on unsupported values");
            appendSiteOrigin(self, &detail, site, operand_index, false) catch return self.fail("attempt to perform operation on unsupported values");
        },
    }
    return failRuntimeDetail(self, thread, detail.items);
}

pub fn failConcatRangeTypeError(self: *State, thread: *Thread, lhs: Value, rhs: Value, lhs_index: usize) RuntimeError {
    var detail = std.ArrayList(u8).empty;
    defer detail.deinit(self.allocator);
    const operand_index = if (!luaStringLike(lhs)) lhs_index else lhs_index + 1;
    const bad_value = if (!luaStringLike(lhs)) lhs else rhs;
    appendFmt(self.allocator, &detail, "attempt to concatenate a {s} value", .{metatable_mod.luaTypeNameForError(self, bad_value)}) catch return self.fail("attempt to perform operation on unsupported values");
    appendSiteOrigin(self, &detail, currentErrorSite(self, thread), operand_index, true) catch return self.fail("attempt to perform operation on unsupported values");
    return failRuntimeDetail(self, thread, detail.items);
}

pub fn failUnaryTypeError(self: *State, thread: *Thread, value: Value, op: operators_mod.UnaryMetamethodOp) RuntimeError {
    if (op == .bnot and operators_mod.isNumber(value)) return failNoIntegerRepresentation(self, thread, value);
    if (op == .unm and value == .string) return failRuntimeDetail(self, thread, "attempt to unm a 'string' with a 'string'");
    var detail = std.ArrayList(u8).empty;
    defer detail.deinit(self.allocator);
    const operation = switch (op) {
        .unm => "arithmetic",
        .bnot => "bitwise operation",
    };
    appendFmt(self.allocator, &detail, "attempt to perform {s} on a {s} value", .{ operation, metatable_mod.luaTypeNameForError(self, value) }) catch return self.fail("attempt to perform operation on unsupported value");
    appendSiteOrigin(self, &detail, currentErrorSite(self, thread), 0, op == .bnot) catch return self.fail("attempt to perform operation on unsupported value");
    return failRuntimeDetail(self, thread, detail.items);
}

pub fn failCompareTypeError(self: *State, thread: *Thread, lhs: Value, rhs: Value) RuntimeError {
    var detail = std.ArrayList(u8).empty;
    defer detail.deinit(self.allocator);
    const lhs_type = metatable_mod.luaTypeNameForError(self, lhs);
    const rhs_type = metatable_mod.luaTypeNameForError(self, rhs);
    if (std.mem.eql(u8, lhs_type, rhs_type)) {
        appendFmt(self.allocator, &detail, "attempt to compare two {s} values", .{lhs_type}) catch return self.fail("attempt to compare unsupported values");
    } else {
        appendFmt(self.allocator, &detail, "attempt to compare {s} with {s}", .{ lhs_type, rhs_type }) catch return self.fail("attempt to compare unsupported values");
    }
    return failRuntimeDetail(self, thread, detail.items);
}

pub fn failLengthTypeError(self: *State, thread: *Thread, value: Value) RuntimeError {
    var detail = std.ArrayList(u8).empty;
    defer detail.deinit(self.allocator);
    appendFmt(self.allocator, &detail, "attempt to get length of a {s} value", .{metatable_mod.luaTypeNameForError(self, value)}) catch return self.fail("attempt to get length of a non-string value");
    appendSiteOrigin(self, &detail, currentErrorSite(self, thread), 0, false) catch return self.fail("attempt to get length of a non-string value");
    return failRuntimeDetail(self, thread, detail.items);
}

pub fn failIndexTypeError(self: *State, thread: ?*Thread, value: Value) RuntimeError {
    return failAccessTypeError(self, thread, value, indexErrorMessage(value));
}

pub fn failNewIndexTypeError(self: *State, thread: ?*Thread, value: Value) RuntimeError {
    return failAccessTypeError(self, thread, value, indexErrorMessage(value));
}

pub fn failCallTypeError(self: *State, thread: *Thread, value: Value, call_name: ?[]const u8, call_namewhat: ?[]const u8) RuntimeError {
    var detail = std.ArrayList(u8).empty;
    defer detail.deinit(self.allocator);
    appendFmt(self.allocator, &detail, "attempt to call a {s} value", .{metatable_mod.luaTypeNameForError(self, value)}) catch return self.fail(callErrorMessage(value));
    if (call_name != null and call_namewhat != null and std.mem.eql(u8, call_namewhat.?, "metamethod")) {
        appendFmt(self.allocator, &detail, " (metamethod '{s}')", .{call_name.?}) catch return self.fail(callErrorMessage(value));
    } else {
        appendCallOrigin(self, &detail, currentErrorSite(self, thread)) catch return self.fail(callErrorMessage(value));
    }
    return failRuntimeDetail(self, thread, detail.items);
}

fn failAccessTypeError(self: *State, thread: ?*Thread, value: Value, fallback: []const u8) RuntimeError {
    var detail = std.ArrayList(u8).empty;
    defer detail.deinit(self.allocator);
    appendFmt(self.allocator, &detail, "attempt to index a {s} value", .{metatable_mod.luaTypeNameForError(self, value)}) catch return self.fail(fallback);
    const site = if (thread) |active| currentErrorSite(self, active) else null;
    appendSiteOrigin(self, &detail, site, 0, false) catch return self.fail(fallback);
    return failRuntimeDetail(self, thread, detail.items);
}

pub fn failForTypeError(self: *State, thread: *Thread, which: vm_mod.ForValueKind, value: Value) RuntimeError {
    var detail = std.ArrayList(u8).empty;
    defer detail.deinit(self.allocator);
    appendFmt(self.allocator, &detail, "bad 'for' {s} (number expected, got {s})", .{ vm_mod.forValueName(which), metatable_mod.luaTypeNameForError(self, value) }) catch return self.fail("bad 'for' value");
    return failRuntimeDetail(self, thread, detail.items);
}

fn appendRuntimeErrorPrefix(self: *State, out: *std.ArrayList(u8), thread: ?*Thread) !void {
    const active = thread orelse return;
    if (active.frames.items.len == 0) return;
    if (State.activeNativeCall(active) != null) return;
    if (active.frames.items[active.frames.items.len - 1].closure.stripped_debug) {
        try out.appendSlice(self.allocator, "?:?: ");
        return;
    }
    const site = currentErrorSite(self, active) orelse return;
    const frame = active.frames.items[active.frames.items.len - 1];
    try appendFmt(self.allocator, out, "{s}:{d}: ", .{ load_mod.runtimeSourceName(frame.closure.proto.source_name), site.line });
}

fn currentErrorSite(self: *State, thread: *Thread) ?proto_mod.ErrorSite {
    if (State.activeNativeCall(thread) != null) return null;
    return instructionErrorSite(self, thread);
}

pub fn instructionErrorSite(self: *State, thread: *Thread) ?proto_mod.ErrorSite {
    _ = self;
    if (thread.frames.items.len == 0) return null;
    const frame = thread.frames.items[thread.frames.items.len - 1];
    if (frame.closure.stripped_debug) return null;
    if (frame.pc == 0) return null;
    return frame.closure.proto.errorSiteAt(frame.pc - 1) orelse blk: {
        if (frame.closure.proto.line_info.items.len == 0) return null;
        const pc = @min(frame.pc - 1, frame.closure.proto.line_info.items.len - 1);
        break :blk proto_mod.ErrorSite{ .line = frame.closure.proto.line_info.items[pc].line, .op = .call };
    };
}

fn appendSiteOrigin(self: *State, out: *std.ArrayList(u8), site: ?proto_mod.ErrorSite, operand_index: usize, allow_constant: bool) !void {
    const active_site = site orelse return;
    if (operand_index >= active_site.operands.len) return;
    try appendOrigin(self, out, active_site.operands[operand_index], allow_constant);
}

fn appendCallOrigin(self: *State, out: *std.ArrayList(u8), site: ?proto_mod.ErrorSite) !void {
    const active_site = site orelse return;
    if (active_site.call_name) |origin| return appendOrigin(self, out, origin, false);
    if (active_site.operands.len != 0) return appendOrigin(self, out, active_site.operands[0], false);
}

fn appendOrigin(self: *State, out: *std.ArrayList(u8), origin: proto_mod.OperandOrigin, allow_constant: bool) !void {
    switch (origin) {
        .temporary => {},
        .local => |name| try appendFmt(self.allocator, out, " (local '{s}')", .{name}),
        .upvalue => |name| try appendFmt(self.allocator, out, " (upvalue '{s}')", .{name}),
        .global => |name| try appendFmt(self.allocator, out, " (global '{s}')", .{name}),
        .field => |name| try appendFmt(self.allocator, out, " (field '{s}')", .{name}),
        .method => |name| try appendFmt(self.allocator, out, " (method '{s}')", .{name}),
        .metamethod => |name| try appendFmt(self.allocator, out, " (metamethod '{s}')", .{name}),
        .constant => |value| if (allow_constant) try appendFmt(self.allocator, out, " (constant '{s}')", .{value}),
    }
}

pub fn errorDetailAlloc(self: *State, allocator: std.mem.Allocator, err: anyerror) ![]const u8 {
    if (self.last_error == null) return allocator.dupe(u8, @errorName(err));
    var out = std.ArrayList(u8).empty;
    defer out.deinit(allocator);
    try io_mod.appendErrorValue(allocator, &out, self.currentErrorValue());
    return allocator.dupe(u8, out.items);
}
