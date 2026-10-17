const std = @import("std");
const reflection = @import("../reflection.zig");
const runtime = @import("../runtime.zig");
const rollback_runtime = @import("../runtime/rollback.zig");
const runtime_types = @import("../runtime/types.zig");
const callbacks = @import("callbacks.zig");
const convert = @import("convert.zig");
const errors = @import("errors.zig");
const handle = @import("handle.zig");
const state_mod = @import("state.zig");
const Context = @import("context.zig").Context;
const Ref = handle.Ref;
const State = state_mod.State;
const Table = @import("table.zig").Table;
const index_mod = @import("../runtime/index.zig");
const metatable_mod = @import("../runtime/metatable.zig");

pub fn UserdataOptions(comptime T: type) type {
    return struct {
        /// Shared metatable used instead of allocating one; install methods before sharing it.
        metatable: ?Table = null,
        /// Runs before Lua-owned storage is destroyed.
        finalizer: ?*const fn (*T) void = null,
        snapshot: ?UserdataSnapshotHooks(T) = null,
    };
}

pub fn UserdataPtrOptions(comptime T: type) type {
    return struct {
        /// Shared metatable used instead of allocating one.
        metatable: ?Table = null,
        /// Runs when the Lua userdata wrapper is finalized.
        finalizer: ?*const fn (*T) void = null,
        snapshot: ?UserdataSnapshotHooks(T) = null,
    };
}

/// Snapshot copy/dispose hooks for userdata payloads. Copies must own all nested storage and
/// must not retain VM pointers or reenter snapshot operations. Hooks must be thread-safe:
/// concurrent `Snapshot.newState` calls may copy one payload, and disposal runs on any thread.
pub fn UserdataSnapshotHooks(comptime T: type) type {
    return struct {
        copy: *const fn (std.mem.Allocator, *const T) anyerror!*T,
        dispose: *const fn (std.mem.Allocator, *T) void,
        /// Eager resources copy on every reset; scoped resources copy on first mutable access.
        tracking: enum { eager, scoped } = .eager,
    };
}

