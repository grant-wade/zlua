const std = @import("std");
const rollback = @import("rollback.zig");
const compile = @import("../compile.zig");
const types = @import("types.zig");
const value_mod = @import("value.zig");

const bytecode = compile.bytecode;
const proto_mod = compile.proto;

const RuntimeErrorPayload = types.RuntimeErrorPayload;
const ProtectedCallResult = types.ProtectedCallResult;
const Value = types.Value;
const NativeFn = types.NativeFn;
const Closure = types.Closure;
const Upvalue = types.Upvalue;
const TableEntry = types.TableEntry;
const Table = types.Table;
const Userdata = types.Userdata;
const Thread = types.Thread;
const StringAllocation = types.StringAllocation;
const GcMode = types.GcMode;
const GcParam = types.GcParam;
const WeakMode = types.WeakMode;
const RuntimeAllocationStats = types.RuntimeAllocationStats;

const argValue = value_mod.argValue;
const toInteger = value_mod.toInteger;
const localActiveAt = value_mod.localActiveAt;

fn isNativeCallable(value: Value) bool {
    return switch (value) {
        .native_print,
        .native_tostring,
        .native_getmetatable,
        .native_setmetatable,
        .native_rawequal,
        .native_rawget,
        .native_rawset,
        .native_rawlen,
        .native_next,
        .native_pairs,
        .native_ipairs,
        .native_ipairs_iter,
        .native_table_create,
        .native_select,
        .native_assert,
        .native_error,
        .native_pcall,
        .native_xpcall,
        .native_collectgarbage,
        .native_debug_traceback,
        .native_coroutine_create,
        .native_coroutine_resume,
        .native_coroutine_yield,
        .native_coroutine_status,
        .native_coroutine_running,
        .native_coroutine_isyieldable,
        .native_coroutine_close,
        .native_coroutine_wrap,
        .native,
        .api_callback,
        => true,
        else => false,
    };
}

fn functionLike(value: Value) bool {
    return switch (value) {
        .closure, .coroutine_wrapper, .gmatch_iterator => true,
        else => isNativeCallable(value),
    };
}

const managed_lists = .{ "table_allocations", "userdata_allocations", "closure_allocations", "upvalue_allocations", "thread_allocations" };

pub fn reserveQueues(comptime State: type, self: *State, extra: usize) !void {
    var count = extra;
    inline for (managed_lists) |field| count += @field(self, field).items.len;
    try self.gc_work.ensureTotalCapacity(self.allocator, count);
    try self.gc_remembered.ensureTotalCapacity(self.allocator, count);
    try self.gc_weak.ensureTotalCapacity(self.allocator, self.table_allocations.items.len + extra);
    try self.gc_tables.ensureTotalCapacity(self.allocator, self.table_allocations.items.len + extra);
    try self.gc_finalizers.ensureTotalCapacity(self.allocator, self.table_allocations.items.len + extra);
}

pub fn prepareRegistration(comptime State: type, self: *State, comptime field: []const u8) !void {
    if (comptime std.mem.eql(u8, field, "string_allocations")) try self.string_allocation_index.ensureUnusedCapacity(1);
    if (comptime std.mem.eql(u8, field, "table_allocations")) try self.table_allocation_index.ensureUnusedCapacity(1);
    inline for (managed_lists) |name| if (comptime std.mem.eql(u8, field, name)) {
        try reserveQueues(State, self, 1);
        if (comptime !std.mem.eql(u8, field, "table_allocations")) try self.object_allocation_index.ensureUnusedCapacity(self.allocator, 1);
    };
}

pub fn registeredAllocation(comptime State: type, self: *State, comptime field: []const u8, item: anytype) void {
    inline for (managed_lists) |name| if (comptime std.mem.eql(u8, field, name)) {
        item.gc.generation = self.gc_generation;
        if (comptime std.mem.eql(u8, field, "table_allocations")) item.gc.storage_bytes = tableCapacityBytes(item);
        if (comptime std.mem.eql(u8, field, "thread_allocations")) {
            item.gc.storage_bytes = threadCapacityBytes(item);
            noteAllocation(State, self, item.gc.storage_bytes);
        }
        if (comptime std.mem.eql(u8, field, "closure_allocations")) noteAllocation(State, self, item.upvalues.len * @sizeOf(*Upvalue));
        if (@intFromEnum(self.gc_phase) >= @intFromEnum(types.GcPhase.sweep_threads)) {
            const tag = comptime name[0 .. name.len - "_allocations".len];
            enqueue(State, self, @unionInit(types.GcObject, tag, item));
        }
        if (comptime !std.mem.eql(u8, field, "table_allocations")) self.object_allocation_index.putAssumeCapacity(@intFromPtr(item), @field(self, field).items.len - 1);
    };
    if (comptime std.mem.eql(u8, field, "string_allocations")) {
        const allocation = &self.string_allocations.items[self.string_allocations.items.len - 1];
        allocation.gc.generation = self.gc_generation;
        if (@intFromEnum(self.gc_phase) >= @intFromEnum(types.GcPhase.sweep_threads)) {
            allocation.gc.epoch = self.gc_epoch;
            allocation.gc.color = .black;
        }
    }
}

pub fn forgetThread(comptime State: type, self: *State, thread: *Thread) void {
    _ = self.object_allocation_index.remove(@intFromPtr(thread));
    inline for (.{ "gc_work", "gc_remembered" }) |field| {
        var i: usize = 0;
        while (i < @field(self, field).items.len) {
            const object = @field(self, field).items[i];
            if (object == .thread and object.thread == thread) {
                _ = @field(self, field).swapRemove(i);
            } else i += 1;
        }
    }
}

pub fn isOld(comptime State: type, self: *State, object: anytype) bool {
    return object.gc.generation != self.gc_generation or object.gc.age == .old;
}

fn markedThisCycle(comptime State: type, self: *State, object: anytype) bool {
    return object.gc.epoch == self.gc_epoch and object.gc.color != .white;
}

fn isMarked(comptime State: type, self: *State, object: anytype) bool {
    return (self.gc_cycle == .minor and isOld(State, self, object)) or markedThisCycle(State, self, object);
}

pub fn rememberObject(comptime State: type, self: *State, object: types.GcObject) void {
    switch (object) {
        inline else => |pointer| {
            if (!isOld(State, self, pointer)) return;
            if (pointer.gc.generation != self.gc_generation) {
                pointer.gc.generation = self.gc_generation;
                pointer.gc.age = .old;
                pointer.gc.remembered = false;
            }
            if (pointer.gc.remembered) return;
            pointer.gc.remembered = true;
            self.gc_remembered.appendAssumeCapacity(object);
        },
    }
}

fn forceEnqueue(comptime State: type, self: *State, object: types.GcObject) void {
    switch (object) {
        inline else => |pointer| {
            if (markedThisCycle(State, self, pointer)) return;
            pointer.gc.epoch = self.gc_epoch;
            pointer.gc.color = .gray;
            self.gc_work.appendAssumeCapacity(object);
        },
    }
}

fn tableCandidate(comptime State: type, self: *State, table: *Table) void {
    if (@intFromEnum(self.gc_phase) >= @intFromEnum(types.GcPhase.sweep_threads)) return;
    if (table.gc.tables_epoch == self.gc_epoch) return;
    table.gc.tables_epoch = self.gc_epoch;
    self.gc_tables.appendAssumeCapacity(table);
}

fn noteYoung(comptime State: type, self: *State, value: Value) void {
    switch (value) {
        .string => |bytes| if (findStringAllocation(State, self, bytes)) |i| {
            if (!isOld(State, self, &self.string_allocations.items[i])) self.gc_found_young = true;
        },
        inline .table, .gmatch_iterator, .userdata, .closure, .thread, .coroutine_wrapper => |pointer| {
            const tracked = if (@TypeOf(pointer) == *Table) self.table_allocation_index.contains(@intFromPtr(pointer)) else self.object_allocation_index.contains(@intFromPtr(pointer));
            if (tracked and !isOld(State, self, pointer)) self.gc_found_young = true;
        },
        else => {},
    }
}

fn enqueue(comptime State: type, self: *State, object: types.GcObject) void {
    switch (object) {
        inline else => |pointer| {
            if (isMarked(State, self, pointer)) return;
            pointer.gc.epoch = self.gc_epoch;
            pointer.gc.color = .gray;
            pointer.marked = true;
            self.gc_work.appendAssumeCapacity(object);
        },
    }
}

