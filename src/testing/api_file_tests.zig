const std = @import("std");
const api = @import("../api.zig");
const io_lib = @import("../stdlib/io.zig");
const a = std.testing.allocator;

const tmpfile_round_trip =
    \\local f = assert(io.tmpfile())
    \\assert(io.type(f) == 'file' and type(f) == 'userdata')
    \\assert(f:write('alpha', 1, '\n', 2.5) == f)
    \\assert(f:seek('set', 0) == 0 and f:read('l') == 'alpha1' and f:read('n') == 2.5)
    \\assert(f:seek('end') == 10 and f:flush() == true)
    \\assert(f:close() == true and io.type(f) == 'closed file')
    \\do local g <close> = assert(io.tmpfile()); g:write('closing') end
    \\local lost = assert(io.tmpfile()); lost:write('collected'); lost = nil
    \\collectgarbage(); collectgarbage()
;

fn countFiles(dir: std.Io.Dir) !usize {
    var iterator = dir.iterate();
    var count: usize = 0;
    while (try iterator.next(std.testing.io)) |_| count += 1;
    return count;
}

test "tmpfile is an anonymous memory file in every filesystem mode" {
    {
        var lua = try api.State.init(a, .{ .stdlib = .full });
        defer lua.deinit();
        try lua.doString(tmpfile_round_trip, .{ .name = "=disabled" });
    }
    {
        const files = [_]api.MemoryFile{.{ .path = "seed.txt", .contents = "seed" }};
        var lua = try api.State.init(a, .{ .stdlib = .full, .capabilities = .{ .filesystem = .{ .memory = &files } } });
        defer lua.deinit();
        try lua.doString(tmpfile_round_trip, .{ .name = "=memory" });
    }
    {
        var filesystem = api.MemoryFilesystem.init(a);
        defer filesystem.deinit();
        var lua = try api.State.init(a, .{ .stdlib = .full, .capabilities = .{ .filesystem = .{ .memory_rw = &filesystem } } });
        defer lua.deinit();
        try lua.doString(tmpfile_round_trip, .{ .name = "=memory_rw" });
        try std.testing.expectEqual(@as(usize, 0), filesystem.files.items.len);
        try std.testing.expectEqual(@as(usize, 0), filesystem.directories.items.len);
    }
    {
        var temporary = std.testing.tmpDir(.{ .iterate = true });
        defer temporary.cleanup();
        var lua = try api.State.init(a, .{
            .stdlib = .full,
            .capabilities = .{ .io = .{ .runtime = std.testing.io }, .filesystem = .{ .host_dir = .{ .dir = temporary.dir } } },
        });
        defer lua.deinit();
        try lua.doString(tmpfile_round_trip, .{ .name = "=host_dir" });
        try std.testing.expectEqual(@as(usize, 0), try countFiles(temporary.dir));
    }
    {
        const Callbacks = struct {
            var calls: usize = 0;
            fn read(_: ?*anyopaque, _: std.mem.Allocator, _: []const u8) anyerror![]const u8 {
                calls += 1;
                return error.FileNotFound;
            }
            fn write(_: ?*anyopaque, _: []const u8, _: []const u8) anyerror!void {
                calls += 1;
            }
        };
        var lua = try api.State.init(a, .{
            .stdlib = .full,
            .capabilities = .{ .filesystem = .{ .custom = .{ .read_file_alloc = Callbacks.read, .write_file = Callbacks.write } } },
        });
        defer lua.deinit();
        try lua.doString(tmpfile_round_trip, .{ .name = "=custom" });
        try std.testing.expectEqual(@as(usize, 0), Callbacks.calls);
    }
}

test "tmpfile writes are bounded by max_file_bytes and max_memory" {
    {
        var lua = try api.State.init(a, .{ .stdlib = .full, .limits = .{ .max_file_bytes = 10 } });
        defer lua.deinit();
        try lua.doString(
            \\local f = assert(io.tmpfile())
            \\assert(f:write('0123456789') == f)
            \\local ok, message, code = f:write('x')
            \\assert(ok == nil and message == 'File too large' and code == 27)
            \\assert(f:seek('end') == 10)
        , .{});
    }
    {
        var lua = try api.State.init(a, .{ .stdlib = .full, .limits = .{ .max_memory = 2 * 1024 * 1024 } });
        defer lua.deinit();
        try lua.doString(
            \\local chunk = string.rep('x', 64 * 1024)
            \\local f = assert(io.tmpfile())
            \\local ok, err = pcall(function() for _ = 1, 128 do f:write(chunk) end end)
            \\assert(not ok and tostring(err):find('not enough memory'))
            \\f:close(); f = nil
            \\collectgarbage()
            \\local g = assert(io.tmpfile()); assert(g:write('still usable')); g:close()
        , .{});
    }
}

