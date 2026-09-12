const std = @import("std");
const runtime = @import("../runtime.zig");
const internal = @import("internal.zig");

const State = runtime.State;
const Value = runtime.Value;
const MemoryFile = runtime.MemoryFile;
const FilesystemCapability = runtime.FilesystemCapability;
const ClockCapability = runtime.ClockCapability;
const ProcessCapability = runtime.ProcessCapability;
const binary_chunk_signature = runtime.binary_chunk_signature;
const binary_chunk_payload_magic = runtime.binary_chunk_payload_magic;
const executeSource = runtime.executeSource;
const executeSourceWithOptions = runtime.executeSourceWithOptions;
const valuesEqual = runtime.valuesEqual;
const appendBinaryChunkHeader = runtime.appendBinaryChunkHeader;
const dumpClosureBinary = runtime.dumpClosureBinary;

test "small table growth preserves existing entries on allocation failure" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, tableGrowthAllocationScenario, .{});
}

fn tableGrowthAllocationScenario(allocator: std.mem.Allocator) !void {
    var table = try runtime.Table.init(allocator, 0, 1);
    defer table.deinit(allocator);
    const keys = [_][]const u8{ "one", "two", "three", "four", "five", "six", "seven", "eight", "nine" };
    for (keys, 0..) |key, index| {
        table.set(allocator, .{ .string = key }, .{ .integer = @intCast(index) }) catch |err| {
            for (keys[0..index], 0..) |previous, expected| {
                try std.testing.expectEqual(@as(i64, @intCast(expected)), table.get(.{ .string = previous }).integer);
            }
            try std.testing.expect(table.get(.{ .string = key }) == .nil);
            return err;
        };
    }
    for (keys, 0..) |key, expected| {
        try std.testing.expectEqual(@as(i64, @intCast(expected)), table.get(.{ .string = key }).integer);
    }
}

test "executes basic print and arithmetic" {
    var result = try executeSource(std.testing.allocator,
        \\print(1 + 2)
        \\print(9 // 4)
        \\print(2 ^ 8)
    );
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(?u8, 0), result.exit_code);
    try std.testing.expect(std.mem.eql(u8, result.stdout, "3\n2\n256.0\n"));
}

test "executes if while and repeat jumps" {
    var result = try executeSource(std.testing.allocator,
        \\local x = 0
        \\while x < 3 do
        \\  x = x + 1
        \\end
        \\if x == 3 then print("while") else print("bad") end
        \\repeat
        \\  x = x - 1
        \\until x == 0
        \\print(x)
    );
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(?u8, 0), result.exit_code);
    try std.testing.expect(std.mem.eql(u8, result.stdout, "while\n0\n"));
}

test "reports stack overflow for unbounded Lua recursion" {
    var result = try executeSource(std.testing.allocator,
        \\function f()
        \\  return 1 + f()
        \\end
        \\f()
    );
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(?u8, 1), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "stack overflow") != null);
}

test "instruction accounting agrees across nested call dispatch paths" {
    const source =
        \\local function f(n)
        \\  if n == 0 then return 3 end
        \\  return 1 + f(n - 1)
        \\end
        \\local sum = 0
        \\for i = 1, 20 do
        \\  local t = { i, a = i }
        \\  sum = sum + f(i) + t[1] - t.a + math.floor(math.sqrt(i * i)) - i
        \\end
        \\assert(sum == 270)
    ;
    var fast = try State.init(std.testing.allocator);
    defer fast.deinit();
    try fast.executeSourceChunk(source);
    var metered = try State.initWithOptions(std.testing.allocator, .{ .max_instructions = 100_000 });
    defer metered.deinit();
    try metered.executeSourceChunk(source);
    try std.testing.expectEqual(metered.instruction_count, fast.instruction_count);
}

test "hand-built bytecode can fall through or jump past its final instruction" {
    const compile = @import("../compile.zig");
    const Instruction = compile.bytecode.Instruction;
    const cases = [_][]const Instruction{
        &.{},
        &.{.{ .load_nil = 0 }},
        &.{ .{ .load_nil = 0 }, .{ .close = 0 } },
        &.{ .{ .load_nil = 0 }, .{ .jmp = 1 }, .{ .ret = .{ .first = 0, .count = 0 } } },
    };
    for (cases) |instructions| {
        var state = try State.initWithOptions(std.testing.allocator, .{ .stdlib = .none });
        defer state.deinit();
        var proto = compile.proto.Proto.init(std.testing.allocator);
        defer proto.deinit();
        proto.max_registers = 1;
        for (instructions) |instruction| _ = try proto.emit(instruction, 0);
        try state.execute(&proto);
    }
}

