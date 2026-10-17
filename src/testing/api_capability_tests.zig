const std = @import("std");
const api = @import("../api.zig");
const ExitRequest = api.ExitRequest;
const MemoryFile = api.MemoryFile;
const MemoryFilesystem = api.MemoryFilesystem;
const PopenResult = api.PopenResult;
const ProcessResult = api.ProcessResult;
const State = api.State;
const UtcOffset = api.UtcOffset;

test "api full stdlib still denies ambient host access by default" {
    var lua = try State.init(std.testing.allocator, .{ .stdlib = .full });
    defer lua.deinit();

    try lua.doString(
        \\assert(os.getenv('ZLUA_API_ENV') == nil)
        \\local ok, err = pcall(os.execute, 'true')
        \\assert(ok == false and tostring(err):find('process access disabled'))
        \\local ok_time, time_err = pcall(os.time)
        \\assert(ok_time == false and tostring(time_err):find('clock access disabled'))
        \\local ok_date, date_err = pcall(os.date)
        \\assert(ok_date == false and tostring(date_err):find('clock access disabled'))
        \\local file = io.open('missing.lua', 'r')
        \\assert(file == nil)
        \\local blocked, write_err, write_code = io.open('blocked.lua', 'w')
        \\assert(blocked == nil and write_err == 'blocked.lua: filesystem write access disabled' and write_code == 30)
        \\local appended, append_err = io.open('blocked.lua', 'a')
        \\assert(appended == nil and append_err == 'blocked.lua: filesystem access disabled')
        \\local ok_input, input_err = pcall(io.input, 'missing.lua')
        \\assert(ok_input == false and tostring(input_err):find('cannot open file'))
        \\local tmp = assert(io.tmpfile())
        \\assert(tmp:write('scratch') == tmp and tmp:seek('set') == 0 and tmp:read('a') == 'scratch')
        \\assert(tmp:close() == true)
        \\local ok_tmpname, tmpname_err = pcall(os.tmpname)
        \\assert(ok_tmpname == false and tostring(tmpname_err):find('unable to generate a unique filename'))
        \\local loaded, load_err = loadfile('missing.lua')
        \\assert(loaded == nil and load_err == 'cannot open missing.lua: filesystem access disabled')
        \\local ok_file, file_err = pcall(dofile, 'missing.lua')
        \\assert(ok_file == false and tostring(file_err):find('filesystem access disabled'))
        \\local ok_require, require_err = pcall(require, 'missing')
        \\assert(ok_require == false and tostring(require_err):find("module 'missing' not found"))
        \\package.path = '/tmp/?.lua;../?.lua'
        \\local ok_escape_require, escape_require_err = pcall(require, 'missing')
        \\assert(ok_escape_require == false and tostring(escape_require_err):find("module 'missing' not found"))
        \\local found, search_err = package.searchpath('missing', '?.lua')
        \\assert(found == nil and tostring(search_err):find("missing.lua"))
        \\local ok_lines, lines_err = pcall(io.lines, 'missing.lua')
        \\assert(ok_lines == false and tostring(lines_err):find('cannot open file'))
        \\local removed, remove_err = os.remove('missing.lua')
        \\assert(removed == nil and tostring(remove_err):find('filesystem write access disabled'))
        \\local renamed, rename_err = os.rename('missing.lua', 'other.lua')
        \\assert(renamed == nil and tostring(rename_err):find('filesystem write access disabled'))
    , .{ .name = "=api-21.6-safe-host-access" });
}

test "api default stdlib omits host-facing libraries" {
    var lua = try State.init(std.testing.allocator, .{});
    defer lua.deinit();

    try lua.doString(
        \\assert(io == nil)
        \\assert(os == nil)
        \\assert(package == nil)
        \\assert(debug == nil)
    , .{ .name = "=api-default-safe-libs" });
}

