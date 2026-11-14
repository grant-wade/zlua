const std = @import("std");
const zlua = @import("zlua");
const term = @import("term.zig");
const highlight = @import("highlight.zig");

const runtime = zlua.runtime;
const State = runtime.State;
const Table = runtime.Table;
const Value = runtime.Value;
const Role = term.Role;

const indent_width = 2;

pub const Options = struct {
    paint: term.Paint = .{},
    /// Columns a table may use before it is split across lines.
    width: usize = 80,
    /// Tables nested deeper print as `{...}`.
    max_depth: usize = 6,
    /// Table items printed in total; the rest are counted.
    max_items: usize = 200,
};

const Leaf = struct {
    text: []const u8,
    role: ?Role = null,
};

const Node = union(enum) {
    leaf: Leaf,
    table: struct { items: []Item, omitted: usize },
    /// Index into `Builder.described`, the values printed with `tostring`.
    described: usize,
};

const Item = struct {
    /// Null for the next position of the sequence.
    key: ?Leaf,
    /// `key` is a name written `name = value`.
    named: bool = false,
    value: Node,
};

const Builder = struct {
    state: *State,
    arena: std.mem.Allocator,
    options: Options,
    remaining: usize,
    path: std.ArrayList(*Table) = .empty,
    described: std.ArrayList(Value) = .empty,
    texts: []Leaf = &.{},

    fn build(self: *Builder, value: Value) anyerror!Node {
        switch (value) {
            .nil, .boolean => return .{ .leaf = .{ .text = try self.plainText(value), .role = .keyword } },
            .integer, .number => return .{ .leaf = .{ .text = try self.plainText(value), .role = .number } },
            .string => |string| return .{ .leaf = .{ .text = try quote(self.arena, string.bytes()), .role = .string } },
            .userdata => return self.describe(value),
            .table => |table| {
                if (table.metatable) |metatable| {
                    if (metatable.getBytes("__tostring") != .nil or metatable.getBytes("__name") != .nil) return self.describe(value);
                }
                for (self.path.items) |ancestor| {
                    if (ancestor == table) return .{ .leaf = .{ .text = "<cycle>", .role = .dim } };
                }
                if (self.path.items.len >= self.options.max_depth) return .{ .leaf = .{ .text = "{...}", .role = .dim } };
                try self.path.append(self.arena, table);
                defer _ = self.path.pop();
                return self.buildTable(table);
            },
            else => return .{ .leaf = .{ .text = try self.plainText(value), .role = .object } },
        }
    }

    fn describe(self: *Builder, value: Value) !Node {
        try self.described.append(self.arena, value);
        return .{ .described = self.described.items.len - 1 };
    }

    fn buildTable(self: *Builder, table: *Table) !Node {
        const Pair = struct { key: Value, value: Value };
        var keyed = std.ArrayList(Pair).empty;
        const border: usize = @intCast(@max(table.len(), 0));
        for (table.array.items(), 1..) |value, position| {
            if (position > border and value != .nil) try keyed.append(self.arena, .{ .key = .{ .integer = @intCast(position) }, .value = value });
        }
        for (table.entries()) |entry| {
            if (entry.value == .nil) continue;
            if (entry.key == .integer and entry.key.integer >= 1 and entry.key.integer <= border) continue;
            try keyed.append(self.arena, .{ .key = entry.key, .value = entry.value });
        }
        std.mem.sort(Pair, keyed.items, {}, struct {
            fn lessThan(_: void, a: Pair, b: Pair) bool {
                return keyLessThan(a.key, b.key);
            }
        }.lessThan);

        const total = border + keyed.items.len;
        var items = std.ArrayList(Item).empty;
        for (1..border + 1) |position| {
            if (self.remaining == 0) break;
            self.remaining -= 1;
            try items.append(self.arena, .{ .key = null, .value = try self.build(table.get(.{ .integer = @intCast(position) })) });
        }
        if (items.items.len == border) for (keyed.items) |pair| {
            if (self.remaining == 0) break;
            self.remaining -= 1;
            const named = pair.key == .string and highlight.isIdentifier(pair.key.string.bytes());
            const key: Leaf = if (named)
                .{ .text = try self.arena.dupe(u8, pair.key.string.bytes()) }
            else switch (pair.key) {
                .string => |string| .{ .text = try quote(self.arena, string.bytes()), .role = .string },
                .integer, .number => .{ .text = try self.plainText(pair.key), .role = .number },
                .boolean => .{ .text = try self.plainText(pair.key), .role = .keyword },
                else => .{ .text = try self.plainText(pair.key), .role = .object },
            };
            try items.append(self.arena, .{ .key = key, .named = named, .value = try self.build(pair.value) });
        };
        return .{ .table = .{ .items = items.items, .omitted = total - items.items.len } };
    }

    fn plainText(self: *Builder, value: Value) ![]const u8 {
        var out = std.ArrayList(u8).empty;
        try runtime.appendValue(self.arena, &out, value);
        return out.items;
    }

    fn resolveDescribed(self: *Builder) !void {
        self.texts = try self.arena.alloc(Leaf, self.described.items.len);
        var roots: runtime.ValueRoots = undefined;
        self.state.pushValueRoots(&roots, self.described.items);
        defer self.state.popValueRoots(&roots);
        for (self.described.items, self.texts) |value, *text| {
            text.* = .{ .text = try self.plainText(value), .role = .object };
            const results = runtime.entry.callFunctionHandled(self.state, .native_tostring, &.{value}, .{}) catch |err| switch (err) {
                error.OutOfMemory => return err,
                else => continue,
            };
            defer self.state.allocator.free(results);
            if (results.len != 0 and results[0] == .string) text.text = try self.arena.dupe(u8, results[0].string.bytes());
        }
    }
};

