const std = @import("std");
const runtime = @import("../runtime.zig");
const rollback_runtime = @import("../runtime/rollback.zig");
const runtime_types = @import("../runtime/types.zig");
const snapshot_runtime = @import("../runtime/snapshot.zig");
const callbacks = @import("callbacks.zig");
const errors = @import("errors.zig");
const state_mod = @import("state.zig");
const MemoryFile = runtime.MemoryFile;
const MemoryLimitAllocator = @import("memory_limit.zig").MemoryLimitAllocator;
const RegisteredCallback = callbacks.RegisteredCallback;
const State = state_mod.State;

/// Immutable, reference-counted VM snapshot. Separately retained handles may call `newState`
/// concurrently; bit copies do not retain ownership. Allocators must outlive every owner and
/// allow frees from any thread. Hookless userdata and host capabilities stay shared.
pub const Snapshot = struct {
    backing: *const SnapshotBacking,

    /// Returns a separately owned handle, e.g. to move to another thread.
    pub fn retain(self: *const Snapshot) Snapshot {
        self.backing.retain();
        return .{ .backing = self.backing };
    }

    /// Releases this handle; storage is freed after the final owner.
    pub fn deinit(self: *Snapshot) void {
        self.backing.release();
        self.* = undefined;
    }

    /// Creates an independent State with this snapshot as its baseline; it keeps the snapshot alive.
    pub fn newState(self: *const Snapshot, state_allocator: std.mem.Allocator) !State {
        var limit: ?*MemoryLimitAllocator = null;
        {
            const p = try state_allocator.create(MemoryLimitAllocator);
            p.* = MemoryLimitAllocator.init(state_allocator, self.backing.image.raw_state.options.max_memory orelse std.math.maxInt(usize));
            limit = p;
        }
        errdefer if (limit) |p| p.lifetime.release();
        var result = try copyFrozenImage(&self.backing.image, state_allocator, if (limit) |p| p.allocator() else state_allocator, if (limit) |p| &p.lifetime else null);
        errdefer discardImage(&result);
        try installRollback(&result, &self.backing.image.raw_state);
        result.memory_limit_allocator = limit;
        self.backing.retain();
        result.baseline = self.backing;
        self.backing.retain();
        result.immutable_owner = self.backing;
        return result;
    }
};

// Immutable after construction; wrappers and states retain it independently.
pub const SnapshotBacking = struct {
    allocator: std.mem.Allocator,
    lifetime: ?*runtime_types.AllocatorLifetime = null,
    references: std.atomic.Value(usize) = .init(1),
    image: State,

    pub fn retain(self: *const SnapshotBacking) void {
        const previous = @constCast(self).references.fetchAdd(1, .monotonic);
        std.debug.assert(previous != 0 and previous != std.math.maxInt(usize));
    }

    pub fn release(self: *const SnapshotBacking) void {
        const mutable = @constCast(self);
        // Acquire pairs with prior releases before destroying the immutable graph.
        const previous = mutable.references.fetchSub(1, .acq_rel);
        std.debug.assert(previous != 0);
        if (previous != 1) return;
        const allocator = mutable.allocator;
        const lifetime = mutable.lifetime;
        discardImage(&mutable.image);
        allocator.destroy(mutable);
        if (lifetime) |owner| owner.release();
    }
};

