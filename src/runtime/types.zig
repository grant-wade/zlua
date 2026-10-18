const std = @import("std");
const compile = @import("../compile.zig");
const runtime = @import("../runtime.zig");
const static_strings = @import("../stdlib/static_strings.zig");
const table_index = @import("table_index.zig");
const value_mod = @import("value.zig");

const bytecode = compile.bytecode;
const proto_mod = compile.proto;
const State = runtime.State;

pub const RuntimeError = error{
    RuntimeError,
    StackOverflow,
    UnsupportedOpcode,
    OutOfMemory,
};

// Full-byte tags keep the interpreter's frequent type checks to byte loads.
pub const Value = union(enum(u8)) {
    nil,
    boolean: bool,
    integer: i64,
    number: f64,
    string: *const String,
    table: *Table,
    userdata: *Userdata,
    closure: *Closure,
    thread: *Thread,
    coroutine_wrapper: *Thread,
    gmatch_iterator: *Table,
    native_print,
    native_tostring,
    native_getmetatable,
    native_setmetatable,
    native_rawequal,
    native_rawget,
    native_rawset,
    native_rawlen,
    native_next,
    native_pairs,
    native_ipairs,
    native_ipairs_iter,
    native_table_create,
    native_select,
    native_assert,
    native_error,
    native_pcall,
    native_xpcall,
    native_collectgarbage,
    native_debug_traceback,
    native_coroutine_create,
    native_coroutine_resume,
    native_coroutine_yield,
    native_coroutine_status,
    native_coroutine_running,
    native_coroutine_isyieldable,
    native_coroutine_close,
    native_coroutine_wrap,
    native: NativeFn,
    api_callback: usize,
};

pub const NativeFn = @import("native_fn.zig").NativeFn;

/// A Lua string, followed by its bytes in the same allocation. Strings of at most
/// `short_limit` bytes are always interned.
pub const String = extern struct {
    gc: GcHeader = .{},
    len: usize,
    /// `table_index.hashStringKey` of the bytes, valid once `hashed` is set.
    hash: u32 = 0,
    hashed: bool = false,
    /// In the state's intern set.
    interned: bool = false,
    /// From the static catalog; never collected or written.
    static: bool = false,

    pub const short_limit = 40;

    pub inline fn bytes(self: *const String) []const u8 {
        return (@as([*]const u8, @ptrCast(self)) + @sizeOf(String))[0..self.len];
    }

    pub inline fn bytesMut(self: *String) []u8 {
        return (@as([*]u8, @ptrCast(self)) + @sizeOf(String))[0..self.len];
    }

    pub inline fn isShort(self: *const String) bool {
        return self.len <= short_limit;
    }

    pub inline fn eql(self: *const String, other: *const String) bool {
        if (self == other) return true;
        if (self.len <= short_limit) return false;
        return self.len == other.len and std.mem.eql(u8, self.bytes(), other.bytes());
    }

    pub inline fn eqlBytes(self: *const String, other: []const u8) bool {
        return self.len == other.len and std.mem.eql(u8, self.bytes(), other);
    }

    pub inline fn tableHash(self: *const String) u32 {
        if (self.hashed) return self.hash;
        return hashLong(@constCast(self));
    }

    noinline fn hashLong(self: *String) u32 {
        self.hash = table_index.hashStringKey(self.bytes());
        self.hashed = true;
        return self.hash;
    }

    pub inline fn gcBytes(self: *const String) usize {
        return @sizeOf(String) + self.len;
    }
};

pub const UserdataFinalizer = *const fn (*anyopaque, ?*const anyopaque) void;
pub const UserdataDeinit = *const fn (std.mem.Allocator, *anyopaque) void;

/// Keeps allocator infrastructure alive while shared userdata outlives its State.
/// The last release, from any thread, destroys it.
pub const AllocatorLifetime = struct {
    references: std.atomic.Value(usize) = .init(1),
    destroy: *const fn (*AllocatorLifetime) void,

    pub fn retain(self: *AllocatorLifetime) void {
        const previous = self.references.fetchAdd(1, .monotonic);
        std.debug.assert(previous != 0 and previous != std.math.maxInt(usize));
    }
    pub fn release(self: *AllocatorLifetime) void {
        const previous = self.references.fetchSub(1, .acq_rel);
        std.debug.assert(previous != 0);
        if (previous == 1) self.destroy(self);
    }
};

pub const UserdataSnapshotCopy = *const fn (std.mem.Allocator, *const anyopaque) anyerror!*anyopaque;

