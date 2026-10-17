const std = @import("std");
const compile = @import("../compile.zig");
const errors = @import("../errors.zig");
const reflection = @import("../reflection.zig");
const stdlib = @import("../stdlib.zig");
const call_mod = @import("call.zig");
const entry_mod = @import("entry.zig");
const host = @import("host.zig");
const io_mod = @import("io.zig");
const metatable_mod = @import("metatable.zig");
const rollback = @import("rollback.zig");
const State = @import("state.zig").State;
const types = @import("types.zig");
const upvalue_mod = @import("upvalue.zig");
const value_mod = @import("value.zig");

const bytecode = compile.bytecode;
const proto_mod = compile.proto;
const RuntimeErrorPayload = types.RuntimeErrorPayload;
const Value = types.Value;
const Closure = types.Closure;
const Upvalue = types.Upvalue;
const TableEntry = types.TableEntry;
const Table = types.Table;
const Userdata = types.Userdata;
const Thread = types.Thread;
const StringAllocation = types.StringAllocation;
const GcMode = types.GcMode;
const GcParam = types.GcParam;
const GcParams = types.GcParams;
const WeakMode = types.WeakMode;
const RuntimeAllocationStats = types.RuntimeAllocationStats;
const argValue = value_mod.argValue;
const toInteger = value_mod.toInteger;
const localActiveAt = value_mod.localActiveAt;

