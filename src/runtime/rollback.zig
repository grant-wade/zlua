//! Worker-local rollback. Retained storage is deliberately absent from GC roots.
const std = @import("std");
const types = @import("types.zig");
const State = @import("state.zig").State;
const Proto = @import("../compile/proto.zig").Proto;

const Kind = enum { table, closure, upvalue, thread, userdata, string, source, proto };
const Allocation = struct { kind: Kind, len: usize = 0 };
const Header = struct {
    journal: *Journal,
    kind: Kind,
    dirty: bool = false,
    detached: bool = false,
    dead: bool = false,
};
pub fn Record(comptime T: type) type {
    return struct {
        header: Header,
        object: *T,
        original: T,
        pristine: ?*types.UserdataPayload = null,
    };
}

pub fn touch(object: anytype) void {
    if (object.rollback) |record| {
        const h = &record.header;
        if (!h.dirty) {
            h.journal.dirty.appendAssumeCapacity(h);
            h.dirty = true;
        }
    }
}

fn duplicateList(a: std.mem.Allocator, old: anytype) !@TypeOf(old) {
    var result: @TypeOf(old) = .empty;
    try result.appendSlice(a, old.items);
    return result;
}

pub fn tableWritable(table: *types.Table) !void {
    const record = table.rollback orelse return;
    if (record.header.detached) return;
    const a = record.header.journal.allocator;
    var array = try duplicateList(a, table.array);
    errdefer array.deinit(a);
    var entries = try duplicateList(a, table.entries);
    errdefer entries.deinit(a);
    const index = try table.entry_index.clone();
    touch(table);
    table.array = array;
    table.entries = entries;
    table.entry_index = index;
    record.header.detached = true;
}

pub fn closureWritable(closure: *types.Closure) !void {
    const record = closure.rollback orelse return;
    if (record.header.detached) return;
    const a = record.header.journal.allocator;
    const upvalues = try a.dupe(*types.Upvalue, closure.upvalues);
    errdefer a.free(upvalues);
    const constants = if (closure.constants) |c| try a.dupe(?types.Value, c) else null;
    touch(closure);
    closure.upvalues = upvalues;
    closure.constants = constants;
    record.header.detached = true;
}

pub fn threadWritable(thread: *types.Thread) !void {
    const record = thread.rollback orelse return;
    if (record.header.detached) return;
    const a = record.header.journal.allocator;
    var replacement = thread.*;
    inline for (thread_lists) |name| @field(replacement, name) = .empty;
    errdefer replacement.deinit(a);
    inline for (thread_lists) |name| {
        if (comptime std.mem.eql(u8, name, "frames")) {
            try replacement.frames.ensureTotalCapacity(a, thread.frames.items.len);
            for (thread.frames.items) |frame| {
                var copy = frame;
                copy.varargs = try a.dupe(types.Value, frame.varargs);
                errdefer a.free(copy.varargs);
                copy.owns_varargs = true;
                copy.pending_returns = if (frame.pending_returns) |values| try a.dupe(types.Value, values) else null;
                replacement.frames.appendAssumeCapacity(copy);
            }
        } else @field(replacement, name) = try duplicateList(a, @field(thread, name));
    }
    touch(thread);
    thread.* = replacement;
    record.header.detached = true;
}

pub fn userdataWritable(userdata: *types.Userdata) !void {
    const record = userdata.rollback orelse return;
    const p = userdata.payload orelse return;
    if (p.snapshot_tracking != .scoped or record.header.detached) return;
    const j = record.header.journal;
    const copy = try copyPayload(j.allocator, j.saved.allocator_lifetime, p);
    touch(userdata);
    // Ownership of the original payload moves from the live wrapper to its
    // rollback record. It is neither finalized nor a live GC root.
    userdata.payload = copy;
    userdata.ptr = copy.ptr;
    record.header.detached = true;
}

