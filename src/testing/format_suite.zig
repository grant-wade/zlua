const std = @import("std");
const api = @import("../root.zig");
const runtime = @import("../runtime.zig");
const handle = @import("../api/handle.zig");
const datetime = @import("../stdlib/datetime.zig");
const expected_failures = @import("expected_failures.zig");

const Dir = std.Io.Dir;
const File = std.Io.File;
const Json = std.json.Value;

const Options = struct {
    toml_test: []const u8 = ".zlua-deps/toml-test",
    msgpack_suite: []const u8 = ".zlua-deps/msgpack-test-suite",
    json_suite: []const u8 = "tests/formats/json/test_parsing",
    csv_suite: []const u8 = ".zlua-deps/csv-spectrum",
    expected: []const u8 = "tests/formats/expected_failures.toml",
};

const Counts = struct {
    passed: usize = 0,
    failed: usize = 0,
    expected_failed: usize = 0,
    implementation_accepted: usize = 0,
    implementation_rejected: usize = 0,
};

pub fn runCli(allocator: std.mem.Allocator, io: std.Io, args: []const []const u8) !u8 {
    const options = parseArgs(args) catch |err| {
        std.debug.print("test-formats: {s}\n", .{@errorName(err)});
        return 2;
    };

    var registry = try expected_failures.load(allocator, io, options.expected);
    defer registry.deinit();

    var lua = try api.State.init(allocator, .{});
    defer lua.deinit();

    var buffer: [8192]u8 = undefined;
    var writer = File.stdout().writer(io, &buffer);

    var suite: Suite = .{
        .allocator = allocator,
        .io = io,
        .out = &writer.interface,
        .registry = registry,
        .lua = &lua,
        .codecs = try Codecs.init(&lua),
    };
    defer suite.codecs.deinit();

    try suite.runToml(options.toml_test);
    try suite.runMsgpack(options.msgpack_suite);
    try suite.runJson(options.json_suite);
    try suite.runCsv(options.csv_suite);

    const counts = suite.counts;
    try suite.out.print(
        \\summary:
        \\  passed={d}
        \\  failed={d}
        \\  expected_failed={d}
        \\  json_implementation_defined_accepted={d}
        \\  json_implementation_defined_rejected={d}
        \\
    , .{ counts.passed, counts.failed, counts.expected_failed, counts.implementation_accepted, counts.implementation_rejected });
    try suite.out.flush();
    return if (counts.failed == 0) 0 else 1;
}

fn parseArgs(args: []const []const u8) !Options {
    var options: Options = .{};
    for (args) |arg| {
        if (std.mem.startsWith(u8, arg, "--toml-test=")) {
            options.toml_test = arg["--toml-test=".len..];
        } else if (std.mem.startsWith(u8, arg, "--msgpack-suite=")) {
            options.msgpack_suite = arg["--msgpack-suite=".len..];
        } else if (std.mem.startsWith(u8, arg, "--json-suite=")) {
            options.json_suite = arg["--json-suite=".len..];
        } else if (std.mem.startsWith(u8, arg, "--csv-suite=")) {
            options.csv_suite = arg["--csv-suite=".len..];
        } else if (std.mem.startsWith(u8, arg, "--expected=")) {
            options.expected = arg["--expected=".len..];
        } else {
            return error.UnknownOption;
        }
    }
    return options;
}

const Codecs = struct {
    json_read: api.Function,
    json_write: api.Function,
    toml_read: api.Function,
    toml_write: api.Function,
    msgpack_read: api.Function,
    msgpack_write: api.Function,
    csv_read: api.Function,
    csv_write: api.Function,
    sections: api.Table,

    fn init(lua: *api.State) !Codecs {
        var json = try lua.getGlobal("json", api.Table);
        defer json.deinit();
        var toml = try lua.getGlobal("toml", api.Table);
        defer toml.deinit();
        var msgpack = try lua.getGlobal("msgpack", api.Table);
        defer msgpack.deinit();
        var csv = try lua.getGlobal("csv", api.Table);
        defer csv.deinit();
        return .{
            .json_read = try json.get("read", api.Function),
            .json_write = try json.get("write", api.Function),
            .toml_read = try toml.get("read", api.Function),
            .toml_write = try toml.get("write", api.Function),
            .msgpack_read = try msgpack.get("read", api.Function),
            .msgpack_write = try msgpack.get("write", api.Function),
            .csv_read = try csv.get("read", api.Function),
            .csv_write = try csv.get("write", api.Function),
            .sections = try lua.createTableFrom(.{ .layout = "sections" }),
        };
    }

    fn deinit(self: *Codecs) void {
        self.json_read.deinit();
        self.json_write.deinit();
        self.toml_read.deinit();
        self.toml_write.deinit();
        self.msgpack_read.deinit();
        self.msgpack_write.deinit();
        self.csv_read.deinit();
        self.csv_write.deinit();
        self.sections.deinit();
    }
};

