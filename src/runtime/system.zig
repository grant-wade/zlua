const std = @import("std");
const builtin = @import("builtin");
const host = @import("host.zig");
const io_mod = @import("io.zig");
const state_mod = @import("state.zig");
const timezone = @import("timezone.zig");
const types = @import("types.zig");
const upvalue_mod = @import("upvalue.zig");

const State = state_mod.State;
const Clock = std.Io.Clock;
const Dir = std.Io.Dir;
const ProcessResult = host.ProcessResult;
const Thread = types.Thread;

pub fn getenv(self: *State, name: []const u8) ?[]const u8 {
    return switch (self.options.environment) {
        .disabled => null,
        .map => |environment| environment.get(name),
        .custom => |environment| environment.get(environment.context, name),
    };
}

pub fn currentTime(self: *State) !i64 {
    return switch (self.options.clock) {
        .disabled => self.fail("clock access disabled"),
        .fixed => |value| value,
        .system => if (comptime builtin.os.tag == .freestanding) {
            return self.fail("host clock unavailable");
        } else {
            const io = try io_mod.requireIo(self, "clock I/O unavailable");
            return @intCast(@divTrunc(Clock.real.now(io).nanoseconds, std.time.ns_per_s));
        },
        .fixed_local => |clock| clock.now,
        .custom => |clock| clock.now(clock.context) catch return self.fail("clock unavailable"),
    };
}

/// Processor seconds for `os.clock`; 0 for a disabled or fixed clock.
pub fn cpuTime(self: *State) !f64 {
    return switch (self.options.clock) {
        .disabled, .fixed => 0,
        .fixed_local => |clock| clock.cpu_seconds,
        .system => if (comptime builtin.os.tag == .freestanding) {
            return self.fail("host clock unavailable");
        } else {
            const io = try io_mod.requireIo(self, "clock I/O unavailable");
            const nanoseconds: f64 = @floatFromInt(Clock.cpu_process.now(io).nanoseconds);
            return nanoseconds / std.time.ns_per_s;
        },
        .custom => |clock| if (clock.cpu) |cpu| cpu(clock.context) catch return self.fail("clock unavailable") else 0,
    };
}

/// Clocks without a time zone use UTC.
pub fn localOffset(self: *State, timestamp: i64) !timezone.LocalOffset {
    return switch (self.options.clock) {
        .disabled, .fixed => .{},
        .fixed_local => |clock| .{ .offset = clock.utc_offset, .is_dst = clock.is_dst },
        .system => (try systemZone(self)).offsetAt(timestamp),
        .custom => |clock| if (clock.utc_offset) |utc_offset| blk: {
            const result = utc_offset(clock.context, timestamp) catch return self.fail("clock unavailable");
            break :blk .{ .offset = result.offset, .is_dst = result.is_dst };
        } else .{},
    };
}

fn localOffsetCallback(self: *State, timestamp: i64) anyerror!timezone.LocalOffset {
    return localOffset(self, timestamp);
}

/// Converts local wall-clock seconds to a Unix timestamp, like `mktime`.
pub fn localToUtc(self: *State, local: i64, is_dst: ?bool) !i64 {
    return timezone.localToUtc(self, localOffsetCallback, local, is_dst);
}

fn systemZone(self: *State) !*const timezone.Zone {
    if (self.local_zone) |zone| return zone;
    const zone = try self.allocator.create(timezone.Zone);
    errdefer self.allocator.destroy(zone);
    zone.* = try loadSystemZone(self);
    self.local_zone = zone;
    return zone;
}

fn loadSystemZone(self: *State) !timezone.Zone {
    const utc = timezone.Zone.utc(self.allocator);
    if (comptime builtin.os.tag == .freestanding or builtin.os.tag == .windows or builtin.os.tag == .wasi) return utc;
    const io = self.options.io orelse return utc;
    var spec = getenv(self, "TZ") orelse "/etc/localtime";
    if (spec.len == 0) return utc;
    if (spec[0] == ':') spec = spec[1..];
    if (spec.len != 0 and std.mem.indexOf(u8, spec, "..") == null) {
        const path = if (spec[0] == '/')
            try self.allocator.dupe(u8, spec)
        else
            try std.fmt.allocPrint(self.allocator, "/usr/share/zoneinfo/{s}", .{spec});
        defer self.allocator.free(path);
        if (Dir.cwd().readFileAlloc(io, path, self.allocator, .limited(1024 * 1024))) |bytes| {
            defer self.allocator.free(bytes);
            if (timezone.Zone.parseTzif(self.allocator, bytes)) |zone| return zone else |err| if (err == error.OutOfMemory) return err;
        } else |err| if (err == error.OutOfMemory) return err;
    }
    return timezone.Zone.fromRule(self.allocator, spec) orelse utc;
}

