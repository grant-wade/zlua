const std = @import("std");
const api = @import("../api.zig");
const handle = @import("../api/handle.zig");
const userdata_mod = @import("../api/userdata.zig");
const AnyUserdata = api.AnyUserdata;
const Context = api.Context;
const Function = api.Function;
const MemoryFile = api.MemoryFile;
const Ref = api.Ref;
const State = api.State;
const Table = api.Table;
const Tuple = api.Tuple;
const Userdata = api.Userdata;

test "api state initializes with safe defaults" {
    var lua = try State.init(std.testing.allocator, .{});
    defer lua.deinit();

    try lua.doString("assert(_VERSION == 'Lua 5.5')", .{});
    try std.testing.expectError(error.LuaError, lua.doFile("missing.lua", .{}));

    const message = try lua.errorMessage();
    defer lua.allocator().free(message);
    try std.testing.expect(std.mem.indexOf(u8, message, "filesystem access disabled") != null);
}

test "api safe stdlib excludes ambient capability libraries" {
    var lua = try State.init(std.testing.allocator, .{});
    defer lua.deinit();

    try lua.doString(
        \\assert(io == nil)
        \\assert(os == nil)
        \\assert(debug == nil)
        \\assert(package == nil)
        \\assert(require == nil)
    , .{ .name = "=api-safe-stdlib-negative" });
}

test "api none stdlib keeps a global environment without libraries" {
    var lua = try State.init(std.testing.allocator, .{ .stdlib = .none });
    defer lua.deinit();

    try lua.setGlobal("host_value", 41);
    var chunk = try lua.loadString(
        "host_value = host_value + 1; return host_value == 42 and _G == _ENV and print == nil and math == nil",
        .{ .name = "=api-none-stdlib" },
    );
    defer chunk.deinit();

    try std.testing.expect(try chunk.call(.{}, bool));
    try std.testing.expectEqual(@as(i64, 42), try lua.getGlobal("host_value", i64));
}

test "api can open custom libraries after none" {
    var lua = try State.init(std.testing.allocator, .{ .stdlib = .none });
    defer lua.deinit();

    try lua.setGlobal("host_value", 81);
    var chunk = try lua.loadString("return math.sqrt(host_value)", .{ .name = "=api-open-after-none" });
    defer chunk.deinit();

    try lua.openLibs(.{ .custom = .{ .math = true } });
    try std.testing.expectEqual(@as(f64, 9), try chunk.call(.{}, f64));
}

test "api custom stdlib opens only selected libraries" {
    var lua = try State.init(std.testing.allocator, .{
        .stdlib = .{ .custom = .{ .math = true, .json = true } },
    });
    defer lua.deinit();

    var chunk = try lua.loadString(
        "return math ~= nil and json ~= nil and string == nil and print == nil",
        .{ .name = "=api-custom-stdlib" },
    );
    defer chunk.deinit();

    try std.testing.expect(try chunk.call(.{}, bool));
}

test "api load string, do string, and protected error" {
    var lua = try State.init(std.testing.allocator, .{});
    defer lua.deinit();

    var chunk = try lua.loadString("assert(1 + 1 == 2)", .{ .name = "=unit" });
    defer chunk.deinit();
    try chunk.call(.{}, void);

    var failing = try lua.loadString("error('boom')", .{ .name = "=unit" });
    defer failing.deinit();

    const result = try failing.protectedCall(.{}, void);
    switch (result) {
        .ok => return error.TestExpectedLuaError,
        .lua_error => |err_ref| {
            var err = err_ref;
            defer err.deinit();
            const message = try err.message();
            defer lua.allocator().free(message);
            try std.testing.expect(std.mem.indexOf(u8, message, "boom") != null);
        },
    }
}

test "api do file uses memory filesystem and reports source names" {
    const files = [_]MemoryFile{
        .{ .path = "ok.lua", .contents = "assert(2 * 3 == 6)" },
        .{ .path = "bad.lua", .contents = "return (" },
    };
    var lua = try State.init(std.testing.allocator, .{
        .capabilities = .{ .filesystem = .{ .memory = &files } },
    });
    defer lua.deinit();

    try lua.doFile("ok.lua", .{ .name = "@ok.lua" });
    try std.testing.expectError(error.LuaError, lua.doFile("bad.lua", .{ .name = "@bad.lua" }));

    const message = try lua.errorMessage();
    defer lua.allocator().free(message);
    try std.testing.expect(std.mem.indexOf(u8, message, "bad.lua") != null);
}

