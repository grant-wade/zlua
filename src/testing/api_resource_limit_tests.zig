const std = @import("std");
const api = @import("../api.zig");
const Context = api.Context;
const Function = api.Function;
const MemoryFile = api.MemoryFile;
const State = api.State;
const Tuple = api.Tuple;

const memory_limit_error_message = "memory limit exceeded";

fn expectLastErrorContains(lua: *State, needle: []const u8) !void {
    const message = try lua.errorMessage();
    defer lua.allocator().free(message);
    try std.testing.expect(std.mem.indexOf(u8, message, needle) != null);
}

fn expectProtectedErrorContains(lua: *State, function: Function, needle: []const u8) !void {
    const result = try function.protectedCall(.{}, void);
    switch (result) {
        .ok => return error.TestExpectedLuaError,
        .lua_error => |err_ref| {
            var err = err_ref;
            defer err.deinit();
            const message = try err.message();
            defer lua.allocator().free(message);
            try std.testing.expect(std.mem.indexOf(u8, message, needle) != null);
        },
    }
}

test "api instruction limit returns a protected Lua error" {
    var lua = try State.init(std.testing.allocator, .{
        .limits = .{ .max_instructions = 50 },
    });
    defer lua.deinit();

    var chunk = try lua.loadString("while true do end", .{ .name = "=api-21.6-instruction-limit" });
    defer chunk.deinit();

    const result = try chunk.protectedCall(.{}, void);
    switch (result) {
        .ok => return error.TestExpectedLuaError,
        .lua_error => |err_ref| {
            var err = err_ref;
            defer err.deinit();
            const message = try err.message();
            defer lua.allocator().free(message);
            try std.testing.expect(std.mem.indexOf(u8, message, "instruction limit exceeded") != null);
        },
    }
}

test "api instruction budget can be queried and reset" {
    var lua = try State.init(std.testing.allocator, .{
        .stdlib = .none,
        .limits = .{ .max_instructions = 1_000 },
    });
    defer lua.deinit();

    try std.testing.expectEqual(@as(?u64, 1_000), lua.instructionBudget().limit);
    try std.testing.expectEqual(@as(u64, 0), lua.instructionBudget().used);
    try std.testing.expectEqual(@as(?u64, 1_000), lua.instructionBudget().remaining);

    var chunk = try lua.loadString("local x = 0; for i = 1, 5 do x = x + i end; return x", .{ .name = "=api-instruction-budget-query" });
    defer chunk.deinit();
    try std.testing.expectEqual(@as(i64, 15), try chunk.call(.{}, i64));

    const used = lua.instructionBudget().used;
    try std.testing.expect(used > 0);
    try std.testing.expectEqual(@as(?u64, 1_000 - used), lua.instructionBudget().remaining);

    lua.resetInstructionBudget();
    try std.testing.expectEqual(@as(u64, 0), lua.instructionBudget().used);
    try std.testing.expectEqual(@as(?u64, 1_000), lua.instructionBudget().remaining);
}

test "api instruction budget reset allows more execution after exhaustion" {
    var lua = try State.init(std.testing.allocator, .{
        .stdlib = .none,
        .limits = .{ .max_instructions = 20 },
    });
    defer lua.deinit();

    var loop = try lua.loadString("while true do end", .{ .name = "=api-instruction-budget-exhaust" });
    defer loop.deinit();
    const failed = try loop.protectedCall(.{}, void);
    switch (failed) {
        .ok => return error.TestExpectedLuaError,
        .lua_error => |err_ref| {
            var err = err_ref;
            defer err.deinit();
            const message = try err.message();
            defer lua.allocator().free(message);
            try std.testing.expect(std.mem.indexOf(u8, message, "instruction limit exceeded") != null);
        },
    }
    try std.testing.expectEqual(@as(u64, 20), lua.instructionBudget().used);
    try std.testing.expectEqual(@as(?u64, 0), lua.instructionBudget().remaining);

    lua.resetInstructionBudget();
    var simple = try lua.loadString("return 42", .{ .name = "=api-instruction-budget-reset" });
    defer simple.deinit();
    try std.testing.expectEqual(@as(i64, 42), try simple.call(.{}, i64));
}

test "api instruction query tracks states without an instruction limit" {
    var lua = try State.init(std.testing.allocator, .{ .stdlib = .none });
    defer lua.deinit();

    try std.testing.expectEqual(@as(?u64, null), lua.instructionBudget().limit);
    try std.testing.expectEqual(@as(?u64, null), lua.instructionBudget().remaining);

    var chunk = try lua.loadString("local x = 0; for i = 1, 3 do x = x + i end; return x", .{ .name = "=api-instruction-budget-unlimited" });
    defer chunk.deinit();
    try std.testing.expectEqual(@as(i64, 6), try chunk.call(.{}, i64));
    try std.testing.expect(lua.instructionBudget().used > 0);

    lua.resetInstructionBudget();
    try std.testing.expectEqual(@as(u64, 0), lua.instructionBudget().used);
}