const thread_lists = .{ "stack", "frames", "yield_values", "protected_continuations", "generic_for_continuations", "tail_call_continuations", "call_one_continuations" };
const registries = .{ "string_allocations", "table_allocations", "userdata_allocations", "closure_allocations", "upvalue_allocations", "thread_allocations", "proto_allocations", "source_allocations" };
const object_lists = .{ "table_allocations", "closure_allocations", "upvalue_allocations", "thread_allocations", "userdata_allocations" };
const object_types = .{ types.Table, types.Closure, types.Upvalue, types.Thread, types.Userdata };
const record_lists = .{ "tables", "closures", "upvalues", "threads", "userdata" };

pub fn copyPayload(a: std.mem.Allocator, lifetime: ?*types.AllocatorLifetime, p: *types.UserdataPayload) !*types.UserdataPayload {
    const result = try a.create(types.UserdataPayload);
    errdefer a.destroy(result);
    const ptr = try p.snapshot_copy.?(a, p.ptr);
    result.* = .{
        .allocator = a,
        .lifetime = lifetime,
        .ptr = ptr,
        .finalizer = p.finalizer,
        .finalizer_data = p.finalizer_data,
        .dispose = p.snapshot_dispose,
        .finalized = p.finalized,
        .snapshot_copy = p.snapshot_copy,
        .snapshot_dispose = p.snapshot_dispose,
        .snapshot_tracking = p.snapshot_tracking,
        .is_snapshot_copy = true,
    };
    if (lifetime) |l| l.retain();
    return result;
}