pub const RollbackMetadata = struct {
    files: std.ArrayList(MemoryFile),
    owned: std.ArrayList(bool),
    callbacks: std.ArrayList(RegisteredCallback),
    error_value: ?runtime.Value,
    detached: bool = false,

    fn capture(state: *State) RollbackMetadata {
        return .{ .files = state.memory_files, .owned = state.memory_file_owned_contents, .callbacks = state.callbacks, .error_value = if (state.last_error_root) |index| state.raw_state.rootedValue(index) else null };
    }
    fn freeContainers(self: *RollbackMetadata, a: std.mem.Allocator) void {
        self.files.deinit(a);
        self.owned.deinit(a);
        self.callbacks.deinit(a);
    }
    fn detach(self: *RollbackMetadata, state: *State) !void {
        if (self.detached) return;
        const a = state.allocator();
        var copy = RollbackMetadata{ .files = .empty, .owned = .empty, .callbacks = .empty, .error_value = null };
        errdefer copy.freeContainers(a);
        // Entries stay owned by the live state; only container storage is retained for rollback.
        try copy.files.appendSlice(a, state.memory_files.items);
        try copy.owned.appendSlice(a, state.memory_file_owned_contents.items);
        try copy.callbacks.appendSlice(a, state.callbacks.items);
        state.memory_files = copy.files;
        state.memory_file_owned_contents = copy.owned;
        state.callbacks = copy.callbacks;
        if (state.raw_state.options.filesystem == .memory) state.raw_state.options.filesystem = .{ .memory = state.memory_files.items };
        self.detached = true;
    }
    fn restore(self: *RollbackMetadata, state: *State) void {
        if (!self.detached) return;
        const a = state.allocator();
        var current = capture(state);
        for (current.files.items[self.files.items.len..], current.owned.items[self.files.items.len..]) |file, owned| {
            a.free(file.path);
            if (owned) a.free(file.contents);
        }
        for (current.callbacks.items[self.callbacks.items.len..]) |entry| a.free(entry.name);
        current.freeContainers(a);
        state.memory_files = self.files;
        state.memory_file_owned_contents = self.owned;
        state.callbacks = self.callbacks;
        self.detached = false;
    }
    fn abandon(self: *RollbackMetadata, state: *State) void {
        if (self.detached) self.freeContainers(state.allocator());
    }
};

pub fn create(state: *State, snapshot_allocator: std.mem.Allocator) !Snapshot {
    try snapshot_runtime.checkIdle(&state.raw_state);
    try ownSnapshotInputs(state);
    const backing = try snapshot_allocator.create(SnapshotBacking);
    errdefer snapshot_allocator.destroy(backing);
    // Stateless allocators may leave ptr undefined, so compare it only after the vtable.
    const uses_state_allocator = snapshot_allocator.vtable == state.raw_state.allocator.vtable and snapshot_allocator.ptr == state.raw_state.allocator.ptr;
    const lifetime = if (uses_state_allocator) state.raw_state.allocator_lifetime else null;
    backing.* = .{ .allocator = snapshot_allocator, .lifetime = lifetime, .image = try copyImage(state, snapshot_allocator, snapshot_allocator, lifetime) };
    errdefer discardImage(&backing.image);
    try installRollback(state, &backing.image.raw_state);
    if (lifetime) |owner| owner.retain();
    backing.retain();
    if (state.baseline) |previous| previous.release();
    state.baseline = backing;
    return .{ .backing = backing };
}

pub fn reset(state: *State) !void {
    const baseline = state.baseline orelse return error.NoSnapshot;
    const journal = state.raw_state.rollback orelse return error.NoSnapshot;
    const metadata = if (state.rollback_metadata) |*value| value else return error.NoSnapshot;
    try snapshot_runtime.checkIdleFast(&state.raw_state);
    if (state.generation == std.math.maxInt(u64)) return error.GenerationExhausted;
    state.raw_state.snapshot_busy = true;
    defer state.raw_state.snapshot_busy = false;
    const limit = state.memory_limit_allocator;
    const previous_limit = if (limit) |l| l.limit else 0;
    const previous_exceeded = if (limit) |l| l.exceeded else false;
    if (limit) |l| l.limit = baseline.image.raw_state.options.max_memory orelse std.math.maxInt(usize);
    errdefer if (limit) |l| {
        l.limit = previous_limit;
        l.exceeded = previous_exceeded;
    };
    const prepared = try journal.prepareReset();
    defer state.allocator().free(prepared);
    metadata.restore(state);
    journal.reset(&state.raw_state, prepared);
    errors.clearLastErrorTraceback(state);
    state.last_error_root = null;
    if (metadata.error_value) |value| {
        state.raw_state.api_roots.appendAssumeCapacity(value);
        state.last_error_root = 0;
    }
    if (limit) |l| {
        l.limit = state.raw_state.options.max_memory orelse std.math.maxInt(usize);
        l.exceeded = false;
    }
    state.generation += 1;
    callbacks.bindDispatch(state);
}