/// Payload ownership is separate from the GC-managed Lua wrapper.
pub const UserdataPayload = struct {
    allocator: std.mem.Allocator,
    lifetime: ?*AllocatorLifetime,
    references: std.atomic.Value(usize) = .init(1),
    ptr: *anyopaque,
    /// Inline storage owned by this payload; nested storage is accounted by the host allocator.
    managed_bytes: usize = 0,
    finalizer: ?UserdataFinalizer,
    finalizer_data: ?*const anyopaque,
    dispose: ?UserdataDeinit,
    finalized: bool = false,
    snapshot_copy: ?UserdataSnapshotCopy = null,
    snapshot_tracking: enum { eager, scoped } = .eager,
    snapshot_dispose: ?UserdataDeinit = null,
    is_snapshot_copy: bool = false,

    pub fn retain(self: *UserdataPayload) void {
        const previous = self.references.fetchAdd(1, .monotonic);
        std.debug.assert(previous != 0 and previous != std.math.maxInt(usize));
    }

    pub fn finalize(self: *UserdataPayload) void {
        // A sole owner cannot race a retain; acquire observes earlier releases before reading `finalized`.
        if (self.references.load(.acquire) != 1) return;
        self.finalizeOwned();
    }

    fn finalizeOwned(self: *UserdataPayload) void {
        if (self.finalized) return;
        self.finalized = true;
        if (self.finalizer) |f| f(self.ptr, self.finalizer_data);
    }

    pub fn release(self: *UserdataPayload, discard: bool) void {
        // Elect the final owner first so concurrent releases neither skip finalization nor use freed storage.
        const previous = self.references.fetchSub(1, .acq_rel);
        std.debug.assert(previous != 0);
        if (previous != 1) return;
        if (!(discard and self.is_snapshot_copy)) self.finalizeOwned();
        const a = self.allocator;
        const lifetime = self.lifetime;
        if (self.dispose) |f| f(a, self.ptr);
        a.destroy(self);
        if (lifetime) |l| l.release();
    }
};

pub const ProtectedCallResult = union(enum) {
    success: []Value,
    failure: Value,
};

pub const ApiCallbackDispatchFn = *const fn (*ApiCallbackContext) anyerror!void;
/// Stores small callback results inline, without self pointers. GC visits them through `items()`.
pub const CallbackReturns = struct {
    inline_values: [4]Value = undefined,
    inline_len: usize = 0,
    spill: std.ArrayList(Value) = .empty,

    pub fn items(self: *const CallbackReturns) []const Value {
        return if (self.spill.capacity != 0) self.spill.items else self.inline_values[0..self.inline_len];
    }
    pub fn deinit(self: *CallbackReturns, allocator: std.mem.Allocator) void {
        self.spill.deinit(allocator);
    }
    pub fn clearRetainingCapacity(self: *CallbackReturns) void {
        self.inline_len = 0;
        self.spill.clearRetainingCapacity();
    }
    pub fn append(self: *CallbackReturns, allocator: std.mem.Allocator, value: Value) !void {
        if (self.spill.capacity == 0) {
            if (self.inline_len < self.inline_values.len) {
                self.inline_values[self.inline_len] = value;
                self.inline_len += 1;
                return;
            }
            // On failure, keep all inline results intact and visible to GC.
            try self.spill.ensureTotalCapacity(allocator, self.inline_len + 1);
            self.spill.appendSliceAssumeCapacity(self.inline_values[0..self.inline_len]);
        }
        try self.spill.append(allocator, value);
    }
};

pub const ApiCallbackContext = struct {
    state: *State,
    thread: *Thread,
    op: bytecode.Call,
    callback_id: usize,
    argument_base: usize,
    parent: ?*ApiCallbackContext,
    user_data: ?*anyopaque,
    function_name: []const u8 = "host callback",
    returns: CallbackReturns = .{},
    error_value: ?Value = null,

    pub fn deinit(self: *ApiCallbackContext) void {
        self.returns.deinit(self.state.allocator);
    }

    pub fn argCount(self: *ApiCallbackContext) usize {
        return self.op.arg_count;
    }

    pub fn callbackArgValue(self: *ApiCallbackContext, index: usize) Value {
        if (index >= self.op.arg_count) return .nil;
        return self.thread.stack.items[self.argument_base + index];
    }

    pub fn clearReturns(self: *ApiCallbackContext) void {
        self.returns.clearRetainingCapacity();
    }

    pub fn appendReturn(self: *ApiCallbackContext, value: Value) !void {
        try self.returns.append(self.state.allocator, value);
        self.state.gc.markValue(value);
    }

    pub fn fail(self: *ApiCallbackContext, message: []const u8) RuntimeError {
        return self.state.fail(message);
    }

    pub fn failArgumentMessage(self: *ApiCallbackContext, index: usize, message: []const u8) RuntimeError {
        return self.state.failArgumentMessage(self.function_name, argumentIndex(index), message);
    }

    pub fn failArgumentType(self: *ApiCallbackContext, index: usize, expected: []const u8, actual: Value) RuntimeError {
        return self.state.failArgumentType(self.function_name, argumentIndex(index), expected, actual);
    }

    pub fn raise(self: *ApiCallbackContext, value: Value) error{LuaError} {
        self.error_value = value;
        self.state.gc.markValue(value);
        return error.LuaError;
    }

    fn argumentIndex(index: usize) u32 {
        return std.math.cast(u32, index + 1) orelse std.math.maxInt(u32);
    }
};

