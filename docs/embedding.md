# Embedding zlua in Zig

zlua's Zig API uses typed values, rooted handles, explicit host capabilities,
and ordinary Zig errors. It has no stack model like the Lua C API.
`zlua.runtime` is internal and may change.

This guide covers each feature's main use and its rules. The
[API reference](api/api.md) lists every declaration.

## Contents

- [Create a State](#create-a-state)
- [Capabilities](#capabilities)
  - [Host Filesystem and Output](#host-filesystem-and-output)
  - [Clock and Process](#clock-and-process)
  - [Memory Files](#memory-files)
  - [Custom Hosts](#custom-hosts)
- [Resource Limits](#resource-limits)
  - [Interrupts](#interrupts)
- [Garbage Collection](#garbage-collection)
- [Load and Run Code](#load-and-run-code)
  - [Finding Globals](#finding-globals)
  - [Binary Chunks](#binary-chunks)
- [Values and Handles](#values-and-handles)
  - [Strings](#strings)
- [Tables and Modules](#tables-and-modules)
  - [Globals and Tables from Structs](#globals-and-tables-from-structs)
  - [Zig Namespaces](#zig-namespaces)
  - [Modules](#modules)
- [Host Callbacks](#host-callbacks)
  - [Typed Callbacks](#typed-callbacks)
  - [Host State](#host-state)
  - [Bound Values](#bound-values)
  - [Context Methods](#context-methods)
- [Decoding Tables](#decoding-tables)
- [Calling and Errors](#calling-and-errors)
- [Coroutines](#coroutines)
  - [Yielding from Callbacks](#yielding-from-callbacks)
  - [Continuations](#continuations)
- [Userdata](#userdata)
  - [Shared Metatables](#shared-metatables)
- [Snapshots](#snapshots)
- [Limitations](#limitations)
- [Examples](#examples)

## Create a State

```zig
const std = @import("std");
const zlua = @import("zlua");

pub fn main(init: std.process.Init) !void {
    const lua = try zlua.State.init(init.gpa, .{});
    defer lua.deinit();

    try lua.doString("assert(_VERSION == 'Lua 5.5')", .{ .name = "=main" });
}
```

`init` returns a `*State` allocated with the given allocator, which must
outlive the state. Rooted handles must be destroyed before it.

A state opens the safe libraries by default. The `stdlib` option takes `.none`,
`.base`, `.safe`, `.full`, or `.custom` with a `LibrarySet`; see
[Library Selection](stdlib.md#library-selection). `State.openLibs` opens more
libraries later.

## Capabilities

The library selection decides which Lua functions exist. Capabilities decide
whether those functions reach host services. A state has no host access until
you grant it, even with `.full`.

| Capability | Modes |
| --- | --- |
| `io` | Optional `std.Io`, stdin bytes, and stdout/stderr writers with flush policies. |
| `filesystem` | Disabled, read-only memory files, writable memory filesystem, host cwd, rooted host directory, or callbacks. |
| `environment` | Disabled, a host map, or callbacks. |
| `clock` | Disabled, fixed timestamp, fixed timestamp with a local offset, system clock, or callbacks. |
| `process` | Disabled, std-backed execution, or callbacks. |

See [Host-Facing Libraries](stdlib.md#host-facing-libraries) for the capability
each Lua function needs.

### Host Filesystem and Output

Std-backed filesystem, clock, and process modes use the `std.Io` given as
`io.runtime`. A rooted directory limits Lua's paths to one host directory:

```zig
var plugin_root = try std.Io.Dir.cwd().openDir(io, "plugins", .{});
defer plugin_root.close(io);

var output = std.Io.Writer.Allocating.init(allocator);
defer output.deinit();

const lua = try zlua.State.init(allocator, .{
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

The state borrows the directory handle, which must outlive it. A rooted
directory rejects absolute paths and `..` traversal. It follows a symlink only
when the link's target stays inside the directory, and otherwise returns
`error.AccessDenied`. An absolute link target is always rejected.

`stdout_flush` and `stderr_flush` choose when the runtime flushes the writers,
and both default to `.explicit`. Output without a writer is discarded, and the
state keeps no copy. Lua warnings are off by default. `IoCapability.warnings`
turns them on, and `IoCapability.warning_handler` receives them in place of
stderr.

### Clock and Process

| Clock mode | `os.time`/`os.date` | Local time | `os.clock` |
| --- | --- | --- | --- |
| `.disabled` | Error without an explicit time. | UTC | `0` |
| `.{ .fixed = t }` | `t` | UTC | `0` |
| `.{ .fixed_local = .{ .now = t, .utc_offset = s, .is_dst = b, .cpu_seconds = c } }` | `t` | `s` seconds east of UTC | `c` |
| `.system` | Host wall clock | `TZ` from the `environment` capability (a zone name, TZif path, or POSIX rule), then `/etc/localtime`, then UTC. Always UTC on Windows, WASI, and freestanding. | Process CPU time |
| `.custom` | `now` | `utc_offset` callback, or UTC | `cpu` callback, or `0` |

| Process mode | `os.execute` | `io.popen` | `os.exit` |
| --- | --- | --- | --- |
| `.disabled` | Raises `process access disabled`; `os.execute()` returns false. | Raises `'popen' not supported`. | Raises `process access disabled`. |
| `.enabled` | Runs `/bin/sh -c` (`cmd.exe /c` on Windows) with inherited stdio. | Same shell. | Unwinds with `error.LuaExit`. |
| `.custom` | `execute` callback. | Optional `popen` callback. | Optional `exit` callback, then `error.LuaExit`. |

`os.exit` never terminates the host process. `error.LuaExit` cannot be caught by
Lua code, and `State.exitRequest()` returns the request's `code` and `close`
flag, or null.

### Memory Files

Memory files serve `loadfile`, `dofile`, `require`, and `io.open` without the
host filesystem:

```zig
const files = [_]zlua.MemoryFile{
    .{
        .path = "plugins/mathx.lua",
        .contents = "return { double = function(x) return x * 2 end }",
    },
};

const lua = try zlua.State.init(allocator, .{
    .stdlib = .full,
    .capabilities = .{ .filesystem = .{ .memory = &files } },
});
defer lua.deinit();

try lua.setPackagePath("plugins/?.lua");
try lua.doString("assert(require('mathx').double(21) == 42)", .{});
```

`.memory_rw` takes a `*zlua.MemoryFilesystem`, a mutable tree that scripts write
to and the host reads with `readFileAlloc`.
[`memory_rw_files.zig`](../examples/memory_rw_files.zig) shows it.
`MemoryFilesystem.Options` sets `max_path_len` and a `max_bytes` quota.

Memory paths are relative to the sandbox. Absolute paths, `..`, backslashes, NUL
bytes, and paths that normalize to nothing are rejected.

`State.addMemoryFile` adds a file after initialization:

| Filesystem mode | Result |
| --- | --- |
| Disabled, `.memory` | The state stores its own copy. A disabled filesystem switches to `.memory` mode. |
| `.memory_rw` | Writes to the `MemoryFilesystem`. |
| Host, custom | Rejected. |

### Custom Hosts

Hosts can provide each service through callbacks:

| Type | Required callback | Optional behavior |
| --- | --- | --- |
| `CustomFilesystem` | `read_file_alloc` | Write, remove, rename, stat, directory listing, mkdir, recursive remove, and copy. |
| `CustomEnvironment` | `get` | None. |
| `CustomClock` | `now` | `cpu` for `os.clock`; `utc_offset(timestamp)` for local time. |
| `CustomProcess` | `execute` | `popen` for `io.popen`; `exit` to observe or refuse `os.exit`. |

Every callback receives the opaque context you provide. Filesystem callbacks
that allocate must use the allocator zlua passes in. An omitted filesystem
operation returns `error.OperationUnsupported`, which Lua sees as
`host filesystem unavailable`. The
[clock and process tables](#clock-and-process) show the other omitted callbacks.
`utc_offset` returns a `zlua.UtcOffset`, and `popen` returns a
`zlua.PopenResult`.

## Resource Limits

```zig
const lua = try zlua.State.init(allocator, .{
    .limits = .{
        .max_memory = 16 * 1024 * 1024,
        .max_stack_values = 4096,
        .max_call_frames = 128,
        .max_instructions = 1_000_000,
        .max_file_bytes = 4 * 1024 * 1024,
    },
});
```

| Limit | Scope |
| --- | --- |
| `max_memory` | Every allocation through the state: parsing, compilation, runtime objects, API conversion, and memory-file copies. Initialization returns `error.OutOfMemory` if the requested libraries don't fit. Afterward, running Lua returns `error.LuaError` with `memory limit exceeded`, and direct API calls return `error.OutOfMemory`. |
| `max_instructions` | Cumulative across all calls and coroutine resumes, counting VM instructions and native work charged by its size. `instructionBudget` reads it and `resetInstructionBudget` restarts it. |
| `max_stack_values`, `max_call_frames` | Overflow raises a catchable `stack overflow` error. |
| `max_native_stack` | Native stack bytes one host call may use. Overflow raises a catchable `C stack overflow` error. Defaults to 6 MiB, or 14 MiB in Debug builds; lower it on smaller threads. |
| `max_finalizer_instructions` | Lua `__gc` run by each `deinit`, `collect`, or `stepGc`. Later finalizers then fail with a warning, and host finalizers still run. Defaults to 1,000,000. |
| `max_output_bytes` | Bytes Lua writes to stdout and stderr, and warnings. Exceeding it raises `output limit exceeded`, which `pcall` cannot catch, until `resetOutputLimit`. `outputBytes` reads the count. |
| `max_file_bytes` | Each file read, each write through an `io` file handle, and each `fs.write`. Defaults to 256 MiB. |

`Limits.untrusted` is a starting point for running code you don't trust. See
[Running Untrusted Lua](security.md).

`CallOptions.max_instructions` limits one `Function.callWith`, and
`ResumeOptions.max_instructions` limits one `Coroutine.resumeCoroutineWith`.
Each covers nested calls and resumed coroutines, and the tightest enclosing
limit applies:

```zig
try handler.callWith(.{event}, void, .{ .max_instructions = 100_000 });
```

An exhausted budget returns `error.LuaError` with `instruction limit exceeded`,
and `pcall` cannot catch it. The
state-wide budget keeps failing every call until `resetInstructionBudget`, and a
coroutine stopped by a budget ends up `.dead`.

### Interrupts

`interruptHandle` returns a small, copyable `InterruptHandle`. Another thread
calls `interrupt()` on it to stop the running script:

```zig
const handle = try lua.interruptHandle();
// On a watchdog thread, after a deadline:
handle.interrupt();
// On the Lua thread:
lua.doString(source, .{}) catch |err| switch (err) {
    error.Interrupted => {}, // the state is still usable
    else => return err,
};
```

Lua stops at its next safepoint: a loop back edge, a call, or a check inside
long-running library functions. `pcall` cannot catch the interrupt, pending
`__close` handlers don't run, and an interrupted coroutine ends up `.dead`. The
request is consumed when `error.Interrupted` reaches the host, and
`clearInterrupt` drops a pending one. Join threads using the handle before
`deinit`.

## Garbage Collection

Collection runs automatically in generational mode. Incremental mode with
automatic collection stopped lets the host advance collection itself:

```zig
const lua = try zlua.State.init(allocator, .{
    .gc = .{ .mode = .incremental, .running = false },
});
defer lua.deinit();

// Between requests or frames:
_ = try lua.stepGc(1);
```

| Call | Effect |
| --- | --- |
| `stepGc(n)` | Runs up to `n` steps, and at least one. Returns `.complete` when a major cycle finishes and `.pending` otherwise. Steps bound work, not elapsed time. |
| `collect()` | Finishes a full collection, including pending finalizers. |
| `stopGc()`, `restartGc()`, `isGcRunning()` | Control automatic collection. `collect` and `stepGc` work while it is stopped. |
| `setGcMode`, `gcMode` | Set or read the mode. The setter returns the previous mode. |
| `setGcParam`, `gcParam` | Set or read a parameter. The setter returns the previous value, and invalid values return `error.InvalidGcParam`. See [GcParams](api/runtime/types.md#type-gcparams). |

`deinit` closes the state like `lua_close`: it runs pending `__gc` finalizers
newest first and closes open files. Finalizer errors are ignored. During
`deinit`, an `os.exit` inside a finalizer ends that finalizer and the rest still
run, and during `collect` it returns `error.LuaExit`. `reset` runs no `__gc`
finalizers.

## Load and Run Code

`doString` and `doFile` run a chunk once:

```zig
try lua.doString("answer = 21 * 2", .{ .name = "=setup" });
try lua.doFile("plugin.lua", .{ .name = "@plugin.lua" });
```

`loadString` and `loadFile` return a rooted `Function`:

```zig
var greet = try lua.loadString(
    "local name = ...; return 'hello, ' .. name",
    .{ .name = "=greet" },
);
defer greet.deinit();

var message = try greet.call(.{"host"}, zlua.String);
defer message.deinit();
```

Load options set the chunk's `_ENV` table with `.environment`, and the accepted
input with `.mode`: `.source_only` (the default), `.binary_only`, or
`.source_or_binary`.

```zig
var chunk = try lua.loadString("return answer", .{
    .environment = env,
    .mode = .source_only,
});
```

### Finding Globals

`zlua.analyze(allocator, source)` parses a chunk without running it and lists
its global reads and writes with their lines:

```zig
var analysis = zlua.analyze(allocator, source) catch |err| switch (err) {
    error.SyntaxError => return fail("does not compile"),
    else => return err,
};
defer analysis.deinit();
for (analysis.globals) |use| {
    if (use.access == .read and !known(use.name)) warn(use.line, use.name);
}
```

It lists uses through the chunk's own `_ENV`, not those under a `local _ENV` or
an `_ENV` parameter. `_G.x` is a read of `_G`, `_ENV.x` is not a use, and
neither is a plain `global x` declaration. `error.SyntaxError` carries no
message; `State.loadString` gives one.

### Binary Chunks

`Function.dumpBytecode` and `State.loadBytecode` round-trip a loaded function:

```zig
var bytes: std.Io.Writer.Allocating = .init(allocator);
defer bytes.deinit();
try chunk.dumpBytecode(&bytes.writer, .{ .strip_debug = true });

var cached = try lua.loadBytecode(bytes.written(), .{});
defer cached.deinit();
```

The format is internal to zlua, can change between versions, and is not
compatible with PUC Lua `luac` chunks. Loading verifies a chunk's structure,
which stops it indexing outside its registers, constants, or code. Lua's `load`,
`loadfile`, `dofile`, and `require` reject binary chunks unless
`Options.binary_chunks` is set.

## Values and Handles

Zig values convert to Lua automatically:

| Zig | Lua |
| --- | --- |
| `null` | `nil` |
| `bool` | boolean |
| integer / float | integer / number |
| byte slice | string |
| non-byte array or slice | array table |
| struct | table keyed by field name |
| enum | its name |
| function | function, called like a [typed callback](#typed-callbacks) |
| struct type | table of its [public declarations](#zig-namespaces) |
| `String`, `Table`, `Function`, `Ref`, `Value`, `Userdata(T)` | existing Lua value |

Reads name the type they want. A tuple type reads multiple return values, and
`zlua.Value` holds a value of unknown type:

```zig
try lua.setGlobal("answer", 42);
const answer = try lua.getGlobal("answer", i64);

var result = try chunk.call(.{}, struct { bool, i64, zlua.String });
defer zlua.deinit(&result);
const ok, const count, const label = result;
```

`zlua.deinit` releases the handles in a tuple, optional, `Value`, or handle.
`Value.typeName` returns the name Lua's `type` gives a value. Reading an enum,
struct, or non-byte slice is a compile error; read a `Value` and pass it to
[`decode`](#decoding-tables).

`String`, `Table`, `Function`, `Coroutine`, `Ref`, userdata, and `ErrorRef`
handles each own a registry root, as do values and tuples containing them. Call
`deinit` on each one. Assigning a handle into Lua does not consume your root.

`handleScope` releases every handle created until its `end`, except those passed
to `keep`:

```zig
var scope = lua.handleScope();
defer scope.end();
const config = try lua.getGlobal("config", zlua.Table);
const players = try config.get("players", zlua.Table);
return scope.keep(players); // the caller deinits it
```

### Strings

Strings read from Lua are `zlua.String` handles, including `Value.string`.
`bytes()` returns the string's bytes, valid until the handle's `deinit` or a
`reset`, `dupe(allocator)` returns a copy, and the `{f}` format specifier prints
them:

```zig
var title = try config.get("title", zlua.String);
defer title.deinit();
const is_demo = std.mem.eql(u8, try title.bytes(), "demo");
std.debug.print("{f}\n", .{title});
```

Callback arguments can also be read as `[]const u8`, and userdata arguments as
`*T`. These point into Lua memory and stay valid until the callback returns.
Reading either type anywhere else is a compile error.

## Tables and Modules

```zig
var config = try lua.newTable(.{ .hash_hint = 3 });
defer config.deinit();

try config.set("title", "demo");
try config.set("max_players", 8);
try lua.setGlobal("config", config);
```

| Lua | With metamethods | Raw |
| --- | --- | --- |
| `t[k]` | `get` | `rawGet` |
| `t[k] = v` | `set` | `rawSet` |
| `#t` | `len` | `rawLen` |
| Iteration | `pairs` | `rawIterator` |

`append` adds to the end of the raw sequence. `setMetatable` ignores
`__metatable`, as `lua_setmetatable` does.

`toSlice(T, allocator)` copies the raw sequence `1..rawLen()` into an allocated
slice. A hole or an element of the wrong type returns `error.TypeMismatch`, and
`?T` allows holes. Deinitialize handle elements.

```zig
var it = try inventory.pairs();
defer it.deinit();
while (try it.next()) |entry| {
    std.debug.print("{f} = {d}\n", .{ entry.key.string, entry.value.integer });
}
```

An iterator roots the table and the current entry, and owns each `Entry` until
the next call. During traversal you may assign to existing fields; adding keys
is undefined.

### Globals and Tables from Structs

`setGlobals` sets a global for each field of a struct. Functions become Lua
functions, nested structs become tables, and other values are copied:

```zig
fn add(a: i64, b: i64) i64 {
    return a + b;
}

try lua.setGlobals(.{
    .add = add,
    .VERSION = "1.2.0",
    .game = .{
        .max_players = 8,
        .clamp = clamp,
    },
});
```

`newTableFrom` builds a `Table` the same way, for example as a chunk's
`environment`. `Table.setFields` assigns each field to an existing table through
`__newindex`.

Converting the same Zig function again reuses its Lua function. A function must
be passed directly; a function pointer is a compile error, and
`newTypedFunction` wraps one.

### Zig Namespaces

A struct or enum type, including a Zig file, converts to a table of its public
declarations:

```zig
// inventory.zig
pub const max_items = 64;

pub fn total(counts: []const i64) i64 { ... }

pub const Item = struct {
    count: i64,

    pub fn add(self: *Item, amount: i64) i64 { ... }
};
```

```zig
try lua.setLoadedModule("inventory", @import("inventory.zig"));
```

| Declaration | Lua value |
| --- | --- |
| `pub fn` | function, called like a typed callback |
| `pub const`, `pub var` | the current value, copied |
| `pub const` struct type, such as `@import("math.zig")` | nested table, when it has public declarations |
| `pub const` enum type | table mapping each tag to its name, plus its public declarations |
| a type already being converted, such as `@This()` | left out |
| other types, `lua`, `lua_userdata` | left out |

A struct's fields aren't exported; create instances as [userdata](#userdata).

A generic function, a function whose parameters Lua can't pass or whose result
has no Lua value, and a value with no Lua equivalent are compile errors, also
inside nested namespaces. A re-exported library such as `std` must be left out.
A namespace's `lua` declaration renames or leaves out declarations:

```zig
pub const lua = .{
    .total = .{ .key = "sum" },
    .debugDump = .{ .skip = true },
};
```

`setGlobals(T)` sets a global for each declaration instead.

### Modules

| Call | Effect |
| --- | --- |
| `setLoadedModule(name, module)` | Stores a value, such as a struct or [namespace](#zig-namespaces), in `package.loaded[name]`. |
| `preloadModule(name, loader)` | Installs a Lua loader in `package.preload[name]`. |
| `preloadModuleFn(name, function)` | Installs a Zig function as the loader. |
| `require(name, T)` | Calls Lua's `require` and converts the result to `T`. |

```zig
fn openHost(ctx: *zlua.Context) !zlua.Table {
    var module = try ctx.state().newTable(.{});
    errdefer module.deinit();
    try module.set("version", 1);
    return module; // released after conversion
}

try lua.preloadModuleFn("host", openHost);

var host = try lua.require("host", zlua.Table); // runs openHost once
defer host.deinit();
```

## Host Callbacks

`newFunction` turns a Zig function into a Lua function. The callback reads
arguments and returns values through a `Context`:

```zig
fn hostAdd(ctx: *zlua.Context) !void {
    const lhs = try ctx.arg(0, i64);
    const rhs = try ctx.arg(1, i64);
    try ctx.returnValues(.{ lhs + rhs, "ok" });
}

var host_add = try lua.newFunction("host_add", hostAdd);
defer host_add.deinit();
try lua.setGlobal("host_add", host_add);
```

Callbacks are native functions: `debug.getinfo` reports `what = "C"`,
`string.dump` rejects them, and `Function.dumpBytecode` returns
`error.TypeMismatch`. A rooted handle read with `ctx.arg` must be deinitialized
by the callback.

### Typed Callbacks

`newTypedFunction` converts parameters and return values:

```zig
fn clamp(value: f64, min: f64, max: f64) f64 {
    return @min(@max(value, min), max);
}

var clamp_fn = try lua.newTypedFunction("clamp", clamp);
defer clamp_fn.deinit();
try lua.setGlobal("clamp", clamp_fn);
```

`lua.setGlobal("clamp", clamp)` installs the same function without a handle. A
parameter type Lua can't pass, such as `std.mem.Allocator`, is a compile error.

Typed callbacks and userdata methods release handle parameters when they return.
To keep one, wrap it in a `Value` and make another handle, as in
`state.read(.{ .table = t }, zlua.Table)`.

A typed callback may also take `*zlua.Context`. One that returns `void` keeps
whatever it set with `ctx.returnValues`, for results a return type can't
express, such as nil or several values.

### Host State

`State.setHost` attaches one typed pointer to the state. Read it with
`ctx.host(T)`, which returns null when the state holds no `*T`, or take a
`zlua.Host(T)` parameter in a typed callback. That parameter consumes no Lua
argument and raises a Lua error when the pointer is missing:

```zig
const Game = struct { gold: i64 };

fn giveGold(game: zlua.Host(Game), amount: i64) i64 {
    game.ptr.gold += amount;
    return game.ptr.gold;
}

var game = Game{ .gold = 0 };
try lua.setHost(&game);
```

Snapshots and their workers keep the pointer, and `reset` restores the
baseline's. A worker on another thread can call `setHost` with its own.

### Bound Values

`newClosure(name, function, values)` creates a function from a typed callback
with the Lua values in tuple `values` bound to it, like the upvalues of a C
closure. Each function has its own values:

```zig
fn count(ctx: *zlua.Context) !i64 {
    const next = try ctx.upvalue(0, i64) + 1;
    try ctx.setUpvalue(0, next);
    return next;
}

var counter = try lua.newClosure("count", count, .{@as(i64, 0)});
defer counter.deinit();
try lua.setGlobal("count", counter);
```

`ctx.upvalue(index, T)` reads a bound value, `ctx.setUpvalue(index, value)`
replaces one, and `ctx.upvalueCount()` returns how many there are. Bound values
are Lua values, so snapshots copy them and `reset` restores them.

### Context Methods

| Method | Behavior |
| --- | --- |
| `argCount()` | Returns the number of arguments. |
| `optionalArg(index, T)` | Returns null when the argument is absent or `nil`. |
| `decodeArg(index, T, allocator)` | Decodes an argument like `decode`. |
| `pushReturn(value)` | Appends one return value. |
| `raise(value)` | Raises any value as a Lua error. |
| `raisef(fmt, args)` | Raises a formatted message starting with the Lua position, like `error`. |
| `argError(index, message)` | Raises a `bad argument` error. |
| `functionName()` | Returns the name the callback's function was created with. |
| `caller(level)` | Describes a Lua function on the callback's coroutine: `source`, `shortSource(&buffer)` with a `[zlua.Caller.short_source_len]u8` buffer, and `line`. Level 0 is the innermost, native functions are not counted, and it returns null past the last function. |
| `currentLine()` | Returns the line of the running Lua function, or null when there is none or its debug info is stripped. |
| `callNonYielding(function, args, R)` | Calls Lua on the callback's coroutine, within its instruction budget, with yields forbidden. Lua errors propagate after cleanup, and completed effects stay. |
| `callThen(function, args, continuation, saved)` | Ends the callback by calling Lua that may yield; see [Continuations](#continuations). |
| `yieldThen(values, continuation, saved)` | Ends the callback by yielding; see [Continuations](#continuations). |
| `upvalue(index, T)`, `setUpvalue(index, value)`, `upvalueCount()` | Read and replace [bound values](#bound-values). |
| `coroutineIdentity()` | Returns a token for the current coroutine, valid during the callback and until reset. |
| `io()` | Returns the `std.Io` given as `capabilities.io.runtime`, or null. |

Calls through `ctx.io()` are not checked against capabilities. The `std.Io`
implementation must outlive the state and every snapshot and worker that shares
it, and must be safe to call from every thread a worker runs on. A callback must
await or cancel any future it starts before it returns or yields.

## Decoding Tables

`zlua.decode` reads a Lua value into a Zig value by its type, checking every
key. It handles integers, floats, booleans, strings, enums by name, optionals,
arrays, vectors, slices, structs, `std.EnumArray`, and `std.EnumSet`. Absent
keys keep the struct's defaults:

```zig
const Weapon = struct {
    name: []const u8 = "",
    kind: enum { sword, spear } = .sword,
    might: i32 = 0,
    tags: []const []const u8 = &.{},

    pub const lua = .{ .name = .{ .required = true } };
};

var arena: std.heap.ArenaAllocator = .init(allocator);
defer arena.deinit();
var diagnostic: zlua.Diagnostic = .{ .gpa = allocator };
defer diagnostic.deinit();

const weapon = zlua.decode(Weapon, value, .{
    .allocator = arena.allocator(),
    .diagnostic = &diagnostic,
}) catch |err| switch (err) {
    error.Invalid => return fail(diagnostic.text),
    else => return err,
};
```

A failure returns `error.Invalid` and leaves the first message in the diagnostic
with its path: `tags[2]: expected a string, got number`,
`unknown field "mighty"`, or `name: missing`. Strings and slices come from
`.allocator`, and a failed decode does not free them. `.strict` makes that many
levels below the value require every field.

A struct's `lua` declaration sets options per field, read back with
`zlua.fieldOptions` and `zlua.fieldKeys`:

| Option | Meaning |
| --- | --- |
| `.key` | The Lua key, the field name by default. |
| `.required` | Decoding fails when the key is absent. |
| `.embed` | The fields of this struct field are given inline in the outer table. |
| `.elements` | The enum whose values a `std.bit_set` field lists. |
| `.doc` | A description for generated documentation. |

A type decodes itself by declaring
`pub fn fromLua(d: anytype, value: zlua.Value, out: *@This()) zlua.DecodeError!void`
and reporting failures with `d.fail(fmt, args)`. For types it can't change, or
lookups that need outside data, create a `zlua.Decoder(Context)`:
`Context.decodes(T)` picks the types it handles,
`Context.decode(d, T, value, out)` decodes them, and `d.context` reaches the
context. A decoder's `push` and `pop` add to the error path, and `decodeStruct`
can leave keys for the caller.

Typed callbacks and userdata methods decode enum, array, vector, slice, struct,
and `fromLua` parameters the same way, with strings and slices that last until
the callback returns. A value that doesn't fit raises
`bad argument #2 to 'box' (size[2]: expected a number, got string)`.

Conversion to Lua follows the same `.key` and `.embed` options. `std.EnumArray`
becomes a table by name, and `std.EnumSet` becomes a list of names. A type can
declare `pub fn toLua(self: @This()) U` to convert as the `U` it returns.

## Calling and Errors

```zig
try lua.doString("function add(a, b) return a + b end", .{});
var add = try lua.getGlobal("add", zlua.Function);
defer add.deinit();
const sum = try add.call(.{ 20, 22 }, i64);
```

`callGlobal("add", .{ 20, 22 }, i64)` fetches and calls a global function in one
step.

`call` and the other state calls report Lua failures as `error.LuaError`, and
the state keeps the error until the next call or resume:

| Call | Effect |
| --- | --- |
| `takeError()` | Returns the rooted Lua error as an `ErrorRef`, which the caller deinits. |
| `writeError(err, writer)` | Writes the message for `error.LuaError`, or the error's name for any other error. |
| `ErrorRef.writeMessage(writer)` | Writes the error's message, as the `{f}` format specifier does. |
| `ErrorRef.value()` | Returns the error value. |

```zig
add.call(.{ "bad", 1 }, i64) catch |err| {
    if (err != error.LuaError) return err;
    var lua_error = lua.takeError().?;
    defer lua_error.deinit();
    std.debug.print("{f}\n", .{lua_error});
};
```

`callWith` takes `CallOptions`:

| Option | Effect |
| --- | --- |
| `.traceback = true` | Captures a traceback where the error was raised, read with `ErrorRef.traceback()`. `ErrorRef.deinit` frees it. |
| `.message_handler` | Runs a Lua `Function` with `xpcall` semantics. |
| `.max_instructions` | Limits this call. |

When a script calls `error(nil)`, `ErrorRef.value` returns `.nil`.

## Coroutines

`newCoroutine(function)` creates a suspended coroutine, and
`resumeCoroutine(args, Yield, Return)` runs it until it yields or returns. The
first resume passes `args` to the function, and later resumes make them the
results of the pending yield. Use a tuple type for multiple values and `void` to
ignore them:

```zig
var chunk = try lua.loadString(
    \\coroutine.yield("show dialogue")
    \\return "story finished"
, .{ .name = "=story.lua" });
defer chunk.deinit();

var story = try lua.newCoroutine(chunk);
defer story.deinit();

while (try story.status() == .suspended) {
    var step = try story.resumeCoroutine(.{}, zlua.String, zlua.String);
    defer step.deinit();
    switch (step) {
        .yielded => |text| std.debug.print("yielded: {f}\n", .{text}),
        .returned => |text| std.debug.print("returned: {f}\n", .{text}),
    }
}
```

- `status()` returns `.suspended`, `.running`, `.normal`, or `.dead`. Only
  suspended coroutines resume.
- Lua failures return `error.LuaError`, and `takeError` returns them.
  `resumeCoroutineWith` takes `ResumeOptions` for `.traceback` and
  `.max_instructions`.
- `switch` on the result. The inactive field is undefined.
- `deinit` each result to release its handles.
- A conversion error leaves the coroutine wherever Lua stopped, and side effects
  stay.
- A coroutine handle's `deinit` only drops the handle. To abandon a suspended
  coroutine, call `close()` first to run its pending `__close` handlers. A Lua
  error raised during closing returns `error.LuaError`.
- `ctx.coroutine()` returns the running coroutine inside a callback.

### Yielding from Callbacks

A callback suspends its coroutine with `return ctx.yield(values)`:

```zig
fn askUser(ctx: *zlua.Context) !void {
    const prompt = try ctx.arg(0, []const u8);
    return ctx.yield(.{prompt});
}
```

When Lua runs `local answer = ask_user("Open the door?")`, Zig receives the
prompt as `.yielded`, and resuming with `.{"yes"}` makes `ask_user` return
`"yes"`. The callback's defers run before the coroutine suspends, and the Zig
function is never reentered. Typed callbacks and userdata methods that return an
error union yield the same way.

Yields work through nested Lua calls, `pcall`, iterators, `__pairs`, and most
metamethods. `ctx.isYieldable()` reports whether the current callback can yield.
It cannot under `Function.call`, `doString`, the main thread,
`Context.callNonYielding`, `ipairs` reading `__index`, `close()`, a finalizer,
or library callbacks such as `table.sort`, `string.gsub`, `load` readers,
`require` loaders, and `__tostring` through `tostring`.

### Continuations

A callback that needs to continue after Lua yields ends with `callThen` or
`yieldThen`. `return ctx.callThen(function, args, continuation, saved)` calls
`function`, which may yield, and then calls `continuation` with its results.
`return ctx.yieldThen(values, continuation, saved)` yields `values` and calls
`continuation` with the resume arguments:

```zig
fn askUser(ctx: *zlua.Context, prompt: []const u8) !void {
    return ctx.yieldThen(.{prompt}, answered, .{prompt});
}

fn answered(ctx: *zlua.Context, answer: []const u8) ![]const u8 {
    const prompt = try ctx.upvalue(0, []const u8);
    return if (std.mem.eql(u8, answer, "yes")) prompt else "declined";
}
```

The continuation is a typed callback whose [bound values](#bound-values) are the
tuple `saved`, and its returns become the original callback's. It can end with
`callThen` or `yieldThen` itself. A suspended continuation is part of the
coroutine, so snapshots capture it. Lua errors propagate through both calls, and
tracebacks and the `debug` library show the pending call as a C function.

## Userdata

`newUserdata` stores a Zig value that Lua owns, and `wrapUserdata` wraps
storage the host owns. Public functions of `T` whose first parameter is `*T` or
`*const T` become methods, and Lua names beginning with `__` become metamethods:

```zig
const Counter = struct {
    value: i64,

    pub fn inc(self: *@This(), amount: i64) i64 {
        self.value += amount;
        return self.value;
    }
};

var counter = try lua.newUserdata(Counter, .{ .value = 0 }, .{});
defer counter.deinit();
try lua.setGlobal("counter", counter);
```

`ptr()` returns the payload pointer, and callbacks take either kind as a typed
argument, such as `ctx.arg(0, *Counter)`. `AnyUserdata.as(T)` checks the payload
type and returns another rooted handle.

A method Lua can't call, such as one that takes a `std.mem.Allocator`, is a
compile error. The `lua` declaration of `T` leaves methods out or renames them,
as it does for a [namespace](#zig-namespaces):

```zig
const Buffer = struct {
    bytes: std.ArrayList(u8) = .empty,

    pub const lua = .{
        .deinit = .{ .skip = true },
        .length = .{ .key = "len" },
        .close = .{ .key = "__close" },
    };

    pub fn deinit(self: *Buffer, gpa: std.mem.Allocator) void { ... }
    pub fn length(self: *const Buffer) i64 { ... }
    pub fn close(self: *Buffer) void { ... }
};
```

| Option or call | Effect |
| --- | --- |
| `.finalizer` | Runs with the payload and the state's allocator when Lua finalizes the userdata, before Lua-owned storage is freed. |
| `.external_bytes`, `setExternalBytes` | Report host storage the payload keeps alive to the collector. These bytes do not count against `max_memory`. |
| `.metatable` | Uses your own metatable and installs `T`'s methods on it. If construction fails, the host still finalizes the value. |
| `.snapshot` | Copy hooks; see [Userdata Payloads](snapshots.md#userdata-payloads). |

A `__gc` metamethod runs before the host finalizer and the deinit hook. A `__gc`
method of `T` runs at most once per object, after which typed access to the
object fails with `userdata is closed` in Lua and `error.UserdataClosed` in Zig.
Equality uses `__eq`, and `rawequal` compares wrapper identity. Zig fields are
not enumerated automatically; define `__pairs` for custom iteration, or
`__index` for `ipairs`.

`getmetatable` returns false for userdata whose metatable zlua created. Set
`UserdataType.expose_metatable` to return the metatable instead.

### Shared Metatables

The first `newUserdata` or `wrapUserdata` of `T` builds one metatable for `T`
that every later value shares. `defineUserdata` builds it with options instead:

```zig
const Canvas = struct {
    width: i64,

    pub fn getWidth(self: *const @This()) i64 {
        return self.width;
    }
};

try lua.defineUserdata(Canvas, .{ .name = "canvas" });
var canvas = try lua.newUserdata(Canvas, .{ .width = 16 }, .{});
defer canvas.deinit();
```

`.name` sets `__name`, which `tostring` and argument errors show. `.methods`
names another struct to take the methods from, and its `lua` declaration applies
to them.

A `lua_userdata` declaration on `T` gives the same options to the first
`newUserdata` or `wrapUserdata`. `.methods = struct {}` binds no methods:

```zig
const Session = struct {
    token: u64,

    pub const lua_userdata = .{ .name = "session", .methods = struct {} };

    pub fn revoke(self: *Session) void { ... }
};
```

`newConstructor(T, name, initializer, options)` creates a Lua function that
reads `initializer`'s arguments by type and returns its result as userdata.

## Snapshots

A `Snapshot` is an immutable capture of a configured state. Workers created from
it are independent, and each resets to its baseline:

```zig
var snapshot = try lua.snapshot(snapshot_allocator);
defer snapshot.deinit();

const worker = try snapshot.newState(worker_allocator);
defer worker.deinit();
try worker.doString("results = {42}", .{});
try worker.reset();
```

A reset invalidates earlier handles. Separately retained `Snapshot` handles can
create workers concurrently, and each `State` needs external serialization. See
[Snapshots](snapshots.md) for baselines, threads, lifetimes, allocators, and
userdata payloads.

## Limitations

- `Context.yield`, `callThen`, and `yieldThen` must be a callback's last action.
  A continuation picks up the work after Lua resumes.

## Examples

`zig build examples` or `just examples` builds and runs every example program in
[`examples/`](../examples), and `zig build ci` includes them.

| Topic | Example |
| --- | --- |
| Overview | [`readme.zig`](../examples/readme.zig) |
| Scripts | [`run_script.zig`](../examples/run_script.zig) |
| Library selection | [`select_libraries.zig`](../examples/select_libraries.zig) |
| Sandboxing | [`plugin_sandbox.zig`](../examples/plugin_sandbox.zig) |
| Memory files | [`memory_rw_files.zig`](../examples/memory_rw_files.zig) |
| Interrupts | [`watchdog.zig`](../examples/watchdog.zig) |
| Bytecode | [`bytecode_roundtrip.zig`](../examples/bytecode_roundtrip.zig) |
| Modules | [`preload_module.zig`](../examples/preload_module.zig) |
| Callbacks | [`register_function.zig`](../examples/register_function.zig), [`typed_host_function.zig`](../examples/typed_host_function.zig) |
| Decoding | [`decode_config.zig`](../examples/decode_config.zig) |
| Coroutines | [`coroutine_story.zig`](../examples/coroutine_story.zig) |
| Userdata | [`userdata_counter.zig`](../examples/userdata_counter.zig), [`userdata_auto.zig`](../examples/userdata_auto.zig), [`typed_userdata_initializer.zig`](../examples/typed_userdata_initializer.zig) |
| Snapshots | [`snapshot_adventure.zig`](../examples/snapshot_adventure.zig), [`snapshot_adversarial.zig`](../examples/snapshot_adversarial.zig), [`snapshot_reset.zig`](../examples/snapshot_reset.zig) |
