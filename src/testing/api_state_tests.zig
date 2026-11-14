const std = @import("std");
const api = @import("../api.zig");
const dumpBytecode = @import("api_expect.zig").dumpBytecode;
const describeError = @import("api_expect.zig").describeError;
const errorMessage = @import("api_expect.zig").errorMessage;
const callError = @import("api_expect.zig").callError;
const expectString = @import("api_expect.zig").expectString;
const handle = @import("../api/handle.zig");
const userdata_mod = @import("../api/userdata.zig");
const AnyUserdata = api.AnyUserdata;
const Context = api.Context;
const Function = api.Function;
const MemoryFile = api.MemoryFile;
const Ref = api.Ref;
const State = api.State;
const Table = api.Table;
const Userdata = api.Userdata;

test "api state initializes with safe defaults" {
    const lua = try State.init(std.testing.allocator, .{});
    defer lua.deinit();

    try lua.doString("assert(_VERSION == 'Lua 5.5')", .{});
    try std.testing.expectError(error.LuaError, lua.doFile("missing.lua", .{}));

    const message = try describeError(lua, error.LuaError);
    defer lua.allocator().free(message);
    try std.testing.expect(std.mem.indexOf(u8, message, "filesystem access disabled") != null);
}

test "api safe stdlib excludes ambient capability libraries" {
    const lua = try State.init(std.testing.allocator, .{});
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
    const lua = try State.init(std.testing.allocator, .{ .stdlib = .none });
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
    const lua = try State.init(std.testing.allocator, .{ .stdlib = .none });
    defer lua.deinit();

    try lua.setGlobal("host_value", 81);
    var chunk = try lua.loadString("return math.sqrt(host_value)", .{ .name = "=api-open-after-none" });
    defer chunk.deinit();

    try lua.openLibs(.{ .custom = .{ .math = true } });
    try std.testing.expectEqual(@as(f64, 9), try chunk.call(.{}, f64));
}

