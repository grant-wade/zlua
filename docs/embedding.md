# Embedding zlua in Zig

The Zig API uses typed values, rooted handles, explicit host capabilities, and Zig errors rather than the Lua C stack model. The public entry point is `zlua.State`; `zlua.runtime` is an internal interface and may change.

## Create a State

```zig
const std = @import("std");
const zlua = @import("zlua");

pub fn main() !void {
    const allocator = std.heap.smp_allocator;

    var lua = try zlua.State.init(allocator, .{});
    defer lua.deinit();

    try lua.doString("assert(_VERSION == 'Lua 5.5')", .{ .name = "=main" });
}
```

The allocator must outlive the state. Destroy rooted handles before destroying their state.

By default, a state opens safe libraries with no ambient host access. Library presets are:

| Selection | Opens |
| --- | --- |
| `.none` | No libraries. `_G` still exists for host and script globals. |
| `.base` | Base globals only. |
| `.safe` | Base, table, string, math, utf8, coroutine, json, toml, msgpack, and csv. |
| `.full` | Safe plus io, os, debug, package, and fs. |
| `.custom` | Only libraries selected in a `LibrarySet`. |

```zig
var lua = try zlua.State.init(allocator, .{
    .stdlib = .{ .custom = .{
        .math = true,
        .json = true,
    } },
});
```

`State.openLibs` can open more libraries later.

## Capabilities

Library selection controls which Lua functions exist. Capabilities control whether those functions can use host services. Opening `.full` does not by itself grant filesystem, environment, clock, process, or I/O access.

| Capability | Modes |
| --- | --- |
| `io` | Optional `std.Io`, stdin bytes, and stdout/stderr writers. |
| `filesystem` | Disabled, read-only memory files, writable memory filesystem, host cwd, rooted host directory, or callbacks. |
| `environment` | Disabled, a host map, or callbacks. |
| `clock` | Disabled, fixed timestamp, system clock, or callbacks. |
| `process` | Disabled, std-backed execution, or callbacks. |

The CLI intentionally uses full libraries and host-oriented capabilities. Embedded states start sandboxed.

### Host Filesystem and Output

Std-backed filesystem, clock, and process modes use Zig 0.16's explicit `std.Io`. A rooted directory is safer than ambient cwd access when Lua should stay under one host directory:

```zig
var plugin_root = try std.Io.Dir.cwd().openDir(io, "plugins", .{});
defer plugin_root.close(io);

var output = std.Io.Writer.Allocating.init(allocator);
defer output.deinit();

var lua = try zlua.State.init(allocator, .{
    .stdlib = .full,
    .capabilities = .{
        .io = .{ .runtime = io, .stdout = &output.writer },
        .filesystem = .{ .host_dir = .{
            .dir = plugin_root,
            .read_only = true,
        } },
        .clock = .{ .fixed = 0 },
    },
});
defer lua.deinit();
```

The directory handle is borrowed and must outlive the state. Rooted directories reject absolute paths and `..` traversal.

### Memory Files

Read-only memory files support `loadfile`, `dofile`, and `require` without host filesystem access:

```zig
const files = [_]zlua.MemoryFile{
    .{
        .path = "plugins/mathx.lua",
        .contents = "return { double = function(x) return x * 2 end }",
    },
};

var lua = try zlua.State.init(allocator, .{
    .stdlib = .full,
    .capabilities = .{ .filesystem = .{ .memory = &files } },
});
defer lua.deinit();

try lua.setPackagePath("plugins/?.lua");
try lua.doString("assert(require('mathx').double(21) == 42)", .{});
```

Use `zlua.MemoryFilesystem` and `.memory_rw` for a mutable in-memory tree:

```zig
var filesystem = zlua.MemoryFilesystem.init(allocator);
defer filesystem.deinit();

var lua = try zlua.State.init(allocator, .{
    .stdlib = .full,
    .capabilities = .{ .filesystem = .{ .memory_rw = &filesystem } },
});
defer lua.deinit();

try lua.doString(
    \\local f = assert(io.open('report.txt', 'w'))
    \\assert(f:write('ok'))
    \\assert(f:close())
, .{});

const report = try filesystem.readFileAlloc(allocator, "report.txt");
defer allocator.free(report);
```

Memory paths are sandbox-relative. They reject absolute paths, `..`, backslashes, NUL bytes, and empty normalized paths. `MemoryFilesystem.Options` can set `max_path_len` and a content `max_bytes` quota.

