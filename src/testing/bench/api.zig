//! Embedding API operations, timed in batches.
const std = @import("std");
const zlua = @import("../../root.zig");
const results = @import("results.zig");
const Options = @import("options.zig").Options;
const allocation = @import("allocation.zig");
const Timestamp = std.Io.Timestamp;

/// Operations timed by each sample.
pub const batch = 1000;

const Case = enum {
    call_lua,
    call_lua_string,
    call_host,
    callback_typed,
    callback_untyped,
    callback_closure,
    callback_string,
    userdata_method,
    builtin_call,
    string_method,
    table_get,
    table_set,
    table_get_index,
    table_get_string,
    new_table,
    new_userdata,
    decode_struct,
    table_from_struct,

    fn description(case: Case) []const u8 {
        return switch (case) {
            .call_lua => "Function.call of a Lua function taking and returning integers",
            .call_lua_string => "Function.call of a Lua function returning a String handle",
            .call_host => "Function.call of a typed host callback",
            .callback_typed => "Lua calling a typed host callback with two integers",
            .callback_untyped => "Lua calling an untyped host callback with two integers",
            .callback_closure => "Lua calling a host closure that reads a bound value",
            .callback_string => "Lua calling a typed host callback with a string",
            .userdata_method => "Lua calling a bound userdata method",
            .builtin_call => "Lua calling math.max",
            .string_method => "Lua calling a string method through the string metatable",
            .table_get => "Table.get of an integer by string key",
            .table_set => "Table.set of an integer by string key",
            .table_get_index => "Table.get of an integer by integer key",
            .table_get_string => "Table.get of a String handle",
            .new_table => "State.newTable and deinit",
            .new_userdata => "State.newUserdata and deinit",
            .decode_struct => "decode of a three-field struct from a table",
            .table_from_struct => "State.newTableFrom of a three-field struct",
        };
    }

    /// A chunk returning `function(n)`, for cases whose operations run in a Lua loop.
    fn loopSource(case: Case) ?[]const u8 {
        return switch (case) {
            .callback_typed => "local f = host_add return function(n) local s for i = 1, n do s = f(i, 1) end end",
            .callback_untyped => "local f = untyped_add return function(n) local s for i = 1, n do s = f(i, 1) end end",
            .callback_closure => "local f = bound_add return function(n) local s for i = 1, n do s = f(i) end end",
            .callback_string => "local f, text = host_len, text return function(n) local s for i = 1, n do s = f(text) end end",
            .userdata_method => "local counter = counter return function(n) local s for i = 1, n do s = counter:add(1) end end",
            .builtin_call => "local f = math.max return function(n) local s for i = 1, n do s = f(i, 1) end end",
            .string_method => "local text = text return function(n) local s for i = 1, n do s = text:byte(3) end end",
            else => null,
        };
    }
};

const Counter = struct {
    n: i64 = 0,

    pub fn add(self: *Counter, amount: i64) i64 {
        self.n +%= amount;
        return self.n;
    }
};

const Config = struct { name: []const u8, port: i64, debug: bool };

fn hostAdd(a: i64, b: i64) i64 {
    return a +% b;
}

fn hostLen(text: []const u8) i64 {
    return @intCast(text.len);
}

fn untypedAdd(ctx: *zlua.Context) !void {
    try ctx.returnValues(.{try ctx.arg(0, i64) +% try ctx.arg(1, i64)});
}

fn boundAdd(ctx: *zlua.Context, a: i64) !i64 {
    return a +% try ctx.upvalue(0, i64);
}

const setup_source =
    \\function add(a, b) return a + b end
    \\function greet() return "hello world" end
    \\config = { name = "srv", port = 8080, debug = true }
    \\fields = { x = 1, name = "n" }
    \\array = {}
    \\for i = 1, 1000 do array[i] = i end
    \\text = "abcdefghijklmnopqrstuvwxyz"
;