test "api primitive values round trip through calls and conversion" {
    var lua = try State.init(std.testing.allocator, .{});
    defer lua.deinit();

    var identity = try lua.loadString("return ...", .{ .name = "=identity" });
    defer identity.deinit();

    try std.testing.expectEqual(true, try identity.call(.{true}, bool));
    try std.testing.expectEqual(@as(i64, -42), try identity.call(.{-42}, i64));
    try std.testing.expectEqual(@as(u8, 42), try identity.call(.{42}, u8));
    try std.testing.expectEqual(@as(f64, 1.5), try identity.call(.{1.5}, f64));
    try std.testing.expectEqualStrings("hello", try identity.call(.{"hello"}, []const u8));

    const pushed = try lua.push(@as(i64, 123));
    try std.testing.expectEqual(@as(i64, 123), try lua.read(pushed, i64));
}

test "api tuple helper reads multiple returns" {
    var lua = try State.init(std.testing.allocator, .{});
    defer lua.deinit();

    var chunk = try lua.loadString("return true, 42, 'ok'", .{ .name = "=tuple" });
    defer chunk.deinit();

    const Result = Tuple(&.{ bool, i64, []const u8 });
    var result = try chunk.call(.{}, Result);
    defer result.deinit();

    try std.testing.expectEqual(true, result.get(0));
    try std.testing.expectEqual(@as(i64, 42), result.get(1));
    try std.testing.expectEqualStrings("ok", result.get(2));
}

test "api public handles survive forced GC" {
    const Counter = struct {
        value: i64,
    };

    var lua = try State.init(std.testing.allocator, .{});
    defer lua.deinit();

    var ref_chunk = try lua.loadString("return { answer = 42 }", .{ .name = "=ref-handle" });
    var ref = try ref_chunk.call(.{}, Ref);
    ref_chunk.deinit();
    defer ref.deinit();

    try lua.collect();
    var ref_value = try ref.value();
    defer ref_value.deinit();
    switch (ref_value) {
        .table => |table| try std.testing.expectEqual(@as(i64, 42), try table.get("answer", i64)),
        else => return error.TypeMismatch,
    }

    var table = try lua.createTable(.{ .hash_hint = 1 });
    defer table.deinit();
    try table.set("answer", 43);

    try lua.collect();
    try std.testing.expectEqual(@as(i64, 43), try table.get("answer", i64));

    var function_chunk = try lua.loadString("return function(x) return x + 1 end", .{ .name = "=function-handle" });
    var function = try function_chunk.call(.{}, Function);
    function_chunk.deinit();
    defer function.deinit();

    try lua.collect();
    try std.testing.expectEqual(@as(i64, 44), try function.call(.{43}, i64));

    var value = try lua.push(.{ .answer = 45 });
    defer value.deinit();

    try lua.collect();
    switch (value) {
        .table => |value_table| try std.testing.expectEqual(@as(i64, 45), try value_table.get("answer", i64)),
        else => return error.TypeMismatch,
    }

    var tuple_chunk = try lua.loadString(
        \\local t = { answer = 46 }
        \\local function f(x) return x + 1 end
        \\return t, f
    , .{ .name = "=tuple-handle" });

    const Result = Tuple(&.{ Table, Function });
    var result = try tuple_chunk.call(.{}, Result);
    tuple_chunk.deinit();
    defer result.deinit();

    try lua.collect();
    try std.testing.expectEqual(@as(i64, 46), try result.get(0).get("answer", i64));
    try std.testing.expectEqual(@as(i64, 47), try result.get(1).call(.{46}, i64));

    var userdata = try lua.newUserdata(Counter, .{ .value = 48 }, .{});
    defer userdata.deinit();

    try lua.collect();
    try std.testing.expectEqual(@as(i64, 48), (try userdata.ptr()).value);

    var typed_userdata = try lua.newUserdata(Counter, .{ .value = 49 }, .{});
    var any_chunk = try lua.loadString("return ...", .{ .name = "=any-userdata-handle" });
    var any_userdata = try any_chunk.call(.{typed_userdata}, AnyUserdata);
    any_chunk.deinit();
    typed_userdata.deinit();
    defer any_userdata.deinit();

    try lua.collect();
    switch (try handle.rawValue(any_userdata.ref)) {
        .userdata => |raw| try std.testing.expectEqual(@as(i64, 49), (try userdata_mod.payloadPtr(Counter, raw)).value),
        else => return error.TypeMismatch,
    }
}

