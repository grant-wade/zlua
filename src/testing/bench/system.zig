const std = @import("std");
const builtin = @import("builtin");

/// Description of the host running the benchmarks.
pub const Info = struct {
    os: []const u8,
    kernel: ?[]const u8,
    arch: []const u8,
    cpu: []const u8,
    cores: ?usize,
    memory_bytes: ?u64,
};

/// Strings in the result are owned by `allocator`.
pub fn detect(allocator: std.mem.Allocator, io: std.Io, environ_map: *const std.process.Environ.Map) Info {
    return .{
        .os = osName(allocator, io) orelse @tagName(builtin.os.tag),
        .kernel = kernel(allocator),
        .arch = @tagName(builtin.cpu.arch),
        .cpu = cpuName(allocator, io, environ_map) orelse builtin.cpu.model.name,
        .cores = std.Thread.getCpuCount() catch null,
        .memory_bytes = std.process.totalSystemMemory() catch null,
    };
}

pub fn write(out: *std.Io.Writer, info: Info) !void {
    try out.writeAll("System\n");
    try out.print("{s:<8} {s}\n", .{ "zig", builtin.zig_version_string });
    try out.print("{s:<8} {s}\n", .{ "os", info.os });
    if (info.kernel) |text| try out.print("{s:<8} {s}\n", .{ "kernel", text });
    try out.print("{s:<8} {s}\n", .{ "arch", info.arch });
    try out.print("{s:<8} {s}\n", .{ "cpu", info.cpu });
    if (info.cores) |count| try out.print("{s:<8} {d}\n", .{ "cores", count });
    if (info.memory_bytes) |bytes| try out.print("{s:<8} {d:.1} GiB\n", .{ "memory", @as(f64, @floatFromInt(bytes)) / (1024 * 1024 * 1024) });
    try out.writeByte('\n');
}

fn osName(allocator: std.mem.Allocator, io: std.Io) ?[]const u8 {
    return switch (builtin.os.tag) {
        .macos => if (sysctlString(allocator, "kern.osproductversion")) |version|
            std.fmt.allocPrint(allocator, "macOS {s}", .{version}) catch null
        else
            null,
        .linux => osRelease(allocator, io),
        else => null,
    };
}

fn osRelease(allocator: std.mem.Allocator, io: std.Io) ?[]const u8 {
    const text = std.Io.Dir.cwd().readFileAlloc(io, "/etc/os-release", allocator, .limited(64 * 1024)) catch return null;
    var lines = std.mem.splitScalar(u8, text, '\n');
    while (lines.next()) |line| {
        if (std.mem.startsWith(u8, line, "PRETTY_NAME=")) return std.mem.trim(u8, line["PRETTY_NAME=".len..], "\"'");
    }
    return null;
}

fn kernel(allocator: std.mem.Allocator) ?[]const u8 {
    if (builtin.os.tag == .windows or std.posix.utsname == void) return null;
    const uts = std.posix.uname();
    return std.fmt.allocPrint(allocator, "{s} {s}", .{ std.mem.sliceTo(&uts.sysname, 0), std.mem.sliceTo(&uts.release, 0) }) catch null;
}

fn cpuName(allocator: std.mem.Allocator, io: std.Io, environ_map: *const std.process.Environ.Map) ?[]const u8 {
    return switch (builtin.os.tag) {
        .macos => sysctlString(allocator, "machdep.cpu.brand_string"),
        .freebsd => sysctlString(allocator, "hw.model"),
        .linux => procCpuModel(allocator, io),
        .windows => environ_map.get("PROCESSOR_IDENTIFIER"),
        else => null,
    };
}

fn procCpuModel(allocator: std.mem.Allocator, io: std.Io) ?[]const u8 {
    const text = std.Io.Dir.cwd().readFileAlloc(io, "/proc/cpuinfo", allocator, .limited(4 * 1024 * 1024)) catch return null;
    var lines = std.mem.splitScalar(u8, text, '\n');
    while (lines.next()) |line| {
        if (!std.mem.startsWith(u8, line, "model name")) continue;
        const colon = std.mem.indexOfScalar(u8, line, ':') orelse continue;
        return std.mem.trim(u8, line[colon + 1 ..], " \t");
    }
    return null;
}

fn sysctlString(allocator: std.mem.Allocator, name: [*:0]const u8) ?[]const u8 {
    var buffer: [256]u8 = undefined;
    var len: usize = buffer.len;
    if (std.posix.system.sysctlbyname(name, &buffer, &len, null, 0) != 0) return null;
    return allocator.dupe(u8, std.mem.sliceTo(buffer[0..len], 0)) catch null;
}