pub const RuntimeErrorPayload = union(enum) {
    /// Process-lifetime text.
    diagnostic: []const u8,
    lua_value: Value,

    pub fn luaValue(self: RuntimeErrorPayload, state: anytype) Value {
        return switch (self) {
            .diagnostic => |message| .{ .string = state.strings.intern(message) catch static_strings.get("not enough memory") },
            .lua_value => |value| value,
        };
    }
};

pub const ProtectedCallContext = struct {
    frame_count: usize,
    relative_base: u32,
    absolute_base: usize,
    stack_len: usize,
    last_result_base: usize,
    last_result_count: usize,
    last_error: ?RuntimeErrorPayload,
    /// Message handler installed for the call, like `lua_pcall`'s `msgh`.
    error_handler: Value = .nil,
    /// The thread's handler before the call, restored when it ends.
    previous_error_handler: Value = .nil,
};

pub const NativeMark = struct {
    /// Frame count when the native function was called.
    frame_count: u32,
    callee: Value,
};

pub const ProtectedContinuation = struct {
    order: usize,
    context: ProtectedCallContext,
    base: u32,
    return_count: u16,
};

pub const GenericForContinuation = struct {
    frame_count: usize,
    op: bytecode.GenericFor,
    jump_on_nil: bool,
};

pub const PairsContinuation = struct {
    order: usize = 0,
    frame_count: usize,
    source_base: usize,
    base: u32,
    return_count: u16,
};

pub const BranchContinuation = struct {
    jump_if_truthy: bool,
    offset: bytecode.JumpOffset,
};

pub const TailCallContinuation = struct {
    frame_count: usize,
    base: u32,
    return_count: u16,
};

pub const CallOneContinuationResult = union(enum) {
    value: usize,
    truthy: usize,
    inverted_truthy: usize,
    branch_truthy: BranchContinuation,
    branch_inverted_truthy: BranchContinuation,
    concat: ConcatContinuation,
    discard,
};

/// A `concat_range` suspended in `__concat`. Slots are absolute stack indices; the
/// metamethod result becomes the last of the `count` operands starting at `first`.
pub const ConcatContinuation = struct {
    dest: usize,
    first: usize,
    count: usize,
};

pub const CallOneContinuation = struct {
    frame_count: usize,
    result: CallOneContinuationResult,
};

pub const CoroutineResumeResult = union(enum) {
    success: []Value,
    failure: Value,
};

/// A Lua function, followed by its `upvalue_count` upvalue pointers in the same allocation.
pub const Closure = struct {
    gc: GcHeader = .{},
    rollback: ?*@import("rollback.zig").Record(Closure) = null,
    proto: *const proto_mod.Proto,
    /// Loaded chunk prototype that owns `proto`; null when `proto` is that root.
    root: ?*const proto_mod.Proto = null,
    constants: ?[]?Value = null,
    upvalue_count: u32 = 0,
    stripped_debug: bool = false,

    comptime {
        std.debug.assert(@sizeOf(Closure) % @alignOf(*Upvalue) == 0);
    }

    pub inline fn upvalues(self: *const Closure) []*Upvalue {
        const base: [*]*Upvalue = @ptrCast(@alignCast(@as([*]u8, @ptrCast(@constCast(self))) + @sizeOf(Closure)));
        return base[0..self.upvalue_count];
    }

    pub fn allocationBytes(upvalue_count: usize) usize {
        return @sizeOf(Closure) + upvalue_count * @sizeOf(*Upvalue);
    }

    /// Allocates `initial` with room for `upvalue_count` upvalues, which start undefined.
    pub fn create(allocator: std.mem.Allocator, upvalue_count: usize, initial: Closure) !*Closure {
        const count = std.math.cast(u32, upvalue_count) orelse return error.OutOfMemory;
        const memory = try allocator.alignedAlloc(u8, .of(Closure), allocationBytes(count));
        const closure: *Closure = @ptrCast(memory.ptr);
        closure.* = initial;
        closure.upvalue_count = count;
        return closure;
    }

    /// Frees the allocation only; `constants` belongs to the caller.
    pub fn destroy(allocator: std.mem.Allocator, closure: *Closure) void {
        const memory: [*]align(@alignOf(Closure)) u8 = @ptrCast(closure);
        allocator.free(memory[0..allocationBytes(closure.upvalue_count)]);
    }
};

pub const Upvalue = struct {
    gc: GcHeader = .{},
    rollback: ?*@import("rollback.zig").Record(Upvalue) = null,
    owner: *Thread,
    stack_index: usize,
    closed: Value = .nil,
    is_open: bool = true,
    next: ?*Upvalue = null,
};

pub const TableEntry = struct {
    key: Value,
    value: Value,
};

pub const TableEntryIndex = table_index.EntryIndex;

