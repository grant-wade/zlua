const std = @import("std");

const Dir = std.Io.Dir;
const Sha256 = std.crypto.hash.sha2.Sha256;

const stamp_name = ".sha256";
const max_archive_bytes = 64 * 1024 * 1024;

/// Usage: `fetch_archive <url> <sha256> <dest>`. Unpacks the archive's top directory into `dest`.
pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    const io = init.io;
    const args = try init.minimal.args.toSlice(arena);
    if (args.len != 4) fatal("usage: fetch_archive <url> <sha256> <dest>", .{});
    const url = args[1];
    const expected = args[2];
    const dest = args[3];

    if (try stampMatches(io, arena, dest, expected)) return;

    var client: std.http.Client = .{ .allocator = init.gpa, .io = io };
    defer client.deinit();
    try client.initDefaultProxies(arena, init.environ_map);

    var body = std.Io.Writer.Allocating.init(init.gpa);
    defer body.deinit();
    const result = client.fetch(.{ .location = .{ .url = url }, .response_writer = &body.writer }) catch |err|
        fatal("fetch_archive: downloading {s} failed: {s}", .{ url, @errorName(err) });
    if (result.status != .ok) fatal("fetch_archive: downloading {s} returned HTTP {d}", .{ url, @intFromEnum(result.status) });
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