/// Typed userdata handle for payload type `T`.
pub fn Userdata(comptime T: type) type {
    return struct {
        /// Marker for zlua's compile-time conversions.
        pub const is_zlua_userdata = true;
        pub const ValueType = T;

        ref: Ref,

        pub fn deinit(self: *@This()) void {
            self.ref.deinit();
            self.* = undefined;
        }

        pub fn ptr(self: @This()) !*T {
            return payloadPtr(T, try self.rawUserdata());
        }

        /// Scoped read-only access; the payload and nested pointers must not escape or be mutated.
        pub fn withRead(self: @This(), context: anytype, comptime callback: anytype) !ScopeResult(@TypeOf(callback)) {
            comptime checkScopeResult(ScopeResult(@TypeOf(callback)));
            const raw = try self.rawUserdata();
            var scope: runtime_types.UserdataScope = undefined;
            try beginScope(&self.ref.state.raw_state, &scope, raw, true);
            defer endScope(&self.ref.state.raw_state, &scope);
            const pointer: *const T = @ptrCast(@alignCast(raw.ptr));
            return @call(.auto, callback, .{ pointer, context });
        }

        /// Scoped mutable access, preserving the snapshot baseline first. Errors do not undo writes.
        pub fn withMut(self: @This(), context: anytype, comptime callback: anytype) !ScopeResult(@TypeOf(callback)) {
            comptime checkScopeResult(ScopeResult(@TypeOf(callback)));
            const raw = try self.rawUserdata();
            var scope: runtime_types.UserdataScope = undefined;
            try beginScope(&self.ref.state.raw_state, &scope, raw, false);
            defer endScope(&self.ref.state.raw_state, &scope);
            const pointer: *T = @ptrCast(@alignCast(raw.ptr));
            return @call(.auto, callback, .{ pointer, context });
        }

        /// Installs a Zig method on `__index`; its first parameter must be a pointer to `T`.
        pub fn method(self: @This(), name: []const u8, comptime function: anytype) !void {
            try handle.validate(self.ref, self.ref.state);
            const Wrapper = struct {
                fn call(ctx: *Context) !void {
                    try callbacks.callUserdataMethod(T, function, ctx);
                }
            };

            const callback_name = try std.fmt.allocPrint(self.ref.state.allocator(), "{s}.{s}", .{ @typeName(T), name });
            defer self.ref.state.allocator().free(callback_name);

            var method_function = try callbacks.create(self.ref.state, callback_name, Wrapper.call);
            defer method_function.deinit();

            const metatable = try self.metatableValue();
            const index_key = runtime.Value{ .string = try self.ref.state.raw_state.strings.intern("__index") };
            var index_value = metatable.table.get(index_key);
            if (index_value == .nil) {
                index_value = self.ref.state.raw_state.newTableWithHints(0, 4) catch |err| return errors.captureLuaError(self.ref.state, err);
                try self.ref.state.raw_state.setTableRaw(metatable.table, index_key, index_value);
                index_mod.setTableValue(&self.ref.state.raw_state, metatable, index_key, index_value) catch |err| return errors.captureLuaError(self.ref.state, err);
            }
            if (index_value != .table) return error.TypeMismatch;
            try index_mod.setTableValue(&self.ref.state.raw_state, index_value, .{ .string = try self.ref.state.raw_state.strings.intern(name) }, try handle.rawValue(method_function.ref));
        }

        /// Installs `Source` methods as in `State.newUserdataAuto`.
        pub fn bindMethods(self: @This(), comptime Source: type) !void {
            try handle.validate(self.ref, self.ref.state);
            if (@typeInfo(Source) != .@"struct") @compileError("bindMethods requires a struct type");

            inline for (reflection.declarationNames(Source)) |decl| {
                const member = @field(Source, decl);
                if (comptime isMethod(T, @TypeOf(member))) {
                    if (comptime isMetamethodName(decl)) {
                        try self.metamethod(decl, member);
                    } else {
                        try self.method(decl, member);
                    }
                }
            }
        }

        /// Installs a typed Zig function as a metamethod such as `__close`.
        pub fn metamethod(self: @This(), name: []const u8, comptime function: anytype) !void {
            try handle.validate(self.ref, self.ref.state);
            const Wrapper = struct {
                fn call(ctx: *Context) !void {
                    try callbacks.callUserdataMethod(T, function, ctx);
                }
            };

            const callback_name = try std.fmt.allocPrint(self.ref.state.allocator(), "{s}.{s}", .{ @typeName(T), name });
            defer self.ref.state.allocator().free(callback_name);

            var metamethod_function = try callbacks.create(self.ref.state, callback_name, Wrapper.call);
            defer metamethod_function.deinit();

            const metatable = try self.metatableValue();
            try index_mod.setTableValue(&self.ref.state.raw_state, metatable, .{ .string = try self.ref.state.raw_state.strings.intern(name) }, try handle.rawValue(metamethod_function.ref));
            if (std.mem.eql(u8, name, "__gc")) self.ref.state.raw_state.gc.checkUserdataFinalizer(try self.rawUserdata());
        }

        fn initMetatable(self: @This()) !void {
            const raw = try self.rawUserdata();
            if (raw.metatable != null) return;
            const metatable = self.ref.state.raw_state.newTableWithHints(0, 3) catch |err| return errors.captureLuaError(self.ref.state, err);
            const index = self.ref.state.raw_state.newTableWithHints(0, 4) catch |err| return errors.captureLuaError(self.ref.state, err);
            try self.ref.state.raw_state.setTableRaw(metatable.table, .{ .string = try self.ref.state.raw_state.strings.intern("__name") }, .{ .string = try self.ref.state.raw_state.strings.intern(@typeName(T)) });
            try self.ref.state.raw_state.setTableRaw(metatable.table, .{ .string = try self.ref.state.raw_state.strings.intern("__index") }, index);
            rollback_runtime.touch(raw);
            try metatable_mod.setDebugMetatableValue(&self.ref.state.raw_state, .{ .userdata = raw }, metatable);
        }

        fn rawUserdata(self: @This()) !*runtime.Userdata {
            return switch (try handle.rawValue(self.ref)) {
                .userdata => |userdata| userdata,
                else => error.TypeMismatch,
            };
        }

        fn metatableValue(self: @This()) !runtime.Value {
            const raw = try self.rawUserdata();
            const metatable = raw.metatable orelse return error.TypeMismatch;
            return .{ .table = metatable };
        }
    };
}