test "automatic GC clears weak values after full collection across VM dispatch paths" {
    // The closure suite waits for this collection without a bound. Keep the
    // allocation pattern, but fail promptly if a dispatch path retains x[1].
    const source =
        \\local A, B = 0, {g = 10}
        \\local function f(x)
        \\  local a = {}
        \\  for i = 1, 1000 do
        \\    local y = 0
        \\    a[i] = function() B.g = B.g + 1; y = y + x; return y + A end
        \\  end
        \\  local dummy = function() return a[A] end
        \\  collectgarbage()
        \\  A = 1; assert(dummy() == a[1]); A = 0
        \\  assert(a[1]() == x and a[3]() == x)
        \\  collectgarbage()
        \\  return a
        \\end
        \\local a = f(10)
        \\local x = {[1] = {}}
        \\setmetatable(x, {__mode = 'kv'})
        \\while x[1] do
        \\  local a = A..A..A..A
        \\  A = A + 1
        \\  if A == 100000 then error('weak value retained') end
        \\end
        \\assert(a[1]() == 20 + A and a[2]() == 10 + A)
    ;
    for ([_]runtime.GcMode{ .generational, .incremental }) |mode| {
        for ([_]?u64{ null, 10_000_000 }) |limit| {
            var state = try State.initWithOptions(std.testing.allocator, .{ .max_instructions = limit });
            defer state.deinit();
            _ = state.setGcMode(mode);
            try state.executeSourceChunk(source);
        }
    }
}

test "condition temporaries preserve Lua truthiness across VM dispatch paths" {
    const source =
        \\for _, value in ipairs{false, true, 0, 0.0, '', {}, function() end} do
        \\  local expected = value ~= false
        \\  local branch = false
        \\  if value then branch = true end
        \\  assert(branch == expected)
        \\  branch = false
        \\  while value do branch = true; break end
        \\  assert(branch == expected)
        \\  local count = 0
        \\  repeat count = count + 1 until value or count == 2
        \\  assert(count == (expected and 1 or 2))
        \\end
        \\if nil then error('nil is false') end
    ;
    for ([_]?u64{ null, 100_000 }) |limit| {
        var state = try State.initWithOptions(std.testing.allocator, .{ .max_instructions = limit });
        defer state.deinit();
        try state.executeSourceChunk(source);
    }
}

test "full collection preserves the generational submode" {
    var state = try State.initWithOptions(std.testing.allocator, .{ .stdlib = .none });
    defer state.deinit();
    // With only live objects, the reclamation heuristic would stay major.
    try state.collectGarbage();
    try std.testing.expect(!try state.stepGc(1));
    try std.testing.expectEqual(.minor, state.gc_cycle);

    state.gc_major_pending = true;
    try state.collectGarbage();
    try std.testing.expect(!try state.stepGc(1));
    try std.testing.expectEqual(.major, state.gc_cycle);
}

test "read-only named vararg calls do not allocate tables" {
    var state = try State.init(std.testing.allocator);
    defer state.deinit();
    try state.executeSourceChunk(
        \\collectgarbage('stop')
        \\function read(key, ...v) return v[key], v.n, ... end
        \\read(1, 10, 20)
    );
    const tables = state.table_allocations.items.len;
    try state.executeSourceChunk(
        \\for i = 1, 100 do
        \\  local value, n, first, second = read(1.0, 10, 20)
        \\  assert(value == 10 and n == 2 and first == 10 and second == 20)
        \\end
    );
    try std.testing.expectEqual(tables, state.table_allocations.items.len);
}

test "major collection returns to minor mode based on growth rather than the whole heap" {
    var state = try State.initWithOptions(std.testing.allocator, .{ .stdlib = .none });
    defer state.deinit();
    const root = try state.newTableWithHints(100, 0);
    const handle = try state.rootValue(root);
    defer state.unrootValue(handle);
    for (0..100) |i| try state.setTableValue(root, .{ .integer = @intCast(i + 1) }, try state.newTableWithHints(0, 0));
    try state.collectGarbage();
    // Reclaim all growth, but much less than half the long-lived heap.
    for (0..10) |_| _ = try state.newTableWithHints(0, 0);
    state.gc_major_pending = true;
    var steps: usize = 0;
    while (!try state.stepGc(1)) : (steps += 1) try std.testing.expect(steps < 1000);
    try std.testing.expect(!try state.stepGc(1));
    try std.testing.expectEqual(.minor, state.gc_cycle);
    try std.testing.expectEqual(@as(usize, 102), state.table_allocations.items.len);
}

