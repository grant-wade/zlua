//! Worker-local rollback. Retained storage is deliberately absent from GC roots.
const std = @import("std");
const reflection = @import("../reflection.zig");
const types = @import("types.zig");
const State = @import("state.zig").State;
const strings_mod = @import("strings.zig");

const Kind = enum { table, closure, upvalue, thread, userdata };
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
        /// The baseline upvalues of a detached closure.
        upvalues: if (T == types.Closure) []*types.Upvalue else void = if (T == types.Closure) &.{} else {},
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

fn duplicateCapacity(a: std.mem.Allocator, old: anytype) !@TypeOf(old) {
    var result: @TypeOf(old) = .empty;
    try result.ensureTotalCapacityPrecise(a, old.capacity);
    result.appendSliceAssumeCapacity(old.items);
    return result;
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
    var array = try table.array.clone(a);
    errdefer array.deinit(a);
    const hash = if (table.hash) |part| try part.clone(a) else null;
    touch(table);
    table.array = array;
    table.hash = hash;
    record.header.detached = true;
}

pub fn closureWritable(closure: *types.Closure) !void {
    const record = closure.rollback orelse return;
    if (record.header.detached) return;
    const a = record.header.journal.allocator;
    const upvalues = try a.dupe(*types.Upvalue, closure.upvalues());
    errdefer a.free(upvalues);
    touch(closure);
    record.upvalues = upvalues;
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
            try replacement.frames.appendSlice(a, thread.frames.items);
            for (replacement.frames.items) |*frame| frame.has_extra = false;
            try replacement.frame_extras.appendNTimes(a, .{}, thread.frame_extras.items.len);
            for (thread.frames.items, 0..) |frame, index| {
                if (!frame.has_extra) continue;
                var extra = thread.frame_extras.items[index];
                if (extra.pending_returns) |values| extra.pending_returns = try a.dupe(types.Value, values);
                replacement.frame_extras.items[index] = extra;
                replacement.frames.items[index].has_extra = true;
            }
        } else if (comptime !std.mem.eql(u8, name, "frame_extras")) @field(replacement, name) = try duplicateList(a, @field(thread, name));
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
    // The original payload now belongs to the rollback record: never finalized, never a GC root.
    userdata.payload = copy;
    userdata.ptr = copy.ptr;
    record.header.detached = true;
}

const thread_lists = .{ "stack", "frames", "frame_extras", "yield_values", "protected_continuations", "generic_for_continuations", "pairs_continuations", "tail_call_continuations", "call_one_continuations" };
const registries = .{ "string_allocations", "table_allocations", "userdata_allocations", "closure_allocations", "upvalue_allocations", "thread_allocations", "chunk_allocations", "source_allocations" };
const object_lists = .{ "table_allocations", "closure_allocations", "upvalue_allocations", "thread_allocations", "userdata_allocations" };
const object_types = .{ types.Table, types.Closure, types.Upvalue, types.Thread, types.Userdata };
const record_lists = .{ "tables", "closures", "upvalues", "threads", "userdata" };