/// Rooted userdata handle with an unknown payload type.
pub const AnyUserdata = struct {
    ref: Ref,

    pub fn deinit(self: *AnyUserdata) void {
        self.ref.deinit();
        self.* = undefined;
    }

    /// Returns a new typed handle after checking the payload type.
    pub fn as(self: AnyUserdata, comptime T: type) !Userdata(T) {
        return convert.fromRuntimeValue(self.ref.state, try self.rawValue(), Userdata(T));
    }

    fn rawValue(self: AnyUserdata) !runtime.Value {
        const raw = try handle.rawValue(self.ref);
        if (raw != .userdata) return error.TypeMismatch;
        return raw;
    }
};

pub fn create(state: *State, comptime T: type, value: T, options: UserdataOptions(T)) !Userdata(T) {
    const metatable = try sharedMetatable(state, options.metatable);
    const ptr = try state.allocator().create(T);
    ptr.* = value;
    const raw = state.raw_state.newUserdata(ptr, typeId(T), @typeName(T), null, null, userdataDestroy(T)) catch |err| {
        state.allocator().destroy(ptr);
        return err;
    };
    raw.userdata.payload.?.managed_bytes = @sizeOf(T);
    state.raw_state.gc.noteAllocation(@sizeOf(T));
    var userdata = try convert.fromRuntimeValue(state, raw, Userdata(T));
    errdefer userdata.deinit();
    if (metatable) |table| try metatable_mod.setDebugMetatableValue(&state.raw_state, raw, .{ .table = table }) else try userdata.initMetatable();
    raw.userdata.finalizer = userdataFinalizer(T, options.finalizer);
    raw.userdata.finalizer_data = userdataFinalizerData(T, options.finalizer);
    raw.userdata.payload.?.finalizer = raw.userdata.finalizer;
    raw.userdata.payload.?.finalizer_data = raw.userdata.finalizer_data;
    setSnapshotHooks(T, raw.userdata, options.snapshot);
    try state_mod.gcBoundary(state);
    return userdata;
}

pub fn wrapPtr(state: *State, comptime T: type, ptr: *T, options: UserdataPtrOptions(T)) !Userdata(T) {
    if (options.snapshot) |hooks| if (hooks.tracking == .scoped) return error.ScopedAccessRequiresOwnedUserdata;
    const metatable = try sharedMetatable(state, options.metatable);
    const raw = try state.raw_state.newUserdata(ptr, typeId(T), @typeName(T), null, null, null);
    var userdata = try convert.fromRuntimeValue(state, raw, Userdata(T));
    errdefer userdata.deinit();
    if (metatable) |table| try metatable_mod.setDebugMetatableValue(&state.raw_state, raw, .{ .table = table }) else try userdata.initMetatable();
    raw.userdata.finalizer = userdataFinalizer(T, options.finalizer);
    raw.userdata.finalizer_data = userdataFinalizerData(T, options.finalizer);
    raw.userdata.payload.?.finalizer = raw.userdata.finalizer;
    raw.userdata.payload.?.finalizer_data = raw.userdata.finalizer_data;
    setSnapshotHooks(T, raw.userdata, options.snapshot);
    try state_mod.gcBoundary(state);
    return userdata;
}

fn sharedMetatable(state: *State, metatable: ?Table) !?*runtime.Table {
    const table = metatable orelse return null;
    try handle.validate(table.ref, state);
    return switch (try handle.rawValue(table.ref)) {
        .table => |raw| raw,
        else => error.TypeMismatch,
    };
}

fn isMethod(comptime T: type, comptime FunctionType: type) bool {
    const function_info = switch (@typeInfo(FunctionType)) {
        .@"fn" => |info| info,
        .pointer => |pointer| switch (@typeInfo(pointer.child)) {
            .@"fn" => |info| info,
            else => return false,
        },
        else => return false,
    };

    if (reflection.isVariadic(function_info) or reflection.paramTypes(function_info).len == 0) return false;
    const Receiver = reflection.paramTypes(function_info)[0] orelse return false;
    return isReceiver(T, Receiver);
}

pub fn isReceiver(comptime T: type, comptime Receiver: type) bool {
    return Receiver == *T or Receiver == *const T;
}