test "api stack value limit returns a protected Lua error" {
    var lua = try State.init(std.testing.allocator, .{
        .limits = .{ .max_stack_values = 4 },
    });
    defer lua.deinit();

    var chunk = try lua.loadString("local a, b, c, d, e = 1, 2, 3, 4, 5; return a", .{ .name = "=api-21.6-stack-limit" });
    defer chunk.deinit();

    const result = try chunk.protectedCall(.{}, void);
    switch (result) {
        .ok => return error.TestExpectedLuaError,
        .lua_error => |err_ref| {
            var err = err_ref;
            defer err.deinit();
            const message = try err.message();
            defer lua.allocator().free(message);
            try std.testing.expect(std.mem.indexOf(u8, message, "stack overflow") != null);
        },
    }
}

test "api stack value limit catches recursive calls" {
    var lua = try State.init(std.testing.allocator, .{
        .limits = .{ .max_stack_values = 64 },
    });
    defer lua.deinit();

    var chunk = try lua.loadString(
        \\local function recurse(a, b, c, d, e, f, g, h)
        \\  local value = recurse(a, b, c, d, e, f, g, h)
        \\  return value
        \\end
        \\recurse(1, 2, 3, 4, 5, 6, 7, 8)
    , .{ .name = "=api-stack-limit-recursion" });
    defer chunk.deinit();

    try expectProtectedErrorContains(&lua, chunk, "stack overflow");
}

test "api call frame limit returns a protected Lua error" {
    var lua = try State.init(std.testing.allocator, .{
        .limits = .{ .max_call_frames = 8 },
    });
    defer lua.deinit();

    var chunk = try lua.loadString(
        \\local function recurse()
        \\  local value = recurse()
        \\  return value
        \\end
        \\recurse()
    , .{ .name = "=api-21.6-call-frame-limit" });
    defer chunk.deinit();

    const result = try chunk.protectedCall(.{}, void);
    switch (result) {
        .ok => return error.TestExpectedLuaError,
        .lua_error => |err_ref| {
            var err = err_ref;
            defer err.deinit();
            const message = try err.message();
            defer lua.allocator().free(message);
            try std.testing.expect(std.mem.indexOf(u8, message, "stack overflow") != null);
        },
    }
}

test "api stack value limit catches metamethod recursion" {
    var lua = try State.init(std.testing.allocator, .{
        .limits = .{ .max_stack_values = 64 },
    });
    defer lua.deinit();

    var chunk = try lua.loadString(
        \\local target
        \\target = setmetatable({}, {
        \\  __index = function(self, key)
        \\    local value = self[key]
        \\    return value
        \\  end,
        \\})
        \\return target.missing
    , .{ .name = "=api-stack-limit-metamethod-recursion" });
    defer chunk.deinit();

    try expectProtectedErrorContains(&lua, chunk, "stack overflow");
}

test "api call frame limit catches metamethod recursion" {
    var lua = try State.init(std.testing.allocator, .{
        .limits = .{ .max_call_frames = 8 },
    });
    defer lua.deinit();

    var chunk = try lua.loadString(
        \\local target
        \\target = setmetatable({}, {
        \\  __index = function(self, key)
        \\    local value = self[key]
        \\    return value
        \\  end,
        \\})
        \\return target.missing
    , .{ .name = "=api-call-frame-limit-metamethod-recursion" });
    defer chunk.deinit();

    try expectProtectedErrorContains(&lua, chunk, "stack overflow");
}

test "api stack value limit catches coroutine recursion" {
    var lua = try State.init(std.testing.allocator, .{
        .limits = .{ .max_stack_values = 64 },
    });
    defer lua.deinit();

    var chunk = try lua.loadString(
        \\local co = coroutine.create(function(a, b, c, d, e, f, g, h)
        \\  local function recurse(x1, x2, x3, x4, x5, x6, x7, x8)
        \\    local value = recurse(x1, x2, x3, x4, x5, x6, x7, x8)
        \\    return value
        \\  end
        \\  recurse(a, b, c, d, e, f, g, h)
        \\end)
        \\local ok, err = coroutine.resume(co, 1, 2, 3, 4, 5, 6, 7, 8)
        \\return ok, tostring(err), coroutine.status(co)
    , .{ .name = "=api-stack-limit-coroutine-recursion" });
    defer chunk.deinit();

    const Result = Tuple(&.{ bool, []const u8, []const u8 });
    var result = try chunk.call(.{}, Result);
    defer result.deinit();
    try std.testing.expectEqual(false, result.get(0));
    try std.testing.expectEqualStrings("dead", result.get(2));
}