test "file buffers count toward collector memory accounting" {
    var lua = try api.State.init(a, .{ .stdlib = .full });
    defer lua.deinit();
    try lua.doString(
        \\local chunk = string.rep('x', 1024 * 1024)
        \\collectgarbage(); collectgarbage('stop')
        \\local before = collectgarbage('count')
        \\local f = assert(io.tmpfile())
        \\f:write(chunk)
        \\grown = collectgarbage('count') - before
        \\f:close()
        \\shrunk = collectgarbage('count') - before
        \\collectgarbage('restart')
    , .{});
    try std.testing.expect(try lua.getGlobal("grown", f64) >= 1024);
    try std.testing.expect(try lua.getGlobal("shrunk", f64) < 64);
    try std.testing.expectEqual(lua.raw_state.allocationStats().total(), lua.raw_state.gc_known_total);
}

test "collecting an unreachable open file flushes and closes it" {
    var filesystem = api.MemoryFilesystem.init(a);
    defer filesystem.deinit();
    var lua = try api.State.init(a, .{ .stdlib = .full, .capabilities = .{ .filesystem = .{ .memory_rw = &filesystem } } });
    defer lua.deinit();
    try lua.doString(
        \\do local f = assert(io.open('lost.txt', 'w')); f:write('flushed by gc') end
        \\-- A `__gc` metamethod still sees an open file that dies with it, then
        \\-- the file's own finalizer flushes and closes it.
        \\do
        \\  local f = assert(io.open('order.txt', 'w'))
        \\  setmetatable({}, { __gc = function() f:write('from __gc'); kept = f end })
        \\end
        \\collectgarbage(); collectgarbage(); collectgarbage()
        \\assert(io.type(kept) == 'closed file')
    , .{});
    for ([_][2][]const u8{ .{ "lost.txt", "flushed by gc" }, .{ "order.txt", "from __gc" } }) |case| {
        const bytes = try filesystem.readFileAlloc(a, case[0]);
        defer a.free(bytes);
        try std.testing.expectEqualStrings(case[1], bytes);
    }
}

test "file handles are FILE* userdata with no Lua-visible fields" {
    var lua = try api.State.init(a, .{ .stdlib = .full });
    defer lua.deinit();
    try lua.doString(
        \\for _, f in ipairs({ io.stdin, io.stdout, io.stderr, io.tmpfile() }) do
        \\  assert(type(f) == 'userdata' and getmetatable(f).__name == 'FILE*')
        \\  assert(not pcall(next, f) and not pcall(rawget, f, 'x') and not pcall(rawlen, f))
        \\  assert(f.read == io.stdout.read and f.nosuch == nil)
        \\end
        \\handle = io.tmpfile()
    , .{});
    const raw = lua.raw_state.getGlobal("handle");
    try std.testing.expect(raw == .userdata and raw.userdata.type_id == io_lib.fileTypeId());
    try std.testing.expect(io_lib.fileOf(raw).?.kind == .anonymous);
}