/// Metamethod events whose absence a metatable caches in
/// `Table.metamethod_absent`. Tag names are the event keys.
pub const MetaEvent = enum(u5) {
    __index,
    __newindex,
    __len,
    __eq,
    __call,
    __add,
    __sub,
    __mul,
    __div,
    __mod,
    __pow,
    __unm,
    __idiv,
    __band,
    __bor,
    __bxor,
    __shl,
    __shr,
    __bnot,
    __lt,
    __le,
    __concat,
    __close,
    __tostring,
    __name,
    __pairs,

    pub fn fromName(name: []const u8) ?MetaEvent {
        if (name.len < 4 or name[0] != '_' or name[1] != '_') return null;
        return std.meta.stringToEnum(MetaEvent, name);
    }

    inline fn bit(event: MetaEvent) u32 {
        return @as(u32, 1) << @intFromEnum(event);
    }
};

pub const Table = struct {
    // Up to this many entries, a linear scan beats maintaining a hash index.
    const linear_entry_limit = 4;

    gc: GcHeader = .{},
    rollback: ?*@import("rollback.zig").Record(Table) = null,
    array: std.ArrayList(Value) = .empty,
    entries: std.ArrayList(TableEntry) = .empty,
    entry_index: TableEntryIndex = .{},
    metatable: ?*Table = null,
    metatable_prev: ?*Table = null,
    metatable_next: ?*Table = null,
    finalizer_registered: bool = false,
    finalizer_next: ?*Table = null,
    finalizer_prev: ?*Table = null,
    finalizer_order: u64 = 0,
    /// Bit `e` set: this metatable has no raw value for `MetaEvent` `e`. Hash-part
    /// writes that may turn nil into non-nil clear the whole set.
    metamethod_absent: u32 = 0,
    /// Collector epoch in which this table joined `Gc.weak`.
    weak_epoch: u64 = 0,
    /// Collector epoch in which this table joined `Gc.tables`.
    tables_epoch: u64 = 0,
    /// Capacity bytes last reported to the collector.
    storage_bytes: usize = 0,

    pub inline fn init(allocator: std.mem.Allocator, array_hint: u32, hash_hint: u32) !Table {
        var table = Table{};
        errdefer table.deinit(allocator);
        try table.array.ensureTotalCapacityPrecise(allocator, array_hint);
        try table.entries.ensureTotalCapacity(allocator, hash_hint);
        if (hash_hint > linear_entry_limit) try table.entry_index.ensureTotalCapacity(allocator, hash_hint);
        return table;
    }

    pub fn deinit(self: *Table, allocator: std.mem.Allocator) void {
        self.entry_index.deinit(allocator);
        self.entries.deinit(allocator);
        self.array.deinit(allocator);
        self.* = undefined;
    }

    pub fn get(self: *const Table, key: Value) Value {
        if (value_mod.arrayIndex(key)) |index| {
            if (index <= self.array.items.len) return self.array.items[index - 1];
        }
        if (self.findEntry(key)) |index| return self.entries.items[index].value;
        return .nil;
    }

    /// Raw read of a string key whose `table_index.hashStringKey` the caller already knows.
    pub inline fn getStringHashed(self: *const Table, key: []const u8, hash: u32) Value {
        if (self.findStringEntry(key, hash)) |index| return self.entries.items[index].value;
        return .nil;
    }

    pub inline fn getLiteral(self: *const Table, comptime key: []const u8) Value {
        return self.getStringHashed(key, comptime table_index.hashStringKey(key));
    }

    pub fn getBytes(self: *const Table, key: []const u8) Value {
        return self.getStringHashed(key, table_index.hashStringKey(key));
    }

    pub inline fn findStringEntry(self: *const Table, key: []const u8, hash: u32) ?usize {
        if (self.entry_index.capacity() != 0) return self.entry_index.findBytes(self.entries.items, key, hash);
        for (self.entries.items, 0..) |entry, index| {
            if (entry.key == .string and entry.key.string.eqlBytes(key)) return index;
        }
        return null;
    }

    pub inline fn findStringKey(self: *const Table, key: *const String) ?usize {
        if (self.entry_index.capacity() != 0) return self.entry_index.find(self.entries.items, .{ .string = key }, key.tableHash());
        for (self.entries.items, 0..) |entry, index| {
            if (entry.key == .string and key.eql(entry.key.string)) return index;
        }
        return null;
    }

    pub inline fn metaEventAbsent(self: *const Table, event: MetaEvent) bool {
        return self.metamethod_absent & event.bit() != 0;
    }

    /// Raw lookup of a metamethod in this metatable, caching absence.
    pub fn metaEvent(self: *Table, event: MetaEvent) Value {
        if (self.metaEventAbsent(event)) return .nil;
        const value = switch (event) {
            inline else => |tag| self.getStringHashed(@tagName(tag), comptime table_index.hashStringKey(@tagName(tag))),
        };
        if (value == .nil) self.metamethod_absent |= event.bit();
        return value;
    }

    /// Call before writing a hash slot that may currently hold nil.
    pub inline fn invalidateMetaEvents(self: *Table) void {
        self.metamethod_absent = 0;
    }

    pub fn findEntry(self: *const Table, key: Value) ?usize {
        if (key == .string) return self.findStringKey(key.string);
        if (self.entry_index.capacity() != 0) return self.entry_index.find(self.entries.items, key, table_index.hashKey(key));
        for (self.entries.items, 0..) |entry, index| {
            if (value_mod.valuesEqual(entry.key, key)) return index;
        }
        return null;
    }

    pub fn rebuildEntryIndex(self: *Table, allocator: std.mem.Allocator) !void {
        if (self.entry_index.capacity() == 0 and self.entries.items.len <= linear_entry_limit) return;
        try self.entry_index.rebuild(allocator, self.entries.items);
    }

    /// Insert an absent hash key using reserved storage. The caller must check
    /// that the key is absent; false means growth or snapshot detachment is needed.
    pub fn insertHashEntryNoAlloc(self: *Table, key: Value, value: Value) bool {
        if (self.rollback) |record| if (!record.header.detached) return false;
        if (value == .nil) return true;
        if (self.entry_index.capacity() != 0 or self.entries.items.len >= linear_entry_limit or
            self.entries.items.len == self.entries.capacity) return false;
        self.invalidateMetaEvents();
        self.entries.appendAssumeCapacity(.{ .key = key, .value = value });
        return true;
    }

    pub fn set(self: *Table, allocator: std.mem.Allocator, key: Value, value: Value) !void {
        try @import("rollback.zig").tableWritable(self);
        if (value_mod.arrayIndex(key)) |index| {
            if (index <= self.array.items.len) {
                self.array.items[index - 1] = value;
                return;
            }
            if (value != .nil and index == self.array.items.len + 1) {
                try self.array.append(allocator, value);
                self.removeHashKey(key);
                return;
            }
            if (value != .nil and index <= self.array.capacity) {
                const old_len = self.array.items.len;
                try self.array.resize(allocator, index);
                @memset(self.array.items[old_len..], .nil);
                self.array.items[index - 1] = value;
                self.removeHashKey(key);
                return;
            }
        }
        self.invalidateMetaEvents();
        if (self.findEntry(key)) |index| {
            self.entries.items[index].value = value;
            return;
        }
        if (value != .nil) {
            // Reserve everything first so allocation failure cannot leave a partial index.
            try self.entries.ensureUnusedCapacity(allocator, 1);
            if (self.entry_index.capacity() == 0 and self.entries.items.len == linear_entry_limit) {
                try self.entry_index.rebuild(allocator, self.entries.items);
            }
            if (self.entry_index.capacity() != 0) {
                try self.entry_index.ensureUnusedCapacity(allocator, 1);
                self.entry_index.insertAssumeCapacity(table_index.hashKey(key), self.entries.items.len);
            }
            self.entries.appendAssumeCapacity(.{ .key = key, .value = value });
        }
    }

    pub fn setExistingNonNil(self: *Table, key: Value, value: Value) bool {
        if (self.rollback) |record| if (!record.header.detached) return false;
        if (value_mod.arrayIndex(key)) |index| {
            if (index <= self.array.items.len and self.array.items[index - 1] != .nil) {
                self.array.items[index - 1] = value;
                return true;
            }
            return false;
        }
        if (self.findEntry(key)) |index| {
            if (self.entries.items[index].value == .nil) return false;
            self.entries.items[index].value = value;
            return true;
        }
        return false;
    }

    pub fn len(self: *Table) i64 {
        var border = self.array.items.len;
        while (border > 0 and self.array.items[border - 1] == .nil) border -= 1;
        if (border != self.array.items.len) self.trimArray(border);
        if (self.entries.items.len == 0) return @intCast(border);
        while (border < std.math.maxInt(i64)) {
            const next_index = border + 1;
            if (self.get(.{ .integer = @intCast(next_index) }) == .nil) break;
            border = next_index;
        }
        return @intCast(border);
    }

    fn trimArray(self: *Table, border: usize) void {
        if (self.rollback) |record| if (!record.header.detached) return;
        self.array.items.len = border;
    }

    pub fn next(self: *const Table, key: Value) ![2]Value {
        if (key == .nil) return self.firstEntryAfterArray(0);
        const array_index = value_mod.arrayIndex(key);
        if (array_index) |index| {
            if (index <= self.array.items.len) return self.firstEntryAfterArray(index);
        }
        if (self.findEntry(key)) |index| {
            return self.firstHashEntryFrom(index + 1);
        }
        if (array_index) |index| {
            if (index <= self.array.capacity) return self.firstHashEntryFrom(0);
        }
        return error.RuntimeError;
    }

    fn firstEntryAfterArray(self: *const Table, index: usize) [2]Value {
        var next_index = index;
        while (next_index < self.array.items.len) {
            next_index += 1;
            const value = self.array.items[next_index - 1];
            if (value != .nil) return .{ .{ .integer = @intCast(next_index) }, value };
        }
        return self.firstHashEntryFrom(0);
    }

    fn firstHashEntryFrom(self: *const Table, start: usize) [2]Value {
        var index = start;
        while (index < self.entries.items.len) : (index += 1) {
            const entry = self.entries.items[index];
            if (entry.value != .nil) return .{ entry.key, entry.value };
        }
        return .{ .nil, .nil };
    }

    pub fn removeHashKey(self: *Table, key: Value) void {
        if (self.entries.items.len == 0) return;
        if (self.findEntry(key)) |index| self.removeEntryAt(index);
    }

    /// Removes one entry, keeping the order of the rest for `next`.
    pub fn removeEntryAt(self: *Table, index: usize) void {
        std.mem.copyForwards(TableEntry, self.entries.items[index .. self.entries.items.len - 1], self.entries.items[index + 1 ..]);
        self.entries.items.len -= 1;
        self.reindexEntries();
    }

    /// Restores the index after entries were removed or moved. Never allocates,
    /// since the index already holds at least as many slots as entries.
    pub fn reindexEntries(self: *Table) void {
        if (self.entry_index.capacity() == 0) return;
        self.entry_index.clearRetainingCapacity();
        for (self.entries.items, 0..) |entry, position| self.entry_index.insertAssumeCapacity(table_index.hashKey(entry.key), position);
    }
};