test "api call frame limit catches coroutine recursion" {
    var lua = try State.init(std.testing.allocator, .{
        .limits = .{ .max_call_frames = 8 },
    });
    defer lua.deinit();

    var chunk = try lua.loadString(
        \\local co = coroutine.create(function()
        \\  local function recurse()
        \\    local value = recurse()
        \\    return value
        \\  end
        \\  recurse()
        \\end)
        \\local ok, err = coroutine.resume(co)
        \\return ok, tostring(err), coroutine.status(co)
    , .{ .name = "=api-call-frame-limit-coroutine-recursion" });
    defer chunk.deinit();

    const Result = Tuple(&.{ bool, []const u8, []const u8 });
    var result = try chunk.call(.{}, Result);
    defer result.deinit();
    try std.testing.expectEqual(false, result.get(0));
    try std.testing.expect(std.mem.indexOf(u8, result.get(1), "stack overflow") != null);
    try std.testing.expectEqualStrings("dead", result.get(2));
}

test "api stack value limit catches host callback reentry" {
    const Callbacks = struct {
        fn enter(ctx: *Context) !void {
            var callback = try ctx.arg(0, Function);
            defer callback.deinit();
            callback.call(.{}, void) catch |err| switch (err) {
                error.LuaError => {
                    const message = try ctx.state().errorMessage();
                    defer ctx.state().allocator().free(message);
                    return ctx.raise(message);
                },
                else => return err,
            };
            try ctx.returnValues(.{});
        }
    };

    var lua = try State.init(std.testing.allocator, .{
        .limits = .{ .max_stack_values = 96 },
    });
    defer lua.deinit();

    var enter = try lua.register("enter", Callbacks.enter);
    defer enter.deinit();
    try lua.setGlobal("enter", enter);

    var chunk = try lua.loadString(
        \\enter(function()
        \\  local function recurse(a, b, c, d, e, f, g, h)
        \\    local value = recurse(a, b, c, d, e, f, g, h)
        \\    return value
        \\  end
        \\  recurse(1, 2, 3, 4, 5, 6, 7, 8)
        \\end)
    , .{ .name = "=api-stack-limit-host-reentry" });
    defer chunk.deinit();

    try expectProtectedErrorContains(&lua, chunk, "stack overflow");
}

test "api call frame limit catches host callback reentry" {
    const Callbacks = struct {
        fn enter(ctx: *Context) !void {
            var callback = try ctx.arg(0, Function);
            defer callback.deinit();
            callback.call(.{}, void) catch |err| switch (err) {
                error.LuaError => {
                    const message = try ctx.state().errorMessage();
                    defer ctx.state().allocator().free(message);
                    return ctx.raise(message);
                },
                else => return err,
            };
            try ctx.returnValues(.{});
        }
    };

    var lua = try State.init(std.testing.allocator, .{
        .limits = .{ .max_call_frames = 8 },
    });
    defer lua.deinit();

    var enter = try lua.register("enter", Callbacks.enter);
    defer enter.deinit();
    try lua.setGlobal("enter", enter);

    var chunk = try lua.loadString(
        \\enter(function()
        \\  local function recurse()
        \\    local value = recurse()
        \\    return value
        \\  end
        \\  recurse()
        \\end)
    , .{ .name = "=api-call-frame-limit-host-reentry" });
    defer chunk.deinit();

    try expectProtectedErrorContains(&lua, chunk, "stack overflow");
}

test "api memory limit returns a protected Lua error" {
    var lua = try State.init(std.testing.allocator, .{
        .limits = .{ .max_memory = 96 * 1024 },
    });
    defer lua.deinit();

    var chunk = try lua.loadString(
        \\local t = {}
        \\for i = 1, 20000 do
        \\  t[i] = { i, i, i, i }
        \\end
        \\return t
    , .{ .name = "=api-21.6-memory-limit" });
    defer chunk.deinit();

    const result = try chunk.protectedCall(.{}, void);
    switch (result) {
        .ok => return error.TestExpectedLuaError,
        .lua_error => |err_ref| {
            var err = err_ref;
            defer err.deinit();
            const message = try err.message();
            defer lua.allocator().free(message);
            try std.testing.expect(std.mem.indexOf(u8, message, "memory limit exceeded") != null);
        },
    }
}