test "os.tmpname reserves unique names inside sandboxed filesystems" {
    const script =
        \\local seen = {}
        \\for _ = 1, 50 do
        \\  local name = os.tmpname()
        \\  assert(name:match('^lua_%w%w%w%w%w%w$'), name)
        \\  assert(not seen[name]); seen[name] = true
        \\  assert(io.open(name, 'r')):close()
        \\end
        \\for name in pairs(seen) do assert(os.remove(name)) end
        \\for name in pairs(seen) do assert(io.open(name) == nil) end
    ;
    {
        var filesystem = api.MemoryFilesystem.init(a);
        defer filesystem.deinit();
        var lua = try api.State.init(a, .{ .stdlib = .full, .capabilities = .{ .filesystem = .{ .memory_rw = &filesystem } } });
        defer lua.deinit();
        try lua.doString("kept = os.tmpname()", .{});
        const kept = try lua.getGlobal("kept", []const u8);
        try std.testing.expectEqual(@as(usize, 0), (try filesystem.statPath(kept)).size);
        try lua.doString("assert(os.remove(kept))", .{});
        try lua.doString(script, .{ .name = "=memory_rw" });
        try std.testing.expectEqual(@as(usize, 0), filesystem.files.items.len);
    }
    {
        var temporary = std.testing.tmpDir(.{ .iterate = true });
        defer temporary.cleanup();
        var lua = try api.State.init(a, .{
            .stdlib = .full,
            .capabilities = .{ .io = .{ .runtime = std.testing.io }, .filesystem = .{ .host_dir = .{ .dir = temporary.dir } } },
        });
        defer lua.deinit();
        try lua.doString("kept = os.tmpname()", .{});
        try std.testing.expectEqual(@as(usize, 1), try countFiles(temporary.dir));
        try lua.doString("assert(os.remove(kept))", .{});
        try lua.doString(script, .{ .name = "=host_dir" });
        try std.testing.expectEqual(@as(usize, 0), try countFiles(temporary.dir));
    }
    {
        const files = [_]api.MemoryFile{.{ .path = "seed.txt", .contents = "seed" }};
        var lua = try api.State.init(a, .{ .stdlib = .full, .capabilities = .{ .filesystem = .{ .memory = &files } } });
        defer lua.deinit();
        try lua.doString(
            \\local ok, err = pcall(os.tmpname)
            \\assert(not ok and err == 'unable to generate a unique filename')
        , .{});
    }
}

fn expectFile(filesystem: *api.MemoryFilesystem, path: []const u8, expected: []const u8) !void {
    const bytes = try filesystem.readFileAlloc(a, path);
    defer a.free(bytes);
    try std.testing.expectEqualStrings(expected, bytes);
}

test "deinit closes open files like lua_close, flushing buffered writes" {
    var filesystem = api.MemoryFilesystem.init(a);
    defer filesystem.deinit();
    {
        var lua = try api.State.init(a, .{ .stdlib = .full, .capabilities = .{ .filesystem = .{ .memory_rw = &filesystem } } });
        defer lua.deinit();
        try lua.doString(
            \\open = assert(io.open('open.txt', 'w')); open:write('buffered')
            \\local appended = assert(io.open('open.txt', 'r')) -- reader handles are left alone
            \\io.output('output.txt'); io.write('default output')
            \\local closed = assert(io.open('closed.txt', 'w')); closed:write('closed'); closed:close()
            \\do local lost = assert(io.open('local.txt', 'w')); lost:write('unreferenced') end
        , .{});
        try expectFile(&filesystem, "open.txt", "");
        try expectFile(&filesystem, "output.txt", "");
    }
    try expectFile(&filesystem, "open.txt", "buffered");
    try expectFile(&filesystem, "output.txt", "default output");
    try expectFile(&filesystem, "closed.txt", "closed");
    try expectFile(&filesystem, "local.txt", "unreferenced");
}

test "deinit closes worker and rollback files but not snapshot images" {
    var filesystem = api.MemoryFilesystem.init(a);
    defer filesystem.deinit();
    var lua = try api.State.init(a, .{ .stdlib = .full, .capabilities = .{ .filesystem = .{ .memory_rw = &filesystem } } });
    var lua_alive = true;
    defer if (lua_alive) lua.deinit();
    try lua.doString("image = assert(io.open('image.txt', 'w')); image:write('in image')", .{});
    var snapshot = try lua.snapshot(a);
    {
        var worker = try snapshot.newState(a);
        defer worker.deinit();
        try worker.doString("assert(io.open('worker.txt', 'w')):write('from worker')", .{});
    }
    try expectFile(&filesystem, "worker.txt", "from worker");
    try lua.doString("discarded = assert(io.open('reset.txt', 'w')); discarded:write('dropped')", .{});
    try lua.reset();
    try expectFile(&filesystem, "reset.txt", "");
    try lua.doString("image:close(); late = assert(io.open('late.txt', 'w')); late:write('after reset')", .{});
    try expectFile(&filesystem, "image.txt", "in image");
    try filesystem.removeFile("image.txt");
    snapshot.deinit();
    lua.deinit();
    lua_alive = false;
    try expectFile(&filesystem, "late.txt", "after reset");
    try std.testing.expectError(error.FileNotFound, filesystem.readFileAlloc(a, "image.txt"));
}