test "api error refs survive forced GC" {
    var lua = try State.init(std.testing.allocator, .{});
    defer lua.deinit();

    var failing = try lua.loadString("error({ message = 'boom' }, 0)", .{ .name = "=error-ref-gc" });
    var err = blk: {
        const result = try failing.protectedCall(.{}, void);
        switch (result) {
            .ok => return error.TestExpectedLuaError,
            .lua_error => |err_ref| break :blk err_ref,
        }
    };
    failing.deinit();
    defer err.deinit();

    if (lua.takeErrorValue()) |last_error_ref| {
        var last = last_error_ref;
        last.deinit();
    }
    lua.raw_state.last_error = null;

    try lua.collect();
    var value = try err.value();
    defer value.deinit();
    switch (value) {
        .table => |table| try std.testing.expectEqualStrings("boom", try table.get("message", []const u8)),
        else => return error.TypeMismatch,
    }
}

test "api callback argument roots survive forced GC through weak tables" {
    const Tracker = struct {
        id: i64,
    };
    const Callbacks = struct {
        fn stress(ctx: *Context) !void {
            var payload = try ctx.arg(0, Table);
            defer payload.deinit();
            var tracker = try ctx.arg(1, Userdata(Tracker));
            defer tracker.deinit();
            var check = try ctx.arg(2, Function);
            defer check.deinit();

            try ctx.state().collect();
            try std.testing.expectEqualStrings("payload", try payload.get("name", []const u8));
            try std.testing.expectEqual(@as(i64, 7), (try tracker.ptr()).id);

            const CheckResult = Tuple(&.{ []const u8, bool });
            var checked = try check.call(.{}, CheckResult);
            defer checked.deinit();
            try std.testing.expectEqualStrings("payload", checked.get(0));
            try std.testing.expectEqual(true, checked.get(1));

            try ctx.state().collect();
            try ctx.returnValues(.{ try payload.get("name", []const u8), (try tracker.ptr()).id });
        }
    };

    var lua = try State.init(std.testing.allocator, .{});
    defer lua.deinit();

    var tracker = try lua.newUserdata(Tracker, .{ .id = 7 }, .{});
    defer tracker.deinit();

    var stress = try lua.register("stress_roots", Callbacks.stress);
    defer stress.deinit();
    try lua.setGlobal("stress_roots", stress);

    var chunk = try lua.loadString(
        \\local tracker = ...
        \\local weak = setmetatable({}, { __mode = 'v' })
        \\local payload = { name = 'payload' }
        \\weak.payload = payload
        \\weak.tracker = tracker
        \\return stress_roots(payload, weak.tracker, function()
        \\  collectgarbage('collect')
        \\  return weak.payload.name, weak.tracker ~= nil
        \\end)
    , .{ .name = "=api-callback-root-stress" });
    defer chunk.deinit();

    const Result = Tuple(&.{ []const u8, i64 });
    var result = try chunk.call(.{tracker}, Result);
    defer result.deinit();
    try std.testing.expectEqualStrings("payload", result.get(0));
    try std.testing.expectEqual(@as(i64, 7), result.get(1));
}

test "api native callback dispatch tolerates forced GC" {
    const Callbacks = struct {
        fn stress(ctx: *Context) !void {
            var callback = try ctx.arg(0, Function);
            defer callback.deinit();

            try ctx.state().collect();
            const returned = try callback.call(.{"native"}, []const u8);
            try ctx.returnValues(.{returned});
        }
    };

    var lua = try State.init(std.testing.allocator, .{});
    defer lua.deinit();

    var stress = try lua.register("stress_callback_gc", Callbacks.stress);
    defer stress.deinit();
    try lua.setGlobal("stress_callback_gc", stress);

    var chunk = try lua.loadString(
        \\return stress_callback_gc(function(value)
        \\  collectgarbage('collect')
        \\  return value .. '-callback'
        \\end)
    , .{ .name = "=api-callback-dispatch-gc" });
    defer chunk.deinit();

    try std.testing.expectEqualStrings("native-callback", try chunk.call(.{}, []const u8));
}