test "api custom stdlib opens only selected libraries" {
    const lua = try State.init(std.testing.allocator, .{
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
    const lua = try State.init(std.testing.allocator, .{});
    defer lua.deinit();

    var chunk = try lua.loadString("assert(1 + 1 == 2)", .{ .name = "=unit" });
    defer chunk.deinit();
    try chunk.call(.{}, void);

    var failing = try lua.loadString("error('boom')", .{ .name = "=unit" });
    defer failing.deinit();

    var err = try callError(failing, .{}, void);
    defer err.deinit();
    const message = try errorMessage(err);
    defer lua.allocator().free(message);
    try std.testing.expect(std.mem.indexOf(u8, message, "boom") != null);
}

test "api do file uses memory filesystem and reports source names" {
    const files = [_]MemoryFile{
        .{ .path = "ok.lua", .contents = "assert(2 * 3 == 6)" },
        .{ .path = "bad.lua", .contents = "return (" },
    };
    const lua = try State.init(std.testing.allocator, .{
        .capabilities = .{ .filesystem = .{ .memory = &files } },
    });
    defer lua.deinit();

    try lua.doFile("ok.lua", .{ .name = "@ok.lua" });
    try std.testing.expectError(error.LuaError, lua.doFile("bad.lua", .{ .name = "@bad.lua" }));

    const message = try describeError(lua, error.LuaError);
    defer lua.allocator().free(message);
    try std.testing.expect(std.mem.indexOf(u8, message, "bad.lua") != null);
}

test "api primitive values round trip through calls and conversion" {
    const lua = try State.init(std.testing.allocator, .{});
    defer lua.deinit();

    var identity = try lua.loadString("return ...", .{ .name = "=identity" });
    defer identity.deinit();

    try std.testing.expectEqual(true, try identity.call(.{true}, bool));
    try std.testing.expectEqual(@as(i64, -42), try identity.call(.{-42}, i64));
    try std.testing.expectEqual(@as(u8, 42), try identity.call(.{42}, u8));
    try std.testing.expectEqual(@as(f64, 1.5), try identity.call(.{1.5}, f64));
    try expectString("hello", identity.call(.{"hello"}, api.String));

    const pushed = try lua.toValue(@as(i64, 123));
    try std.testing.expectEqual(@as(i64, 123), try lua.read(pushed, i64));
}

test "api tuple helper reads multiple returns" {
    const lua = try State.init(std.testing.allocator, .{});
    defer lua.deinit();

    var chunk = try lua.loadString("return true, 42, 'ok'", .{ .name = "=tuple" });
    defer chunk.deinit();

    const Result = struct { bool, i64, api.String };
    var result = try chunk.call(.{}, Result);
    defer api.deinit(&result);

    try std.testing.expectEqual(true, result[0]);
    try std.testing.expectEqual(@as(i64, 42), result[1]);
    try std.testing.expectEqualStrings("ok", try result[2].bytes());
}

test "api public handles survive forced GC" {
    const Counter = struct {
        value: i64,
    };

    const lua = try State.init(std.testing.allocator, .{});
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

    var table = try lua.newTable(.{ .hash_hint = 1 });
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

    var value = try lua.toValue(.{ .answer = 45 });
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

    const Result = struct { Table, Function };
    var result = try tuple_chunk.call(.{}, Result);
    tuple_chunk.deinit();
    defer api.deinit(&result);

    try lua.collect();
    try std.testing.expectEqual(@as(i64, 46), try result[0].get("answer", i64));
    try std.testing.expectEqual(@as(i64, 47), try result[1].call(.{46}, i64));

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
    const lua = try State.init(std.testing.allocator, .{});
    defer lua.deinit();

    var failing = try lua.loadString("error({ message = 'boom' }, 0)", .{ .name = "=error-ref-gc" });
    var err = try callError(failing, .{}, void);
    failing.deinit();
    defer err.deinit();

    if (lua.takeError()) |last_error_ref| {
        var last = last_error_ref;
        last.deinit();
    }
    lua.raw_state.last_error = null;

    try lua.collect();
    var value = try err.value();
    defer value.deinit();
    switch (value) {
        .table => |table| try expectString("boom", table.get("message", api.String)),
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
            try expectString("payload", payload.get("name", api.String));
            try std.testing.expectEqual(@as(i64, 7), (try tracker.ptr()).id);

            const CheckResult = struct { api.String, bool };
            var checked = try check.call(.{}, CheckResult);
            defer api.deinit(&checked);
            try std.testing.expectEqualStrings("payload", try checked[0].bytes());
            try std.testing.expectEqual(true, checked[1]);

            try ctx.state().collect();
            var name = try payload.get("name", api.String);
            defer name.deinit();
            try ctx.returnValues(.{ name, (try tracker.ptr()).id });
        }
    };

    const lua = try State.init(std.testing.allocator, .{});
    defer lua.deinit();

    var tracker = try lua.newUserdata(Tracker, .{ .id = 7 }, .{});
    defer tracker.deinit();

    var stress = try lua.newFunction("stress_roots", Callbacks.stress);
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

    const Result = struct { api.String, i64 };
    var result = try chunk.call(.{tracker}, Result);
    defer api.deinit(&result);
    try std.testing.expectEqualStrings("payload", try result[0].bytes());
    try std.testing.expectEqual(@as(i64, 7), result[1]);
}

test "api native callback dispatch tolerates forced GC" {
    const Callbacks = struct {
        fn stress(ctx: *Context) !void {
            var callback = try ctx.arg(0, Function);
            defer callback.deinit();

            try ctx.state().collect();
            var returned_string = try callback.call(.{"native"}, api.String);
            defer returned_string.deinit();
            const returned = try returned_string.bytes();
            try ctx.returnValues(.{returned});
        }
    };

    const lua = try State.init(std.testing.allocator, .{});
    defer lua.deinit();

    var stress = try lua.newFunction("stress_callback_gc", Callbacks.stress);
    defer stress.deinit();
    try lua.setGlobal("stress_callback_gc", stress);

    var chunk = try lua.loadString(
        \\return stress_callback_gc(function(value)
        \\  collectgarbage('collect')
        \\  return value .. '-callback'
        \\end)
    , .{ .name = "=api-callback-dispatch-gc" });
    defer chunk.deinit();

    try expectString("native-callback", chunk.call(.{}, api.String));
}

test "api userdata handles root weak values until finalizers can run" {
    const Tracker = struct {
        finalized: *usize,

        fn finalize(self: *@This(), _: std.mem.Allocator) void {
            self.finalized.* += 1;
        }
    };

    const lua = try State.init(std.testing.allocator, .{});
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
    const lua = try State.init(std.testing.allocator, .{});
    defer lua.deinit();

    var failing = try lua.loadString(
        \\weak_errors = setmetatable({}, { __mode = 'v' })
        \\local err = { tag = 'kept' }
        \\weak_errors.err = err
        \\error(err, 0)
    , .{ .name = "=api-error-root-weak" });
    var err = try callError(failing, .{}, void);
    failing.deinit();

    if (lua.takeError()) |last_error_ref| {
        var last = last_error_ref;
        last.deinit();
    }
    lua.raw_state.last_error = null;

    try lua.collect();
    var value = try err.value();
    switch (value) {
        .table => |table| try expectString("kept", table.get("tag", api.String)),
        else => return error.TypeMismatch,
    }
    value.deinit();

    var check_alive = try lua.loadString("return weak_errors.err and weak_errors.err.tag or 'gone'", .{ .name = "=api-error-root-weak-alive" });
    defer check_alive.deinit();
    try expectString("kept", check_alive.call(.{}, api.String));

    err.deinit();
    try lua.collect();
    try lua.doString("assert(weak_errors.err == nil)", .{ .name = "=api-error-root-weak-collected" });
}

test "api released handles remove runtime roots" {
    const lua = try State.init(std.testing.allocator, .{});
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
    const lua = try State.init(std.testing.allocator, .{});
    defer lua.deinit();

    try lua.setGlobal("answer", 42);
    try std.testing.expectEqual(@as(i64, 42), try lua.getGlobal("answer", i64));

    var config = try lua.newTable(.{ .hash_hint = 4 });
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
    try expectString("sandbox", features.get(2, api.String));
}

test "api loaded module is returned by require" {
    const lua = try State.init(std.testing.allocator, .{});
    defer lua.deinit();

    var host = try lua.newTable(.{});
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
    const lua = try State.init(std.testing.allocator, .{});
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
    const lua = try State.init(std.testing.allocator, .{ .stdlib = .full });
    defer lua.deinit();

    var env = try lua.newTable(.{ .hash_hint = 1 });
    defer env.deinit();
    try env.set("secret", 42);

    var source_chunk = try lua.loadString("return secret", .{ .name = "=api-21.6-env", .environment = env });
    defer source_chunk.deinit();
    try std.testing.expectEqual(@as(i64, 42), try source_chunk.call(.{}, i64));

    var dumper = try lua.loadString("return string.dump(function() return secret end)", .{ .name = "=api-21.6-dump" });
    defer dumper.deinit();
    var dumped_string = try dumper.call(.{}, api.String);
    defer dumped_string.deinit();
    const dumped = try dumped_string.bytes();

    var binary_chunk = try lua.loadString(dumped, .{ .mode = .source_or_binary, .environment = env });
    defer binary_chunk.deinit();
    try std.testing.expectEqual(@as(i64, 42), try binary_chunk.call(.{}, i64));

    try std.testing.expectError(error.LuaError, lua.loadString(dumped, .{ .mode = .source_only }));
    try std.testing.expectError(error.LuaError, lua.loadString("return 1", .{ .mode = .binary_only }));
}

test "api dumps and loads zlua bytecode" {
    const source_state = try State.init(std.testing.allocator, .{});
    defer source_state.deinit();

    var source_chunk = try source_state.loadString("return secret, ...", .{ .name = "=api-bytecode" });
    defer source_chunk.deinit();

    const dumped = try dumpBytecode(source_chunk, .{ .strip_debug = true });
    defer source_state.allocator().free(dumped);

    const target_state = try State.init(std.testing.allocator, .{});
    defer target_state.deinit();

    var env = try target_state.newTable(.{ .hash_hint = 1 });
    defer env.deinit();
    try env.set("secret", "roundtrip");

    var loaded = try target_state.loadBytecode(dumped, .{ .environment = env });
    defer loaded.deinit();

    const Result = struct { api.String, i64 };
    var result = try loaded.call(.{42}, Result);
    defer api.deinit(&result);

    try std.testing.expectEqualStrings("roundtrip", try result[0].bytes());
    try std.testing.expectEqual(@as(i64, 42), result[1]);
    try std.testing.expectError(error.LuaError, target_state.loadBytecode("return 1", .{}));
}

fn ownedChunkCount(lua: *const State) usize {
    var count: usize = 0;
    for (lua.raw_state.chunk_allocations.items) |chunk| count += @intFromBool(chunk.root_owner != .snapshot);
    return count;
}

test "collections free chunk prototypes once their closures are unreachable" {
    const lua = try State.init(std.testing.allocator, .{});
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
    try std.testing.expect(ownedChunkCount(lua) < 20);
    try std.testing.expectEqual(lua.raw_state.gc.allocationStats().total(), lua.raw_state.gc.known_total);

    try lua.doString(
        \\for _, pair in ipairs(keep) do
        \\  local t, f = pair[1], pair[2]
        \\  local i = f()
        \\  assert(t["field" .. i] == i and t["k" .. i] == 0)
        \\end
    , .{});
}

test "fast field stores keep their keys after the chunk prototype is freed" {
    const lua = try State.init(std.testing.allocator, .{});
    defer lua.deinit();

    try lua.doString(
        \\keep = {}
        \\for i = 1, 200 do
        \\  local chunk = load("local function fill(t) for j = 1, 2 do t.name" .. i .. " = j end end " ..
        \\    "local a, b = {}, { p = 1, q = 2, r = 3 } b.s = 4 fill(a) fill(b) return b")
        \\  local t = chunk()
        \\  if i % 50 == 0 then keep[i] = t end
        \\end
        \\collectgarbage()
    , .{});
    try std.testing.expect(ownedChunkCount(lua) < 20);

    try lua.doString(
        \\for i, t in pairs(keep) do
        \\  local found = false
        \\  for k, v in pairs(t) do
        \\    if k == "name" .. i then found = v == 2 end
        \\  end
        \\  assert(found and t["name" .. i] == 2)
        \\end
    , .{});
}

test "rooted nil values leave other handles intact" {
    const lua = try State.init(std.testing.allocator, .{});
    defer lua.deinit();

    var missing = try lua.getGlobal("missing", api.Ref);
    var table = try lua.newTable(.{});
    defer table.deinit();
    try table.set("x", 1);
    missing.deinit();
    try std.testing.expectEqual(@as(i64, 1), try table.get("x", i64));

    try std.testing.expectError(error.LuaError, lua.doString("error(nil)", .{}));
    var kept = try lua.newTable(.{});
    defer kept.deinit();
    try kept.set("x", 2);
    try std.testing.expectError(error.LuaError, lua.doString("error('next')", .{}));
    try std.testing.expectEqual(@as(i64, 2), try kept.get("x", i64));

    {
        var scope = lua.handleScope();
        defer scope.end();
        _ = try lua.getGlobal("missing", api.Ref);
    }
    try std.testing.expectEqual(@as(i64, 2), try kept.get("x", i64));
}

test "later openLibs calls register libraries in package.loaded" {
    const package_first = try State.init(std.testing.allocator, .{ .stdlib = .{ .custom = .{ .base = true, .package = true } } });
    defer package_first.deinit();
    try package_first.openLibs(.{ .custom = .{ .json = true } });
    try package_first.doString("assert(require('json') == json and package.loaded._G == _G)", .{});

    const package_last = try State.init(std.testing.allocator, .{ .stdlib = .{ .custom = .{ .base = true, .json = true } } });
    defer package_last.deinit();
    try package_last.openLibs(.{ .custom = .{ .package = true } });
    try package_last.doString("assert(require('json') == json and require('_G') == _G)", .{});

    const no_base = try State.init(std.testing.allocator, .{ .stdlib = .{ .custom = .{ .package = true } } });
    defer no_base.deinit();
    var check = try no_base.loadString("return package.loaded._G == nil", .{});
    defer check.deinit();
    try std.testing.expect(try check.call(.{}, bool));
}

test "strings read from Lua stay valid until deinit" {
    const lua = try State.init(std.testing.allocator, .{});
    defer lua.deinit();
    try lua.doString("function make() return string.rep('a', 128) end t = { s = string.rep('c', 128) }", .{});
    var make = try lua.getGlobal("make", Function);
    defer make.deinit();
    var made = try make.call(.{}, api.String);
    defer made.deinit();
    var table = try lua.getGlobal("t", api.Table);
    defer table.deinit();
    var field = try table.get("s", api.String);
    defer field.deinit();
    try lua.doString("t.s = nil", .{});
    try lua.collect();
    try std.testing.expectEqualStrings(&@as([128]u8, @splat('a')), try made.bytes());
    try std.testing.expectEqualStrings(&@as([128]u8, @splat('c')), try field.bytes());

    var value = try make.call(.{}, api.Value);
    defer value.deinit();
    try lua.collect();
    try std.testing.expectEqualStrings(&@as([128]u8, @splat('a')), try value.string.bytes());
}

test "plain tuple results convert each value and release handles" {
    const lua = try State.init(std.testing.allocator, .{});
    defer lua.deinit();
    var chunk = try lua.loadString("return 7, 'seven', {}", .{});
    defer chunk.deinit();
    const roots = lua.raw_state.activeRootCount();
    var result = try chunk.call(.{}, struct { i64, api.String, ?api.Table });
    try std.testing.expectEqual(@as(i64, 7), result[0]);
    try std.testing.expectEqualStrings("seven", try result[1].bytes());
    try std.testing.expect(result[2] != null);
    api.deinit(&result);
    try std.testing.expectEqual(roots, lua.raw_state.activeRootCount());
    try std.testing.expectError(error.TypeMismatch, chunk.call(.{}, struct { i64, i64 }));
    try std.testing.expectEqual(roots, lua.raw_state.activeRootCount());
}

test "api released handle slots are reused without disturbing live handles" {
    const lua = try State.init(std.testing.allocator, .{});
    defer lua.deinit();

    var tables: [16]Table = undefined;
    for (&tables, 0..) |*table, id| {
        table.* = try lua.newTable(.{});
        try table.set("id", @as(i64, @intCast(id)));
    }
    const slots = lua.raw_state.api_roots.items.len;
    for (0..8) |pair| tables[pair * 2].deinit();
    for (0..8) |pair| {
        tables[pair * 2] = try lua.newTable(.{});
        try tables[pair * 2].set("id", @as(i64, @intCast(pair * 2 + 100)));
    }
    try std.testing.expectEqual(slots, lua.raw_state.api_roots.items.len);

    try lua.collect();
    for (&tables, 0..) |*table, id| {
        const expected: i64 = @intCast(if (id % 2 == 0) id + 100 else id);
        try std.testing.expectEqual(expected, try table.get("id", i64));
        table.deinit();
    }
    try std.testing.expectEqual(@as(usize, 0), lua.raw_state.activeRootCount());
}

test "api a call clears the error kept from an earlier one" {
    const lua = try State.init(std.testing.allocator, .{});
    defer lua.deinit();

    try std.testing.expectError(error.LuaError, lua.doString("error('first')", .{}));
    try lua.doString("x = 1", .{});
    try std.testing.expect(lua.takeError() == null);
}

test "api strings and errors format with the f specifier" {
    const lua = try State.init(std.testing.allocator, .{});
    defer lua.deinit();
    var buffer: [128]u8 = undefined;

    try lua.setGlobal("greeting", "hello");
    var greeting = try lua.getGlobal("greeting", api.String);
    defer greeting.deinit();
    try std.testing.expectEqualStrings("hello!", try std.fmt.bufPrint(&buffer, "{f}!", .{greeting}));

    try std.testing.expectError(error.LuaError, lua.doString("error('boom')", .{ .name = "=unit" }));
    var failure = lua.takeError().?;
    defer failure.deinit();
    const message = try errorMessage(failure);
    defer lua.allocator().free(message);
    try std.testing.expectEqualStrings(message, try std.fmt.bufPrint(&buffer, "{f}", .{failure}));
}

test "api calls into Lua allocate nothing once a host thread is kept" {
    const CountingAllocator = @import("bench/allocation.zig").CountingAllocator;
    var counter = CountingAllocator{ .backing = std.testing.allocator };
    const lua = try State.init(counter.allocator(), .{});
    defer lua.deinit();
    try lua.doString("function add(a, b) return a + b end function three() return 1, 2, 3 end", .{});
    var add = try lua.getGlobal("add", Function);
    defer add.deinit();
    var three = try lua.getGlobal("three", Function);
    defer three.deinit();
    _ = try add.call(.{ 1, 2 }, i64);

    const allocations = counter.allocations;
    for (0..100) |i| {
        try std.testing.expectEqual(@as(i64, @intCast(i + 1)), try add.call(.{ @as(i64, @intCast(i)), 1 }, i64));
        const one, const two, const last = try three.call(.{}, struct { i64, i64, i64 });
        try std.testing.expectEqual(@as(i64, 6), one + two + last);
    }
    try std.testing.expectEqual(allocations, counter.allocations);
}

test "api a failed call keeps no host thread" {
    const lua = try State.init(std.testing.allocator, .{});
    defer lua.deinit();
    try lua.doString("function fail() error('failed') end", .{});
    try std.testing.expect(lua.raw_state.idle_host_thread != null);
    try std.testing.expectError(error.LuaError, lua.callGlobal("fail", .{}, void));
    try std.testing.expect(lua.raw_state.idle_host_thread == null);
}

fn callBack(ctx: *Context, function: Function, value: i64) !i64 {
    _ = ctx;
    return try function.call(.{value}, i64) + 1;
}

test "api a host call starts clean after calls that failed, nested, or exposed their thread" {
    const lua = try State.init(std.testing.allocator, .{});
    defer lua.deinit();
    try lua.setGlobal("call_back", callBack);
    try lua.doString(
        \\closed = 0
        \\function fail(...)
        \\  local guard <close> = setmetatable({}, { __close = function() closed = closed + 1 end })
        \\  local captured = select("#", ...)
        \\  hold = function() return captured end
        \\  error("failed")
        \\end
        \\function many() return 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12 end
        \\function double(n) return n * 2 end
        \\function nested(n) return call_back(double, n) end
        \\function running() return coroutine.running() end
        \\function locals() local a, b, c, d; return a, b, c, d end
    , .{});
    var fail = try lua.getGlobal("fail", Function);
    defer fail.deinit();
    var many = try lua.getGlobal("many", Function);
    defer many.deinit();
    var nested = try lua.getGlobal("nested", Function);
    defer nested.deinit();
    var running = try lua.getGlobal("running", Function);
    defer running.deinit();
    var locals = try lua.getGlobal("locals", Function);
    defer locals.deinit();

    for (0..3) |round| {
        try std.testing.expectError(error.LuaError, fail.call(.{ 1, 2, 3, 4, 5, 6, 7, 8, 9 }, void));
        try std.testing.expectEqual(@as(i64, @intCast(round + 1)), try lua.getGlobal("closed", i64));
        try std.testing.expectEqual(@as(i64, 9), try lua.callGlobal("hold", .{}, i64));

        const empty = try locals.call(.{}, struct { ?i64, ?i64, ?i64, ?i64 });
        inline for (empty) |value| try std.testing.expectEqual(@as(?i64, null), value);

        const values = try many.call(.{}, struct { i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64 });
        var sum: i64 = 0;
        inline for (values) |value| sum += value;
        try std.testing.expectEqual(@as(i64, 78), sum);

        try std.testing.expectEqual(@as(i64, 43), try nested.call(.{21}, i64));

        var first = try running.call(.{}, api.Coroutine);
        defer first.deinit();
        var second = try running.call(.{}, api.Coroutine);
        defer second.deinit();
        try lua.setGlobals(.{ .first = first, .second = second });
        try lua.doString("assert(first ~= second and coroutine.status(first) == 'dead' and coroutine.status(second) == 'dead')", .{});
    }
}