test "reports calls to non-functions" {
    var result = try executeSource(std.testing.allocator,
        \\local value = 1
        \\value()
    );
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(?u8, 1), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "attempt to call a number value") != null);
}

test "debug errors dump stack state before unwinding" {
    var result = try executeSourceWithOptions(std.testing.allocator,
        \\local x = 42
        \\error("boom", 0)
    , .{ .state = .{ .debug_errors = true } });
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(?u8, 1), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "[zlua debug] unhandled runtime exception") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "local x r") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "stack (") != null);
}

test "unhandled Lua errors render without zlua prefix" {
    var result = try executeSource(std.testing.allocator,
        \\error("boom", 0)
    );
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(?u8, 1), result.exit_code);
    try std.testing.expect(std.mem.eql(u8, result.stderr, "boom\n"));
}

test "safe stdlib omits host-facing libraries" {
    var result = try executeSourceWithOptions(std.testing.allocator,
        \\print(type(io), type(os), type(package), type(debug))
    , .{ .state = .{ .stdlib = .safe } });
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(?u8, 0), result.exit_code);
    try std.testing.expect(std.mem.eql(u8, result.stdout, "nil\tnil\tnil\tnil\n"));
}

test "granular stdlib loads selected libraries only" {
    var result = try executeSourceWithOptions(std.testing.allocator,
        \\print(type(string), type(table), string.upper("ok"))
    , .{ .state = .{ .stdlib = .{ .libraries = .{ .base = true, .string = true } } } });
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(?u8, 0), result.exit_code);
    try std.testing.expect(std.mem.eql(u8, result.stdout, "table\tnil\tOK\n"));
}

test "full stdlib can use memory-backed filesystem and fixed clock" {
    const files = [_]MemoryFile{
        .{ .path = "input.txt", .contents = "alpha\nbeta" },
        .{ .path = "loaded.lua", .contents = "return 'loaded'" },
    };
    var result = try executeSourceWithOptions(std.testing.allocator,
        \\local file = assert(io.open("input.txt", "r"))
        \\print(file:read("*l"))
        \\print(file:read("*a"))
        \\print(assert(loadfile("loaded.lua"))())
        \\print(os.date("!%Y", 0))
    , .{ .state = .{ .filesystem = .{ .memory = &files }, .clock = .{ .fixed = 0 } } });
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(?u8, 0), result.exit_code);
    try std.testing.expect(std.mem.eql(u8, result.stdout, "alpha\nbeta\nloaded\n1970\n"));
}

test "disabled capabilities block filesystem and process access" {
    var result = try executeSourceWithOptions(std.testing.allocator,
        \\local file, err = io.open("missing.lua", "r")
        \\print(file == nil, type(err))
        \\print(pcall(os.execute, "true"))
    , .{ .state = .{ .filesystem = .disabled, .process = .disabled, .clock = .{ .fixed = 0 } } });
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(?u8, 0), result.exit_code);
    try std.testing.expect(std.mem.eql(u8, result.stdout, "true\tstring\nfalse\tprocess access disabled\n"));
}

test "runtime internal re-exports match facade" {
    comptime {
        if (internal.State != State) @compileError("internal State diverged from facade");
        if (internal.StateOptions != runtime.StateOptions) @compileError("internal StateOptions diverged from facade");
        if (internal.Value != Value) @compileError("internal Value diverged from facade");
        if (internal.Table != runtime.Table) @compileError("internal Table diverged from facade");
        if (internal.Thread != runtime.Thread) @compileError("internal Thread diverged from facade");
        if (internal.GcMode != runtime.GcMode) @compileError("internal GcMode diverged from facade");
    }

    const memory_file: MemoryFile = internal.MemoryFile{ .path = "init.lua", .contents = "return 1" };
    _ = memory_file;
    const filesystem: FilesystemCapability = internal.FilesystemCapability.disabled;
    _ = filesystem;
    const clock: ClockCapability = internal.ClockCapability.system;
    _ = clock;
    const process_capability: ProcessCapability = internal.ProcessCapability.disabled;
    _ = process_capability;

    try std.testing.expect(internal.valuesEqual(Value.nil, .nil));
    var out = std.ArrayList(u8).empty;
    defer out.deinit(std.testing.allocator);
    try internal.appendValue(std.testing.allocator, &out, .{ .integer = 42 });
    try std.testing.expect(std.mem.eql(u8, out.items, "42"));

    out.clearRetainingCapacity();
    try internal.appendBinaryChunkHeader(std.testing.allocator, &out);
    try std.testing.expect(std.mem.startsWith(u8, out.items, binary_chunk_signature));
}