pub const UserdataScope = struct {
    userdata: *Userdata,
    readonly: bool,
    previous: ?*UserdataScope,
};

/// Values a native function holds outside the Lua stack while it runs Lua
/// code. The collector marks them until the scope is popped.
pub const ValueRoots = struct {
    values: []const Value,
    previous: ?*ValueRoots,
};

pub const Userdata = struct {
    gc: GcHeader = .{},
    scope_readers: usize = 0,
    scope_writers: usize = 0,
    rollback: ?*@import("rollback.zig").Record(Userdata) = null,
    payload: ?*UserdataPayload = null,
    ptr: *anyopaque,
    type_id: usize,
    type_name: []const u8,
    metatable: ?*Table = null,
    finalizer: ?UserdataFinalizer = null,
    finalizer_data: ?*const anyopaque = null,
    deinit_fn: ?UserdataDeinit = null,
    finalized: bool = false,
    finalization_pending: bool = false,
    finalizer_next: ?*Userdata = null,
    /// Registered for its metatable's `__gc`, like `Table.finalizer_registered`.
    lua_finalizer_registered: bool = false,
    /// Registration order on the `Table.finalizer_order` scale, then the
    /// position in the finalizer queue once separated.
    lua_finalizer_order: u64 = 0,
    lua_finalizer_next: ?*Userdata = null,
};

