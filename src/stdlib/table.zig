const std = @import("std");
const cost = @import("../runtime/budget.zig").cost;
const compile = @import("../compile.zig");
const runtime = @import("../runtime.zig");
const call_mod = @import("../runtime/call.zig");
const index_mod = @import("../runtime/index.zig");
const metatable_mod = @import("../runtime/metatable.zig");
const operators_mod = @import("../runtime/operators.zig");
const static_strings = @import("static_strings.zig");

const bytecode = compile.bytecode;
const State = runtime.State;
const Thread = runtime.Thread;
const Value = runtime.Value;

/// Table operations an argument must support, either natively or through metamethods.
const TableOps = struct {
    read: bool = false,
    write: bool = false,
    length: bool = false,
};

fn checkTable(state: *State, thread: *Thread, op: bytecode.Call, function_name: []const u8, index: u32, ops: TableOps) !void {
    const value = runtime.argValue(state, thread, op, index);
    if (value == .table) return;
    const metatable = metatable_mod.rawMetatableValue(state, value);
    if (metatable == .table and
        (!ops.read or metatable.table.getLiteral("__index") != .nil) and
        (!ops.write or metatable.table.getLiteral("__newindex") != .nil) and
        (!ops.length or value == .string or metatable.table.getLiteral("__len") != .nil)) return;
    return state.failArgumentType(function_name, index + 1, "table", value);
}

pub fn concat(state: *State, thread: *Thread, op: bytecode.Call) !void {
    const table_value = runtime.argValue(state, thread, op, 0);
    try checkTable(state, thread, op, "table.concat", 0, .{ .read = true, .length = true });
    const len = try operators_mod.lengthInteger(state, thread, table_value);
    const sep = try state.optionalArgumentString(thread, op, "table.concat", 1) orelse "";
    const start = try state.optionalArgumentInteger(thread, op, "table.concat", 2, 1);
    const stop = try state.optionalArgumentInteger(thread, op, "table.concat", 3, len);
    var out = state.strings.builder();
    defer out.deinit();
    var index = start;
    while (index <= stop) : (index += 1) {
        try state.budget.charge(2);
        if (index != start) try out.appendSlice(sep);
        const next_len = if (table_value == .table) switch (table_value.table.get(.{ .integer = index })) {
            .string => |string| string.len,
            else => 0,
        } else 0;
        try state.gc.reserve(thread, (out.buffer.items.len +| next_len) *| 2);
        const value = try index_mod.getTableFromThread(state, thread, table_value, .{ .integer = index });
        switch (value) {
            .integer, .number, .string => try runtime.appendLuaString(state.allocator, &out.buffer, value),
            else => return state.failLibraryFmt("invalid value ({s}) at index {d} in table for 'concat'", .{ runtime.typeName(value), index }),
        }
        if (index == std.math.maxInt(i64)) break;
    }
    try state.returnValues(thread, op.base, op.return_count, &.{.{ .string = try out.finish() }});
}

/// Unique sequence elements in first-occurrence order, compared by raw key equality.
pub fn dedup(state: *State, thread: *Thread, op: bytecode.Call) !void {
    const table_value = runtime.argValue(state, thread, op, 0);
    _ = try state.expectArgumentTable(thread, op, "table.dedup", 0);
    const len = try operators_mod.lengthInteger(state, thread, table_value);
    if (len > 1_000_000) return state.fail("array too big");
    const count: u32 = if (len > 0) @intCast(len) else 0;

    var seen = try runtime.Table.init(state.allocator, 0, count);
    defer seen.deinit(state.allocator);

    const result = try state.newTableWithHints(count, 0);
    const result_root = try state.rootValue(result);
    defer state.unrootValue(result_root);

    var result_index: i64 = 1;
    var index: i64 = 1;
    while (index <= len) : (index += 1) {
        try state.budget.charge(4);
        const value = try index_mod.getTableFromThread(state, thread, table_value, .{ .integer = index });
        if (value == .nil) continue;
        const is_nan = value == .number and std.math.isNan(value.number);
        const seen_key = if (value == .number) if (runtime.floatToInteger(value.number)) |integer| Value{ .integer = integer } else value else value;
        if (!is_nan and seen.get(seen_key) != .nil) continue;
        if (!is_nan) try seen.set(state.allocator, seen_key, .{ .boolean = true });
        try state.setTableRaw(result.table, .{ .integer = result_index }, value);
        result_index += 1;
    }

    try state.returnValues(thread, op.base, op.return_count, &.{result});
}