pub fn propagate(comptime State: type, self: *State, budget: usize) usize {
    const start = self.gc_work_done;
    while (self.gc_work.items.len != 0 and self.gc_work_done - start < budget) {
        const object = self.gc_work.pop().?;
        switch (object) {
            inline else => |pointer, tag| {
                pointer.gc.color = .black;
                self.gc_found_young = false;
                switch (tag) {
                    .table => traceTable(State, self, pointer),
                    .userdata => traceUserdata(State, self, pointer),
                    .closure => traceClosure(State, self, pointer),
                    .upvalue => traceUpvalue(State, self, pointer),
                    .thread => traceThread(State, self, pointer),
                }
                pointer.gc.has_young = self.gc_found_young;
            },
        }
        self.gc_work_done +|= 1;
    }
    return self.gc_work_done - start;
}

fn drain(comptime State: type, self: *State) void {
    _ = propagate(State, self, std.math.maxInt(usize));
}

pub fn noteAllocation(comptime State: type, self: *State, bytes: usize) void {
    self.gc_known_total = self.gc_known_total +| bytes;
}

pub fn noteAllocationFreed(comptime State: type, self: *State, bytes: usize) void {
    self.gc_known_total = if (bytes > self.gc_known_total) 0 else self.gc_known_total - bytes;
}

pub fn refreshAllocationTotal(comptime State: type, self: *State) usize {
    for (self.table_allocations.items) |table| table.gc.storage_bytes = tableCapacityBytes(table);
    for (self.thread_allocations.items) |thread| thread.gc.storage_bytes = threadCapacityBytes(thread);
    const total = allocationStats(State, self.*).total();
    self.gc_known_total = total;
    return total;
}

pub fn currentAllocationTotal(comptime State: type, self: *State) usize {
    return self.gc_known_total;
}

pub fn tableCapacityBytes(table: *const Table) usize {
    return table.array.capacity * @sizeOf(Value) + table.entries.capacity * @sizeOf(TableEntry) + table.entry_index.capacity() * (@sizeOf(Value) + @sizeOf(usize) + 1);
}

pub fn tableGcBytes(table: *const Table) usize {
    return @sizeOf(Table) + tableCapacityBytes(table);
}

pub fn noteTableCapacityDelta(comptime State: type, self: *State, table: *Table, old_capacity_bytes: usize) void {
    _ = old_capacity_bytes;
    syncStorage(State, self, &table.gc, tableCapacityBytes(table));
}

fn syncStorage(comptime State: type, self: *State, meta: *types.GcMeta, bytes: usize) void {
    if (bytes >= meta.storage_bytes) noteAllocation(State, self, bytes - meta.storage_bytes) else noteAllocationFreed(State, self, meta.storage_bytes - bytes);
    meta.storage_bytes = bytes;
}

/// Managed backing capacities; allocator overhead and rollback copies are
/// measured separately by the embedding allocator, never used to pace GC.
pub fn threadCapacityBytes(thread: *const Thread) usize {
    var bytes: usize = 0;
    inline for (.{ "stack", "frames", "yield_values", "protected_continuations", "generic_for_continuations", "pairs_continuations", "tail_call_continuations", "call_one_continuations" }) |name| {
        const list = @field(thread, name);
        const T = @typeInfo(@TypeOf(list.items)).pointer.child;
        bytes += list.capacity * @sizeOf(T);
    }
    for (thread.frames.items) |frame| {
        if (frame.owns_varargs) bytes += frame.varargs.len * @sizeOf(Value);
        if (frame.pending_returns) |values| bytes += values.len * @sizeOf(Value);
    }
    return bytes;
}

pub fn syncThreadStorage(comptime State: type, self: *State, thread: *Thread) void {
    syncStorage(State, self, &thread.gc, threadCapacityBytes(thread));
}

pub fn userdataBytes(userdata: *const Userdata) usize {
    return @sizeOf(Userdata) + if (userdata.payload) |payload| @sizeOf(types.UserdataPayload) + payload.managed_bytes else @as(usize, 0);
}

pub fn closureBytes(closure: *const Closure) usize {
    return @sizeOf(Closure) + closure.upvalues.len * @sizeOf(*Upvalue) + if (closure.constants) |c| c.len * @sizeOf(?Value) else @as(usize, 0);
}

pub fn collectGarbageValue(comptime State: type, self: *State, thread: *Thread, op: bytecode.Call) !void {
    const option = argValue(self, thread, op, 0);
    if (self.is_collecting) {
        // Lua rejects collector controls from finalizers, including mode and
        // running-state changes. Argument validation still happens first.
        if (option == .string and std.mem.eql(u8, option.string, "param")) {
            _ = try collectGarbageParam(State, self, argValue(self, thread, op, 1));
            if (op.arg_count >= 3 and argValue(self, thread, op, 2) != .nil) {
                _ = toInteger(argValue(self, thread, op, 2)) orelse return self.fail("number expected");
            }
            return self.returnValues(thread, op.base, op.return_count, &.{.{ .integer = -1 }});
        }
        if (option == .string and std.mem.eql(u8, option.string, "step") and op.arg_count >= 2 and argValue(self, thread, op, 1) != .nil) {
            _ = toInteger(argValue(self, thread, op, 1)) orelse return self.fail("number expected");
        }
        if (option == .nil) return self.returnValues(thread, op.base, op.return_count, &.{.nil});
        if (option == .string) inline for (.{ "collect", "step", "count", "isrunning", "stop", "restart", "incremental", "generational" }) |name| {
            if (std.mem.eql(u8, option.string, name)) return self.returnValues(thread, op.base, op.return_count, &.{.nil});
        };
        return self.failArgumentMessage("collectgarbage", 1, "invalid option");
    }
    if (option == .nil or (option == .string and std.mem.eql(u8, option.string, "collect"))) {
        if (self.conservative_gc_depth != 0) {
            try collectGarbageConservatively(State, self, thread);
        } else {
            try collectGarbageWithFinalizers(State, self, thread);
        }
        try self.returnValues(thread, op.base, op.return_count, &.{.{ .integer = 0 }});
        return;
    }
    if (option == .string and std.mem.eql(u8, option.string, "step")) {
        const budget = if (op.arg_count >= 2 and argValue(self, thread, op, 1) != .nil) toInteger(argValue(self, thread, op, 1)) orelse return self.fail("number expected") else 0;
        const complete = try collectGarbageStep(State, self, thread, budget);
        try self.returnValues(thread, op.base, op.return_count, &.{.{ .boolean = complete }});
        return;
    }
    if (option == .string and std.mem.eql(u8, option.string, "count")) {
        try self.returnValues(thread, op.base, op.return_count, &.{.{ .number = @as(f64, @floatFromInt(refreshAllocationTotal(State, self))) / 1024.0 }});
        return;
    }
    if (option == .string and std.mem.eql(u8, option.string, "isrunning")) {
        try self.returnValues(thread, op.base, op.return_count, &.{.{ .boolean = self.gc_running }});
        return;
    }
    if (option == .string and std.mem.eql(u8, option.string, "stop")) {
        self.gc_running = false;
        try self.returnValues(thread, op.base, op.return_count, &.{.{ .integer = 0 }});
        return;
    }
    if (option == .string and std.mem.eql(u8, option.string, "restart")) {
        self.gc_running = true;
        try self.returnValues(thread, op.base, op.return_count, &.{.{ .integer = 0 }});
        return;
    }
    if (option == .string and std.mem.eql(u8, option.string, "incremental")) {
        const old = self.setGcMode(.incremental);
        try self.returnValues(thread, op.base, op.return_count, &.{.{ .string = try self.intern(old.name()) }});
        return;
    }
    if (option == .string and std.mem.eql(u8, option.string, "generational")) {
        const old = self.setGcMode(.generational);
        try self.returnValues(thread, op.base, op.return_count, &.{.{ .string = try self.intern(old.name()) }});
        return;
    }
    if (option == .string and std.mem.eql(u8, option.string, "param")) {
        const param_value = argValue(self, thread, op, 1);
        const param = try collectGarbageParam(State, self, param_value);
        const old = self.gc_params.get(param);
        if (op.arg_count >= 3 and argValue(self, thread, op, 2) != .nil) {
            const new_value = toInteger(argValue(self, thread, op, 2)) orelse return self.fail("number expected");
            // lua_gc receives a C int, and negative values query without setting.
            const narrowed: i32 = @truncate(new_value);
            if (narrowed >= 0) {
                self.gc_params.set(param, roundedLuaParam(@intCast(narrowed)));
                resetAutoGcThreshold(State, self);
            }
        }
        try self.returnValues(thread, op.base, op.return_count, &.{.{ .integer = old }});
        return;
    }
    return self.failArgumentMessage("collectgarbage", 1, "invalid option");
}