/// An object separated for a Lua `__gc` call.
pub const FinalizerObject = union(enum) {
    table: *Table,
    userdata: *Userdata,

    pub fn order(self: FinalizerObject) u64 {
        return switch (self) {
            .table => |table| table.finalizer_order,
            .userdata => |userdata| userdata.lua_finalizer_order,
        };
    }
};

pub const Thread = struct {
    gc: GcHeader = .{},
    rollback: ?*@import("rollback.zig").Record(Thread) = null,
    /// A Lua value has exposed this thread beyond its current host call.
    exposed: bool = false,
    stack: std.ArrayList(Value) = .empty,
    frames: std.ArrayList(CallFrame) = .empty,
    yield_values: std.ArrayList(Value) = .empty,
    protected_continuations: std.ArrayList(ProtectedContinuation) = .empty,
    generic_for_continuations: std.ArrayList(GenericForContinuation) = .empty,
    pairs_continuations: std.ArrayList(PairsContinuation) = .empty,
    continuation_order: usize = 0,
    tail_call_continuations: std.ArrayList(TailCallContinuation) = .empty,
    call_one_continuations: std.ArrayList(CallOneContinuation) = .empty,
    /// Largest `frame_count` among the pending continuations. Every push calls
    /// `noteContinuation`; every removal calls `refreshContinuationFrameCount`.
    continuation_frame_count: usize = 0,
    open_upvalues: ?*Upvalue = null,
    hook: Value = .nil,
    hook_call: bool = false,
    hook_line: bool = false,
    hook_return: bool = false,
    hook_count: u32 = 0,
    hook_count_remaining: u32 = 0,
    hook_running: bool = false,
    hook_return_name: ?[]const u8 = null,
    hook_level2_func: Value = .nil,
    hook_transfer_index_base: i64 = 0,
    hook_transfer_stack_base: usize = 0,
    hook_transfer_count: usize = 0,
    hook_transfer_values: []const Value = &.{},
    next_call_name: ?[]const u8 = null,
    next_call_namewhat: ?[]const u8 = null,
    pending_yield_hook_return: bool = false,
    last_result_base: usize = 0,
    last_result_count: usize = 0,
    last_transfer_base: usize = 0,
    last_transfer_count: usize = 0,
    yield_result_base: usize = 0,
    yield_result_count: u16 = 0,
    native_call_depth: usize = 0,
    native_call: ?NativeCall = null,
    protected_close_depth: usize = 0,
    /// Message handler for errors raised on this thread, like `L->errfunc`.
    error_handler: Value = .nil,
    /// Set after a stack overflow so a message handler can still run on top
    /// of the full stack; cleared once the stack unwinds below the limit.
    stack_error_space: bool = false,
    /// Tracebacks end with the `[C]: in ?` entry of a standalone host call.
    host_frame: bool = false,
    /// Native functions with no calling instruction (called by `xpcall` or a message
    /// handler) still live while a message handler runs, oldest first, for tracebacks.
    native_marks: [4]NativeMark = undefined,
    native_mark_count: u8 = 0,
    close_error_value: ?Value = null,
    error_traceback: ?*const String = null,
    pending_unwind_error: ?Value = null,
    pending_unwind_resume_frame_count: usize = 0,
    pending_unwind_target_frame_count: usize = 0,
    /// Bytes of owned varargs and pending returns held by this thread's frames.
    frame_storage_bytes: usize = 0,
    /// Capacity bytes last reported to the collector.
    storage_bytes: usize = 0,
    resume_parent: ?*Thread = null,
    entry: Value = .nil,
    started: bool = false,
    is_main: bool = false,
    closing: bool = false,
    status: ThreadStatus = .suspended,

    pub fn initRoot(allocator: std.mem.Allocator, closure: *Closure, stack_value_limit: usize) !Thread {
        var thread = Thread{};
        thread.entry = .{ .closure = closure };
        thread.started = true;
        thread.is_main = true;
        thread.status = .running;
        errdefer thread.deinit(allocator);
        const proto = closure.proto;
        try thread.ensureStack(allocator, @max(proto.max_registers, 1), stack_value_limit);
        try thread.frames.append(allocator, .{ .closure = closure, .proto = proto, .base = 0, .pc = 0, .return_start = 0, .return_count = 0, .varargs = &.{} });
        return thread;
    }

    pub fn initCoroutine(entry: Value) Thread {
        return .{ .entry = entry, .status = .suspended };
    }

    pub fn deinit(self: *Thread, allocator: std.mem.Allocator) void {
        for (self.frames.items) |*frame| frame.deinit(allocator);
        self.yield_values.deinit(allocator);
        self.protected_continuations.deinit(allocator);
        self.generic_for_continuations.deinit(allocator);
        self.pairs_continuations.deinit(allocator);
        self.tail_call_continuations.deinit(allocator);
        self.call_one_continuations.deinit(allocator);
        self.frames.deinit(allocator);
        self.stack.deinit(allocator);
        self.* = undefined;
    }

    pub fn releaseFrame(self: *Thread, frame: *CallFrame, allocator: std.mem.Allocator) void {
        self.frame_storage_bytes -= frame.storageBytes();
        frame.deinit(allocator);
    }

    pub fn noteContinuation(self: *Thread, frame_count: usize) void {
        self.continuation_frame_count = @max(self.continuation_frame_count, frame_count);
    }

    pub fn refreshContinuationFrameCount(self: *Thread) void {
        var result: usize = 0;
        for (self.pairs_continuations.items) |continuation| result = @max(result, continuation.frame_count);
        for (self.call_one_continuations.items) |continuation| result = @max(result, continuation.frame_count);
        for (self.protected_continuations.items) |continuation| result = @max(result, continuation.context.frame_count);
        for (self.tail_call_continuations.items) |continuation| result = @max(result, continuation.frame_count);
        for (self.generic_for_continuations.items) |continuation| result = @max(result, continuation.frame_count);
        self.continuation_frame_count = result;
    }

    pub fn ensureStack(self: *Thread, allocator: std.mem.Allocator, size: usize, limit: usize) !void {
        if (size > limit) return error.StackOverflow;
        const old_len = self.stack.items.len;
        if (size <= old_len) return;
        try self.stack.resize(allocator, size);
        @memset(self.stack.items[old_len..], .nil);
    }

    /// Register, relative to the top frame, for calls the runtime makes itself: above
    /// the frame's registers and any running native function's arguments.
    pub fn scratchRegister(self: *const Thread) u32 {
        const frame_count = self.frames.items.len;
        const registers = self.frames.items[frame_count - 1].proto.max_registers;
        const call = self.native_call orelse return registers;
        if (call.frame_count != frame_count) return registers;
        return @max(registers, call.base + 1 + call.arg_count);
    }
};