test "api userdata handles root weak values until finalizers can run" {
    const Tracker = struct {
        finalized: *usize,

        fn finalize(self: *@This()) void {
            self.finalized.* += 1;
        }
    };

    var lua = try State.init(std.testing.allocator, .{});
    defer lua.deinit();

    var finalized: usize = 0;
    var tracker = try lua.newUserdata(Tracker, .{ .finalized = &finalized }, .{ .finalizer = Tracker.finalize });
    try lua.setGlobal("tracker", tracker);
    try lua.doString(
        \\weak_trackers = setmetatable({}, { __mode = 'v' })
        \\weak_trackers.item = tracker
    , .{ .name = "=api-userdata-root-weak-setup" });
    try lua.setGlobal("tracker", null);

    try lua.collect();
    try std.testing.expectEqual(@as(usize, 0), finalized);
    try lua.doString("assert(weak_trackers.item ~= nil)", .{ .name = "=api-userdata-root-weak-alive" });

    tracker.deinit();
    try lua.collect();
    try lua.collect();
    try std.testing.expectEqual(@as(usize, 1), finalized);
    try lua.doString("assert(weak_trackers.item == nil)", .{ .name = "=api-userdata-root-weak-collected" });
}

test "api error value refs root weak-table values through forced GC" {
    var lua = try State.init(std.testing.allocator, .{});
    defer lua.deinit();

    var failing = try lua.loadString(
        \\weak_errors = setmetatable({}, { __mode = 'v' })
        \\local err = { tag = 'kept' }
        \\weak_errors.err = err
        \\error(err, 0)
    , .{ .name = "=api-error-root-weak" });
    var err = blk: {
        const result = try failing.protectedCall(.{}, void);
        switch (result) {
            .ok => return error.TestExpectedLuaError,
            .lua_error => |err_ref| break :blk err_ref,
        }
    };
    failing.deinit();

    if (lua.takeErrorValue()) |last_error_ref| {
        var last = last_error_ref;
        last.deinit();
    }
    lua.raw_state.last_error = null;

    try lua.collect();
    var value = try err.value();
    switch (value) {
        .table => |table| try std.testing.expectEqualStrings("kept", try table.get("tag", []const u8)),
        else => return error.TypeMismatch,
    }
    value.deinit();

    var check_alive = try lua.loadString("return weak_errors.err and weak_errors.err.tag or 'gone'", .{ .name = "=api-error-root-weak-alive" });
    defer check_alive.deinit();
    try std.testing.expectEqualStrings("kept", try check_alive.call(.{}, []const u8));

    err.deinit();
    try lua.collect();
    try lua.doString("assert(weak_errors.err == nil)", .{ .name = "=api-error-root-weak-collected" });
}

test "api released handles remove runtime roots" {
    var lua = try State.init(std.testing.allocator, .{});
    defer lua.deinit();

    try std.testing.expectEqual(@as(usize, 0), lua.raw_state.activeRootCount());

    var chunk = try lua.loadString("return { alive = true }", .{ .name = "=root-count" });
    try std.testing.expectEqual(@as(usize, 1), lua.raw_state.activeRootCount());

    var table = try chunk.call(.{}, Table);
    try std.testing.expectEqual(@as(usize, 2), lua.raw_state.activeRootCount());

    try lua.collect();
    try std.testing.expectEqual(true, try table.get("alive", bool));

    table.deinit();
    try std.testing.expectEqual(@as(usize, 1), lua.raw_state.activeRootCount());
    chunk.deinit();
    try std.testing.expectEqual(@as(usize, 0), lua.raw_state.activeRootCount());

    try lua.collect();
}

test "api globals tables arrays and structs build Lua environments" {
    var lua = try State.init(std.testing.allocator, .{});
    defer lua.deinit();

    try lua.setGlobal("answer", 42);
    try std.testing.expectEqual(@as(i64, 42), try lua.getGlobal("answer", i64));

    var config = try lua.createTable(.{ .hash_hint = 4 });
    defer config.deinit();
    try config.set("title", "demo");
    try config.set("max_players", 8);
    try config.set("debug", true);
    try lua.setGlobal("config", config);

    try lua.setGlobal("search_path", &.{ "scripts/?.lua", "scripts/?/init.lua" });
    try lua.setGlobal("app", .{
        .name = "zlua-host",
        .version = 1,
        .features = &.{ "plugins", "sandbox" },
    });

    try lua.doString(
        \\assert(config.title == 'demo')
        \\assert(config.max_players == 8)
        \\assert(config.debug == true)
        \\assert(search_path[1] == 'scripts/?.lua')
        \\assert(search_path[2] == 'scripts/?/init.lua')
        \\assert(app.name == 'zlua-host')
        \\assert(app.version == 1)
        \\assert(app.features[1] == 'plugins')
        \\assert(app.features[2] == 'sandbox')
    , .{ .name = "=api-21.3-env" });

    var app = try lua.getGlobal("app", Table);
    defer app.deinit();
    var features = try app.get("features", Table);
    defer features.deinit();
    try std.testing.expectEqualStrings("sandbox", try features.get(2, []const u8));
}

