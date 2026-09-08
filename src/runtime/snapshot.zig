//! In-memory graph copying. No collector or Lua code runs here. Destination
//! shells are registered before references are populated, preserving identity.
const std = @import("std");
const types = @import("types.zig");
const State = @import("state.zig").State;
const Proto = @import("../compile/proto.zig").Proto;
const static_strings = @import("../stdlib/static_strings.zig");

pub fn checkIdleFast(source: *const State) !void {
    if (source.execution_depth != 0 or source.userdata_scope != null or source.current_thread != null or source.active_api_callback != null or source.is_collecting or source.snapshot_busy) return error.SnapshotBusy;
}

pub fn checkIdle(source: *const State) !void {
    try checkIdleFast(source);
    for (source.thread_allocations.items) |thread| {
        if (thread.status == .running or thread.status == .normal or thread.hook_running or thread.hook_transfer_values.len != 0) return error.SnapshotBusy;
    }
}

/// `error_root` is the only host API root retained. All application handles must
/// be reacquired. The caller owns destination allocator infrastructure.
pub fn copy(source: *State, allocator: std.mem.Allocator, lifetime: ?*types.AllocatorLifetime, error_root: ?usize) !State {
    try checkIdle(source);
    source.snapshot_busy = true;
    defer source.snapshot_busy = false;
    return copyGraph(source, allocator, lifetime, error_root, false);
}

/// The source must be an idle, immutable backing image retained until destination
/// destruction. Concurrent readers never write source VM metadata.
pub fn copyFrozen(source: *const State, allocator: std.mem.Allocator, lifetime: ?*types.AllocatorLifetime, error_root: ?usize) !State {
    return copyGraph(source, allocator, lifetime, error_root, true);
}

fn copyGraph(source: *const State, allocator: std.mem.Allocator, lifetime: ?*types.AllocatorLifetime, error_root: ?usize, borrow_protos: bool) !State {
    var destination = State{
        .allocator = allocator,
        .allocator_lifetime = lifetime,
        .strings = std.StringHashMap([]const u8).init(allocator),
        .string_allocation_index = types.PointerAllocationIndex.init(allocator),
        .table_allocation_index = types.PointerAllocationIndex.init(allocator),
        .options = source.options,
    };
    errdefer destination.discard();
    var copier = Copier{ .destination = &destination, .borrow_protos = borrow_protos, .map = std.AutoHashMap(usize, usize).init(allocator) };
    defer copier.map.deinit();
    try copier.populate(source, error_root);
    return destination;
}