fn keyRank(key: Value) u8 {
    return switch (key) {
        .integer, .number => 0,
        .string => 1,
        else => 2,
    };
}

fn keyLessThan(a: Value, b: Value) bool {
    const rank = keyRank(a);
    if (rank != keyRank(b)) return rank < keyRank(b);
    return switch (rank) {
        0 => numberOf(a) < numberOf(b),
        1 => std.mem.lessThan(u8, a.string.bytes(), b.string.bytes()),
        else => false,
    };
}

fn numberOf(value: Value) f64 {
    return switch (value) {
        .integer => |integer| @floatFromInt(integer),
        .number => |number| number,
        else => unreachable,
    };
}

pub fn quote(allocator: std.mem.Allocator, bytes: []const u8) ![]const u8 {
    var out = std.ArrayList(u8).empty;
    errdefer out.deinit(allocator);
    try out.append(allocator, '"');
    var index: usize = 0;
    while (index < bytes.len) {
        const byte = bytes[index];
        const len = std.unicode.utf8ByteSequenceLength(byte) catch 0;
        const valid = len != 0 and index + len <= bytes.len and std.unicode.utf8ValidateSlice(bytes[index..][0..len]);
        switch (byte) {
            '"' => try out.appendSlice(allocator, "\\\""),
            '\\' => try out.appendSlice(allocator, "\\\\"),
            '\n' => try out.appendSlice(allocator, "\\n"),
            '\r' => try out.appendSlice(allocator, "\\r"),
            '\t' => try out.appendSlice(allocator, "\\t"),
            else => if (byte < 0x20 or byte == 0x7f or !valid) {
                var escape: [4]u8 = undefined;
                try out.appendSlice(allocator, std.fmt.bufPrint(&escape, "\\x{X:0>2}", .{byte}) catch unreachable);
            } else {
                try out.appendSlice(allocator, bytes[index..][0..len]);
                index += len - 1;
            },
        }
        index += 1;
    }
    try out.append(allocator, '"');
    return out.toOwnedSlice(allocator);
}

const Printer = struct {
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    options: Options,
    texts: []const Leaf,

    fn leafOf(self: *const Printer, node: Node) ?Leaf {
        return switch (node) {
            .leaf => |leaf| leaf,
            .described => |index| self.texts[index],
            .table => null,
        };
    }

    /// Null when `node` needs more than `limit` columns or holds a line break.
    fn flatWidth(self: *const Printer, node: Node, limit: usize) ?usize {
        if (self.leafOf(node)) |leaf| {
            if (std.mem.indexOfScalar(u8, leaf.text, '\n') != null) return null;
            const width = term.textWidth(leaf.text);
            return if (width > limit) null else width;
        }
        const table = node.table;
        var width: usize = 2;
        for (table.items, 0..) |item, index| {
            if (index != 0) width += 2;
            if (item.key) |key| width += term.textWidth(key.text) + @as(usize, if (item.named) 3 else 5);
            if (width > limit) return null;
            width += self.flatWidth(item.value, limit - width) orelse return null;
        }
        if (table.omitted != 0) width += omittedWidth(table.omitted) + @as(usize, if (table.items.len != 0) 2 else 0);
        return if (width > limit) null else width;
    }

    fn write(self: *Printer, node: Node, indent: usize, column: usize) anyerror!void {
        if (self.leafOf(node)) |leaf| return self.writeLeaf(leaf);
        const table = node.table;
        const flat = self.flatWidth(node, self.options.width -| column) != null;
        try self.text("{");
        for (table.items, 0..) |item, index| {
            if (flat and index != 0) try self.text(", ");
            if (!flat) try self.newline(indent + indent_width);
            var key_width: usize = 0;
            if (item.key) |key| {
                if (!item.named) try self.text("[");
                try self.writeLeaf(key);
                try self.text(if (item.named) " = " else "] = ");
                key_width = term.textWidth(key.text) + @as(usize, if (item.named) 3 else 5);
            }
            try self.write(item.value, indent + indent_width, indent + indent_width + key_width);
            if (!flat) try self.text(",");
        }
        if (table.omitted != 0) {
            if (flat and table.items.len != 0) try self.text(", ");
            if (!flat) try self.newline(indent + indent_width);
            var buffer: [40]u8 = undefined;
            try self.writeLeaf(.{ .text = std.fmt.bufPrint(&buffer, "... {d} more", .{table.omitted}) catch unreachable, .role = .dim });
        }
        if (!flat) try self.newline(indent);
        try self.text("}");
    }

    fn omittedWidth(omitted: usize) usize {
        return std.fmt.count("... {d} more", .{omitted});
    }

    fn newline(self: *Printer, indent: usize) !void {
        try self.out.append(self.allocator, '\n');
        try self.out.appendNTimes(self.allocator, ' ', indent);
    }

    fn text(self: *Printer, bytes: []const u8) !void {
        try self.out.appendSlice(self.allocator, bytes);
    }

    fn writeLeaf(self: *Printer, leaf: Leaf) !void {
        const paint = self.options.paint;
        if (leaf.role) |role| try self.text(paint.on(role));
        try self.text(leaf.text);
        if (leaf.role != null) try self.text(paint.off());
    }
};

