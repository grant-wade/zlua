const std = @import("std");
const api = @import("../api.zig");
const a = std.testing.allocator;

fn expectErrorMessage(lua: *api.State, source: []const u8, expected: []const u8) !void {
    var function = try lua.loadString(source, .{ .name = "=test" });
    defer function.deinit();
    var result = try function.protectedCall(.{}, void);
    switch (result) {
        .ok => return error.TestExpectedError,
        .lua_error => |*lua_error| {
            defer lua_error.deinit();
            const message = try lua_error.message();
            defer lua.allocator().free(message);
            if (std.mem.indexOf(u8, message, expected) == null) {
                std.debug.print("unexpected error: {s}\n", .{message});
                return error.TestUnexpectedError;
            }
        },
    }
}

test "load rejects binary chunks unless the state allows them" {
    const script =
        \\local f, err = load(string.dump(function() return 7 end))
        \\return f and f() or err
    ;
    {
        var lua = try api.State.init(a, .{});
        defer lua.deinit();
        var function = try lua.loadString(script, .{});
        defer function.deinit();
        try std.testing.expectEqualStrings("binary chunks are disabled", try function.call(.{}, []const u8));

        var dumped = try lua.loadString("return 8", .{});
        defer dumped.deinit();
        const bytes = try dumped.dumpBytecode(.{});
        defer lua.allocator().free(bytes);
        var loaded = try lua.loadBytecode(bytes, .{});
        defer loaded.deinit();
        try std.testing.expectEqual(@as(i64, 8), try loaded.call(.{}, i64));
    }
    {
        var lua = try api.State.init(a, .{ .binary_chunks = true });
        defer lua.deinit();
        var function = try lua.loadString(script, .{});
        defer function.deinit();
        try std.testing.expectEqual(@as(i64, 7), try function.call(.{}, i64));
    }
}

test "output limit counts every stream, survives pcall, and can be reset" {
    var buffer: [64]u8 = undefined;
    var sink: std.Io.Writer.Discarding = .init(&buffer);
    var lua = try api.State.init(a, .{
        .capabilities = .{ .io = .{ .stdout = &sink.writer, .stderr = &sink.writer } },
        .limits = .{ .max_output_bytes = 16 },
    });
    defer lua.deinit();

    try lua.doString("print('0123456')", .{});
    try std.testing.expectEqual(@as(u64, 8), lua.outputBytes());
    try expectErrorMessage(&lua, "pcall(print, 'more than the rest of the limit') while true do end", "output limit exceeded");
    try expectErrorMessage(&lua, "return 1", "output limit exceeded");
    try std.testing.expectEqual(@as(u64, 8), lua.outputBytes());

    lua.resetOutputLimit();
    try std.testing.expectEqual(@as(u64, 0), lua.outputBytes());
    try lua.doString("print('fine')", .{});
}

const Handle = struct {
    id: i64 = 1,

    var finalized: usize = 0;
    var gc_runs: usize = 0;

    pub fn value(self: *Handle) i64 {
        return self.id;
    }

    pub fn __gc(_: *Handle) void {
        gc_runs += 1;
    }

    fn finalize(_: *Handle, _: std.mem.Allocator) void {
        finalized += 1;
    }
};

test "finalizer budget bounds deinit and collect and host finalizers still run" {
    Handle.finalized = 0;
    var lua = try api.State.init(a, .{ .limits = .{ .max_finalizer_instructions = 10_000 } });
    var handle = try lua.newUserdataAuto(Handle, .{}, .{ .finalizer = Handle.finalize });
    try lua.setGlobal("handle", handle);
    handle.deinit();

    try lua.doString(
        \\setmetatable({}, {__gc = function() while true do end end})
        \\finalizer_kept = setmetatable({}, {__gc = function() while true do end end})
    , .{});
    try lua.collect();
    try lua.doString("assert(handle:value() == 1)", .{});
    lua.deinit();
    try std.testing.expectEqual(@as(usize, 1), Handle.finalized);
}

test "native stack limit raises a catchable error and leaves the state usable" {
    var lua = try api.State.init(a, .{ .limits = .{ .max_native_stack = 64 << 10 } });
    defer lua.deinit();
    try lua.doString(
        \\local function f() return ("x"):gsub("x", f) end
        \\local ok, message = pcall(f)
        \\assert(not ok and tostring(message):find("stack overflow", 1, true), message)
        \\local native = setmetatable({}, {__tostring = tostring})
        \\ok, message = pcall(tostring, native)
        \\assert(not ok and tostring(message):find("stack overflow", 1, true), message)
        \\local deep = ("("):rep(190) .. "1" .. (")"):rep(190)
        \\assert(not load("return " .. deep) or load("return " .. deep)() == 1)
        \\assert(load("return 1 + 1")() == 2)
    , .{});
}

