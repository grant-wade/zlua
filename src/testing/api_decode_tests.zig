const std = @import("std");
const api = @import("../root.zig");
const a = std.testing.allocator;
const State = api.State;
const Value = api.Value;

const Kind = enum { sword, spear, bow };
const Id = enum(u8) { _ };

const Stats = struct {
    speed: f32 = 1.5,
    range: [2]i32 = .{ 0, 0 },
};

const Weapon = struct {
    name: []const u8 = "",
    kind: Kind = .sword,
    might: i32 = 0,
    heavy: bool = false,
    bonus: ?i32 = null,
    tags: []const []const u8 = &.{},
    stats: Stats = .{},
    base: Base = .{},
    costs: std.EnumArray(Kind, i32) = .initFill(0),
    usable: std.EnumSet(Kind) = .empty,
    alias: i32 = 0,
    flags: std.bit_set.IntegerBitSet(8) = .empty,

    const Base = struct { weight: i32 = 0, value: i32 = 7 };

    pub const lua = .{
        .name = .{ .required = true, .doc = "Shown in menus." },
        .base = .{ .embed = true },
        .alias = .{ .key = "other_name" },
        .flags = .{ .elements = Kind },
    };
};

const Decoded = struct {
    arena: std.heap.ArenaAllocator,
    diagnostic: api.Diagnostic,
    lua: State,

    fn init() !Decoded {
        return .{ .arena = .init(a), .diagnostic = .{ .gpa = a }, .lua = try State.init(a, .{}) };
    }

    fn deinit(self: *Decoded) void {
        self.lua.deinit();
        self.diagnostic.deinit();
        self.arena.deinit();
    }

    fn value(self: *Decoded, source: []const u8) !Value {
        var chunk = try self.lua.loadString(source, .{});
        defer chunk.deinit();
        return chunk.call(.{}, Value);
    }

    fn decode(self: *Decoded, comptime T: type, source: []const u8) !T {
        var v = try self.value(source);
        defer v.deinit();
        return api.decode(T, v, .{ .allocator = self.arena.allocator(), .diagnostic = &self.diagnostic });
    }

    fn expectFailure(self: *Decoded, comptime T: type, source: []const u8, expected: []const u8) !void {
        self.diagnostic.deinit();
        try std.testing.expectError(error.Invalid, self.decode(T, source));
        try std.testing.expectEqualStrings(expected, self.diagnostic.text);
    }
};

test "decode fills structs from tables and keeps defaults for absent keys" {
    var d = try Decoded.init();
    defer d.deinit();
    const weapon = try d.decode(Weapon,
        \\return {
        \\  name = "pike", kind = "spear", might = 7, heavy = true, bonus = 2,
        \\  tags = { "long", "cheap" },
        \\  stats = { range = { 1, 2 } },
        \\  weight = 9,
        \\  costs = { bow = 3 },
        \\  usable = { "sword", "bow" },
        \\  other_name = 4,
        \\  flags = { "spear", "bow" },
        \\}
    );
    try std.testing.expectEqualStrings("pike", weapon.name);
    try std.testing.expectEqual(Kind.spear, weapon.kind);
    try std.testing.expectEqual(@as(i32, 7), weapon.might);
    try std.testing.expect(weapon.heavy);
    try std.testing.expectEqual(@as(?i32, 2), weapon.bonus);
    try std.testing.expectEqual(@as(usize, 2), weapon.tags.len);
    try std.testing.expectEqualStrings("cheap", weapon.tags[1]);
    try std.testing.expectEqual(@as(f32, 1.5), weapon.stats.speed);
    try std.testing.expectEqual([2]i32{ 1, 2 }, weapon.stats.range);
    try std.testing.expectEqual(@as(i32, 9), weapon.base.weight);
    try std.testing.expectEqual(@as(i32, 7), weapon.base.value);
    try std.testing.expectEqual(@as(i32, 3), weapon.costs.get(.bow));
    try std.testing.expectEqual(@as(i32, 0), weapon.costs.get(.sword));
    try std.testing.expect(weapon.usable.contains(.sword) and weapon.usable.contains(.bow) and !weapon.usable.contains(.spear));
    try std.testing.expectEqual(@as(i32, 4), weapon.alias);
    try std.testing.expect(weapon.flags.isSet(1) and weapon.flags.isSet(2) and !weapon.flags.isSet(0));
}