// Lua's floating-byte parameter encoding, decoded back to a percentage.
fn roundedLuaParam(value: u32) i64 {
    if (value >= 396800) return 396800;
    const scaled = (@as(u64, value) * 128 + 99) / 100;
    const shift: u6 = if (scaled < 16) 0 else @intCast(63 - @clz(scaled) - 4);
    return @intCast(((scaled >> shift) << shift) * 100 / 128);
}

pub fn collectGarbageParam(comptime State: type, self: *State, value: Value) !GcParam {
    if (value != .string) return self.fail("bad argument #2 to 'collectgarbage'");
    if (std.mem.eql(u8, value.string, "minormul")) return .minormul;
    if (std.mem.eql(u8, value.string, "majorminor")) return .majorminor;
    if (std.mem.eql(u8, value.string, "minormajor")) return .minormajor;
    if (std.mem.eql(u8, value.string, "pause")) return .pause;
    if (std.mem.eql(u8, value.string, "stepmul")) return .stepmul;
    if (std.mem.eql(u8, value.string, "stepsize")) return .stepsize;
    return self.fail("bad argument #2 to 'collectgarbage'");
}

fn luaFastStep(comptime State: type, self: *State) bool {
    const incremental = self.gc_mode == .incremental or self.gc_major_pending or
        (self.gc_phase != .pause and self.gc_cycle == .major);
    const size: usize = @intCast(@max(self.gc_params.stepsize, 0));
    const mul: usize = @intCast(@max(self.gc_params.stepmul, 0));
    return incremental and ((size / @sizeOf(usize)) *| mul / 100 == 0);
}

/// Lua 5.5 expresses explicit step budgets in bytes; zero forces a basic step.
pub fn collectGarbageStep(comptime State: type, self: *State, thread: ?*Thread, budget: i64) !bool {
    if (self.is_collecting) return false;
    // Match luaL's integer -> size_t -> signed-memory conversion on 32-bit
    // targets as well as native hosts.
    const narrowed: isize = @bitCast(@as(usize, @truncate(@as(u64, @bitCast(budget)))));
    if (narrowed > 0) {
        self.gc_next_total -|= @as(usize, @intCast(narrowed));
        if (!shouldRunAutoGc(State, self)) return false;
    }
    // Lua's work calculation can round to zero even for nonzero parameters.
    // That requests a full cycle, independently of the Zig step-count adapter.
    if (luaFastStep(State, self)) {
        try collectGarbageWithFinalizersMode(State, self, thread, self.conservative_gc_depth != 0);
        return true;
    }
    return step(State, self, thread, self.conservative_gc_depth != 0);
}

pub fn stepCount(comptime State: type, self: *State, thread: ?*Thread, steps: usize) !bool {
    for (0..@max(steps, 1)) |_| {
        if (try step(State, self, thread, self.conservative_gc_depth != 0)) return true;
    }
    return false;
}

pub fn autoStep(comptime State: type, self: *State, thread: ?*Thread) !void {
    if (self.step_after_instruction and self.gc_phase == .pause) self.gc_major_pending = true;
    if (self.collect_after_instruction or luaFastStep(State, self)) return collectGarbageConservatively(State, self, thread);
    _ = try step(State, self, thread, true);
}

fn basicWork(comptime State: type, self: *State) usize {
    const size: usize = @intCast(@max(self.gc_params.stepsize, 1));
    const mul: usize = @intCast(@max(self.gc_params.stepmul, 1));
    return @max(1, (size *| mul / 100) / @sizeOf(usize));
}

fn beginCycle(comptime State: type, self: *State) void {
    resetMarks(State, self);
    self.gc_cycle = if (self.gc_mode == .generational and !self.gc_major_pending) .minor else .major;
    self.gc_cycle_start_total = self.gc_known_total;
    self.gc_phase = .propagate;
    if (self.gc_cycle == .minor) for (self.table_allocations.items[self.gc_old.table_allocations..]) |table| tableCandidate(State, self, table);
    if (self.gc_cycle == .minor) for (self.gc_remembered.items) |object| {
        forceEnqueue(State, self, object);
        if (object == .table) tableCandidate(State, self, object.table);
    };
    markRoots(State, self);
}

fn revisitMutable(comptime State: type, self: *State) void {
    // Thread stacks and open upvalues are mutable roots. Their ordinary VM
    // stores need no per-register barrier; revisit them at the atomic boundary.
    const thread_start = if (self.gc_cycle == .minor) self.gc_old.thread_allocations else 0;
    for (self.thread_allocations.items[thread_start..]) |thread| {
        if (isMarked(State, self, thread)) traceThread(State, self, thread);
    }
    const upvalue_start = if (self.gc_cycle == .minor) self.gc_old.upvalue_allocations else 0;
    for (self.upvalue_allocations.items[upvalue_start..]) |upvalue| {
        if (upvalue.is_open and isMarked(State, self, upvalue)) traceUpvalue(State, self, upvalue);
    }
    if (self.gc_cycle == .minor) for (self.gc_remembered.items) |object| switch (object) {
        .thread => |t| traceThread(State, self, t),
        .upvalue => |u| if (u.is_open) traceUpvalue(State, self, u),
        else => {},
    };
    if (self.current_thread) |t| traceThread(State, self, t);
    markRoots(State, self);
    drain(State, self);
}

fn atomic(comptime State: type, self: *State) !void {
    if (self.gc_cycle == .major) for (self.table_allocations.items) |table| tableCandidate(State, self, table);
    revisitMutable(State, self);
    convergeEphemerons(State, self);
    // Complete all fallible detachment before removing weak entries or changing
    // finalization state. Failure leaves this phase safe to retry.
    if (self.rollback) |journal| {
        try journal.prepareCollection(self);
        try prepareRollbackTableWrites(State, self);
        for (self.userdata_allocations.items[if (self.gc_cycle == .minor) self.gc_old.userdata_allocations else 0..]) |userdata| {
            if (!isMarked(State, self, userdata) and !userdata.finalized and userdata.finalizer != null) try rollback.userdataWritable(userdata);
        }
    }
    clearWeakValues(State, self);
    prepareTableFinalizers(State, self);
    separateUserdataFinalizers(State, self);
    drain(State, self);
    convergeEphemerons(State, self);
    clearWeakTables(State, self);
    clearDeadHashKeys(State, self);
}