test "writes to regular files stop at max_file_bytes" {
    var filesystem = api.MemoryFilesystem.init(a);
    defer filesystem.deinit();
    var lua = try api.State.init(a, .{
        .stdlib = .full,
        .limits = .{ .max_file_bytes = 10 },
        .capabilities = .{ .filesystem = .{ .memory_rw = &filesystem } },
    });
    defer lua.deinit();
    try lua.doString(
        \\local f = assert(io.open('capped.txt', 'w'))
        \\assert(f:write('0123', '45678') == f)
        \\local ok, message, code, written = f:write('9', 'ab', 'c')
        \\assert(ok == nil and message == 'File too large' and code == 27 and written == 1)
        \\assert(f:seek('cur') == 10 and f:seek('set', 20) == 20)
        \\assert(select(2, f:write('x')) == 'File too large')
        \\assert(f:close())
        \\local g = assert(fs.open('fs.txt', 'w'))
        \\assert(select(4, g:write('abcdefghijk')) == 0)
        \\assert(g:close())
        \\local a = assert(io.open('capped.txt', 'a'))
        \\assert(select(3, a:write('more')) == 27)
        \\assert(a:close())
    , .{});
    try expectFile(&filesystem, "capped.txt", "0123456789");
    try expectFile(&filesystem, "fs.txt", "");
}

test "append opens leave the file alone and writes land at its current end" {
    const Backed = struct {
        fn read(context: ?*anyopaque, allocator: std.mem.Allocator, path: []const u8) anyerror![]const u8 {
            const filesystem: *api.MemoryFilesystem = @ptrCast(@alignCast(context.?));
            return filesystem.readFileAlloc(allocator, path);
        }
        fn write(context: ?*anyopaque, path: []const u8, contents: []const u8) anyerror!void {
            const filesystem: *api.MemoryFilesystem = @ptrCast(@alignCast(context.?));
            return filesystem.writeFile(path, contents);
        }
    };
    for ([_]bool{ false, true }) |custom| {
        var filesystem = api.MemoryFilesystem.init(a);
        defer filesystem.deinit();
        try filesystem.writeFile("log.txt", "start\n");
        const capability: api.FilesystemCapability = if (custom)
            .{ .custom = .{ .context = &filesystem, .read_file_alloc = Backed.read, .write_file = Backed.write } }
        else
            .{ .memory_rw = &filesystem };
        var lua = try api.State.init(a, .{ .stdlib = .full, .capabilities = .{ .filesystem = capability } });
        defer lua.deinit();
        try lua.doString(
            \\local a = assert(io.open('log.txt', 'a'))
            \\local b = assert(io.open('log.txt', 'a+'))
            \\b:write('B\n'); assert(b:close())
            \\a:write('A\n'); assert(a:flush())
            \\a:write('A2\n'); assert(a:close())
            \\local c = assert(io.open('new.txt', 'a')); c:write('n'); assert(c:close())
        , .{});
        try expectFile(&filesystem, "log.txt", "start\nB\nA\nA2\n");
        try expectFile(&filesystem, "new.txt", "n");
    }
}

test "__close and collection ignore flush failures like f_gc" {
    const Failing = struct {
        fn read(_: ?*anyopaque, _: std.mem.Allocator, _: []const u8) anyerror![]const u8 {
            return error.FileNotFound;
        }
        fn write(_: ?*anyopaque, _: []const u8, contents: []const u8) anyerror!void {
            if (contents.len != 0) return error.NoSpaceLeft;
        }
    };
    var lua = try api.State.init(a, .{
        .stdlib = .full,
        .capabilities = .{ .filesystem = .{ .custom = .{ .read_file_alloc = Failing.read, .write_file = Failing.write } } },
    });
    defer lua.deinit();
    try lua.doString(
        \\local escaped
        \\do
        \\  local f <close> = assert(io.open('full.txt', 'w'))
        \\  f:write('data')
        \\  escaped = f
        \\end
        \\assert(io.type(escaped) == 'closed file')
        \\local f = assert(io.open('full.txt', 'w'))
        \\f:write('data')
        \\assert(getmetatable(f).__gc(f) == nil and io.type(f) == 'closed file')
        \\local g = assert(io.open('full.txt', 'w'))
        \\g:write('data')
        \\local ok, message, code = g:close()
        \\assert(ok == nil and message == 'No space left on device' and code == 28 and io.type(g) == 'closed file')
        \\do local lost = assert(io.open('full.txt', 'w')); lost:write('data') end
        \\collectgarbage(); collectgarbage()
        \\leaked = assert(io.open('full.txt', 'w')); leaked:write('data')
    , .{});
}