/// Single-owner mutable rollback state; snapshot sharing does not synchronize it.
pub const Journal = struct {
    allocator: std.mem.Allocator,
    saved: State,
    tables: []Record(types.Table) = &.{},
    closures: []Record(types.Closure) = &.{},
    upvalues: []Record(types.Upvalue) = &.{},
    threads: []Record(types.Thread) = &.{},
    userdata: []Record(types.Userdata) = &.{},
    dirty: std.ArrayList(*Header) = .empty,
    eager: std.ArrayList(*Record(types.Userdata)) = .empty,
    new_objects: std.AutoHashMap(usize, Allocation),
    registries_detached: bool = false,
    output_detached: bool = false,
    /// Counts logical restored records, independently of the size of the heap.
    last_restored_objects: usize = 0,

    pub fn create(state: *State, pristine: *const State) !*Journal {
        const a = state.allocator;
        const self = try a.create(Journal);
        self.* = .{ .allocator = a, .saved = state.*, .new_objects = std.AutoHashMap(usize, Allocation).init(a) };
        errdefer self.freeRecords();
        var count: usize = 0;
        inline for (object_types, object_lists, record_lists) |T, list, records| {
            const objects = @field(state, list).items;
            @field(self, records) = try a.alloc(Record(T), objects.len);
            for (objects, @field(self, records)) |object, *record| {
                record.* = .{ .header = .{ .journal = self, .kind = kindOf(T) }, .object = object, .original = object.* };
            }
            count += objects.len;
        }
        try self.dirty.ensureTotalCapacity(a, count);
        for (self.userdata, pristine.userdata_allocations.items) |*record, original| {
            const p = record.object.payload orelse continue;
            if (p.snapshot_copy != null and p.snapshot_tracking == .eager) {
                try self.eager.append(a, record);
                record.pristine = original.payload.?;
                record.pristine.?.retain();
            }
        }
        return self;
    }

    pub fn attach(self: *Journal, state: *State) void {
        state.rollback = self;
        inline for (record_lists) |records| for (@field(self, records)) |*record| {
            record.object.rollback = record;
            record.original.rollback = record;
        };
        self.saved.rollback = self;
    }

    pub fn prepareAllocation(self: *Journal, state: *State) !void {
        try self.detachRegistries(state);
        try self.new_objects.ensureUnusedCapacity(1);
    }

    pub fn allocated(self: *Journal, comptime field: []const u8, item: anytype) void {
        const kind: Kind = comptime if (std.mem.eql(u8, field, "string_allocations")) .string else if (std.mem.eql(u8, field, "source_allocations")) .source else if (std.mem.eql(u8, field, "proto_allocations")) .proto else kindOf(@typeInfo(@TypeOf(item)).pointer.child);
        const address = switch (kind) {
            .string => @intFromPtr(item.bytes.ptr),
            .source => @intFromPtr(item.ptr),
            else => @intFromPtr(item),
        };
        const len = switch (kind) {
            .string => item.bytes.len,
            .source => item.len,
            else => 0,
        };
        if ((kind == .string or kind == .source) and len == 0) return;
        self.new_objects.putAssumeCapacity(address, .{ .kind = kind, .len = len });
    }

    pub fn freed(self: *Journal, address: usize) void {
        _ = self.new_objects.remove(address);
    }

    pub fn detachRegistries(self: *Journal, state: *State) !void {
        if (self.registries_detached) return;
        var replacement = state.*;
        inline for (registries) |name| @field(replacement, name) = .empty;
        replacement.strings = std.StringHashMap([]const u8).init(self.allocator);
        replacement.string_allocation_index = types.PointerAllocationIndex.init(self.allocator);
        replacement.table_allocation_index = types.PointerAllocationIndex.init(self.allocator);
        errdefer freeRegistries(&replacement);
        inline for (registries) |name| @field(replacement, name) = try duplicateList(self.allocator, @field(state, name));
        replacement.strings = try state.strings.clone();
        replacement.string_allocation_index = try state.string_allocation_index.clone();
        replacement.table_allocation_index = try state.table_allocation_index.clone();
        inline for (registries) |name| @field(state, name) = @field(replacement, name);
        state.strings = replacement.strings;
        state.string_allocation_index = replacement.string_allocation_index;
        state.table_allocation_index = replacement.table_allocation_index;
        self.registries_detached = true;
    }

    pub fn outputWritable(self: *Journal, state: *State) !void {
        if (self.output_detached) return;
        var stdout = try duplicateList(self.allocator, state.stdout);
        errdefer stdout.deinit(self.allocator);
        const stderr = try duplicateList(self.allocator, state.stderr);
        state.stdout = stdout;
        state.stderr = stderr;
        self.output_detached = true;
    }

    /// Called before GC enters its infallible destructive phases.
    pub fn prepareCollection(self: *Journal, state: *State) !void {
        try self.detachRegistries(state);
        // Mark bits are collector scratch space. Every collection resets them;
        // restoring the logical heap never needs a mark-bit traversal.
        for (state.table_allocations.items) |table| {
            if (table.finalizer_registered) touch(table);
        }
    }

    pub fn keepString(self: *Journal, bytes: []const u8) bool {
        if (self.saved.string_allocation_index.contains(@intFromPtr(bytes.ptr))) return true;
        self.freed(@intFromPtr(bytes.ptr));
        return false;
    }

    pub fn prepareReset(self: *Journal) ![]*types.UserdataPayload {
        const copies = try self.allocator.alloc(*types.UserdataPayload, self.eager.items.len);
        errdefer self.allocator.free(copies);
        var initialized: usize = 0;
        errdefer for (copies[0..initialized]) |p| p.release(true);
        for (self.eager.items, copies) |record, *copy| {
            copy.* = try copyPayload(self.allocator, self.saved.allocator_lifetime, record.pristine.?);
            initialized += 1;
        }
        return copies;
    }

    pub fn reset(self: *Journal, state: *State, prepared: []*types.UserdataPayload) void {
        state.discarding = true;
        self.last_restored_objects = self.dirty.items.len + self.new_objects.count();
        var objects = self.new_objects.iterator();
        while (objects.next()) |entry| destroyAllocation(self.allocator, entry.key_ptr.*, entry.value_ptr.*);
        self.new_objects.deinit();
        self.new_objects = std.AutoHashMap(usize, Allocation).init(self.allocator);
        for (self.dirty.items) |h| switch (h.kind) {
            inline .table, .closure, .upvalue, .thread, .userdata => |kind| {
                const T = typeOf(kind);
                const record: *Record(T) = @fieldParentPtr("header", h);
                if (h.detached) freeStorage(T, self.allocator, record.object);
                record.object.* = record.original;
                h.dirty = false;
                h.detached = false;
                h.dead = false;
            },
            else => unreachable,
        };
        for (self.eager.items, prepared) |record, payload| {
            if (record.object.payload) |old| old.release(true);
            record.object.* = record.original;
            record.object.payload = payload;
            record.object.ptr = payload.ptr;
            record.original = record.object.*;
        }
        self.dirty.clearRetainingCapacity();
        if (self.registries_detached) freeRegistries(state);
        if (self.output_detached) {
            state.stdout.deinit(self.allocator);
            state.stderr.deinit(self.allocator);
        }
        const roots = state.api_roots;
        const callback_dispatch = state.api_callback_dispatch;
        const callback_data = state.api_callback_user_data;
        state.* = self.saved;
        state.api_roots = roots;
        state.api_roots.clearRetainingCapacity();
        state.api_callback_dispatch = callback_dispatch;
        state.api_callback_user_data = callback_data;
        self.registries_detached = false;
        self.output_detached = false;
    }

    /// End tracking while preserving the current logical state. Capture and
    /// destruction may traverse the baseline; reset only walks dirty records.
    pub fn abandon(self: *Journal, state: *State) void {
        state.rollback = null;
        inline for (object_types, record_lists) |T, records| for (@field(self, records)) |*record| {
            record.object.rollback = null;
            if (record.header.detached) freeStorage(T, self.allocator, &record.original);
            if (record.header.dead) {
                freeStorage(T, self.allocator, record.object);
                self.allocator.destroy(record.object);
            }
        };
        if (self.registries_detached) {
            for (self.saved.string_allocations.items) |allocation| {
                if (!state.string_allocation_index.contains(@intFromPtr(allocation.bytes.ptr))) self.allocator.free(allocation.bytes);
            }
            freeRegistries(&self.saved);
        }
        if (self.output_detached) {
            self.saved.stdout.deinit(self.allocator);
            self.saved.stderr.deinit(self.allocator);
        }
        self.freeRecords();
    }

    fn freeRecords(self: *Journal) void {
        const a = self.allocator;
        for (self.userdata) |record| if (record.pristine) |p| p.release(true);
        self.eager.deinit(a);
        inline for (record_lists) |records| a.free(@field(self, records));
        self.dirty.deinit(a);
        self.new_objects.deinit();
        a.destroy(self);
    }
};

