const std = @import("std");
const compile = @import("../compile.zig");
const errors = @import("../errors.zig");
const frontend = @import("../frontend.zig");
const process = @import("../testing/process.zig");
const state_mod = @import("state.zig");

pub const ExecuteOptions = struct {
    stress_collect: bool = false,
    stress_step: bool = false,
    state: state_mod.StateOptions = .{},
};

pub fn executeSource(allocator: std.mem.Allocator, source: []const u8) !process.ProcessResult {
    return executeSourceWithOptions(allocator, source, .{});
}

pub fn executeSourceWithOptions(allocator: std.mem.Allocator, source: []const u8, options: ExecuteOptions) !process.ProcessResult {
    var diagnostic: ?errors.Diagnostic = null;
    var tree = frontend.parseWithDiagnostic(allocator, source, &diagnostic) catch {
        return sourceFailureResult(allocator, source, diagnostic, "cannot load source");
    };
    defer tree.deinit();

    compile.resolver.resolveWithDiagnostic(allocator, &tree, &diagnostic) catch {
        return sourceFailureResult(allocator, source, diagnostic, "cannot resolve source");
    };

    var proto = compile.compileWithDiagnostic(allocator, &tree, &diagnostic) catch {
        return sourceFailureResult(allocator, source, diagnostic, "cannot compile source");
    };
    defer proto.deinit();

    var state = try state_mod.State.initWithOptions(allocator, options.state);
    defer state.deinit();
    state.stress_collect = options.stress_collect;
    state.stress_step = options.stress_step;
    if (options.stress_step) {
        state.gc_major_pending = true;
        state.gc_params.stepsize = 8;
        state.gc_params.stepmul = 100;
    }
    state.execute(&proto) catch |err| {
        if (err == error.LuaExit) {
            const request = state.exit_request;
            const code: i32 = if (request != null and request.?.close) closeExitCode(&state) orelse request.?.code else if (request) |exit| exit.code else 0;
            return .{
                .stdout = try allocator.dupe(u8, state.stdout.items),
                .stderr = try allocator.dupe(u8, state.stderr.items),
                .exit_code = exitStatus(code),
                .signal = null,
                .timed_out = false,
            };
        }
        const detail = try state.errorDetailAlloc(allocator, err);
        defer allocator.free(detail);
        const message = try std.fmt.allocPrint(allocator, "{s}\n", .{detail});
        defer allocator.free(message);
        const reported = state.stderr.items.len;
        const close_code = closeExitCode(&state);
        var stderr = std.ArrayList(u8).empty;
        errdefer stderr.deinit(allocator);
        try stderr.appendSlice(allocator, state.stderr.items[0..reported]);
        try stderr.appendSlice(allocator, message);
        try stderr.appendSlice(allocator, state.stderr.items[reported..]);
        return .{
            .stdout = try allocator.dupe(u8, state.stdout.items),
            .stderr = try stderr.toOwnedSlice(allocator),
            .exit_code = exitStatus(close_code orelse 1),
            .signal = null,
            .timed_out = false,
        };
    };

    const close_code = closeExitCode(&state);
    return .{
        .stdout = try allocator.dupe(u8, state.stdout.items),
        .stderr = try allocator.dupe(u8, state.stderr.items),
        .exit_code = exitStatus(close_code orelse 0),
        .signal = null,
        .timed_out = false,
    };
}

fn closeExitCode(state: *state_mod.State) ?i32 {
    state.exit_request = null;
    state.runCloseFinalizers();
    return if (state.exit_request) |exit| exit.code else null;
}

fn exitStatus(code: i32) u8 {
    return @truncate(@as(u32, @bitCast(code)));
}

fn sourceFailureResult(allocator: std.mem.Allocator, source: []const u8, diagnostic: ?errors.Diagnostic, fallback: []const u8) !process.ProcessResult {
    const rendered = if (diagnostic) |diag|
        try errors.renderLoadDiagnostic(allocator, null, source, diag)
    else
        try allocator.dupe(u8, fallback);
    defer allocator.free(rendered);
    const message = try std.fmt.allocPrint(allocator, "{s}\n", .{rendered});
    defer allocator.free(message);
    return process.ownedResult(allocator, "", message, 1);
}