const Copier = struct {
    destination: *State,
    borrow_protos: bool = false,
    map: std.AutoHashMap(usize, usize),

    fn mapped(self: *Copier, pointer: anytype) !@TypeOf(pointer) {
        return @ptrFromInt(self.map.get(@intFromPtr(pointer)) orelse return error.SnapshotUnsupported);
    }

    fn shells(self: *Copier, comptime T: type, source: []const *T, destination: *std.ArrayList(*T), initial: T) !void {
        const a = self.destination.allocator;
        try destination.ensureTotalCapacity(a, source.len);
        for (source) |old| {
            const new = try a.create(T);
            new.* = initial;
            destination.appendAssumeCapacity(new);
            try self.map.put(@intFromPtr(old), @intFromPtr(new));
        }
    }

    // Metadata strings are owned by source_allocations, independently of GC.
    fn text(self: *Copier, bytes: []const u8) ![]const u8 {
        if (bytes.len == 0) return "";
        if (self.map.get(@intFromPtr(bytes.ptr))) |address| return @as([*]const u8, @ptrFromInt(address))[0..bytes.len];
        const a = self.destination.allocator;
        const result = try a.dupe(u8, bytes);
        self.destination.source_allocations.append(a, result) catch |err| {
            a.free(result);
            return err;
        };
        try self.map.put(@intFromPtr(bytes.ptr), @intFromPtr(result.ptr));
        return result;
    }

    fn value(self: *Copier, old: types.Value) !types.Value {
        switch (old) {
            .string => |bytes| {
                if (bytes.len == 0) return .{ .string = "" };
                if (self.map.get(@intFromPtr(bytes.ptr))) |address| return .{ .string = @as([*]const u8, @ptrFromInt(address))[0..bytes.len] };
                return .{ .string = try self.destination.intern(bytes) };
            },
            inline .table, .closure, .userdata, .thread, .coroutine_wrapper, .gmatch_iterator => |pointer, tag| {
                const address = self.map.get(@intFromPtr(pointer)) orelse return error.SnapshotUnsupported;
                return @unionInit(types.Value, @tagName(tag), @as(@TypeOf(pointer), @ptrFromInt(address)));
            },
            else => return old,
        }
    }

    /// Used only on POD metadata, VM references and diagnostics. Owning slices
    /// and containers have explicit handlers below; unknown pointers fail build.
    fn remap(self: *Copier, old: anytype) anyerror!@TypeOf(old) {
        const T = @TypeOf(old);
        if (T == types.Value) return self.value(old);
        if (T == types.TableEntry) return .{
            .key = if (old.value == .nil) try self.storedValue(old.key) else try self.value(old.key),
            .value = try self.value(old.value),
        };
        if (T == []const u8) return self.text(old);
        return switch (@typeInfo(T)) {
            .optional => if (old) |v| try self.remap(v) else null,
            .pointer => |p| if (p.size == .one and (p.child == types.Table or p.child == types.Userdata or p.child == types.Closure or p.child == types.Upvalue or p.child == types.Thread or p.child == Proto)) try self.mapped(old) else @compileError("unclassified snapshot pointer: " ++ @typeName(T)),
            .@"struct" => blk: {
                var result: T = undefined;
                inline for (@typeInfo(T).@"struct".fields) |f| @field(result, f.name) = try self.remap(@field(old, f.name));
                break :blk result;
            },
            .@"union" => switch (old) {
                inline else => |v, tag| @unionInit(T, @tagName(tag), try self.remap(v)),
            },
            else => old,
        };
    }

    fn list(self: *Copier, comptime T: type, old: []const T) !std.ArrayList(T) {
        var result: std.ArrayList(T) = .empty;
        errdefer result.deinit(self.destination.allocator);
        try result.ensureTotalCapacity(self.destination.allocator, old.len);
        for (old) |v| result.appendAssumeCapacity(try self.remap(v));
        return result;
    }

    fn values(self: *Copier, comptime T: type, old: []const T) ![]T {
        const a = self.destination.allocator;
        const result = try a.alloc(T, old.len);
        errdefer a.free(result);
        for (old, result) |v, *out| out.* = try self.remap(v);
        return result;
    }

    fn borrowedProto(self: *Copier, old: *Proto) anyerror!void {
        try self.map.put(@intFromPtr(old), @intFromPtr(old));
        for (old.children.items) |child| try self.borrowedProto(child);
    }

    fn proto(self: *Copier, old: *const Proto) anyerror!*Proto {
        const a = self.destination.allocator;
        const new = try a.create(Proto);
        new.* = Proto.init(a);
        errdefer {
            new.deinit();
            a.destroy(new);
        }
        try self.map.put(@intFromPtr(old), @intFromPtr(new));
        inline for (.{ "max_registers", "param_count", "is_vararg", "named_vararg", "defined_line", "last_defined_line", "has_to_close_locals" }) |name| @field(new, name) = @field(old, name);
        new.source_name = try self.text(old.source_name);
        new.debug_name = try self.remap(old.debug_name);
        new.instructions = try self.list(@import("../compile/bytecode.zig").Instruction, old.instructions.items);
        new.constants = try self.list(@import("../compile/bytecode.zig").Constant, old.constants.items);
        new.line_info = try self.list(@import("../compile/proto.zig").LineInfo, old.line_info.items);
        for (old.locals.items) |v| _ = try new.addLocal(v);
        for (old.upvalues.items) |v| _ = try new.addUpvalue(v);
        for (old.error_sites.items) |v| try new.addErrorSite(v.pc, v.site);
        try new.children.ensureTotalCapacity(a, old.children.items.len);
        for (old.children.items) |child| new.children.appendAssumeCapacity(try self.proto(child));
        return new;
    }

    fn populate(self: *Copier, source: *const State, error_root: ?usize) !void {
        const d = self.destination;
        const a = d.allocator;
        try self.map.ensureTotalCapacity(@intCast(source.table_allocations.items.len + source.closure_allocations.items.len + source.upvalue_allocations.items.len + source.thread_allocations.items.len + source.string_allocations.items.len + 256));
        for (static_strings.names) |bytes| if (bytes.len != 0) {
            try self.map.put(@intFromPtr(bytes.ptr), @intFromPtr(bytes.ptr));
        };
        for (source.string_allocations.items) |allocation| {
            const bytes = try d.allocateString(allocation.bytes);
            if (bytes.len != 0) try self.map.put(@intFromPtr(allocation.bytes.ptr), @intFromPtr(bytes.ptr));
        }
        var strings = source.strings.iterator();
        while (strings.next()) |entry| {
            const v = try self.value(.{ .string = entry.value_ptr.* });
            try d.strings.put(v.string, v.string);
        }
        for (source.source_allocations.items) |bytes| _ = try self.text(bytes);
        try d.proto_allocations.ensureTotalCapacity(a, source.proto_allocations.items.len);
        for (source.proto_allocations.items) |old| {
            if (self.borrow_protos) {
                try self.borrowedProto(old);
                d.proto_allocations.appendAssumeCapacity(old);
                d.borrowed_proto_count += 1;
            } else d.proto_allocations.appendAssumeCapacity(try self.proto(old));
        }
        try self.shells(types.Table, source.table_allocations.items, &d.table_allocations, .{ .entry_index = types.TableEntryIndex.init(a) });
        try self.shells(types.Thread, source.thread_allocations.items, &d.thread_allocations, .{});
        try self.shells(types.Closure, source.closure_allocations.items, &d.closure_allocations, .{ .proto = undefined, .upvalues = &.{} });
        try self.shells(types.Upvalue, source.upvalue_allocations.items, &d.upvalue_allocations, .{ .owner = undefined, .stack_index = 0 });
        try self.shells(types.Userdata, source.userdata_allocations.items, &d.userdata_allocations, .{ .ptr = undefined, .type_id = 0, .type_name = "", .finalized = true });
        for (source.table_allocations.items, d.table_allocations.items, 0..) |old, new, index| {
            new.array = try self.list(types.Value, old.array.items);
            // Tombstone keys can refer to objects already swept. Preserve valid
            // keys for next(), but never dereference missing heap identities.
            new.entries = try self.list(types.TableEntry, old.entries.items);
            var retained: usize = 0;
            for (new.entries.items) |entry| {
                if (entry.key == .nil) continue;
                new.entries.items[retained] = entry;
                retained += 1;
            }
            new.entries.items.len = retained;
            try new.rebuildEntryIndex();
            inline for (.{ "metatable", "metatable_prev", "metatable_next", "counts_for_gc_count", "finalizer_registered", "finalizer_next", "finalizer_prev", "finalizer_order" }) |name| @field(new, name) = try self.remap(@field(old, name));
            try d.table_allocation_index.put(@intFromPtr(new), index);
        }
        for (source.closure_allocations.items, d.closure_allocations.items) |old, new| {
            new.proto = try self.mapped(old.proto);
            new.upvalues = try self.values(*types.Upvalue, old.upvalues);
            if (old.constants) |v| new.constants = try self.values(?types.Value, v);
            new.stripped_debug = old.stripped_debug;
        }
        for (source.upvalue_allocations.items, d.upvalue_allocations.items) |old, new| {
            new.stack_index = old.stack_index;
            new.is_open = old.is_open;
            if (old.is_open) {
                new.owner = try self.mapped(old.owner);
                new.next = try self.remap(old.next);
            } else new.closed = try self.value(old.closed);
        }
        for (source.thread_allocations.items, d.thread_allocations.items) |old, new| try self.thread(old, new);
        for (source.userdata_allocations.items, d.userdata_allocations.items) |old, new| try self.userdata(old, new);
        inline for (.{ "global_table", "table_metatable_head", "table_finalizer_head", "table_pending_finalizer_head", "userdata_pending_finalizer_head", "table_metatable_count", "table_finalizer_serial", "stdin_pos", "last_error", "last_error_in_close", "traceback_error_in_close", "string_metatable", "number_metatable", "boolean_metatable", "nil_metatable", "file_metatable", "zerde_null", "zerde_array_metatable", "zerde_object_metatable", "gc_running", "gc_mode", "gc_params", "random_state", "instruction_count" }) |name| @field(d, name) = try self.remap(@field(source, name));
        d.stdout = try self.list(u8, source.stdout.items);
        d.stderr = try self.list(u8, source.stderr.items);
        d.options.stdin = try self.text(source.options.stdin);
        inline for (.{ "userdata_allocations", "closure_allocations", "upvalue_allocations", "thread_allocations" }) |field| {
            for (@field(d, field).items, 0..) |object, index| try d.object_allocation_index.put(a, @intFromPtr(object), index);
        }
        try @import("gc.zig").reserveQueues(State, d, 0);
        if (error_root) |index| _ = try d.rootValue(try self.value(source.rootedValue(index)));
        _ = d.refreshAllocationTotal();
        d.normalizeGcBaseline();
    }

    fn storedValue(self: *Copier, v: types.Value) !types.Value {
        // Inspect identities, never memory behind untracked stale pointers.
        switch (v) {
            .string => |bytes| if (bytes.len != 0 and !self.map.contains(@intFromPtr(bytes.ptr))) {
                return .nil;
            },
            inline .table, .closure, .userdata, .thread, .coroutine_wrapper, .gmatch_iterator => |p| if (!self.map.contains(@intFromPtr(p))) {
                return .nil;
            },
            else => {},
        }
        return self.value(v);
    }

    fn liveSlot(target: *const types.Thread, index: usize) bool {
        inline for (.{ "last_result", "last_transfer", "yield_result" }) |prefix| {
            const base = @field(target, prefix ++ "_base");
            if (index >= base and index - base < @field(target, prefix ++ "_count")) return true;
        }
        for (target.frames.items) |frame| {
            for (frame.proto.locals.items) |local| {
                if (index == frame.base + local.register and @import("value.zig").localActiveAt(local, frame.pc)) return true;
            }
        }
        var open = target.open_upvalues;
        while (open) |upvalue| : (open = upvalue.next) {
            if (upvalue.stack_index == index) return true;
        }
        return false;
    }

    fn thread(self: *Copier, old: *const types.Thread, new: *types.Thread) !void {
        const a = self.destination.allocator;
        // Unused stack storage may contain dangling references after collection.
        // Only read scalar tags and pointer identities before consulting the map.
        try new.stack.resize(a, old.stack.items.len);
        for (old.stack.items, new.stack.items, 0..) |v, *out, index| {
            // Native diagnostic strings may be process-lifetime literals rather
            // than interned allocations. Copy those only from live registers.
            out.* = if (v == .string and liveSlot(old, index)) try self.value(v) else try self.storedValue(v);
        }
        try new.frames.ensureTotalCapacity(a, old.frames.items.len);
        for (old.frames.items) |f| {
            new.frames.appendAssumeCapacity(.{ .closure = try self.mapped(f.closure), .proto = try self.mapped(f.proto), .base = f.base, .pc = f.pc, .return_start = f.return_start, .return_count = f.return_count, .varargs = &.{} });
            const frame = &new.frames.items[new.frames.items.len - 1];
            frame.varargs = try self.values(types.Value, f.varargs);
            frame.owns_varargs = true;
            if (f.pending_returns) |v| frame.pending_returns = try self.values(types.Value, v);
            inline for (.{ "vararg_table_local", "last_hook_line", "debug_name_override", "debug_namewhat_override", "is_tail_call" }) |name| @field(frame, name) = try self.remap(@field(f, name));
        }
        inline for (.{ "yield_values", "protected_continuations", "generic_for_continuations", "pairs_continuations", "tail_call_continuations", "call_one_continuations" }) |name| {
            const items = @field(old, name).items;
            @field(new, name) = try self.list(std.meta.Elem(@TypeOf(items)), items);
        }
        inline for (.{ "open_upvalues", "hook", "hook_call", "hook_line", "hook_return", "hook_count", "hook_count_remaining", "pending_yield_hook_return", "continuation_order", "last_result_base", "last_result_count", "last_transfer_base", "last_transfer_count", "yield_result_base", "yield_result_count", "close_error_value", "error_traceback", "pending_unwind_error", "pending_unwind_resume_frame_count", "pending_unwind_target_frame_count", "entry", "started", "is_main", "closing", "status", "exposed" }) |name| @field(new, name) = try self.remap(@field(old, name));
        // Hook transfer/name pointers and native call depths belong to host call
        // scopes, not suspended bytecode. They must not retain obsolete storage.
    }

    fn userdata(self: *Copier, old: *const types.Userdata, new: *types.Userdata) !void {
        const p = old.payload orelse return error.SnapshotUnsupported;
        new.type_id = old.type_id;
        new.type_name = try self.text(old.type_name);
        new.metatable = try self.remap(old.metatable);
        new.finalizer_next = try self.remap(old.finalizer_next);
        new.finalization_pending = old.finalization_pending;
        new.finalized = old.finalized;
        new.finalizer = old.finalizer;
        new.finalizer_data = old.finalizer_data;
        if (p.snapshot_copy) |f| {
            const a = self.destination.allocator;
            const payload = try a.create(types.UserdataPayload);
            errdefer a.destroy(payload);
            const ptr = try f(a, p.ptr);
            payload.* = .{
                .allocator = a,
                .lifetime = self.destination.allocator_lifetime,
                .ptr = ptr,
                .finalizer = p.finalizer,
                .finalizer_data = p.finalizer_data,
                .dispose = p.snapshot_dispose,
                .finalized = p.finalized,
                .managed_bytes = p.managed_bytes,
                .snapshot_copy = p.snapshot_copy,
                .snapshot_dispose = p.snapshot_dispose,
                .snapshot_tracking = p.snapshot_tracking,
                .is_snapshot_copy = true,
            };
            if (payload.lifetime) |l| l.retain();
            new.payload = payload;
            new.ptr = ptr;
        } else {
            p.retain();
            new.payload = p;
            new.ptr = p.ptr;
        }
    }
};

