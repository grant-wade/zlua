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
const bytecode = @import("../compile.zig").bytecode;
const proto_mod = @import("../compile.zig").proto;

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
    , .{ .stress_collect = true });
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
    , .{ .stress_collect = true });
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
    , .{ .stress_collect = true });
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

const Opcode = std.meta.Tag(bytecode.Instruction);

const verified_chunk_program =
    \\local log = {}
    \\local function add(...)
    \\  for i = 1, select("#", ...) do log[#log + 1] = tostring((select(i, ...))) end
    \\end
    \\local function varargs(first, ...)
    \\  local a, b = ...
    \\  local packed = { ... }
    \\  return first, a, b, #packed, ...
    \\end
    \\add(varargs(1, 2, 3, 4))
    \\local function named(...args) return args.n, args[1] end
    \\add(named("x", "y"))
    \\local function counter(start)
    \\  local total = start
    \\  return function(step)
    \\    total = total + step + #log * 0
    \\    return total
    \\  end
    \\end
    \\local tick = counter(10)
    \\add(tick(1), tick(2))
    \\local sum = 0
    \\for i = 10, 1, -3 do sum = sum + i end
    \\for k, v in ipairs({ 5, 6, 7 }) do sum = sum + k * v end
    \\for word in string.gmatch("a b c", "%a+") do add(word) end
    \\add(sum)
    \\local closed = {}
    \\do
    \\  local resource <close> = setmetatable({}, { __close = function() closed[#closed + 1] = "closed" end })
    \\  add(resource ~= nil)
    \\end
    \\add(closed[1])
    \\local fns = {}
    \\for i = 1, 3 do fns[i] = function() return i end end
    \\add(fns[1]() + fns[3]())
    \\local n = 0
    \\::top::
    \\n = n + 1
    \\if n < 3 then goto top end
    \\add(n)
    \\local object = { value = 4 }
    \\function object:scaled(factor) return self.value * factor end
    \\add(object:scaled(3))
    \\local function three() return 1, 2, 3 end
    \\local list = { 0, three() }
    \\local keyed = { [1 + 1] = "two", name = "n", three() }
    \\add(#list, keyed[2], keyed.name, #keyed)
    \\local x, y, flag, maybe = 7, 2, true, nil
    \\add(x + y, x - y, x * y, x / y, x // y, x % y, x ^ y, -x)
    \\add(x & y, x | y, x ~ y, ~x, x << y, x >> y)
    \\add(x == y, x < y, x <= y, not x, #"abc", "a" .. x .. y, x .. y, [[long]])
    \\if x > y and y >= 1 then add("cmp") end
    \\if maybe then add("never") end
    \\add(maybe or "default", flag and y)
    \\while x > 5 do x = x - 1 end
    \\repeat y = y + 1 until y >= 4
    \\add(x, y)
    \\do global answer = 41 end
    \\answer = answer + 1
    \\add(answer)
    \\local t = {}
    \\t[1] = "a"; t.k = "v"; t[x] = y
    \\add(t[1], t.k, t[x])
    \\local function tail(depth) if depth == 0 then return "tail" end return tail(depth - 1) end
    \\add(tail(3))
    \\return table.concat(log, ",")
;

fn collectOpcodes(proto: *const proto_mod.Proto, seen: *std.EnumSet(Opcode)) void {
    for (proto.instructions.items) |instruction| seen.insert(std.meta.activeTag(instruction));
    for (proto.children.items) |child| collectOpcodes(child, seen);
}

fn runLoadedString(state: *State, closure: *runtime.Closure) ![]const u8 {
    const values = try state.callLoadedClosure(closure, &.{});
    defer state.allocator.free(values);
    try std.testing.expectEqual(@as(usize, 1), values.len);
    return std.testing.allocator.dupe(u8, values[0].string);
}

test "zlua binary chunks verify and round-trip every compiled opcode family" {
    var source_state = try State.init(std.testing.allocator);
    defer source_state.deinit();
    const loaded = try source_state.loadSourceAsClosure(verified_chunk_program);

    var seen: std.EnumSet(Opcode) = .empty;
    collectOpcodes(loaded.closure.proto, &seen);
    const never_emitted = [_]Opcode{ .tfor_call, .get_global, .set_global };
    for (std.enums.values(Opcode)) |opcode| {
        const expected = std.mem.indexOfScalar(Opcode, &never_emitted, opcode) == null;
        if (expected != seen.contains(opcode)) std.debug.print("opcode coverage mismatch: {s}\n", .{@tagName(opcode)});
        try std.testing.expectEqual(expected, seen.contains(opcode));
    }

    const expected = try runLoadedString(&source_state, loaded.closure);
    defer std.testing.allocator.free(expected);

    for ([_]bool{ false, true }) |strip| {
        var dump = std.ArrayList(u8).empty;
        defer dump.deinit(std.testing.allocator);
        try dumpClosureBinary(std.testing.allocator, &dump, loaded.closure, strip);

        var target_state = try State.init(std.testing.allocator);
        defer target_state.deinit();
        const reloaded = try target_state.loadBinaryDump(dump.items, .{ .table = target_state.global_table.? });
        const actual = try runLoadedString(&target_state, reloaded.closure);
        defer std.testing.allocator.free(actual);
        try std.testing.expectEqualStrings(expected, actual);
    }
}

const ChunkMutation = enum {
    register,
    constant_index,
    name_constant,
    jump_past_end,
    jump_before_start,
    branch_past_end,
    child_index,
    upvalue_index,
    captured_register,
    captured_upvalue,
    call_arguments,
    numeric_for_base,
    generic_for_variables,
    return_range,
    vararg_range,
    set_list_range,
    concat_range,
    check_close_register,
    new_table_hint,
    param_count,
    named_vararg_register,
    local_register,
    error_site_pc,
    long_string,
    integer_lexeme,
};

const InstructionSite = struct {
    proto: *proto_mod.Proto,
    pc: usize,

    fn op(self: InstructionSite) *bytecode.Instruction {
        return &self.proto.instructions.items[self.pc];
    }

    fn registers(self: InstructionSite) u16 {
        return self.proto.max_registers;
    }
};

fn findSite(proto: *proto_mod.Proto, opcode: Opcode) ?InstructionSite {
    for (proto.instructions.items, 0..) |instruction, pc| {
        if (std.meta.activeTag(instruction) == opcode) return .{ .proto = proto, .pc = pc };
    }
    for (proto.children.items) |child| if (findSite(child, opcode)) |site| return site;
    return null;
}

fn findCapture(proto: *proto_mod.Proto, in_stack: bool) ?struct { parent: *proto_mod.Proto, upvalue: *proto_mod.UpvalueDesc } {
    for (proto.children.items) |child| {
        for (child.upvalues.items) |*upvalue| {
            if (upvalue.in_stack == in_stack) return .{ .parent = proto, .upvalue = upvalue };
        }
        if (findCapture(child, in_stack)) |capture| return capture;
    }
    return null;
}

fn findConstant(proto: *proto_mod.Proto, tag: std.meta.Tag(bytecode.Constant)) ?*bytecode.Constant {
    for (proto.constants.items) |*constant| if (constant.* == tag) return constant;
    return null;
}

fn findProto(proto: *proto_mod.Proto, comptime matches: fn (*const proto_mod.Proto) bool) ?*proto_mod.Proto {
    if (matches(proto)) return proto;
    for (proto.children.items) |child| if (findProto(child, matches)) |found| return found;
    return null;
}

fn hasNamedVararg(proto: *const proto_mod.Proto) bool {
    return proto.named_vararg;
}

fn applyChunkMutation(root: *proto_mod.Proto, mutation: ChunkMutation) !bool {
    switch (mutation) {
        .register => {
            const site = findSite(root, .move) orelse return false;
            site.op().move.dest = site.registers();
        },
        .constant_index => {
            const site = findSite(root, .load_const) orelse return false;
            site.op().load_const.constant = @intCast(site.proto.constants.items.len);
        },
        .name_constant => {
            const site = findSite(root, .get_field) orelse return false;
            try site.proto.constants.append(site.proto.allocator, .nil);
            site.op().get_field.name = @intCast(site.proto.constants.items.len - 1);
        },
        .jump_past_end => {
            const site = findSite(root, .jmp) orelse return false;
            site.op().jmp = @intCast(site.proto.instructions.items.len - site.pc);
        },
        .jump_before_start => {
            const site = findSite(root, .jmp) orelse return false;
            site.op().jmp = -@as(i32, @intCast(site.pc + 2));
        },
        .branch_past_end => {
            const site = findSite(root, .compare_branch) orelse return false;
            site.op().compare_branch.offset = @intCast(site.proto.instructions.items.len - site.pc);
        },
        .child_index => {
            const site = findSite(root, .closure) orelse return false;
            site.op().closure.proto = @intCast(site.proto.children.items.len);
        },
        .upvalue_index => {
            const site = findSite(root, .get_upvalue) orelse return false;
            site.op().get_upvalue.upvalue = @intCast(site.proto.upvalues.items.len);
        },
        .captured_register => {
            const capture = findCapture(root, true) orelse return false;
            capture.upvalue.index = capture.parent.max_registers;
        },
        .captured_upvalue => {
            const capture = findCapture(root, false) orelse return false;
            capture.upvalue.index = @intCast(capture.parent.upvalues.items.len);
        },
        .call_arguments => {
            const site = findSite(root, .call) orelse return false;
            site.op().call = .{ .base = site.registers() - 1, .arg_count = 1, .return_count = 0 };
        },
        .numeric_for_base => {
            const site = findSite(root, .for_loop) orelse return false;
            site.op().for_loop.base = site.registers() - 2;
        },
        .generic_for_variables => {
            const site = findSite(root, .tfor_prep) orelse return false;
            site.op().tfor_prep.variable_count = site.registers();
        },
        .return_range => {
            const site = findSite(root, .ret) orelse return false;
            site.op().ret = .{ .first = site.registers() - 1, .count = 2 };
        },
        .vararg_range => {
            const site = findSite(root, .vararg) orelse return false;
            site.op().vararg = .{ .dest = site.registers() - 1, .count = 2 };
        },
        .set_list_range => {
            const site = findSite(root, .set_list) orelse return false;
            site.op().set_list.first = site.registers() - 1;
            site.op().set_list.count = 2;
        },
        .concat_range => {
            const site = findSite(root, .concat_range) orelse return false;
            site.op().concat_range.first = site.registers() - 1;
        },
        .check_close_register => {
            const site = findSite(root, .check_close) orelse return false;
            site.op().check_close = site.registers();
        },
        .new_table_hint => {
            const site = findSite(root, .new_table) orelse return false;
            site.op().new_table.array_hint = std.math.maxInt(u32);
        },
        .param_count => root.param_count = root.max_registers + 1,
        .named_vararg_register => {
            const proto = findProto(root, hasNamedVararg) orelse return false;
            proto.max_registers = proto.param_count;
        },
        .local_register => {
            if (root.locals.items.len == 0) return false;
            root.locals.items[0].register = root.max_registers;
        },
        .error_site_pc => {
            if (root.error_sites.items.len == 0) return false;
            root.error_sites.items[0].pc = root.instructions.items.len;
        },
        .long_string => {
            const constant = findConstant(root, .string) orelse return false;
            constant.* = .{ .string = "[==" };
        },
        .integer_lexeme => {
            const constant = findConstant(root, .integer) orelse return false;
            constant.* = .{ .integer = "1x" };
        },
    }
    return true;
}

test "zlua binary chunks with out-of-range operands are rejected" {
    for (std.enums.values(ChunkMutation)) |mutation| {
        var state = try State.initWithOptions(std.testing.allocator, .{ .stdlib = .none });
        defer state.deinit();
        const loaded = try state.loadSourceAsClosure(verified_chunk_program);
        const root: *proto_mod.Proto = @constCast(loaded.closure.proto);
        if (!try applyChunkMutation(root, mutation)) {
            std.debug.print("mutation did not apply: {s}\n", .{@tagName(mutation)});
            return error.TestUnexpectedResult;
        }

        var dump = std.ArrayList(u8).empty;
        defer dump.deinit(std.testing.allocator);
        try dumpClosureBinary(std.testing.allocator, &dump, loaded.closure, false);
        _ = state.loadBinaryDump(dump.items, .nil) catch |err| {
            try std.testing.expectEqual(error.RuntimeError, err);
            const detail = try state.errorDetailAlloc(std.testing.allocator, err);
            defer std.testing.allocator.free(detail);
            try std.testing.expect(std.mem.indexOf(u8, detail, "bad binary chunk") != null);
            continue;
        };
        std.debug.print("mutation was accepted: {s}\n", .{@tagName(mutation)});
        return error.TestUnexpectedResult;
    }
}

test "truncated and oversized zlua binary chunks are rejected" {
    var state = try State.initWithOptions(std.testing.allocator, .{ .stdlib = .none });
    defer state.deinit();
    const loaded = try state.loadSourceAsClosure(
        \\local scale = 2
        \\return function(...)
        \\  local t = { ... }
        \\  for i = 1, #t do t[i] = t[i] * scale end
        \\  return t
        \\end
    );
    var dump = std.ArrayList(u8).empty;
    defer dump.deinit(std.testing.allocator);
    try dumpClosureBinary(std.testing.allocator, &dump, loaded.closure, false);

    for (0..dump.items.len) |len| {
        try std.testing.expectError(error.RuntimeError, state.loadBinaryDump(dump.items[0..len], .nil));
    }
    try dump.append(std.testing.allocator, 0);
    try std.testing.expectError(error.RuntimeError, state.loadBinaryDump(dump.items, .nil));
}

fn appendNestedProtoChunk(out: *std.ArrayList(u8), depth: usize) !void {
    const allocator = std.testing.allocator;
    try appendBinaryChunkHeader(allocator, out);
    try out.appendSlice(allocator, binary_chunk_payload_magic);
    try out.append(allocator, 0);
    for (0..depth) |level| {
        if (level == 0) try out.appendSlice(allocator, &.{ 1, 0, 0, 0, 0 }) else try out.append(allocator, 0);
        try out.append(allocator, 0);
        try out.appendNTimes(allocator, 0, 8 + 8 + 2 + 2 + 1 + 1 + 5 * 4);
        const child_count: u8 = if (level + 1 < depth) 1 else 0;
        try out.appendSlice(allocator, &.{ child_count, 0, 0, 0 });
    }
}

test "zlua binary chunks bound counts and nesting before allocating" {
    var state = try State.initWithOptions(std.testing.allocator, .{ .stdlib = .none });
    defer state.deinit();

    var huge_count = std.ArrayList(u8).empty;
    defer huge_count.deinit(std.testing.allocator);
    try appendBinaryChunkHeader(std.testing.allocator, &huge_count);
    try huge_count.appendSlice(std.testing.allocator, binary_chunk_payload_magic);
    try huge_count.appendSlice(std.testing.allocator, &.{ 0, 1, 0, 0, 0, 0, 0 });
    try huge_count.appendNTimes(std.testing.allocator, 0, 8 + 8 + 2 + 2 + 1 + 1);
    try huge_count.appendSlice(std.testing.allocator, &.{ 0xff, 0xff, 0xff, 0xff });
    try std.testing.expectError(error.RuntimeError, state.loadBinaryDump(huge_count.items, .nil));
    const detail = try state.errorDetailAlloc(std.testing.allocator, error.RuntimeError);
    defer std.testing.allocator.free(detail);
    try std.testing.expect(std.mem.indexOf(u8, detail, "truncated binary chunk") != null);

    var nested = std.ArrayList(u8).empty;
    defer nested.deinit(std.testing.allocator);
    try appendNestedProtoChunk(&nested, 200);
    _ = try state.loadBinaryDump(nested.items, .nil);
    nested.clearRetainingCapacity();
    try appendNestedProtoChunk(&nested, 201);
    try std.testing.expectError(error.RuntimeError, state.loadBinaryDump(nested.items, .nil));
}

test "load reports malformed binary chunks to Lua" {
    var result = try executeSource(std.testing.allocator,
        \\local dumped = string.dump(function(a) return a + 1 end)
        \\print(load(dumped:sub(1, -2), "cut", "b"))
        \\print(load(dumped .. "x", "extra", "b"))
        \\print(load(dumped, "whole", "b")(1))
    );
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(?u8, 0), result.exit_code);
    try std.testing.expectEqualStrings("nil\ttruncated binary chunk\nnil\tbad binary chunk\n2\n", result.stdout);
}

const corrupted_chunk_program =
    \\local function iter(limit, control)
    \\  if control < limit then return control + 1, control * 2 end
    \\end
    \\local acc = 0
    \\for i, v in iter, 5, 0 do acc = acc + i + v end
    \\for i = 1, 10, 3 do acc = acc + i end
    \\local function make(n)
    \\  local up = n
    \\  return function(x) up = up + x; return up end
    \\end
    \\local f = make(3)
    \\acc = acc + f(1) + f(2)
    \\local function spread(...) local a, b = ...; return b, a, ... end
    \\local x, y, z = spread(1, 2, 3)
    \\local list = { spread(4, 5) }
    \\list.k = #list
    \\list[1] = list.k
    \\do local c <close> = nil end
    \\local object = { v = 1 }
    \\function object:get(d) return self.v + d end
    \\acc = acc + object:get(1) + acc // 3 + acc % 7 + (acc << 1 >> 1) + (acc & 3 | 1 ~ 2)
    \\if acc > 3 and acc <= 1000 or acc == 7 then acc = acc + 1 end
    \\while acc > 100 do acc = acc - 50 end
    \\return acc, x, y, z, #list, "s" .. acc, not acc, -acc, 2 ^ 2, acc / 2
;

test "randomly corrupted zlua binary chunks load safely or fail" {
    var dump = std.ArrayList(u8).empty;
    defer dump.deinit(std.testing.allocator);
    {
        var state = try State.initWithOptions(std.testing.allocator, .{ .stdlib = .none });
        defer state.deinit();
        const loaded = try state.loadSourceAsClosure(corrupted_chunk_program);
        try dumpClosureBinary(std.testing.allocator, &dump, loaded.closure, false);
    }
    var header = std.ArrayList(u8).empty;
    defer header.deinit(std.testing.allocator);
    try appendBinaryChunkHeader(std.testing.allocator, &header);
    const payload_start = header.items.len + binary_chunk_payload_magic.len;

    const mutated = try std.testing.allocator.alloc(u8, dump.items.len);
    defer std.testing.allocator.free(mutated);
    var prng = std.Random.DefaultPrng.init(0x7a6c_7561_6263);
    const random = prng.random();
    var loaded_count: usize = 0;
    for (0..2000) |_| {
        @memcpy(mutated, dump.items);
        for (0..random.intRangeAtMost(usize, 1, 4)) |_| {
            const index = random.intRangeLessThan(usize, payload_start, mutated.len);
            if (random.boolean()) {
                mutated[index] ^= @as(u8, 1) << random.int(u3);
            } else {
                mutated[index] = random.int(u8);
            }
        }

        var state = try State.initWithOptions(std.testing.allocator, .{
            .stdlib = .none,
            .max_instructions = 10_000,
            .max_call_frames = 64,
            .max_stack_values = 4096,
        });
        defer state.deinit();
        const environment = try state.newTableWithHints(0, 0);
        const loaded = state.loadBinaryDump(mutated, environment) catch |err| {
            try std.testing.expectEqual(error.RuntimeError, err);
            continue;
        };
        loaded_count += 1;
        if (state.callLoadedClosure(loaded.closure, &.{})) |values| {
            state.allocator.free(values);
        } else |_| {}
    }
    try std.testing.expect(loaded_count > 0);
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

test "closing the state calls each queued userdata finalizer once" {
    var result = try executeSource(std.testing.allocator,
        \\ran = 0
        \\for i = 1, 4 do
        \\  debug.setmetatable(io.tmpfile(), { __gc = function() ran = ran + 1; print("gc", i) end })
        \\end
        \\collectgarbage("incremental")
        \\repeat collectgarbage("step") until ran > 0
    );
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(?u8, 0), result.exit_code);
    try std.testing.expectEqualStrings("gc\t4\ngc\t3\ngc\t2\ngc\t1\n", result.stdout);
}

test "precise collection inside a native keeps its multiple-result arguments" {
    var result = try executeSource(std.testing.allocator,
        \\local function args()
        \\  return ("collect "):rep(3) .. "collect", "%a+", collectgarbage
        \\end
        \\print(string.gsub(args()))
        \\print(pcall(string.gsub, args()))
    );
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(?u8, 0), result.exit_code);
    try std.testing.expectEqualStrings("0 0 0 0\t4\ntrue\t0 0 0 0\t4\n", result.stdout);
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

test "minor cycles trace old suspended threads changed without barriers" {
    var state = try State.init(std.testing.allocator);
    defer state.deinit();
    try state.executeSourceChunk(
        \\collectgarbage('generational')
        \\co = coroutine.create(function()
        \\  local held = 'old'
        \\  set = function(v) held = v end
        \\  coroutine.yield()
        \\  return held
        \\end)
        \\coroutine.resume(co)
    );
    try state.collectGarbage();
    const thread = state.getGlobal("co").thread;
    const isOld = struct {
        fn check(st: *State, object: anytype) bool {
            return object.gc.generation != st.gc_generation or object.gc.age == .old;
        }
    }.check;
    try std.testing.expect(isOld(&state, thread));
    try state.executeSourceChunk("set({ 'young' })");
    const slot = thread.open_upvalues.?.stack_index;
    const young = thread.stack.items[slot];
    try std.testing.expect(young == .table and !isOld(&state, young.table));
    for (0..3) |_| {
        _ = try state.stepGc(1);
        try std.testing.expectEqual(.minor, state.gc_cycle);
        try std.testing.expect(state.isTrackedTable(young.table));
        try std.testing.expectEqual(young, thread.stack.items[slot]);
    }
    try std.testing.expectEqual(.old, young.table.gc.age);
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

const value_mod = @import("value.zig");

test "formatNumber fits extreme floats" {
    var buffer: [value_mod.max_number_text_len]u8 = undefined;
    for ([_]f64{ -std.math.floatMax(f64), -std.math.floatTrueMin(f64), -2.2250738585072009e-308, -1.2345678901234567e-300 }) |number| {
        const text = value_mod.formatNumber(&buffer, .{ .number = number });
        try std.testing.expectEqual(number, try std.fmt.parseFloat(f64, text));
    }
}