/// A basic step bounds propagation by references and sweeping by objects.
/// Atomic weak processing, large objects, and one finalizer can exceed the target.
pub fn step(comptime State: type, self: *State, thread: ?*Thread, conservative: bool) !bool {
    if (self.is_collecting) return false;
    self.is_collecting = true;
    const previous_mark_all = self.mark_all_stack_registers;
    self.mark_all_stack_registers = conservative;
    defer {
        self.mark_all_stack_registers = previous_mark_all;
        self.is_collecting = false;
    }
    const budget = basicWork(State, self);
    switch (self.gc_phase) {
        .pause => {
            beginCycle(State, self);
            if (self.gc_cycle == .minor) {
                drain(State, self);
                self.gc_phase = .atomic;
                try atomic(State, self);
                self.gc_phase = .sweep_threads;
                inline for (.{ "thread_allocations", "closure_allocations", "upvalue_allocations", "string_allocations", "userdata_allocations", "table_allocations" }) |field| {
                    self.gc_sweep_cursor = @field(self.gc_old, field);
                    _ = sweepList(State, self, field, std.math.maxInt(usize));
                }
                promoteYoung(State, self);
                self.gc_minor_count += 1;
                self.gc_major_pending = self.gc_known_total > self.gc_major_base +| @max(256, self.gc_major_base *| @as(usize, @intCast(@max(self.gc_params.minormajor, 0))) / 100);
                self.gc_phase = .finalize;
                _ = try runUserdataFinalizerBatch(State, self, 1);
                _ = try runFinalizerBatch(State, self, thread, 1);
                drain(State, self);
                self.gc_phase = .pause;
                resetAutoGcThreshold(State, self);
                return false;
            }
        },
        .propagate => {
            _ = propagate(State, self, budget);
            if (self.gc_work.items.len == 0) self.gc_phase = .atomic;
        },
        .atomic => {
            try atomic(State, self);
            if (self.gc_cycle == .major) {
                self.gc_remembered.clearRetainingCapacity();
                self.gc_old = .{};
            }
            self.gc_phase = .sweep_threads;
            self.gc_sweep_cursor = if (self.gc_cycle == .minor) self.gc_old.thread_allocations else 0;
        },
        inline .sweep_threads, .sweep_closures, .sweep_upvalues, .sweep_strings, .sweep_userdata, .sweep_tables => |phase| {
            _ = propagate(State, self, budget); // References installed since the preceding step.
            if (self.gc_work.items.len != 0) return false;
            const field = comptime switch (phase) {
                .sweep_threads => "thread_allocations",
                .sweep_closures => "closure_allocations",
                .sweep_upvalues => "upvalue_allocations",
                .sweep_strings => "string_allocations",
                .sweep_userdata => "userdata_allocations",
                .sweep_tables => "table_allocations",
                else => unreachable,
            };
            if (sweepList(State, self, field, budget)) {
                self.gc_phase = @enumFromInt(@intFromEnum(phase) + 1);
                self.gc_sweep_cursor = if (self.gc_cycle == .minor) switch (self.gc_phase) {
                    .sweep_closures => self.gc_old.closure_allocations,
                    .sweep_upvalues => self.gc_old.upvalue_allocations,
                    .sweep_strings => self.gc_old.string_allocations,
                    .sweep_userdata => self.gc_old.userdata_allocations,
                    .sweep_tables => self.gc_old.table_allocations,
                    else => 0,
                } else 0;
            }
        },
        .finalize => {
            const userdata_done = try runUserdataFinalizerBatch(State, self, 1);
            if (try runFinalizerBatch(State, self, thread, 1) and userdata_done) {
                drain(State, self);
                const major = self.gc_cycle == .major;
                if (major) {
                    const reclaimed = self.gc_cycle_start_total -| self.gc_known_total;
                    const return_to_minor = reclaimed >= self.gc_cycle_start_total *| @as(usize, @intCast(@max(self.gc_params.majorminor, 0))) / 100;
                    normalizeBaseline(State, self);
                    self.gc_major_pending = self.gc_mode == .generational and !return_to_minor;
                } else {
                    promoteYoung(State, self);
                    self.gc_phase = .pause;
                }
                resetAutoGcThreshold(State, self);
                return major;
            }
        },
    }
    self.gc_next_total = self.gc_known_total +| @as(usize, @intCast(@max(self.gc_params.stepsize, 1)));
    return false;
}

pub fn collectGarbage(comptime State: type, self: *State) !void {
    try collectGarbageWithFinalizers(State, self, self.current_thread);
}

pub fn gcParam(comptime State: type, self: State, param: GcParam) i64 {
    return self.gc_params.get(param);
}

pub fn setGcParam(comptime State: type, self: *State, param: GcParam, value: i64) void {
    self.gc_params.set(param, value);
}

pub fn collectGarbageConservatively(comptime State: type, self: *State, thread: ?*Thread) !void {
    try collectGarbageWithFinalizersMode(State, self, thread, true);
}

pub fn collectGarbageWithFinalizers(comptime State: type, self: *State, thread: ?*Thread) !void {
    try collectGarbageWithFinalizersMode(State, self, thread, false);
}

pub fn collectGarbageWithFinalizersMode(comptime State: type, self: *State, thread: ?*Thread, mark_all_stack_registers: bool) !void {
    if (self.is_collecting) return;
    // A full collection starts from current roots, including objects already
    // separated for finalization. Abandon scratch state without running callbacks
    // from an earlier partial cycle before the new cycle's separation phase.
    normalizeBaseline(State, self);
    self.gc_major_pending = true;
    while (!try step(State, self, thread, mark_all_stack_registers)) {}
}

pub fn shouldRunAutoGc(comptime State: type, self: *State) bool {
    if (self.current_thread) |thread| syncThreadStorage(State, self, thread);
    return !self.is_collecting and currentAllocationTotal(State, self) >= self.gc_next_total;
}

pub fn resetAutoGcThreshold(comptime State: type, self: *State) void {
    const total = currentAllocationTotal(State, self);
    self.gc_next_total = if (self.gc_mode == .generational and !self.gc_major_pending)
        total +| @max(256, total *| @as(usize, @intCast(@max(self.gc_params.minormul, 0))) / 100)
    else
        @max(total +| 256, total *| @as(usize, @intCast(@max(self.gc_params.pause, 100))) / 100);
}

pub fn normalizeBaseline(comptime State: type, self: *State) void {
    resetMarks(State, self);
    self.gc_generation += 1;
    self.gc_remembered.clearRetainingCapacity();
    self.gc_major_pending = false;
    self.gc_phase = .pause;
    self.gc_sweep_cursor = 0;
    inline for (@typeInfo(types.GcGenerations).@"struct".fields) |f| @field(self.gc_old, f.name) = @field(self, f.name).items.len;
    self.gc_major_base = self.gc_known_total;
    resetAutoGcThreshold(State, self);
}

pub fn resetMarks(comptime State: type, self: *State) void {
    self.gc_epoch += 1;
    self.gc_work.clearRetainingCapacity();
    self.gc_weak.clearRetainingCapacity();
    self.gc_tables.clearRetainingCapacity();
    self.gc_finalizers.clearRetainingCapacity();
    self.gc_work_done = 0;
}

pub fn markRoots(comptime State: type, self: *State) void {
    var pending_userdata = self.userdata_pending_finalizer_head;
    while (pending_userdata) |userdata| : (pending_userdata = userdata.finalizer_next) markUserdata(State, self, userdata);
    var pending = self.table_pending_finalizer_head;
    while (pending) |table| : (pending = table.finalizer_next) markTable(State, self, table);
    var scope = self.userdata_scope;
    while (scope) |active| : (scope = active.previous) markUserdata(State, self, active.userdata);
    if (self.global_table) |table| if (isTrackedTable(State, self, table)) markTable(State, self, table);
    for (self.api_roots.items) |root| markValue(State, self, root);
    // Native callbacks have no Lua wrapper whose varargs would keep arguments
    // alive. Reentrant calls may collect while an outer callback is suspended.
    var callback = self.active_api_callback;
    while (callback) |context| : (callback = context.parent) {
        forceEnqueue(State, self, .{ .thread = context.thread });
        markString(State, self, context.function_name);
        markStackRange(State, self, context.thread, context.argument_base, context.argCount());
        for (context.returns.items()) |value| markValue(State, self, value);
        if (context.error_value) |value| markValue(State, self, value);
    }
    markRuntimeErrorPayload(State, self, self.last_error);
    if (self.current_thread) |thread| forceEnqueue(State, self, .{ .thread = thread });
    if (self.file_metatable) |metatable| if (isTrackedTable(State, self, metatable)) markTable(State, self, metatable);
    if (self.string_metatable) |metatable| if (isTrackedTable(State, self, metatable)) markTable(State, self, metatable);
    if (self.number_metatable) |metatable| if (isTrackedTable(State, self, metatable)) markTable(State, self, metatable);
    if (self.boolean_metatable) |metatable| if (isTrackedTable(State, self, metatable)) markTable(State, self, metatable);
    if (self.nil_metatable) |metatable| if (isTrackedTable(State, self, metatable)) markTable(State, self, metatable);
    if (self.zerde_null) |table| if (isTrackedTable(State, self, table)) markTable(State, self, table);
    if (self.zerde_array_metatable) |table| if (isTrackedTable(State, self, table)) markTable(State, self, table);
    if (self.zerde_object_metatable) |table| if (isTrackedTable(State, self, table)) markTable(State, self, table);
}

pub fn markValue(comptime State: type, self: *State, value: Value) void {
    if (self.gc_phase == .pause and !self.is_collecting) return;
    self.gc_work_done +|= 1;
    noteYoung(State, self, value);
    switch (value) {
        .string => |string| markString(State, self, string),
        .table => |table| if (isTrackedTable(State, self, table)) markTable(State, self, table),
        .userdata => |userdata| if (isTrackedUserdata(State, self, userdata)) markUserdata(State, self, userdata),
        .closure => |closure| if (isTrackedClosure(State, self, closure)) markClosure(State, self, closure),
        .thread, .coroutine_wrapper => |thread| if (isTrackedThread(State, self, thread) or thread == self.current_thread) markThread(State, self, thread),
        .gmatch_iterator => |table| if (isTrackedTable(State, self, table)) markTable(State, self, table),
        else => {},
    }
}