test "decode reports the first failure with its path" {
    var d = try Decoded.init();
    defer d.deinit();
    try d.expectFailure(Weapon, "return 1", "expected a table, got number");
    try d.expectFailure(Weapon, "return {}", "name: missing");
    try d.expectFailure(Weapon, "return { name = 'x', Name = 'y' }", "unknown field \"Name\"");
    try d.expectFailure(Weapon, "return { name = 'x', [1] = 2 }", "unexpected number key");
    try d.expectFailure(Weapon, "return { name = 1 }", "name: expected a string, got number");
    try d.expectFailure(Weapon, "return { name = 'x', might = 'y' }", "might: expected an integer, got string");
    try d.expectFailure(Weapon, "return { name = 'x', might = 1.5 }", "might: number has no integer representation");
    try d.expectFailure(Weapon, "return { name = 'x', might = 3000000000 }", "might: 3000000000 is out of range");
    try d.expectFailure(Weapon, "return { name = 'x', heavy = 1 }", "heavy: expected a boolean, got number");
    try d.expectFailure(Weapon, "return { name = 'x', kind = 'axe' }", "kind: unknown name \"axe\"; expected one of sword, spear, bow");
    try d.expectFailure(Weapon, "return { name = 'x', tags = { 'a', 2 } }", "tags[2]: expected a string, got number");
    try d.expectFailure(Weapon, "return { name = 'x', stats = { range = { 1 } } }", "stats.range: expected 2 values, got 1");
    try d.expectFailure(Weapon, "return { name = 'x', stats = { speed = print } }", "stats.speed: expected a number, got function");
    try d.expectFailure(Weapon, "return { name = 'x', costs = { axe = 1 } }", "costs: unknown field \"axe\"");
    try d.expectFailure(Weapon, "return { name = 'x', usable = { 'axe' } }", "usable[1]: unknown name \"axe\"; expected one of sword, spear, bow");
    try d.expectFailure(Weapon, "return { name = 'x', flags = 'bow' }", "flags: expected a list, got string");
}

test "decode strict levels require every field" {
    var d = try Decoded.init();
    defer d.deinit();
    var v = try d.value("return { speed = 2 }");
    defer v.deinit();
    try std.testing.expectError(error.Invalid, api.decode(Stats, v, .{ .allocator = d.arena.allocator(), .diagnostic = &d.diagnostic, .strict = 1 }));
    try std.testing.expectEqualStrings("range: missing", d.diagnostic.text);
}

test "decode can match enum names ignoring case" {
    var d = try Decoded.init();
    defer d.deinit();
    var v = try d.value("return 'SPEAR'");
    defer v.deinit();
    try std.testing.expectEqual(Kind.spear, try api.decode(Kind, v, .{ .allocator = d.arena.allocator(), .diagnostic = &d.diagnostic, .ignore_enum_case = true }));
}

const Color = struct {
    rgba: u32 = 0,

    pub fn fromLua(d: anytype, value: Value, out: *Color) api.DecodeError!void {
        if (value != .integer or value.integer < 0) return d.fail("expected a color, got {s}", .{value.typeName()});
        out.rgba = @intCast(value.integer);
    }

    pub fn toLua(self: Color) i64 {
        return self.rgba;
    }
};

test "decode uses fromLua hooks in nested values" {
    var d = try Decoded.init();
    defer d.deinit();
    const Paint = struct { colors: []const Color = &.{} };
    const paint = try d.decode(Paint, "return { colors = { 1, 2 } }");
    try std.testing.expectEqual(@as(u32, 2), paint.colors[1].rgba);
    try d.expectFailure(Paint, "return { colors = { 1, 'x' } }", "colors[2]: expected a color, got string");
}