pub const ThreadStatus = enum {
    suspended,
    running,
    normal,
    dead,
};

/// The innermost native function running on a thread. Library errors use it like
/// `luaL_argerror` and `luaL_where` use the C call stack.
pub const NativeCall = struct {
    /// Callee register, relative to the frame on top when it was called.
    base: u32,
    arg_count: u32,
    /// Arguments prepended by `__call` metamethods, like `lua_Debug.extraargs`.
    extra_args: u8 = 0,
    frame_count: usize,
    /// Called by another native function (like `pcall(f)`) rather than Lua code.
    from_native: bool,
    /// Frame count of the enclosing native call, if any.
    outer_frame_count: ?usize = null,
    /// Static name for calls not made by CALL instructions, such as metamethods and `__close`.
    name: ?[]const u8 = null,
    namewhat: ?[]const u8 = null,
};

pub const CallFrame = struct {
    closure: *Closure,
    proto: *const proto_mod.Proto,
    base: usize,
    pc: usize,
    return_start: usize,
    return_count: u16,
    varargs: []const Value,
    owns_varargs: bool = false,
    vararg_table_local: Value = .nil,
    named_vararg_readonly: bool = false,
    last_hook_line: ?usize = null,
    debug_name_override: ?[]const u8 = null,
    debug_namewhat_override: ?[]const u8 = null,
    is_tail_call: bool = false,
    pending_returns: ?[]Value = null,

    pub fn storageBytes(self: CallFrame) usize {
        const varargs = if (self.owns_varargs) self.varargs.len else 0;
        const returns = if (self.pending_returns) |values| values.len else 0;
        return (varargs + returns) * @sizeOf(Value);
    }

    pub fn deinit(self: *CallFrame, allocator: std.mem.Allocator) void {
        if (self.owns_varargs) allocator.free(self.varargs);
        if (self.pending_returns) |returns| allocator.free(returns);
        self.varargs = &.{};
        self.owns_varargs = false;
        self.pending_returns = null;
    }
};