fn isMetamethodName(comptime name: []const u8) bool {
    return std.mem.startsWith(u8, name, "__");
}

pub fn beginScope(state: *runtime.State, scope: *runtime_types.UserdataScope, userdata: *runtime.Userdata, readonly: bool) !void {
    if ((readonly and userdata.scope_writers != 0) or (!readonly and userdata.scope_readers != 0)) return error.ScopedAccessConflict;
    scope.* = .{ .userdata = userdata, .readonly = readonly, .previous = state.userdata_scope };
    state.userdata_scope = scope;
    if (readonly) userdata.scope_readers += 1 else userdata.scope_writers += 1;
    errdefer endScope(state, scope);
    if (!readonly) try rollback_runtime.userdataWritable(userdata);
}

pub fn endScope(state: *runtime.State, scope: *runtime_types.UserdataScope) void {
    std.debug.assert(state.userdata_scope == scope);
    state.userdata_scope = scope.previous;
    if (scope.readonly) scope.userdata.scope_readers -= 1 else scope.userdata.scope_writers -= 1;
}

fn ScopeResult(comptime F: type) type {
    const CallbackType = if (@typeInfo(F) == .pointer) @typeInfo(F).pointer.child else F;
    const R = @typeInfo(CallbackType).@"fn".return_type orelse void;
    return if (@typeInfo(R) == .error_union) @typeInfo(R).error_union.payload else R;
}

fn checkScopeResult(comptime T: type) void {
    switch (@typeInfo(T)) {
        .pointer => @compileError("userdata scope results cannot contain pointers; copy the required value inside the scope"),
        .optional => |o| checkScopeResult(o.child),
        .array => |a| checkScopeResult(a.child),
        .@"struct", .@"union" => inline for (reflection.fieldsOf(T)) |field| checkScopeResult(@FieldType(T, field)),
        else => {},
    }
}

fn TypeToken(comptime T: type) type {
    return struct {
        const ValueType = T;
        var id: u8 = 0;
    };
}

pub fn typeId(comptime T: type) usize {
    return @intFromPtr(&TypeToken(T).id);
}

fn setSnapshotHooks(comptime T: type, raw: *runtime.Userdata, hooks: ?UserdataSnapshotHooks(T)) void {
    if (hooks) |h| {
        raw.payload.?.snapshot_copy = @ptrCast(h.copy);
        raw.payload.?.snapshot_dispose = @ptrCast(h.dispose);
        raw.payload.?.snapshot_tracking = if (h.tracking == .scoped) .scoped else .eager;
        if (h.tracking == .scoped) {
            // Scoped storage shares one disposal contract for originals and copies.
            raw.payload.?.dispose = @ptrCast(h.dispose);
            raw.payload.?.is_snapshot_copy = true;
        }
    }
}

pub fn payloadPtr(comptime T: type, raw: *runtime.Userdata) !*T {
    if (raw.type_id != typeId(T)) return error.TypeMismatch;
    if (raw.payload) |p| if (p.snapshot_tracking == .scoped) return error.ScopedAccessRequired;
    return @ptrCast(@alignCast(raw.ptr));
}

fn userdataFinalizer(comptime T: type, finalizer: ?*const fn (*T) void) ?runtime.UserdataFinalizer {
    if (finalizer == null) return null;
    return struct {
        fn call(ptr: *anyopaque, data: ?*const anyopaque) void {
            const typed_finalizer: *const fn (*T) void = @ptrCast(@alignCast(data.?));
            typed_finalizer(@ptrCast(@alignCast(ptr)));
        }
    }.call;
}

fn userdataFinalizerData(comptime T: type, finalizer: ?*const fn (*T) void) ?*const anyopaque {
    return if (finalizer) |active| @ptrCast(active) else null;
}

fn userdataDestroy(comptime T: type) runtime.UserdataDeinit {
    return struct {
        fn destroy(allocator: std.mem.Allocator, ptr: *anyopaque) void {
            allocator.destroy(@as(*T, @ptrCast(@alignCast(ptr))));
        }
    }.destroy;
}

pub fn isHandle(comptime T: type) bool {
    return switch (@typeInfo(T)) {
        .@"struct" => @hasDecl(T, "is_zlua_userdata") and T.is_zlua_userdata,
        else => false,
    };
}
