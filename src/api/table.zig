const std = @import("std");
const reflection = @import("../reflection.zig");
const runtime = @import("../runtime.zig");
const rollback_runtime = @import("../runtime/rollback.zig");
const callbacks = @import("callbacks.zig");
const convert = @import("convert.zig");
const errors = @import("errors.zig");
const handle = @import("handle.zig");
const state_mod = @import("state.zig");
const Ref = handle.Ref;
const State = state_mod.State;
const Value = @import("value.zig").Value;
const entry_mod = @import("../runtime/entry.zig");
const metatable_mod = @import("../runtime/metatable.zig");
const operators_mod = @import("../runtime/operators.zig");

/// Rooted handle to a Lua table.
pub const Table = struct {
    ref: Ref,

    pub fn deinit(self: *Table) void {
        self.ref.deinit();
        self.* = undefined;
    }

    /// Reads `t[key]` honoring `__index`; metamethods cannot yield and fail with `error.LuaError`.
    /// A `[]const u8` result borrows VM memory; see `Value.string`.
    pub fn get(self: Table, key: anytype, comptime T: type) !T {
        const state = self.ref.state;
        const raw = try self.rawValue();
        const raw_key = try convert.toRuntimeValue(state, key);
        const raw_value = indexTable(state, raw.table, raw_key) catch |err| return errors.captureLuaError(state, err);
        return convert.fromRuntimeValue(state, raw_value, T);
    }

    /// Assigns `t[key]` honoring `__newindex`; metamethods cannot yield.
    /// A nil or NaN key returns `error.LuaError`.
    pub fn set(self: Table, key: anytype, value: anytype) !void {
        const state = self.ref.state;
        const raw = try self.rawValue();
        const raw_key = try convert.toRuntimeValue(state, key);
        const raw_value = try convert.toRuntimeValue(state, value);
        assignTable(state, raw.table, raw_key, raw_value) catch |err| return errors.captureLuaError(state, err);
        try state_mod.gcBoundary(state);
    }

    /// Like `set` without `__newindex`; a nil or NaN key returns `error.LuaError`.
    pub fn rawSet(self: Table, key: anytype, value: anytype) !void {
        const state = self.ref.state;
        const raw = try self.rawValue();
        const raw_key = try convert.toRuntimeValue(state, key);
        const raw_value = try convert.toRuntimeValue(state, value);
        storeRaw(state, raw.table, try writableTableKey(state, raw_key), raw_value) catch |err| return errors.captureLuaError(state, err);
        try state_mod.gcBoundary(state);
    }

    /// Raw-appends at `rawLen() + 1`; appending nil is a no-op.
    pub fn append(self: Table, value: anytype) !void {
        const state = self.ref.state;
        const raw = try self.rawValue();
        const raw_value = try convert.toRuntimeValue(state, value);
        const length = raw.table.len();
        if (length == std.math.maxInt(i64)) return errors.captureLuaError(state, state.raw_state.fail("table overflow"));
        storeRaw(state, raw.table, .{ .integer = length + 1 }, raw_value) catch |err| return errors.captureLuaError(state, err);
        try state_mod.gcBoundary(state);
    }

    /// Lua `#t` honoring `__len`, which cannot yield; a non-integer result returns `error.LuaError`.
    pub fn len(self: Table) !i64 {
        const state = self.ref.state;
        const raw = try self.rawValue();
        const handler = (metatable_mod.getMetamethod(&state.raw_state, raw, "__len") catch |err| return errors.captureLuaError(state, err)) orelse return raw.table.len();
        const result = callFirstResult(state, handler, &.{ raw, raw }) catch |err| return errors.captureLuaError(state, err);
        return operators_mod.lengthToInteger(&state.raw_state, result) catch |err| return errors.captureLuaError(state, err);
    }

    pub fn rawLen(self: Table) !i64 {
        return (try self.rawValue()).table.len();
    }

    /// State-local, non-retaining token valid while rooted and until reset.
    pub fn identity(self: Table) !usize {
        return @intFromPtr((try self.rawValue()).table);
    }

    /// Ignores `__metatable`. The caller must `deinit` the result.
    pub fn getMetatable(self: Table) !?Table {
        const meta = (try self.rawValue()).table.metatable orelse return null;
        return try convert.fromRuntimeValue(self.ref.state, .{ .table = meta }, Table);
    }

    /// Sets or removes the metatable, ignoring `__metatable` like `lua_setmetatable`.
    pub fn setMetatable(self: Table, metatable: ?Table) !void {
        const state = self.ref.state;
        const raw = try self.rawValue();
        const raw_metatable: runtime.Value = if (metatable) |table| try convert.toRuntimeValue(state, table) else .nil;
        metatable_mod.setDebugMetatableValue(&state.raw_state, raw, raw_metatable) catch |err| return errors.captureLuaError(state, err);
    }

    /// A `[]const u8` result borrows VM memory; see `Value.string`.
    pub fn rawGet(self: Table, key: anytype, comptime T: type) !T {
        const state = self.ref.state;
        const raw = try self.rawValue();
        const raw_key = readableTableKey(try convert.toRuntimeValue(state, key)) orelse return convert.fromRuntimeValue(state, .nil, T);
        return convert.fromRuntimeValue(state, raw.table.get(raw_key), T);
    }

    /// Reads raw entries `1..rawLen()`; holes fail with `error.TypeMismatch` unless `T` is optional.
    /// The caller frees the slice and deinits handle elements; string elements borrow VM memory.
    pub fn toSlice(self: Table, comptime T: type, allocator: std.mem.Allocator) ![]T {
        const state = self.ref.state;
        const table = (try self.rawValue()).table;
        const count = std.math.cast(usize, table.len()) orelse return error.OutOfMemory;
        const items = try allocator.alloc(T, count);
        errdefer allocator.free(items);
        var initialized: usize = 0;
        errdefer for (items[0..initialized]) |*item| convert.deinitIfOwned(T, item);
        for (items, 1..) |*item, index| {
            item.* = try convert.fromRuntimeValue(state, table.get(.{ .integer = @intCast(index) }), T);
            initialized += 1;
        }
        return items;
    }

    /// String fields borrow VM memory; see `Value.string`.
    pub const Entry = struct {
        key: Value,
        value: Value,

        /// Only for `rawNext` entries; `Iterator` owns the entries it returns.
        pub fn deinit(self: *Entry) void {
            self.key.deinit();
            self.value.deinit();
        }
    };

    /// Lua `next`: start with null or `.nil`; deinit each entry. Prefer `rawIterator`.
    pub fn rawNext(self: Table, key: anytype) !?Entry {
        const state = self.ref.state;
        const raw = try self.rawValue();
        const raw_key = readableTableKey(try convert.toRuntimeValue(state, key)) orelse runtime.Value.nil;
        const pair = raw.table.next(raw_key) catch return errors.captureLuaError(state, state.raw_state.fail("invalid key to 'next'"));
        if (pair[0] == .nil) return null;
        var owned_key = try convert.fromRuntimeValue(state, pair[0], Value);
        errdefer owned_key.deinit();
        return .{ .key = owned_key, .value = try convert.fromRuntimeValue(state, pair[1], Value) };
    }

    /// Raw-entry iterator like Lua `next`; the caller must `deinit` it. Existing fields may be
    /// assigned or cleared during traversal; adding keys is undefined.
    pub fn rawIterator(self: Table) !Iterator {
        const raw = try self.rawValue();
        var iterator = Iterator.init(self.ref.state, .raw);
        errdefer iterator.deinit();
        try iterator.store(.target, raw);
        return iterator;
    }

    /// Iterator like Lua `pairs(t)`, honoring `__pairs`; its calls cannot yield. A closing value
    /// gets `__close` when iteration ends, fails, or `close` is called, but not on `deinit`.
    pub fn pairs(self: Table) !Iterator {
        const state = self.ref.state;
        const raw = try self.rawValue();
        const handler = (metatable_mod.getMetamethod(&state.raw_state, raw, "__pairs") catch |err| return errors.captureLuaError(state, err)) orelse return self.rawIterator();
        const results = entry_mod.callFunction(&state.raw_state, handler, &.{raw}) catch |err| return errors.captureLuaError(state, err);
        defer state.allocator().free(results);
        const result = struct {
            fn at(values: []const runtime.Value, index: usize) runtime.Value {
                return if (index < values.len) values[index] else .nil;
            }
        }.at;
        var iterator = Iterator.init(state, .call);
        errdefer iterator.deinit();
        try iterator.store(.target, result(results, 0));
        try iterator.store(.invariant, result(results, 1));
        try iterator.store(.control, result(results, 2));
        const closing = result(results, 3);
        if (runtime.truthy(closing)) {
            const close_handler = metatable_mod.getMetamethod(&state.raw_state, closing, "__close") catch |err| return errors.captureLuaError(state, err);
            if (close_handler == null) return errors.captureLuaError(state, state.raw_state.fail("variable '(for state)' got a non-closable value"));
            try iterator.store(.closing, closing);
        }
        return iterator;
    }

    /// Owns each returned `Entry` until the next `next`, `close`, or `deinit`; do not deinit entries.
    /// Reset invalidates the iterator.
    pub const Iterator = struct {
        state: *State,
        generation: u64,
        mode: Mode,
        roots: [slot_count]?usize = @splat(null),
        entry: ?Entry = null,
        done: bool = false,

        const Mode = enum { raw, call };
        const Slot = enum { target, invariant, control, value, closing };
        const slot_count = reflection.fieldsOf(Slot).len;

        fn init(state: *State, mode: Mode) Iterator {
            return .{ .state = state, .generation = state.generation, .mode = mode };
        }

        /// Returns the next entry, or null at the end; the previous entry is released first.
        pub fn next(self: *Iterator) !?Entry {
            try self.validate();
            self.releaseEntry();
            if (self.done) return null;
            const state = self.state;
            callbacks.bindDispatch(state);
            const pair: [2]runtime.Value = switch (self.mode) {
                .raw => self.rooted(.target).table.next(self.rooted(.control)) catch {
                    self.done = true;
                    return errors.captureLuaError(state, state.raw_state.fail("invalid key to 'next'"));
                },
                .call => try self.callIterator(),
            };
            if (pair[0] == .nil) {
                self.release(.control);
                self.release(.value);
                try self.finish(.nil);
                return null;
            }
            try self.store(.control, pair[0]);
            try self.store(.value, pair[1]);
            var key = try convert.fromRuntimeValue(state, pair[0], Value);
            errdefer key.deinit();
            self.entry = .{ .key = key, .value = try convert.fromRuntimeValue(state, pair[1], Value) };
            return self.entry.?;
        }

        /// Ends traversal early, running a pending closing value like `break`; still call `deinit`.
        pub fn close(self: *Iterator) !void {
            try self.validate();
            self.releaseEntry();
            self.release(.control);
            self.release(.value);
            try self.finish(.nil);
        }

        /// Releases roots without calling Lua.
        pub fn deinit(self: *Iterator) void {
            if (self.generation == self.state.generation) {
                self.releaseEntry();
                for (self.roots) |root| if (root) |index| self.state.raw_state.unrootValue(index);
            }
            self.* = undefined;
        }

        fn validate(self: *const Iterator) !void {
            if (self.generation != self.state.generation) return error.InvalidHandle;
        }

        fn callIterator(self: *Iterator) ![2]runtime.Value {
            const state = self.state;
            const results = entry_mod.callFunction(&state.raw_state, self.rooted(.target), &.{ self.rooted(.invariant), self.rooted(.control) }) catch |err| {
                const failure = errors.captureLuaError(state, err);
                self.release(.control);
                self.release(.value);
                if (failure == error.LuaError) try self.finish(errors.lastErrorValue(state)) else self.done = true;
                return failure;
            };
            defer state.allocator().free(results);
            return .{
                if (results.len > 0) results[0] else .nil,
                if (results.len > 1) results[1] else .nil,
            };
        }

        fn finish(self: *Iterator, failure: runtime.Value) !void {
            self.done = true;
            const index = self.roots[@intFromEnum(Slot.closing)] orelse return;
            self.roots[@intFromEnum(Slot.closing)] = null;
            const state = self.state;
            defer state.raw_state.unrootValue(index);
            const closing = state.raw_state.rootedValue(index);
            const handler = (metatable_mod.getMetamethod(&state.raw_state, closing, "__close") catch |err| return errors.captureLuaError(state, err)) orelse return;
            const results = entry_mod.callFunction(&state.raw_state, handler, &.{ closing, failure }) catch |err| return errors.captureLuaError(state, err);
            state.allocator().free(results);
        }

        fn rooted(self: *const Iterator, slot: Slot) runtime.Value {
            const index = self.roots[@intFromEnum(slot)] orelse return .nil;
            return self.state.raw_state.rootedValue(index);
        }

        fn store(self: *Iterator, slot: Slot, value: runtime.Value) !void {
            self.release(slot);
            if (value == .nil) return;
            self.roots[@intFromEnum(slot)] = try self.state.raw_state.rootValue(value);
        }

        fn release(self: *Iterator, slot: Slot) void {
            const index = self.roots[@intFromEnum(slot)] orelse return;
            self.state.raw_state.unrootValue(index);
            self.roots[@intFromEnum(slot)] = null;
        }

        fn releaseEntry(self: *Iterator) void {
            if (self.entry) |*entry| entry.deinit();
            self.entry = null;
        }
    };

    fn rawValue(self: Table) !runtime.Value {
        const raw = try handle.rawValue(self.ref);
        if (raw != .table) return error.TypeMismatch;
        return raw;
    }
};

