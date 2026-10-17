# Embedding zlua in Zig

zlua's Zig API is built around typed values, rooted handles, explicit host capabilities, and ordinary Zig errors, rather than the stack model of the Lua C API. Everything you need goes through `zlua.State`. The `zlua.runtime` namespace is an internal interface and may change.

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

The allocator you pass must outlive the state, and any rooted handles you create must be destroyed before the state is.

By default, a state opens the safe libraries and has no ambient access to the host. The `stdlib` option picks a different set:

| Selection | Opens |
| --- | --- |
| `.none` | No libraries. `_G` still exists for host and script globals. |
| `.base` | Base globals only. |
| `.safe` | Base, table, string, math, utf8, coroutine, json, toml, msgpack, and csv. |
| `.full` | Safe plus io, os, debug, package, and fs. |
| `.custom` | Only libraries selected in a `LibrarySet`. |

With `.custom`, you list exactly the libraries you want:

```zig
var lua = try zlua.State.init(allocator, .{
    .stdlib = .{ .custom = .{
        .math = true,
        .json = true,
    } },
});
```

If you need more libraries after initialization, `State.openLibs` opens them on an existing state.

## Capabilities

Library selection and capabilities answer two different questions. The library selection decides which Lua functions exist, and capabilities decide whether those functions can reach host services. Opening `.full` gives scripts `io`, `os`, and the rest, but on its own it does not grant filesystem, environment, clock, process, or I/O access.

| Capability | Modes |
| --- | --- |
| `io` | Optional `std.Io`, stdin bytes, and stdout/stderr writers with flush policies. |
| `filesystem` | Disabled, read-only memory files, writable memory filesystem, host cwd, rooted host directory, or callbacks. |
| `environment` | Disabled, a host map, or callbacks. |
| `clock` | Disabled, fixed timestamp, fixed timestamp with a local offset, system clock, or callbacks. |
| `process` | Disabled, std-backed execution, or callbacks. Covers `os.execute`, `io.popen`, and `os.exit`. |

The CLI intentionally opens the full libraries with host-oriented capabilities. Embedded states start sandboxed instead, so you decide what each one can reach.

### Host Filesystem and Output

The std-backed filesystem, clock, and process modes go through Zig's explicit `std.Io`, which you supply as `io.runtime`. When Lua should stay inside one host directory, give it a rooted directory rather than access to the current working directory:

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

The state borrows the directory handle, so the handle must outlive the state. A rooted directory rejects absolute paths and `..` traversal.

Lua output goes to the configured writers as it is produced. The `stdout_flush` and `stderr_flush` options choose when the runtime flushes them, and both default to `.explicit`.

Lua warnings are off by default. Set `IoCapability.warnings` to turn them on, as `lua -W` does, and set `IoCapability.warning_handler` if you want to receive warnings yourself instead of having them written to stderr.

File reads and writes share one size limit, `limits.max_file_bytes`, which is 256 MiB by default. When an open fails, Lua gets the usual C-style result, such as `nil, "data.txt: No such file or directory", 2`.

### Clock and Process

The clock capability decides what `os.time`, `os.date`, and `os.clock` report, and which time zone local time uses:

| Mode | `os.time`/`os.date` | Local time | `os.clock` |
| --- | --- | --- | --- |
| `.disabled` | Error without an explicit time. | UTC | `0` |
| `.{ .fixed = t }` | `t` | UTC | `0` |
| `.{ .fixed_local = .{ .now = t, .utc_offset = s, .is_dst = b, .cpu_seconds = c } }` | `t` | `s` seconds east of UTC | `c` |
| `.system` | Host wall clock | `TZ`, then `/etc/localtime` | Process CPU time |
| `.custom` | `now` | `utc_offset` callback, or UTC | `cpu` callback, or `0` |

With the system clock, local time comes from `TZ` (a zone name, TZif path, or POSIX rule), then `/etc/localtime`, and falls back to UTC if neither is available.

The process capability covers `os.execute`, `io.popen`, and `os.exit`:

| Mode | `os.execute` | `io.popen` | `os.exit` |
| --- | --- | --- | --- |
| `.disabled` | Raises `process access disabled`; `os.execute()` returns false. | Raises `'popen' not supported`. | Raises `process access disabled`. |
| `.enabled` | Runs `/bin/sh -c` (`cmd.exe /c` on Windows) with inherited stdio. | Same shell. | Unwinds with `error.LuaExit`. |
| `.custom` | `execute` callback. | Optional `popen` callback. | Optional `exit` callback, then `error.LuaExit`. |

`io.popen` runs the whole command in one go. In read mode the command runs when the handle opens, and in write mode it runs when the handle closes.

`os.exit` never terminates the host process. Instead, it unwinds Lua with `error.LuaExit`, which Lua code cannot catch, and `State.exitRequest()` gives you the requested exit code.

### Memory Files

Memory files let scripts use `loadfile`, `dofile`, and `require` without touching the host filesystem. The simplest form is a read-only list of files:

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

When scripts also need to write files, use `zlua.MemoryFilesystem` with the `.memory_rw` mode. This gives Lua a mutable in-memory tree that the host can read back afterward:

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

Memory paths are relative to the sandbox. Absolute paths, `..`, backslashes, NUL bytes, and paths that normalize to nothing are all rejected. `MemoryFilesystem.Options` lets you set `max_path_len` and a `max_bytes` quota for file contents.

You can also add files after initialization with `State.addMemoryFile`. What it does depends on the filesystem mode. If the filesystem is disabled or uses read-only memory files, the state stores its own copy of the file. With `.memory_rw`, the write goes through to the `MemoryFilesystem`. Host and custom filesystem modes reject it.

### Custom Hosts

Freestanding hosts, and hosts that don't use std, can provide each service through callbacks instead:

| Type | Required callback | Optional behavior |
| --- | --- | --- |
| `CustomFilesystem` | `read_file_alloc` | Write, remove, rename, stat, directory listing, mkdir, recursive remove, and copy. |
| `CustomEnvironment` | `get` | Environment lookup. |
| `CustomClock` | `now` | `cpu` for `os.clock`; `utc_offset(timestamp)` for local time. |
| `CustomProcess` | `execute` | `popen` for `io.popen`; `exit` to observe or refuse `os.exit`. |

Every callback receives the opaque context you provide. Filesystem callbacks that allocate must use the allocator zlua passes in. If you leave out an optional operation, calls to it return an unsupported error. zlua never falls back to ambient host access.

## Resource Limits

Limits keep a runaway or hostile script from taking over the host. You set them when you create the state:

```zig
var lua = try zlua.State.init(allocator, .{
    .limits = .{
        .max_memory = 16 * 1024 * 1024,
        .max_stack_values = 4096,
        .max_call_frames = 128,
        .max_instructions = 1_000_000,
        .max_file_bytes = 4 * 1024 * 1024,
    },
});
```

`max_instructions` is cumulative, counting instructions across all calls and coroutine resumes. You can check it with `instructionBudget` and start it over with `resetInstructionBudget`.

To limit a single call instead, pass `CallOptions` to `Function.callWith` or `Function.protectedCallWith`. Its `max_instructions` covers that call, including nested calls and any coroutines it resumes. When budgets nest, the tighter limit applies.

```zig
const result = try handler.protectedCallWith(.{event}, void, .{ .max_instructions = 100_000 });
```

`max_memory` bounds every allocation made through the state: parsing, compilation, runtime objects, API conversion, memory-file copies, and captured output. If the limit is too small to hold the requested libraries, initialization may return `error.OutOfMemory`.

Once a budget is exhausted, the script is done. `pcall` cannot catch the failure and keep it running.

### Interrupts

Budgets work well when you know the limit ahead of time. For deadlines measured in wall-clock time, use an interrupt. `interruptHandle` returns a small, copyable `InterruptHandle`, and another thread can call `interrupt()` on it to stop the running script:

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