test "explicit close and flush failures return luaL_fileresult values" {
    const Failing = struct {
        fn read(_: ?*anyopaque, _: std.mem.Allocator, _: []const u8) anyerror![]const u8 {
            return error.FileNotFound;
        }
        fn write(_: ?*anyopaque, _: []const u8, contents: []const u8) anyerror!void {
            if (contents.len != 0) return error.NoSpaceLeft;
        }
    };
    {
        var lua = try api.State.init(a, .{
            .stdlib = .full,
            .capabilities = .{ .filesystem = .{ .custom = .{ .read_file_alloc = Failing.read, .write_file = Failing.write } } },
        });
        defer lua.deinit();
        try lua.doString(
            \\local function failed(ok, message, code, ...)
            \\  assert(ok == nil and message == 'No space left on device' and code == 28, tostring(message))
            \\  return ...
            \\end
            \\local f = assert(io.open('f.txt', 'w'))
            \\assert(f:write('data') == f)
            \\failed(f:flush())
            \\failed(f:close())
            \\assert(io.type(f) == 'closed file')
            \\io.output(assert(io.open('out.txt', 'w')))
            \\assert(io.write('data') == io.output())
            \\failed(io.flush())
            \\failed(io.close())
            \\io.output(io.stdout)
            \\local u = assert(io.open('u.txt', 'w'))
            \\assert(u:setvbuf('no') == true)
            \\assert(failed(u:write('ab', 'cd')) == 0)
            \\failed(u:close())
            \\local l = assert(io.open('l.txt', 'w'))
            \\assert(l:setvbuf('line') == true)
            \\assert(l:write('line\\n') == l)
            \\failed(l:setvbuf('full'))
            \\failed(l:close())
        , .{ .name = "=custom" });
    }
    {
        const files = [_]api.MemoryFile{.{ .path = "seed.txt", .contents = "seed" }};
        var lua = try api.State.init(a, .{ .stdlib = .full, .capabilities = .{ .filesystem = .{ .memory = &files } } });
        defer lua.deinit();
        try lua.doString(
            \\local f = assert(io.open('seed.txt', 'r+'))
            \\assert(f:write('more') == f)
            \\local ok, message, code = f:flush()
            \\assert(ok == nil and message == 'filesystem write access disabled' and code == 30)
            \\ok, message, code = f:close()
            \\assert(ok == nil and message == 'filesystem write access disabled' and code == 30)
        , .{ .name = "=memory" });
    }
}

const FinalizerLog = struct {
    var bytes: [256]u8 = undefined;
    var len: usize = 0;

    fn log(ctx: *api.Context) !void {
        const entry = try ctx.arg(0, []const u8);
        @memcpy(bytes[len..][0..entry.len], entry);
        len += entry.len;
    }

    fn reset() void {
        len = 0;
    }

    fn text() []const u8 {
        return bytes[0..len];
    }
};