test "api host-backed capabilities require explicit I/O access" {
    var lua = try State.init(std.testing.allocator, .{
        .stdlib = .full,
        .capabilities = .{
            .filesystem = .host_cwd,
            .clock = .system,
            .process = .enabled,
        },
    });
    defer lua.deinit();

    try lua.doString(
        \\local ok_process, process_err = pcall(os.execute, 'true')
        \\assert(ok_process == false and tostring(process_err):find('process I/O unavailable'))
        \\local ok_time, time_err = pcall(os.time)
        \\assert(ok_time == false and tostring(time_err):find('clock I/O unavailable'))
        \\local ok_file, file_err = pcall(dofile, 'missing.lua')
        \\assert(ok_file == false and tostring(file_err):find('filesystem I/O unavailable'))
    , .{ .name = "=api-host-backed-capabilities-need-io" });
}

test "api os filesystem mutations respect filesystem capability" {
    const files = [_]MemoryFile{
        .{ .path = "keep.lua", .contents = "return 42" },
    };
    var lua = try State.init(std.testing.allocator, .{
        .stdlib = .full,
        .capabilities = .{ .filesystem = .{ .memory = &files } },
    });
    defer lua.deinit();

    try lua.doString(
        \\local removed, remove_err = os.remove('keep.lua')
        \\assert(removed == nil and tostring(remove_err):find('filesystem write access disabled'))
        \\local renamed, rename_err = os.rename('keep.lua', 'gone.lua')
        \\assert(renamed == nil and tostring(rename_err):find('filesystem write access disabled'))
        \\assert(dofile('keep.lua') == 42)
    , .{ .name = "=api-21.6-os-fs-capability" });
}

test "api read-only memory filesystem denies stdlib writes" {
    const files = [_]MemoryFile{
        .{ .path = "seed.txt", .contents = "seed" },
    };
    var lua = try State.init(std.testing.allocator, .{
        .stdlib = .full,
        .capabilities = .{ .filesystem = .{ .memory = &files } },
    });
    defer lua.deinit();

    try lua.doString(
        \\local read = assert(io.open('seed.txt', 'r'))
        \\assert(read:read('*a') == 'seed')
        \\assert(read:close())
        \\local written, write_err = io.open('new.txt', 'w')
        \\assert(written == nil and tostring(write_err):find('filesystem write access disabled'))
        \\local appended, append_err = io.open('seed.txt', 'a')
        \\assert(appended == nil and tostring(append_err):find('filesystem write access disabled'))
        \\local tmp = assert(io.tmpfile())
        \\assert(tmp:write('temporary'))
        \\assert(tmp:close() == true)
        \\assert(not pcall(os.tmpname))
        \\local removed, remove_err = os.remove('seed.txt')
        \\assert(removed == nil and tostring(remove_err):find('filesystem write access disabled'))
        \\local renamed, rename_err = os.rename('seed.txt', 'renamed.txt')
        \\assert(renamed == nil and tostring(rename_err):find('filesystem write access disabled'))
        \\read = assert(io.open('seed.txt', 'r'))
        \\assert(read:read('*a') == 'seed')
    , .{ .name = "=api-memory-read-only-negative" });
}