const Env = struct {
    lua: *zlua.State,
    add: zlua.Function,
    greet: zlua.Function,
    host_add: zlua.Function,
    loop: ?zlua.Function,
    fields: zlua.Table,
    array: zlua.Table,
    config: zlua.Value,
    arena: std.heap.ArenaAllocator,
    diagnostic: zlua.Diagnostic,

    fn init(allocator: std.mem.Allocator, case: Case) !Env {
        const lua = try zlua.State.init(allocator, .{});
        errdefer lua.deinit();
        try lua.doString(setup_source, .{});
        const host_add = try lua.newTypedFunction("host_add", hostAdd);
        try lua.setGlobal("host_add", host_add);
        try lua.setGlobal("host_len", hostLen);
        var untyped_add = try lua.newFunction("untyped_add", untypedAdd);
        defer untyped_add.deinit();
        try lua.setGlobal("untyped_add", untyped_add);
        var bound_add = try lua.newClosure("bound_add", boundAdd, .{@as(i64, 7)});
        defer bound_add.deinit();
        try lua.setGlobal("bound_add", bound_add);
        var counter = try lua.newUserdata(Counter, .{}, .{});
        defer counter.deinit();
        try lua.setGlobal("counter", counter);
        var loop: ?zlua.Function = null;
        if (case.loopSource()) |source| {
            var chunk = try lua.loadString(source, .{});
            defer chunk.deinit();
            loop = try chunk.call(.{}, zlua.Function);
        }
        return .{
            .lua = lua,
            .add = try lua.getGlobal("add", zlua.Function),
            .greet = try lua.getGlobal("greet", zlua.Function),
            .host_add = host_add,
            .loop = loop,
            .fields = try lua.getGlobal("fields", zlua.Table),
            .array = try lua.getGlobal("array", zlua.Table),
            .config = try lua.getGlobal("config", zlua.Value),
            .arena = .init(allocator),
            .diagnostic = .{ .gpa = allocator },
        };
    }

    fn deinit(self: *Env) void {
        self.diagnostic.deinit();
        self.arena.deinit();
        self.config.deinit();
        self.array.deinit();
        self.fields.deinit();
        if (self.loop) |*loop| loop.deinit();
        self.host_add.deinit();
        self.greet.deinit();
        self.add.deinit();
        self.lua.deinit();
    }

    fn run(self: *Env, case: Case) !void {
        const lua = self.lua;
        var sum: i64 = 0;
        switch (case) {
            .call_lua => for (0..batch) |i| {
                sum +%= try self.add.call(.{ @as(i64, @intCast(i)), 1 }, i64);
            },
            .call_lua_string => for (0..batch) |_| {
                var text = try self.greet.call(.{}, zlua.String);
                defer text.deinit();
                sum +%= @intCast((try text.bytes()).len);
            },
            .call_host => for (0..batch) |i| {
                sum +%= try self.host_add.call(.{ @as(i64, @intCast(i)), 1 }, i64);
            },
            .callback_typed, .callback_untyped, .callback_closure, .callback_string, .userdata_method, .builtin_call, .string_method => {
                try self.loop.?.call(.{@as(i64, batch)}, void);
            },
            .table_get => for (0..batch) |_| {
                sum +%= try self.fields.get("x", i64);
            },
            .table_set => for (0..batch) |i| {
                try self.fields.set("x", @as(i64, @intCast(i)));
            },
            .table_get_index => for (1..batch + 1) |i| {
                sum +%= try self.array.get(@as(i64, @intCast(i)), i64);
            },
            .table_get_string => for (0..batch) |_| {
                var text = try self.fields.get("name", zlua.String);
                defer text.deinit();
                sum +%= @intCast((try text.bytes()).len);
            },
            .new_table => for (0..batch) |_| {
                var table = try lua.newTable(.{});
                table.deinit();
            },
            .new_userdata => for (0..batch) |_| {
                var userdata = try lua.newUserdata(Counter, .{}, .{});
                userdata.deinit();
            },
            .decode_struct => for (0..batch) |_| {
                const config = try zlua.decode(Config, self.config, .{ .allocator = self.arena.allocator(), .diagnostic = &self.diagnostic });
                sum +%= config.port;
                _ = self.arena.reset(.retain_capacity);
            },
            .table_from_struct => for (0..batch) |i| {
                var table = try lua.newTableFrom(.{ .name = "srv", .port = @as(i64, @intCast(i)), .debug = true });
                table.deinit();
            },
        }
        std.mem.doNotOptimizeAway(sum);
    }
};

pub fn collect(allocator: std.mem.Allocator, io: std.Io, options: Options, suite: *results.Suite) !void {
    const iterations = options.iterations orelse 1000;
    const warmup = options.warmup orelse 100;
    for (std.enums.values(Case)) |case| {
        const name = @tagName(case);
        if (!options.matches("api", "native", name)) continue;
        if (options.list) {
            try suite.addCase("api", "native", name, case.description());
            continue;
        }
        var env = try Env.init(allocator, case);
        defer env.deinit();
        const samples = try allocator.alloc(results.Metric, iterations);
        defer allocator.free(samples);
        for (0..warmup + iterations) |i| {
            const start = Timestamp.now(io, .awake);
            try env.run(case);
            const elapsed = allocation.elapsedSince(io, start);
            if (i >= warmup) samples[i - warmup] = .{ .elapsed_ns = elapsed };
        }
        try suite.add(.{
            .group = "api",
            .case = name,
            .engine = "native",
            .operation = "batch",
            .build_mode = @tagName(@import("builtin").mode),
            .scope = std.fmt.comptimePrint("{d} operations", .{batch}),
            .iterations = iterations,
            .warmup = warmup,
            .samples = samples,
        });
    }
}

test "every embedding API benchmark case runs" {
    for (std.enums.values(Case)) |case| {
        var env = try Env.init(std.testing.allocator, case);
        defer env.deinit();
        try env.run(case);
    }
}