const Catalog = struct {
    ids: []const []const u8,

    pub fn decodes(comptime T: type) bool {
        return T == Id;
    }

    pub fn decode(d: anytype, comptime T: type, value: Value, out: *T) api.DecodeError!void {
        if (value != .string) return d.fail("expected an id, got {s}", .{value.typeName()});
        for (d.context.ids, 0..) |id, index| {
            if (std.mem.eql(u8, id, value.string)) {
                out.* = @enumFromInt(index);
                return;
            }
        }
        return d.fail("unknown id \"{s}\"", .{value.string});
    }
};

test "decoder contexts decide types they do not own" {
    const Pack = struct {
        first: Id = @enumFromInt(0),
        all: std.bit_set.IntegerBitSet(4) = .empty,

        pub const lua = .{ .all = .{ .elements = Id } };
    };

    var d = try Decoded.init();
    defer d.deinit();
    var v = try d.value("return { first = 'b', all = { 'a', 'c' } }");
    defer v.deinit();
    var decoder: api.Decoder(Catalog) = .{
        .allocator = d.arena.allocator(),
        .diagnostic = &d.diagnostic,
        .context = .{ .ids = &.{ "a", "b", "c" } },
    };
    defer decoder.deinit();
    _ = try decoder.push("pack", .{});
    var pack: Pack = .{};
    try decoder.decode(Pack, v, &pack);
    try std.testing.expectEqual(@as(u8, 1), @intFromEnum(pack.first));
    try std.testing.expect(pack.all.isSet(0) and pack.all.isSet(2) and !pack.all.isSet(1));

    var bad = try d.value("return { all = { 'a', 'z' } }");
    defer bad.deinit();
    try std.testing.expectError(error.Invalid, decoder.decode(Pack, bad, &pack));
    try std.testing.expectEqualStrings("pack.all[2]: unknown id \"z\"", d.diagnostic.text);
}

test "field reflection lists keys and options" {
    const keys = api.fieldKeys(Weapon);
    var found_weight = false;
    var found_alias = false;
    for (keys) |key| {
        found_weight = found_weight or std.mem.eql(u8, key, "weight");
        found_alias = found_alias or std.mem.eql(u8, key, "other_name");
        try std.testing.expect(!std.mem.eql(u8, key, "base"));
    }
    try std.testing.expect(found_weight and found_alias);
    const name_options = comptime api.fieldOptions(Weapon, "name");
    try std.testing.expectEqualStrings("Shown in menus.", name_options.doc);
    try std.testing.expect(name_options.required);
}

const Typed = struct {
    fn describe(kind: Kind, stats: Stats, colors: []const Color, range: [2]i32, maybe: ?Stats) []const u8 {
        _ = stats;
        _ = range;
        _ = maybe;
        return if (colors.len == 2 and kind == .bow) "ok" else "no";
    }

    fn paint(color: Color, name: []const u8) i64 {
        return color.rgba + @as(i64, @intCast(name.len));
    }

    fn load(ctx: *api.Context) !void {
        var arena: std.heap.ArenaAllocator = .init(a);
        defer arena.deinit();
        const weapon = try ctx.decodeArg(0, Weapon, arena.allocator());
        try ctx.returnValues(.{weapon.might});
    }

    const Mesh = struct {
        faces: i64,

        pub fn add(self: *@This(), stats: Stats) i64 {
            self.faces += stats.range[1];
            return self.faces;
        }
    };
};