pub fn markRuntimeErrorPayload(comptime State: type, self: *State, payload: ?RuntimeErrorPayload) void {
    const active = payload orelse return;
    switch (active) {
        .diagnostic => |message| markString(State, self, message),
        .argument => |argument| {
            markString(State, self, argument.function_name);
            switch (argument.detail) {
                .message => |message| markString(State, self, message),
                .expected => |expected| {
                    markString(State, self, expected.expected);
                    markString(State, self, expected.actual);
                },
            }
        },
        .lua_value => |value| markValue(State, self, value),
    }
}

pub fn markString(comptime State: type, self: *State, bytes: []const u8) void {
    if (findStringAllocation(State, self, bytes)) |index| {
        if (!isOld(State, self, &self.string_allocations.items[index])) self.gc_found_young = true;
        self.string_allocations.items[index].gc.epoch = self.gc_epoch;
        self.string_allocations.items[index].gc.color = .black;
    }
}

pub fn markTable(comptime State: type, self: *State, table: *Table) void {
    if (isTrackedTable(State, self, table) and !isOld(State, self, table)) self.gc_found_young = true;
    enqueue(State, self, .{ .table = table });
}

fn traceTable(comptime State: type, self: *State, table: *Table) void {
    tableCandidate(State, self, table);
    for (table.array.items) |value| noteYoung(State, self, value);
    for (table.entries.items) |entry| {
        if (entry.value == .nil) continue;
        noteYoung(State, self, entry.key);
        noteYoung(State, self, entry.value);
    }
    const mode = weakMode(State, self, table);
    if (@intFromEnum(self.gc_phase) < @intFromEnum(types.GcPhase.sweep_threads) and (mode.keys or mode.values) and table.gc.weak_epoch != self.gc_epoch) {
        table.gc.weak_epoch = self.gc_epoch;
        self.gc_weak.appendAssumeCapacity(table);
    }
    if (table.metatable) |metatable| markTable(State, self, metatable);
    const weak = weakMode(State, self, table);
    if (weak.keys and weak.values) {
        markWeakTableStrings(State, self, table, true, true);
        return;
    }
    if (weak.values) {
        for (table.entries.items) |entry| if (entry.value != .nil) markValue(State, self, entry.key);
        markWeakTableStrings(State, self, table, false, true);
        return;
    }
    if (weak.keys) {
        for (table.array.items) |value| markValue(State, self, value);
        _ = markEphemeronValues(State, self, table);
        return;
    }
    for (table.array.items) |value| markValue(State, self, value);
    for (table.entries.items) |entry| {
        if (entry.value == .nil) continue;
        markValue(State, self, entry.key);
        markValue(State, self, entry.value);
    }
}

pub fn markUserdata(comptime State: type, self: *State, userdata: *Userdata) void {
    if (isTrackedUserdata(State, self, userdata) and !isOld(State, self, userdata)) self.gc_found_young = true;
    enqueue(State, self, .{ .userdata = userdata });
}

fn traceUserdata(comptime State: type, self: *State, userdata: *Userdata) void {
    if (userdata.metatable) |metatable| markTable(State, self, metatable);
}

pub fn markWeakTableStrings(comptime State: type, self: *State, table: *Table, keys: bool, values: bool) void {
    if (values) {
        for (table.array.items) |value| markWeakString(State, self, value);
    }
    for (table.entries.items) |entry| {
        if (entry.value == .nil) continue;
        if (keys) markWeakString(State, self, entry.key);
        if (values) markWeakString(State, self, entry.value);
    }
}

pub fn markWeakString(comptime State: type, self: *State, value: Value) void {
    if (value == .string) markString(State, self, value.string);
}

pub fn markClosure(comptime State: type, self: *State, closure: *Closure) void {
    if (isTrackedClosure(State, self, closure) and !isOld(State, self, closure)) self.gc_found_young = true;
    // Native adapters can own a closure on the host stack. Its children are
    // managed, but its address must never survive in a persistent worklist.
    if (!isTrackedClosure(State, self, closure)) {
        if (markedThisCycle(State, self, closure)) return;
        closure.gc.epoch = self.gc_epoch;
        closure.gc.color = .black;
        traceClosure(State, self, closure);
        return;
    }
    enqueue(State, self, .{ .closure = closure });
}

fn traceClosure(comptime State: type, self: *State, closure: *Closure) void {
    if (closure.constants) |constants| for (constants) |constant| {
        if (constant) |value| markValue(State, self, value);
    };
    for (closure.upvalues) |upvalue| {
        if (!isOld(State, self, upvalue)) self.gc_found_young = true;
        markUpvalue(State, self, upvalue);
    }
}

pub fn markUpvalue(comptime State: type, self: *State, upvalue: *Upvalue) void {
    if (isTrackedUpvalue(State, self, upvalue) and !isOld(State, self, upvalue)) self.gc_found_young = true;
    if (!isTrackedUpvalue(State, self, upvalue)) return;
    enqueue(State, self, .{ .upvalue = upvalue });
}

fn traceUpvalue(comptime State: type, self: *State, upvalue: *Upvalue) void {
    if (upvalue.is_open) {
        if (upvalue.stack_index < upvalue.owner.stack.items.len) markValue(State, self, upvalue.owner.stack.items[upvalue.stack_index]);
    } else {
        markValue(State, self, upvalue.closed);
    }
}

pub fn markThread(comptime State: type, self: *State, thread: *Thread) void {
    if (isTrackedThread(State, self, thread) and !isOld(State, self, thread)) self.gc_found_young = true;
    enqueue(State, self, .{ .thread = thread });
}

fn traceThread(comptime State: type, self: *State, thread: *Thread) void {
    syncThreadStorage(State, self, thread);
    markValue(State, self, thread.entry);
    if (thread.resume_parent) |parent| markThread(State, self, parent);
    markThreadStack(State, self, thread);
    markValue(State, self, thread.hook);
    markValue(State, self, thread.hook_level2_func);
    for (thread.hook_transfer_values) |value| markValue(State, self, value);
    for (thread.yield_values.items) |value| markValue(State, self, value);
    if (thread.close_error_value) |value| markValue(State, self, value);
    if (thread.pending_unwind_error) |value| markValue(State, self, value);
    inline for (.{ "error_traceback", "hook_return_name", "next_call_name", "next_call_namewhat", "traceback_native_name" }) |field| {
        if (@field(thread, field)) |name| markString(State, self, name);
    }
    for (thread.protected_continuations.items) |continuation| {
        markRuntimeErrorPayload(State, self, continuation.context.last_error);
        markValue(State, self, continuation.handler);
    }
    for (thread.frames.items) |frame| {
        markClosure(State, self, frame.closure);
        markValue(State, self, frame.vararg_table_local);
        if (frame.debug_name_override) |name| markString(State, self, name);
        if (frame.debug_namewhat_override) |name| markString(State, self, name);
        for (frame.varargs) |value| markValue(State, self, value);
        if (frame.pending_returns) |returns| for (returns) |value| markValue(State, self, value);
    }
    var current = thread.open_upvalues;
    while (current) |upvalue| : (current = upvalue.next) markUpvalue(State, self, upvalue);
}

pub fn markThreadStack(comptime State: type, self: *State, thread: *Thread) void {
    if (self.mark_all_stack_registers) {
        markStackRange(State, self, thread, 0, thread.stack.items.len);
        return;
    }
    for (thread.frames.items) |frame| {
        for (frame.proto.locals.items) |local| {
            if (!localActiveAt(local, frame.pc)) continue;
            markStackRange(State, self, thread, frame.base + local.register, 1);
        }
    }
    markStackRange(State, self, thread, thread.last_result_base, thread.last_result_count);
    markStackRange(State, self, thread, thread.last_transfer_base, thread.last_transfer_count);
    markStackRange(State, self, thread, thread.yield_result_base, thread.yield_result_count);
}

pub fn markStackRange(comptime State: type, self: *State, thread: *Thread, base: usize, count: usize) void {
    if (base >= thread.stack.items.len) return;
    const end = @min(thread.stack.items.len, base + count);
    for (thread.stack.items[base..end]) |value| markValue(State, self, value);
}

pub fn weakMode(comptime State: type, self: *State, table: *Table) WeakMode {
    _ = self;
    const metatable = table.metatable orelse return .{};
    const mode = metatable.get(.{ .string = "__mode" });
    if (mode != .string) return .{};
    return .{
        .keys = std.mem.indexOfScalar(u8, mode.string, 'k') != null,
        .values = std.mem.indexOfScalar(u8, mode.string, 'v') != null,
    };
}

pub fn hasWeakTables(comptime State: type, self: *State) bool {
    return self.gc_weak.items.len != 0;
}

