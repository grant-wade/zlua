const std = @import("std");

const Dir = std.Io.Dir;
const Sha256 = std.crypto.hash.sha2.Sha256;

const stamp_name = ".sha256";
const max_archive_bytes = 64 * 1024 * 1024;
const max_attempts = 4;

/// Usage: `fetch_archive <url> <sha256> <dest> [url_env]`. Unpacks the archive's top directory
/// into `dest`. The environment variable `url_env`, when set, replaces `url`.
pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    const io = init.io;
    const args = try init.minimal.args.toSlice(arena);
    if (args.len != 4 and args.len != 5) fatal("usage: fetch_archive <url> <sha256> <dest> [url_env]", .{});
    const url = if (args.len == 5) init.environ_map.get(args[4]) orelse args[1] else args[1];
    const expected = args[2];
    const dest = args[3];

    if (try stampMatches(io, arena, dest, expected)) return;

    var client: std.http.Client = .{ .allocator = init.gpa, .io = io };
    defer client.deinit();
    try client.initDefaultProxies(arena, init.environ_map);

    var body = std.Io.Writer.Allocating.init(init.gpa);
    defer body.deinit();
    var attempt: u6 = 1;
    while (true) : (attempt += 1) {
        body.clearRetainingCapacity();
        if (client.fetch(.{ .location = .{ .url = url }, .response_writer = &body.writer })) |result| {
            if (result.status == .ok) break;
            if (attempt == max_attempts) fatal("fetch_archive: downloading {s} returned HTTP {d}", .{ url, @intFromEnum(result.status) });
            std.debug.print("fetch_archive: {s} returned HTTP {d}; retrying\n", .{ url, @intFromEnum(result.status) });
        } else |err| {
            if (attempt == max_attempts) fatal("fetch_archive: downloading {s} failed: {s}", .{ url, @errorName(err) });
            std.debug.print("fetch_archive: downloading {s} failed: {s}; retrying\n", .{ url, @errorName(err) });
        }
        try io.sleep(.fromSeconds(@as(i64, 1) << attempt), .awake);
    }
    const archive = body.written();
    if (archive.len > max_archive_bytes) fatal("fetch_archive: {s} is larger than {d} bytes", .{ url, max_archive_bytes });

    var digest: [Sha256.digest_length]u8 = undefined;
    Sha256.hash(archive, &digest, .{});
    const actual = std.fmt.bytesToHex(digest, .lower);
    if (!std.mem.eql(u8, &actual, expected)) {
        fatal("fetch_archive: checksum mismatch for {s}\n  expected: {s}\n  actual:   {s}", .{ url, expected, &actual });
    }

    const cwd = Dir.cwd();
    cwd.deleteTree(io, dest) catch {};
    try cwd.createDirPath(io, dest);
    var dir = try cwd.openDir(io, dest, .{});
    defer dir.close(io);

    var reader: std.Io.Reader = .fixed(archive);
    var window: [std.compress.flate.max_window_len]u8 = undefined;
    var decompress: std.compress.flate.Decompress = .init(&reader, .gzip, &window);
    try std.tar.extract(io, dir, &decompress.reader, .{ .strip_components = 1 });
    try dir.writeFile(io, .{ .sub_path = stamp_name, .data = expected });
}

fn stampMatches(io: std.Io, allocator: std.mem.Allocator, dest: []const u8, expected: []const u8) !bool {
    const path = try std.fs.path.join(allocator, &.{ dest, stamp_name });
    const stamp = Dir.cwd().readFileAlloc(io, path, allocator, .limited(256)) catch return false;
    return std.mem.eql(u8, std.mem.trim(u8, stamp, " \r\n"), expected);
}

fn fatal(comptime fmt: []const u8, args: anytype) noreturn {
    std.debug.print(fmt ++ "\n", args);
    std.process.exit(1);
}