// Explicit ownership review: adding/removing/renaming a field fails compilation
// until its copy policy and implementation have been reviewed together.
const Policy = struct {
    copied: []const u8 = "",
    remapped: []const u8 = "",
    rebuilt: []const u8 = "",
    external: []const u8 = "",
    transient: []const u8 = "",
    unsupported: []const u8 = "",
};
pub fn review(comptime T: type, comptime policy: Policy) void {
    comptime {
        var count: usize = 0;
        for (std.meta.fields(Policy)) |category| {
            var names = std.mem.tokenizeScalar(u8, @field(policy, category.name), ' ');
            while (names.next()) |name| {
                if (!@hasField(T, name)) @compileError("obsolete snapshot policy: " ++ @typeName(T) ++ "." ++ name);
                count += 1;
            }
        }
        if (count != std.meta.fields(T).len) @compileError("review snapshot fields for " ++ @typeName(T));
        for (std.meta.fields(T)) |field| {
            var matches: usize = 0;
            for (std.meta.fields(Policy)) |category| {
                var names = std.mem.tokenizeScalar(u8, @field(policy, category.name), ' ');
                while (names.next()) |name| {
                    if (std.mem.eql(u8, field.name, name)) matches += 1;
                }
            }
            if (matches != 1) @compileError("missing/duplicate snapshot policy: " ++ @typeName(T) ++ "." ++ field.name);
        }
    }
}
comptime {
    @setEvalBranchQuota(1000000);
    review(State, .{
        .external = "allocator allocator_lifetime options",
        .rebuilt = "borrowed_proto_count strings string_allocation_index table_allocation_index object_allocation_index gc_next_total gc_known_total api_roots",
        .remapped = "global_table table_metatable_head table_finalizer_head table_pending_finalizer_head userdata_pending_finalizer_head string_metatable number_metatable boolean_metatable nil_metatable file_metatable zerde_null zerde_array_metatable zerde_object_metatable last_error",
        .copied = "string_allocations table_allocations userdata_allocations closure_allocations upvalue_allocations thread_allocations proto_allocations source_allocations stdout stderr table_metatable_count table_finalizer_serial stdin_pos last_error_in_close traceback_error_in_close gc_running gc_mode gc_params random_state instruction_count",
        .transient = "execution_depth userdata_scope rollback snapshot_busy discarding current_thread api_callback_dispatch api_callback_user_data active_api_callback coroutine_close_depth gc_epoch gc_generation gc_phase gc_cycle gc_work gc_remembered gc_weak gc_tables gc_finalizers gc_major_pending gc_cycle_start_total gc_found_young gc_old gc_sweep_cursor gc_major_base gc_work_done gc_minor_count is_collecting collect_after_instruction step_after_instruction mark_all_stack_registers conservative_gc_depth",
    });
    review(types.Thread, .{
        .copied = "exposed stack frames yield_values protected_continuations generic_for_continuations pairs_continuations tail_call_continuations call_one_continuations hook_call hook_line hook_return hook_count hook_count_remaining pending_yield_hook_return continuation_order last_result_base last_result_count last_transfer_base last_transfer_count yield_result_base yield_result_count pending_unwind_resume_frame_count pending_unwind_target_frame_count started is_main closing status",
        .remapped = "open_upvalues hook close_error_value error_traceback pending_unwind_error entry",
        .transient = "rollback marked gc hook_running hook_return_name hook_level2_func hook_transfer_index_base hook_transfer_stack_base hook_transfer_count hook_transfer_values next_call_name next_call_namewhat native_call_depth traceback_native_name protected_close_depth resume_parent",
    });
    review(types.CallFrame, .{
        .copied = "base pc return_start return_count varargs last_hook_line debug_name_override debug_namewhat_override is_tail_call pending_returns",
        .remapped = "closure proto vararg_table_local",
        .rebuilt = "owns_varargs",
    });
    review(types.Table, .{
        .copied = "array entries counts_for_gc_count finalizer_registered finalizer_order",
        .remapped = "metatable metatable_prev metatable_next finalizer_next finalizer_prev",
        .rebuilt = "entry_index",
        .transient = "rollback marked gc",
    });
    review(types.Closure, .{
        .remapped = "proto upvalues constants",
        .copied = "stripped_debug",
        .transient = "rollback marked gc",
    });
    review(types.Upvalue, .{
        .remapped = "owner closed next",
        .copied = "stack_index is_open",
        .transient = "rollback marked gc",
    });
    review(types.Userdata, .{
        .external = "ptr type_id finalizer finalizer_data deinit_fn",
        .copied = "type_name finalized finalization_pending",
        .remapped = "metatable payload finalizer_next",
        .transient = "scope_readers scope_writers rollback marked gc",
    });
    review(Proto, .{
        .rebuilt = "allocator arena",
        .copied = "constants instructions line_info locals upvalues error_sites max_registers param_count is_vararg named_vararg source_name debug_name defined_line last_defined_line has_to_close_locals",
        .remapped = "children",
    });
    review(types.Value, .{ .remapped = "string table userdata closure thread coroutine_wrapper gmatch_iterator", .external = "nil boolean integer number native_print native_tostring native_getmetatable native_setmetatable native_rawequal native_rawget native_rawset native_rawlen native_next native_pairs native_ipairs native_ipairs_iter native_table_create native_select native_assert native_error native_pcall native_xpcall native_collectgarbage native_debug_traceback native_coroutine_create native_coroutine_resume native_coroutine_yield native_coroutine_status native_coroutine_running native_coroutine_isyieldable native_coroutine_close native_coroutine_wrap native api_callback" });
    review(types.StringAllocation, .{
        .copied = "bytes",
        .transient = "marked gc",
    });
    review(types.UserdataPayload, .{
        .external = "allocator lifetime ptr finalizer finalizer_data dispose snapshot_copy snapshot_dispose",
        .rebuilt = "references is_snapshot_copy",
        .copied = "finalized snapshot_tracking managed_bytes",
    });
}