pub fn markEphemeronValues(comptime State: type, self: *State, table: *Table) bool {
    var changed = false;
    for (table.entries.items) |entry| {
        if (entry.value == .nil) continue;
        if (valueIsWeaklyCleared(State, self, entry.key)) continue;
        markValue(State, self, entry.key);
        if (markValueChanged(State, self, entry.value)) changed = true;
    }
    return changed;
}

pub fn convergeEphemerons(comptime State: type, self: *State) void {
    var changed = true;
    while (changed) {
        drain(State, self);
        changed = false;
        for (self.gc_weak.items) |table| {
            if (!isMarked(State, self, table)) continue;
            const weak = weakMode(State, self, table);
            if (!weak.keys or weak.values) continue;
            if (markEphemeronValues(State, self, table)) changed = true;
        }
    }
}

pub fn markValueChanged(comptime State: type, self: *State, value: Value) bool {
    const was_marked = valueIsMarked(State, self, value);
    markValue(State, self, value);
    return !was_marked and valueIsMarked(State, self, value);
}

pub fn valueIsMarked(comptime State: type, self: *State, value: Value) bool {
    return switch (value) {
        .string => |string| if (findStringAllocation(State, self, string)) |index| isMarked(State, self, &self.string_allocations.items[index]) else true,
        .table, .gmatch_iterator => |table| !isTrackedTable(State, self, table) or isMarked(State, self, table),
        .userdata => |userdata| !isTrackedUserdata(State, self, userdata) or isMarked(State, self, userdata),
        .closure => |closure| !isTrackedClosure(State, self, closure) or isMarked(State, self, closure),
        .thread, .coroutine_wrapper => |thread| !isTrackedThread(State, self, thread) or isMarked(State, self, thread),
        else => true,
    };
}

pub fn valueIsWeaklyCleared(comptime State: type, self: *State, value: Value) bool {
    return switch (value) {
        .table, .gmatch_iterator => |table| isTrackedTable(State, self, table) and !isMarked(State, self, table),
        .userdata => |userdata| isTrackedUserdata(State, self, userdata) and !isMarked(State, self, userdata),
        .closure => |closure| isTrackedClosure(State, self, closure) and !isMarked(State, self, closure),
        .thread, .coroutine_wrapper => |thread| isTrackedThread(State, self, thread) and !isMarked(State, self, thread),
        else => false,
    };
}

pub fn valueIsCollectableUnmarked(comptime State: type, self: *State, value: Value) bool {
    return switch (value) {
        .string => |string| if (findStringAllocation(State, self, string)) |index| !isMarked(State, self, &self.string_allocations.items[index]) else false,
        .table, .gmatch_iterator => |table| isTrackedTable(State, self, table) and !isMarked(State, self, table),
        .userdata => |userdata| isTrackedUserdata(State, self, userdata) and !isMarked(State, self, userdata),
        .closure => |closure| isTrackedClosure(State, self, closure) and !isMarked(State, self, closure),
        .thread, .coroutine_wrapper => |thread| isTrackedThread(State, self, thread) and !isMarked(State, self, thread),
        else => false,
    };
}

fn prepareRollbackTableWrites(comptime State: type, self: *State) !void {
    for (self.gc_tables.items) |table| {
        if (table.rollback == null) continue;
        const weak = weakMode(State, self, table);
        var changed = false;
        if (weak.values) for (table.array.items) |value| {
            if (valueIsWeaklyCleared(State, self, value)) {
                changed = true;
                break;
            }
        };
        if (!changed) for (table.entries.items) |entry| {
            if ((weak.values and valueIsWeaklyCleared(State, self, entry.value)) or
                (weak.keys and valueIsWeaklyCleared(State, self, entry.key)) or
                (entry.value == .nil and valueIsCollectableUnmarked(State, self, entry.key)))
            {
                changed = true;
                break;
            }
        };
        if (changed) {
            try rollback.tableWritable(table);
            noteTableCapacityDelta(State, self, table, 0);
        }
    }
}

pub fn clearWeakValues(comptime State: type, self: *State) void {
    for (self.gc_weak.items) |table| {
        if (!isMarked(State, self, table)) continue;
        if (!weakMode(State, self, table).values) continue;
        clearWeakTableValues(State, self, table);
    }
}

pub fn clearWeakTables(comptime State: type, self: *State) void {
    for (self.gc_weak.items) |table| {
        if (!isMarked(State, self, table)) continue;
        const weak = weakMode(State, self, table);
        if (weak.values) clearWeakTableValues(State, self, table);
        if (weak.keys) clearWeakTableKeys(State, self, table);
    }
}

pub fn clearDeadHashKeys(comptime State: type, self: *State) void {
    for (self.gc_tables.items) |table| {
        if (!isMarked(State, self, table)) continue;
        var read_index: usize = 0;
        var write_index: usize = 0;
        while (read_index < table.entries.items.len) : (read_index += 1) {
            const entry = table.entries.items[read_index];
            if (entry.value == .nil and valueIsCollectableUnmarked(State, self, entry.key)) {
                _ = table.entry_index.remove(entry.key);
            } else {
                if (write_index != read_index) {
                    table.entries.items[write_index] = entry;
                    if (table.entry_index.capacity() != 0) table.entry_index.getPtr(entry.key).?.* = write_index;
                }
                write_index += 1;
            }
        }
        table.entries.items.len = write_index;
    }
}

pub fn clearWeakTableValues(comptime State: type, self: *State, table: *Table) void {
    for (table.array.items) |*value| {
        if (valueIsWeaklyCleared(State, self, value.*)) value.* = .nil;
    }
    var index: usize = 0;
    while (index < table.entries.items.len) {
        if (valueIsWeaklyCleared(State, self, table.entries.items[index].value)) {
            table.removeEntryAt(index);
        } else {
            index += 1;
        }
    }
}

pub fn clearWeakTableKeys(comptime State: type, self: *State, table: *Table) void {
    var index: usize = 0;
    while (index < table.entries.items.len) {
        if (valueIsWeaklyCleared(State, self, table.entries.items[index].key)) {
            table.removeEntryAt(index);
        } else {
            index += 1;
        }
    }
}

pub fn writeTableBarrier(comptime State: type, self: *State, table: *Table, key: Value, value: Value) void {
    rememberObject(State, self, .{ .table = table });
    if (key == .string and std.mem.eql(u8, key.string, "__mode")) {
        var current = self.table_metatable_head;
        while (current) |dependent| : (current = dependent.metatable_next) {
            if (dependent.metatable != table) continue;
            rememberObject(State, self, .{ .table = dependent });
            if (self.gc_phase != .pause and dependent.gc.color != .gray) {
                dependent.gc.epoch = 0;
                forceEnqueue(State, self, .{ .table = dependent });
            }
        }
    }
    if (self.gc_phase == .pause or !isMarked(State, self, table)) return;
    const weak = weakMode(State, self, table);
    markWeakString(State, self, key);
    markWeakString(State, self, value);
    if (!weak.keys) markValue(State, self, key);
    if (!weak.values and (!weak.keys or !valueIsWeaklyCleared(State, self, key))) markValue(State, self, value);
}

pub fn writeBarrier(comptime State: type, self: *State, parent: anytype, child: Value) void {
    const T = @typeInfo(@TypeOf(parent)).pointer.child;
    const tag = comptime if (T == Table) "table" else if (T == Userdata) "userdata" else if (T == Closure) "closure" else if (T == Upvalue) "upvalue" else "thread";
    rememberObject(State, self, @unionInit(types.GcObject, tag, parent));
    if (self.gc_phase == .pause or !isMarked(State, self, parent)) return;
    markValue(State, self, child);
}

fn prepareTableFinalizers(comptime State: type, self: *State) void {
    self.gc_finalizers.clearRetainingCapacity();
    // gc_tables contains young and remembered tables in a minor collection.
    // Doubly linked registrations let us separate those objects without walking
    // the old registration list. Selection precedes resurrection tracing.
    for (self.gc_tables.items) |table| {
        if (!table.finalizer_registered or isMarked(State, self, table)) continue;
        self.gc_finalizers.appendAssumeCapacity(table);
    }
    std.mem.sort(*Table, self.gc_finalizers.items, {}, struct {
        fn newer(_: void, a: *Table, b: *Table) bool {
            return a.finalizer_order > b.finalizer_order;
        }
    }.newer);
    var tail = &self.table_pending_finalizer_head;
    var tail_owner: ?*Table = null;
    while (tail.*) |table| {
        tail = &table.finalizer_next;
        tail_owner = table;
    }
    for (self.gc_finalizers.items) |table| {
        rollback.touch(table);
        if (table.finalizer_prev) |prev| {
            rollback.touch(prev);
            prev.finalizer_next = table.finalizer_next;
        } else self.table_finalizer_head = table.finalizer_next;
        if (table.finalizer_next) |next| {
            rollback.touch(next);
            next.finalizer_prev = table.finalizer_prev;
        }
        if (tail_owner) |owner| rollback.touch(owner);
        table.finalizer_prev = null;
        tail.* = table;
        tail_owner = table;
        tail = &table.finalizer_next;
    }
    tail.* = null;
    var pending = self.table_pending_finalizer_head;
    while (pending) |table| : (pending = table.finalizer_next) markTable(State, self, table);
    self.gc_finalizers.clearRetainingCapacity();
    drain(State, self);
    convergeEphemerons(State, self);
}