/// A rooted decoded value.
const Decoded = struct {
    ref: handle.Ref,

    fn raw(self: Decoded) !runtime.Value {
        return handle.rawValue(self.ref);
    }

    fn deinit(self: *Decoded) void {
        self.ref.deinit();
    }
};

const Outcome = union(enum) {
    ok: Decoded,
    lua_error: []const u8,
};

const Encoded = union(enum) {
    ok: []const u8,
    lua_error: []const u8,
};

const Suite = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    out: *std.Io.Writer,
    registry: expected_failures.Registry,
    lua: *api.State,
    codecs: Codecs,
    counts: Counts = .{},
    arena: std.heap.ArenaAllocator = undefined,

    /// `detail` is null when the case passed.
    fn report(self: *Suite, id: []const u8, detail: ?[]const u8) !void {
        const reason = self.registry.reason(id);
        if (detail == null and reason == null) {
            self.counts.passed += 1;
        } else if (detail != null and reason != null) {
            self.counts.expected_failed += 1;
            try self.out.print("xfail {s} ({s})\n", .{ id, reason.? });
        } else {
            self.counts.failed += 1;
            if (detail) |text| {
                try self.out.print("fail {s}: {s}\n", .{ id, text });
            } else {
                try self.out.print("fail {s} (expected failure passed)\n", .{id});
            }
        }
    }

    fn call(self: *Suite, function: api.Function, args: anytype) !Outcome {
        var result = try function.protectedCall(args, handle.Ref);
        switch (result) {
            .ok => |ref| return .{ .ok = .{ .ref = ref } },
            .lua_error => |*err| {
                defer err.deinit();
                const message = try err.message();
                defer self.lua.allocator().free(message);
                return .{ .lua_error = try self.arena.allocator().dupe(u8, message) };
            },
        }
    }

    fn encode(self: *Suite, function: api.Function, args: anytype) !Encoded {
        var result = try function.protectedCall(args, []const u8);
        switch (result) {
            .ok => |bytes| return .{ .ok = try self.arena.allocator().dupe(u8, bytes) },
            .lua_error => |*err| {
                defer err.deinit();
                const message = try err.message();
                defer self.lua.allocator().free(message);
                return .{ .lua_error = try self.arena.allocator().dupe(u8, message) };
            },
        }
    }

    fn readFile(self: *Suite, path: []const u8) ![]u8 {
        return Dir.cwd().readFileAlloc(self.io, path, self.arena.allocator(), .limited(64 * 1024 * 1024));
    }

    fn parseJson(self: *Suite, text: []const u8) !Json {
        return std.json.parseFromSliceLeaky(Json, self.arena.allocator(), text, .{ .duplicate_field_behavior = .use_last });
    }

    fn resetArena(self: *Suite) void {
        self.arena.deinit();
        self.arena = .init(self.allocator);
    }

    fn runToml(self: *Suite, root: []const u8) !void {
        self.arena = .init(self.allocator);
        defer self.arena.deinit();
        const list_path = try std.fs.path.join(self.allocator, &.{ root, "tests", "files-toml-1.1.0" });
        defer self.allocator.free(list_path);
        const list = try Dir.cwd().readFileAlloc(self.io, list_path, self.allocator, .limited(1024 * 1024));
        defer self.allocator.free(list);

        var lines = std.mem.tokenizeAny(u8, list, "\r\n");
        while (lines.next()) |name| {
            if (!std.mem.endsWith(u8, name, ".toml")) continue;
            self.resetArena();
            const a = self.arena.allocator();
            const input = try self.readFile(try std.fs.path.join(a, &.{ root, "tests", name }));
            var outcome = try self.call(self.codecs.toml_read, .{input});
            defer if (outcome == .ok) outcome.ok.deinit();

            if (std.mem.startsWith(u8, name, "invalid/")) {
                try self.report(try std.fmt.allocPrint(a, "toml decode {s}", .{name}), if (outcome == .ok) "accepted invalid input" else null);
                continue;
            }

            const json_name = try std.fmt.allocPrint(a, "{s}.json", .{name[0 .. name.len - ".toml".len]});
            const want = try self.parseJson(try self.readFile(try std.fs.path.join(a, &.{ root, "tests", json_name })));
            const decode_id = try std.fmt.allocPrint(a, "toml decode {s}", .{name});
            const decoded = switch (outcome) {
                .ok => |value| value,
                .lua_error => |message| {
                    try self.report(decode_id, message);
                    continue;
                },
            };
            try self.report(decode_id, try self.compareToml(try decoded.raw(), want, "$"));

            for ([_][]const u8{ "inline", "sections" }) |layout| {
                const id = try std.fmt.allocPrint(a, "toml encode {s} {s}", .{ layout, name });
                const encoded = if (std.mem.eql(u8, layout, "inline"))
                    try self.encode(self.codecs.toml_write, .{decoded.ref})
                else
                    try self.encode(self.codecs.toml_write, .{ decoded.ref, self.codecs.sections });
                const text = switch (encoded) {
                    .ok => |bytes| bytes,
                    .lua_error => |message| {
                        try self.report(id, message);
                        continue;
                    },
                };
                var again = try self.call(self.codecs.toml_read, .{text});
                defer if (again == .ok) again.ok.deinit();
                switch (again) {
                    .ok => |value| try self.report(id, try self.compareToml(try value.raw(), want, "$")),
                    .lua_error => |message| try self.report(id, try std.fmt.allocPrint(a, "reading the output failed: {s}\n{s}", .{ message, text })),
                }
            }
        }
    }

    fn runMsgpack(self: *Suite, root: []const u8) !void {
        self.arena = .init(self.allocator);
        defer self.arena.deinit();
        const path = try std.fs.path.join(self.allocator, &.{ root, "dist", "msgpack-test-suite.json" });
        defer self.allocator.free(path);
        var file_arena: std.heap.ArenaAllocator = .init(self.allocator);
        defer file_arena.deinit();
        const text = try Dir.cwd().readFileAlloc(self.io, path, file_arena.allocator(), .limited(16 * 1024 * 1024));
        const groups = try std.json.parseFromSliceLeaky(Json, file_arena.allocator(), text, .{});

        var names: std.ArrayList([]const u8) = .empty;
        defer names.deinit(self.allocator);
        for (groups.object.keys()) |name| try names.append(self.allocator, name);
        std.mem.sort([]const u8, names.items, {}, lessThanString);

        for (names.items) |group| {
            for (groups.object.get(group).?.array.items, 1..) |entry, index| {
                self.resetArena();
                const a = self.arena.allocator();
                const encodings = entry.object.get("msgpack").?.array.items;
                var first_ok: ?Decoded = null;
                defer if (first_ok) |*value| value.deinit();
                for (encodings, 0..) |hex, position| {
                    const id = try std.fmt.allocPrint(a, "msgpack decode {s}#{d} {s}", .{ group, index, hex.string });
                    var outcome = try self.call(self.codecs.msgpack_read, .{try hexBytes(a, hex.string)});
                    switch (outcome) {
                        .ok => |*value| {
                            const detail = try self.compareMsgpack(try value.raw(), entry);
                            try self.report(id, detail);
                            if (position == 0 and detail == null) first_ok = value.* else value.deinit();
                        },
                        .lua_error => |message| try self.report(id, message),
                    }
                }

                const decoded = first_ok orelse continue;
                if (entry.object.get("binary")) |binary| {
                    if (std.unicode.utf8ValidateSlice(try hexBytes(a, binary.string))) continue;
                }
                const id = try std.fmt.allocPrint(a, "msgpack encode {s}#{d}", .{ group, index });
                const bytes = switch (try self.encode(self.codecs.msgpack_write, .{decoded.ref})) {
                    .ok => |bytes| bytes,
                    .lua_error => |message| {
                        try self.report(id, message);
                        continue;
                    },
                };
                try self.report(id, if (matchesAny(a, bytes, encodings)) null else try std.fmt.allocPrint(a, "wrote {s}", .{try bytesHex(a, bytes)}));
            }
        }
    }

    fn runJson(self: *Suite, root: []const u8) !void {
        self.arena = .init(self.allocator);
        defer self.arena.deinit();
        var dir = try Dir.cwd().openDir(self.io, root, .{ .iterate = true });
        defer dir.close(self.io);
        var names: std.ArrayList([]u8) = .empty;
        defer {
            for (names.items) |name| self.allocator.free(name);
            names.deinit(self.allocator);
        }
        var iterator = dir.iterate();
        while (try iterator.next(self.io)) |entry| {
            if (entry.kind == .file and std.mem.endsWith(u8, entry.name, ".json")) try names.append(self.allocator, try self.allocator.dupe(u8, entry.name));
        }
        std.mem.sort([]u8, names.items, {}, lessThanMutable);

        for (names.items) |name| {
            self.resetArena();
            const a = self.arena.allocator();
            const input = try self.readFile(try std.fs.path.join(a, &.{ root, name }));
            var outcome = try self.call(self.codecs.json_read, .{input});
            defer if (outcome == .ok) outcome.ok.deinit();

            switch (name[0]) {
                'n' => try self.report(try std.fmt.allocPrint(a, "json reject {s}", .{name}), if (outcome == .ok) "accepted invalid input" else null),
                'i' => if (outcome == .ok) {
                    self.counts.implementation_accepted += 1;
                } else {
                    self.counts.implementation_rejected += 1;
                },
                else => {
                    const id = try std.fmt.allocPrint(a, "json accept {s}", .{name});
                    const decoded = switch (outcome) {
                        .ok => |value| value,
                        .lua_error => |message| {
                            try self.report(id, message);
                            continue;
                        },
                    };
                    const want = self.parseJson(input) catch {
                        try self.report(id, null);
                        continue;
                    };
                    try self.report(id, try self.compareJson(try decoded.raw(), want, "$"));

                    const round_id = try std.fmt.allocPrint(a, "json round trip {s}", .{name});
                    const text = switch (try self.encode(self.codecs.json_write, .{decoded.ref})) {
                        .ok => |bytes| bytes,
                        .lua_error => |message| {
                            try self.report(round_id, message);
                            continue;
                        },
                    };
                    var again = try self.call(self.codecs.json_read, .{text});
                    defer if (again == .ok) again.ok.deinit();
                    switch (again) {
                        .ok => |value| try self.report(round_id, try self.compareJson(try value.raw(), want, "$")),
                        .lua_error => |message| try self.report(round_id, message),
                    }
                },
            }
        }
    }

    fn runCsv(self: *Suite, root: []const u8) !void {
        self.arena = .init(self.allocator);
        defer self.arena.deinit();
        const csv_dir = try std.fs.path.join(self.allocator, &.{ root, "csvs" });
        defer self.allocator.free(csv_dir);
        var dir = try Dir.cwd().openDir(self.io, csv_dir, .{ .iterate = true });
        defer dir.close(self.io);
        var names: std.ArrayList([]u8) = .empty;
        defer {
            for (names.items) |name| self.allocator.free(name);
            names.deinit(self.allocator);
        }
        var iterator = dir.iterate();
        while (try iterator.next(self.io)) |entry| {
            if (entry.kind == .file and std.mem.endsWith(u8, entry.name, ".csv")) try names.append(self.allocator, try self.allocator.dupe(u8, entry.name));
        }
        std.mem.sort([]u8, names.items, {}, lessThanMutable);

        for (names.items) |name| {
            self.resetArena();
            const a = self.arena.allocator();
            const stem = name[0 .. name.len - ".csv".len];
            const input = try self.readFile(try std.fs.path.join(a, &.{ csv_dir, name }));
            const want = try self.parseJson(try self.readFile(try std.fs.path.join(a, &.{ root, "json", try std.fmt.allocPrint(a, "{s}.json", .{stem}) })));

            const id = try std.fmt.allocPrint(a, "csv decode {s}", .{name});
            var outcome = try self.call(self.codecs.csv_read, .{input});
            defer if (outcome == .ok) outcome.ok.deinit();
            const decoded = switch (outcome) {
                .ok => |value| value,
                .lua_error => |message| {
                    try self.report(id, message);
                    continue;
                },
            };
            try self.report(id, try self.compareJson(try decoded.raw(), want, "$"));

            const round_id = try std.fmt.allocPrint(a, "csv round trip {s}", .{name});
            const text = switch (try self.encode(self.codecs.csv_write, .{decoded.ref})) {
                .ok => |bytes| bytes,
                .lua_error => |message| {
                    try self.report(round_id, message);
                    continue;
                },
            };
            var again = try self.call(self.codecs.csv_read, .{text});
            defer if (again == .ok) again.ok.deinit();
            switch (again) {
                .ok => |value| try self.report(round_id, try self.compareJson(try value.raw(), want, "$")),
                .lua_error => |message| try self.report(round_id, message),
            }
        }
    }

    fn mismatch(self: *Suite, path: []const u8, comptime fmt: []const u8, args: anytype) !?[]const u8 {
        const text: []const u8 = try std.fmt.allocPrint(self.arena.allocator(), "{s}: " ++ fmt, .{path} ++ args);
        return text;
    }

    fn child(self: *Suite, path: []const u8, key: anytype) ![]const u8 {
        return switch (@TypeOf(key)) {
            usize => std.fmt.allocPrint(self.arena.allocator(), "{s}[{d}]", .{ path, key }),
            else => std.fmt.allocPrint(self.arena.allocator(), "{s}.{s}", .{ path, key }),
        };
    }

    fn container(self: *Suite, value: runtime.Value, comptime kind: enum { array, object }) ?*runtime.Table {
        if (value != .table) return null;
        const tables = &self.lua.raw_state.library_tables;
        const expected = if (kind == .array) tables.get(.data_array_metatable) else tables.get(.data_object_metatable);
        if (expected == null or value.table.metatable != expected) return null;
        return value.table;
    }

    fn isNull(self: *Suite, value: runtime.Value) bool {
        return value == .table and value.table == self.lua.raw_state.library_tables.get(.data_null);
    }

    /// `compareLeaf` compares each element.
    fn compareTree(self: *Suite, got: runtime.Value, want: Json, path: []const u8, comptime compareLeaf: anytype) anyerror!?[]const u8 {
        switch (want) {
            .array => |items| {
                const table = self.container(got, .array) orelse return self.mismatch(path, "expected an array", .{});
                if (entryCount(table) != items.items.len) return self.mismatch(path, "expected {d} elements, got {d}", .{ items.items.len, entryCount(table) });
                for (items.items, 0..) |item, index| {
                    if (try compareLeaf(self, table.get(.{ .integer = @intCast(index + 1) }), item, try self.child(path, index + 1))) |detail| return detail;
                }
                return null;
            },
            .object => |map| {
                const table = self.container(got, .object) orelse return self.mismatch(path, "expected an object", .{});
                if (entryCount(table) != map.count()) return self.mismatch(path, "expected {d} keys, got {d}", .{ map.count(), entryCount(table) });
                var iterator = map.iterator();
                while (iterator.next()) |entry| {
                    if (try compareLeaf(self, table.getBytes(entry.key_ptr.*), entry.value_ptr.*, try self.child(path, entry.key_ptr.*))) |detail| return detail;
                }
                return null;
            },
            else => unreachable,
        }
    }

    fn compareJson(self: *Suite, got: runtime.Value, want: Json, path: []const u8) anyerror!?[]const u8 {
        switch (want) {
            .array, .object => return self.compareTree(got, want, path, compareJson),
            .null => return if (self.isNull(got)) null else self.mismatch(path, "expected null", .{}),
            .bool => |expected| return if (got == .boolean and got.boolean == expected) null else self.mismatch(path, "expected {}", .{expected}),
            .integer => |expected| return compareNumber(self, got, @floatFromInt(expected), expected, path),
            .float => |expected| return compareNumber(self, got, expected, null, path),
            .number_string => |text| return compareNumber(self, got, std.fmt.parseFloat(f64, text) catch return self.mismatch(path, "bad oracle number", .{}), std.fmt.parseInt(i64, text, 10) catch null, path),
            .string => |expected| return if (got == .string and std.mem.eql(u8, got.string.bytes(), expected)) null else self.mismatch(path, "expected string \"{s}\"", .{expected}),
        }
    }

    fn compareToml(self: *Suite, got: runtime.Value, want: Json, path: []const u8) anyerror!?[]const u8 {
        const tag = taggedScalar(want) orelse return switch (want) {
            .array, .object => self.compareTree(got, want, path, compareToml),
            else => self.mismatch(path, "bad oracle value", .{}),
        };
        const text = tag.value;
        if (std.mem.eql(u8, tag.type, "string")) {
            return if (got == .string and std.mem.eql(u8, got.string.bytes(), text)) null else self.mismatch(path, "expected string \"{s}\"", .{text});
        }
        if (std.mem.eql(u8, tag.type, "bool")) {
            return if (got == .boolean and got.boolean == std.mem.eql(u8, text, "true")) null else self.mismatch(path, "expected {s}", .{text});
        }
        if (std.mem.eql(u8, tag.type, "integer")) {
            const expected = try std.fmt.parseInt(i64, text, 10);
            return if (got == .integer and got.integer == expected) null else self.mismatch(path, "expected integer {s}", .{text});
        }
        if (std.mem.eql(u8, tag.type, "float")) {
            if (got != .number) return self.mismatch(path, "expected float {s}", .{text});
            const expected = parseTaggedFloat(text) orelse return self.mismatch(path, "bad oracle float", .{});
            if (std.math.isNan(expected)) return if (std.math.isNan(got.number)) null else self.mismatch(path, "expected nan", .{});
            return if (got.number == expected) null else self.mismatch(path, "expected float {s}, got {d}", .{ text, got.number });
        }
        if (got != .table or !datetime.isDateTime(&self.lua.raw_state, got.table)) return self.mismatch(path, "expected {s} {s}", .{ tag.type, text });
        const actual = switch (datetime.fromTable(got.table)) {
            .ok => |value| value,
            .invalid => |message| return self.mismatch(path, "invalid datetime: {s}", .{message}),
        };
        var failure: datetime.Failure = undefined;
        const expected = datetime.parse(text, &failure) catch return self.mismatch(path, "bad oracle datetime", .{});
        const kind_ok = if (std.mem.eql(u8, tag.type, "datetime"))
            actual.offset != null
        else if (std.mem.eql(u8, tag.type, "datetime-local"))
            actual.date != null and actual.time != null and actual.offset == null
        else if (std.mem.eql(u8, tag.type, "date-local"))
            actual.date != null and actual.time == null
        else
            actual.date == null and actual.time != null;
        if (!kind_ok or !std.meta.eql(actual, expected)) return self.mismatch(path, "expected {s} {s}, got {f}", .{ tag.type, text, actual });
        return null;
    }

    fn compareMsgpack(self: *Suite, got: runtime.Value, entry: Json) !?[]const u8 {
        const a = self.arena.allocator();
        const fields = entry.object;
        if (fields.get("nil") != null) return if (self.isNull(got)) null else self.mismatch("$", "expected nil", .{});
        if (fields.get("binary")) |binary| {
            const expected = try hexBytes(a, binary.string);
            return if (got == .string and std.mem.eql(u8, got.string.bytes(), expected)) null else self.mismatch("$", "expected bytes {s}", .{binary.string});
        }
        if (fields.get("bignum")) |bignum| {
            return compareNumber(self, got, try std.fmt.parseFloat(f64, bignum.string), std.fmt.parseInt(i64, bignum.string, 10) catch null, "$");
        }
        if (fields.get("timestamp")) |timestamp| {
            const items = timestamp.array.items;
            const expected = datetime.DateTime.fromUnix(items[0].integer, @intCast(items[1].integer));
            if (got != .table or !datetime.isDateTime(&self.lua.raw_state, got.table)) return self.mismatch("$", "expected a datetime", .{});
            return switch (datetime.fromTable(got.table)) {
                .ok => |actual| if (std.meta.eql(actual, expected)) null else self.mismatch("$", "expected {f}, got {f}", .{ expected, actual }),
                .invalid => |message| self.mismatch("$", "invalid datetime: {s}", .{message}),
            };
        }
        if (fields.get("ext")) |ext| {
            const items = ext.array.items;
            const expected_data = try hexBytes(a, items[1].string);
            if (got != .table) return self.mismatch("$", "expected an extension", .{});
            const type_id = got.table.getLiteral("type");
            const payload = got.table.getLiteral("data");
            const ok = type_id == .integer and type_id.integer == items[0].integer and payload == .string and std.mem.eql(u8, payload.string.bytes(), expected_data);
            return if (ok) null else self.mismatch("$", "expected extension {d} {s}", .{ items[0].integer, items[1].string });
        }
        inline for (.{ "bool", "number", "string", "array", "map" }) |key| {
            if (fields.get(key)) |value| return self.compareJson(got, value, "$");
        }
        return self.mismatch("$", "unknown oracle entry", .{});
    }
};