pub fn insert(state: *State, thread: *Thread, op: bytecode.Call) !void {
    const table_value = runtime.argValue(state, thread, op, 0);
    try checkTable(state, thread, op, "table.insert", 0, .{ .read = true, .write = true, .length = true });
    const first_empty = (try operators_mod.lengthInteger(state, thread, table_value)) +% 1;
    if (op.arg_count < 2 or op.arg_count > 3) return state.failLibrary("wrong number of arguments to 'insert'");
    const pos = if (op.arg_count == 2) first_empty else try state.argumentInteger(thread, op, "table.insert", 1);
    const value = if (op.arg_count == 2) runtime.argValue(state, thread, op, 1) else runtime.argValue(state, thread, op, 2);
    if (op.arg_count == 3 and @as(u64, @bitCast(pos)) -% 1 >= @as(u64, @bitCast(first_empty))) return state.failArgumentMessage("table.insert", 2, "position out of bounds");
    var index = first_empty;
    while (index > pos) : (index -= 1) {
        try state.budget.charge(2);
        const shifted = try index_mod.getTableFromThread(state, thread, table_value, .{ .integer = index - 1 });
        try index_mod.setTableFromThread(state, thread, table_value, .{ .integer = index }, shifted);
    }
    try index_mod.setTableFromThread(state, thread, table_value, .{ .integer = pos }, value);
    try state.returnValues(thread, op.base, op.return_count, &.{});
}

pub fn move(state: *State, thread: *Thread, op: bytecode.Call) !void {
    const src_value = runtime.argValue(state, thread, op, 0);
    const first = try state.argumentInteger(thread, op, "table.move", 1);
    const last = try state.argumentInteger(thread, op, "table.move", 2);
    const dest_start = try state.argumentInteger(thread, op, "table.move", 3);
    const dest_index: u32 = if (op.arg_count >= 5 and runtime.argValue(state, thread, op, 4) != .nil) 4 else 0;
    try checkTable(state, thread, op, "table.move", 0, .{ .read = true });
    try checkTable(state, thread, op, "table.move", dest_index, .{ .write = true });
    const dest_value = runtime.argValue(state, thread, op, dest_index);
    if (last >= first) {
        const count_i = @as(i128, last) - @as(i128, first) + 1;
        if (count_i > std.math.maxInt(i64)) return state.failArgumentMessage("table.move", 3, "too many elements to move");
        const dest_end = @as(i128, dest_start) + count_i - 1;
        if (dest_end < std.math.minInt(i64) or dest_end > std.math.maxInt(i64)) return state.failArgumentMessage("table.move", 4, "destination wrap around");
        const count: i64 = @intCast(count_i);
        if (runtime.valuesEqual(src_value, dest_value) and dest_start > first and dest_start <= last) {
            var offset = count - 1;
            while (true) {
                try state.budget.charge(2);
                const value = try index_mod.getTableFromThread(state, thread, src_value, .{ .integer = first + offset });
                try index_mod.setTableFromThread(state, thread, dest_value, .{ .integer = dest_start + offset }, value);
                if (offset == 0) break;
                offset -= 1;
            }
        } else {
            var offset: i64 = 0;
            while (offset < count) : (offset += 1) {
                try state.budget.charge(2);
                const value = try index_mod.getTableFromThread(state, thread, src_value, .{ .integer = first + offset });
                try index_mod.setTableFromThread(state, thread, dest_value, .{ .integer = dest_start + offset }, value);
            }
        }
    }
    try state.returnValues(thread, op.base, op.return_count, &.{dest_value});
}

pub fn pack(state: *State, thread: *Thread, op: bytecode.Call) !void {
    const table_value = try state.newTableWithHints(op.arg_count, 1);
    const table = table_value.table;
    for (0..op.arg_count) |index| try state.setTableRaw(table, .{ .integer = @intCast(index + 1) }, runtime.argValue(state, thread, op, @intCast(index)));
    try state.setTableRaw(table, .{ .string = static_strings.get("n") }, .{ .integer = op.arg_count });
    try state.returnValues(thread, op.base, op.return_count, &.{table_value});
}