pub fn runPendingFinalizers(comptime State: type, self: *State, thread: ?*Thread) !void {
    _ = try runFinalizerBatch(State, self, thread, std.math.maxInt(usize));
}

pub fn runFinalizerBatch(comptime State: type, self: *State, thread: ?*Thread, limit: usize) !bool {
    if (self.table_pending_finalizer_head == null) return true;
    const active_thread = thread orelse return self.runFinalizersFromHost(limit);
    var count: usize = 0;
    while (self.table_pending_finalizer_head) |table| {
        if (count >= limit) return false;
        // protectedCall's initial stack reservation can fail before protected
        // execution begins. Keep the registration pending until it succeeds.
        const frame = active_thread.frames.items[active_thread.frames.items.len - 1];
        try active_thread.ensureStack(self.allocator, frame.base + @as(usize, frame.proto.max_registers) + 2, self.stackValueLimit());
        count += 1;
        rollback.touch(table);
        self.table_pending_finalizer_head = table.finalizer_next;
        table.finalizer_next = null;
        table.finalizer_registered = false;
        const metatable = table.metatable orelse continue;
        const finalizer = metatable.get(.{ .string = "__gc" });
        if (finalizer == .nil) continue;
        const previous_name = active_thread.next_call_name;
        const previous_namewhat = active_thread.next_call_namewhat;
        active_thread.next_call_name = "__gc";
        active_thread.next_call_namewhat = "metamethod";
        active_thread.native_call_depth += 1;
        defer {
            active_thread.next_call_name = previous_name;
            active_thread.next_call_namewhat = previous_namewhat;
            active_thread.native_call_depth -= 1;
        }
        const result = try self.protectedCall(active_thread, finalizer, &.{.{ .table = table }});
        value_mod.freeProtectedResult(self.allocator, result);
    }
    return true;
}

fn separateUserdataFinalizers(comptime State: type, self: *State) void {
    for (self.userdata_allocations.items[if (self.gc_cycle == .minor) self.gc_old.userdata_allocations else 0..]) |userdata| {
        if (isMarked(State, self, userdata) or userdata.finalized or userdata.finalization_pending or userdata.finalizer == null) continue;
        rollback.touch(userdata);
        userdata.finalization_pending = true;
        userdata.finalizer_next = self.userdata_pending_finalizer_head;
        self.userdata_pending_finalizer_head = userdata;
    }
    var pending = self.userdata_pending_finalizer_head;
    while (pending) |userdata| : (pending = userdata.finalizer_next) markUserdata(State, self, userdata);
}

fn runUserdataFinalizerBatch(comptime State: type, self: *State, limit: usize) !bool {
    var count: usize = 0;
    while (self.userdata_pending_finalizer_head) |userdata| {
        if (count == limit) return false;
        // A snapshot can establish its baseline after separation. Detach that
        // baseline payload before consuming the registration or calling out.
        // Failure leaves this finalizer pending and safe to retry.
        try rollback.userdataWritable(userdata);
        count += 1;
        rollback.touch(userdata);
        self.userdata_pending_finalizer_head = userdata.finalizer_next;
        userdata.finalizer_next = null;
        userdata.finalization_pending = false;
        userdata.finalized = true;
        if (userdata.payload) |payload| payload.finalize() else if (userdata.finalizer) |finalizer| finalizer(userdata.ptr, userdata.finalizer_data);
    }
    return true;
}

pub fn runPendingUserdataFinalizers(comptime State: type, self: *State) !void {
    _ = try runUserdataFinalizerBatch(State, self, std.math.maxInt(usize));
}

pub fn callableValue(comptime State: type, self: *State, value: Value) bool {
    if (functionLike(value)) return true;
    return (self.getMetamethod(value, "__call") catch null) != null;
}

fn updateIndex(comptime State: type, self: *State, comptime field: []const u8, index: usize) void {
    const item = @field(self, field).items[index];
    if (comptime std.mem.eql(u8, field, "string_allocations")) {
        if (item.bytes.len != 0) self.string_allocation_index.getPtr(@intFromPtr(item.bytes.ptr)).?.* = index;
    } else if (comptime std.mem.eql(u8, field, "table_allocations")) self.table_allocation_index.getPtr(@intFromPtr(item)).?.* = index else self.object_allocation_index.getPtr(@intFromPtr(item)).?.* = index;
}

pub fn removeRegistryItem(comptime State: type, self: *State, comptime field: []const u8, index: usize) void {
    const boundary = &@field(self.gc_old, field);
    var hole = index;
    if (hole < boundary.*) {
        boundary.* -= 1;
        if (hole != boundary.*) {
            @field(self, field).items[hole] = @field(self, field).items[boundary.*];
            updateIndex(State, self, field, hole);
        }
        hole = boundary.*;
    }
    _ = @field(self, field).swapRemove(hole);
    if (hole < @field(self, field).items.len) updateIndex(State, self, field, hole);
}

fn promoteYoung(comptime State: type, self: *State) void {
    // No old-generation iteration: survivors are partitioned in place.
    inline for (@typeInfo(types.GcGenerations).@"struct".fields) |f| {
        const field = f.name;
        const strings = comptime std.mem.eql(u8, field, "string_allocations");
        var i = @field(self.gc_old, field);
        while (i < @field(self, field).items.len) : (i += 1) {
            const pointer = if (strings) &@field(self, field).items[i] else @field(self, field).items[i];
            if (pointer.gc.age == .new) {
                pointer.gc.age = .survivor;
            } else {
                pointer.gc.age = .old;
                if (!strings) {
                    const tag = comptime field[0 .. field.len - "_allocations".len];
                    rememberObject(State, self, @unionInit(types.GcObject, tag, pointer));
                    pointer.gc.has_young = true; // Revisit once after promotion.
                }
                const boundary = &@field(self.gc_old, field);
                std.mem.swap(@TypeOf(@field(self, field).items[i]), &@field(self, field).items[i], &@field(self, field).items[boundary.*]);
                updateIndex(State, self, field, i);
                updateIndex(State, self, field, boundary.*);
                boundary.* += 1;
            }
        }
    }
    var i: usize = 0;
    while (i < self.gc_remembered.items.len) {
        const object = self.gc_remembered.items[i];
        const keep = switch (object) {
            inline else => |p| p.gc.has_young,
        };
        if (keep) {
            i += 1;
        } else {
            switch (object) {
                inline else => |p| p.gc.remembered = false,
            }
            _ = self.gc_remembered.swapRemove(i);
        }
    }
}