pub fn executeProcess(self: *State, command: []const u8) !ProcessResult {
    return switch (self.options.process) {
        .disabled => return self.fail("process access disabled"),
        .custom => |process| return process.execute(process.context, command) catch return self.fail("process execution failed"),
        .enabled => if (comptime builtin.os.tag == .freestanding) {
            return self.fail("host process unavailable");
        } else {
            const io = try io_mod.requireIo(self, "process I/O unavailable");
            try flushOutputForChild(self);
            const argv = shellArgv(command);
            var child = std.process.spawn(io, .{
                .argv = &argv,
                .environ_map = environmentMap(self),
            }) catch return self.fail("process execution failed");
            const term = child.wait(io) catch {
                child.kill(io);
                return self.fail("process execution failed");
            };
            return processResult(term);
        },
    };
}

/// Read mode (`input == null`) returns the command's stdout; write mode feeds
/// `input` to its stdin. Other streams are inherited, like C `popen`.
pub fn popenProcess(self: *State, command: []const u8, input: ?[]const u8) !host.PopenResult {
    switch (self.options.process) {
        .disabled => return self.fail("'popen' not supported"),
        .custom => |process| {
            const popen = process.popen orelse return self.fail("'popen' not supported");
            const result = popen(process.context, self.allocator, command, input) catch |err| {
                if (err == error.OutOfMemory) return error.OutOfMemory;
                return self.fail("process execution failed");
            };
            if (result.output.len > self.options.max_file_bytes) {
                self.allocator.free(result.output);
                return self.fail("process output too large");
            }
            return result;
        },
        .enabled => if (comptime builtin.os.tag == .freestanding) {
            return self.fail("'popen' not supported");
        } else {
            const io = try io_mod.requireIo(self, "process I/O unavailable");
            try flushOutputForChild(self);
            const argv = shellArgv(command);
            var child = std.process.spawn(io, .{
                .argv = &argv,
                .environ_map = environmentMap(self),
                .stdin = if (input == null) .inherit else .pipe,
                .stdout = if (input == null) .pipe else .inherit,
            }) catch return self.fail("process execution failed");
            var output: []const u8 = "";
            errdefer self.allocator.free(output);
            if (input) |bytes| {
                const stdin = child.stdin.?;
                stdin.writeStreamingAll(io, bytes) catch {};
                stdin.close(io);
                child.stdin = null;
            } else {
                var buffer: [4096]u8 = undefined;
                var reader = child.stdout.?.readerStreaming(io, &buffer);
                output = reader.interface.allocRemaining(self.allocator, .limited(self.options.max_file_bytes)) catch |err| {
                    child.kill(io);
                    if (err == error.OutOfMemory) return error.OutOfMemory;
                    return self.fail(if (err == error.StreamTooLong) "process output too large" else "process execution failed");
                };
            }
            const term = child.wait(io) catch {
                child.kill(io);
                return self.fail("process execution failed");
            };
            return .{ .output = output, .result = processResult(term) };
        },
    }
}

/// The caller then unwinds with `error.LuaExit`.
pub fn requestExit(self: *State, code: i32, close: bool) !void {
    switch (self.options.process) {
        .disabled => return self.fail("process access disabled"),
        .enabled => {},
        .custom => |process| if (process.exit) |exit| exit(process.context, code, close) catch |err| {
            if (err == error.OutOfMemory) return error.OutOfMemory;
            return self.fail("process exit failed");
        },
    }
    io_mod.flushStdout(self) catch {};
    io_mod.flushStderr(self) catch {};
    self.exit_request = .{ .code = code, .close = close };
}

pub fn finishExitUnwind(self: *State, thread: *Thread) !void {
    const request = self.exit_request orelse return;
    if (!request.close) return;
    upvalue_mod.closeFramesTo(self, thread, 0, null) catch |err| if (err == error.OutOfMemory) return err;
}

fn flushOutputForChild(self: *State) !void {
    try io_mod.flushStdout(self);
    try io_mod.flushStderr(self);
}

fn shellArgv(command: []const u8) [3][]const u8 {
    return if (comptime builtin.os.tag == .windows)
        .{ "cmd.exe", "/c", command }
    else
        .{ "/bin/sh", "-c", command };
}

fn processResult(term: std.process.Child.Term) ProcessResult {
    return switch (term) {
        .exited => |code| .{ .status = .exit, .code = code },
        .signal, .stopped => |signal| .{ .status = .signal, .code = signalNumber(signal) },
        .unknown => |code| .{ .status = .exit, .code = code },
    };
}

fn signalNumber(signal: anytype) i64 {
    return switch (@typeInfo(@TypeOf(signal))) {
        .@"enum" => @intCast(@intFromEnum(signal)),
        .int => @intCast(signal),
        else => 0,
    };
}

fn environmentMap(self: *State) ?*const std.process.Environ.Map {
    return switch (self.options.environment) {
        .map => |environment| environment,
        .disabled, .custom => null,
    };
}

pub fn processEnabled(self: *State) bool {
    return switch (self.options.process) {
        .disabled => false,
        .enabled, .custom => true,
    };
}