const max_metamethod_chain = 2000;

fn readableTableKey(key: runtime.Value) ?runtime.Value {
    return switch (key) {
        .nil => null,
        .number => |number| if (std.math.isNan(number)) null else if (runtime.floatToInteger(number)) |integer| .{ .integer = integer } else key,
        else => key,
    };
}

fn writableTableKey(state: *State, key: runtime.Value) !runtime.Value {
    return switch (key) {
        .nil => errors.captureLuaError(state, state.raw_state.fail("table index is nil")),
        .number => |number| if (std.math.isNan(number)) errors.captureLuaError(state, state.raw_state.fail("table index is NaN")) else readableTableKey(key).?,
        else => key,
    };
}

fn callFirstResult(state: *State, callable: runtime.Value, args: []const runtime.Value) !runtime.Value {
    const results = try entry_mod.callFunction(&state.raw_state, callable, args);
    defer state.allocator().free(results);
    return if (results.len == 0) .nil else results[0];
}

fn indexTable(state: *State, start: *runtime.Table, key: runtime.Value) !runtime.Value {
    var table = start;
    const lookup = readableTableKey(key);
    for (0..max_metamethod_chain) |_| {
        if (lookup) |raw_key| {
            const found = table.get(raw_key);
            if (found != .nil) return found;
        }
        const handler = try metatable_mod.getMetamethod(&state.raw_state, .{ .table = table }, "__index") orelse return .nil;
        switch (handler) {
            .table => |next| table = next,
            else => return callFirstResult(state, handler, &.{ .{ .table = table }, key }),
        }
    }
    return state.raw_state.fail("'__index' chain too long; possible loop");
}