fn compareNumber(self: *Suite, got: runtime.Value, expected: f64, exact: ?i64, path: []const u8) !?[]const u8 {
    switch (got) {
        .integer => |integer| {
            if (exact) |value| return if (integer == value) null else self.mismatch(path, "expected {d}, got {d}", .{ value, integer });
            return if (@as(f64, @floatFromInt(integer)) == expected) null else self.mismatch(path, "expected {d}, got {d}", .{ expected, integer });
        },
        .number => |number| return if (number == expected) null else self.mismatch(path, "expected {d}, got {d}", .{ expected, number }),
        else => return self.mismatch(path, "expected a number", .{}),
    }
}

const Tag = struct { type: []const u8, value: []const u8 };

fn taggedScalar(value: Json) ?Tag {
    if (value != .object or value.object.count() != 2) return null;
    const tag = value.object.get("type") orelse return null;
    const text = value.object.get("value") orelse return null;
    if (tag != .string or text != .string) return null;
    return .{ .type = tag.string, .value = text.string };
}

fn parseTaggedFloat(text: []const u8) ?f64 {
    const body = if (text.len != 0 and (text[0] == '+' or text[0] == '-')) text[1..] else text;
    const negative = text.len != 0 and text[0] == '-';
    if (std.mem.eql(u8, body, "nan")) return std.math.nan(f64);
    if (std.mem.eql(u8, body, "inf")) return if (negative) -std.math.inf(f64) else std.math.inf(f64);
    return std.fmt.parseFloat(f64, text) catch null;
}