pub fn remove(state: *State, thread: *Thread, op: bytecode.Call) !void {
    const table_value = runtime.argValue(state, thread, op, 0);
    try checkTable(state, thread, op, "table.remove", 0, .{ .read = true, .write = true, .length = true });
    const size = try operators_mod.lengthInteger(state, thread, table_value);
    const pos = try state.optionalArgumentInteger(thread, op, "table.remove", 1, size);
    if (pos != size and @as(u64, @bitCast(pos)) -% 1 > @as(u64, @bitCast(size))) return state.failArgumentMessage("table.remove", 2, "position out of bounds");
    const removed = try index_mod.getTableFromThread(state, thread, table_value, .{ .integer = pos });
    const removed_root = try state.rootValue(removed);
    defer state.unrootValue(removed_root);
    var index = pos;
    while (index < size) : (index += 1) {
        try state.budget.charge(2);
        const shifted = try index_mod.getTableFromThread(state, thread, table_value, .{ .integer = index + 1 });
        try index_mod.setTableFromThread(state, thread, table_value, .{ .integer = index }, shifted);
    }
    try index_mod.setTableFromThread(state, thread, table_value, .{ .integer = index }, .nil);
    try state.returnValues(thread, op.base, op.return_count, &.{removed});
}

pub fn sort(state: *State, thread: *Thread, op: bytecode.Call) !void {
    const table_value = runtime.argValue(state, thread, op, 0);
    try checkTable(state, thread, op, "table.sort", 0, .{ .read = true, .write = true, .length = true });
    const len = try operators_mod.lengthInteger(state, thread, table_value);
    if (len > 1) {
        if (len >= std.math.maxInt(i32)) return state.failArgumentMessage("table.sort", 1, "array too big");
        const comparator = if (op.arg_count >= 2) runtime.argValue(state, thread, op, 1) else Value.nil;
        if (comparator != .nil and !std.mem.eql(u8, runtime.typeName(comparator), "function")) {
            return state.failArgumentType("table.sort", 2, "function", comparator);
        }
        var sorter = Sorter{ .state = state, .thread = thread, .table = table_value, .comparator = comparator };
        state.pushValueRoots(&sorter.roots, &sorter.held);
        defer state.popValueRoots(&sorter.roots);
        try sorter.auxsort(1, @intCast(len), 0);
    }
    try state.returnValues(thread, op.base, op.return_count, &.{});
}

