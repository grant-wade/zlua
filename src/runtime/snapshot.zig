//! In-memory graph copying. No collector or Lua code runs here. Destination
//! shells are registered before references are populated, preserving identity.

const std = @import("std");
const Proto = @import("../compile/proto.zig").Proto;
const reflection = @import("../reflection.zig");
const static_strings = @import("../stdlib/static_strings.zig");
const budget_mod = @import("budget.zig");
const gc_mod = @import("gc.zig");
const State = @import("state.zig").State;
const types = @import("types.zig");

const AddressMap = std.HashMap(usize, usize, types.AddressContext, std.hash_map.default_max_load_percentage);

pub fn checkIdleFast(source: *const State) !void {
    if (source.execution_depth != 0 or source.userdata_scope != null or source.current_thread != null or source.active_api_callback != null or source.gc.collecting or source.snapshot_busy) return error.SnapshotBusy;
}

pub fn checkIdle(source: *const State) !void {
    try checkIdleFast(source);
    for (source.thread_allocations.items) |thread| {
        if (thread.status == .running or thread.status == .normal or thread.hook_running or thread.hook_transfer_values.len != 0) return error.SnapshotBusy;
    }
}

/// Only `error_root` survives among host API roots; application handles must be reacquired.
pub fn copy(source: *State, allocator: std.mem.Allocator, lifetime: ?*types.AllocatorLifetime, error_root: ?usize) !State {
    try checkIdle(source);
    source.snapshot_busy = true;
    defer source.snapshot_busy = false;
    return copyGraph(source, allocator, lifetime, error_root, false);
}

/// The source must be an idle, immutable image that outlives the destination.
pub fn copyFrozen(source: *const State, allocator: std.mem.Allocator, lifetime: ?*types.AllocatorLifetime, error_root: ?usize) !State {
    return copyGraph(source, allocator, lifetime, error_root, true);
}

fn copyGraph(source: *const State, allocator: std.mem.Allocator, lifetime: ?*types.AllocatorLifetime, error_root: ?usize, borrow_protos: bool) !State {
    var destination = State{
        .allocator = allocator,
        .allocator_lifetime = lifetime,
        .options = source.options,
    };
    errdefer destination.discard();
    destination.strings.set = try @import("strings.zig").InternSet.initStatic(allocator, source.strings.set.count);
    var copier = Copier{ .destination = &destination, .borrow_protos = borrow_protos, .map = AddressMap.init(allocator) };
    defer copier.map.deinit();
    try copier.populate(source, error_root);
    return destination;
}