pub fn writableBindings(state: *State) !void {
    if (state.rollback_metadata) |*metadata| try metadata.detach(state);
}

pub fn abandonRollbackMetadata(state: *State) void {
    if (state.rollback_metadata) |*metadata| metadata.abandon(state);
    state.rollback_metadata = null;
}

fn ownSnapshotInputs(state: *State) !void {
    const input = state.raw_state.options.stdin;
    if (input.len != 0) {
        var owned = false;
        for (state.raw_state.source_allocations.items) |source| if (source.ptr == input.ptr) {
            owned = true;
            break;
        };
        if (!owned) {
            const copy = try state.allocator().dupe(u8, input);
            errdefer state.allocator().free(copy);
            try state.raw_state.registerAllocation("source_allocations", copy);
            state.raw_state.options.stdin = copy;
        }
    }
    for (0..state.memory_files.items.len) |index| {
        if (state.memory_file_owned_contents.items[index]) continue;
        try writableBindings(state);
        const copy = try state.allocator().dupe(u8, state.memory_files.items[index].contents);
        state.memory_files.items[index].contents = copy;
        state.memory_file_owned_contents.items[index] = true;
    }
}

fn installRollback(state: *State, pristine: *const runtime.State) !void {
    const journal = try rollback_runtime.Journal.create(&state.raw_state, pristine);
    abandonRollbackMetadata(state);
    if (state.raw_state.rollback) |previous| previous.abandon(&state.raw_state);
    state.rollback_metadata = RollbackMetadata.capture(state);
    journal.attach(&state.raw_state);
}

fn discardImage(state: *State) void {
    const a = state.allocator();
    abandonRollbackMetadata(state);
    state.raw_state.discard();
    state_mod.deinitOwnedMemoryFiles(state, a);
    state.memory_files.deinit(a);
    state.memory_file_owned_contents.deinit(a);
    callbacks.deinitNames(state, a);
    state.callbacks.deinit(a);
    if (state.baseline) |baseline| baseline.release();
    if (state.immutable_owner) |owner| owner.release();
}

fn copyImage(state: *State, base: std.mem.Allocator, a: std.mem.Allocator, lifetime: ?*runtime_types.AllocatorLifetime) !State {
    const raw = try snapshot_runtime.copy(&state.raw_state, a, lifetime, state.last_error_root);
    return copyImageMetadata(state, base, a, raw);
}

fn copyFrozenImage(state: *const State, base: std.mem.Allocator, a: std.mem.Allocator, lifetime: ?*runtime_types.AllocatorLifetime) !State {
    const raw = try snapshot_runtime.copyFrozen(&state.raw_state, a, lifetime, state.last_error_root);
    return copyImageMetadata(state, base, a, raw);
}

fn copyImageMetadata(state: *const State, base: std.mem.Allocator, a: std.mem.Allocator, raw: runtime.State) !State {
    var result = State{ .base_allocator = base, .raw_state = raw };
    errdefer discardImage(&result);
    if (state.last_error_root != null) result.last_error_root = 0;
    for (state.callbacks.items) |entry| {
        const name = try a.dupe(u8, entry.name);
        errdefer a.free(name);
        try result.callbacks.append(a, .{ .name = name, .callback = entry.callback });
    }
    for (state.memory_files.items) |file| try state_mod.appendMemoryFile(&result, file.path, file.contents, true);
    if (result.raw_state.options.filesystem == .memory) result.raw_state.options.filesystem = .{ .memory = result.memory_files.items };
    return result;
}
