const std = @import("std");
const api = @import("../api.zig");

pub fn expectString(expected: []const u8, result: anyerror!api.String) !void {
    var string = try result;
    defer string.deinit();
    try std.testing.expectEqualStrings(expected, try string.bytes());
}

/// The Lua error `result` failed with; the caller must `deinit` it.
pub fn takeError(state: *api.State, result: anytype) !api.ErrorRef {
    if (result) |_| return error.TestExpectedLuaError else |err| if (err != error.LuaError) return err;
    return state.takeError() orelse error.TestExpectedLuaError;
}

pub fn callError(function: api.Function, args: anytype, comptime R: type) !api.ErrorRef {
    return takeError(function.ref.state, function.call(args, R));
}

pub fn callErrorWith(function: api.Function, args: anytype, comptime R: type, options: api.CallOptions) !api.ErrorRef {
    return takeError(function.ref.state, function.callWith(args, R, options));
}

/// The caller frees the result with the state's allocator.
pub fn errorMessage(error_ref: api.ErrorRef) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(error_ref.ref.state.allocator());
    defer out.deinit();
    try error_ref.writeMessage(&out.writer);
    return out.toOwnedSlice();
}

/// The caller frees the result with the state's allocator.
pub fn describeError(state: *api.State, err: anyerror) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(state.allocator());
    defer out.deinit();
    try state.writeError(err, &out.writer);
    return out.toOwnedSlice();
}

/// The caller frees the result with the state's allocator.
pub fn dumpBytecode(function: api.Function, options: api.BytecodeDumpOptions) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(function.ref.state.allocator());
    defer out.deinit();
    try function.dumpBytecode(&out.writer, options);
    return out.toOwnedSlice();
}