/// Lua 5.5's `auxsort`, reading and writing the table like `lua_geti` and `lua_seti`.
const Sorter = struct {
    state: *State,
    thread: *Thread,
    table: Value,
    comparator: Value,
    /// The pivot and the two elements being compared.
    held: [3]Value = .{ .nil, .nil, .nil },
    roots: runtime.ValueRoots = undefined,

    const pivot = 0;
    const first = 1;
    const second = 2;

    inline fn arraySlot(self: *Sorter, index: u32) ?*Value {
        if (self.table != .table) return null;
        const table = self.table.table;
        if (index > table.array.len) return null;
        const slot = &table.array.items()[index - 1];
        return if (slot.* != .nil) slot else null;
    }

    fn get(self: *Sorter, slot: usize, index: u32) !void {
        if (self.arraySlot(index)) |element| {
            self.held[slot] = element.*;
            return;
        }
        self.held[slot] = try index_mod.getTableFromThread(self.state, self.thread, self.table, .{ .integer = index });
    }

    fn set(self: *Sorter, index: u32, slot: usize) !void {
        const value = self.held[slot];
        if (self.arraySlot(index)) |element| {
            const table = self.table.table;
            const detached = if (table.rollback) |record| record.header.detached else true;
            if (detached) {
                element.* = value;
                self.state.gc.writeExistingKeyBarrier(table, .{ .integer = index }, value);
                return;
            }
        }
        try index_mod.setTableFromThread(self.state, self.thread, self.table, .{ .integer = index }, value);
    }

    /// Stores `held[a]` at `i`, then `held[b]` at `j`.
    fn set2(self: *Sorter, i: u32, a: usize, j: u32, b: usize) !void {
        try self.set(i, a);
        try self.set(j, b);
    }

    fn less(self: *Sorter, lhs: usize, rhs: usize) !bool {
        if (self.comparator == .nil) return operators_mod.compareValues(self.state, self.thread, self.held[lhs], self.held[rhs], .lt);
        return runtime.truthy(try call_mod.callOneResult(self.state, self.thread, self.comparator, &.{ self.held[lhs], self.held[rhs] }));
    }

    fn auxsort(self: *Sorter, lower: u32, upper: u32, seed: u32) !void {
        var lo = lower;
        var up = upper;
        var rnd = seed;
        while (lo < up) {
            try self.state.budget.charge(cost.elements(up - lo));
            try self.get(first, lo);
            try self.get(second, up);
            if (try self.less(second, first)) try self.set2(lo, second, up, first);
            if (up - lo == 1) break;
            var p = if (up - lo < 100 or rnd == 0) (lo + up) / 2 else choosePivot(lo, up, rnd);
            try self.get(first, p);
            try self.get(second, lo);
            if (try self.less(first, second)) {
                try self.set2(p, second, lo, first);
            } else {
                try self.get(second, up);
                if (try self.less(second, first)) try self.set2(p, second, up, first);
            }
            if (up - lo == 2) break;
            try self.get(pivot, p);
            try self.get(first, up - 1);
            try self.set2(p, first, up - 1, pivot);
            p = try self.partition(lo, up);
            self.held = .{ .nil, .nil, .nil };
            var smaller: u32 = undefined;
            if (p - lo < up - p) {
                try self.auxsort(lo, p - 1, rnd);
                smaller = p - lo;
                lo = p + 1;
            } else {
                try self.auxsort(p + 1, up, rnd);
                smaller = up - p;
                up = p - 1;
            }
            if ((up -% lo) / 128 > smaller and up > lo) rnd = randomizePivot(lo, up, smaller);
        }
        self.held = .{ .nil, .nil, .nil };
    }

    /// Expects the pivot in `held[pivot]` and at `up - 1`.
    fn partition(self: *Sorter, lo: u32, up: u32) !u32 {
        var i = lo;
        var j = up - 1;
        while (true) {
            i += 1;
            try self.get(first, i);
            while (try self.less(first, pivot)) {
                if (i == up - 1) return self.state.failLibrary("invalid order function for sorting");
                i += 1;
                try self.get(first, i);
            }
            j -= 1;
            try self.get(second, j);
            while (try self.less(pivot, second)) {
                if (j < i) return self.state.failLibrary("invalid order function for sorting");
                j -= 1;
                try self.get(second, j);
            }
            if (j < i) {
                try self.set2(up - 1, first, i, pivot);
                return i;
            }
            try self.set2(i, second, j, first);
        }
    }

    fn choosePivot(lo: u32, up: u32, rnd: u32) u32 {
        const r4 = (up - lo) / 4;
        return (rnd ^ lo ^ up) % (r4 * 2) + (lo + r4);
    }

    fn randomizePivot(lo: u32, up: u32, smaller: u32) u32 {
        const mixed = (@as(u64, lo) *% 0x9e3779b97f4a7c15) ^ (@as(u64, up) << 17) ^ smaller;
        return @truncate(mixed ^ (mixed >> 32));
    }
};

pub fn unpack(state: *State, thread: *Thread, op: bytecode.Call) !void {
    const table_value = runtime.argValue(state, thread, op, 0);
    try checkTable(state, thread, op, "table.unpack", 0, .{ .read = true, .length = true });
    const len = try operators_mod.lengthInteger(state, thread, table_value);
    const start = try state.optionalArgumentInteger(thread, op, "table.unpack", 1, 1);
    const stop = try state.optionalArgumentInteger(thread, op, "table.unpack", 2, len);
    const count = @as(i128, stop) - @as(i128, start) + 1;
    if (count > 0 and (count > std.math.maxInt(u32) or !call_mod.nativeStackFits(state, thread, op, @intCast(count)))) return state.failLibrary("too many results to unpack");
    if (count > 0) try state.budget.charge(cost.elements(@intCast(count)));
    const values = try state.allocator.alloc(Value, if (count > 0) @intCast(count) else 0);
    defer state.allocator.free(values);
    @memset(values, .nil);
    var roots: runtime.ValueRoots = undefined;
    state.pushValueRoots(&roots, values);
    defer state.popValueRoots(&roots);
    for (values, 0..) |*slot, offset| slot.* = try index_mod.getTableFromThread(state, thread, table_value, .{ .integer = start + @as(i64, @intCast(offset)) });
    try state.returnValues(thread, op.base, op.return_count, values);
}