`State.addMemoryFile` stores an owned file when the state is disabled/read-only, writes through to `.memory_rw`, and rejects host or custom filesystem modes.

### Custom Hosts

Freestanding and non-std hosts can provide callback-backed services:

| Type | Required callback | Optional behavior |
| --- | --- | --- |
| `CustomFilesystem` | `read_file_alloc` | Write, remove, rename, stat, directory listing, mkdir, recursive remove, and copy. |
| `CustomEnvironment` | `get` | Environment lookup. |
| `CustomClock` | `now` | Current Unix timestamp. |
| `CustomProcess` | `execute` | Returns an exit/signal status and code. |

Callbacks receive the host's opaque context. Allocating filesystem callbacks must use the allocator supplied by zlua. Missing optional operations return an unsupported error; they never fall back to ambient host access.

## Resource Limits

```zig
var lua = try zlua.State.init(allocator, .{
    .limits = .{
        .max_memory = 16 * 1024 * 1024,
        .max_stack_values = 4096,
        .max_call_frames = 128,
        .max_instructions = 1_000_000,
    },
});
```

`max_instructions` is cumulative across calls and coroutine resumes. Query it with `instructionBudget` and reset it with `resetInstructionBudget`.

`max_memory` bounds allocations made through the state, including parsing, compilation, runtime objects, API conversion, memory-file copies, and captured output. Initialization may return `error.OutOfMemory` if the limit cannot hold the requested libraries.

Limit failures become Lua errors during execution.

## Garbage Collection

Garbage collection runs automatically. The default generational mode focuses on short-lived objects and collects older objects less often. Most applications can leave the defaults alone.

If your application has a convenient place to do cleanup, you can use incremental mode and advance collection yourself:

```zig
var lua = try zlua.State.init(allocator, .{
    .gc = .{ .mode = .incremental, .running = false },
});
defer lua.deinit();

// Between requests or frames:
_ = try lua.stepGc(.{ .steps = 1 });
```

`stepGc` performs up to the requested number of steps; zero also means one step. It returns `.complete` when a full cycle finishes and `.pending` otherwise. A generational minor collection returns `.pending`. Steps limit the amount of work requested, not elapsed time: a large table or a finalizer can still take longer than expected.

Use `collect()` to finish a full collection, including pending finalizers. Both `collect` and `stepGc` work while automatic collection is stopped. `stopGc()` and `restartGc()` control automatic collection; `isGcRunning()` reports its state.