/// One length per name in `registries`.
pub const RegistryLengths = struct {
    string_allocations: usize = 0,
    table_allocations: usize = 0,
    userdata_allocations: usize = 0,
    closure_allocations: usize = 0,
    upvalue_allocations: usize = 0,
    thread_allocations: usize = 0,
    chunk_allocations: usize = 0,
    source_allocations: usize = 0,
};

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
        .managed_bytes = p.managed_bytes,
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
    /// Registry lengths at `attach`.
    attached: RegistryLengths = .{},
    /// Baseline objects still in each registry; they precede every object allocated since `attach`.
    baseline: RegistryLengths = .{},
    registries_detached: bool = false,
    output_detached: bool = false,
    finalizers_detached: bool = false,
    /// Logical restored records, independent of heap size.
    last_restored_objects: usize = 0,

    pub fn create(state: *State, pristine: *const State) !*Journal {
        const a = state.allocator;
        const self = try a.create(Journal);
        self.* = .{ .allocator = a, .saved = state.* };
        errdefer self.freeRecords();
        var count: usize = 0;
        inline for (object_types, object_lists, record_lists) |T, list, records| {
            const objects = @field(state, list).items;
            @field(self, records) = try a.alloc(Record(T), objects.len);
            for (objects, @field(self, records)) |object, *record| {
                record.* = .{ .header = .{ .journal = self, .kind = kindOf(T) }, .object = object, .original = object.* };
                if (T == types.Table) {
                    record.original.in_weak_list = false;
                    record.original.in_table_list = false;
                }
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

    pub fn forEachOriginal(self: *Journal, comptime f: anytype) void {
        inline for (record_lists) |records| for (@field(self, records)) |*record| f(&record.original);
    }

    pub fn attach(self: *Journal, state: *State) void {
        state.rollback = self;
        inline for (record_lists) |records| for (@field(self, records)) |*record| {
            record.object.rollback = record;
            record.original.rollback = record;
        };
        state.gc.normalizeBaseline();
        inline for (registries) |name| @field(self.attached, name) = @field(state, name).items.len;
        self.baseline = self.attached;
        self.saved = state.*;
        self.saved.rollback = self;
    }

    pub fn prepareAllocation(self: *Journal, state: *State) !void {
        try self.detachRegistries(state);
    }

    pub fn detachRegistries(self: *Journal, state: *State) !void {
        if (self.registries_detached) return;
        var replacement = state.*;
        inline for (registries) |name| @field(replacement, name) = .empty;
        replacement.strings.set = .{};
        errdefer freeRegistries(&replacement);
        inline for (registries) |name| @field(replacement, name) = try duplicateList(self.allocator, @field(state, name));
        replacement.strings.set = try state.strings.set.clone(self.allocator);
        inline for (registries) |name| @field(state, name) = @field(replacement, name);
        state.strings.set = replacement.strings.set;
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

    pub fn finalizersWritable(self: *Journal, state: *State) !void {
        if (self.finalizers_detached) return;
        var registered = try duplicateCapacity(self.allocator, state.table_finalizers);
        errdefer registered.deinit(self.allocator);
        const pending = try duplicateCapacity(self.allocator, state.table_pending_finalizers);
        state.table_finalizers = registered;
        state.table_pending_finalizers = pending;
        self.finalizers_detached = true;
    }

    /// Called before GC enters its infallible destructive phases.
    pub fn prepareCollection(self: *Journal, state: *State) !void {
        if (state.table_finalizers.items.len != 0) try self.finalizersWritable(state);
        if (state.gc.cycle == .major) return self.detachRegistries(state);
        inline for (reflection.fieldsOf(types.GcGenerations)) |f| {
            if (@field(state, f).items.len != @field(state.gc.old, f)) return self.detachRegistries(state);
        }
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
        state.gc.work.clearRetainingCapacity();
        state.gc.remembered.clearRetainingCapacity();
        state.gc.clearTableLists();
        state.gc.finalizers.clearRetainingCapacity();
        state.discarding = true;
        self.last_restored_objects = self.dirty.items.len + self.destroyNewObjects(state);
        for (self.dirty.items) |h| switch (h.kind) {
            inline else => |kind| {
                const T = typeOf(kind);
                const record: *Record(T) = @fieldParentPtr("header", h);
                if (h.detached) {
                    freeStorage(T, self.allocator, record.object);
                    if (T == types.Closure) restoreUpvalues(self.allocator, record);
                }
                record.object.* = record.original;
                h.dirty = false;
                h.detached = false;
                h.dead = false;
            },
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
        if (self.finalizers_detached) {
            state.table_finalizers.deinit(self.allocator);
            state.table_pending_finalizers.deinit(self.allocator);
        }
        const roots = state.api_roots;
        const callback_dispatch = state.api_callback_dispatch;
        const callback_data = state.api_callback_user_data;
        const interrupt = state.budget.interrupt;
        const file_generation = state.file_generation;
        const gc_work = state.gc.work;
        const gc_remembered = state.gc.remembered;
        const gc_weak = state.gc.weak;
        const gc_tables = state.gc.tables;
        const gc_finalizers = state.gc.finalizers;
        const string_scratch = state.strings.scratch;
        const epoch = state.gc.epoch;
        const generation = state.gc.generation;
        state.* = self.saved;
        state.gc.work = gc_work;
        state.gc.remembered = gc_remembered;
        state.gc.weak = gc_weak;
        state.gc.tables = gc_tables;
        state.gc.finalizers = gc_finalizers;
        state.strings.scratch = string_scratch;
        state.gc.epoch = epoch;
        state.gc.generation = generation;
        state.gc.advanceEpoch();
        state.gc.advanceGeneration();
        state.api_roots = roots;
        state.api_roots.clearRetainingCapacity();
        state.api_callback_dispatch = callback_dispatch;
        state.api_callback_user_data = callback_data;
        state.budget.interrupt = interrupt;
        state.file_generation = file_generation +% 1;
        state.budget.call_deadline = null;
        state.budget.checkpoint = 0;
        self.baseline = self.attached;
        self.registries_detached = false;
        self.output_detached = false;
        self.finalizers_detached = false;
    }

    /// Frees every object allocated since `attach` and still registered, returning how many.
    fn destroyNewObjects(self: *Journal, state: *State) usize {
        const a = self.allocator;
        var count: usize = 0;
        inline for (registries) |name| {
            for (@field(state, name).items[@field(self.baseline, name)..]) |item| {
                if (comptime std.mem.eql(u8, name, "string_allocations")) {
                    strings_mod.destroy(state.objects(), item);
                } else if (comptime std.mem.eql(u8, name, "source_allocations")) {
                    if (item.len == 0) continue;
                    a.free(item);
                } else if (comptime std.mem.eql(u8, name, "chunk_allocations")) {
                    item.destroy(a);
                } else {
                    const T = @typeInfo(@TypeOf(item)).pointer.child;
                    freeStorage(T, a, item);
                    destroyObject(T, state, item);
                }
                count += 1;
            }
        }
        return count;
    }

    /// End tracking while preserving the current logical state. Capture and
    /// destruction may traverse the baseline; reset only walks dirty records.
    pub fn abandon(self: *Journal, state: *State) void {
        state.rollback = null;
        inline for (object_types, record_lists) |T, records| for (@field(self, records)) |*record| {
            record.object.rollback = null;
            if (record.header.detached) {
                freeStorage(T, self.allocator, &record.original);
                if (T == types.Closure) self.allocator.free(record.upvalues);
            }
            if (record.header.dead) {
                freeStorage(T, self.allocator, record.object);
                destroyObject(T, state, record.object);
            }
        };
        if (self.registries_detached) {
            freeRetainedStrings(self.allocator, &self.saved, state);
            freeRegistries(&self.saved);
        }
        if (self.output_detached) {
            self.saved.stdout.deinit(self.allocator);
            self.saved.stderr.deinit(self.allocator);
        }
        if (self.finalizers_detached) {
            self.saved.table_finalizers.deinit(self.allocator);
            self.saved.table_pending_finalizers.deinit(self.allocator);
        }
        self.freeRecords();
    }

    fn freeRecords(self: *Journal) void {
        const a = self.allocator;
        for (self.userdata) |record| if (record.pristine) |p| p.release(true);
        self.eager.deinit(a);
        inline for (record_lists) |records| a.free(@field(self, records));
        self.dirty.deinit(a);
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
    state.strings.set.deinit(state.allocator);
}

/// Frees baseline strings that were collected since the snapshot.
fn freeRetainedStrings(a: std.mem.Allocator, saved: *const State, state: *const State) void {
    var live = std.AutoHashMap(*const types.String, void).init(a);
    defer live.deinit();
    live.ensureTotalCapacity(@intCast(state.string_allocations.items.len)) catch return;
    for (state.string_allocations.items) |string| live.putAssumeCapacity(string, {});
    for (saved.string_allocations.items) |string| {
        if (!live.contains(string)) strings_mod.destroy(state.objects(), string);
    }
}
fn freeStorage(comptime T: type, a: std.mem.Allocator, object: *T) void {
    if (T == types.Table or T == types.Thread) {
        object.deinit(a);
    } else if (T == types.Userdata) {
        if (object.payload) |p| p.release(true);
    }
}
fn restoreUpvalues(a: std.mem.Allocator, record: *Record(types.Closure)) void {
    @memcpy(record.object.upvalues(), record.upvalues);
    a.free(record.upvalues);
    record.upvalues = &.{};
}
fn destroyObject(comptime T: type, state: *const State, object: *T) void {
    const a = state.allocatorFor(T);
    if (T == types.Closure) types.Closure.destroy(a, object) else a.destroy(object);
}
fn kindOf(comptime T: type) Kind {
    inline for (comptime std.enums.values(Kind)) |kind| if (T == typeOf(kind)) return kind;
    @compileError("unknown rollback allocation " ++ @typeName(T));
}
fn typeOf(comptime kind: Kind) type {
    return switch (kind) {
        .table => types.Table,
        .closure => types.Closure,
        .upvalue => types.Upvalue,
        .thread => types.Thread,
        .userdata => types.Userdata,
    };
}