test "api memory limit applies while loading source" {
    var source = std.ArrayList(u8).empty;
    defer source.deinit(std.testing.allocator);
    try source.appendSlice(std.testing.allocator, "global x\n");
    for (0..20_000) |_| try source.appendSlice(std.testing.allocator, "x = 1\n");

    var lua = try State.init(std.testing.allocator, .{
        .stdlib = .none,
        .limits = .{ .max_memory = 64 * 1024 },
    });
    defer lua.deinit();

    try std.testing.expectError(error.LuaError, lua.loadString(source.items, .{ .name = "=api-memory-load-source-limit" }));
    try expectLastErrorContains(&lua, memory_limit_error_message);
}

test "api memory limit applies while loading bytecode" {
    var source = std.ArrayList(u8).empty;
    defer source.deinit(std.testing.allocator);
    try source.appendSlice(std.testing.allocator, "return function() return '");
    for (0..256 * 1024) |_| try source.append(std.testing.allocator, 'x');
    try source.appendSlice(std.testing.allocator, "' end");

    var source_state = try State.init(std.testing.allocator, .{ .stdlib = .none });
    defer source_state.deinit();

    var source_chunk = try source_state.loadString(source.items, .{ .name = "=api-memory-bytecode-source" });
    defer source_chunk.deinit();
    const dumped = try source_chunk.dumpBytecode(.{});
    defer source_state.allocator().free(dumped);

    var target_state = try State.init(std.testing.allocator, .{
        .stdlib = .none,
        .limits = .{ .max_memory = 64 * 1024 },
    });
    defer target_state.deinit();

    try std.testing.expectError(error.LuaError, target_state.loadBytecode(dumped, .{}));
    try expectLastErrorContains(&target_state, memory_limit_error_message);
}

test "api memory limit applies to captured output buffers" {
    var source = std.ArrayList(u8).empty;
    defer source.deinit(std.testing.allocator);
    try source.appendSlice(std.testing.allocator, "print('");
    for (0..128 * 1024) |_| try source.append(std.testing.allocator, 'x');
    try source.appendSlice(std.testing.allocator, "')");

    var lua = try State.init(std.testing.allocator, .{
        .stdlib = .base,
        .limits = .{ .max_memory = 400 * 1024 },
    });
    defer lua.deinit();

    var chunk = try lua.loadString(source.items, .{ .name = "=api-memory-output-limit" });
    defer chunk.deinit();

    const result = try chunk.protectedCall(.{}, void);
    switch (result) {
        .ok => return error.TestExpectedLuaError,
        .lua_error => |err_ref| {
            var err = err_ref;
            defer err.deinit();
            const message = try err.message();
            defer lua.allocator().free(message);
            try std.testing.expect(std.mem.indexOf(u8, message, memory_limit_error_message) != null);
        },
    }
}

test "api memory limit applies to stdlib temporaries" {
    var lua = try State.init(std.testing.allocator, .{
        .stdlib = .safe,
        .limits = .{ .max_memory = 160 * 1024 },
    });
    defer lua.deinit();

    var chunk = try lua.loadString("return string.rep('x', 256 * 1024)", .{ .name = "=api-memory-stdlib-temporary-limit" });
    defer chunk.deinit();

    try expectProtectedErrorContains(&lua, chunk, memory_limit_error_message);
}

test "api memory limit applies to memory filesystem read copies" {
    const BigFile = struct {
        const contents: [256 * 1024]u8 = @splat('x');
    };
    const files = [_]MemoryFile{
        .{ .path = "large.lua", .contents = BigFile.contents[0..] },
    };
    var lua = try State.init(std.testing.allocator, .{
        .stdlib = .safe,
        .capabilities = .{ .filesystem = .{ .memory = &files } },
        .limits = .{ .max_memory = 160 * 1024 },
    });
    defer lua.deinit();

    try std.testing.expectError(error.LuaError, lua.loadFile("large.lua", .{}));
    try expectLastErrorContains(&lua, memory_limit_error_message);
}

test "api memory limit recovery preserves nested protected calls" {
    var lua = try State.init(std.testing.allocator, .{
        .stdlib = .safe,
        .limits = .{ .max_memory = 160 * 1024 },
    });
    defer lua.deinit();

    var failing = try lua.loadString("return string.rep('x', 256 * 1024)", .{ .name = "=api-memory-recovery-fail" });
    defer failing.deinit();
    try expectProtectedErrorContains(&lua, failing, memory_limit_error_message);

    var recovered = try lua.loadString(
        \\local ok, value = pcall(function()
        \\  local inner_ok, inner_value = pcall(function()
        \\    return 21
        \\  end)
        \\  assert(inner_ok and inner_value == 21)
        \\  return inner_value * 2
        \\end)
        \\assert(ok and value == 42)
    , .{ .name = "=api-memory-recovery-nested-pcall" });
    defer recovered.deinit();
    try recovered.call(.{}, void);
}