test "typed callbacks decode aggregate parameters" {
    var lua = try State.init(a, .{});
    defer lua.deinit();

    var describe = try lua.registerTyped("describe", Typed.describe);
    defer describe.deinit();
    try lua.setGlobal("describe", describe);
    var paint = try lua.registerTyped("paint", Typed.paint);
    defer paint.deinit();
    try lua.setGlobal("paint", paint);
    var load = try lua.register("load_weapon", Typed.load);
    defer load.deinit();
    try lua.setGlobal("load_weapon", load);
    try lua.defineUserdata(Typed.Mesh, .{ .name = "mesh" });
    var mesh = try lua.newUserdata(Typed.Mesh, .{ .faces = 1 }, .{});
    defer mesh.deinit();
    try lua.setGlobal("mesh", mesh);

    try lua.doString(
        \\assert(describe("bow", { speed = 2 }, { 1, 2 }, { 3, 4 }) == "ok")
        \\assert(describe("bow", {}, { 1, 2 }, { 3, 4 }, { speed = 1 }) == "ok")
        \\assert(paint(5, "abc") == 8)
        \\assert(load_weapon({ name = "x", might = 6 }) == 6)
        \\assert(mesh:add({ range = { 0, 2 } }) == 3)
        \\local ok, message = pcall(describe, "axe")
        \\assert(not ok and message:find("bad argument #1 to 'describe' (unknown name \"axe\"", 1, true), message)
        \\ok, message = pcall(describe, "bow", { speed = "fast" })
        \\assert(not ok and message:find("bad argument #2 to 'describe' (speed: expected a number, got string)", 1, true), message)
        \\ok, message = pcall(paint, "red", "abc")
        \\assert(not ok and message:find("bad argument #1 to 'paint' (expected a color, got string)", 1, true), message)
        \\ok, message = pcall(load_weapon, { might = 6 })
        \\assert(not ok and message:find("bad argument #1 to 'load_weapon' (name: missing)", 1, true), message)
        \\ok, message = pcall(mesh.add, mesh, { nope = 1 })
        \\assert(not ok and message:find("unknown field \"nope\"", 1, true), message)
    , .{});
}

test "values convert to tables by the same field options" {
    const Hero = struct {
        name: []const u8 = "ana",
        kind: Kind = .bow,
        color: Color = .{ .rgba = 9 },
        base: Weapon.Base = .{ .weight = 3 },
        alias: i32 = 4,
        costs: std.EnumArray(Kind, i32) = .initFill(2),
        usable: std.EnumSet(Kind) = .empty,
        missing: ?i32 = null,

        pub const lua = .{
            .base = .{ .embed = true },
            .alias = .{ .key = "other_name" },
        };
    };

    var lua = try State.init(a, .{});
    defer lua.deinit();
    var hero = Hero{};
    hero.usable.insert(.spear);
    try lua.setGlobal("hero", hero);
    try lua.setGlobal("mode", .fast);
    try lua.doString(
        \\assert(hero.name == "ana")
        \\assert(hero.kind == "bow")
        \\assert(hero.color == 9)
        \\assert(hero.weight == 3 and hero.value == 7 and hero.base == nil)
        \\assert(hero.other_name == 4 and hero.alias == nil)
        \\assert(hero.costs.sword == 2 and hero.costs.bow == 2)
        \\assert(#hero.usable == 1 and hero.usable[1] == "spear")
        \\assert(hero.missing == nil)
        \\assert(mode == "fast")
    , .{});

    const Open = enum(u8) { known, _ };
    try std.testing.expectError(error.UnsupportedType, lua.setGlobal("open", @as(Open, @enumFromInt(9))));
}

test "decoded values round trip through table conversion" {
    const Hero = struct {
        kind: Kind = .sword,
        base: Weapon.Base = .{},
        costs: std.EnumArray(Kind, i32) = .initFill(0),
        usable: std.EnumSet(Kind) = .empty,
        tags: []const []const u8 = &.{},

        pub const lua = .{ .base = .{ .embed = true } };
    };

    var d = try Decoded.init();
    defer d.deinit();
    var hero: Hero = .{ .kind = .bow, .base = .{ .weight = 8, .value = 2 }, .tags = &.{ "a", "b" } };
    hero.costs.set(.spear, 5);
    hero.usable.insert(.bow);

    var pushed = try d.lua.push(hero);
    defer pushed.deinit();
    const copy = try api.decode(Hero, pushed, .{ .allocator = d.arena.allocator(), .diagnostic = &d.diagnostic });
    try std.testing.expectEqual(Kind.bow, copy.kind);
    try std.testing.expectEqual(hero.base, copy.base);
    try std.testing.expectEqual(@as(i32, 5), copy.costs.get(.spear));
    try std.testing.expect(copy.usable.contains(.bow) and !copy.usable.contains(.spear));
    try std.testing.expectEqualStrings("b", copy.tags[1]);
}