test "bound __gc runs once and closes the payload" {
    Handle.gc_runs = 0;
    Handle.finalized = 0;
    var lua = try api.State.init(a, .{ .stdlib = .full });
    var handle = try lua.newUserdataAuto(Handle, .{}, .{ .finalizer = Handle.finalize });
    try lua.setGlobal("handle", handle);
    try std.testing.expect((try handle.ptr()).id == 1);

    try lua.doString(
        \\assert(getmetatable(handle) == false)
        \\local mt = debug.getmetatable(handle)
        \\mt.__gc(handle)
        \\mt.__gc(handle)
        \\local ok, message = pcall(function() return handle:value() end)
        \\assert(not ok and message:find("closed", 1, true), message)
    , .{});
    try std.testing.expectEqual(@as(usize, 1), Handle.gc_runs);
    try std.testing.expectError(error.UserdataClosed, handle.ptr());
    handle.deinit();
    lua.deinit();
    try std.testing.expectEqual(@as(usize, 1), Handle.gc_runs);
    try std.testing.expectEqual(@as(usize, 1), Handle.finalized);
}

test "expose_metatable keeps getmetatable working" {
    var lua = try api.State.init(a, .{});
    defer lua.deinit();
    try lua.defineUserdata(Handle, .{ .expose_metatable = true });
    var handle = try lua.newUserdata(Handle, .{}, .{});
    defer handle.deinit();
    try lua.setGlobal("handle", handle);
    try lua.doString("assert(type(getmetatable(handle)) == 'table')", .{});
}

test "the instruction budget charges native work" {
    var lua = try api.State.init(a, .{});
    defer lua.deinit();

    const Case = struct { source: []const u8 };
    const cases = [_]Case{
        .{ .source = "return ('a'):rep(32):find(('a-'):rep(12) .. 'b')" },
        .{ .source = "return ('x'):rep(1 << 24)" },
        .{ .source = "local s = ('x'):rep(1 << 16) return s:gsub('x', '')" },
        .{ .source = "return load(('x=1 '):rep(1 << 12))" },
        .{ .source = "local t = table.create(1 << 16) for i = 1, 1 << 16 do t[i] = i end table.sort(t) table.sort(t) return t" },
        .{ .source = "local s = ('x'):rep(1 << 22) return utf8.len(s)" },
    };
    for (cases) |case| {
        var function = try lua.loadString(case.source, .{ .name = "=charge" });
        defer function.deinit();
        var result = try function.protectedCallWith(.{}, void, .{ .max_instructions = 2_000 });
        switch (result) {
            .ok => return error.TestExpectedError,
            .lua_error => |*lua_error| lua_error.deinit(),
        }
    }

    const before = lua.instructionBudget().used;
    var loaded = try lua.loadString("return 1", .{});
    defer loaded.deinit();
    try std.testing.expectEqual(before, lua.instructionBudget().used);
}

test "garbage is collected before the memory limit fails an allocation" {
    var lua = try api.State.init(a, .{ .limits = .{ .max_memory = 16 << 20 } });
    defer lua.deinit();
    try lua.doString(
        \\for i = 1, 10 do local s = ("x"):rep(7 << 20) end
        \\for i = 1, 10 do local t = table.create(1 << 19) end
        \\collectgarbage("stop")
        \\for i = 1, 10 do local s = ("x"):rep(7 << 20) end
    , .{});
    try expectErrorMessage(&lua, "local t = {} while true do t[#t + 1] = ('x'):rep(1 << 20) .. #t end", "memory limit exceeded");
}

test "long chains compile to working code" {
    var lua = try api.State.init(a, .{});
    defer lua.deinit();
    try lua.doString(
        \\local function f() return f end
        \\_G.f = f
        \\assert(load("return f" .. ("()"):rep(50000))() == f)
        \\assert(load("return 1" .. (" + 1"):rep(50000))() == 50001)
        \\local add = load("local a = ... return a" .. (" + 1"):rep(50000))
        \\assert(add(2) == 50002)
        \\assert(load("local a = ... return a" .. (" + a"):rep(50000))(2) == 100002)
        \\assert(load("return false" .. (" or false"):rep(50000) .. " or 3")() == 3)
        \\assert(load("return true" .. (" and true"):rep(50000) .. " and 4")() == 4)
        \\assert(load("local a = ... if a" .. (" and a"):rep(50000) .. " then return 5 end")(true) == 5)
    , .{});
}