Lua stops at its next safepoint (a loop back edge, a call, or a check inside long-running library functions), and the host call returns `error.Interrupted`. Like an exhausted budget, this cannot be caught by `pcall`.

The request is consumed when `error.Interrupted` reaches the host. If you want to drop a request that is still pending, call `clearInterrupt`.

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

`stepGc` performs up to the requested number of steps, and a count of zero also means one step. It returns `.complete` when a full cycle finishes and `.pending` otherwise; a generational minor collection returns `.pending`. Keep in mind that steps limit the amount of work requested, not elapsed time, so a large table or a finalizer can still take longer than expected.

To finish a full collection, including pending finalizers, call `collect()`. Both `collect` and `stepGc` work while automatic collection is stopped. You can stop and restart automatic collection with `stopGc()` and `restartGc()`, and `isGcRunning()` tells you which state it is in.

`deinit` closes the state the way `lua_close` does. It runs pending `__gc` finalizers, newest first, and closes open files. Errors in finalizers are ignored, and an `os.exit` inside one is dropped. `reset`, by contrast, runs no finalizers.

You can switch modes with `setGcMode` and tune collection with `setGcParam`. Both return the previous setting, and `gcMode` and `gcParam` read the current one. See [GcParams](api/runtime/types.md#type-gcparams) for parameter names, units, and defaults. Invalid parameter values return `error.InvalidGcParam`.

## Load and Run Code

For one-shot execution, use `doString` or `doFile`:

```zig
try lua.doString("answer = 21 * 2", .{ .name = "=setup" });
try lua.doFile("plugin.lua", .{ .name = "@plugin.lua" });
```

When you want to run the same chunk more than once, `loadString` and `loadFile` return a rooted `Function` you can call as often as you like:

```zig
var greet = try lua.loadString(
    "local name = ...; return 'hello, ' .. name",
    .{ .name = "=greet" },
);
defer greet.deinit();

const message = try greet.call(.{"host"}, []const u8);
```

A load can also run the chunk in its own environment table and restrict what kind of input it accepts:

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

The load modes are `.source_only`, `.binary_only`, and `.source_or_binary`.

### Binary Chunks

You can dump a loaded function to bytecode and load it back later, for example to cache compiled chunks. zlua bytecode is meant only for zlua-to-zlua use:

```zig
var chunk = try lua.loadString("return 40 + ...", .{ .name = "=cached" });
defer chunk.deinit();

const bytes = try chunk.dumpBytecode(.{ .strip_debug = true });
defer lua.allocator().free(bytes);

var cached = try lua.loadBytecode(bytes, .{});
defer cached.deinit();

const value = try cached.call(.{2}, i64);
```

The format is internal to zlua, can change between versions, and is not compatible with PUC Lua `luac` chunks.

Loading verifies a chunk's structure before it runs, so a malformed chunk cannot index outside its registers, constants, or code. That check does not make bytecode trustworthy, though. Run untrusted chunks with the same limits you would use for untrusted source.

## Values and Handles

Common Zig values convert to Lua automatically:

| Zig | Lua |
| --- | --- |
| `null` | `nil` |
| `bool` | boolean |
| integer / float | integer / number |
| byte slice | string |
| non-byte array or slice | array table |
| struct | table keyed by field name |
| `Table`, `Function`, `Ref`, `Value`, `Userdata(T)` | existing Lua value |

Going the other way, you always name the type you want back:

```zig
try lua.setGlobal("answer", 42);
const answer = try lua.getGlobal("answer", i64);
```

Multiple return values come back through `zlua.Tuple`:

```zig
var chunk = try lua.loadString("return true, 42, 'ok'", .{});
defer chunk.deinit();

const Result = zlua.Tuple(&.{ bool, i64, []const u8 });
var result = try chunk.call(.{}, Result);
defer result.deinit();
```

Handles keep Lua objects alive. `Table`, `Function`, `Coroutine`, `Ref`, userdata, and `ErrorRef` each own a registry root, as do values and tuples that contain them, so call `deinit` when you are finished with one. Assigning a handle into Lua does not consume your root, and you still need to release it.

When you don't know a value's type ahead of time, read it as a dynamic `zlua.Value`. It can represent nil, booleans, numbers, strings, tables, functions, coroutines, and userdata. Any other runtime-only value appears as `.unsupported`.

### Borrowed Strings

A `[]const u8` read from Lua (through `getGlobal`, `Table.get`, `Function.call`, `Context.arg`, and similar) points into Lua memory rather than being copied. It stays valid while Lua still references the string, but once nothing does, any call that may collect garbage can free it. Callback arguments stay valid until the callback returns, and `deinit` and `reset` invalidate every borrowed slice.

If you need to keep a string, copy it or read it as a `Ref`.

## Tables and Modules

Create a table with `createTable`, fill it in, and publish it as a global:

```zig
var config = try lua.createTable(.{ .hash_hint = 3 });
defer config.deinit();

try config.set("title", "demo");
try config.set("max_players", 8);
try lua.setGlobal("config", config);
```

`Table.get` and `Table.set` behave like Lua's `t[k]` and `t[k] = v`, including function metamethods. To bypass metamethods, use `rawGet`, `rawSet`, `rawLen`, `append`, `toSlice`, and `rawIterator`. `len()` is Lua's `#t`, and `setMetatable` ignores `__metatable` just as `lua_setmetatable` does.

To copy an array-like table into Zig, `toSlice(T, allocator)` reads the raw sequence `1..rawLen()` into a new slice:

```zig
const scores = try list.toSlice(i64, allocator);
defer allocator.free(scores);
```

A hole or an element of the wrong type returns `error.TypeMismatch`. Use `?T` as the element type if holes are allowed. If the elements are handles, deinitialize each one, and remember that string elements are [borrowed](#borrowed-strings).

There are two ways to iterate. `rawIterator()` works like `next`, and `pairs()` works like Lua's `pairs`:

```zig
var it = try inventory.pairs();
defer it.deinit();
while (try it.next()) |entry| {
    std.debug.print("{s} = {d}\n", .{ entry.key.string, entry.value.integer });
}
```

The iterator keeps the table and the current entry rooted, and it owns each `Entry` until the next call, so don't deinitialize entries yourself. During traversal you may assign to existing fields, but adding keys is undefined.

`Table.identity()` returns a state-local token for the table. It stays valid while the table is rooted, until the state is reset.

### Modules

There are two ways to make a module available to `require`. `setLoadedModule(name, module)` stores a value directly in `package.loaded[name]`. `preloadModule(name, loader)` instead installs a loader in `package.preload[name]`, which runs on the first `require(name)`. `preloadModuleFn` does the same with a Zig function as the loader:

```zig
fn openHost(ctx: *zlua.Context, name: []const u8) !zlua.Table {
    var module = try ctx.state().createModule(name);
    errdefer module.deinit();
    try module.set("version", 1);
    return module; // released after conversion
}

try lua.preloadModuleFn("host", openHost);

var host = try lua.require("host", zlua.Table); // runs openHost once
defer host.deinit();
```

From the host side, `State.require(name, T)` calls Lua's `require` and converts the result to `T`.

## Host Callbacks

`register` turns a Zig function into a Lua function. The callback receives a `Context`, which it uses to read arguments and return values:

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

Registered callbacks are native functions. Each registration has its own identity, `debug.getinfo` reports `what = "C"`, and there are no Lua upvalues or compiler-generated dispatcher globals behind them. They cannot be dumped with `string.dump`, and `Function.dumpBytecode` returns `error.TypeMismatch` for them. The callback name is kept, so argument errors can still mention it.

Use `ctx.optionalArg` for optional arguments and `ctx.raise` to raise a Lua error. When an argument fails to convert, the error includes the callback and argument it came from. A callback may also receive rooted `Table` or `Function` handles as arguments, and it must deinitialize them.

For simple functions, `registerTyped` skips the `Context` and converts parameters and return values for you:

```zig
fn clamp(value: f64, min: f64, max: f64) f64 {
    return @min(@max(value, min), max);
}

var clamp_fn = try lua.registerTyped("clamp", clamp);
defer clamp_fn.deinit();
try lua.setGlobal("clamp", clamp_fn);
```

A callback can call back into Lua with `Context.callNonYielding(function, args, R)`. The call runs on the callback's coroutine, within that coroutine's current instruction budget, and the Lua code is not allowed to yield. Lua errors propagate unchanged once cleanup, including `__close`, has run, and any effects that already completed stay in place. `Context.coroutineIdentity()` returns a token for the current coroutine that is valid only during the callback and is invalidated by reset.

## Calling and Errors

To call a Lua function from Zig, fetch it as a `Function` and call it:

```zig
try lua.doString("function add(a, b) return a + b end", .{});
var add = try lua.getGlobal("add", zlua.Function);
defer add.deinit();
const sum = try add.call(.{ 20, 22 }, i64);
```

`call` and the convenience APIs report Lua failures as `error.LuaError`. After that, `errorMessage` gives you an allocated copy of the message, and `takeErrorValue` hands you ownership of the rooted Lua error.

When a Lua failure is an expected outcome, `protectedCall` returns it as a value instead:

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

Set `CallOptions.traceback` to capture a traceback at the point where the error was raised:

```zig
const result = try run.protectedCallWith(.{}, void, .{ .traceback = true });
switch (result) {
    .ok => {},
    .lua_error => |error_ref| {
        var err = error_ref;
        defer err.deinit(); // also frees the traceback
        std.debug.print("{s}\n", .{err.traceback().?});
        // stack traceback:
        //     [C]: in global 'error'
        //     app.lua:2: in upvalue 'check'
        //     app.lua:6: in function <app.lua:5>
    },
}
```

If you want your own handler instead, `CallOptions.message_handler` takes a Lua `Function` and uses it with `xpcall` semantics.

When a script calls `error(nil)`, `ErrorRef.value` returns `.nil`.

## Coroutines

`newCoroutine(function)` creates a suspended coroutine without running it, and `resumeCoroutine(args, Yield, Return)` runs it until it yields or returns. On the first resume, `args` are passed to the function. On later resumes, they become the results of the pending yield. Use `Tuple` for multiple values and `void` to ignore them:

```zig
var chunk = try lua.loadString(
    \\coroutine.yield("show dialogue")
    \\return "story finished"
, .{ .name = "=story.lua" });
defer chunk.deinit();

var story = try lua.newCoroutine(chunk);
defer story.deinit();

while (try story.status() == .suspended) {
    var step = try story.resumeCoroutine(.{}, []const u8, []const u8);
    defer step.deinit();
    switch (step) {
        .yielded => |text| std.debug.print("yielded: {s}\n", .{text}),
        .returned => |text| std.debug.print("returned: {s}\n", .{text}),
    }
}
```

Always `switch` on the result rather than checking the tag and then reading a field, because the inactive field is undefined.

A few more things to know about coroutine handles:

- `status()` returns `.suspended`, `.running`, `.normal`, or `.dead`. Only suspended coroutines can be resumed.
- Lua failures return `error.LuaError`. Use `protectedResume` to receive the error as a value, as with `protectedCall`.
- Call `deinit` on each result to release its handles. Strings are borrowed VM slices, so copy any you need to keep.
- A conversion error leaves the coroutine wherever Lua stopped, and its side effects are not undone.
- `deinit` only drops the handle. If you are abandoning a suspended coroutine, call `close()` first to run its pending `__close` handlers. Use `protectedClose()` if you want to keep a Lua error raised during closing, and deinitialize the resulting `ErrorRef`.
- Coroutine handles behave like other handles. You can store them in globals and tables, pass them as arguments, or read them through `Value.coroutine`. Inside a callback, `ctx.coroutine()` returns the running coroutine.

### Yielding from Callbacks

A callback can suspend its coroutine with `return ctx.yield(values)`:

```zig
fn askUser(ctx: *zlua.Context) !void {
    const prompt = try ctx.arg(0, []const u8);
    return ctx.yield(.{prompt});
}
```

When Lua runs `local answer = ask_user("Open the door?")`, Zig receives the prompt as `.yielded`. Resuming with `.{"yes"}` then makes `ask_user` return `"yes"`. The callback's defers run before the coroutine suspends, and the Zig function is never reentered. Typed callbacks and userdata methods that return an error union can yield the same way.

Yields work through nested Lua calls, `pcall`, iterators, `__pairs`, and most metamethods. `ctx.isYieldable()` tells you whether the current callback can yield. A callback cannot yield when it runs under `Function.call`, `doString`, the main thread, `Context.callNonYielding`, `ipairs` reading `__index`, `close()`, or a finalizer.

Snapshots capture suspended threads, and each worker resumes its own copy. Reset restores the suspended state, but it cannot cancel work the host has already started. [`coroutine_story.zig`](../examples/coroutine_story.zig) runs both examples.

## Userdata

Userdata lets Lua hold Zig values. `newUserdata` stores a Zig value that Lua owns, while `newUserdataPtr` wraps storage the host owns. You can install methods explicitly:

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

To skip that step, `newUserdataAuto` and `newUserdataPtrAuto` bind the public functions whose first parameter is `*T` or `*const T`. Names beginning with `__` become metamethods, and other methods go on `__index`. `registerUserdataInitializerWith` creates a typed Lua constructor that returns auto-bound userdata.

Both `newUserdata` and `newUserdataPtr` accept a `finalizer` option. For Lua-owned userdata it runs before the storage is freed, and for host-owned storage it runs when the Lua wrapper is finalized. Callbacks can take either kind as a typed argument, such as `ctx.arg(0, *Counter)`.

To share one metatable between userdata from the same state, pass `.metatable = table` to `newUserdata` or `newUserdataPtr`, and install its methods before you share it. If construction fails, responsibility for finalizing the value stays with the host.

A `__gc` metamethod works on userdata the same way it does on tables. It runs before the host finalizer and the deinit hook.

Userdata equality uses `__eq`, while `rawequal` compares wrapper identity. `AnyUserdata.as(T)` checks that the payload has type `T` and returns a new rooted handle.

For custom iteration, define `__pairs`. It returns an iterator, a state, an initial key, and an optional closing value. `ipairs` needs no special method, since it uses `__index` to read integer keys from 1 until the first `nil`:

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

With `newUserdata`, register the metamethod explicitly: `try sequence.metamethod("__index", Sequence.__index);`. Auto-binding also picks up public `__pairs` methods with a pointer receiver. Lua `__pairs` functions can yield, but `__index` calls made by `ipairs` cannot. Zig fields are not enumerated automatically.

## Snapshots

Snapshots let you set up a state once and then create many independent workers from it. You configure a `State`, capture an immutable `Snapshot`, and create workers from that snapshot, each of which can be reset back to where it started:

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

Capturing copies the VM heap, including suspended Lua coroutines, shared references, module caches, I/O buffers, random state, and GC settings. Workers share the snapshot's immutable bytecode, while closures, caches, and other mutable VM objects stay private to each worker.

The point a state resets to is its baseline. Capturing a snapshot makes it the source state's active baseline, and `newState()` gives the new worker that same baseline. Reset restores options, host bindings, and instruction usage as well. Snapshots are reusable, can outlive the source state, and have no persistence format.

A fresh state has no baseline, so `reset()` returns `error.NoSnapshot` until `snapshot()` succeeds. Each state resets only to its own baseline. Capturing the state again installs a newer baseline, and older snapshots remain usable with `newState()`. Reset does not need a public `Snapshot` handle, because the state keeps its baseline even after every public handle is destroyed.

To switch a worker to a different template, construct the replacement state before releasing the old one. That way, if construction fails, the old state is still usable:

```zig
const replacement = try other_snapshot.newState(allocator);
old.deinit();
old = replacement;
```

Snapshot and reset require an idle VM. If a call is active, a collection is running, the state is being destroyed, or a snapshot operation is called recursively, they return `error.SnapshotBusy`. Runtime objects that zlua does not track return `error.SnapshotUnsupported`. You must externally serialize all use of each `State`, including reset and its rollback journal. Reset fails atomically, but that guarantee does not make a state safe to use concurrently.

Snapshots, unlike states, can be shared between threads. Independently owned `Snapshot` handles can share one immutable backing and call `newState()` concurrently to create independent mutable VMs. Get each additional handle with `snapshot.retain()` and move it to its owner; `deinit()` consumes only that handle. An arbitrary bit copy of a `Snapshot` is not an ownership retain. Each individual handle still needs external serialization against mutation or `deinit`, and you must keep a live owned handle throughout any `newState()` or `retain()` call. Each state resets only itself and retains its own baseline.

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

The source state and the original handle can also be destroyed before the workers finish.

### Reset and Lifetimes

A successful reset invalidates every earlier handle, along with borrowed VM slices and pointers. Operations on a stale handle return `error.InvalidHandle`, though calling `deinit` on one is harmless. After a reset, reacquire objects through globals or modules. Handles from other states are also rejected. As always, destroy handles before their state.

Resetting to the active baseline restores the objects that were modified and releases private allocations. Tables, closures, upvalues, and threads keep their worker-local addresses: the first write to an object copies its whole storage, and reset swaps the original storage back in. If the baseline is unchanged and there are no eager userdata hooks, reset needs no allocations and no heap traversal. Every eager-resource replacement that can fail is prepared before the rollback commits, so a failure leaves the current state, its handles, and its baseline usable.

When reset discards objects, it does not run Lua `__gc` or `__close` handlers, so run any application teardown first if you need it. Reset restores GC settings but not the progress of an in-flight collection cycle, so collections and finalizers may run at different points than they did before. Address-based strings, such as `tostring({})` or `%p` output, can also differ.

Memory accounting follows the worker. The destination state keeps its own allocator, and rollback records, retained worker storage, private copies, and new allocations all count against the worker's memory limit. Retained storage is not a Lua GC root, so weak reachability and normal finalization still operate on the live object graph. Because the GC byte estimate counts only live Lua objects, it can be smaller than actual allocator usage while rollback storage is retained.

Snapshot storage comes from `snapshot_allocator`. With a separate allocator, that storage is outside the worker limit. Passing `state.allocator()` instead charges snapshot storage to that state's limit and keeps that state's allocator infrastructure alive. Workers use the allocator you supply and inherit the captured limit. Host-owned results can still be freed through the state allocator while the state lives.

A successful capture or `newState()` retains the snapshot backing as the state's baseline, and reset uses that retained baseline without changing ownership. A worker also separately retains the owner of its borrowed bytecode, so capturing a modified worker does not invalidate its existing functions. `Snapshot.deinit` releases the public wrapper, and the backing storage is freed only after the last retaining state or handle releases it. This means `snapshot_allocator` has to stay valid for that entire lifetime, including after the wrapper is destroyed, and an arena used for snapshot storage must not be reset while any retaining state exists. In general, keep backing allocators valid until all allocations, including shared userdata, are released.

When owners live on different threads, the final destruction of the backing, of userdata, and of retained allocator infrastructure can happen on any of those threads. The allocators for these objects must therefore support allocation and free calls that overlap across threads, including freeing on a thread other than the one that allocated. Use a thread-safe allocator, or add allocator-level synchronization when you share one; a thread-confined arena does not provide that synchronization on its own. Worker-local allocators need no extra synchronization unless their storage is shared or exported. zlua's retained memory-limit allocator supports concurrent frees from shared owners, but allocation, resize, and state operations through `state.allocator()` stay with the state's owner, and the allocator underneath it must meet the same cross-thread lifetime requirements. There is no deferred reclamation on an owner thread.

### Userdata and Host Bindings

Userdata payloads are shared by default, so changes to a payload survive reset. A Lua-owned payload is finalized and freed once its last owner releases it, and a borrowed payload must outlive every state and snapshot that references it. zlua synchronizes the bookkeeping for shared payload lifetimes and finalizes or disposes each payload at most once. Synchronizing access to mutable host payloads, and owning any external resources, is still up to you.

If you want independent copies of a payload instead, supply a pair of hooks to `newUserdata` or `newUserdataPtr`:

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

`copy` must allocate all nested storage with the allocator it is given, and `dispose` releases that storage, including when construction fails or a snapshot is destroyed. Hooks must not hold on to source VM pointers or reenter snapshot operations.

Hooks may also run concurrently. When `newState()` or reset runs on different workers at the same time, `copy` can be called on the same pristine payload simultaneously, so hooks must allow concurrent reads of the source and synchronize any shared counters or host resources. `dispose` and finalizers can run on different owner threads and must support that; zlua does not serialize host hooks.

Capture and discard skip application finalizers, and normal finalizers must not free storage owned by `dispose`. Eager payloads, which are the default, keep their original ownership rules and call the copy hook on every reset.

Rather than copying on every reset, you can have zlua track an owned payload through scoped access by setting `.tracking = .scoped`:

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

Scope callbacks receive `(payload, context)`. Scoped payload pointers, including pointers to nested storage, must not escape the callback. A read scope forbids mutating anything reachable from the payload, including slice contents. Scope results must not contain pointers; to copy out a buffer, pass caller-owned output storage through the context. Overlapping read and write scopes on one payload return `error.ScopedAccessConflict`. While a scope is active, its userdata stays reachable, and capture or reset returns `error.SnapshotBusy`.

Typed callbacks and auto-bound methods open these scopes for you, using a read scope for `*const T` arguments and a mutable scope for `*T` arguments. Unscoped extraction through `ptr`, `getGlobal(..., *T)`, or `Context.arg(..., *T)` returns `error.ScopedAccessRequired`. Scoped tracking requires owned userdata, and `newUserdataPtr` rejects it because external aliases could change the borrowed storage without zlua noticing.

The first mutable scope copies the payload before exposing writable storage. If the callback fails, its writes stay and the payload remains dirty. Reset disposes of the private copy and restores the pristine storage, so scoped payloads that never changed need no copies at reset time. Finalization also preserves the pristine storage before calling the finalizer, so reset never brings back a resource instance that was already finalized. For scoped userdata, the `dispose` hook releases both the initial owned payload and any copies the hooks created, including nested storage. Normal finalizers must not release storage owned by `dispose`.

Callbacks and host capabilities remain external bindings, so they must stay valid. Reset cannot undo output already sent to the host or changes made outside the VM. During capture, the source state takes ownership of copies of borrowed stdin and read-only memory-file bytes. Reset restores state-owned memory files, input positions, captured output, host bindings, errors, options, and instruction usage. Host-result allocations and reusable host root capacity are kept separate from managed allocation cleanup.

Snapshots save GC settings and pending finalizers without running any cleanup callbacks. After a reset, generational collection focuses on allocations made since the snapshot, and objects from the snapshot are reclaimed by a later full collection once they are no longer reachable.

Reset still has costs. First writes, allocation-registry detachment, private-allocation cleanup, and eager external resources all have real costs, so look at the mutation and full-cycle benchmarks alongside the reset-only timings. Runtime setters take part in tracking, but direct writes to raw object storage cannot be tracked automatically.

## Current Boundaries

The current API has a few limits to be aware of:

- No stable raw runtime wrapper is exposed.
- A Zig callback cannot call Lua that yields and then continue running. `Context.yield` must be the callback's last action.
- Broad decoding of Lua tables into Zig structs is not implemented.
- There are no `callGlobal` convenience methods. Fetch a `Function` and call it instead.

The embedding examples under `examples/` cover scripts, library selection, callbacks, sandboxing, interrupts, bytecode, memory files, userdata, modules, and coroutines. Either of these commands builds and runs them:

```sh
zig build examples
just examples
```

`zig build ci` also compiles and runs the examples.
