const std = @import("std");
const call_mod = @import("call.zig");
const rollback_mod = @import("rollback.zig");
const state_mod = @import("state.zig");
const types = @import("types.zig");
const value_mod = @import("value.zig");

const State = state_mod.State;
const Value = types.Value;
const appendNamedValue = value_mod.appendNamedValue;
const luaTypeName = value_mod.luaTypeName;
const Table = types.Table;
const Thread = types.Thread;

pub fn valueToString(self: *State, thread: *Thread, value: Value) anyerror![]const u8 {
    if (try getMetaEvent(self, value, .__tostring)) |metamethod| {
        const result = try call_mod.callOneResult(self, thread, metamethod, &.{value});
        return switch (result) {
            .string => |string| string,
            .integer, .number => {
                var buffer: [value_mod.max_number_text_len]u8 = undefined;
                return self.strings.intern(value_mod.formatNumber(&buffer, result));
            },
            else => self.failLibrary("'__tostring' must return a string"),
        };
    }

    if (try getMetaEvent(self, value, .__name)) |name| {
        if (name == .string) {
            var named = std.ArrayList(u8).empty;
            defer named.deinit(self.allocator);
            try appendNamedValue(self.allocator, &named, name.string, value);
            return self.strings.intern(named.items);
        }
    }

    var out = std.ArrayList(u8).empty;
    defer out.deinit(self.allocator);
    try value_mod.appendValue(self.allocator, &out, value);
    return self.strings.intern(out.items);
}

/// Ignores `__metatable`, as `debug.getmetatable` does.
pub fn rawMetatableValue(self: *State, value: Value) Value {
    const metatable = switch (value) {
        .table => |table| table.metatable,
        .userdata => |userdata| userdata.metatable,
        .string => self.string_metatable,
        .integer, .number => self.number_metatable,
        .boolean => self.boolean_metatable,
        .nil => self.nil_metatable,
        else => null,
    };
    return if (metatable) |table| .{ .table = table } else .nil;
}

pub fn getMetatableValue(self: *State, value: Value) !Value {
    const metatable = switch (value) {
        .table => |table| table.metatable orelse return .nil,
        .userdata => |userdata| userdata.metatable orelse return .nil,
        .string => self.string_metatable orelse return .nil,
        .integer, .number => self.number_metatable orelse return .nil,
        .boolean => self.boolean_metatable orelse return .nil,
        .nil => self.nil_metatable orelse return .nil,
        else => return .nil,
    };
    const locked = metatable.get(.{ .string = "__metatable" });
    if (locked != .nil) return locked;
    return .{ .table = metatable };
}

pub fn setMetatableValue(self: *State, table_value: Value, metatable_value: Value) !void {
    const table = try self.expectTable(table_value);
    if (table.metatable) |metatable| {
        if (metatable.get(.{ .string = "__metatable" }) != .nil) return self.failLibrary("cannot change a protected metatable");
    }
    const metatable = switch (metatable_value) {
        .nil => null,
        .table => |metatable| metatable,
        else => return self.fail("nil or table expected"),
    };
    setTableMetatableRaw(self, table, metatable);
    if (table.metatable) |active_metatable| self.gc.writeBarrier(table, .{ .table = active_metatable });
}

pub fn setDebugMetatableValue(self: *State, value: Value, metatable_value: Value) !void {
    const metatable = switch (metatable_value) {
        .nil => null,
        .table => |metatable| metatable,
        else => return self.fail("nil or table expected"),
    };
    switch (value) {
        .table => |table| {
            setTableMetatableRaw(self, table, metatable);
            if (metatable) |mt| self.gc.writeBarrier(table, .{ .table = mt });
        },
        .userdata => |userdata| {
            rollback_mod.touch(userdata);
            userdata.metatable = metatable;
            if (metatable) |mt| self.gc.writeBarrier(userdata, .{ .table = mt });
            self.gc.checkUserdataFinalizer(userdata);
        },
        .string => self.string_metatable = metatable,
        .integer, .number => self.number_metatable = metatable,
        .boolean => self.boolean_metatable = metatable,
        .nil => self.nil_metatable = metatable,
        else => return self.fail("cannot set metatable for this value"),
    }
    if (metatable) |mt| self.gc.markValue(.{ .table = mt });
}

pub fn getMetamethod(self: *State, value: Value, name: []const u8) !?Value {
    if (types.MetaEvent.fromName(name)) |event| return getMetaEvent(self, value, event);
    const metatable = switch (value) {
        .table => |table| table.metatable orelse return null,
        .userdata => |userdata| userdata.metatable orelse return null,
        .string => self.string_metatable orelse return null,
        .integer, .number => self.number_metatable orelse return null,
        .boolean => self.boolean_metatable orelse return null,
        .nil => self.nil_metatable orelse return null,
        else => return null,
    };
    const metamethod = metatable.get(.{ .string = name });
    return if (metamethod == .nil) null else metamethod;
}

pub fn getMetaEvent(self: *State, value: Value, event: types.MetaEvent) !?Value {
    const metatable = switch (value) {
        .table => |table| table.metatable orelse return null,
        .userdata => |userdata| userdata.metatable orelse return null,
        .string => self.string_metatable orelse return null,
        .integer, .number => self.number_metatable orelse return null,
        .boolean => self.boolean_metatable orelse return null,
        .nil => self.nil_metatable orelse return null,
        else => return null,
    };
    const metamethod = metatable.metaEvent(event);
    return if (metamethod == .nil) null else metamethod;
}

pub fn setTableMetatableRaw(self: *State, table: *Table, metatable: ?*Table) void {
    rollback_mod.touch(table);
    const old_has_metatable = table.metatable != null;
    table.metatable = metatable;
    self.gc.noteTableMetatableChanged(table, old_has_metatable);
    if (metatable) |mt| self.gc.writeBarrier(table, .{ .table = mt });
}

pub fn nextFinalizerOrder(self: *State) u64 {
    self.table_finalizer_serial += 1;
    return self.table_finalizer_serial;
}

pub fn luaTypeNameForError(self: *State, value: Value) []const u8 {
    if (getMetaEvent(self, value, .__name) catch null) |name| {
        if (name == .string) return name.string;
    }
    return luaTypeName(value);
}

pub fn getEitherMetamethod(self: *State, lhs: Value, rhs: Value, name: []const u8) !?Value {
    if (types.MetaEvent.fromName(name)) |event| {
        if (try getMetaEvent(self, lhs, event)) |metamethod| return metamethod;
        return getMetaEvent(self, rhs, event);
    }
    if (try getMetamethod(self, lhs, name)) |metamethod| return metamethod;
    return getMetamethod(self, rhs, name);
}

pub inline fn noMetaEvent(table: *const Table, comptime event: types.MetaEvent) bool {
    const metatable = table.metatable orelse return true;
    return metatable.metaEventAbsent(event);
}