test "GC stress preserves live locals during execution" {
    var result = try executeSourceWithOptions(std.testing.allocator,
        \\local keep = { answer = 42 }
        \\local i = 1
        \\while i <= 50 do
        \\  local transient = { i, { i + 1 } }
        \\  collectgarbage("collect")
        \\  i = i + 1
        \\end
        \\collectgarbage("collect")
        \\print(keep.answer)
    , .{ .collect_after_instruction = true });
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(?u8, 0), result.exit_code);
    try std.testing.expect(std.mem.eql(u8, result.stdout, "42\n"));
}

test "GC stress during table mutation closure allocation and string interning" {
    var result = try executeSourceWithOptions(std.testing.allocator,
        \\local roots = { entries = {} }
        \\local marker = "literal-anchor"
        \\for i = 1, 30 do
        \\  local key = assert(load("return 'interned-" .. i .. "'"))()
        \\  roots.entries[key] = { value = i }
        \\  roots.entries[i] = function(delta)
        \\    return key, roots.entries[key].value + delta, marker
        \\  end
        \\  collectgarbage("collect")
        \\  local got_key, total, got_marker = roots.entries[i](2)
        \\  assert(got_key == key and total == i + 2 and got_marker == marker)
        \\end
        \\collectgarbage("collect")
        \\print(roots.entries["interned-30"].value, roots.entries[30](12))
    , .{ .collect_after_instruction = true });
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(?u8, 0), result.exit_code);
    try std.testing.expect(std.mem.eql(u8, result.stdout, "30\tinterned-30\t42\tliteral-anchor\n"));
}

test "GC stress during binary dumping and bytecode loading" {
    var result = try executeSourceWithOptions(std.testing.allocator,
        \\answer = 37
        \\local dumped = string.dump(assert(load("return function(delta) return answer + delta end"))())
        \\collectgarbage("collect")
        \\local loaded = assert(load(dumped, "dumped", "b", _ENV))
        \\collectgarbage("collect")
        \\answer = 40
        \\print(loaded(2))
    , .{ .collect_after_instruction = true });
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(?u8, 0), result.exit_code);
    try std.testing.expect(std.mem.eql(u8, result.stdout, "42\n"));
}

test "collectgarbage runs table finalizers before sweeping" {
    var result = try executeSource(std.testing.allocator,
        \\do
        \\  local dead = setmetatable({ name = "dead" }, {
        \\    __gc = function(self)
        \\      local info = debug.getinfo(1)
        \\      assert(info.namewhat == "metamethod" and info.name == "__gc")
        \\      print("gc-final", self.name)
        \\    end,
        \\  })
        \\  dead = nil
        \\end
        \\collectgarbage("collect")
        \\collectgarbage("collect")
        \\print("done")
    );
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(?u8, 0), result.exit_code);
    try std.testing.expect(std.mem.eql(u8, result.stdout, "gc-final\tdead\ndone\n"));
}

test "string.dump reloads Lua closures" {
    var result = try executeSource(std.testing.allocator,
        \\local f = assert(load(string.dump(function() return 42 end)))
        \\local ok, message = pcall(string.dump, print)
        \\print(f(), ok, message ~= nil)
    );
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(?u8, 0), result.exit_code);
    try std.testing.expect(std.mem.eql(u8, result.stdout, "42\tfalse\ttrue\n"));
}

test "zlua binary chunks are portable across states" {
    var dump = std.ArrayList(u8).empty;
    defer dump.deinit(std.testing.allocator);

    {
        var source_state = try State.init(std.testing.allocator);
        defer source_state.deinit();
        const loaded = try source_state.loadSourceAsClosure("return 42, 'ok'");
        try dumpClosureBinary(std.testing.allocator, &dump, loaded.closure, false);
    }

    var target_state = try State.init(std.testing.allocator);
    defer target_state.deinit();
    const loaded = try target_state.loadBinaryDump(dump.items, .nil);
    const values = try target_state.callLoadedClosure(loaded.closure, &.{});
    defer target_state.allocator.free(values);

    try std.testing.expectEqual(@as(usize, 2), values.len);
    try std.testing.expect(valuesEqual(values[0], .{ .integer = 42 }));
    try std.testing.expect(valuesEqual(values[1], .{ .string = "ok" }));
}