const Copier = struct {
    destination: *State,
    borrow_protos: bool = false,
    map: AddressMap,

    fn mapped(self: *Copier, pointer: anytype) !@TypeOf(pointer) {
        return @ptrFromInt(self.map.get(@intFromPtr(pointer)) orelse return error.SnapshotUnsupported);
    }

    fn shells(self: *Copier, comptime T: type, source: []const *T, destination: *std.ArrayList(*T), initial: T) !void {
        const a = self.destination.allocator;
        try destination.ensureTotalCapacity(a, source.len);
        for (source) |old| {
            const new = if (T == types.Closure) try types.Closure.create(a, old.upvalue_count, initial) else try a.create(T);
            if (T != types.Closure) new.* = initial;
            new.gc.registry_index = @intCast(destination.items.len);
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
            .string => |string| {
                if (string.static) return old;
                if (self.map.get(@intFromPtr(string))) |address| return .{ .string = @ptrFromInt(address) };
                return .{ .string = try self.destination.strings.intern(string.bytes()) };
            },
            inline .table, .closure, .userdata, .thread, .coroutine_wrapper, .gmatch_iterator => |pointer, tag| {
                const address = self.map.get(@intFromPtr(pointer)) orelse return error.SnapshotUnsupported;
                return @unionInit(types.Value, @tagName(tag), @as(@TypeOf(pointer), @ptrFromInt(address)));
            },
            else => return old,
        }
    }

    /// For POD metadata, VM references and diagnostics only; unknown pointers fail to compile.
    fn remap(self: *Copier, old: anytype) anyerror!@TypeOf(old) {
        const T = @TypeOf(old);
        if (T == types.Value) return self.value(old);
        if (T == types.TableEntry) return .{
            .key = if (old.value == .nil) try self.storedValue(old.key) else try self.value(old.key),
            .value = try self.value(old.value),
        };
        if (T == []const u8) return self.text(old);
        if (T == *const types.String) return (try self.value(.{ .string = old })).string;
        return switch (@typeInfo(T)) {
            .optional => if (old) |v| try self.remap(v) else null,
            .pointer => |p| if (p.size == .one and (p.child == types.Table or p.child == types.Userdata or p.child == types.Closure or p.child == types.Upvalue or p.child == types.Thread or p.child == Proto)) try self.mapped(old) else @compileError("unclassified snapshot pointer: " ++ @typeName(T)),
            .@"struct" => blk: {
                var result: T = undefined;
                inline for (reflection.fieldsOf(T)) |f| @field(result, f) = try self.remap(@field(old, f));
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
        inline for (.{ "max_registers", "param_count", "is_vararg", "named_vararg", "defined_line", "last_defined_line", "has_to_close_locals", "runtime_prepared", "named_vararg_readonly", "fast_loop_entry", "fast_loop_call" }) |name| @field(new, name) = @field(old, name);
        new.constant_values = try new.arena.allocator().dupe(types.Value, old.constant_values);
        new.constant_hashes = try new.arena.allocator().dupe(u32, old.constant_hashes);
        new.close_exit_jumps = try new.arena.allocator().dupe(u64, old.close_exit_jumps);
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
        try d.string_allocations.ensureTotalCapacity(a, source.string_allocations.items.len);
        for (source.string_allocations.items) |string| {
            const duplicate = try d.strings.duplicate(string);
            try self.map.put(@intFromPtr(string), @intFromPtr(duplicate));
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
        try self.shells(types.Table, source.table_allocations.items, &d.table_allocations, .{});
        try self.shells(types.Thread, source.thread_allocations.items, &d.thread_allocations, .{});
        try self.shells(types.Closure, source.closure_allocations.items, &d.closure_allocations, .{ .proto = undefined });
        try self.shells(types.Upvalue, source.upvalue_allocations.items, &d.upvalue_allocations, .{ .owner = undefined, .stack_index = 0 });
        try self.shells(types.Userdata, source.userdata_allocations.items, &d.userdata_allocations, .{ .ptr = undefined, .type_id = 0, .type_name = "", .finalized = true });
        for (source.table_allocations.items, d.table_allocations.items) |old, new| {
            new.array = try self.list(types.Value, old.array.items);
            // Tombstone keys may reference swept objects; keep valid ones for next() without dereferencing.
            new.entries = try self.list(types.TableEntry, old.entries.items);
            var retained: usize = 0;
            for (new.entries.items) |entry| {
                if (entry.key == .nil) continue;
                new.entries.items[retained] = entry;
                retained += 1;
            }
            new.entries.items.len = retained;
            try new.rebuildEntryIndex(a);
            inline for (.{ "metatable", "metatable_prev", "metatable_next", "finalizer_registered", "finalizer_next", "finalizer_prev", "finalizer_order" }) |name| @field(new, name) = try self.remap(@field(old, name));
        }
        for (source.closure_allocations.items, d.closure_allocations.items) |old, new| {
            new.proto = try self.mapped(old.proto);
            new.root = if (old.root) |root| try self.mapped(root) else null;
            for (old.upvalues(), new.upvalues()) |upvalue, *slot| slot.* = try self.mapped(upvalue);
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
        inline for (.{ "global_table", "table_metatable_head", "table_finalizer_head", "table_pending_finalizer_head", "userdata_pending_finalizer_head", "userdata_lua_pending_head", "table_metatable_count", "table_finalizer_serial", "stdin_pos", "file_generation", "last_error", "error_handled", "warnings_on", "string_metatable", "number_metatable", "boolean_metatable", "nil_metatable", "file_metatable", "fs_file_metatable", "io_input", "io_output", "random_state" }) |name| @field(d, name) = try self.remap(@field(source, name));
        inline for (.{ "running", "mode", "params" }) |name| @field(d.gc, name) = @field(source.gc, name);
        inline for (.{ "instructions", "base" }) |name| @field(d.budget, name) = @field(source.budget, name);
        for (&d.library_tables.values, source.library_tables.values) |*slot, table| slot.* = try self.remap(table);
        d.file_generation +%= 1;
        d.stdout = try self.list(u8, source.stdout.items);
        d.stderr = try self.list(u8, source.stderr.items);
        d.options.stdin = try self.text(source.options.stdin);
        try d.gc.reserveQueues(0);
        if (error_root) |index| _ = try d.rootValue(try self.value(source.rootedValue(index)));
        _ = d.gc.refreshAllocationTotal();
        d.gc.normalizeBaseline();
    }

    fn storedValue(self: *Copier, v: types.Value) !types.Value {
        // Inspect identities, never memory behind untracked stale pointers.
        switch (v) {
            .string => |string| if (!self.map.contains(@intFromPtr(string)) and !isStatic(string)) {
                return .nil;
            },
            inline .table, .closure, .userdata, .thread, .coroutine_wrapper, .gmatch_iterator => |p| if (!self.map.contains(@intFromPtr(p))) {
                return .nil;
            },
            else => {},
        }
        return self.value(v);
    }

    fn isStatic(string: *const types.String) bool {
        for (static_strings.strings) |static| if (static == string) return true;
        return false;
    }

    fn liveSlot(target: *const types.Thread, index: usize) bool {
        inline for (.{ "last_result", "last_transfer", "yield_result" }) |prefix| {
            const base = @field(target, prefix ++ "_base");
            if (index >= base and index - base < @field(target, prefix ++ "_count")) return true;
        }
        for (target.frames.items) |frame| {
            if (index >= frame.vararg_base and index - frame.vararg_base < frame.vararg_count) return true;
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
        // Unused stack slots may dangle after collection; only inspect tags and identities.
        try new.stack.resize(a, old.stack.items.len);
        for (old.stack.items, new.stack.items, 0..) |v, *out, index| {
            out.* = if (v == .string and liveSlot(old, index)) try self.value(v) else try self.storedValue(v);
        }
        try new.frames.ensureTotalCapacity(a, old.frames.items.len);
        for (old.frames.items) |f| {
            new.frames.appendAssumeCapacity(.{ .closure = try self.mapped(f.closure), .proto = try self.mapped(f.proto), .base = f.base, .pc = f.pc, .return_start = f.return_start, .return_count = f.return_count, .vararg_base = f.vararg_base, .vararg_count = f.vararg_count });
            const frame = &new.frames.items[new.frames.items.len - 1];
            if (f.pending_returns) |v| frame.pending_returns = try self.values(types.Value, v);
            inline for (.{ "vararg_table_local", "named_vararg_readonly", "last_hook_line", "debug_name_override", "debug_namewhat_override", "is_tail_call" }) |name| @field(frame, name) = try self.remap(@field(f, name));
        }
        inline for (.{ "yield_values", "protected_continuations", "generic_for_continuations", "pairs_continuations", "tail_call_continuations", "call_one_continuations" }) |name| {
            const items = @field(old, name).items;
            @field(new, name) = try self.list(std.meta.Elem(@TypeOf(items)), items);
        }
        inline for (.{ "open_upvalues", "hook", "hook_call", "hook_line", "hook_return", "hook_count", "hook_count_remaining", "pending_yield_hook_return", "continuation_order", "continuation_frame_count", "last_result_base", "last_result_count", "last_transfer_base", "last_transfer_count", "yield_result_base", "yield_result_count", "close_error_value", "error_traceback", "pending_unwind_error", "pending_unwind_resume_frame_count", "pending_unwind_target_frame_count", "entry", "started", "is_main", "closing", "status", "exposed", "error_handler", "stack_error_space", "host_frame", "frame_storage_bytes" }) |name| @field(new, name) = try self.remap(@field(old, name));
        // Hook transfer/name pointers and native call depths belong to host scopes and are not copied.
    }

    fn userdata(self: *Copier, old: *const types.Userdata, new: *types.Userdata) !void {
        const p = old.payload orelse return error.SnapshotUnsupported;
        new.type_id = old.type_id;
        new.type_name = try self.text(old.type_name);
        new.metatable = try self.remap(old.metatable);
        new.finalizer_next = try self.remap(old.finalizer_next);
        new.lua_finalizer_next = try self.remap(old.lua_finalizer_next);
        new.lua_finalizer_registered = old.lua_finalizer_registered;
        new.lua_finalizer_order = old.lua_finalizer_order;
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

// Any field change fails compilation until its copy policy is reviewed.
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
        for (reflection.fieldsOf(Policy)) |category| {
            var names = std.mem.tokenizeScalar(u8, @field(policy, category), ' ');
            while (names.next()) |name| {
                if (!@hasField(T, name)) @compileError("obsolete snapshot policy: " ++ @typeName(T) ++ "." ++ name);
                count += 1;
            }
        }
        if (count != reflection.fieldsOf(T).len) @compileError("review snapshot fields for " ++ @typeName(T));
        for (reflection.fieldsOf(T)) |field| {
            var matches: usize = 0;
            for (reflection.fieldsOf(Policy)) |category| {
                var names = std.mem.tokenizeScalar(u8, @field(policy, category), ' ');
                while (names.next()) |name| {
                    if (std.mem.eql(u8, field, name)) matches += 1;
                }
            }
            if (matches != 1) @compileError("missing/duplicate snapshot policy: " ++ @typeName(T) ++ "." ++ field);
        }
    }
}
comptime {
    @setEvalBranchQuota(1000000);
    review(State, .{
        .external = "allocator allocator_lifetime options",
        .rebuilt = "borrowed_proto_count strings api_roots gc budget",
        .remapped = "global_table table_metatable_head table_finalizer_head table_pending_finalizer_head userdata_pending_finalizer_head userdata_lua_pending_head string_metatable number_metatable boolean_metatable nil_metatable file_metatable fs_file_metatable io_input io_output library_tables last_error",
        .copied = "string_allocations table_allocations userdata_allocations closure_allocations upvalue_allocations thread_allocations proto_allocations source_allocations stdout stderr table_metatable_count table_finalizer_serial stdin_pos file_generation error_handled warnings_on random_state",
        .transient = "execution_depth userdata_scope value_roots rollback snapshot_busy discarding exit_request local_zone current_thread api_callback_dispatch api_callback_user_data active_api_callback coroutine_close_depth",
    });
    review(budget_mod.Budget, .{
        .copied = "instructions base",
        .transient = "call_deadline checkpoint interrupt",
    });
    review(gc_mod.Gc, .{
        .rebuilt = "next_total known_total",
        .copied = "running mode params",
        .transient = "epoch generation phase cycle work remembered weak tables finalizers major_pending cycle_start_total found_young old old_protos sweep_cursor major_base work_done minor_count collecting stress_collect stress_step stress_mark mark_all_stack_registers conservative_depth",
    });
    review(types.Thread, .{
        .copied = "exposed stack frames yield_values protected_continuations generic_for_continuations pairs_continuations tail_call_continuations call_one_continuations hook_call hook_line hook_return hook_count hook_count_remaining pending_yield_hook_return continuation_order continuation_frame_count last_result_base last_result_count last_transfer_base last_transfer_count yield_result_base yield_result_count pending_unwind_resume_frame_count pending_unwind_target_frame_count started is_main closing status stack_error_space host_frame frame_storage_bytes",
        .rebuilt = "storage_bytes",
        .remapped = "open_upvalues hook close_error_value error_traceback pending_unwind_error entry error_handler",
        .transient = "rollback gc hook_running hook_return_name hook_level2_func hook_transfer_index_base hook_transfer_stack_base hook_transfer_count hook_transfer_values next_call_name next_call_namewhat native_call_depth native_call protected_close_depth resume_parent native_marks native_mark_count",
    });
    review(types.CallFrame, .{
        .copied = "base pc return_start return_count vararg_base vararg_count named_vararg_readonly last_hook_line debug_name_override debug_namewhat_override is_tail_call pending_returns",
        .remapped = "closure proto vararg_table_local",
    });
    review(types.Table, .{
        .copied = "array entries finalizer_registered finalizer_order",
        .remapped = "metatable metatable_prev metatable_next finalizer_next finalizer_prev",
        .rebuilt = "entry_index storage_bytes",
        .transient = "rollback gc metamethod_absent weak_epoch tables_epoch",
    });
    review(types.Closure, .{
        .remapped = "proto root constants",
        .copied = "upvalue_count stripped_debug",
        .transient = "rollback gc",
    });
    review(types.Upvalue, .{
        .remapped = "owner closed next",
        .copied = "stack_index is_open",
        .transient = "rollback gc",
    });
    review(types.Userdata, .{
        .external = "ptr type_id finalizer finalizer_data deinit_fn",
        .copied = "type_name finalized finalization_pending lua_finalizer_registered lua_finalizer_order",
        .remapped = "metatable payload finalizer_next lua_finalizer_next",
        .transient = "scope_readers scope_writers rollback gc",
    });
    review(Proto, .{
        .rebuilt = "allocator arena",
        .copied = "constants instructions line_info locals upvalues error_sites max_registers param_count is_vararg named_vararg source_name debug_name defined_line last_defined_line has_to_close_locals runtime_prepared named_vararg_readonly fast_loop_entry fast_loop_call constant_values constant_hashes close_exit_jumps",
        .remapped = "children",
    });
    review(types.Value, .{ .remapped = "string table userdata closure thread coroutine_wrapper gmatch_iterator", .external = "nil boolean integer number native_print native_tostring native_getmetatable native_setmetatable native_rawequal native_rawget native_rawset native_rawlen native_next native_pairs native_ipairs native_ipairs_iter native_table_create native_select native_assert native_error native_pcall native_xpcall native_collectgarbage native_debug_traceback native_coroutine_create native_coroutine_resume native_coroutine_yield native_coroutine_status native_coroutine_running native_coroutine_isyieldable native_coroutine_close native_coroutine_wrap native api_callback" });
    review(types.String, .{
        .copied = "len hash hashed interned static",
        .transient = "gc",
    });
    review(types.UserdataPayload, .{
        .external = "allocator lifetime ptr finalizer finalizer_data dispose snapshot_copy snapshot_dispose",
        .rebuilt = "references is_snapshot_copy",
        .copied = "finalized snapshot_tracking managed_bytes",
    });
}