pub const Gc = struct {
    collecting: bool = false,
    stress_collect: bool = false,
    stress_step: bool = false,
    stress_mark: usize = 0,
    running: bool = true,
    mode: GcMode = .generational,
    params: GcParams = .{},
    next_total: usize = 0,
    known_total: usize = 0,
    epoch: u64 = 1,
    generation: u64 = 1,
    phase: types.GcPhase = .pause,
    cycle: types.GcCycle = .major,
    work: std.ArrayList(types.GcObject) = .empty,
    remembered: std.ArrayList(types.GcObject) = .empty,
    weak: std.ArrayList(*Table) = .empty,
    tables: std.ArrayList(*Table) = .empty,
    finalizers: std.ArrayList(types.FinalizerObject) = .empty,
    major_pending: bool = false,
    cycle_start_total: usize = 0,
    found_young: bool = false,
    old: types.GcGenerations = .{},
    sweep_cursor: usize = 0,
    major_base: usize = 0,
    work_done: usize = 0,
    minor_count: usize = 0,
    mark_all_stack_registers: bool = false,
    conservative_depth: usize = 0,

    fn parentState(gc: *Gc) *State {
        return @alignCast(@fieldParentPtr("gc", gc));
    }

    fn constParentState(gc: *const Gc) *const State {
        return @alignCast(@fieldParentPtr("gc", gc));
    }

    pub fn reserveQueues(gc: *Gc, extra: usize) !void {
        const state = gc.parentState();
        var count = extra;
        inline for (managed_lists) |field| count += @field(state, field).items.len;
        try state.gc.work.ensureTotalCapacity(state.allocator, count);
        try state.gc.remembered.ensureTotalCapacity(state.allocator, count);
        try state.gc.weak.ensureTotalCapacity(state.allocator, state.table_allocations.items.len + extra);
        try state.gc.tables.ensureTotalCapacity(state.allocator, state.table_allocations.items.len + extra);
        try state.gc.finalizers.ensureTotalCapacity(state.allocator, state.table_allocations.items.len + state.userdata_allocations.items.len + extra);
    }

    pub fn prepareRegistration(gc: *Gc, comptime field: []const u8) !void {
        const state = gc.parentState();
        if (comptime std.mem.eql(u8, field, "string_allocations")) try state.string_allocation_index.ensureUnusedCapacity(1);
        if (comptime std.mem.eql(u8, field, "table_allocations")) try state.table_allocation_index.ensureUnusedCapacity(1);
        inline for (managed_lists) |name| if (comptime std.mem.eql(u8, field, name)) {
            try gc.reserveQueues(1);
            if (comptime !std.mem.eql(u8, field, "table_allocations")) try state.object_allocation_index.ensureUnusedCapacity(state.allocator, 1);
        };
    }

    pub fn registeredAllocation(gc: *Gc, comptime field: []const u8, item: anytype) void {
        const state = gc.parentState();
        inline for (managed_lists) |name| if (comptime std.mem.eql(u8, field, name)) {
            item.gc.generation = state.gc.generation;
            if (comptime std.mem.eql(u8, field, "table_allocations")) item.gc.storage_bytes = tableCapacityBytes(item);
            if (comptime std.mem.eql(u8, field, "thread_allocations")) {
                item.gc.storage_bytes = threadCapacityBytes(item);
                gc.noteAllocation(item.gc.storage_bytes);
            }
            if (comptime std.mem.eql(u8, field, "closure_allocations")) gc.noteAllocation(item.upvalues.len * @sizeOf(*Upvalue));
            if (@intFromEnum(state.gc.phase) >= @intFromEnum(types.GcPhase.sweep_threads)) {
                const tag = comptime name[0 .. name.len - "_allocations".len];
                gc.enqueue(@unionInit(types.GcObject, tag, item));
            }
            if (comptime !std.mem.eql(u8, field, "table_allocations")) state.object_allocation_index.putAssumeCapacity(@intFromPtr(item), @field(state, field).items.len - 1);
        };
        if (comptime std.mem.eql(u8, field, "string_allocations")) {
            const allocation = &state.string_allocations.items[state.string_allocations.items.len - 1];
            allocation.gc.generation = state.gc.generation;
            if (@intFromEnum(state.gc.phase) >= @intFromEnum(types.GcPhase.sweep_threads)) {
                allocation.gc.epoch = state.gc.epoch;
                allocation.gc.color = .black;
            }
        }
    }

    pub fn forgetThread(gc: *Gc, thread: *Thread) void {
        const state = gc.parentState();
        _ = state.object_allocation_index.remove(@intFromPtr(thread));
        inline for (.{ "work", "remembered" }) |field| {
            var i: usize = 0;
            while (i < @field(gc, field).items.len) {
                const object = @field(gc, field).items[i];
                if (object == .thread and object.thread == thread) {
                    _ = @field(gc, field).swapRemove(i);
                } else i += 1;
            }
        }
    }

    pub fn isOld(gc: *Gc, object: anytype) bool {
        const state = gc.parentState();
        return object.gc.generation != state.gc.generation or object.gc.age == .old;
    }

    fn markedThisCycle(gc: *Gc, object: anytype) bool {
        const state = gc.parentState();
        return object.gc.epoch == state.gc.epoch and object.gc.color != .white;
    }

    fn isMarked(gc: *Gc, object: anytype) bool {
        const state = gc.parentState();
        return (state.gc.cycle == .minor and gc.isOld(object)) or gc.markedThisCycle(object);
    }

    pub fn rememberObject(gc: *Gc, object: types.GcObject) void {
        const state = gc.parentState();
        switch (object) {
            inline else => |pointer| {
                if (!gc.isOld(pointer)) return;
                if (pointer.gc.generation != state.gc.generation) {
                    pointer.gc.generation = state.gc.generation;
                    pointer.gc.age = .old;
                    pointer.gc.remembered = false;
                }
                if (pointer.gc.remembered) return;
                pointer.gc.remembered = true;
                state.gc.remembered.appendAssumeCapacity(object);
            },
        }
    }

    fn forceEnqueue(gc: *Gc, object: types.GcObject) void {
        const state = gc.parentState();
        switch (object) {
            inline else => |pointer| {
                if (gc.markedThisCycle(pointer)) return;
                pointer.gc.epoch = state.gc.epoch;
                pointer.gc.color = .gray;
                state.gc.work.appendAssumeCapacity(object);
            },
        }
    }

    fn tableCandidate(gc: *Gc, table: *Table) void {
        const state = gc.parentState();
        if (@intFromEnum(state.gc.phase) >= @intFromEnum(types.GcPhase.sweep_threads)) return;
        if (table.gc.tables_epoch == state.gc.epoch) return;
        table.gc.tables_epoch = state.gc.epoch;
        state.gc.tables.appendAssumeCapacity(table);
    }

    fn noteYoung(gc: *Gc, value: Value) void {
        const state = gc.parentState();
        switch (value) {
            .string => |bytes| if (gc.findStringAllocation(bytes)) |i| {
                if (!gc.isOld(&state.string_allocations.items[i])) state.gc.found_young = true;
            },
            inline .table, .gmatch_iterator, .userdata, .closure, .thread, .coroutine_wrapper => |pointer| {
                const tracked = if (@TypeOf(pointer) == *Table) state.table_allocation_index.contains(@intFromPtr(pointer)) else state.object_allocation_index.contains(@intFromPtr(pointer));
                if (tracked and !gc.isOld(pointer)) state.gc.found_young = true;
            },
            else => {},
        }
    }

    fn enqueue(gc: *Gc, object: types.GcObject) void {
        const state = gc.parentState();
        switch (object) {
            inline else => |pointer| {
                if (gc.isMarked(pointer)) return;
                pointer.gc.epoch = state.gc.epoch;
                pointer.gc.color = .gray;
                pointer.marked = true;
                state.gc.work.appendAssumeCapacity(object);
            },
        }
    }

    pub fn propagate(gc: *Gc, budget: usize) usize {
        const state = gc.parentState();
        const start = state.gc.work_done;
        while (state.gc.work.items.len != 0 and state.gc.work_done - start < budget) {
            const object = state.gc.work.pop().?;
            switch (object) {
                inline else => |pointer, tag| {
                    pointer.gc.color = .black;
                    state.gc.found_young = false;
                    switch (tag) {
                        .table => gc.traceTable(pointer),
                        .userdata => gc.traceUserdata(pointer),
                        .closure => gc.traceClosure(pointer),
                        .upvalue => gc.traceUpvalue(pointer),
                        .thread => gc.traceThread(pointer),
                    }
                    pointer.gc.has_young = state.gc.found_young;
                },
            }
            state.gc.work_done +|= 1;
        }
        return state.gc.work_done - start;
    }

    fn drain(gc: *Gc) void {
        _ = gc.propagate(std.math.maxInt(usize));
    }

    pub fn noteAllocation(gc: *Gc, bytes: usize) void {
        const state = gc.parentState();
        state.gc.known_total = state.gc.known_total +| bytes;
    }

    pub fn noteAllocationFreed(gc: *Gc, bytes: usize) void {
        const state = gc.parentState();
        state.gc.known_total = if (bytes > state.gc.known_total) 0 else state.gc.known_total - bytes;
    }

    pub fn refreshAllocationTotal(gc: *Gc) usize {
        const state = gc.parentState();
        for (state.table_allocations.items) |table| table.gc.storage_bytes = tableCapacityBytes(table);
        for (state.thread_allocations.items) |thread| thread.gc.storage_bytes = threadCapacityBytes(thread);
        const total = state.gc.allocationStats().total();
        state.gc.known_total = total;
        return total;
    }

    pub fn currentAllocationTotal(gc: *Gc) usize {
        const state = gc.parentState();
        return state.gc.known_total;
    }

    pub fn noteTableCapacityDelta(gc: *Gc, table: *Table, old_capacity_bytes: usize) void {
        _ = old_capacity_bytes;
        gc.syncStorage(&table.gc, tableCapacityBytes(table));
    }

    fn syncStorage(gc: *Gc, meta: *types.GcMeta, bytes: usize) void {
        if (bytes >= meta.storage_bytes) gc.noteAllocation(bytes - meta.storage_bytes) else gc.noteAllocationFreed(meta.storage_bytes - bytes);
        meta.storage_bytes = bytes;
    }

    pub fn syncThreadStorage(gc: *Gc, thread: *Thread) void {
        gc.syncStorage(&thread.gc, threadCapacityBytes(thread));
    }

    pub fn collectGarbageValue(gc: *Gc, thread: *Thread, op: bytecode.Call) !void {
        const state = gc.parentState();
        const option = argValue(state, thread, op, 0);
        if (state.gc.collecting) {
            // Lua rejects collector controls from finalizers, but validates arguments first.
            if (option == .string and std.mem.eql(u8, option.string, "param")) {
                _ = try gc.collectGarbageParam(argValue(state, thread, op, 1));
                if (op.arg_count >= 3 and argValue(state, thread, op, 2) != .nil) {
                    _ = toInteger(argValue(state, thread, op, 2)) orelse return state.fail("number expected");
                }
                return state.returnValues(thread, op.base, op.return_count, &.{.{ .integer = -1 }});
            }
            if (option == .string and std.mem.eql(u8, option.string, "step") and op.arg_count >= 2 and argValue(state, thread, op, 1) != .nil) {
                _ = toInteger(argValue(state, thread, op, 1)) orelse return state.fail("number expected");
            }
            if (option == .nil) return state.returnValues(thread, op.base, op.return_count, &.{.nil});
            if (option == .string) inline for (.{ "collect", "step", "count", "isrunning", "stop", "restart", "incremental", "generational" }) |name| {
                if (std.mem.eql(u8, option.string, name)) return state.returnValues(thread, op.base, op.return_count, &.{.nil});
            };
            return gc.failInvalidOption(thread, op);
        }
        if (option == .nil or (option == .string and std.mem.eql(u8, option.string, "collect"))) {
            if (state.gc.conservative_depth != 0) {
                try gc.collectConservatively(thread);
            } else {
                try gc.collectWithFinalizers(thread);
            }
            try state.returnValues(thread, op.base, op.return_count, &.{.{ .integer = 0 }});
            return;
        }
        if (option == .string and std.mem.eql(u8, option.string, "step")) {
            const budget = if (op.arg_count >= 2 and argValue(state, thread, op, 1) != .nil) toInteger(argValue(state, thread, op, 1)) orelse return state.fail("number expected") else 0;
            const complete = try gc.collectStep(thread, budget);
            try state.returnValues(thread, op.base, op.return_count, &.{.{ .boolean = complete }});
            return;
        }
        if (option == .string and std.mem.eql(u8, option.string, "count")) {
            try state.returnValues(thread, op.base, op.return_count, &.{.{ .number = @as(f64, @floatFromInt(gc.refreshAllocationTotal())) / 1024.0 }});
            return;
        }
        if (option == .string and std.mem.eql(u8, option.string, "isrunning")) {
            try state.returnValues(thread, op.base, op.return_count, &.{.{ .boolean = state.gc.running }});
            return;
        }
        if (option == .string and std.mem.eql(u8, option.string, "stop")) {
            state.gc.running = false;
            try state.returnValues(thread, op.base, op.return_count, &.{.{ .integer = 0 }});
            return;
        }
        if (option == .string and std.mem.eql(u8, option.string, "restart")) {
            state.gc.running = true;
            try state.returnValues(thread, op.base, op.return_count, &.{.{ .integer = 0 }});
            return;
        }
        if (option == .string and std.mem.eql(u8, option.string, "incremental")) {
            const old = gc.setMode(.incremental);
            try state.returnValues(thread, op.base, op.return_count, &.{.{ .string = try state.strings.intern(old.name()) }});
            return;
        }
        if (option == .string and std.mem.eql(u8, option.string, "generational")) {
            const old = gc.setMode(.generational);
            try state.returnValues(thread, op.base, op.return_count, &.{.{ .string = try state.strings.intern(old.name()) }});
            return;
        }
        if (option == .string and std.mem.eql(u8, option.string, "param")) {
            const param_value = argValue(state, thread, op, 1);
            const param = try gc.collectGarbageParam(param_value);
            const old = state.gc.params.get(param);
            if (op.arg_count >= 3 and argValue(state, thread, op, 2) != .nil) {
                const new_value = toInteger(argValue(state, thread, op, 2)) orelse return state.fail("number expected");
                // lua_gc receives a C int, and negative values query without setting.
                const narrowed: i32 = @truncate(new_value);
                if (narrowed >= 0) {
                    state.gc.params.set(param, roundedLuaParam(@intCast(narrowed)));
                    gc.resetAutoThreshold();
                }
            }
            try state.returnValues(thread, op.base, op.return_count, &.{.{ .integer = old }});
            return;
        }
        return gc.failInvalidOption(thread, op);
    }

    fn failInvalidOption(gc: *Gc, thread: *Thread, op: bytecode.Call) anyerror {
        const state = gc.parentState();
        const name = try state.expectArgumentString(thread, op, "collectgarbage", 0);
        const message = try std.fmt.allocPrint(state.allocator, "invalid option '{s}'", .{name});
        defer state.allocator.free(message);
        return state.failArgumentMessage("collectgarbage", 1, try state.strings.intern(message));
    }

    fn collectGarbageParam(gc: *Gc, value: Value) !GcParam {
        const state = gc.parentState();
        if (value != .string) return state.fail("bad argument #2 to 'collectgarbage'");
        if (std.mem.eql(u8, value.string, "minormul")) return .minormul;
        if (std.mem.eql(u8, value.string, "majorminor")) return .majorminor;
        if (std.mem.eql(u8, value.string, "minormajor")) return .minormajor;
        if (std.mem.eql(u8, value.string, "pause")) return .pause;
        if (std.mem.eql(u8, value.string, "stepmul")) return .stepmul;
        if (std.mem.eql(u8, value.string, "stepsize")) return .stepsize;
        return state.fail("bad argument #2 to 'collectgarbage'");
    }

    fn luaFastStep(gc: *Gc) bool {
        const state = gc.parentState();
        const incremental = state.gc.mode == .incremental or state.gc.major_pending or
            (state.gc.phase != .pause and state.gc.cycle == .major);
        const size: usize = @intCast(@max(state.gc.params.stepsize, 0));
        const mul: usize = @intCast(@max(state.gc.params.stepmul, 0));
        return incremental and ((size / @sizeOf(usize)) *| mul / 100 == 0);
    }

    /// Lua 5.5 expresses explicit step budgets in bytes; zero forces a basic step.
    fn collectStep(gc: *Gc, thread: ?*Thread, budget: i64) !bool {
        const state = gc.parentState();
        if (state.gc.collecting) return false;
        // Match luaL's integer -> size_t -> signed-memory conversion, including on 32-bit targets.
        const narrowed: isize = @bitCast(@as(usize, @truncate(@as(u64, @bitCast(budget)))));
        if (narrowed > 0) {
            state.gc.next_total -|= @as(usize, @intCast(narrowed));
            if (!gc.shouldRunAuto()) return false;
        }
        // Lua's work calculation can round to zero for nonzero parameters, requesting a full cycle.
        if (gc.luaFastStep()) {
            try gc.collectWithFinalizersMode(thread, state.gc.conservative_depth != 0);
            return true;
        }
        return gc.step(thread, state.gc.conservative_depth != 0);
    }

    fn stepCount(gc: *Gc, thread: ?*Thread, steps: usize) !bool {
        const state = gc.parentState();
        for (0..@max(steps, 1)) |_| {
            if (try gc.step(thread, state.gc.conservative_depth != 0)) return true;
        }
        return false;
    }

    pub fn autoStep(gc: *Gc, thread: ?*Thread) !void {
        const state = gc.parentState();
        if (state.gc.stress_step and state.gc.phase == .pause) state.gc.major_pending = true;
        defer state.gc.stress_mark = state.gc.known_total;
        if (state.gc.stress_collect or gc.luaFastStep()) return gc.collectConservatively(thread);
        _ = try gc.step(thread, true);
    }

    fn basicWork(gc: *Gc) usize {
        const state = gc.parentState();
        const size: usize = @intCast(@max(state.gc.params.stepsize, 1));
        const mul: usize = @intCast(@max(state.gc.params.stepmul, 1));
        return @max(1, (size *| mul / 100) / @sizeOf(usize));
    }

    fn beginCycle(gc: *Gc) void {
        const state = gc.parentState();
        gc.resetMarks();
        state.gc.cycle = if (state.gc.mode == .generational and !state.gc.major_pending) .minor else .major;
        state.gc.cycle_start_total = state.gc.known_total;
        state.gc.phase = .propagate;
        if (state.gc.cycle == .minor) for (state.table_allocations.items[state.gc.old.table_allocations..]) |table| gc.tableCandidate(table);
        if (state.gc.cycle == .minor) for (state.gc.remembered.items) |object| {
            gc.forceEnqueue(object);
            if (object == .table) gc.tableCandidate(object.table);
        };
        gc.markRoots();
    }

    fn revisitMutable(gc: *Gc) void {
        const state = gc.parentState();
        // Thread stacks and open upvalues have no write barrier; revisit them at the atomic boundary.
        const thread_start = if (state.gc.cycle == .minor) state.gc.old.thread_allocations else 0;
        for (state.thread_allocations.items[thread_start..]) |thread| {
            if (gc.isMarked(thread)) gc.traceThread(thread);
        }
        const upvalue_start = if (state.gc.cycle == .minor) state.gc.old.upvalue_allocations else 0;
        for (state.upvalue_allocations.items[upvalue_start..]) |upvalue| {
            if (upvalue.is_open and gc.isMarked(upvalue)) gc.traceUpvalue(upvalue);
        }
        if (state.gc.cycle == .minor) for (state.gc.remembered.items) |object| switch (object) {
            .thread => |t| gc.traceThread(t),
            .upvalue => |u| if (u.is_open) gc.traceUpvalue(u),
            else => {},
        };
        if (state.current_thread) |t| gc.traceThread(t);
        gc.markRoots();
        gc.drain();
    }

    fn atomic(gc: *Gc) !void {
        const state = gc.parentState();
        if (state.gc.cycle == .major) for (state.table_allocations.items) |table| gc.tableCandidate(table);
        gc.revisitMutable();
        gc.convergeEphemerons();
        // Finish fallible detachment before touching weak entries or finalizers so failure can retry.
        if (state.rollback) |journal| {
            try journal.prepareCollection(state);
            try gc.prepareRollbackTableWrites();
            if (!state.gc.mark_all_stack_registers) for (state.thread_allocations.items) |thread| try rollback.threadWritable(thread);
            for (state.userdata_allocations.items[if (state.gc.cycle == .minor) state.gc.old.userdata_allocations else 0..]) |userdata| {
                if (!gc.isMarked(userdata) and !userdata.finalized and userdata.finalizer != null) try rollback.userdataWritable(userdata);
            }
        }
        gc.clearWeakValues();
        gc.separateUserdataFinalizers(.builtin);
        gc.prepareLuaFinalizers();
        gc.separateUserdataFinalizers(.host);
        gc.drain();
        gc.convergeEphemerons();
        gc.clearWeakTables();
        gc.clearDeadHashKeys();
        if (!state.gc.mark_all_stack_registers) gc.clearUnmarkedStackSlots();
    }

    fn clearUnmarkedStackSlots(gc: *Gc) void {
        const state = gc.parentState();
        for (state.thread_allocations.items) |thread| {
            if (!gc.isMarked(thread)) continue;
            for (thread.stack.items) |*slot| {
                if (gc.valueIsCollectableUnmarked(slot.*)) slot.* = .nil;
            }
        }
    }

    /// A basic step bounds propagation by references and sweeping by objects.
    /// Atomic weak processing, large objects, and one finalizer can exceed the target.
    pub fn step(gc: *Gc, thread: ?*Thread, conservative: bool) !bool {
        const state = gc.parentState();
        if (state.gc.collecting) return false;
        state.gc.collecting = true;
        const previous_mark_all = state.gc.mark_all_stack_registers;
        state.gc.mark_all_stack_registers = conservative;
        defer {
            state.gc.mark_all_stack_registers = previous_mark_all;
            state.gc.collecting = false;
        }
        const budget = gc.basicWork();
        switch (state.gc.phase) {
            .pause => {
                gc.beginCycle();
                if (state.gc.cycle == .minor) {
                    gc.drain();
                    state.gc.phase = .atomic;
                    try gc.atomic();
                    state.gc.phase = .sweep_threads;
                    inline for (.{ "thread_allocations", "closure_allocations", "upvalue_allocations", "string_allocations", "userdata_allocations", "table_allocations" }) |field| {
                        state.gc.sweep_cursor = @field(state.gc.old, field);
                        _ = gc.sweepList(field, std.math.maxInt(usize));
                    }
                    gc.promoteYoung();
                    state.gc.minor_count += 1;
                    state.gc.major_pending = state.gc.params.minormajor != 0 and
                        state.gc.known_total > state.gc.major_base +| @max(256, state.gc.major_base *| @as(usize, @intCast(@max(state.gc.params.minormajor, 0))) / 100);
                    state.gc.phase = .finalize;
                    if (try gc.runFinalizerBatch(thread, 1)) _ = try gc.runUserdataFinalizerBatch(1);
                    gc.drain();
                    state.gc.phase = .pause;
                    gc.resetAutoThreshold();
                    return false;
                }
            },
            .propagate => {
                _ = gc.propagate(budget);
                if (state.gc.work.items.len == 0) state.gc.phase = .atomic;
            },
            .atomic => {
                try gc.atomic();
                if (state.gc.cycle == .major) {
                    state.gc.remembered.clearRetainingCapacity();
                    state.gc.old = .{};
                }
                state.gc.phase = .sweep_threads;
                state.gc.sweep_cursor = if (state.gc.cycle == .minor) state.gc.old.thread_allocations else 0;
            },
            inline .sweep_threads, .sweep_closures, .sweep_upvalues, .sweep_strings, .sweep_userdata, .sweep_tables => |phase| {
                _ = gc.propagate(budget); // References installed since the preceding step.
                if (state.gc.work.items.len != 0) return false;
                const field = comptime switch (phase) {
                    .sweep_threads => "thread_allocations",
                    .sweep_closures => "closure_allocations",
                    .sweep_upvalues => "upvalue_allocations",
                    .sweep_strings => "string_allocations",
                    .sweep_userdata => "userdata_allocations",
                    .sweep_tables => "table_allocations",
                    else => unreachable,
                };
                if (gc.sweepList(field, budget)) {
                    state.gc.phase = @enumFromInt(@intFromEnum(phase) + 1);
                    state.gc.sweep_cursor = if (state.gc.cycle == .minor) switch (state.gc.phase) {
                        .sweep_closures => state.gc.old.closure_allocations,
                        .sweep_upvalues => state.gc.old.upvalue_allocations,
                        .sweep_strings => state.gc.old.string_allocations,
                        .sweep_userdata => state.gc.old.userdata_allocations,
                        .sweep_tables => state.gc.old.table_allocations,
                        else => 0,
                    } else 0;
                }
            },
            .finalize => {
                if (try gc.runFinalizerBatch(thread, 1) and try gc.runUserdataFinalizerBatch(1)) {
                    gc.drain();
                    const major = state.gc.cycle == .major;
                    if (major) {
                        const reclaimed = state.gc.cycle_start_total -| state.gc.known_total;
                        const added = state.gc.cycle_start_total -| state.gc.major_base;
                        const return_to_minor = reclaimed > added *| @as(usize, @intCast(@max(state.gc.params.majorminor, 0))) / 100;
                        gc.normalizeBaseline();
                        state.gc.major_pending = state.gc.mode == .generational and !return_to_minor;
                    } else {
                        gc.promoteYoung();
                        state.gc.phase = .pause;
                    }
                    gc.resetAutoThreshold();
                    return major;
                }
            },
        }
        state.gc.next_total = state.gc.known_total +| @as(usize, @intCast(@max(state.gc.params.stepsize, 1)));
        return false;
    }

    pub fn collect(gc: *Gc) !void {
        const state = gc.parentState();
        try gc.collectWithFinalizers(state.current_thread);
    }

    pub fn getParam(gc: *const Gc, param: GcParam) i64 {
        const state = gc.constParentState();
        return state.gc.params.get(param);
    }

    pub fn setParam(gc: *Gc, param: GcParam, value: i64) void {
        const state = gc.parentState();
        state.gc.params.set(param, value);
    }

    fn collectConservatively(gc: *Gc, thread: ?*Thread) !void {
        try gc.collectWithFinalizersMode(thread, true);
    }

    pub fn collectWithFinalizers(gc: *Gc, thread: ?*Thread) !void {
        try gc.collectWithFinalizersMode(thread, false);
    }

    fn collectWithFinalizersMode(gc: *Gc, thread: ?*Thread, mark_all_stack_registers: bool) !void {
        const state = gc.parentState();
        if (state.gc.collecting) return;
        const was_major = state.gc.major_pending or (state.gc.phase != .pause and state.gc.cycle == .major);
        // Restart from current roots, abandoning an earlier partial cycle's scratch state without callbacks.
        gc.normalizeBaseline();
        state.gc.major_pending = true;
        while (!try gc.step(thread, mark_all_stack_registers)) {}
        // Like Lua, an explicit full collection preserves the generational submode (minor or major).
        if (state.gc.mode == .generational) {
            state.gc.major_pending = was_major;
            gc.resetAutoThreshold();
        }
    }

    pub fn shouldRunAuto(gc: *Gc) bool {
        const state = gc.parentState();
        if (state.current_thread) |thread| gc.syncThreadStorage(thread);
        return !state.gc.collecting and gc.currentAllocationTotal() >= state.gc.next_total;
    }

    pub fn resetAutoThreshold(gc: *Gc) void {
        const state = gc.parentState();
        const total = gc.currentAllocationTotal();
        state.gc.next_total = if (state.gc.mode == .generational and !state.gc.major_pending)
            total +| @max(256, total *| @as(usize, @intCast(@max(state.gc.params.minormul, 0))) / 100)
        else
            @max(total +| 256, total *| @as(usize, @intCast(@max(state.gc.params.pause, 100))) / 100);
    }

    pub fn normalizeBaseline(gc: *Gc) void {
        const state = gc.parentState();
        gc.resetMarks();
        state.gc.generation += 1;
        state.gc.remembered.clearRetainingCapacity();
        state.gc.major_pending = false;
        state.gc.phase = .pause;
        state.gc.sweep_cursor = 0;
        inline for (reflection.fieldsOf(types.GcGenerations)) |f| @field(state.gc.old, f) = @field(state, f).items.len;
        state.gc.major_base = state.gc.known_total;
        gc.resetAutoThreshold();
    }

    fn resetMarks(gc: *Gc) void {
        const state = gc.parentState();
        state.gc.epoch += 1;
        state.gc.work.clearRetainingCapacity();
        state.gc.weak.clearRetainingCapacity();
        state.gc.tables.clearRetainingCapacity();
        state.gc.finalizers.clearRetainingCapacity();
        state.gc.work_done = 0;
    }

    fn markRoots(gc: *Gc) void {
        const state = gc.parentState();
        var pending_userdata = state.userdata_pending_finalizer_head;
        while (pending_userdata) |userdata| : (pending_userdata = userdata.finalizer_next) gc.markUserdata(userdata);
        var pending = state.table_pending_finalizer_head;
        while (pending) |table| : (pending = table.finalizer_next) gc.markTable(table);
        var lua_pending = state.userdata_lua_pending_head;
        while (lua_pending) |userdata| : (lua_pending = userdata.lua_finalizer_next) gc.markUserdata(userdata);
        var scope = state.userdata_scope;
        while (scope) |active| : (scope = active.previous) gc.markUserdata(active.userdata);
        if (state.global_table) |table| if (gc.isTrackedTable(table)) gc.markTable(table);
        for (state.api_roots.items) |root| gc.markValue(root);
        var value_roots = state.value_roots;
        while (value_roots) |roots| : (value_roots = roots.previous) for (roots.values) |value| gc.markValue(value);
        // No Lua varargs keep native callback arguments alive, and outer callbacks may be suspended.
        var callback = state.active_api_callback;
        while (callback) |context| : (callback = context.parent) {
            gc.forceEnqueue(.{ .thread = context.thread });
            gc.markString(context.function_name);
            gc.markStackRange(context.thread, context.argument_base, context.argCount());
            for (context.returns.items()) |value| gc.markValue(value);
            if (context.error_value) |value| gc.markValue(value);
        }
        gc.markRuntimeErrorPayload(state.last_error);
        if (state.current_thread) |thread| gc.forceEnqueue(.{ .thread = thread });
        if (state.file_metatable) |metatable| if (gc.isTrackedTable(metatable)) gc.markTable(metatable);
        if (state.fs_file_metatable) |metatable| if (gc.isTrackedTable(metatable)) gc.markTable(metatable);
        if (state.io_input) |file| if (gc.isTrackedUserdata(file)) gc.markUserdata(file);
        if (state.io_output) |file| if (gc.isTrackedUserdata(file)) gc.markUserdata(file);
        if (state.string_metatable) |metatable| if (gc.isTrackedTable(metatable)) gc.markTable(metatable);
        if (state.number_metatable) |metatable| if (gc.isTrackedTable(metatable)) gc.markTable(metatable);
        if (state.boolean_metatable) |metatable| if (gc.isTrackedTable(metatable)) gc.markTable(metatable);
        if (state.nil_metatable) |metatable| if (gc.isTrackedTable(metatable)) gc.markTable(metatable);
        for (state.library_tables.values) |slot| if (slot) |table| if (gc.isTrackedTable(table)) gc.markTable(table);
    }

    pub fn markValue(gc: *Gc, value: Value) void {
        const state = gc.parentState();
        if (state.gc.phase == .pause and !state.gc.collecting) return;
        state.gc.work_done +|= 1;
        gc.noteYoung(value);
        switch (value) {
            .string => |string| gc.markString(string),
            .table => |table| if (gc.isTrackedTable(table)) gc.markTable(table),
            .userdata => |userdata| if (gc.isTrackedUserdata(userdata)) gc.markUserdata(userdata),
            .closure => |closure| if (gc.isTrackedClosure(closure)) gc.markClosure(closure),
            .thread, .coroutine_wrapper => |thread| if (gc.isTrackedThread(thread) or thread == state.current_thread) gc.markThread(thread),
            .gmatch_iterator => |table| if (gc.isTrackedTable(table)) gc.markTable(table),
            else => {},
        }
    }

    fn markRuntimeErrorPayload(gc: *Gc, payload: ?RuntimeErrorPayload) void {
        const active = payload orelse return;
        switch (active) {
            .diagnostic => |message| gc.markString(message),
            .argument => |argument| {
                gc.markString(argument.function_name);
                switch (argument.detail) {
                    .message => |message| gc.markString(message),
                    .expected => |expected| {
                        gc.markString(expected.expected);
                        gc.markString(expected.actual);
                    },
                }
            },
            .lua_value => |value| gc.markValue(value),
        }
    }

    pub fn markString(gc: *Gc, bytes: []const u8) void {
        const state = gc.parentState();
        if (gc.findStringAllocation(bytes)) |index| {
            if (!gc.isOld(&state.string_allocations.items[index])) state.gc.found_young = true;
            state.string_allocations.items[index].gc.epoch = state.gc.epoch;
            state.string_allocations.items[index].gc.color = .black;
        }
    }

    fn markTable(gc: *Gc, table: *Table) void {
        const state = gc.parentState();
        if (gc.isTrackedTable(table) and !gc.isOld(table)) state.gc.found_young = true;
        gc.enqueue(.{ .table = table });
    }

    fn traceTable(gc: *Gc, table: *Table) void {
        const state = gc.parentState();
        gc.tableCandidate(table);
        for (table.array.items) |value| gc.noteYoung(value);
        for (table.entries.items) |entry| {
            if (entry.value == .nil) continue;
            gc.noteYoung(entry.key);
            gc.noteYoung(entry.value);
        }
        const mode = gc.weakMode(table);
        if (@intFromEnum(state.gc.phase) < @intFromEnum(types.GcPhase.sweep_threads) and (mode.keys or mode.values) and table.gc.weak_epoch != state.gc.epoch) {
            table.gc.weak_epoch = state.gc.epoch;
            state.gc.weak.appendAssumeCapacity(table);
        }
        if (table.metatable) |metatable| gc.markTable(metatable);
        const weak = gc.weakMode(table);
        if (weak.keys and weak.values) {
            gc.markWeakTableStrings(table, true, true);
            return;
        }
        if (weak.values) {
            for (table.entries.items) |entry| if (entry.value != .nil) gc.markValue(entry.key);
            gc.markWeakTableStrings(table, false, true);
            return;
        }
        if (weak.keys) {
            for (table.array.items) |value| gc.markValue(value);
            _ = gc.markEphemeronValues(table);
            return;
        }
        for (table.array.items) |value| gc.markValue(value);
        for (table.entries.items) |entry| {
            if (entry.value == .nil) continue;
            gc.markValue(entry.key);
            gc.markValue(entry.value);
        }
    }

    fn markUserdata(gc: *Gc, userdata: *Userdata) void {
        const state = gc.parentState();
        if (gc.isTrackedUserdata(userdata) and !gc.isOld(userdata)) state.gc.found_young = true;
        gc.enqueue(.{ .userdata = userdata });
    }

    fn traceUserdata(gc: *Gc, userdata: *Userdata) void {
        if (userdata.metatable) |metatable| gc.markTable(metatable);
    }

    fn markWeakTableStrings(gc: *Gc, table: *Table, keys: bool, values: bool) void {
        if (values) {
            for (table.array.items) |value| gc.markWeakString(value);
        }
        for (table.entries.items) |entry| {
            if (entry.value == .nil) continue;
            if (keys) gc.markWeakString(entry.key);
            if (values) gc.markWeakString(entry.value);
        }
    }

    fn markWeakString(gc: *Gc, value: Value) void {
        if (value == .string) gc.markString(value.string);
    }

    fn markClosure(gc: *Gc, closure: *Closure) void {
        const state = gc.parentState();
        if (gc.isTrackedClosure(closure) and !gc.isOld(closure)) state.gc.found_young = true;
        // A native adapter's closure may live on the host stack; never keep its address in a worklist.
        if (!gc.isTrackedClosure(closure)) {
            if (gc.markedThisCycle(closure)) return;
            closure.gc.epoch = state.gc.epoch;
            closure.gc.color = .black;
            gc.traceClosure(closure);
            return;
        }
        gc.enqueue(.{ .closure = closure });
    }

    fn traceClosure(gc: *Gc, closure: *Closure) void {
        const state = gc.parentState();
        if (closure.constants) |constants| for (constants) |constant| {
            if (constant) |value| gc.markValue(value);
        };
        for (closure.upvalues) |upvalue| {
            if (!gc.isOld(upvalue)) state.gc.found_young = true;
            gc.markUpvalue(upvalue);
        }
    }

    fn markUpvalue(gc: *Gc, upvalue: *Upvalue) void {
        const state = gc.parentState();
        if (gc.isTrackedUpvalue(upvalue) and !gc.isOld(upvalue)) state.gc.found_young = true;
        if (!gc.isTrackedUpvalue(upvalue)) return;
        gc.enqueue(.{ .upvalue = upvalue });
    }

    fn traceUpvalue(gc: *Gc, upvalue: *Upvalue) void {
        if (upvalue.is_open) {
            if (upvalue.stack_index < upvalue.owner.stack.items.len) gc.markValue(upvalue.owner.stack.items[upvalue.stack_index]);
        } else {
            gc.markValue(upvalue.closed);
        }
    }

    fn markThread(gc: *Gc, thread: *Thread) void {
        const state = gc.parentState();
        if (gc.isTrackedThread(thread) and !gc.isOld(thread)) state.gc.found_young = true;
        gc.enqueue(.{ .thread = thread });
    }

    fn traceThread(gc: *Gc, thread: *Thread) void {
        const state = gc.parentState();
        if (std.debug.runtime_safety) std.debug.assert(thread.frame_storage_bytes == frameStorageBytes(thread));
        gc.syncThreadStorage(thread);
        gc.markValue(thread.entry);
        if (thread.resume_parent) |parent| {
            if (gc.isTrackedThread(parent) and !gc.isOld(parent)) state.gc.found_young = true;
            gc.forceEnqueue(.{ .thread = parent });
        }
        gc.markThreadStack(thread);
        gc.markValue(thread.hook);
        gc.markValue(thread.hook_level2_func);
        for (thread.hook_transfer_values) |value| gc.markValue(value);
        for (thread.yield_values.items) |value| gc.markValue(value);
        if (thread.close_error_value) |value| gc.markValue(value);
        if (thread.pending_unwind_error) |value| gc.markValue(value);
        gc.markValue(thread.error_handler);
        inline for (.{ "error_traceback", "hook_return_name", "next_call_name", "next_call_namewhat" }) |field| {
            if (@field(thread, field)) |name| gc.markString(name);
        }
        for (thread.protected_continuations.items) |continuation| {
            gc.markRuntimeErrorPayload(continuation.context.last_error);
            gc.markValue(continuation.context.error_handler);
            gc.markValue(continuation.context.previous_error_handler);
        }
        for (thread.frames.items) |frame| {
            gc.markClosure(frame.closure);
            gc.markValue(frame.vararg_table_local);
            if (frame.debug_name_override) |name| gc.markString(name);
            if (frame.debug_namewhat_override) |name| gc.markString(name);
            for (frame.varargs) |value| gc.markValue(value);
            if (frame.pending_returns) |returns| for (returns) |value| gc.markValue(value);
        }
        var current = thread.open_upvalues;
        while (current) |upvalue| : (current = upvalue.next) gc.markUpvalue(upvalue);
    }

    fn markThreadStack(gc: *Gc, thread: *Thread) void {
        const state = gc.parentState();
        if (state.gc.mark_all_stack_registers) {
            gc.markStackRange(thread, 0, thread.stack.items.len);
            return;
        }
        const frames = thread.frames.items;
        for (frames, 0..) |frame, index| {
            const live_end = if (index + 1 < frames.len) frames[index + 1].base else innermostLiveEnd(thread, frame);
            if (live_end > frame.base) gc.markStackRange(thread, frame.base, live_end - frame.base);
            for (frame.proto.locals.items) |local| {
                if (frame.base + local.register < live_end or !localActiveAt(local, frame.pc)) continue;
                gc.markStackRange(thread, frame.base + local.register, 1);
            }
        }
        gc.markStackRange(thread, thread.last_result_base, thread.last_result_count);
        gc.markStackRange(thread, thread.last_transfer_base, thread.last_transfer_count);
        gc.markStackRange(thread, thread.yield_result_base, thread.yield_result_count);
    }

    fn markStackRange(gc: *Gc, thread: *Thread, base: usize, count: usize) void {
        if (base >= thread.stack.items.len) return;
        const end = @min(thread.stack.items.len, base + count);
        for (thread.stack.items[base..end]) |value| gc.markValue(value);
    }

    fn weakMode(gc: *Gc, table: *Table) WeakMode {
        const state = gc.parentState();
        _ = state;
        const metatable = table.metatable orelse return .{};
        const mode = metatable.get(.{ .string = "__mode" });
        if (mode != .string) return .{};
        return .{
            .keys = std.mem.indexOfScalar(u8, mode.string, 'k') != null,
            .values = std.mem.indexOfScalar(u8, mode.string, 'v') != null,
        };
    }

    fn markEphemeronValues(gc: *Gc, table: *Table) bool {
        var changed = false;
        for (table.entries.items) |entry| {
            if (entry.value == .nil) continue;
            if (gc.valueIsWeaklyCleared(entry.key)) continue;
            gc.markValue(entry.key);
            if (gc.markValueChanged(entry.value)) changed = true;
        }
        return changed;
    }

    fn convergeEphemerons(gc: *Gc) void {
        const state = gc.parentState();
        var changed = true;
        while (changed) {
            gc.drain();
            changed = false;
            for (state.gc.weak.items) |table| {
                if (!gc.isMarked(table)) continue;
                const weak = gc.weakMode(table);
                if (!weak.keys or weak.values) continue;
                if (gc.markEphemeronValues(table)) changed = true;
            }
        }
    }

    fn markValueChanged(gc: *Gc, value: Value) bool {
        const was_marked = gc.valueIsMarked(value);
        gc.markValue(value);
        return !was_marked and gc.valueIsMarked(value);
    }

    fn valueIsMarked(gc: *Gc, value: Value) bool {
        const state = gc.parentState();
        return switch (value) {
            .string => |string| if (gc.findStringAllocation(string)) |index| gc.isMarked(&state.string_allocations.items[index]) else true,
            .table, .gmatch_iterator => |table| !gc.isTrackedTable(table) or gc.isMarked(table),
            .userdata => |userdata| !gc.isTrackedUserdata(userdata) or gc.isMarked(userdata),
            .closure => |closure| !gc.isTrackedClosure(closure) or gc.isMarked(closure),
            .thread, .coroutine_wrapper => |thread| !gc.isTrackedThread(thread) or gc.isMarked(thread),
            else => true,
        };
    }

    fn valueIsWeaklyCleared(gc: *Gc, value: Value) bool {
        return switch (value) {
            .table, .gmatch_iterator => |table| gc.isTrackedTable(table) and !gc.isMarked(table),
            .userdata => |userdata| gc.isTrackedUserdata(userdata) and !gc.isMarked(userdata),
            .closure => |closure| gc.isTrackedClosure(closure) and !gc.isMarked(closure),
            .thread, .coroutine_wrapper => |thread| gc.isTrackedThread(thread) and !gc.isMarked(thread),
            else => false,
        };
    }

    fn valueIsCollectableUnmarked(gc: *Gc, value: Value) bool {
        const state = gc.parentState();
        return switch (value) {
            .string => |string| if (gc.findStringAllocation(string)) |index| !gc.isMarked(&state.string_allocations.items[index]) else false,
            .table, .gmatch_iterator => |table| gc.isTrackedTable(table) and !gc.isMarked(table),
            .userdata => |userdata| gc.isTrackedUserdata(userdata) and !gc.isMarked(userdata),
            .closure => |closure| gc.isTrackedClosure(closure) and !gc.isMarked(closure),
            .thread, .coroutine_wrapper => |thread| gc.isTrackedThread(thread) and !gc.isMarked(thread),
            else => false,
        };
    }

    fn prepareRollbackTableWrites(gc: *Gc) !void {
        const state = gc.parentState();
        for (state.gc.tables.items) |table| {
            if (table.rollback == null) continue;
            const weak = gc.weakMode(table);
            var changed = false;
            if (weak.values) for (table.array.items) |value| {
                if (gc.valueIsWeaklyCleared(value)) {
                    changed = true;
                    break;
                }
            };
            if (!changed) for (table.entries.items) |entry| {
                if ((weak.values and gc.valueIsWeaklyCleared(entry.value)) or
                    (weak.keys and gc.valueIsWeaklyCleared(entry.key)) or
                    (entry.value == .nil and gc.valueIsCollectableUnmarked(entry.key)))
                {
                    changed = true;
                    break;
                }
            };
            if (changed) {
                try rollback.tableWritable(table);
                gc.noteTableCapacityDelta(table, 0);
            }
        }
    }

    fn clearWeakValues(gc: *Gc) void {
        const state = gc.parentState();
        for (state.gc.weak.items) |table| {
            if (!gc.isMarked(table)) continue;
            if (!gc.weakMode(table).values) continue;
            gc.clearWeakTableValues(table);
        }
    }

    fn clearWeakTables(gc: *Gc) void {
        const state = gc.parentState();
        for (state.gc.weak.items) |table| {
            if (!gc.isMarked(table)) continue;
            const weak = gc.weakMode(table);
            if (weak.values) gc.clearWeakTableValues(table);
            if (weak.keys) gc.clearWeakTableKeys(table);
        }
    }

    fn clearDeadHashKeys(gc: *Gc) void {
        const state = gc.parentState();
        for (state.gc.tables.items) |table| {
            if (!gc.isMarked(table)) continue;
            var read_index: usize = 0;
            var write_index: usize = 0;
            while (read_index < table.entries.items.len) : (read_index += 1) {
                const entry = table.entries.items[read_index];
                if (entry.value == .nil and gc.valueIsCollectableUnmarked(entry.key)) {
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

    fn clearWeakTableValues(gc: *Gc, table: *Table) void {
        for (table.array.items) |*value| {
            if (gc.valueIsWeaklyCleared(value.*)) value.* = .nil;
        }
        var index: usize = 0;
        while (index < table.entries.items.len) {
            if (gc.valueIsWeaklyCleared(table.entries.items[index].value)) {
                table.removeEntryAt(index);
            } else {
                index += 1;
            }
        }
    }

    fn clearWeakTableKeys(gc: *Gc, table: *Table) void {
        var index: usize = 0;
        while (index < table.entries.items.len) {
            if (gc.valueIsWeaklyCleared(table.entries.items[index].key)) {
                table.removeEntryAt(index);
            } else {
                index += 1;
            }
        }
    }

    pub fn writeTableBarrier(gc: *Gc, table: *Table, key: Value, value: Value) void {
        const state = gc.parentState();
        gc.rememberObject(.{ .table = table });
        if (key == .string and std.mem.eql(u8, key.string, "__mode")) {
            var current = state.table_metatable_head;
            while (current) |dependent| : (current = dependent.metatable_next) {
                if (dependent.metatable != table) continue;
                gc.rememberObject(.{ .table = dependent });
                if (state.gc.phase != .pause and dependent.gc.color != .gray) {
                    dependent.gc.epoch = 0;
                    gc.forceEnqueue(.{ .table = dependent });
                }
            }
        }
        if (state.gc.phase == .pause or !gc.isMarked(table)) return;
        const weak = gc.weakMode(table);
        gc.markWeakString(key);
        gc.markWeakString(value);
        if (!weak.keys) gc.markValue(key);
        if (!weak.values and (!weak.keys or !gc.valueIsWeaklyCleared(key))) gc.markValue(value);
    }

    pub fn writeBarrier(gc: *Gc, parent: anytype, child: Value) void {
        const state = gc.parentState();
        const T = @typeInfo(@TypeOf(parent)).pointer.child;
        const tag = comptime if (T == Table) "table" else if (T == Userdata) "userdata" else if (T == Closure) "closure" else if (T == Upvalue) "upvalue" else "thread";
        gc.rememberObject(@unionInit(types.GcObject, tag, parent));
        if (state.gc.phase == .pause or !gc.isMarked(parent)) return;
        gc.markValue(child);
    }

    fn prepareLuaFinalizers(gc: *Gc) void {
        const state = gc.parentState();
        state.gc.finalizers.clearRetainingCapacity();
        // A minor collection sees only young and remembered tables here. Selection precedes resurrection.
        for (state.gc.tables.items) |table| {
            if (!table.finalizer_registered or gc.isMarked(table)) continue;
            state.gc.finalizers.appendAssumeCapacity(.{ .table = table });
        }
        for (state.userdata_allocations.items[if (state.gc.cycle == .minor) state.gc.old.userdata_allocations else 0..]) |userdata| {
            if (!userdata.lua_finalizer_registered or userdata.finalized or gc.isMarked(userdata)) continue;
            state.gc.finalizers.appendAssumeCapacity(.{ .userdata = userdata });
        }
        std.mem.sort(types.FinalizerObject, state.gc.finalizers.items, {}, struct {
            fn newer(_: void, a: types.FinalizerObject, b: types.FinalizerObject) bool {
                return a.order() > b.order();
            }
        }.newer);
        var tail = &state.table_pending_finalizer_head;
        var tail_owner: ?*Table = null;
        while (tail.*) |table| {
            tail = &table.finalizer_next;
            tail_owner = table;
        }
        var userdata_tail = &state.userdata_lua_pending_head;
        var userdata_tail_owner: ?*Userdata = null;
        while (userdata_tail.*) |userdata| {
            userdata_tail = &userdata.lua_finalizer_next;
            userdata_tail_owner = userdata;
        }
        for (state.gc.finalizers.items) |object| switch (object) {
            .table => |table| {
                rollback.touch(table);
                if (table.finalizer_prev) |prev| {
                    rollback.touch(prev);
                    prev.finalizer_next = table.finalizer_next;
                } else state.table_finalizer_head = table.finalizer_next;
                if (table.finalizer_next) |next| {
                    rollback.touch(next);
                    next.finalizer_prev = table.finalizer_prev;
                }
                if (tail_owner) |owner| rollback.touch(owner);
                table.finalizer_prev = null;
                table.finalizer_order = metatable_mod.nextFinalizerOrder(state);
                tail.* = table;
                tail_owner = table;
                tail = &table.finalizer_next;
            },
            .userdata => |userdata| {
                rollback.touch(userdata);
                if (userdata_tail_owner) |owner| rollback.touch(owner);
                userdata.lua_finalizer_order = metatable_mod.nextFinalizerOrder(state);
                userdata_tail.* = userdata;
                userdata_tail_owner = userdata;
                userdata_tail = &userdata.lua_finalizer_next;
            },
        };
        tail.* = null;
        userdata_tail.* = null;
        var pending = state.table_pending_finalizer_head;
        while (pending) |table| : (pending = table.finalizer_next) gc.markTable(table);
        var lua_pending = state.userdata_lua_pending_head;
        while (lua_pending) |userdata| : (lua_pending = userdata.lua_finalizer_next) gc.markUserdata(userdata);
        state.gc.finalizers.clearRetainingCapacity();
        gc.drain();
        gc.convergeEphemerons();
    }

    fn nextPendingFinalizer(gc: *Gc) ?types.FinalizerObject {
        const state = gc.parentState();
        const table = state.table_pending_finalizer_head;
        const userdata = state.userdata_lua_pending_head;
        if (table) |t| {
            if (userdata) |u| if (u.lua_finalizer_order < t.finalizer_order) return .{ .userdata = u };
            return .{ .table = t };
        }
        if (userdata) |u| return .{ .userdata = u };
        return null;
    }

    fn runFinalizerBatch(gc: *Gc, thread: ?*Thread, limit: usize) !bool {
        const state = gc.parentState();
        if (gc.nextPendingFinalizer() == null) return true;
        const active_thread = thread orelse return gc.runFinalizersFromHost(limit);
        var count: usize = 0;
        while (gc.nextPendingFinalizer()) |object| {
            if (count >= limit) return false;
            // Reserve before consuming the registration, as protectedCall's reservation can fail.
            const frame = active_thread.frames.items[active_thread.frames.items.len - 1];
            try active_thread.ensureStack(state.allocator, frame.base + @as(usize, active_thread.scratchRegister()) + 2, call_mod.callStackValueLimit(state, active_thread));
            count += 1;
            switch (object) {
                .table => |table| {
                    rollback.touch(table);
                    state.table_pending_finalizer_head = table.finalizer_next;
                    table.finalizer_next = null;
                    table.finalizer_registered = false;
                    try gc.callLuaFinalizer(active_thread, .{ .table = table }, table.metatable);
                },
                .userdata => |userdata| {
                    rollback.touch(userdata);
                    state.userdata_lua_pending_head = userdata.lua_finalizer_next;
                    userdata.lua_finalizer_next = null;
                    userdata.lua_finalizer_registered = false;
                    try gc.callLuaFinalizer(active_thread, .{ .userdata = userdata }, userdata.metatable);
                },
            }
        }
        return true;
    }

    fn callLuaFinalizer(gc: *Gc, thread: *Thread, object: Value, metatable: ?*Table) !void {
        const state = gc.parentState();
        const finalizer = (metatable orelse return).get(.{ .string = "__gc" });
        if (finalizer == .nil) return;
        const previous_name = thread.next_call_name;
        const previous_namewhat = thread.next_call_namewhat;
        thread.next_call_name = "__gc";
        thread.next_call_namewhat = "metamethod";
        thread.native_call_depth += 1;
        defer {
            thread.next_call_name = previous_name;
            thread.next_call_namewhat = previous_namewhat;
            thread.native_call_depth -= 1;
        }
        const result = try call_mod.protectedCall(state, thread, finalizer, &.{object});
        defer value_mod.freeProtectedResult(state.allocator, result);
        switch (result) {
            .success => {},
            .failure => |failure| io_mod.warnError(state, "__gc", failure),
        }
    }

    /// Registers `userdata` for its metatable's `__gc` if needed, like `luaC_checkfinalizer`.
    /// File handles are registered at creation, so they finalize in creation order.
    pub fn checkUserdataFinalizer(gc: *Gc, userdata: *Userdata) void {
        const state = gc.parentState();
        if (userdata.lua_finalizer_registered or userdata.finalized or userdata.finalization_pending) return;
        const metatable = userdata.metatable orelse return;
        const builtin = State.isBuiltinUserdata(userdata);
        if (builtin) {
            if (metatable == state.file_metatable or metatable == state.fs_file_metatable) return;
        } else if (metatable.get(.{ .string = "__gc" }) == .nil) return;
        rollback.touch(userdata);
        userdata.lua_finalizer_registered = true;
        userdata.lua_finalizer_order = if (builtin) State.builtinFinalizerOrder(userdata) else metatable_mod.nextFinalizerOrder(state);
    }

    fn hasUserdataLuaFinalizers(gc: *Gc) bool {
        const state = gc.parentState();
        if (state.userdata_lua_pending_head != null) return true;
        for (state.userdata_allocations.items) |userdata| {
            if (userdata.lua_finalizer_registered) return true;
        }
        return false;
    }

    /// Calls all pending finalizers like `luaC_freeallobjects`, ignoring errors.
    /// An interrupt, `os.exit`, or a host failure stops the calls.
    fn runCloseFinalizersOnThread(gc: *Gc, thread: *Thread) void {
        const state = gc.parentState();
        var finalizers = std.ArrayList(CloseFinalizer).empty;
        defer finalizers.deinit(state.allocator);
        gc.collectCloseFinalizers(&finalizers) catch return;

        var pending = state.table_pending_finalizer_head;
        while (pending) |table| : (pending = table.finalizer_next) table.finalizer_registered = false;
        var registered = state.table_finalizer_head;
        while (registered) |table| {
            registered = table.finalizer_next;
            table.finalizer_registered = false;
            table.finalizer_next = null;
            table.finalizer_prev = null;
        }
        state.table_pending_finalizer_head = null;
        state.table_finalizer_head = null;
        while (state.userdata_lua_pending_head) |userdata| {
            state.userdata_lua_pending_head = userdata.lua_finalizer_next;
            userdata.lua_finalizer_next = null;
        }
        for (state.userdata_allocations.items) |userdata| userdata.lua_finalizer_registered = false;

        const previous_collecting = state.gc.collecting;
        state.gc.collecting = true;
        defer state.gc.collecting = previous_collecting;
        for (finalizers.items) |finalizer| switch (finalizer.object) {
            inline .table, .userdata => |object, tag| {
                const frame = thread.frames.items[thread.frames.items.len - 1];
                thread.ensureStack(state.allocator, frame.base + @as(usize, thread.scratchRegister()) + 2, call_mod.callStackValueLimit(state, thread)) catch return;
                state.budget.reset();
                gc.callLuaFinalizer(thread, @unionInit(Value, @tagName(tag), object), object.metatable) catch return;
            },
            .file => |userdata| _ = state.finalizeBuiltinUserdata(userdata),
        };
    }

    fn collectCloseFinalizers(gc: *Gc, finalizers: *std.ArrayList(CloseFinalizer)) !void {
        const state = gc.parentState();
        const a = state.allocator;
        var pending_table = state.table_pending_finalizer_head;
        var pending_lua = state.userdata_lua_pending_head;
        var pending_lua_tail: ?*Userdata = null;
        while (pending_table != null or pending_lua != null) {
            const take_table = if (pending_table) |table| if (pending_lua) |userdata| table.finalizer_order <= userdata.lua_finalizer_order else true else false;
            if (take_table) {
                try finalizers.append(a, .{ .object = .{ .table = pending_table.? }, .order = 0 });
                pending_table = pending_table.?.finalizer_next;
            } else {
                try finalizers.append(a, .{ .object = .{ .userdata = pending_lua.? }, .order = 0 });
                pending_lua_tail = pending_lua;
                pending_lua = pending_lua.?.lua_finalizer_next;
            }
        }
        var pending_userdata = state.userdata_pending_finalizer_head;
        while (pending_userdata) |userdata| : (pending_userdata = userdata.finalizer_next) {
            if (State.closeFinalizerOrder(userdata) != null) try finalizers.append(a, .{ .object = .{ .file = userdata }, .order = 0 });
        }
        const separated = finalizers.items.len;
        var registered = state.table_finalizer_head;
        while (registered) |table| : (registered = table.finalizer_next) try finalizers.append(a, .{ .object = .{ .table = table }, .order = table.finalizer_order });
        for (state.userdata_allocations.items) |userdata| {
            if (userdata.lua_finalizer_registered and userdata.lua_finalizer_next == null and userdata != pending_lua_tail) {
                try finalizers.append(a, .{ .object = .{ .userdata = userdata }, .order = userdata.lua_finalizer_order });
            }
            if (userdata.finalization_pending) continue;
            const order = State.closeFinalizerOrder(userdata) orelse continue;
            try finalizers.append(a, .{ .object = .{ .file = userdata }, .order = order });
        }
        std.mem.sort(CloseFinalizer, finalizers.items[separated..], {}, CloseFinalizer.newer);
    }

    fn separateUserdataFinalizers(gc: *Gc, comptime kind: enum { builtin, host }) void {
        const state = gc.parentState();
        for (state.userdata_allocations.items[if (state.gc.cycle == .minor) state.gc.old.userdata_allocations else 0..]) |userdata| {
            if (gc.isMarked(userdata) or userdata.finalized or userdata.finalization_pending or userdata.finalizer == null) continue;
            if (userdata.lua_finalizer_registered) continue;
            if (State.isBuiltinUserdata(userdata) != (kind == .builtin)) continue;
            rollback.touch(userdata);
            userdata.finalization_pending = true;
            userdata.finalizer_next = state.userdata_pending_finalizer_head;
            state.userdata_pending_finalizer_head = userdata;
        }
        var pending = state.userdata_pending_finalizer_head;
        while (pending) |userdata| : (pending = userdata.finalizer_next) gc.markUserdata(userdata);
    }

    fn runUserdataFinalizerBatch(gc: *Gc, limit: usize) !bool {
        const state = gc.parentState();
        var count: usize = 0;
        while (state.userdata_pending_finalizer_head) |userdata| {
            if (count == limit) return false;
            // Detach a snapshot baseline payload first so failure leaves this finalizer pending.
            try rollback.userdataWritable(userdata);
            count += 1;
            rollback.touch(userdata);
            state.userdata_pending_finalizer_head = userdata.finalizer_next;
            userdata.finalizer_next = null;
            userdata.finalization_pending = false;
            userdata.finalized = true;
            if (state.finalizeBuiltinUserdata(userdata)) continue;
            if (userdata.payload) |payload| payload.finalize() else if (userdata.finalizer) |finalizer| finalizer(userdata.ptr, userdata.finalizer_data);
        }
        return true;
    }

    fn updateIndex(gc: *Gc, comptime field: []const u8, index: usize) void {
        const state = gc.parentState();
        const item = @field(state, field).items[index];
        if (comptime std.mem.eql(u8, field, "string_allocations")) {
            if (item.bytes.len != 0) state.string_allocation_index.getPtr(@intFromPtr(item.bytes.ptr)).?.* = index;
        } else if (comptime std.mem.eql(u8, field, "table_allocations")) state.table_allocation_index.getPtr(@intFromPtr(item)).?.* = index else state.object_allocation_index.getPtr(@intFromPtr(item)).?.* = index;
    }

    pub fn removeRegistryItem(gc: *Gc, comptime field: []const u8, index: usize) void {
        const state = gc.parentState();
        const boundary = &@field(state.gc.old, field);
        var hole = index;
        if (hole < boundary.*) {
            boundary.* -= 1;
            if (hole != boundary.*) {
                @field(state, field).items[hole] = @field(state, field).items[boundary.*];
                gc.updateIndex(field, hole);
            }
            hole = boundary.*;
        }
        _ = @field(state, field).swapRemove(hole);
        if (hole < @field(state, field).items.len) gc.updateIndex(field, hole);
    }

    fn promoteYoung(gc: *Gc) void {
        const state = gc.parentState();
        // No old-generation iteration: survivors are partitioned in place.
        inline for (reflection.fieldsOf(types.GcGenerations)) |f| {
            const field = f;
            const strings = comptime std.mem.eql(u8, field, "string_allocations");
            var i = @field(state.gc.old, field);
            while (i < @field(state, field).items.len) : (i += 1) {
                const pointer = if (strings) &@field(state, field).items[i] else @field(state, field).items[i];
                if (pointer.gc.age == .new) {
                    pointer.gc.age = .survivor;
                } else {
                    pointer.gc.age = .old;
                    if (!strings) {
                        const tag = comptime field[0 .. field.len - "_allocations".len];
                        gc.rememberObject(@unionInit(types.GcObject, tag, pointer));
                        pointer.gc.has_young = true; // Revisit once after promotion.
                    }
                    const boundary = &@field(state.gc.old, field);
                    std.mem.swap(@TypeOf(@field(state, field).items[i]), &@field(state, field).items[i], &@field(state, field).items[boundary.*]);
                    gc.updateIndex(field, i);
                    gc.updateIndex(field, boundary.*);
                    boundary.* += 1;
                }
            }
        }
        var i: usize = 0;
        while (i < state.gc.remembered.items.len) {
            const object = state.gc.remembered.items[i];
            const keep = switch (object) {
                inline else => |p| p.gc.has_young,
            };
            if (keep) {
                i += 1;
            } else {
                switch (object) {
                    inline else => |p| p.gc.remembered = false,
                }
                _ = state.gc.remembered.swapRemove(i);
            }
        }
    }

    fn sweepList(gc: *Gc, comptime field: []const u8, budget: usize) bool {
        const state = gc.parentState();
        const strings = comptime std.mem.eql(u8, field, "string_allocations");
        const tables = comptime std.mem.eql(u8, field, "table_allocations");
        var work: usize = 0;
        while (state.gc.sweep_cursor < @field(state, field).items.len and work < budget) : (work += 1) {
            const index = state.gc.sweep_cursor;
            const item = @field(state, field).items[index];
            if (gc.isMarked(if (strings) &item else item)) {
                state.gc.sweep_cursor += 1;
                continue;
            }
            if (strings) {
                if (state.strings.map.get(item.bytes)) |interned| {
                    if (interned.ptr == item.bytes.ptr and interned.len == item.bytes.len) _ = state.strings.map.remove(item.bytes);
                }
                if (item.bytes.len != 0) _ = state.string_allocation_index.remove(@intFromPtr(item.bytes.ptr));
                const retained = if (state.rollback) |journal| journal.keepString(item.bytes) else false;
                gc.noteAllocationFreed(@sizeOf(StringAllocation) + item.bytes.len);
                if (!retained) state.allocator.free(item.bytes);
            } else {
                if (tables) _ = state.table_allocation_index.remove(@intFromPtr(item)) else _ = state.object_allocation_index.remove(@intFromPtr(item));
                if (tables) {
                    gc.noteAllocationFreed(tableGcBytes(item));
                    gc.destroyTable(item);
                } else if (comptime std.mem.eql(u8, field, "thread_allocations")) {
                    gc.noteAllocationFreed(@sizeOf(Thread) + item.gc.storage_bytes);
                    upvalue_mod.closeUpvalues(state, item, 0);
                    gc.destroyThread(item);
                } else if (comptime std.mem.eql(u8, field, "closure_allocations")) {
                    gc.noteAllocationFreed(closureBytes(item));
                    gc.destroyClosure(item);
                } else if (comptime std.mem.eql(u8, field, "userdata_allocations")) {
                    gc.noteAllocationFreed(userdataBytes(item));
                    gc.destroyUserdata(item);
                } else {
                    gc.noteAllocationFreed(@sizeOf(Upvalue));
                    if (!rollback.retainCollected(item)) {
                        if (state.rollback) |journal| journal.freed(@intFromPtr(item));
                        state.allocator.destroy(item);
                    }
                }
            }
            gc.removeRegistryItem(field, index);
        }
        return state.gc.sweep_cursor >= @field(state, field).items.len;
    }

    pub fn findStringAllocation(gc: *Gc, bytes: []const u8) ?usize {
        const state = gc.parentState();
        if (bytes.len == 0) {
            for (state.string_allocations.items, 0..) |allocation, index| {
                if (allocation.bytes.ptr == bytes.ptr and allocation.bytes.len == bytes.len) return index;
            }
            return null;
        }
        return state.string_allocation_index.get(@intFromPtr(bytes.ptr));
    }

    fn isTrackedThread(gc: *Gc, thread: *Thread) bool {
        return gc.trackedIn("thread_allocations", thread);
    }

    pub fn isTrackedTable(gc: *Gc, table: *Table) bool {
        const state = gc.parentState();
        return state.table_allocation_index.contains(@intFromPtr(table));
    }

    fn isTrackedUserdata(gc: *Gc, userdata: *Userdata) bool {
        return gc.trackedIn("userdata_allocations", userdata);
    }

    fn isTrackedClosure(gc: *Gc, closure: *Closure) bool {
        return gc.trackedIn("closure_allocations", closure);
    }

    fn isTrackedUpvalue(gc: *Gc, upvalue: *Upvalue) bool {
        return gc.trackedIn("upvalue_allocations", upvalue);
    }

    fn trackedIn(gc: *Gc, comptime field: []const u8, pointer: anytype) bool {
        const state = gc.parentState();
        const index = state.object_allocation_index.get(@intFromPtr(pointer)) orelse return false;
        const items = @field(state, field).items;
        return index < items.len and items[index] == pointer;
    }

    pub fn destroyTable(gc: *Gc, table: *Table) void {
        const state = gc.parentState();
        rollback.touch(table);
        if (table.metatable != null) {
            gc.unlinkTableMetatable(table);
            state.table_metatable_count -= 1;
        }
        if (rollback.retainCollected(table)) return;
        if (state.rollback) |journal| journal.freed(@intFromPtr(table));
        table.deinit(state.allocator);
        state.allocator.destroy(table);
    }

    pub fn destroyUserdata(gc: *Gc, userdata: *Userdata) void {
        const state = gc.parentState();
        if (rollback.retainCollected(userdata)) return;
        if (state.rollback) |journal| journal.freed(@intFromPtr(userdata));
        if (userdata.payload) |payload| {
            payload.release(state.discarding);
            state.allocator.destroy(userdata);
            return;
        }
        if (!userdata.finalized and !state.discarding) {
            if (userdata.finalizer) |finalizer| finalizer(userdata.ptr, userdata.finalizer_data);
            userdata.finalized = true;
        }
        if (userdata.deinit_fn) |deinit_fn| deinit_fn(state.allocator, userdata.ptr);
        state.allocator.destroy(userdata);
    }

    pub fn destroyClosure(gc: *Gc, closure: *Closure) void {
        const state = gc.parentState();
        if (rollback.retainCollected(closure)) return;
        if (state.rollback) |journal| journal.freed(@intFromPtr(closure));
        if (closure.constants) |constants| state.allocator.free(constants);
        if (closure.upvalues.len != 0) state.allocator.free(closure.upvalues);
        state.allocator.destroy(closure);
    }

    pub fn destroyThread(gc: *Gc, thread: *Thread) void {
        const state = gc.parentState();
        if (rollback.retainCollected(thread)) return;
        if (state.rollback) |journal| journal.freed(@intFromPtr(thread));
        thread.deinit(state.allocator);
        state.allocator.destroy(thread);
    }

    pub fn allocationStats(gc: *const Gc) RuntimeAllocationStats {
        const state = gc.constParentState();
        var bytes: usize = 0;
        for (state.string_allocations.items) |allocation| bytes += @sizeOf(StringAllocation) + allocation.bytes.len;
        for (state.table_allocations.items) |table| {
            bytes += tableGcBytes(table);
        }
        for (state.userdata_allocations.items) |userdata| bytes += userdataBytes(userdata);
        for (state.closure_allocations.items) |closure| bytes += closureBytes(closure);
        bytes += state.upvalue_allocations.items.len * @sizeOf(Upvalue);
        for (state.thread_allocations.items) |thread| bytes += @sizeOf(Thread) + threadCapacityBytes(thread);

        return .{
            .strings = state.string_allocations.items.len,
            .tables = state.table_allocations.items.len,
            .closures = state.closure_allocations.items.len,
            .upvalues = state.upvalue_allocations.items.len,
            .threads = state.thread_allocations.items.len,
            .bytes = bytes,
        };
    }

    pub fn noteTableMetatableChanged(gc: *Gc, table: *Table, old_has_metatable: bool) void {
        const state = gc.parentState();
        rollback.touch(table);
        if (!gc.isTrackedTable(table)) return;
        gc.rememberObject(.{ .table = table });
        if (state.gc.phase != .pause and table.gc.color != .gray) {
            table.gc.epoch = 0;
            gc.forceEnqueue(.{ .table = table });
        }
        if (!table.finalizer_registered) {
            if (table.metatable) |metatable| {
                if (metatable.get(.{ .string = "__gc" }) != .nil) {
                    table.finalizer_registered = true;
                    table.finalizer_order = metatable_mod.nextFinalizerOrder(state);
                    table.finalizer_prev = null;
                    if (state.table_finalizer_head) |head| {
                        rollback.touch(head);
                        head.finalizer_prev = table;
                    }
                    table.finalizer_next = state.table_finalizer_head;
                    state.table_finalizer_head = table;
                }
            }
        }
        const new_has_metatable = table.metatable != null;
        if (old_has_metatable == new_has_metatable) return;
        if (new_has_metatable) {
            table.metatable_prev = null;
            table.metatable_next = state.table_metatable_head;
            if (state.table_metatable_head) |head| {
                rollback.touch(head);
                head.metatable_prev = table;
            }
            state.table_metatable_head = table;
            state.table_metatable_count += 1;
        } else {
            gc.unlinkTableMetatable(table);
            state.table_metatable_count -= 1;
        }
    }

    fn unlinkTableMetatable(gc: *Gc, table: *Table) void {
        const state = gc.parentState();
        rollback.touch(table);
        if (table.metatable_prev) |prev| {
            rollback.touch(prev);
            prev.metatable_next = table.metatable_next;
        } else if (state.table_metatable_head == table) {
            state.table_metatable_head = table.metatable_next;
        }
        if (table.metatable_next) |next| {
            rollback.touch(next);
            next.metatable_prev = table.metatable_prev;
        }
        table.metatable_prev = null;
        table.metatable_next = null;
    }

    pub fn setMode(gc: *Gc, mode: GcMode) GcMode {
        const state = gc.parentState();
        const previous = state.gc.mode;
        if (mode == previous) return previous;
        state.gc.mode = mode;
        if (!state.gc.collecting) gc.normalizeBaseline();
        return previous;
    }

    pub fn runSteps(gc: *Gc, steps: usize) !bool {
        const state = gc.parentState();
        return gc.stepCount(state.current_thread, steps);
    }

    pub fn upvalueBarrier(gc: *Gc, closure: *Closure, upvalue: *Upvalue) void {
        const state = gc.parentState();
        gc.rememberObject(.{ .closure = closure });
        if (state.gc.phase != .pause) gc.markUpvalue(upvalue);
    }

    pub fn threadBarrier(gc: *Gc, thread: *Thread, value: Value) void {
        gc.syncThreadStorage(thread);
        gc.rememberObject(.{ .thread = thread });
        gc.markValue(value);
    }

    /// Runs pending finalizers as `deinit` does, keeping the state. Only for an idle host;
    /// later registrations are left for `deinit`.
    pub fn runCloseFinalizers(gc: *Gc) void {
        const state = gc.parentState();
        if (state.execution_depth != 0 or state.current_thread != null) return;
        if (state.table_pending_finalizer_head == null and state.table_finalizer_head == null and !gc.hasUserdataLuaFinalizers() and !stdlib.io.hasOpenFiles(state)) return;
        var proto = proto_mod.Proto.init(state.allocator);
        defer proto.deinit();
        proto.source_name = "=[C]";
        var closure = Closure{ .proto = &proto, .upvalues = &.{} };
        const thread = entry_mod.newHostThread(state, &closure) catch return;
        defer entry_mod.retireHostThread(state, thread);
        state.current_thread = thread;
        defer state.current_thread = null;
        gc.runCloseFinalizersOnThread(thread);
    }

    fn runFinalizersFromHost(gc: *Gc, limit: usize) anyerror!bool {
        const state = gc.parentState();
        var proto = proto_mod.Proto.init(state.allocator);
        defer proto.deinit();
        proto.source_name = "=[C]";
        var closure = Closure{ .proto = &proto, .upvalues = &.{} };
        const thread = try entry_mod.newHostThread(state, &closure);
        defer entry_mod.retireHostThread(state, thread);
        const previous_thread = state.current_thread;
        state.current_thread = thread;
        defer state.current_thread = previous_thread;
        return gc.runFinalizerBatch(thread, limit);
    }
};

const managed_lists = .{ "table_allocations", "userdata_allocations", "closure_allocations", "upvalue_allocations", "thread_allocations" };

pub fn tableCapacityBytes(table: *const Table) usize {
    return table.array.capacity * @sizeOf(Value) + table.entries.capacity * @sizeOf(TableEntry) + @as(usize, table.entry_index.capacity()) * (@sizeOf(Value) + @sizeOf(usize) + 1);
}

pub fn tableGcBytes(table: *const Table) usize {
    return @sizeOf(Table) + tableCapacityBytes(table);
}

/// Managed backing capacity; excludes allocator overhead and rollback copies.
fn threadCapacityBytes(thread: *const Thread) usize {
    return threadListBytes(thread) + thread.frame_storage_bytes;
}

fn frameStorageBytes(thread: *const Thread) usize {
    var bytes: usize = 0;
    for (thread.frames.items) |frame| bytes += frame.storageBytes();
    return bytes;
}

fn threadListBytes(thread: *const Thread) usize {
    var bytes: usize = 0;
    inline for (.{ "stack", "frames", "yield_values", "protected_continuations", "generic_for_continuations", "pairs_continuations", "tail_call_continuations", "call_one_continuations" }) |name| {
        const list = @field(thread, name);
        const T = @typeInfo(@TypeOf(list.items)).pointer.child;
        bytes += list.capacity * @sizeOf(T);
    }
    return bytes;
}

pub fn userdataBytes(userdata: *const Userdata) usize {
    return @sizeOf(Userdata) + if (userdata.payload) |payload| @sizeOf(types.UserdataPayload) + payload.managed_bytes else @as(usize, 0);
}

fn closureBytes(closure: *const Closure) usize {
    return @sizeOf(Closure) + closure.upvalues.len * @sizeOf(*Upvalue) + if (closure.constants) |c| c.len * @sizeOf(?Value) else @as(usize, 0);
}

// Lua's floating-byte parameter encoding, decoded back to a percentage.
fn roundedLuaParam(value: u32) i64 {
    if (value >= 396800) return 396800;
    const scaled = (@as(u64, value) * 128 + 99) / 100;
    const shift: u6 = if (scaled < 16) 0 else @intCast(63 - @clz(scaled) - 4);
    return @intCast(((scaled >> shift) << shift) * 100 / 128);
}

/// Includes a running native's arguments, which can extend past the CALL operands.
fn innermostLiveEnd(thread: *const Thread, frame: types.CallFrame) usize {
    const end = callerLiveEnd(frame);
    const call = thread.native_call orelse return end;
    if (call.frame_count != thread.frames.items.len) return end;
    return @max(end, frame.base + call.base + 1 + call.arg_count);
}

fn callerLiveEnd(frame: types.CallFrame) usize {
    const whole = frame.base + frame.proto.max_registers;
    if (frame.pc == 0 or frame.pc > frame.proto.instructions.items.len) return whole;
    const op = switch (frame.proto.instructions.items[frame.pc - 1]) {
        .call, .tail_call => |op| op,
        else => return whole,
    };
    const args: usize = if (op.arg_count == bytecode.multret_arg_count) 0 else op.arg_count;
    return frame.base + op.base + 1 + args;
}

const CloseFinalizer = struct {
    object: union(enum) { table: *Table, userdata: *Userdata, file: *Userdata },
    order: u64,

    fn newer(_: void, a: CloseFinalizer, b: CloseFinalizer) bool {
        if (a.order != b.order) return a.order > b.order;
        return a.object != .file and b.object == .file;
    }
};