test "api loaded module is returned by require" {
    var lua = try State.init(std.testing.allocator, .{});
    defer lua.deinit();

    var host = try lua.createModule("host");
    defer host.deinit();
    try host.set("name", "host-module");
    try host.set("version", 3);
    try lua.setLoadedModule("host", host);

    try lua.doString(
        \\local host = require('host')
        \\assert(host.name == 'host-module')
        \\assert(host.version == 3)
    , .{ .name = "=api-21.3-preload" });
}

test "api package path loads memory backed Lua modules" {
    var lua = try State.init(std.testing.allocator, .{});
    defer lua.deinit();

    try lua.addMemoryFile("plugins/mathx.lua",
        \\local M = {}
        \\function M.double(x) return x * 2 end
        \\return M
    );
    try lua.setPackagePath("plugins/?.lua");

    try lua.doString(
        \\local mathx = require('mathx')
        \\assert(mathx.double(21) == 42)
    , .{ .name = "=api-21.3-memory-require" });
}

test "api load options support environments and binary modes" {
    var lua = try State.init(std.testing.allocator, .{ .stdlib = .full });
    defer lua.deinit();

    var env = try lua.createTable(.{ .hash_hint = 1 });
    defer env.deinit();
    try env.set("secret", 42);

    var source_chunk = try lua.loadString("return secret", .{ .name = "=api-21.6-env", .environment = env });
    defer source_chunk.deinit();
    try std.testing.expectEqual(@as(i64, 42), try source_chunk.call(.{}, i64));

    var dumper = try lua.loadString("return string.dump(function() return secret end)", .{ .name = "=api-21.6-dump" });
    defer dumper.deinit();
    const dumped = try dumper.call(.{}, []const u8);

    var binary_chunk = try lua.loadString(dumped, .{ .mode = .source_or_binary, .environment = env });
    defer binary_chunk.deinit();
    try std.testing.expectEqual(@as(i64, 42), try binary_chunk.call(.{}, i64));

    try std.testing.expectError(error.LuaError, lua.loadString(dumped, .{ .mode = .source_only }));
    try std.testing.expectError(error.LuaError, lua.loadString("return 1", .{ .mode = .binary_only }));
}

test "api dumps and loads zlua bytecode" {
    var source_state = try State.init(std.testing.allocator, .{});
    defer source_state.deinit();

    var source_chunk = try source_state.loadString("return secret, ...", .{ .name = "=api-bytecode" });
    defer source_chunk.deinit();

    const dumped = try source_chunk.dumpBytecode(.{ .strip_debug = true });
    defer source_state.allocator().free(dumped);

    var target_state = try State.init(std.testing.allocator, .{});
    defer target_state.deinit();

    var env = try target_state.createTable(.{ .hash_hint = 1 });
    defer env.deinit();
    try env.set("secret", "roundtrip");

    var loaded = try target_state.loadBytecode(dumped, .{ .environment = env });
    defer loaded.deinit();

    const Result = Tuple(&.{ []const u8, i64 });
    var result = try loaded.call(.{42}, Result);
    defer result.deinit();

    try std.testing.expectEqualStrings("roundtrip", result.get(0));
    try std.testing.expectEqual(@as(i64, 42), result.get(1));
    try std.testing.expectError(error.LuaError, target_state.loadBytecode("return 1", .{}));
}

test "collections free chunk prototypes once their closures are unreachable" {
    var lua = try State.init(std.testing.allocator, .{});
    defer lua.deinit();

    try lua.doString(
        \\keep = {}
        \\for i = 1, 200 do
        \\  local chunk = load("local t = { ['k' .. " .. i .. "] = 0 } t.field" .. i .. " = " .. i .. " return t, function() return " .. i .. " end")
        \\  local t, f = chunk()
        \\  if i % 50 == 0 then keep[#keep + 1] = { t, f } end
        \\end
        \\collectgarbage()
    , .{});
    try std.testing.expect(lua.raw_state.proto_allocations.items.len - lua.raw_state.borrowed_proto_count < 20);
    try std.testing.expectEqual(lua.raw_state.gc.allocationStats().total(), lua.raw_state.gc.known_total);

    try lua.doString(
        \\for _, pair in ipairs(keep) do
        \\  local t, f = pair[1], pair[2]
        \\  local i = f()
        \\  assert(t["field" .. i] == i and t["k" .. i] == 0)
        \\end
    , .{});
}