/// Hashes object addresses, which are distinct and aligned, without Wyhash.
pub const AddressContext = struct {
    pub fn hash(_: AddressContext, address: usize) u64 {
        const product = @as(u64, address >> 3) *% 0x9e3779b97f4a7c15;
        return product ^ (product >> 32);
    }

    pub fn eql(_: AddressContext, lhs: usize, rhs: usize) bool {
        return lhs == rhs;
    }
};

pub const GcColor = enum(u8) { white, gray, black };
pub const GcAge = enum(u8) { new, survivor, old };

/// Collector state embedded in every collectable object.
pub const GcHeader = extern struct {
    pub const untracked = std.math.maxInt(u32);

    /// Collector epoch of the last mark; `color` is stale when it differs.
    epoch: u64 = 0,
    /// Collector generation at allocation; any older generation means old.
    generation: u64 = 0,
    /// Position in this type's registry; `untracked` for strings and objects the collector doesn't own.
    registry_index: u32 = untracked,
    color: GcColor = .white,
    age: GcAge = .new,
    /// In `Gc.remembered`.
    remembered: bool = false,
    /// Referenced a young object when last traced.
    has_young: bool = false,
};

/// Queue entries own identities, never pointers into growable registries.
pub const GcObject = union(enum) {
    table: *Table,
    userdata: *Userdata,
    closure: *Closure,
    upvalue: *Upvalue,
    thread: *Thread,
};

pub const GcPhase = enum { pause, propagate, atomic, sweep_threads, sweep_closures, sweep_upvalues, sweep_strings, sweep_userdata, sweep_tables, finalize };
pub const GcCycle = enum { major, minor };
pub const GcGenerations = struct {
    string_allocations: usize = 0,
    table_allocations: usize = 0,
    userdata_allocations: usize = 0,
    closure_allocations: usize = 0,
    upvalue_allocations: usize = 0,
    thread_allocations: usize = 0,
};

pub const GcMode = enum {
    incremental,
    generational,

    pub fn name(self: GcMode) []const u8 {
        return switch (self) {
            .incremental => "incremental",
            .generational => "generational",
        };
    }
};

pub const GcParam = enum {
    minormul,
    majorminor,
    minormajor,
    pause,
    stepmul,
    stepsize,
};

/// Collection tuning. Values are percentages except `stepsize`, in bytes. The Zig API accepts
/// 0 through maxInt(i32) without the rounding `collectgarbage("param", ...)` applies.
pub const GcParams = struct {
    /// Heap growth before the next minor collection.
    minormul: i64 = 20,
    /// Percentage of heap growth a major collection must reclaim to return to minor collections.
    majorminor: i64 = 50,
    /// Heap growth since the last major collection before another is requested; zero disables the transition.
    minormajor: i64 = 70,
    /// Heap size relative to the last collection before starting another full cycle.
    pause: i64 = 250,
    /// Work multiplier for each step.
    stepmul: i64 = 200,
    /// Allocation between steps, in bytes; also used to determine step work.
    stepsize: i64 = 200,

    pub fn get(self: GcParams, param: GcParam) i64 {
        return switch (param) {
            .minormul => self.minormul,
            .majorminor => self.majorminor,
            .minormajor => self.minormajor,
            .pause => self.pause,
            .stepmul => self.stepmul,
            .stepsize => self.stepsize,
        };
    }

    pub fn set(self: *GcParams, param: GcParam, value: i64) void {
        switch (param) {
            .minormul => self.minormul = value,
            .majorminor => self.majorminor = value,
            .minormajor => self.minormajor = value,
            .pause => self.pause = value,
            .stepmul => self.stepmul = value,
            .stepsize => self.stepsize = value,
        }
    }
};

pub const WeakMode = struct {
    keys: bool = false,
    values: bool = false,
};

pub const RuntimeAllocationStats = struct {
    strings: usize,
    tables: usize,
    closures: usize,
    upvalues: usize,
    threads: usize,
    bytes: usize,

    pub fn total(self: RuntimeAllocationStats) usize {
        return self.bytes;
    }
};