pub fn retainCollected(object: anytype) bool {
    if (object.rollback) |record| {
        touch(object);
        record.header.dead = true;
        return true;
    }
    return false;
}

fn freeRegistries(state: *State) void {
    inline for (registries) |name| @field(state, name).deinit(state.allocator);
    state.strings.deinit();
    state.string_allocation_index.deinit();
    state.table_allocation_index.deinit();
}
fn freeStorage(comptime T: type, a: std.mem.Allocator, object: *T) void {
    if (T == types.Table or T == types.Thread) {
        object.deinit(a);
    } else if (T == types.Closure) {
        a.free(object.upvalues);
        if (object.constants) |c| a.free(c);
    } else if (T == types.Userdata) {
        if (object.payload) |p| p.release(true);
    }
}
fn destroyAllocation(a: std.mem.Allocator, address: usize, allocation: Allocation) void {
    switch (allocation.kind) {
        .string, .source => a.free(@as([*]const u8, @ptrFromInt(address))[0..allocation.len]),
        .proto => {
            const p: *Proto = @ptrFromInt(address);
            p.deinit();
            a.destroy(p);
        },
        inline else => |tag| {
            const T = typeOf(tag);
            const object: *T = @ptrFromInt(address);
            freeStorage(T, a, object);
            a.destroy(object);
        },
    }
}
fn kindOf(comptime T: type) Kind {
    inline for (.{ Kind.table, Kind.closure, Kind.upvalue, Kind.thread, Kind.userdata }) |kind| if (T == typeOf(kind)) return kind;
    @compileError("unknown rollback allocation " ++ @typeName(T));
}
fn typeOf(comptime kind: Kind) type {
    return switch (kind) {
        .table => types.Table,
        .closure => types.Closure,
        .upvalue => types.Upvalue,
        .thread => types.Thread,
        .userdata => types.Userdata,
        else => @compileError("not a managed shell"),
    };
}