fn sweepList(comptime State: type, self: *State, comptime field: []const u8, budget: usize) bool {
    const strings = comptime std.mem.eql(u8, field, "string_allocations");
    const tables = comptime std.mem.eql(u8, field, "table_allocations");
    var work: usize = 0;
    while (self.gc_sweep_cursor < @field(self, field).items.len and work < budget) : (work += 1) {
        const index = self.gc_sweep_cursor;
        const item = @field(self, field).items[index];
        if (isMarked(State, self, if (strings) &item else item)) {
            self.gc_sweep_cursor += 1;
            continue;
        }
        if (strings) {
            if (self.strings.get(item.bytes)) |interned| {
                if (interned.ptr == item.bytes.ptr and interned.len == item.bytes.len) _ = self.strings.remove(item.bytes);
            }
            if (item.bytes.len != 0) _ = self.string_allocation_index.remove(@intFromPtr(item.bytes.ptr));
            const retained = if (self.rollback) |journal| journal.keepString(item.bytes) else false;
            noteAllocationFreed(State, self, @sizeOf(StringAllocation) + item.bytes.len);
            if (!retained) self.allocator.free(item.bytes);
        } else {
            if (tables) _ = self.table_allocation_index.remove(@intFromPtr(item)) else _ = self.object_allocation_index.remove(@intFromPtr(item));
            if (tables) {
                noteAllocationFreed(State, self, tableGcBytes(item));
                destroyTable(State, self, item);
            } else if (comptime std.mem.eql(u8, field, "thread_allocations")) {
                noteAllocationFreed(State, self, @sizeOf(Thread) + item.gc.storage_bytes);
                self.closeUpvalues(item, 0);
                destroyThread(State, self, item);
            } else if (comptime std.mem.eql(u8, field, "closure_allocations")) {
                noteAllocationFreed(State, self, closureBytes(item));
                destroyClosure(State, self, item);
            } else if (comptime std.mem.eql(u8, field, "userdata_allocations")) {
                noteAllocationFreed(State, self, userdataBytes(item));
                destroyUserdata(State, self, item);
            } else {
                noteAllocationFreed(State, self, @sizeOf(Upvalue));
                if (!rollback.retainCollected(item)) {
                    if (self.rollback) |journal| journal.freed(@intFromPtr(item));
                    self.allocator.destroy(item);
                }
            }
        }
        removeRegistryItem(State, self, field, index);
    }
    return self.gc_sweep_cursor >= @field(self, field).items.len;
}

pub fn sweepStrings(comptime State: type, self: *State) void {
    self.gc_sweep_cursor = 0;
    _ = sweepList(State, self, "string_allocations", std.math.maxInt(usize));
}

pub fn sweepTables(comptime State: type, self: *State) void {
    self.gc_sweep_cursor = 0;
    _ = sweepList(State, self, "table_allocations", std.math.maxInt(usize));
}

pub fn sweepUserdata(comptime State: type, self: *State) void {
    self.gc_sweep_cursor = 0;
    _ = sweepList(State, self, "userdata_allocations", std.math.maxInt(usize));
}

pub fn sweepClosures(comptime State: type, self: *State) void {
    self.gc_sweep_cursor = 0;
    _ = sweepList(State, self, "closure_allocations", std.math.maxInt(usize));
}

pub fn sweepUpvalues(comptime State: type, self: *State) void {
    self.gc_sweep_cursor = 0;
    _ = sweepList(State, self, "upvalue_allocations", std.math.maxInt(usize));
}

pub fn sweepThreads(comptime State: type, self: *State) void {
    self.gc_sweep_cursor = 0;
    _ = sweepList(State, self, "thread_allocations", std.math.maxInt(usize));
}

pub fn findStringAllocation(comptime State: type, self: *State, bytes: []const u8) ?usize {
    if (bytes.len == 0) {
        for (self.string_allocations.items, 0..) |allocation, index| {
            if (allocation.bytes.ptr == bytes.ptr and allocation.bytes.len == bytes.len) return index;
        }
        return null;
    }
    return self.string_allocation_index.get(@intFromPtr(bytes.ptr));
}

pub fn isTrackedThread(comptime State: type, self: *State, thread: *Thread) bool {
    return self.object_allocation_index.contains(@intFromPtr(thread));
}

pub fn isTrackedTable(comptime State: type, self: *State, table: *Table) bool {
    return self.table_allocation_index.contains(@intFromPtr(table));
}

pub fn isTrackedUserdata(comptime State: type, self: *State, userdata: *Userdata) bool {
    return self.object_allocation_index.contains(@intFromPtr(userdata));
}

pub fn isTrackedClosure(comptime State: type, self: *State, closure: *Closure) bool {
    return self.object_allocation_index.contains(@intFromPtr(closure));
}

pub fn isTrackedUpvalue(comptime State: type, self: *State, upvalue: *Upvalue) bool {
    return self.object_allocation_index.contains(@intFromPtr(upvalue));
}

pub fn destroyTable(comptime State: type, self: *State, table: *Table) void {
    rollback.touch(table);
    if (table.metatable != null) {
        unlinkTableMetatable(State, self, table);
        self.table_metatable_count -= 1;
    }
    if (rollback.retainCollected(table)) return;
    if (self.rollback) |journal| journal.freed(@intFromPtr(table));
    table.deinit(self.allocator);
    self.allocator.destroy(table);
}

pub fn destroyUserdata(comptime State: type, self: *State, userdata: *Userdata) void {
    if (rollback.retainCollected(userdata)) return;
    if (self.rollback) |journal| journal.freed(@intFromPtr(userdata));
    if (userdata.payload) |payload| {
        payload.release(self.discarding);
        self.allocator.destroy(userdata);
        return;
    }
    if (!userdata.finalized and !self.discarding) {
        if (userdata.finalizer) |finalizer| finalizer(userdata.ptr, userdata.finalizer_data);
        userdata.finalized = true;
    }
    if (userdata.deinit_fn) |deinit_fn| deinit_fn(self.allocator, userdata.ptr);
    self.allocator.destroy(userdata);
}

pub fn destroyClosure(comptime State: type, self: *State, closure: *Closure) void {
    if (rollback.retainCollected(closure)) return;
    if (self.rollback) |journal| journal.freed(@intFromPtr(closure));
    if (closure.constants) |constants| self.allocator.free(constants);
    if (closure.upvalues.len != 0) self.allocator.free(closure.upvalues);
    self.allocator.destroy(closure);
}

pub fn destroyThread(comptime State: type, self: *State, thread: *Thread) void {
    if (rollback.retainCollected(thread)) return;
    if (self.rollback) |journal| journal.freed(@intFromPtr(thread));
    thread.deinit(self.allocator);
    self.allocator.destroy(thread);
}

pub fn allocationStats(comptime State: type, self: State) RuntimeAllocationStats {
    var bytes: usize = 0;
    for (self.string_allocations.items) |allocation| bytes += @sizeOf(StringAllocation) + allocation.bytes.len;
    for (self.table_allocations.items) |table| {
        bytes += tableGcBytes(table);
    }
    for (self.userdata_allocations.items) |userdata| bytes += userdataBytes(userdata);
    for (self.closure_allocations.items) |closure| bytes += closureBytes(closure);
    bytes += self.upvalue_allocations.items.len * @sizeOf(Upvalue);
    for (self.thread_allocations.items) |thread| bytes += @sizeOf(Thread) + threadCapacityBytes(thread);

    return .{
        .strings = self.string_allocations.items.len,
        .tables = self.table_allocations.items.len,
        .closures = self.closure_allocations.items.len,
        .upvalues = self.upvalue_allocations.items.len,
        .threads = self.thread_allocations.items.len,
        .bytes = bytes,
    };
}

pub fn noteTableMetatableChanged(comptime State: type, self: *State, table: *Table, old_has_metatable: bool) void {
    rollback.touch(table);
    if (!isTrackedTable(State, self, table)) return;
    rememberObject(State, self, .{ .table = table });
    if (self.gc_phase != .pause and table.gc.color != .gray) {
        table.gc.epoch = 0;
        forceEnqueue(State, self, .{ .table = table });
    }
    if (!table.finalizer_registered) {
        if (table.metatable) |metatable| {
            if (metatable.get(.{ .string = "__gc" }) != .nil) {
                table.finalizer_registered = true;
                self.table_finalizer_serial += 1;
                table.finalizer_order = self.table_finalizer_serial;
                table.finalizer_prev = null;
                if (self.table_finalizer_head) |head| {
                    rollback.touch(head);
                    head.finalizer_prev = table;
                }
                table.finalizer_next = self.table_finalizer_head;
                self.table_finalizer_head = table;
            }
        }
    }
    const new_has_metatable = table.metatable != null;
    if (old_has_metatable == new_has_metatable) return;
    if (new_has_metatable) {
        table.metatable_prev = null;
        table.metatable_next = self.table_metatable_head;
        if (self.table_metatable_head) |head| {
            rollback.touch(head);
            head.metatable_prev = table;
        }
        self.table_metatable_head = table;
        self.table_metatable_count += 1;
    } else {
        unlinkTableMetatable(State, self, table);
        self.table_metatable_count -= 1;
    }
}

pub fn unlinkTableMetatable(comptime State: type, self: *State, table: *Table) void {
    rollback.touch(table);
    if (table.metatable_prev) |prev| {
        rollback.touch(prev);
        prev.metatable_next = table.metatable_next;
    } else if (self.table_metatable_head == table) {
        self.table_metatable_head = table.metatable_next;
    }
    if (table.metatable_next) |next| {
        rollback.touch(next);
        next.metatable_prev = table.metatable_prev;
    }
    table.metatable_prev = null;
    table.metatable_next = null;
}
