//! Run: zig build run-example -- snapshot_adversarial
const std = @import("std");
const zlua = @import("zlua");

pub fn main() !void {
    const allocator = std.heap.smp_allocator;
    var lua = try zlua.State.init(allocator, .{ .stdlib = .full });
    defer lua.deinit();
    try lua.doString(
        \\box = {secret = 'baseline'}; box.self = box
        \\alias = box
        \\weak = setmetatable({box}, {__mode = 'v'})
        \\package.loaded.saved = box
        \\local closed = box
        \\function read_closed() return closed.secret end
        \\co = coroutine.create(function()
        \\    local held = box
        \\    coroutine.yield()
        \\    return held.secret
        \\end)
        \\assert(coroutine.resume(co))
    , .{});
    var checkpoint = try lua.snapshot(allocator);
    defer checkpoint.deinit();

    for (0..20) |_| {
        // Even handles acquired before an attack must be revoked by reset.
        var old_table = try lua.getGlobal("box", zlua.Table);
        var old_table_live = true;
        defer if (old_table_live) old_table.deinit();
        var old_function = try lua.getGlobal("read_closed", zlua.Function);
        defer old_function.deinit();
        var old_value = try lua.getGlobal("box", zlua.Value);
        defer old_value.deinit();
        var root_only = try lua.createTable(.{});
        var root_only_live = true;
        defer if (root_only_live) root_only.deinit();
        try root_only.set("secret", "host-root-only");

        try lua.doString(
            \\box.secret = 'discard-me'
            \\box.injected = {secret = 'discard-me'}
            \\escape = box.injected
            \\local stolen = escape
            \\function steal() return stolen.secret end
            \\setmetatable(box, {__index = function() return stolen end})
            \\package.loaded.injected = stolen
            \\weak[2] = stolen
            \\local ok, secret = coroutine.resume(co)
            \\assert(ok and secret == 'discard-me')
            \\assert(read_closed() == 'discard-me' and steal() == 'discard-me')
        , .{});
        var injected = try lua.getGlobal("escape", zlua.Table);
        defer injected.deinit();
        var steal = try lua.getGlobal("steal", zlua.Function);
        defer steal.deinit();
        try rejected(error.LuaError, lua.doString("error(escape)", .{}));
        var old_error = lua.takeErrorValue() orelse return error.MissingError;
        defer old_error.deinit();

        try lua.reset(&checkpoint);

        // Force fresh root allocations before trying the stale handles: an
        // old root index must not grant access to a new generation's object.
        var fresh = try lua.createTable(.{});
        defer fresh.deinit();
        try fresh.set("secret", "new-generation");
        try rejected(error.InvalidHandle, old_table.get("secret", []const u8));
        try rejected(error.InvalidHandle, old_table.set("secret", "poison"));
        try rejected(error.InvalidHandle, injected.get("secret", []const u8));
        try rejected(error.InvalidHandle, root_only.get("secret", []const u8));
        try rejected(error.InvalidHandle, old_function.call(.{}, []const u8));
        try rejected(error.InvalidHandle, steal.call(.{}, []const u8));
        try rejected(error.InvalidHandle, old_error.value());
        try rejected(error.InvalidHandle, lua.setGlobal("smuggled", old_value));
        try rejected(error.InvalidHandle, fresh.set(old_table, true));
        try rejected(error.InvalidHandle, fresh.set("smuggled", injected));
        try rejected(error.InvalidHandle, lua.loadString("return secret", .{ .environment = old_table }));
        var identity = try lua.loadString("return ...", .{});
        defer identity.deinit();
        try rejected(error.InvalidHandle, identity.call(.{injected}, void));

        // Destroying stale roots must not unroot fresh objects, even after GC.
        old_table.deinit();
        old_table_live = false;
        root_only.deinit();
        root_only_live = false;
        try lua.collect();
        try require(std.mem.eql(u8, try fresh.get("secret", []const u8), "new-generation"));
        try lua.doString(
            \\assert(box.secret == 'baseline' and box.self == box and alias == box)
            \\assert(box.injected == nil and getmetatable(box) == nil)
            \\assert(escape == nil and steal == nil and smuggled == nil)
            \\assert(package.loaded.saved == box and package.loaded.injected == nil)
            \\assert(weak[1] == box and weak[2] == nil)
            \\assert(read_closed() == 'baseline')
            \\assert(coroutine.status(co) == 'suspended')
            \\local ok, secret = coroutine.resume(co)
            \\assert(ok and secret == 'baseline')
        , .{});
        // Restore the suspended baseline for the next attack round.
        try lua.reset(&checkpoint);
    }
    std.debug.print("PASS: 20 rounds of stale-handle, root-reuse, closure, coroutine, module, weak-table and metatable probes\n", .{});

    var clone = try checkpoint.clone(allocator);
    defer clone.deinit();
    var foreign = try lua.getGlobal("box", zlua.Table);
    defer foreign.deinit();
    try rejected(error.InvalidHandle, clone.setGlobal("foreign", foreign));
    try clone.doString("box.secret = 'clone-only'", .{});
    try lua.doString("assert(box.secret == 'baseline')", .{});
    try clone.reset(&checkpoint);
    try clone.doString("assert(box.secret == 'baseline')", .{});
    std.debug.print("PASS: cross-state handle injection rejected; clone mutations isolated\n", .{});
    try userdataBoundary(allocator);
}

const Payload = struct {
    value: i64,
    fn copy(allocator: std.mem.Allocator, source: *const Payload) !*Payload {
        const destination = try allocator.create(Payload);
        destination.* = source.*;
        return destination;
    }
    fn dispose(allocator: std.mem.Allocator, payload: *Payload) void {
        allocator.destroy(payload);
    }
};

fn userdataBoundary(allocator: std.mem.Allocator) !void {
    // Host-owned storage outlives both the state and checkpoint.
    var backing = Payload{ .value = 7 };
    var lua = try zlua.State.init(allocator, .{});
    defer lua.deinit();
    var shared = try lua.newUserdataPtr(Payload, &backing, .{});
    defer shared.deinit();
    try lua.setGlobal("shared", shared);
    var copied = try lua.newUserdataPtr(Payload, &backing, .{
        .snapshot = .{ .copy = Payload.copy, .dispose = Payload.dispose },
    });
    defer copied.deinit();
    try lua.setGlobal("copied", copied);
    var checkpoint = try lua.snapshot(allocator);
    defer checkpoint.deinit();
    backing.value = 99;
    try lua.reset(&checkpoint);
    try rejected(error.InvalidHandle, shared.ptr());
    try rejected(error.InvalidHandle, copied.ptr());
    var current_shared = try lua.getGlobal("shared", zlua.Userdata(Payload));
    defer current_shared.deinit();
    var current_copied = try lua.getGlobal("copied", zlua.Userdata(Payload));
    defer current_copied.deinit();
    try require((try current_shared.ptr()).value == 99);
    try require((try current_copied.ptr()).value == 7);
    std.debug.print("PASS: stale userdata handles rejected; copy hook restores payload\n", .{});
    std.debug.print("BOUNDARY: shared host payload remains 99 after reset; reset is not external-state rollback or secure memory erasure\n", .{});
}

fn require(condition: bool) !void {
    if (!condition) return error.ProbeFailed;
}

// Unlike debug assertions, these checks remain active in ReleaseFast builds.
fn rejected(expected: anyerror, result: anytype) !void {
    if (result) |_| {
        return error.AttackUnexpectedlySucceeded;
    } else |actual| {
        if (actual != expected) return actual;
    }
}