test "long chains report their real error lines" {
    var lua = try api.State.init(a, .{});
    defer lua.deinit();
    try expectErrorMessage(&lua,
        \\local function f() return nil end
        \\return f()
        \\  ()
    , "test:3:");
}

test "interrupts stop host compilation" {
    var lua = try api.State.init(a, .{});
    defer lua.deinit();
    const handle = try lua.interruptHandle();
    handle.interrupt();
    try std.testing.expectError(error.Interrupted, lua.loadString("return 1", .{}));
    try std.testing.expect(!lua.isInterruptPending());
    var loaded = try lua.loadString("return 1", .{});
    defer loaded.deinit();
}

test "decoding rejects tables nested through themselves" {
    const Tree = struct {
        name: i64 = 0,
        kids: []const @This() = &.{},
    };
    var lua = try api.State.init(a, .{});
    defer lua.deinit();
    try lua.doString("cycle = {name = 1} cycle.kids = {cycle}", .{});
    var cycle = try lua.getGlobal("cycle", api.Value);
    defer cycle.deinit();

    var arena: std.heap.ArenaAllocator = .init(a);
    defer arena.deinit();
    var diagnostic: api.Diagnostic = .{ .gpa = a };
    defer diagnostic.deinit();
    try std.testing.expectError(error.Invalid, api.decode(Tree, cycle, .{ .allocator = arena.allocator(), .diagnostic = &diagnostic }));
}

test "reset undoes what a script changed in shared state" {
    var lua = try api.State.init(a, .{ .stdlib = .full, .limits = .{ .max_output_bytes = 1 << 16, .max_instructions = 10_000_000 } });
    defer lua.deinit();
    try lua.doString(
        \\pristine = string.rep
        \\math.randomseed(42)
    , .{});
    var snapshot = try lua.snapshot(a);
    defer snapshot.deinit();
    try lua.doString(
        \\baseline_random = math.random(1 << 40)
    , .{});
    const first = try lua.getGlobal("baseline_random", i64);
    try lua.reset();

    try lua.doString(
        \\string.rep = function() return "hijacked" end
        \\getmetatable("").__index = function() return "hijacked" end
        \\getmetatable("").__add = function() return "hijacked" end
        \\table.insert = nil
        \\_G.leak = {1, 2, 3}
        \\print = function() return "hijacked" end
        \\package.loaded.string = nil
        \\debug.setmetatable(1, {__index = function() return "hijacked" end})
        \\setmetatable(_G, {__index = function() return "hijacked" end})
        \\co = coroutine.wrap(function() coroutine.yield() end) co()
        \\collectgarbage("stop")
        \\math.randomseed(7)
    , .{});
    try lua.reset();

    try lua.doString(
        \\assert(string.rep == pristine and ("x"):rep(2) == "xx")
        \\assert(getmetatable("").__add == nil and getmetatable("").__index == string)
        \\assert(table.insert ~= nil and leak == nil and co == nil)
        \\assert(package.loaded.string == string)
        \\assert(debug.getmetatable(1) == nil and getmetatable(_G) == nil)
        \\assert(collectgarbage("isrunning"))
        \\assert(print ~= nil and type(print) == "function")
        \\baseline_random = math.random(1 << 40)
    , .{});
    try std.testing.expectEqual(first, try lua.getGlobal("baseline_random", i64));
    try std.testing.expectEqual(@as(u64, 0), lua.outputBytes());
}

test "file handles fail cleanly when a script exhausts the descriptor limit" {
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const io = std.testing.io;
    try temporary.dir.writeFile(io, .{ .sub_path = "f.txt", .data = "data" });
    var root = try temporary.dir.openDir(io, ".", .{});
    defer root.close(io);
    var lua = try api.State.init(a, .{
        .stdlib = .full,
        .capabilities = .{ .io = .{ .runtime = io }, .filesystem = .{ .host_dir = .{ .dir = root } } },
    });
    defer lua.deinit();
    try lua.doString(
        \\local files = {}
        \\for i = 1, 100000 do
        \\  local f, err = io.open("f.txt")
        \\  if not f then
        \\    assert(type(err) == "string")
        \\    break
        \\  end
        \\  files[i] = f
        \\end
        \\for _, f in ipairs(files) do f:close() end
        \\assert(io.open("f.txt")):close()
    , .{});
}
