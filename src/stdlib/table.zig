const std = @import("std");
const compile = @import("../compile.zig");
const runtime = @import("../runtime.zig");
const call_mod = @import("../runtime/call.zig");
const index_mod = @import("../runtime/index.zig");
const operators_mod = @import("../runtime/operators.zig");

const bytecode = compile.bytecode;
const State = runtime.State;
const Thread = runtime.Thread;
const Value = runtime.Value;

pub fn concat(state: *State, thread: *Thread, op: bytecode.Call) !void {
    const table_value = runtime.argValue(state, thread, op, 0);
    _ = try state.expectArgumentTable(thread, op, "table.concat", 0);
    const len = try operators_mod.lengthInteger(state, thread, table_value);
    const sep = try state.optionalArgumentString(thread, op, "table.concat", 1) orelse "";
    const start = try state.optionalArgumentInteger(thread, op, "table.concat", 2, 1);
    const stop = try state.optionalArgumentInteger(thread, op, "table.concat", 3, len);
    var out = std.ArrayList(u8).empty;
    defer out.deinit(state.allocator);
    var index = start;
    while (index <= stop) : (index += 1) {
        if ((index -% start) & 0xfff == 0) try state.budget.checkInterrupt();
        if (index != start) try out.appendSlice(state.allocator, sep);
        const value = try index_mod.getTableFromThread(state, thread, table_value, .{ .integer = index });
        switch (value) {
            .integer, .number, .string => try runtime.appendLuaString(state.allocator, &out, value),
            else => return state.failLibraryFmt("invalid value ({s}) at index {d} in table for 'concat'", .{ runtime.typeName(value), index }),
        }
        if (index == std.math.maxInt(i64)) break;
    }
    try state.returnValues(thread, op.base, op.return_count, &.{.{ .string = try state.strings.intern(out.items) }});
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
    _ = try state.expectArgumentTable(thread, op, "table.insert", 0);
    const first_empty = (try operators_mod.lengthInteger(state, thread, table_value)) +% 1;
    if (op.arg_count < 2 or op.arg_count > 3) return state.failLibrary("wrong number of arguments to 'insert'");
    const pos = if (op.arg_count == 2) first_empty else try state.argumentInteger(thread, op, "table.insert", 1);
    const value = if (op.arg_count == 2) runtime.argValue(state, thread, op, 1) else runtime.argValue(state, thread, op, 2);
    if (op.arg_count == 3 and @as(u64, @bitCast(pos)) -% 1 >= @as(u64, @bitCast(first_empty))) return state.failArgumentMessage("table.insert", 2, "position out of bounds");
    var index = first_empty;
    while (index > pos) : (index -= 1) {
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
    _ = try state.expectArgumentTable(thread, op, "table.move", 0);
    const dest_value = if (op.arg_count >= 5 and runtime.argValue(state, thread, op, 4) != .nil) runtime.argValue(state, thread, op, 4) else runtime.argValue(state, thread, op, 0);
    if (dest_value != .table) return state.failArgumentType("table.move", 5, "table", dest_value);
    if (last >= first) {
        const count_i = @as(i128, last) - @as(i128, first) + 1;
        if (count_i > std.math.maxInt(i64)) return state.failArgumentMessage("table.move", 3, "too many elements to move");
        const dest_end = @as(i128, dest_start) + count_i - 1;
        if (dest_end < std.math.minInt(i64) or dest_end > std.math.maxInt(i64)) return state.failArgumentMessage("table.move", 4, "destination wrap around");
        const count: i64 = @intCast(count_i);
        if (runtime.valuesEqual(src_value, dest_value) and dest_start > first and dest_start <= last) {
            var offset = count - 1;
            while (true) {
                const value = try index_mod.getTableFromThread(state, thread, src_value, .{ .integer = first + offset });
                try index_mod.setTableFromThread(state, thread, dest_value, .{ .integer = dest_start + offset }, value);
                if (offset == 0) break;
                offset -= 1;
            }
        } else {
            var offset: i64 = 0;
            while (offset < count) : (offset += 1) {
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
    try state.setTableRaw(table, .{ .string = try state.strings.intern("n") }, .{ .integer = op.arg_count });
    try state.returnValues(thread, op.base, op.return_count, &.{table_value});
}

pub fn remove(state: *State, thread: *Thread, op: bytecode.Call) !void {
    const table_value = runtime.argValue(state, thread, op, 0);
    _ = try state.expectArgumentTable(thread, op, "table.remove", 0);
    const size = try operators_mod.lengthInteger(state, thread, table_value);
    const pos = try state.optionalArgumentInteger(thread, op, "table.remove", 1, size);
    if (pos != size and @as(u64, @bitCast(pos)) -% 1 > @as(u64, @bitCast(size))) return state.failArgumentMessage("table.remove", 2, "position out of bounds");
    const removed = try index_mod.getTableFromThread(state, thread, table_value, .{ .integer = pos });
    const removed_root = if (pos < size) try state.rootValue(removed) else null;
    defer if (removed_root) |root| state.unrootValue(root);
    var index = pos;
    while (index < size) : (index += 1) {
        const shifted = try index_mod.getTableFromThread(state, thread, table_value, .{ .integer = index + 1 });
        try index_mod.setTableFromThread(state, thread, table_value, .{ .integer = index }, shifted);
    }
    try index_mod.setTableFromThread(state, thread, table_value, .{ .integer = index }, .nil);
    try state.returnValues(thread, op.base, op.return_count, &.{removed});
}

pub fn sort(state: *State, thread: *Thread, op: bytecode.Call) !void {
    const table_value = runtime.argValue(state, thread, op, 0);
    _ = try state.expectArgumentTable(thread, op, "table.sort", 0);
    const comparator = if (op.arg_count >= 2) runtime.argValue(state, thread, op, 1) else Value.nil;
    const len = try operators_mod.lengthInteger(state, thread, table_value);
    if (len > 1_000_000) return state.failArgumentMessage("table.sort", 1, "array too big");
    if (len > 1 and comparator != .nil and !std.mem.eql(u8, runtime.typeName(comparator), "function")) {
        return state.failArgumentType("table.sort", 2, "function", comparator);
    }
    if (len > 1) {
        const count: usize = @intCast(len);
        const values = try state.allocator.alloc(Value, count);
        defer state.allocator.free(values);
        @memset(values, .nil);
        var roots: runtime.ValueRoots = undefined;
        state.pushValueRoots(&roots, values);
        defer state.popValueRoots(&roots);
        for (values, 0..) |*slot, index| slot.* = try index_mod.getTableFromThread(state, thread, table_value, .{ .integer = @intCast(index + 1) });
        var sorter = Sorter{ .state = state, .thread = thread, .comparator = comparator, .values = values };
        try sorter.auxsort(1, count, 0);
        for (values, 0..) |value, index| try index_mod.setTableFromThread(state, thread, table_value, .{ .integer = @intCast(index + 1) }, value);
    }
    try state.returnValues(thread, op.base, op.return_count, &.{});
}

/// Port of Lua 5.5's `auxsort` over a 1-based view of `values`, so comparator calls
/// and invalid-order detection match the reference implementation.
const Sorter = struct {
    state: *State,
    thread: *Thread,
    comparator: Value,
    values: []Value,

    fn at(self: *Sorter, index: usize) *Value {
        return &self.values[index - 1];
    }

    fn swap(self: *Sorter, lhs: usize, rhs: usize) void {
        std.mem.swap(Value, self.at(lhs), self.at(rhs));
    }

    fn less(self: *Sorter, lhs: Value, rhs: Value) !bool {
        if (self.comparator == .nil) return operators_mod.compareValues(self.state, self.thread, lhs, rhs, .lt);
        return runtime.truthy(try call_mod.callOneResult(self.state, self.thread, self.comparator, &.{ lhs, rhs }));
    }

    fn auxsort(self: *Sorter, lower: usize, upper: usize, seed: u32) !void {
        var lo = lower;
        var up = upper;
        var rnd = seed;
        while (lo < up) {
            try self.state.budget.checkInterrupt();
            if (try self.less(self.at(up).*, self.at(lo).*)) self.swap(lo, up);
            if (up - lo == 1) break;
            var p = if (up - lo < 100 or rnd == 0) (lo + up) / 2 else choosePivot(lo, up, rnd);
            if (try self.less(self.at(p).*, self.at(lo).*)) {
                self.swap(p, lo);
            } else if (try self.less(self.at(up).*, self.at(p).*)) {
                self.swap(p, up);
            }
            if (up - lo == 2) break;
            const pivot = self.at(p).*;
            self.swap(p, up - 1);
            p = try self.partition(lo, up, pivot);
            var smaller: usize = undefined;
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
    }

    fn partition(self: *Sorter, lo: usize, up: usize, pivot: Value) !usize {
        var i = lo;
        var j = up - 1;
        while (true) {
            i += 1;
            while (try self.less(self.at(i).*, pivot)) : (i += 1) {
                if (i == up - 1) return self.state.failLibrary("invalid order function for sorting");
            }
            j -= 1;
            while (try self.less(pivot, self.at(j).*)) : (j -= 1) {
                if (j < i) return self.state.failLibrary("invalid order function for sorting");
            }
            if (j < i) {
                self.swap(up - 1, i);
                return i;
            }
            self.swap(i, j);
        }
    }

    fn choosePivot(lo: usize, up: usize, rnd: u32) usize {
        const r4 = (up - lo) / 4;
        return rnd % (r4 * 2) + (lo + r4);
    }

    fn randomizePivot(lo: usize, up: usize, smaller: usize) u32 {
        const mixed = (@as(u64, lo) *% 0x9e3779b97f4a7c15) ^ (@as(u64, up) << 17) ^ smaller;
        return @truncate(mixed ^ (mixed >> 32));
    }
};

pub fn unpack(state: *State, thread: *Thread, op: bytecode.Call) !void {
    const table_value = runtime.argValue(state, thread, op, 0);
    const start = try state.optionalArgumentInteger(thread, op, "table.unpack", 1, 1);
    const stop = if (runtime.argValue(state, thread, op, 2) == .nil) try operators_mod.lengthInteger(state, thread, table_value) else try state.argumentInteger(thread, op, "table.unpack", 2);
    const count = @as(i128, stop) - @as(i128, start) + 1;
    if (count > 0 and (count > std.math.maxInt(u32) or !call_mod.nativeStackFits(state, thread, op, @intCast(count)))) return state.failLibrary("too many results to unpack");
    const values = try state.allocator.alloc(Value, if (count > 0) @intCast(count) else 0);
    defer state.allocator.free(values);
    @memset(values, .nil);
    var roots: runtime.ValueRoots = undefined;
    state.pushValueRoots(&roots, values);
    defer state.popValueRoots(&roots);
    for (values, 0..) |*slot, offset| slot.* = try index_mod.getTableFromThread(state, thread, table_value, .{ .integer = start + @as(i64, @intCast(offset)) });
    try state.returnValues(thread, op.base, op.return_count, values);
}