test "zlua binary chunks preserve nested protos and upvalue descriptors" {
    var result = try executeSource(std.testing.allocator,
        \\local source = [[
        \\  return function(seed)
        \\    local total = seed
        \\    local function add(value)
        \\      total = total + value
        \\      return total
        \\    end
        \\    return add
        \\  end
        \\]]
        \\local factory = assert(load(string.dump(assert(load(source)))))()
        \\local add = factory(10)
        \\print(add(2), add(3))
        \\local debug = require "debug"
        \\local closure = factory(1)
        \\print(debug.getupvalue(closure, 1))
    );
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(?u8, 0), result.exit_code);
    try std.testing.expect(std.mem.eql(u8, result.stdout, "12\t15\ntotal\t1\n"));
}

test "zlua binary chunks honor supplied load environment" {
    var dump = std.ArrayList(u8).empty;
    defer dump.deinit(std.testing.allocator);

    {
        var source_state = try State.init(std.testing.allocator);
        defer source_state.deinit();
        const loaded = try source_state.loadSourceAsClosure("return answer + ...");
        try dumpClosureBinary(std.testing.allocator, &dump, loaded.closure, false);
    }

    var target_state = try State.init(std.testing.allocator);
    defer target_state.deinit();
    const environment = try target_state.newTableWithHints(0, 1);
    try environment.table.set(target_state.allocator, .{ .string = try target_state.intern("answer") }, .{ .integer = 40 });

    const loaded = try target_state.loadBinaryDump(dump.items, environment);
    const values = try target_state.callLoadedClosure(loaded.closure, &.{.{ .integer = 2 }});
    defer target_state.allocator.free(values);

    try std.testing.expectEqual(@as(usize, 1), values.len);
    try std.testing.expect(valuesEqual(values[0], .{ .integer = 42 }));
}

test "zlua binary chunks preserve stripped debug state" {
    var result = try executeSource(std.testing.allocator,
        \\local debug = require "debug"
        \\local secret = 12
        \\local f = assert(load(string.dump(function() return secret end, true)))
        \\print(debug.getupvalue(f, 1))
        \\print(debug.getinfo(f).currentline)
    );
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(?u8, 0), result.exit_code);
    try std.testing.expect(std.mem.eql(u8, result.stdout, "(no name)\tnil\n-1\n"));
}

test "PUC binary chunks are rejected explicitly" {
    var chunk = std.ArrayList(u8).empty;
    defer chunk.deinit(std.testing.allocator);
    try appendBinaryChunkHeader(std.testing.allocator, &chunk);
    try chunk.appendNTimes(std.testing.allocator, 0, binary_chunk_payload_magic.len);

    var state = try State.init(std.testing.allocator);
    defer state.deinit();
    try std.testing.expectError(error.RuntimeError, state.loadBinaryDump(chunk.items, .nil));
    const detail = try state.errorDetailAlloc(std.testing.allocator, error.RuntimeError);
    defer std.testing.allocator.free(detail);
    try std.testing.expect(std.mem.indexOf(u8, detail, "unsupported PUC Lua binary chunk") != null);
}

test "official closure upvalue edge cases" {
    var result = try executeSource(std.testing.allocator,
        \\local a = {}
        \\local i = 1
        \\repeat
        \\  local x = i
        \\  a[i] = function () i = x + 1; return x end
        \\until i > 10 or a[i]() ~= x
        \\assert(i == 11 and a[1]() == 1 and a[3]() == 3 and i == 4)
        \\
        \\a = {}
        \\for j = 1, 3 do
        \\  if j % 3 == 2 then
        \\    local t
        \\    goto make
        \\    ::assign:: a[j] = t; goto done
        \\    ::make::
        \\    local y = 2
        \\    t = function (x) local old = y; y = x; return old end
        \\    goto assign
        \\    ::done::
        \\  end
        \\end
        \\assert(a[2](20) == 2 and a[2]() == 20)
        \\
        \\local debug = require "debug"
        \\local foo1, foo2
        \\do
        \\  local x, y = 3, 5
        \\  foo1 = function () return x + y end
        \\  foo2 = function () return y + x end
        \\end
        \\assert(debug.upvalueid(foo1, 1) == debug.upvalueid(foo2, 2))
        \\debug.upvaluejoin(foo1, 2, foo2, 2)
        \\assert(foo1() == 6 and foo2() == 8)
        \\print("ok")
    );
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(?u8, 0), result.exit_code);
    try std.testing.expect(std.mem.eql(u8, result.stdout, "ok\n"));
}