fn assignTable(state: *State, start: *runtime.Table, key: runtime.Value, value: runtime.Value) !void {
    var table = start;
    const lookup = readableTableKey(key);
    for (0..max_metamethod_chain) |_| {
        const existing = if (lookup) |raw_key| table.get(raw_key) != .nil else false;
        const handler = if (existing) null else try metatable_mod.getMetamethod(&state.raw_state, .{ .table = table }, "__newindex");
        const metamethod = handler orelse {
            const raw_key = lookup orelse return state.raw_state.fail(if (key == .nil) "table index is nil" else "table index is NaN");
            return storeRaw(state, table, raw_key, value);
        };
        switch (metamethod) {
            .table => |next| table = next,
            else => {
                _ = try callFirstResult(state, metamethod, &.{ .{ .table = table }, key, value });
                return;
            },
        }
    }
    return state.raw_state.fail("'__newindex' chain too long; possible loop");
}

fn storeRaw(state: *State, table: *runtime.Table, key: runtime.Value, value: runtime.Value) !void {
    if (table.rollback != null and table.get(key) != .nil) {
        try rollback_runtime.tableWritable(table);
        state.raw_state.gc.noteTableCapacityDelta(table, 0);
    }
    if (!table.setExistingNonNil(key, value)) try state.raw_state.setTableRaw(table, key, value);
    state.raw_state.gc.writeTableBarrier(table, key, value);
}