fn entryCount(table: *runtime.Table) usize {
    var count: usize = 0;
    for (table.array.items()) |value| {
        if (value != .nil) count += 1;
    }
    for (table.entries()) |entry| {
        if (entry.value != .nil) count += 1;
    }
    return count;
}

fn hexBytes(allocator: std.mem.Allocator, text: []const u8) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    var index: usize = 0;
    while (index + 1 < text.len) {
        if (text[index] == '-') {
            index += 1;
            continue;
        }
        try out.append(allocator, try std.fmt.parseInt(u8, text[index..][0..2], 16));
        index += 2;
    }
    return out.toOwnedSlice(allocator);
}

fn bytesHex(allocator: std.mem.Allocator, bytes: []const u8) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    for (bytes, 0..) |byte, index| {
        if (index != 0) try out.append(allocator, '-');
        try out.print(allocator, "{x:0>2}", .{byte});
    }
    return out.toOwnedSlice(allocator);
}

fn matchesAny(allocator: std.mem.Allocator, bytes: []const u8, encodings: []const Json) bool {
    for (encodings) |hex| {
        const expected = hexBytes(allocator, hex.string) catch continue;
        if (std.mem.eql(u8, bytes, expected)) return true;
    }
    return false;
}

fn lessThanString(_: void, lhs: []const u8, rhs: []const u8) bool {
    return std.mem.lessThan(u8, lhs, rhs);
}

fn lessThanMutable(_: void, lhs: []u8, rhs: []u8) bool {
    return std.mem.lessThan(u8, lhs, rhs);
}