test "fs extension supports memory filesystem directory utilities" {
    var filesystem = MemoryFilesystem.init(std.testing.allocator);
    defer filesystem.deinit();
    try filesystem.writeFile("seed/sub/a.txt", "alpha");

    var lua = try State.init(std.testing.allocator, .{
        .stdlib = .full,
        .capabilities = .{ .filesystem = .{ .memory_rw = &filesystem } },
    });
    defer lua.deinit();

    try lua.doString(
        \\assert(fs ~= nil and require('fs') == fs)
        \\local entries = assert(fs.list('seed'))
        \\assert(#entries == 1 and entries[1].name == 'sub' and entries[1].kind == 'directory')
        \\assert(entries[1].path == 'seed/sub')
        \\assert(fs.stat('seed/sub/a.txt').size == 5)
        \\assert(fs.mkdir('work/deep', { parents = true }))
        \\assert(fs.write('work/deep/data.bin', 'abc'))
        \\local seen = {}
        \\for entry in fs.walk('work') do seen[entry.path] = entry.kind end
        \\assert(seen['work/deep'] == 'directory' and seen['work/deep/data.bin'] == 'file')
        \\assert(fs.copy('work', 'copy', { recursive = true }))
        \\assert(fs.read('copy/deep/data.bin') == 'abc')
        \\assert(fs.remove('work', { recursive = true }))
        \\assert(not fs.exists('work'))
    , .{ .name = "=api-fs-memory" });
}

test "fs host directory capability confines paths to borrowed root" {
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();

    var lua = try State.init(std.testing.allocator, .{
        .stdlib = .full,
        .capabilities = .{
            .io = .{ .runtime = std.testing.io },
            .filesystem = .{ .host_dir = .{ .dir = temporary.dir } },
        },
    });
    defer lua.deinit();

    try lua.doString(
        \\assert(fs.mkdir('inside/deep', { parents = true }))
        \\assert(fs.write('inside/deep/value.txt', 'rooted'))
        \\assert(fs.read('inside/deep/value.txt') == 'rooted')
        \\local seen = {}
        \\for entry in fs.walk('inside') do seen[entry.path] = entry.kind end
        \\assert(seen['inside/deep'] == 'directory' and seen['inside/deep/value.txt'] == 'file')
        \\assert(fs.copy('inside', 'copied', { recursive = true }))
        \\assert(fs.read('copied/deep/value.txt') == 'rooted')
        \\assert(fs.remove('copied', { recursive = true }))
        \\local escaped, escape_err = fs.write('../escape.txt', 'bad')
        \\assert(escaped == nil and escape_err.code == 'invalid_path')
        \\local absolute, absolute_err = fs.stat('/tmp')
        \\assert(absolute == nil and absolute_err.code == 'invalid_path')
    , .{ .name = "=api-fs-host-dir" });
}

test "api writable memory filesystem supports Lua writes and mutations" {
    var filesystem = MemoryFilesystem.init(std.testing.allocator);
    defer filesystem.deinit();
    try filesystem.writeFile("seed.lua", "return 'seed'");

    var lua = try State.init(std.testing.allocator, .{
        .stdlib = .full,
        .capabilities = .{ .filesystem = .{ .memory_rw = &filesystem } },
    });
    defer lua.deinit();

    try lua.doString(
        \\assert(dofile('seed.lua') == 'seed')
        \\local file = assert(io.open('generated.lua', 'w'))
        \\assert(file:write("return 'generated'"))
        \\assert(file:close())
        \\assert(dofile('generated.lua') == 'generated')
        \\local log = assert(io.open('log.txt', 'w'))
        \\assert(log:write('alpha'))
        \\assert(log:close())
        \\log = assert(io.open('log.txt', 'a'))
        \\assert(log:write(' beta'))
        \\assert(log:close())
        \\local read = assert(io.open('log.txt', 'r'))
        \\assert(read:read('*a') == 'alpha beta')
        \\assert(read:close())
        \\assert(os.rename('generated.lua', 'renamed.lua'))
        \\assert(dofile('renamed.lua') == 'generated')
        \\assert(os.remove('renamed.lua'))
        \\assert(loadfile('renamed.lua') == nil)
    , .{ .name = "=api-21.6-memory-rw" });

    const log = try filesystem.readFileAlloc(std.testing.allocator, "log.txt");
    defer std.testing.allocator.free(log);
    try std.testing.expectEqualStrings("alpha beta", log);
}

test "api writable memory filesystem rejects sandbox escape writes" {
    var filesystem = MemoryFilesystem.init(std.testing.allocator);
    defer filesystem.deinit();
    try filesystem.writeFile("seed.txt", "seed");

    var lua = try State.init(std.testing.allocator, .{
        .stdlib = .full,
        .capabilities = .{ .filesystem = .{ .memory_rw = &filesystem } },
    });
    defer lua.deinit();

    try lua.doString(
        \\local absolute, absolute_err = io.open('/tmp/escape.txt', 'w')
        \\assert(absolute == nil and absolute_err == '/tmp/escape.txt: Permission denied')
        \\local relative, write_err, write_code = io.open('../escape.txt', 'w')
        \\assert(relative == nil and write_err == '../escape.txt: Permission denied' and write_code == 13)
        \\local ok_output, output_err = pcall(function()
        \\  local file = assert(io.open('generated.txt', 'w'))
        \\  assert(file:write('generated'))
        \\  return file:close()
        \\end)
        \\assert(ok_output == true)
        \\local removed, remove_err = os.remove('../escape.txt')
        \\assert(removed == nil and remove_err == '../escape.txt: Permission denied')
        \\local renamed, rename_err = os.rename('seed.txt', '../escape.txt')
        \\assert(renamed == nil and rename_err == 'Permission denied')
        \\local loaded, load_err = loadfile('../escape.lua')
        \\assert(loaded == nil and load_err == 'cannot open ../escape.lua: Permission denied')
        \\local ok_do, do_err = pcall(dofile, '../escape.lua')
        \\assert(ok_do == false and do_err == 'cannot open ../escape.lua: Permission denied')
    , .{ .name = "=api-memory-rw-escape-negative" });

    const seed = try filesystem.readFileAlloc(std.testing.allocator, "seed.txt");
    defer std.testing.allocator.free(seed);
    try std.testing.expectEqualStrings("seed", seed);
    try std.testing.expectError(error.FileNotFound, filesystem.readFileAlloc(std.testing.allocator, "escape.txt"));
}

test "api file reads share the max_file_bytes limit" {
    const files = [_]MemoryFile{
        .{ .path = "small.txt", .contents = "1234" },
        .{ .path = "big.lua", .contents = "return 123456789" },
        .{ .path = "dir/inner.txt", .contents = "x" },
    };
    var lua = try State.init(std.testing.allocator, .{
        .stdlib = .full,
        .capabilities = .{ .filesystem = .{ .memory = &files } },
        .limits = .{ .max_file_bytes = 8 },
    });
    defer lua.deinit();

    try lua.doString(
        \\assert(io.open('small.txt'):read('a') == '1234')
        \\local file, err, code = io.open('big.lua')
        \\assert(file == nil and err == 'big.lua: File too large' and code == 27)
        \\local missing, missing_err, missing_code = io.open('missing.txt')
        \\assert(missing == nil and missing_err == 'missing.txt: No such file or directory' and missing_code == 2)
        \\local loaded, load_err = loadfile('big.lua')
        \\assert(loaded == nil and load_err == 'cannot read big.lua: File too large')
        \\local ok, lines_err = pcall(io.lines, 'big.lua')
        \\assert(not ok and lines_err == "cannot open file 'big.lua' (File too large)")
        \\local value, fs_err = fs.read('big.lua', { max_bytes = 1024 })
        \\assert(value == nil and fs_err.code == 'io')
        \\assert(fs.read('small.txt', { max_bytes = 1024 }) == '1234')
        \\local dir = assert(io.open('dir'))
        \\local data, dir_err, dir_code = dir:read('a')
        \\assert(data == nil and dir_err == 'Is a directory' and dir_code == 21)
        \\assert(select(2, loadfile('dir')) == 'cannot read dir')
    , .{ .name = "=api-max-file-bytes" });
    try std.testing.expectError(error.LuaError, lua.loadFile("big.lua", .{}));
}

test "api base loadfile and dofile fail cleanly without filesystem access" {
    var lua = try State.init(std.testing.allocator, .{ .capabilities = .{ .io = .{ .stdin = "return 40 + 2" } } });
    defer lua.deinit();
    try lua.doString(
        \\assert(package == nil and type(loadfile) == 'function' and type(dofile) == 'function')
        \\local loaded, err = loadfile('plugin.lua')
        \\assert(loaded == nil and err == 'cannot open plugin.lua: filesystem access disabled')
        \\local ok, do_err = pcall(dofile, 'plugin.lua')
        \\assert(not ok and do_err == 'cannot open plugin.lua: filesystem access disabled')
        \\assert(dofile() == 42)
    , .{ .name = "=api-base-loadfile" });
}

test "api os.exit unwinds past pcall as error.LuaExit" {
    var lua = try State.init(std.testing.allocator, .{
        .stdlib = .full,
        .capabilities = .{ .process = .enabled },
    });
    defer lua.deinit();

    try std.testing.expectError(error.LuaExit, lua.doString(
        \\closed = false
        \\local guard <close> = setmetatable({}, { __close = function() closed = true end })
        \\pcall(os.exit, 3, true)
        \\error('unreachable')
    , .{}));
    try std.testing.expectEqual(ExitRequest{ .code = 3, .close = true }, lua.exitRequest().?);
    try std.testing.expect(try lua.getGlobal("closed", bool));

    lua.clearExitRequest();
    try std.testing.expectError(error.LuaExit, lua.doString(
        \\local co = coroutine.wrap(function() os.exit(false) end)
        \\co()
    , .{}));
    try std.testing.expectEqual(ExitRequest{ .code = 1, .close = false }, lua.exitRequest().?);
    try lua.doString("assert(true)", .{});

    var sandboxed = try State.init(std.testing.allocator, .{ .stdlib = .full });
    defer sandboxed.deinit();
    try sandboxed.doString(
        \\local ok, err = pcall(os.exit, 0)
        \\assert(not ok and err == 'process access disabled')
        \\ok, err = pcall(io.popen, 'true')
        \\assert(not ok and err == "'popen' not supported")
        \\assert(os.execute() == false)
    , .{});
    try std.testing.expect(sandboxed.exitRequest() == null);
}

test "api custom process callbacks back io.popen and os.exit" {
    const Host = struct {
        input: std.ArrayList(u8) = .empty,
        exit_code: ?i32 = null,

        fn execute(_: ?*anyopaque, command: []const u8) anyerror!ProcessResult {
            return .{ .status = .exit, .code = @intCast(command.len) };
        }

        fn popen(context: ?*anyopaque, allocator: std.mem.Allocator, command: []const u8, input: ?[]const u8) anyerror!PopenResult {
            const self: *@This() = @ptrCast(@alignCast(context.?));
            if (input) |bytes| {
                try self.input.appendSlice(std.testing.allocator, bytes);
                return .{ .result = .{ .status = .exit, .code = 4 } };
            }
            return .{ .output = try std.fmt.allocPrint(allocator, "ran {s}\nnext\n", .{command}), .result = .{ .status = .exit, .code = 0 } };
        }

        fn exit(context: ?*anyopaque, code: i32, close: bool) anyerror!void {
            const self: *@This() = @ptrCast(@alignCast(context.?));
            if (close) return error.ExitRefused;
            self.exit_code = code;
        }
    };
    var host: Host = .{};
    defer host.input.deinit(std.testing.allocator);

    var lua = try State.init(std.testing.allocator, .{
        .stdlib = .full,
        .capabilities = .{ .process = .{ .custom = .{
            .context = &host,
            .execute = Host.execute,
            .popen = Host.popen,
            .exit = Host.exit,
        } } },
    });
    defer lua.deinit();

    try std.testing.expectError(error.LuaExit, lua.doString(
        \\local reader = assert(io.popen('job'))
        \\assert(reader:read('l') == 'ran job' and reader:read('a') == 'next\n')
        \\local ok, status, code = reader:close()
        \\assert(ok == true and status == 'exit' and code == 0)
        \\local writer = assert(io.popen('sink', 'w'))
        \\writer:write('a', 1, '\n')
        \\ok, status, code = writer:close()
        \\assert(ok == nil and status == 'exit' and code == 4)
        \\assert(select('#', os.execute('abc')) == 3 and select(3, os.execute('abc')) == 3)
        \\local refused, err = pcall(os.exit, 9, true)
        \\assert(not refused and err == 'process exit failed')
        \\os.exit(9)
    , .{}));
    try std.testing.expectEqualStrings("a1\n", host.input.items);
    try std.testing.expectEqual(@as(?i32, 9), host.exit_code);
}

test "api clock callbacks provide cpu time and local offsets" {
    const Host = struct {
        fn now(_: ?*anyopaque) anyerror!i64 {
            return 86400;
        }
        fn cpu(_: ?*anyopaque) anyerror!f64 {
            return 0.25;
        }
        fn offset(_: ?*anyopaque, timestamp: i64) anyerror!UtcOffset {
            return if (timestamp >= 86400) .{ .offset = 3600, .is_dst = true } else .{ .offset = 0 };
        }
    };
    var lua = try State.init(std.testing.allocator, .{
        .stdlib = .full,
        .capabilities = .{ .clock = .{ .custom = .{ .now = Host.now, .cpu = Host.cpu, .utc_offset = Host.offset } } },
    });
    defer lua.deinit();
    try lua.doString(
        \\assert(os.clock() == 0.25)
        \\assert(os.date('%H:%M %z') == '01:00 +0100')
        \\assert(os.date('!%H:%M') == '00:00')
        \\assert(os.date('*t').isdst == true and os.date('*t', 0).isdst == false)
        \\assert(os.time({ year = 1970, month = 1, day = 2, hour = 1 }) == 86400)
    , .{});
}

test "api debug.getmetatable bypasses __metatable" {
    var lua = try State.init(std.testing.allocator, .{
        .stdlib = .full,
        .capabilities = .{ .io = .{ .stdin = "debugged = 1\nerror('oops')\ncont\nafter = true\n" } },
    });
    defer lua.deinit();
    try lua.doString(
        \\debug.debug()
        \\assert(debugged == 1 and after == nil)
        \\assert(io.read('l') == 'after = true')
    , .{});
    try lua.doString(
        \\local mt = { __metatable = 'locked' }
        \\local t = setmetatable({}, mt)
        \\assert(getmetatable(t) == 'locked' and debug.getmetatable(t) == mt)
        \\assert(debug.getmetatable(1) == nil and debug.getmetatable('') == getmetatable(''))
        \\assert(debug.setmetatable(t, nil) == t and debug.getmetatable(t) == nil)
        \\assert(select(3, package.loadlib('lib.so', 'luaopen_x')) == 'absent')
    , .{});
}

test "api custom stdout captures print and io writes" {
    var output = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer output.deinit();
    var errors = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer errors.deinit();

    var lua = try State.init(std.testing.allocator, .{
        .stdlib = .full,
        .capabilities = .{ .io = .{ .stdin = "input\n", .stdout = &output.writer, .stderr = &errors.writer } },
    });
    defer lua.deinit();

    try lua.doString(
        \\print('alpha', io.read('*l'))
        \\io.write('beta', '\n')
        \\io.stderr:write('gamma', '\n')
        \\io.flush()
        \\io.stderr:flush()
    , .{ .name = "=api-21.6-stdout" });

    try std.testing.expectEqualStrings("alpha\tinput\nbeta\n", output.writer.buffered());
    try std.testing.expectEqualStrings("gamma\n", errors.writer.buffered());
}

test "api memory filesystem backs loadfile dofile and require" {
    const files = [_]MemoryFile{
        .{ .path = "./script.lua", .contents = "return 42" },
        .{ .path = "moddir/chunk.lua", .contents = "return 7" },
        .{ .path = "plugins//plugin.lua", .contents = "return { value = 9 }" },
    };
    var lua = try State.init(std.testing.allocator, .{
        .stdlib = .full,
        .capabilities = .{ .filesystem = .{ .memory = &files } },
    });
    defer lua.deinit();
    try lua.setPackagePath("plugins/?.lua");

    try lua.doString(
        \\assert(dofile('script.lua') == 42)
        \\local chunk = assert(loadfile('moddir/chunk.lua'))
        \\assert(chunk() == 7)
        \\local plugin = require('plugin')
        \\assert(plugin.value == 9)
    , .{ .name = "=api-21.6-memory-fs" });
}

test "api extension readers accept Lua file handles" {
    const files = [_]MemoryFile{
        .{ .path = "data.json", .contents = "xx{\"name\":\"Ada\",\"nums\":[1,null]}" },
        .{ .path = "data.toml", .contents = "name = \"Ada\"\nok = true\nnums = [1, 2]\n" },
        .{ .path = "data.csv", .contents = "name,age\nAda,37\nBob,\n" },
    };
    var lua = try State.init(std.testing.allocator, .{
        .stdlib = .full,
        .capabilities = .{ .filesystem = .{ .memory = &files } },
    });
    defer lua.deinit();

    try lua.doString(
        \\local jf = assert(io.open('data.json', 'r'))
        \\assert(jf:read(2) == 'xx')
        \\local j = json.read(jf)
        \\assert(j.name == 'Ada' and j.nums[2] == json.null)
        \\assert(jf:read(0) == nil)
        \\
        \\local tf = assert(io.open('data.toml', 'r'))
        \\local t = toml.read(tf)
        \\assert(t.name == 'Ada' and t.ok == true and t.nums[2] == 2)
        \\assert(tf:read(0) == nil)
        \\
        \\local cf = assert(io.open('data.csv', 'r'))
        \\local c = csv.read(cf)
        \\assert(c[1].name == 'Ada' and c[1].age == '37')
        \\assert(c[2].age == csv.null)
        \\assert(cf:read(0) == nil)
        \\
        \\local mf = assert(io.tmpfile())
        \\assert(mf:write(msgpack.write({ name = 'Ada', ok = true, nums = { 1, msgpack.null } })))
        \\assert(mf:seek('set') == 0)
        \\local m = msgpack.read(mf)
        \\assert(m.name == 'Ada' and m.ok == true and m.nums[2] == msgpack.null)
        \\assert(mf:read(0) == nil)
        \\
        \\local closed = assert(io.open('data.json', 'r'))
        \\assert(closed:close())
        \\local ok, err = pcall(json.read, closed)
        \\assert(ok == false and tostring(err):find('json.read'))
    , .{ .name = "=api-extension-read-file-handles" });
}

test "api memory filesystem rejects sandbox escape paths" {
    const bad_files = [_]MemoryFile{
        .{ .path = "../secret.lua", .contents = "return 1" },
    };
    try std.testing.expectError(error.InvalidPath, State.init(std.testing.allocator, .{
        .stdlib = .full,
        .capabilities = .{ .filesystem = .{ .memory = &bad_files } },
    }));

    var lua = try State.init(std.testing.allocator, .{ .stdlib = .full });
    defer lua.deinit();
    try std.testing.expectError(error.InvalidPath, lua.addMemoryFile("/tmp/plugin.lua", "return 1"));
    try std.testing.expectError(error.InvalidPath, lua.addMemoryFile("plugins/../secret.lua", "return 1"));

    const files = [_]MemoryFile{
        .{ .path = "plugins/safe.lua", .contents = "return true" },
    };
    var sandboxed = try State.init(std.testing.allocator, .{
        .stdlib = .full,
        .capabilities = .{ .filesystem = .{ .memory = &files } },
    });
    defer sandboxed.deinit();
    try sandboxed.setPackagePath("../?.lua;/tmp/?.lua;plugins/?.lua");
    try sandboxed.doString(
        \\local ok, err = pcall(require, 'secret')
        \\assert(ok == false and tostring(err):find("module 'secret' not found"))
        \\assert(require('safe') == true)
    , .{ .name = "=api-memory-require-sandbox-paths" });
}

test "api package loading rejects sandbox escape module paths" {
    const files = [_]MemoryFile{
        .{ .path = "plugins/safe.lua", .contents = "return true" },
        .{ .path = "secret.lua", .contents = "return 'secret'" },
    };
    var lua = try State.init(std.testing.allocator, .{
        .stdlib = .full,
        .capabilities = .{ .filesystem = .{ .memory = &files } },
    });
    defer lua.deinit();
    try lua.setPackagePath("?.lua;plugins/?.lua;../?.lua;/tmp/?.lua");

    try lua.doString(
        \\local found, search_err = package.searchpath('../secret', '?.lua;../?.lua;/tmp/?.lua', '', '')
        \\assert(found == nil and tostring(search_err):find('no file'))
        \\local loader, loader_data = package.searchers[2]('..secret')
        \\assert(type(loader) == 'string' and loader:find('no matching file'))
        \\assert(loader_data == nil)
        \\local ok, require_err = pcall(require, '..secret')
        \\assert(ok == false and tostring(require_err):find("module '..secret' not found"))
        \\assert(require('safe') == true)
    , .{ .name = "=api-package-escape-negative" });
}

test "api environment and fixed clock capabilities are explicit" {
    var env = std.process.Environ.Map.init(std.testing.allocator);
    defer env.deinit();
    try env.put("ZLUA_API_ENV", "present");

    var lua = try State.init(std.testing.allocator, .{
        .stdlib = .full,
        .capabilities = .{
            .environment = .{ .map = &env },
            .clock = .{ .fixed = 123 },
        },
    });
    defer lua.deinit();

    try lua.doString(
        \\assert(os.getenv('ZLUA_API_ENV') == 'present')
        \\assert(os.time() == 123)
        \\assert(os.date('!%Y', 0) == '1970')
    , .{ .name = "=api-21.6-env-clock" });
}
