const std = @import("std");
const builtin = @import("builtin");
const zlua = @import("zlua");

var heap_buffer: [4 * 1024 * 1024]u8 align(16) = undefined;

export fn _start() noreturn {
    run() catch exit(1);
    exit(0);
}

export fn smoke() bool {
    run() catch return false;
    return true;
}

fn run() !void {
    var fixed = std.heap.FixedBufferAllocator.init(&heap_buffer);
    var host = Host{
        .filesystem = zlua.MemoryFilesystem.init(fixed.allocator()),
    };
    defer host.filesystem.deinit();
    try host.filesystem.writeFile("boot/init.lua", "return 'booted'");
    try host.filesystem.writeFile("mod.lua", "return { answer = 42 }");

    var lua = try zlua.State.init(fixed.allocator(), .{
        .stdlib = .full,
        .capabilities = .{
            .io = .{ .stdin = "kernel input\n" },
            .filesystem = .{ .custom = .{
                .context = &host,
                .read_file_alloc = Host.readFileAlloc,
                .write_file = Host.writeFile,
                .remove_file = Host.removeFile,
                .rename_file = Host.renameFile,
                .stat = Host.stat,
                .read_dir_alloc = Host.readDirAlloc,
                .make_dir = Host.makeDir,
                .remove_path = Host.removePath,
                .copy_file = Host.copyFile,
            } },
            .environment = .{ .custom = .{
                .context = &host,
                .get = Host.getenv,
            } },
            .clock = .{ .custom = .{
                .context = &host,
                .now = Host.now,
            } },
            .process = .{ .custom = .{
                .context = &host,
                .execute = Host.execute,
            } },
        },
        .limits = .{ .max_instructions = 200_000 },
    });
    defer lua.deinit();

    try lua.doString(
        \\assert(_VERSION == 'Lua 5.5')
        \\assert(io ~= nil and os ~= nil and package ~= nil and debug ~= nil and fs ~= nil)
        \\assert(fs.path.join('boot', 'init.lua') == 'boot/init.lua')
        \\
        \\local t = { 3, 1, 2 }
        \\table.sort(t)
        \\assert(table.concat(t, ',') == '1,2,3')
        \\assert(string.reverse('abc') == 'cba')
        \\assert(string.pack('>I2', 0x1234) == string.char(0x12, 0x34))
        \\local size_limit = string.packsize('T') == 4 and 0xffffffff or math.maxinteger
        \\local halves = 'c' .. (size_limit // 2) .. 'c' .. (size_limit // 2)
        \\assert(string.packsize(halves) == size_limit - 1)
        \\assert(string.packsize(halves .. 'x') == size_limit)
        \\assert(not pcall(string.packsize, halves .. 'xx'))
        \\assert(not pcall(string.packsize, 'c' .. size_limit .. '0'))
        \\assert(math.max(1, 5, 3) == 5)
        \\assert(utf8.len('hello') == 5)
        \\
        \\local co = coroutine.create(function(x)
        \\  coroutine.yield(x + 1)
        \\  return x + 2
        \\end)
        \\local ok, value = coroutine.resume(co, 40)
        \\assert(ok and value == 41)
        \\ok, value = coroutine.resume(co, 40)
        \\assert(ok and value == 42)
        \\
        \\local json_value = json.read('{"name":"Ada","nums":[1,null]}')
        \\assert(json_value.name == 'Ada' and json_value.nums[2] == json.null)
        \\assert(json.write({ ok = true }):find('"ok":true') ~= nil)
        \\local toml_value = toml.read('name = "Ada"\nok = true\n')
        \\assert(toml_value.name == 'Ada' and toml_value.ok == true)
        \\local csv_value = csv.read('name,age\nAda,37\nBob,\n')
        \\assert(csv_value[1].name == 'Ada' and csv_value[2].age == csv.null)
        \\local msgpack_value = msgpack.read(msgpack.write({ name = 'Ada', ok = true }))
        \\assert(msgpack_value.name == 'Ada' and msgpack_value.ok == true)
        \\assert(not pcall(msgpack.write, { [0xffffffff] = true }))
        \\assert(not pcall(msgpack.write, { [0x100000000] = true }))
        \\local sequence = msgpack.read(msgpack.write({ 1, false, 'three', msgpack.null }))
        \\assert(#sequence == 4 and sequence[1] == 1 and sequence[2] == false)
        \\assert(sequence[3] == 'three' and sequence[4] == msgpack.null)
        \\
        \\assert(os.getenv('KERNEL_ENV') == 'present')
        \\assert(os.time() == 123456)
        \\local ok, why, code = os.execute('true')
        \\assert(ok == true and why == 'exit' and code == 0)
        \\ok, why, code = os.execute('false')
        \\assert(ok == nil and why == 'exit' and code == 7)
        \\
        \\assert(dofile('boot/init.lua') == 'booted')
        \\local loaded = assert(loadfile('boot/init.lua'))
        \\assert(loaded() == 'booted')
        \\assert(require('mod').answer == 42)
        \\assert(fs.stat('boot').kind == 'directory')
        \\local boot_entries = assert(fs.list('boot'))
        \\assert(#boot_entries == 1 and boot_entries[1].name == 'init.lua')
        \\assert(fs.mkdir('work/deep', { parents = true }))
        \\assert(fs.write('work/deep/value.txt', 'custom fs'))
        \\assert(fs.read('work/deep/value.txt') == 'custom fs')
        \\assert(fs.remove('work', { recursive = true }))
        \\local input = io.read('l')
        \\assert(input == 'kernel input')
        \\local f = assert(io.open('tmp.txt', 'w'))
        \\assert(f:write('hello from kernel fs'))
        \\assert(f:close())
        \\f = assert(io.open('tmp.txt', 'r'))
        \\assert(f:read('a') == 'hello from kernel fs')
        \\assert(f:close())
        \\assert(os.rename('tmp.txt', 'renamed.txt'))
        \\assert(assert(io.open('renamed.txt', 'r')):read('a') == 'hello from kernel fs')
        \\assert(os.remove('renamed.txt'))
    , .{ .name = "=freestanding-custom-host-profile" });
}

const Host = struct {
    filesystem: zlua.MemoryFilesystem,

    fn fromContext(context: ?*anyopaque) *Host {
        return @ptrCast(@alignCast(context.?));
    }

    fn readFileAlloc(context: ?*anyopaque, allocator: std.mem.Allocator, path: []const u8) ![]const u8 {
        return fromContext(context).filesystem.readFileAlloc(allocator, path);
    }

    fn writeFile(context: ?*anyopaque, path: []const u8, contents: []const u8) !void {
        try fromContext(context).filesystem.writeFile(path, contents);
    }

    fn removeFile(context: ?*anyopaque, path: []const u8) !void {
        try fromContext(context).filesystem.removeFile(path);
    }

    fn renameFile(context: ?*anyopaque, old_path: []const u8, new_path: []const u8) !void {
        try fromContext(context).filesystem.renameFile(old_path, new_path);
    }

    fn stat(context: ?*anyopaque, path: []const u8, follow_symlinks: bool) !zlua.FilesystemFileStat {
        _ = follow_symlinks;
        return fromContext(context).filesystem.statPath(path);
    }

    fn readDirAlloc(context: ?*anyopaque, allocator: std.mem.Allocator, path: []const u8) ![]zlua.FilesystemDirectoryEntry {
        return fromContext(context).filesystem.readDirAlloc(allocator, path);
    }

    fn makeDir(context: ?*anyopaque, path: []const u8, parents: bool) !void {
        try fromContext(context).filesystem.makeDir(path, parents);
    }

    fn removePath(context: ?*anyopaque, path: []const u8, recursive: bool) !void {
        try fromContext(context).filesystem.removePath(path, recursive);
    }

    fn copyFile(context: ?*anyopaque, source: []const u8, destination: []const u8, overwrite: bool) !void {
        try fromContext(context).filesystem.copyFile(source, destination, overwrite);
    }

    fn getenv(context: ?*anyopaque, name: []const u8) ?[]const u8 {
        _ = context;
        if (std.mem.eql(u8, name, "KERNEL_ENV")) return "present";
        return null;
    }

    fn now(context: ?*anyopaque) !i64 {
        _ = context;
        return 123456;
    }

    fn execute(context: ?*anyopaque, command: []const u8) !zlua.ProcessResult {
        _ = context;
        if (std.mem.eql(u8, command, "true")) return .{ .status = .exit, .code = 0 };
        if (std.mem.eql(u8, command, "false")) return .{ .status = .exit, .code = 7 };
        return .{ .status = .signal, .code = 0 };
    }
};

fn exit(code: u8) noreturn {
    if (comptime builtin.target.cpu.arch == .wasm32) @trap();
    if (comptime builtin.target.cpu.arch != .x86_64) @compileError("freestanding smoke test uses x86_64 Linux syscall ABI");

    asm volatile ("syscall"
        :
        : [number] "{rax}" (@as(u64, 60)),
          [arg1] "{rdi}" (@as(u64, code)),
        : .{ .rcx = true, .r11 = true, .memory = true });
    unreachable;
}

fn panicExit() noreturn {
    exit(255);
}

pub const panic = struct {
    pub fn call(msg: []const u8, ra: ?usize) noreturn {
        _ = msg;
        _ = ra;
        panicExit();
    }

    pub fn sentinelMismatch(expected: anytype, found: @TypeOf(expected)) noreturn {
        _ = found;
        panicExit();
    }

    pub fn unwrapError(err: anyerror) noreturn {
        _ = &err;
        panicExit();
    }

    pub fn outOfBounds(index: usize, len: usize) noreturn {
        _ = index;
        _ = len;
        panicExit();
    }

    pub fn startGreaterThanEnd(start: usize, end: usize) noreturn {
        _ = start;
        _ = end;
        panicExit();
    }

    pub fn inactiveUnionField(active: anytype, accessed: @TypeOf(active)) noreturn {
        _ = accessed;
        panicExit();
    }

    pub fn sliceCastLenRemainder(src_len: usize) noreturn {
        _ = src_len;
        panicExit();
    }

    pub fn reachedUnreachable() noreturn {
        panicExit();
    }

    pub fn unwrapNull() noreturn {
        panicExit();
    }

    pub fn castToNull() noreturn {
        panicExit();
    }

    pub fn incorrectAlignment() noreturn {
        panicExit();
    }

    pub fn invalidErrorCode() noreturn {
        panicExit();
    }

    pub fn integerOutOfBounds() noreturn {
        panicExit();
    }

    pub fn integerOverflow() noreturn {
        panicExit();
    }

    pub fn shlOverflow() noreturn {
        panicExit();
    }

    pub fn shrOverflow() noreturn {
        panicExit();
    }

    pub fn divideByZero() noreturn {
        panicExit();
    }

    pub fn exactDivisionRemainder() noreturn {
        panicExit();
    }

    pub fn integerPartOutOfBounds() noreturn {
        panicExit();
    }

    pub fn corruptSwitch() noreturn {
        panicExit();
    }

    pub fn shiftRhsTooBig() noreturn {
        panicExit();
    }

    pub fn invalidEnumValue() noreturn {
        panicExit();
    }

    pub fn forLenMismatch() noreturn {
        panicExit();
    }

    pub fn copyLenMismatch() noreturn {
        panicExit();
    }

    pub fn memcpyAlias() noreturn {
        panicExit();
    }

    pub fn noreturnReturned() noreturn {
        panicExit();
    }
};