test "deinit calls pending __gc metamethods like lua_close" {
    var filesystem = api.MemoryFilesystem.init(a);
    defer filesystem.deinit();
    FinalizerLog.reset();
    {
        var lua = try api.State.init(a, .{ .stdlib = .full, .capabilities = .{ .filesystem = .{ .memory_rw = &filesystem } } });
        defer lua.deinit();
        var log = try lua.register("log", FinalizerLog.log);
        defer log.deinit();
        try lua.setGlobal("log", log);
        try lua.doString(
            \\local function gc(name, extra)
            \\  return setmetatable({}, {__gc = function(o) log(name); if extra then extra(o) end end})
            \\end
            \\keep = {}
            \\local f = assert(io.open('f.txt', 'w')); f:write('f')
            \\keep.a = gc('a', function() keep.new = gc('never') end)
            \\keep.b = gc('b', function() error('ignored') end)
            \\keep.c = gc('c', function(o) log(io.type(f)); f:write('+c'); resurrected = o; setmetatable(o, getmetatable(o)) end)
            \\keep.d = gc('d', function() log(tostring(collectgarbage())); log(tostring(collectgarbage('count'))) end)
            \\keep.e = gc('e', function() log(select(2, pcall(coroutine.yield)) and 'Y' or '?') end)
            \\local g = assert(io.open('g.txt', 'w')); g:write('g')
            \\keep.h = gc('h', function() log(io.type(g)) end)
            \\collectgarbage('stop')
            \\gc('garbage')
            \\setmetatable({}, {__gc = 0})
        , .{});
        FinalizerLog.reset();
    }
    try std.testing.expectEqualStrings("garbagehfileeYdnilnilcfileba", FinalizerLog.text());
    try expectFile(&filesystem, "f.txt", "f+c");
    try expectFile(&filesystem, "g.txt", "g");
}

test "deinit finalizers run collected tables first and respect limits and interrupts" {
    FinalizerLog.reset();
    {
        var lua = try api.State.init(a, .{ .gc = .{ .running = false, .mode = .incremental } });
        defer lua.deinit();
        var log = try lua.register("log", FinalizerLog.log);
        defer log.deinit();
        try lua.setGlobal("log", log);
        try lua.doString(
            \\keep = setmetatable({}, {__gc = function() log('kept') end})
            \\setmetatable({}, {__gc = function() log('separated') end})
        , .{});
        while (lua.raw_state.gc_phase != .finalize) _ = try lua.stepGc(.{});
        try std.testing.expect(lua.raw_state.table_pending_finalizer_head != null);
        try lua.doString("late = setmetatable({}, {__gc = function() log('late') end})", .{});
    }
    try std.testing.expectEqualStrings("separatedlatekept", FinalizerLog.text());

    FinalizerLog.reset();
    {
        var lua = try api.State.init(a, .{ .limits = .{ .max_instructions = 10_000 } });
        defer lua.deinit();
        var log = try lua.register("log", FinalizerLog.log);
        defer log.deinit();
        try lua.setGlobal("log", log);
        try lua.doString(
            \\after = setmetatable({}, {__gc = function() log('after') end})
            \\runaway = setmetatable({}, {__gc = function() log('loop') while true do end end})
            \\local i = 0 while i < 500 do i = i + 1 end
        , .{});
    }
    try std.testing.expectEqualStrings("loopafter", FinalizerLog.text());

    FinalizerLog.reset();
    {
        var lua = try api.State.init(a, .{});
        defer lua.deinit();
        var log = try lua.register("log", FinalizerLog.log);
        defer log.deinit();
        try lua.setGlobal("log", log);
        try lua.doString(
            \\after = setmetatable({}, {__gc = function() log('after') end})
            \\stopped = setmetatable({}, {__gc = function() log('stopped') end})
        , .{});
        const interrupt = try lua.interruptHandle();
        interrupt.interrupt();
    }
    try std.testing.expectEqualStrings("", FinalizerLog.text());
}

test "reset skips finalizers while workers and sources finalize at deinit" {
    FinalizerLog.reset();
    var lua = try api.State.init(a, .{});
    var log = try lua.register("log", FinalizerLog.log);
    try lua.setGlobal("log", log);
    log.deinit();
    try lua.doString("base = setmetatable({}, {__gc = function() log('base') end})", .{});
    var snapshot = try lua.snapshot(a);
    {
        var worker = try snapshot.newState(a);
        defer worker.deinit();
        try worker.doString("extra = setmetatable({}, {__gc = function() log('worker') end})", .{});
        try worker.reset();
        try std.testing.expectEqualStrings("", FinalizerLog.text());
    }
    try std.testing.expectEqualStrings("base", FinalizerLog.text());
    FinalizerLog.reset();
    lua.deinit();
    try std.testing.expectEqualStrings("base", FinalizerLog.text());
    FinalizerLog.reset();
    snapshot.deinit();
    try std.testing.expectEqualStrings("", FinalizerLog.text());
}