test "last Lua error value is a GC root" {
    var state = try State.init(std.testing.allocator);
    defer state.deinit();

    const object = try state.newTableWithHints(0, 1);
    try object.table.set(state.allocator, .{ .string = try state.intern("tag") }, .{ .string = try state.intern("live") });
    try std.testing.expectEqual(error.RuntimeError, state.failValue(object));

    try state.collectGarbage();

    const error_value = state.currentErrorValue();
    try std.testing.expect(error_value == .table);
    try std.testing.expect(error_value.table == object.table);
    try std.testing.expect(state.isTrackedTable(object.table));
    try std.testing.expect(valuesEqual(error_value.table.get(.{ .string = "tag" }), .{ .string = "live" }));
}

test "collects unreachable runtime allocations" {
    var state = try State.init(std.testing.allocator);
    defer state.deinit();

    const before = state.allocationStats();
    _ = try state.intern("transient-gc-string");
    _ = try state.newTableWithHints(4, 4);

    try state.collectGarbage();

    const after = state.allocationStats();
    try std.testing.expect(after.strings >= before.strings);
    try std.testing.expectEqual(before.tables, after.tables);
    try std.testing.expectEqual(before.closures, after.closures);
    try std.testing.expectEqual(before.upvalues, after.upvalues);
    try std.testing.expectEqual(before.threads, after.threads);
}

test "keeps global table graph alive during collection" {
    var state = try State.init(std.testing.allocator);
    defer state.deinit();

    const root = try state.newTableWithHints(0, 1);
    const child = try state.newTableWithHints(0, 1);
    const key = try state.intern("child");
    try child.table.set(state.allocator, .{ .string = try state.intern("answer") }, .{ .integer = 42 });
    try root.table.set(state.allocator, .{ .string = key }, child);
    try state.putGlobal("gc_root", root);

    try state.collectGarbage();

    const kept_root = state.getGlobal("gc_root");
    try std.testing.expect(kept_root == .table);
    const kept_child = kept_root.table.get(.{ .string = key });
    try std.testing.expect(kept_child == .table);
    try std.testing.expect(valuesEqual(kept_child.table.get(.{ .string = "answer" }), .{ .integer = 42 }));
}

test "weak value tables clear unreachable values" {
    var state = try State.init(std.testing.allocator);
    defer state.deinit();

    const weak = try state.newTableWithHints(0, 1);
    const metatable = try state.newTableWithHints(0, 1);
    try metatable.table.set(state.allocator, .{ .string = try state.intern("__mode") }, .{ .string = try state.intern("v") });
    state.setTableMetatableRaw(weak.table, metatable.table);
    try state.putGlobal("weak_values", weak);

    const dead = try state.newTableWithHints(0, 0);
    try weak.table.set(state.allocator, .{ .string = try state.intern("item") }, dead);

    try state.collectGarbage();

    try std.testing.expect(weak.table.get(.{ .string = "item" }) == .nil);
}

test "weak key tables clear unreachable keys" {
    var state = try State.init(std.testing.allocator);
    defer state.deinit();

    const weak = try state.newTableWithHints(0, 1);
    const metatable = try state.newTableWithHints(0, 1);
    try metatable.table.set(state.allocator, .{ .string = try state.intern("__mode") }, .{ .string = try state.intern("k") });
    state.setTableMetatableRaw(weak.table, metatable.table);
    try state.putGlobal("weak_keys", weak);

    const dead_key = try state.newTableWithHints(0, 0);
    try weak.table.set(state.allocator, dead_key, .{ .integer = 1 });

    try state.collectGarbage();

    try std.testing.expectEqual(@as(usize, 0), weak.table.entries.items.len);
}

test "ephemeron table marks value when key is reachable" {
    var state = try State.init(std.testing.allocator);
    defer state.deinit();

    const ephemeron = try state.newTableWithHints(0, 1);
    const metatable = try state.newTableWithHints(0, 1);
    try metatable.table.set(state.allocator, .{ .string = try state.intern("__mode") }, .{ .string = try state.intern("k") });
    state.setTableMetatableRaw(ephemeron.table, metatable.table);
    try state.putGlobal("ephemeron", ephemeron);

    const key = try state.newTableWithHints(0, 0);
    const value = try state.newTableWithHints(0, 1);
    try value.table.set(state.allocator, .{ .string = try state.intern("answer") }, .{ .integer = 42 });
    try ephemeron.table.set(state.allocator, key, value);
    try state.putGlobal("live_key", key);

    try state.collectGarbage();

    const kept_value = ephemeron.table.get(key);
    try std.testing.expect(kept_value == .table);
    try std.testing.expect(valuesEqual(kept_value.table.get(.{ .string = "answer" }), .{ .integer = 42 }));
}

