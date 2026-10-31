const std = @import("std");
const compile = @import("../compile.zig");
const frontend = @import("../frontend.zig");

const resolver = compile.resolver;

/// A read or write of a global variable in a chunk's source.
pub const GlobalUse = struct {
    name: []const u8,
    line: usize,
    access: resolver.GlobalAccess,
};

/// What `analyze` found in a chunk.
pub const Analysis = struct {
    arena: std.heap.ArenaAllocator,
    /// Every use of a global through the chunk's own `_ENV`, in source order.
    globals: []const GlobalUse,

    pub fn deinit(self: *Analysis) void {
        self.arena.deinit();
        self.* = undefined;
    }
};

/// Parses `source` without running it. Returns `error.SyntaxError` for a chunk that doesn't compile;
/// `State.loadString` gives the message.
pub fn analyze(allocator: std.mem.Allocator, source: []const u8) (std.mem.Allocator.Error || error{SyntaxError})!Analysis {
    var tree = frontend.parse(allocator, source) catch |err| return mapError(err);
    defer tree.deinit();

    var uses: std.ArrayList(resolver.GlobalUseSite) = .empty;
    defer uses.deinit(allocator);
    resolver.collectGlobals(allocator, &tree, &uses) catch |err| return mapError(err);

    var arena: std.heap.ArenaAllocator = .init(allocator);
    errdefer arena.deinit();
    const globals = try arena.allocator().alloc(GlobalUse, uses.items.len);
    for (uses.items, globals) |use, *global| {
        global.* = .{
            .name = try arena.allocator().dupe(u8, use.name),
            .line = use.line,
            .access = use.access,
        };
    }
    return .{ .arena = arena, .globals = globals };
}

fn mapError(err: anyerror) (std.mem.Allocator.Error || error{SyntaxError}) {
    return if (err == error.OutOfMemory) error.OutOfMemory else error.SyntaxError;
}