/// `value` must be reachable from a GC root.
pub fn append(state: *State, allocator: std.mem.Allocator, out: *std.ArrayList(u8), value: Value, options: Options) !void {
    var arena: std.heap.ArenaAllocator = .init(allocator);
    defer arena.deinit();
    var builder: Builder = .{ .state = state, .arena = arena.allocator(), .options = options, .remaining = options.max_items };
    const node = try builder.build(value);
    try builder.resolveDescribed();
    var printer: Printer = .{ .allocator = allocator, .out = out, .options = options, .texts = builder.texts };
    try printer.write(node, 0, 0);
}

fn expectInspect(source: []const u8, options: Options, expected: []const u8) !void {
    const allocator = std.testing.allocator;
    var state = try State.initWithOptions(allocator, .{ .stdlib = .safe });
    defer state.deinit();
    const loaded = try runtime.load.loadSourceAsClosureNamed(&state, source, "=test");
    const results = try runtime.entry.callFunctionHandled(&state, loaded, &.{}, .{});
    defer allocator.free(results);
    var roots: runtime.ValueRoots = undefined;
    state.pushValueRoots(&roots, results);
    defer state.popValueRoots(&roots);
    var out = std.ArrayList(u8).empty;
    defer out.deinit(allocator);
    try append(&state, allocator, &out, results[0], options);
    try std.testing.expectEqualStrings(expected, out.items);
}

test "scalars print as Lua literals" {
    try expectInspect("return 42", .{}, "42");
    try expectInspect("return 1.5", .{}, "1.5");
    try expectInspect("return nil", .{}, "nil");
    try expectInspect("return 'a\\n\"b\"\\0\\xff\\u{e9}'", .{}, "\"a\\n\\\"b\\\"\\x00\\xFF\u{e9}\"");
}

test "tables print their sequence, then sorted keys" {
    try expectInspect("return {}", .{}, "{}");
    try expectInspect("return {1, 'two', b = 2, a = 1, [10] = true, ['a b'] = 0}", .{}, "{1, \"two\", [10] = true, a = 1, [\"a b\"] = 0, b = 2}");
    try expectInspect("return {{1, 2}, {x = {}}}", .{}, "{{1, 2}, {x = {}}}");
}

test "wide tables split across lines" {
    try expectInspect("return {name = 'zlua', tags = {'a', 'b'}, nested = {deep = {1, 2, 3}}}", .{ .width = 30 },
        \\{
        \\  name = "zlua",
        \\  nested = {deep = {1, 2, 3}},
        \\  tags = {"a", "b"},
        \\}
    );
}

test "cycles, depth, and item limits are bounded" {
    try expectInspect("local t = {} t.self = t return t", .{}, "{self = <cycle>}");
    try expectInspect("return {{{{}}}}", .{ .max_depth = 2 }, "{{{...}}}");
    try expectInspect("return {1, 2, 3, 4, 5, x = 1}", .{ .max_items = 3 }, "{1, 2, 3, ... 3 more}");
}

test "tostring metamethods describe values" {
    try expectInspect("return setmetatable({}, {__tostring = function() return 'point(1, 2)' end})", .{}, "point(1, 2)");
    try expectInspect("return {1, p = setmetatable({}, {__tostring = function() return 'P' end})}", .{}, "{1, p = P}");
    try expectInspect("return {setmetatable({}, {__tostring = function() error('no') end}) == nil}", .{}, "{false}");
}