test "collector traverses deep mixed graphs without native recursion" {
    var state = try State.initWithOptions(std.testing.allocator, .{ .stdlib = .none });
    defer state.deinit();
    const root = try state.newTableWithHints(1, 0);
    const handle = try state.rootValue(root);
    var tail = root;
    for (0..50000) |_| {
        const child = try state.newTableWithHints(1, 0);
        try state.setTableValue(tail, .{ .integer = 1 }, child);
        tail = child;
    }
    try state.setTableValue(tail, .{ .integer = 1 }, root);
    try state.collectGarbage();
    try std.testing.expectEqual(@as(usize, 50002), state.table_allocations.items.len);
    state.unrootValue(handle);
    try state.collectGarbage();
    try std.testing.expectEqual(@as(usize, 1), state.table_allocations.items.len);
}

test "incremental phases preserve mutations and allocations while sweeping" {
    var state = try State.initWithOptions(std.testing.allocator, .{ .stdlib = .none });
    defer state.deinit();
    state.gc_mode = .incremental;
    state.gc_params.stepsize = 8;
    state.gc_params.stepmul = 100;
    const root = try state.newTableWithHints(0, 2);
    const handle = try state.rootValue(root);
    defer state.unrootValue(handle);
    for (0..100) |_| _ = try state.newTableWithHints(0, 0);
    try std.testing.expect(!try state.stepGc(0));
    try std.testing.expectEqual(.propagate, state.gc_phase);
    while (state.gc_phase == .propagate) _ = try state.stepGc(1);
    const child = try state.newTableWithHints(0, 1);
    try state.setTableValue(root, .{ .string = "child" }, child);
    _ = try state.stepGc(1);
    try std.testing.expectEqual(.sweep_threads, state.gc_phase);
    const during_sweep = try state.newTableWithHints(0, 1);
    try state.setTableValue(during_sweep, .{ .string = "message" }, .{ .string = try state.intern("allocated during sweeping") });
    try state.setTableValue(child, .{ .string = "nested" }, during_sweep);
    var steps: usize = 0;
    while (!try state.stepGc(1)) : (steps += 1) try std.testing.expect(steps < 1000);
    try std.testing.expect(state.isTrackedTable(child.table));
    try std.testing.expect(state.isTrackedTable(during_sweep.table));
    try std.testing.expectEqualStrings("allocated during sweeping", during_sweep.table.get(.{ .string = "message" }).string);
}

test "minor work scales with young and remembered objects and promotes survivors" {
    var state = try State.initWithOptions(std.testing.allocator, .{ .stdlib = .none });
    defer state.deinit();
    const root = try state.newTableWithHints(10000, 0);
    for (0..10000) |i| {
        const child = try state.newTableWithHints(0, 1);
        try state.setTableValue(root, .{ .integer = @intCast(i + 1) }, child);
    }
    const handle = try state.rootValue(root);
    defer state.unrootValue(handle);
    state.normalizeGcBaseline();
    const leaf = root.table.get(.{ .integer = 5000 });
    const young = try state.newTableWithHints(0, 1);
    try state.setTableValue(leaf, .{ .string = "child" }, young);
    try std.testing.expect(!try state.stepGc(1));
    try std.testing.expectEqual(.minor, state.gc_cycle);
    try std.testing.expect(state.gc_work_done < 100);
    try std.testing.expectEqual(.survivor, young.table.gc.age);
    try std.testing.expect(!try state.stepGc(1));
    try std.testing.expectEqual(.old, young.table.gc.age);
    const second = try state.newTableWithHints(0, 0);
    try state.setTableValue(young, .{ .string = "next" }, second);
    try std.testing.expect(!try state.stepGc(1));
    try std.testing.expect(state.isTrackedTable(second.table));
    try state.setTableValue(young, .{ .string = "next" }, .nil);
    try std.testing.expect(!try state.stepGc(1));
    try std.testing.expect(!state.isTrackedTable(second.table));
    try std.testing.expectEqual(@as(usize, 10003), state.table_allocations.items.len);
}

