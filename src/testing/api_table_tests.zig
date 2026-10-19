const std = @import("std");
const api = @import("../api.zig");
const a = std.testing.allocator;

fn expectLuaError(lua: *api.State, result: anytype, needle: []const u8) !void {
    if (result) |_| return error.TestExpectedLuaError else |err| try std.testing.expectEqual(error.LuaError, err);
    const message = try lua.errorMessage();
    defer lua.allocator().free(message);
    if (std.mem.indexOf(u8, message, needle) == null) {
        std.debug.print("unexpected error message: {s}\n", .{message});
        return error.TestUnexpectedErrorMessage;
    }
}

test "table get and set honor function and table metamethods; raw access bypasses them" {
    var lua = try api.State.init(a, .{});
    defer lua.deinit();
    try lua.doString(
        \\writes = {}
        \\proxy = {}
        \\t = setmetatable({ present = 'raw' }, {
        \\  __index = function(_, k) return 'computed ' .. tostring(k) end,
        \\  __newindex = function(t, k, v) writes[#writes + 1] = k; rawset(t, k, v * 2) end,
        \\})
        \\chained = setmetatable({}, { __index = setmetatable({}, { __index = { deep = 7 } }), __newindex = proxy })
    , .{});
    var t = try lua.getGlobal("t", api.Table);
    defer t.deinit();

    try std.testing.expectEqualStrings("computed missing", try t.get("missing", []const u8));
    try std.testing.expectEqualStrings("raw", try t.get("present", []const u8));
    try std.testing.expectEqual(@as(?[]const u8, null), try t.rawGet("missing", ?[]const u8));

    try t.set("doubled", 21);
    try std.testing.expectEqual(@as(i64, 42), try t.rawGet("doubled", i64));
    try t.set("doubled", 5);
    try std.testing.expectEqual(@as(i64, 5), try t.rawGet("doubled", i64));
    try t.rawSet("bypass", 3);
    try std.testing.expectEqual(@as(i64, 3), try t.rawGet("bypass", i64));
    try lua.doString("assert(#writes == 1 and writes[1] == 'doubled')", .{});

    var chained = try lua.getGlobal("chained", api.Table);
    defer chained.deinit();
    try std.testing.expectEqual(@as(i64, 7), try chained.get("deep", i64));
    try chained.set("forwarded", true);
    try std.testing.expectEqual(@as(?bool, null), try chained.rawGet("forwarded", ?bool));
    try lua.doString("assert(proxy.forwarded == true)", .{});

    try t.rawSet(2.0, "two");
    try std.testing.expectEqualStrings("two", try t.rawGet(2, []const u8));
    try std.testing.expectEqualStrings("two", try t.get(@as(f64, 2.0), []const u8));
    try expectLuaError(&lua, t.rawSet(null, 1), "table index is nil");
    try expectLuaError(&lua, t.rawSet(std.math.nan(f64), 1), "table index is NaN");
    var plain = try lua.createTable(.{});
    defer plain.deinit();
    try expectLuaError(&lua, plain.set(null, 1), "table index is nil");

    try lua.doString("bad = setmetatable({}, { __index = function() error('index boom') end, __newindex = function() error('newindex boom') end })", .{});
    var bad = try lua.getGlobal("bad", api.Table);
    defer bad.deinit();
    try expectLuaError(&lua, bad.get("x", ?i64), "index boom");
    try expectLuaError(&lua, bad.set("x", 1), "newindex boom");
    try lua.doString("loop = {}; setmetatable(loop, { __index = loop, __newindex = loop })", .{});
    var loop = try lua.getGlobal("loop", api.Table);
    defer loop.deinit();
    try expectLuaError(&lua, loop.get("x", ?i64), "'__index' chain too long");
    try expectLuaError(&lua, loop.set("x", 1), "'__newindex' chain too long");
}

test "table len honors __len and rawLen ignores it" {
    var lua = try api.State.init(a, .{});
    defer lua.deinit();
    try lua.doString(
        \\seq = setmetatable({ 1, 2, 3 }, { __len = function(t) return rawlen(t) * 10 end })
        \\float_len = setmetatable({}, { __len = function() return 4.0 end })
        \\string_len = setmetatable({}, { __len = function() return '3' end })
        \\string_float_len = setmetatable({}, { __len = function() return ' 4.0 ' end })
        \\bad_len = setmetatable({}, { __len = function() return 'long' end })
        \\fractional = setmetatable({}, { __len = function() return 1.5 end })
        \\fractional_string = setmetatable({}, { __len = function() return '2.5' end })
        \\raising = setmetatable({}, { __len = function() error('len boom') end })
    , .{});
    var seq = try lua.getGlobal("seq", api.Table);
    defer seq.deinit();
    try std.testing.expectEqual(@as(i64, 30), try seq.len());
    try std.testing.expectEqual(@as(i64, 3), try seq.rawLen());

    var float_len = try lua.getGlobal("float_len", api.Table);
    defer float_len.deinit();
    try std.testing.expectEqual(@as(i64, 4), try float_len.len());

    var string_len = try lua.getGlobal("string_len", api.Table);
    defer string_len.deinit();
    try std.testing.expectEqual(@as(i64, 3), try string_len.len());

    var string_float_len = try lua.getGlobal("string_float_len", api.Table);
    defer string_float_len.deinit();
    try std.testing.expectEqual(@as(i64, 4), try string_float_len.len());

    inline for (.{ "bad_len", "fractional", "fractional_string" }) |name| {
        var table = try lua.getGlobal(name, api.Table);
        defer table.deinit();
        try expectLuaError(&lua, table.len(), "object length is not an integer");
    }
    var raising = try lua.getGlobal("raising", api.Table);
    defer raising.deinit();
    try expectLuaError(&lua, raising.len(), "len boom");
    try std.testing.expectEqual(@as(i64, 0), try raising.rawLen());

    var empty = try lua.createTable(.{});
    defer empty.deinit();
    try std.testing.expectEqual(@as(i64, 0), try empty.len());
}

test "table setMetatable matches lua_setmetatable and getMetatable round trips" {
    var lua = try api.State.init(a, .{});
    defer lua.deinit();
    var t = try lua.createTable(.{});
    defer t.deinit();
    try std.testing.expect((try t.getMetatable()) == null);

    var meta = try lua.createTable(.{});
    defer meta.deinit();
    var fallback = try lua.createTable(.{});
    defer fallback.deinit();
    try fallback.set("answer", 42);
    try meta.set("__index", fallback);
    try meta.set("__metatable", "locked");
    try t.setMetatable(meta);
    try std.testing.expectEqual(@as(i64, 42), try t.get("answer", i64));

    var actual = (try t.getMetatable()).?;
    try std.testing.expectEqual(try meta.identity(), try actual.identity());
    actual.deinit();

    try lua.setGlobal("t", t);
    try lua.doString(
        \\assert(getmetatable(t) == 'locked')
        \\assert(not pcall(setmetatable, t, {}))
    , .{});

    var replacement = try lua.createTable(.{});
    defer replacement.deinit();
    try t.setMetatable(replacement);
    try lua.doString("assert(getmetatable(t) ~= 'locked' and t.answer == nil)", .{});
    try t.setMetatable(null);
    try std.testing.expect((try t.getMetatable()) == null);
    try lua.doString("assert(getmetatable(t) == nil)", .{});

    var foreign = try api.State.init(a, .{});
    defer foreign.deinit();
    var foreign_meta = try foreign.createTable(.{});
    defer foreign_meta.deinit();
    try std.testing.expectError(error.InvalidHandle, t.setMetatable(foreign_meta));
}

test "table setMetatable installs __gc finalizers and __mode weak tables" {
    var lua = try api.State.init(a, .{});
    defer lua.deinit();
    try lua.doString("finalized = 0", .{});
    var meta = try lua.createTable(.{});
    defer meta.deinit();
    var gc = try lua.loadString("finalized = finalized + 1", .{});
    defer gc.deinit();
    try meta.set("__gc", gc);
    {
        var doomed = try lua.createTable(.{});
        defer doomed.deinit();
        try doomed.setMetatable(meta);
    }
    try lua.collect();
    try lua.collect();
    try std.testing.expectEqual(@as(i64, 1), try lua.getGlobal("finalized", i64));

    var weak = try lua.createTable(.{});
    defer weak.deinit();
    var weak_meta = try lua.createTable(.{});
    defer weak_meta.deinit();
    try weak_meta.set("__mode", "v");
    try weak.setMetatable(weak_meta);
    {
        var value = try lua.createTable(.{});
        defer value.deinit();
        try weak.set("entry", value);
    }
    try lua.collect();
    try std.testing.expect((try weak.rawGet("entry", ?api.Table)) == null);
}

test "table append writes raw sequence slots" {
    var lua = try api.State.init(a, .{});
    defer lua.deinit();
    try lua.doString("t = setmetatable({}, { __newindex = function() error('no') end, __len = function() return 100 end })", .{});
    var t = try lua.getGlobal("t", api.Table);
    defer t.deinit();
    try t.append("one");
    try t.append(2);
    try t.append(null);
    try t.append(.{ .nested = true });
    try std.testing.expectEqual(@as(i64, 3), try t.rawLen());
    try std.testing.expectEqualStrings("one", try t.rawGet(1, []const u8));
    try std.testing.expectEqual(@as(i64, 2), try t.rawGet(2, i64));
    var nested = try t.rawGet(3, api.Table);
    defer nested.deinit();
    try std.testing.expect(try nested.get("nested", bool));
}

test "table raw iterator roots keys values and the table across forced collections" {
    var lua = try api.State.init(a, .{});
    defer lua.deinit();
    try lua.doString(
        \\local t = {}
        \\for i = 1, 40 do t[i] = 'array ' .. i end
        \\for i = 1, 40 do t['key ' .. i] = { id = i } end
        \\for i = 1, 10 do t[i + 0.5] = string.rep('x', i) end
        \\t[true] = 'boolean'
        \\setmetatable(t, { __pairs = function() error('raw iteration must not call __pairs') end })
        \\holder = t
    , .{});
    var table = try lua.getGlobal("holder", api.Table);
    var iterator = try table.rawIterator();
    defer iterator.deinit();
    table.deinit();
    try lua.setGlobal("holder", null);

    var buffer: [64]u8 = undefined;
    var array_seen: usize = 0;
    var hash_seen: usize = 0;
    var float_seen: usize = 0;
    var boolean_seen: usize = 0;
    var seen_keys = std.StringHashMap(void).init(a);
    defer seen_keys.deinit();
    while (try iterator.next()) |entry| {
        try lua.collect();
        switch (entry.key) {
            .integer => |index| {
                try std.testing.expectEqualStrings(try std.fmt.bufPrint(&buffer, "array {d}", .{index}), entry.value.string);
                array_seen += 1;
            },
            .string => |key| {
                const id = try entry.value.table.get("id", i64);
                try std.testing.expectEqualStrings(try std.fmt.bufPrint(&buffer, "key {d}", .{id}), key);
                try seen_keys.put(try std.fmt.allocPrint(lua.allocator(), "{s}", .{key}), {});
                hash_seen += 1;
            },
            .number => |number| {
                try std.testing.expectEqual(@as(usize, @intFromFloat(number - 0.5)), entry.value.string.len);
                float_seen += 1;
            },
            .boolean => {
                try std.testing.expectEqualStrings("boolean", entry.value.string);
                boolean_seen += 1;
            },
            else => return error.TestUnexpectedResult,
        }
    }
    var keys = seen_keys.keyIterator();
    while (keys.next()) |key| lua.allocator().free(key.*);
    try std.testing.expectEqual(@as(usize, 40), array_seen);
    try std.testing.expectEqual(@as(usize, 40), hash_seen);
    try std.testing.expectEqual(@as(usize, 40), seen_keys.count());
    try std.testing.expectEqual(@as(usize, 10), float_seen);
    try std.testing.expectEqual(@as(usize, 1), boolean_seen);
    try std.testing.expect((try iterator.next()) == null);
    try std.testing.expectEqual(@as(usize, 0), lua.raw_state.activeRootCount() - 1);
}

test "table raw iterator allows clearing and updating fields during traversal" {
    var lua = try api.State.init(a, .{});
    defer lua.deinit();
    try lua.doString(
        \\t = {}
        \\for i = 1, 20 do t[i] = i end
        \\for i = 1, 30 do t[string.format('k%03d', i)] = { i } end
    , .{});
    var table = try lua.getGlobal("t", api.Table);
    defer table.deinit();
    try lua.setGlobal("t", null);
    const roots_before = lua.raw_state.activeRootCount();

    var iterator = try table.rawIterator();
    var visited: usize = 0;
    var cleared: usize = 0;
    while (try iterator.next()) |entry| {
        visited += 1;
        switch (entry.key) {
            .integer => |index| try table.rawSet(index, index * 100),
            .string => |key| {
                try table.set(entry.key, null);
                cleared += 1;
                try lua.collect();
                try std.testing.expectEqual(@as(u8, 'k'), key[0]);
                try std.testing.expectEqual(@as(i64, try std.fmt.parseInt(i64, key[1..], 10)), try entry.value.table.rawGet(1, i64));
            },
            else => return error.TestUnexpectedResult,
        }
    }
    iterator.deinit();
    try std.testing.expectEqual(roots_before, lua.raw_state.activeRootCount());
    try std.testing.expectEqual(@as(usize, 50), visited);
    try std.testing.expectEqual(@as(usize, 30), cleared);
    try std.testing.expectEqual(@as(i64, 20), try table.rawLen());
    try std.testing.expectEqual(@as(i64, 700), try table.rawGet(7, i64));
    var check = try table.rawIterator();
    defer check.deinit();
    var remaining: usize = 0;
    while (try check.next()) |entry| {
        try std.testing.expect(entry.key == .integer);
        remaining += 1;
    }
    try std.testing.expectEqual(@as(usize, 20), remaining);
}

test "table pairs honors __pairs, closing values, and errors" {
    var lua = try api.State.init(a, .{});
    defer lua.deinit();
    try lua.doString(
        \\closed = {}
        \\local function closer(tag) return setmetatable({}, { __close = function(_, err) closed[#closed + 1] = tag .. ':' .. tostring(err) end }) end
        \\squares = setmetatable({ hidden = true }, { __pairs = function(t)
        \\  local function step(limit, i)
        \\    i = i + 1
        \\    collectgarbage()
        \\    if i <= limit then return i, string.rep('#', i * i) end
        \\  end
        \\  return step, 5, 0, closer('squares')
        \\end })
        \\failing = setmetatable({}, { __pairs = function()
        \\  return function(_, i) i = (i or 0) + 1; if i == 3 then error('iter boom') end; return i, i end, nil, nil, closer('failing')
        \\end })
        \\early = setmetatable({}, { __pairs = function() return next, { 1, 2, 3 }, nil, closer('early') end })
        \\non_closable = setmetatable({}, { __pairs = function() return next, {}, nil, {} end })
        \\pairs_error = setmetatable({}, { __pairs = function() error('pairs boom') end })
        \\plain = { 10, 20, x = 30 }
    , .{});

    var squares = try lua.getGlobal("squares", api.Table);
    defer squares.deinit();
    var iterator = try squares.pairs();
    var count: i64 = 0;
    while (try iterator.next()) |entry| {
        count += 1;
        try lua.collect();
        try std.testing.expectEqual(count, entry.key.integer);
        try std.testing.expectEqual(@as(usize, @intCast(count * count)), entry.value.string.len);
        for (entry.value.string) |byte| try std.testing.expectEqual(@as(u8, '#'), byte);
    }
    iterator.deinit();
    try std.testing.expectEqual(@as(i64, 5), count);
    try lua.doString("assert(#closed == 1 and closed[1] == 'squares:nil', closed[1])", .{});

    var raw = try squares.rawIterator();
    defer raw.deinit();
    const raw_entry = (try raw.next()).?;
    try std.testing.expectEqualStrings("hidden", raw_entry.key.string);
    try std.testing.expect((try raw.next()) == null);

    var failing = try lua.getGlobal("failing", api.Table);
    defer failing.deinit();
    var failing_iterator = try failing.pairs();
    defer failing_iterator.deinit();
    _ = (try failing_iterator.next()).?;
    _ = (try failing_iterator.next()).?;
    try expectLuaError(&lua, failing_iterator.next(), "iter boom");
    try std.testing.expect((try failing_iterator.next()) == null);
    try lua.doString("assert(#closed == 2 and closed[2]:find('^failing:.*iter boom'), closed[2])", .{});

    var early = try lua.getGlobal("early", api.Table);
    defer early.deinit();
    var early_iterator = try early.pairs();
    defer early_iterator.deinit();
    try std.testing.expectEqual(@as(i64, 1), (try early_iterator.next()).?.key.integer);
    try early_iterator.close();
    try early_iterator.close();
    try std.testing.expect((try early_iterator.next()) == null);
    try lua.doString("assert(#closed == 3 and closed[3] == 'early:nil')", .{});

    var abandoned = try early.pairs();
    _ = (try abandoned.next()).?;
    abandoned.deinit();
    try lua.doString("assert(#closed == 3)", .{});

    var non_closable = try lua.getGlobal("non_closable", api.Table);
    defer non_closable.deinit();
    try expectLuaError(&lua, non_closable.pairs(), "non-closable value");
    var pairs_error = try lua.getGlobal("pairs_error", api.Table);
    defer pairs_error.deinit();
    try expectLuaError(&lua, pairs_error.pairs(), "pairs boom");

    var plain = try lua.getGlobal("plain", api.Table);
    defer plain.deinit();
    var plain_iterator = try plain.pairs();
    defer plain_iterator.deinit();
    var sum: i64 = 0;
    while (try plain_iterator.next()) |entry| sum += entry.value.integer;
    try std.testing.expectEqual(@as(i64, 60), sum);
}

test "table iterators and rawNext reject invalid keys and reset" {
    var lua = try api.State.init(a, .{});
    defer lua.deinit();
    try lua.doString("t = { a = 1 }", .{});
    var table = try lua.getGlobal("t", api.Table);
    defer table.deinit();
    try expectLuaError(&lua, table.rawNext("absent"), "invalid key to 'next'");

    var snapshot = try lua.snapshot(a);
    defer snapshot.deinit();
    var stale_table = try lua.getGlobal("t", api.Table);
    defer stale_table.deinit();
    var stale = try stale_table.rawIterator();
    defer stale.deinit();
    _ = (try stale.next()).?;
    try lua.reset();
    try std.testing.expectError(error.InvalidHandle, stale.next());
    try std.testing.expectError(error.InvalidHandle, stale.close());
}

test "table writes follow snapshot rollback" {
    var lua = try api.State.init(a, .{});
    defer lua.deinit();
    try lua.doString("t = { 1, 2, name = 'base' }; mt = { __index = { extra = 'meta' } }", .{});
    var snapshot = try lua.snapshot(a);
    defer snapshot.deinit();
    for (0..2) |_| {
        var t = try lua.getGlobal("t", api.Table);
        defer t.deinit();
        var mt = try lua.getGlobal("mt", api.Table);
        defer mt.deinit();
        try t.rawSet("name", "changed");
        try t.rawSet("fresh", true);
        try t.append(3);
        try t.setMetatable(mt);
        try std.testing.expectEqualStrings("meta", try t.get("extra", []const u8));
        try lua.doString("assert(t.name == 'changed' and t.fresh and #t == 3 and t.extra == 'meta')", .{});
        try lua.reset();
        try lua.doString("assert(t.name == 'base' and t.fresh == nil and #t == 2 and getmetatable(t) == nil)", .{});
    }
}

test "table toSlice converts raw sequences with ownership and type errors" {
    var lua = try api.State.init(a, .{});
    defer lua.deinit();
    try lua.doString(
        \\ints = { 1, 2.0, 3 }
        \\strings = setmetatable({ 'a', 'bb' }, { __index = function() return 'meta' end, __len = function() return 99 end })
        \\tables = { { n = 1 }, { n = 2 } }
        \\holes = { 1, nil, 3 }
        \\mixed = { 1, 'two', 3 }
        \\huge = { 1, 300 }
        \\partial = { {}, {}, 'x' }
        \\empty = {}
    , .{});
    const roots_before = lua.raw_state.activeRootCount();

    var ints = try lua.getGlobal("ints", api.Table);
    defer ints.deinit();
    const int_slice = try ints.toSlice(i64, a);
    defer a.free(int_slice);
    try std.testing.expectEqualSlices(i64, &.{ 1, 2, 3 }, int_slice);
    const float_slice = try ints.toSlice(f32, a);
    defer a.free(float_slice);
    try std.testing.expectEqual(@as(f32, 2), float_slice[1]);

    var strings = try lua.getGlobal("strings", api.Table);
    defer strings.deinit();
    const string_slice = try strings.toSlice([]const u8, a);
    defer a.free(string_slice);
    try std.testing.expectEqual(@as(usize, 2), string_slice.len);
    try std.testing.expectEqualStrings("bb", string_slice[1]);

    var tables = try lua.getGlobal("tables", api.Table);
    defer tables.deinit();
    const table_slice = try tables.toSlice(api.Table, a);
    try lua.collect();
    try std.testing.expectEqual(@as(i64, 2), try table_slice[1].get("n", i64));
    for (table_slice) |*item| item.deinit();
    a.free(table_slice);

    var holes = try lua.getGlobal("holes", api.Table);
    defer holes.deinit();
    const optional_slice = try holes.toSlice(?i64, a);
    defer a.free(optional_slice);
    try std.testing.expectEqual(@as(?i64, null), optional_slice[1]);
    try std.testing.expectEqual(@as(?i64, 3), optional_slice[2]);
    try std.testing.expectError(error.TypeMismatch, holes.toSlice(i64, a));

    var mixed = try lua.getGlobal("mixed", api.Table);
    defer mixed.deinit();
    try std.testing.expectError(error.TypeMismatch, mixed.toSlice(i64, a));
    var partial = try lua.getGlobal("partial", api.Table);
    defer partial.deinit();
    const roots_with_partial = lua.raw_state.activeRootCount();
    try std.testing.expectError(error.TypeMismatch, partial.toSlice(api.Table, a));
    try std.testing.expectEqual(roots_with_partial, lua.raw_state.activeRootCount());
    const values = try mixed.toSlice(api.Value, a);
    try std.testing.expectEqualStrings("two", values[1].string);
    for (values) |*value| value.deinit();
    a.free(values);

    var huge = try lua.getGlobal("huge", api.Table);
    defer huge.deinit();
    try std.testing.expectError(error.IntegerOutOfRange, huge.toSlice(u8, a));

    var empty = try lua.getGlobal("empty", api.Table);
    defer empty.deinit();
    const empty_slice = try empty.toSlice(i64, a);
    defer a.free(empty_slice);
    try std.testing.expectEqual(@as(usize, 0), empty_slice.len);

    try std.testing.expectEqual(roots_before + 8, lua.raw_state.activeRootCount());
}

test "preloadModuleFn loads lazily once with Lua 5.5 loader arguments" {
    const Loader = struct {
        var calls: usize = 0;
        var seen_name: [16]u8 = undefined;
        var seen_name_len: usize = 0;
        var seen_data: [16]u8 = undefined;
        var seen_data_len: usize = 0;

        fn open(ctx: *api.Context, name: []const u8, data: []const u8) !api.Table {
            calls += 1;
            @memcpy(seen_name[0..name.len], name);
            seen_name_len = name.len;
            @memcpy(seen_data[0..data.len], data);
            seen_data_len = data.len;
            var module = try ctx.state().createTable(.{});
            errdefer module.deinit();
            try module.set("version", 7);
            return module;
        }
    };
    var lua = try api.State.init(a, .{});
    defer lua.deinit();
    try lua.preloadModuleFn("hostmod", Loader.open);
    try std.testing.expectEqual(@as(usize, 0), Loader.calls);
    try lua.collect();
    try std.testing.expectEqual(@as(usize, 0), Loader.calls);

    try lua.doString(
        \\local m, data = require('hostmod')
        \\assert(m.version == 7 and data == ':preload:')
        \\assert(require('hostmod') == m and package.loaded.hostmod == m)
    , .{});
    try std.testing.expectEqual(@as(usize, 1), Loader.calls);
    try std.testing.expectEqualStrings("hostmod", Loader.seen_name[0..Loader.seen_name_len]);
    try std.testing.expectEqualStrings(":preload:", Loader.seen_data[0..Loader.seen_data_len]);

    var module = try lua.require("hostmod", api.Table);
    defer module.deinit();
    try std.testing.expectEqual(@as(i64, 7), try module.get("version", i64));
    try std.testing.expectEqual(@as(usize, 1), Loader.calls);
}

test "package helpers keep the original tables after Lua replaces them" {
    var lua = try api.State.init(a, .{ .stdlib = .base });
    defer lua.deinit();
    try lua.setPackagePath("./?.lua");
    try lua.doString(
        \\original, loaded, preload = package, package.loaded, package.preload
        \\package.loaded = {}
        \\package.preload = {}
        \\package = nil
    , .{});
    var loader = try lua.loadString("return { name = ... }", .{ .name = "=loader" });
    defer loader.deinit();
    try lua.preloadModule("hosted", loader);
    try lua.setLoadedModule("answer", 42);
    try lua.setPackagePath("?.lua");
    try std.testing.expectEqual(@as(?i64, null), try lua.getGlobal("package", ?i64));

    var hosted = try lua.require("hosted", api.Table);
    defer hosted.deinit();
    try std.testing.expectEqualStrings("hosted", try hosted.get("name", []const u8));
    try std.testing.expectEqual(@as(i64, 42), try lua.require("answer", i64));
    try lua.doString(
        \\assert(loaded.hosted.name == 'hosted' and loaded.answer == 42 and next(original.loaded) == nil)
        \\assert(preload.hosted and next(original.preload) == nil and original.path == '?.lua')
        \\assert(require('hosted') == loaded.hosted)
    , .{});
}

test "preloadModule installs Lua loaders and host require reports errors" {
    var lua = try api.State.init(a, .{ .stdlib = .base });
    defer lua.deinit();
    var loader = try lua.loadString(
        \\local name, data = ...
        \\loads = (loads or 0) + 1
        \\if name == 'broken' then error('loader boom') end
        \\return { name = name, data = data }
    , .{ .name = "=loader" });
    defer loader.deinit();
    try lua.preloadModule("lazy", loader);
    try lua.preloadModule("broken", loader);
    try lua.preloadModule("broken", loader);
    try std.testing.expectEqual(@as(?i64, null), try lua.getGlobal("loads", ?i64));

    const Result = api.Tuple(&.{ api.Table, []const u8 });
    var result = try lua.require("lazy", Result);
    defer result.deinit();
    try std.testing.expectEqualStrings("lazy", try result.get(0).get("name", []const u8));
    try std.testing.expectEqualStrings(":preload:", try result.get(0).get("data", []const u8));
    try std.testing.expectEqualStrings(":preload:", result.get(1));
    try std.testing.expectEqual(@as(i64, 1), try lua.getGlobal("loads", i64));

    try expectLuaError(&lua, lua.require("broken", api.Table), "loader boom");
    try expectLuaError(&lua, lua.require("broken", api.Table), "loader boom");
    try std.testing.expectEqual(@as(i64, 3), try lua.getGlobal("loads", i64));
    try expectLuaError(&lua, lua.require("missing", api.Table), "module 'missing' not found");

    try lua.doString("require = function() error('replaced') end", .{});
    var again = try lua.require("lazy", api.Table);
    defer again.deinit();
    try std.testing.expectEqual(try result.get(0).identity(), try again.identity());

    var eager = try lua.createModule("eager");
    defer eager.deinit();
    try eager.set("ready", true);
    try lua.setLoadedModule("eager", eager);
    try lua.setLoadedModule("answer", 42);
    var loaded = try lua.require("eager", api.Table);
    defer loaded.deinit();
    try std.testing.expect(try loaded.get("ready", bool));
    try std.testing.expectEqual(@as(i64, 42), try lua.require("answer", i64));
}