You can change modes with `setGcMode` and tune collection with `setGcParam`; both return the previous setting. Their query counterparts are `gcMode` and `gcParam`. See [GcParams](api/runtime/types.md#type-gcparams) for parameter names, units, and defaults. Invalid parameter values return `error.InvalidGcParam`.

## Load and Run Code

Use `doString` or `doFile` for one-shot execution:

```zig
try lua.doString("answer = 21 * 2", .{ .name = "=setup" });
try lua.doFile("plugin.lua", .{ .name = "@plugin.lua" });
```

Use `loadString` or `loadFile` for a reusable rooted `Function`:

```zig
var greet = try lua.loadString(
    "local name = ...; return 'hello, ' .. name",
    .{ .name = "=greet" },
);
defer greet.deinit();

const message = try greet.call(.{"host"}, []const u8);
```

A load can use a custom environment and restrict accepted input:

```zig
var env = try lua.createTable(.{ .hash_hint = 1 });
defer env.deinit();
try env.set("answer", 42);

var chunk = try lua.loadString("return answer", .{
    .environment = env,
    .mode = .source_only,
});
defer chunk.deinit();
```

Load modes are `.source_only`, `.binary_only`, and `.source_or_binary`.

### Binary Chunks

zlua bytecode is for zlua-to-zlua use only:

```zig
var chunk = try lua.loadString("return 40 + ...", .{ .name = "=cached" });
defer chunk.deinit();

const bytes = try chunk.dumpBytecode(.{ .strip_debug = true });
defer lua.allocator().free(bytes);

var cached = try lua.loadBytecode(bytes, .{});
defer cached.deinit();

const value = try cached.call(.{2}, i64);
```

The format is version-sensitive and is not compatible with PUC Lua `luac` chunks.

## Values and Handles

Common conversions are automatic:

| Zig | Lua |
| --- | --- |
| `null` | `nil` |
| `bool` | boolean |
| integer / float | integer / number |
| byte slice | string |
| non-byte array or slice | array table |
| struct | table keyed by field name |
| `Table`, `Function`, `Ref`, `Value`, `Userdata(T)` | existing Lua value |

Reading a value always names the target type:

```zig
try lua.setGlobal("answer", 42);
const answer = try lua.getGlobal("answer", i64);
```

Use `zlua.Tuple` for multiple returns:

```zig
var chunk = try lua.loadString("return true, 42, 'ok'", .{});
defer chunk.deinit();

const Result = zlua.Tuple(&.{ bool, i64, []const u8 });
var result = try chunk.call(.{}, Result);
defer result.deinit();
```

`Table`, `Function`, `Ref`, userdata, `ErrorRef`, and values/tuples containing them own registry roots. Call `deinit` when finished. Assigning a handle into Lua does not consume the host's root.

Dynamic `zlua.Value` can represent nil, booleans, numbers, strings, tables, functions, and userdata. Other runtime-only values appear as `.unsupported`.

## Tables and Modules

```zig
var config = try lua.createTable(.{ .hash_hint = 3 });
defer config.deinit();

try config.set("title", "demo");
try config.set("max_players", 8);
try lua.setGlobal("config", config);
```

`createModule` creates a table; `preloadModule` adds it to `package.loaded`, opening `package` if needed:

```zig
var host = try lua.createModule("host");
defer host.deinit();
try host.set("version", 1);
try lua.preloadModule("host", host);
```

`Table.rawGet(key, T)` and `Table.rawNext(previous_key)` bypass metamethods. Start traversal with `null` or `Value.nil`, deinitialize each returned `Entry`, and avoid structural changes during traversal.

`Table.getMetatable()` returns a rooted handle even when `__metatable` protects the table. `Table.identity()` returns a state-local token valid while the table is rooted, until reset.

## Host Callbacks

`register` exposes the `Context` API:

```zig
fn hostAdd(ctx: *zlua.Context) !void {
    const lhs = try ctx.arg(0, i64);
    const rhs = try ctx.arg(1, i64);
    try ctx.returnValues(.{ lhs + rhs, "ok" });
}

var host_add = try lua.register("host_add", hostAdd);
defer host_add.deinit();
try lua.setGlobal("host_add", host_add);
```

Registered callbacks are native functions: each registration has a distinct identity, `debug.getinfo` reports `what = "C"`, and there are no Lua upvalues or compiler-generated dispatcher globals. They cannot be dumped with `string.dump`; `Function.dumpBytecode` returns `error.TypeMismatch`. Callback names remain available in argument errors.

Use `ctx.optionalArg` for optional values and `ctx.raise` to raise a Lua error. Argument conversion failures include callback and argument context. Callbacks may also receive rooted `Table` or `Function` handles and must deinitialize them.

For simple functions, `registerTyped` converts parameters and returns automatically:

```zig
fn clamp(value: f64, min: f64, max: f64) f64 {
    return @min(@max(value, min), max);
}

var clamp_fn = try lua.registerTyped("clamp", clamp);
defer clamp_fn.deinit();
try lua.setGlobal("clamp", clamp_fn);
```

`Context.callNonYielding(function, args, R)` calls Lua on the callback’s coroutine using its current instruction budget. Yielding is forbidden. Lua errors propagate unchanged after cleanup, including `__close`; completed effects remain. `Context.threadIdentity()` returns a coroutine token valid only during the callback and invalidated by reset.

## Calling and Errors

```zig
try lua.doString("function add(a, b) return a + b end", .{});
var add = try lua.getGlobal("add", zlua.Function);
defer add.deinit();
const sum = try add.call(.{ 20, 22 }, i64);
```

`call` and convenience APIs return `error.LuaError` for Lua failures. Use `errorMessage` for an allocated message or `takeErrorValue` to take ownership of the rooted Lua error.

Use `protectedCall` when a Lua failure should be a value:

```zig
const result = try add.protectedCall(.{ "bad", 1 }, i64);
switch (result) {
    .ok => |number| _ = number,
    .lua_error => |error_ref| {
        var err = error_ref;
        defer err.deinit();
        const message = try err.message();
        defer lua.allocator().free(message);
    },
}
```

## Userdata

`newUserdata` stores a Zig value owned by Lua; `newUserdataPtr` wraps host-owned storage. Methods can be installed explicitly:

```zig
const Counter = struct {
    value: i64,

    fn inc(self: *@This(), amount: i64) i64 {
        self.value += amount;
        return self.value;
    }
};

var counter = try lua.newUserdata(Counter, .{ .value = 0 }, .{});
defer counter.deinit();
try counter.method("inc", Counter.inc);
try lua.setGlobal("counter", counter);
```

`newUserdataAuto` and `newUserdataPtrAuto` bind public functions whose first parameter is `*T` or `*const T`. Names beginning with `__` become metamethods; other methods go on `__index`. `registerUserdataInitializerWith` creates a typed Lua constructor that returns auto-bound userdata.

Lua-owned userdata may receive a finalizer through its options. Both forms support typed callback arguments such as `ctx.arg(0, *Counter)`.

Pass `.metatable = table` to `newUserdata` or `newUserdataPtr` to share a metatable from the same state. Install its methods before sharing it. Failed construction leaves finalizer responsibility with the host.

Userdata equality uses `__eq`; `rawequal` compares wrapper identity. `AnyUserdata.as(T)` checks the payload type and returns a new rooted handle.

Use `__pairs` for custom iteration. It returns an iterator, state, initial key, and optional closing value. `ipairs` uses `__index` to read integer keys from 1 until the first `nil`:

```zig
const Sequence = struct {
    values: [3]i64,

    pub fn __index(self: *const @This(), index: i64) ?i64 {
        if (index < 1 or index > self.values.len) return null;
        return self.values[@intCast(index - 1)];
    }
};

var sequence = try lua.newUserdataAuto(Sequence, .{ .values = .{ 10, 20, 30 } }, .{});
defer sequence.deinit();
try lua.setGlobal("sequence", sequence);
try lua.doString("for i, value in ipairs(sequence) do print(i, value) end", .{});
```

With `newUserdata`, register the method explicitly: `try sequence.metamethod("__index", Sequence.__index);`. Auto-binding also supports public `__pairs` methods with a pointer receiver. Lua `__pairs` functions can yield; `__index` calls from `ipairs` cannot. Zig fields are not enumerated automatically.

## Snapshots

Configure a State, capture an immutable Snapshot, and create independent workers:

```zig
var snapshot = try lua.snapshot(snapshot_allocator);
defer snapshot.deinit();

var worker = try snapshot.newState(worker_allocator);
defer worker.deinit();
try worker.doString("results = {42}", .{});
try worker.reset();
```

```text
configure State
    ↓
State.snapshot()
    ↓
immutable Snapshot
    ↓
Snapshot.newState() ─── Snapshot.newState() ─── ...
    ↓
independent worker
    ↓
work
    ↓
State.reset()
    ↓
same worker, restored to its own baseline
```

Capture copies the VM heap, including suspended Lua coroutines, shared references, module caches, I/O buffers, random state, and GC settings. Workers share immutable Snapshot bytecode while keeping mutable closures, caches, and other VM objects private. Capture establishes the source State's active baseline; `newState()` establishes that same baseline on the new worker. Reset restores options, host bindings, and instruction usage. Snapshots are reusable, can outlive the source State, and have no persistence format.

A fresh State has no baseline: `reset()` returns `error.NoSnapshot` until `snapshot()` succeeds. Each State resets only to its own baseline. Capturing the State again installs a newer baseline; older Snapshots remain usable with `newState()`. Reset needs no public Snapshot handle: the State retains its baseline even after all public handles are destroyed.

To switch templates, construct a replacement State before releasing the old one. If construction fails, the old State remains usable:

```zig
const replacement = try other_snapshot.newState(allocator);
old.deinit();
old = replacement;
```

Snapshot and reset require an idle VM. Active calls, collection, destruction, or recursive snapshot operations return `error.SnapshotBusy`. Untracked runtime objects return `error.SnapshotUnsupported`. Externally serialize every `State`, including reset and its rollback journal. Reset's atomic failure guarantee does not make a state concurrently usable.

Independently owned `Snapshot` handles can share one immutable backing and call `newState()` concurrently to create independent mutable VMs. Obtain each additional handle with `snapshot.retain()` and move it to its owner. Externally serialize each individual handle against mutation or `deinit`; `deinit()` consumes only that handle. An arbitrary bit copy is not an ownership retain. Keep a live owned handle throughout `newState()` or `retain()`. Each State resets only itself and retains its own baseline.

For example, with a thread-safe allocator `a` that outlives the joined workers:

```zig
const Worker = struct {
    fn run(owned: zlua.Snapshot, allocator: std.mem.Allocator) void {
        var snapshot = owned; // ownership moved from the spawning thread
        var vm = snapshot.newState(allocator) catch {
            snapshot.deinit();
            return;
        };
        snapshot.deinit(); // vm now retains its own baseline
        defer vm.deinit();
        vm.doString("result = 42", .{}) catch return;
        vm.reset() catch return;
    }
};
var snapshot = try lua.snapshot(a);
defer snapshot.deinit();
var threads: [4]std.Thread = undefined;
var started: usize = 0;
defer for (threads[0..started]) |thread| thread.join();
for (&threads) |*thread| {
    var owned = snapshot.retain();
    thread.* = std.Thread.spawn(.{}, Worker.run, .{ owned, a }) catch |err| {
        owned.deinit();
        return err;
    };
    started += 1; // the worker now owns the retained handle
}
```

The source state and original handle can also be destroyed before the workers finish.

### Reset and Lifetimes

Successful reset invalidates all earlier handles and borrowed VM slices and pointers. Stale handle operations return `error.InvalidHandle`; their `deinit` is harmless. Reacquire objects through globals or modules. Handles from other states are also rejected. Destroy handles before their state.

Reset to the active baseline restores dirty objects and releases private allocations. Tables, closures, upvalues, and threads keep their worker-local addresses. First writes copy whole-object storage; reset swaps back the original storage. An unchanged baseline with no eager userdata hooks resets without allocations or a heap traversal. All fallible eager-resource replacements are prepared before committing rollback; failure leaves the current state, handles, and baseline usable. Discard does not run Lua `__gc` or `__close` handlers; run application teardown first if needed. Collection timing and pointer-derived strings may change.

The destination keeps its allocator. Rollback records, retained worker storage, private copies, and new allocations count against the worker memory limit. Retained storage is not a Lua GC root: weak reachability and normal finalization still operate on the live graph. The GC byte estimate counts live Lua objects, so it can be smaller than allocator usage while rollback storage is retained. Snapshot storage uses `snapshot_allocator`; with a separate allocator it is outside the worker limit. Passing `state.allocator()` charges snapshot storage to that state’s limit and retains its allocator infrastructure. Workers use their supplied allocator and inherit the captured limit. Host-owned results remain freeable through the state allocator while the state lives.

Successful capture and `newState()` retain the Snapshot backing as the State’s baseline. Reset uses that retained baseline without changing ownership. A worker also retains the owner of its borrowed bytecode independently, so capturing a modified worker does not invalidate its existing functions. `Snapshot.deinit` releases the public wrapper; backing storage is freed only after the last retaining state or handle releases it. Keep `snapshot_allocator` valid for that entire lifetime, including after the wrapper is destroyed. An arena used for snapshot storage must not be reset while a retaining state exists. Keep backing allocators valid until all allocations, including shared userdata, are released.

Final backing, userdata, and retained allocator infrastructure destruction may run on any participating owner thread. Allocators for these objects must support the allocation/free calls that overlap across those threads, including freeing on a thread other than the allocating thread. Choose a thread-safe allocator or provide allocator-level synchronization when sharing it; a thread-confined arena alone does not provide that synchronization. Worker-local allocators need no additional synchronization unless their storage is shared or exported. zlua's retained memory-limit allocator supports concurrent frees from shared owners, but allocation/resize and state operations through `state.allocator()` remain with the state owner. Its underlying allocator must satisfy the same cross-thread lifetime requirements. There is no owner-thread deferred reclamation.

### Userdata and Host Bindings

Userdata payloads are shared by default, so payload mutations survive reset. Lua-owned payloads are finalized and freed once the last owner releases them. Borrowed payloads must outlive every referencing state and snapshot. zlua synchronizes shared payload lifetime accounting and finalizes/disposes each payload at most once. Embedders still synchronize mutable host payload access and external resource ownership.

For independent payload copies, supply paired hooks to `newUserdata` or `newUserdataPtr`:

```zig
const Counter = struct {
    value: i64,

    fn copy(allocator: std.mem.Allocator, source: *const @This()) !*@This() {
        const result = try allocator.create(@This());
        result.* = source.*;
        return result;
    }

    fn dispose(allocator: std.mem.Allocator, value: *@This()) void {
        allocator.destroy(value);
    }
};

var counter = try lua.newUserdata(Counter, .{ .value = 7 }, .{
    .snapshot = .{ .copy = Counter.copy, .dispose = Counter.dispose },
});
defer counter.deinit();
try lua.setGlobal("counter", counter);
```

`copy` must own all nested storage using the supplied allocator. `dispose` releases it, including on failed construction or snapshot destruction. Hooks must not retain source VM pointers or reenter snapshot operations. Concurrent `newState()`/reset operations on different workers can invoke `copy` on the same pristine payload simultaneously. Such hooks must permit concurrent source reads and synchronize any shared counters or host resources. `dispose` and finalizers can run on different owner threads and must support that usage; zlua does not serialize host hooks. Capture and discard skip application finalizers; normal finalizers must not free storage owned by `dispose`. Eager payloads (the default) keep their original ownership rules and invoke the copy hook on every reset.

To track an owned payload through scoped access, set `.tracking = .scoped`:

```zig
var tracked = try lua.newUserdata(Counter, .{ .value = 7 }, .{
    .snapshot = .{ .copy = Counter.copy, .dispose = Counter.dispose, .tracking = .scoped },
});
defer tracked.deinit();
try tracked.withMut(@as(i64, 3), struct {
    fn add(value: *Counter, amount: i64) void { value.value += amount; }
}.add);
const count = try tracked.withRead({}, struct {
    fn read(value: *const Counter, _: void) i64 { return value.value; }
}.read);
```

Callbacks receive `(payload, context)`. Scoped payload pointers, including pointers to nested storage, must not escape the callback. Read scopes forbid mutation of all reachable storage, including slice contents. Scope results must contain no pointers; use caller-owned output storage passed through the context when copying buffers. Overlapping read and write scopes on one payload return `error.ScopedAccessConflict`. Active scopes keep their userdata reachable, and capture or reset during a scope returns `error.SnapshotBusy`.

Typed callbacks and auto-bound methods apply read scopes to `*const T` arguments and mutable scopes to `*T` arguments automatically. Unscoped extraction through `ptr`, `getGlobal(..., *T)`, or `Context.arg(..., *T)` returns `error.ScopedAccessRequired`. Scoped tracking requires owned userdata; `newUserdataPtr` rejects it because external aliases could mutate borrowed storage invisibly.

The first mutable scope copies the payload before exposing writable storage. A failing callback leaves its writes dirty. Reset disposes the private copy and restores pristine storage; unchanged scoped payloads need no reset-time copies. Finalization also preserves pristine storage before invoking the finalizer, so reset never restores the finalized resource instance. For scoped userdata, the supplied `dispose` hook releases both the initial owned payload and hook-created copies, including nested storage. Normal finalizers must not release storage owned by `dispose`.

Callbacks and host capabilities remain external bindings and must stay valid. Reset cannot undo host output or external mutations. Capture takes ownership of copies of borrowed stdin and read-only memory-file bytes on the source. State-owned memory files, input positions, captured output, host bindings, errors, options, and instruction usage are restored. Host-result allocations and reusable host root capacity are separate from managed allocation cleanup.

Snapshots save GC settings and pending finalizers without running cleanup callbacks. After reset, generational collection focuses on allocations made since the snapshot. Objects from the snapshot are reclaimed during a later full collection when they are no longer reachable.

First writes, allocation-registry detachment, private-allocation cleanup, and eager external resources still have real costs. Use the mutation and full-cycle benchmarks alongside reset-only timings. Runtime setters participate in tracking; direct writes to raw object storage cannot be tracked automatically.

## Current Boundaries

- No stable raw runtime wrapper is exposed.
- Coroutine/thread handles are not in the high-level API.
- Broad Lua-table-to-Zig-struct decoding is not implemented.
- There are no `callGlobal` convenience methods; fetch a `Function` and call it.

Embedding examples under `examples/` cover scripts, library selection, callbacks, sandboxing, bytecode, memory files, userdata, and modules:

```sh
zig build examples
zig build run-example
zig build run-example -- plugin_sandbox
just example userdata_auto
```

Example compilation and execution are part of `zig build ci`.