test "automatic finalization runs a bounded userdata batch" {
    var state = try State.initWithOptions(std.testing.allocator, .{ .stdlib = .none });
    defer state.deinit();
    state.gc_mode = .incremental;
    var calls: usize = 0;
    const finalizer = struct {
        fn run(ptr: *anyopaque, _: ?*const anyopaque) void {
            const count: *usize = @ptrCast(@alignCast(ptr));
            count.* += 1;
        }
    }.run;
    for (0..5) |_| _ = try state.newUserdata(&calls, 1, "count", finalizer, null, null);
    while (state.gc_phase != .finalize) _ = try state.stepGc(1);
    try std.testing.expectEqual(@as(usize, 0), calls);
    try std.testing.expect(!try state.stepGc(1));
    try std.testing.expectEqual(@as(usize, 1), calls);
    try state.collectGarbage();
    try std.testing.expectEqual(@as(usize, 5), calls);
}

test "remembered old metatables keep young metadata through promotion" {
    var state = try State.initWithOptions(std.testing.allocator, .{ .stdlib = .none });
    defer state.deinit();
    const parent = try state.newTableWithHints(0, 0);
    const handle = try state.rootValue(parent);
    defer state.unrootValue(handle);
    state.normalizeGcBaseline();
    const metatable = try state.newTableWithHints(0, 0);
    state.setTableMetatableRaw(parent.table, metatable.table);
    for (0..3) |_| {
        try std.testing.expect(!try state.stepGc(1));
        try std.testing.expect(state.isTrackedTable(metatable.table));
    }
    try std.testing.expectEqual(.old, metatable.table.gc.age);
}

test "suspended unwind errors remain roots across minor and major cycles" {
    var state = try State.initWithOptions(std.testing.allocator, .{ .stdlib = .none });
    defer state.deinit();
    const thread = try state.newCoroutineThread(.nil);
    const handle = try state.rootValue(.{ .thread = thread });
    defer state.unrootValue(handle);
    state.normalizeGcBaseline();
    const error_value = try state.newTableWithHints(0, 1);
    try state.setTableRaw(error_value.table, .{ .string = "detail" }, .{ .string = try state.intern("suspended error") });
    thread.pending_unwind_error = error_value;
    state.threadBarrier(thread, error_value);
    for (0..3) |_| {
        _ = try state.stepGc(1);
        try std.testing.expect(state.isTrackedTable(error_value.table));
    }
    try state.collectGarbage();
    try std.testing.expect(state.isTrackedTable(error_value.table));
    try std.testing.expectEqualStrings("suspended error", error_value.table.get(.{ .string = "detail" }).string);
    thread.pending_unwind_error = null;
    try state.collectGarbage();
    try std.testing.expect(!state.isTrackedTable(error_value.table));
}

test "remembered old threads retain young diagnostic strings through promotion" {
    var state = try State.initWithOptions(std.testing.allocator, .{ .stdlib = .none });
    defer state.deinit();
    const thread = try state.newCoroutineThread(.nil);
    const handle = try state.rootValue(.{ .thread = thread });
    defer state.unrootValue(handle);
    state.normalizeGcBaseline();
    const diagnostic = try state.intern("young traceback belonging to a suspended old thread");
    thread.error_traceback = diagnostic;
    state.threadBarrier(thread, .{ .string = diagnostic });
    for (0..3) |_| {
        _ = try state.stepGc(1);
        try std.testing.expect(state.findStringAllocation(diagnostic) != null);
    }
    try state.collectGarbage();
    try std.testing.expectEqualStrings("young traceback belonging to a suspended old thread", thread.error_traceback.?);
}

test "changing weak modes after propagation retraces newly strong edges" {
    var state = try State.initWithOptions(std.testing.allocator, .{ .stdlib = .none });
    defer state.deinit();
    state.gc_mode = .incremental;
    const metatable = try state.newTableWithHints(0, 1);
    try state.setTableRaw(metatable.table, .{ .string = "__mode" }, .{ .string = "v" });
    const weak = try state.newTableWithHints(0, 1);
    state.setTableMetatableRaw(weak.table, metatable.table);
    const handle = try state.rootValue(weak);
    defer state.unrootValue(handle);
    const child = try state.newTableWithHints(0, 0);
    try state.setTableRaw(weak.table, .{ .string = "item" }, child);
    while (state.gc_phase != .atomic) _ = try state.stepGc(1);
    try state.setTableRaw(metatable.table, .{ .string = "__mode" }, .{ .string = "" });
    while (!try state.stepGc(1)) {}
    try std.testing.expect(state.isTrackedTable(child.table));
    try std.testing.expect(weak.table.get(.{ .string = "item" }) == .table);
    try state.setTableRaw(metatable.table, .{ .string = "__mode" }, .{ .string = "v" });
    try state.collectGarbage();
    try std.testing.expect(weak.table.get(.{ .string = "item" }) == .nil);
}
