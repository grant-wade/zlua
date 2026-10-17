# api.context

## Navigation

- [API Index](../README.md)
- Parent: [api](../api.md)

<details>
<summary>All documents</summary>

- [root](../root.md)
- [frontend](../frontend.md)
- [errors](../errors.md)
- [frontend.source](../frontend/source.md)
- [frontend.token](../frontend/token.md)
- [frontend.diagnostic](../frontend/diagnostic.md)
- [frontend.lexer](../frontend/lexer.md)
- [frontend.ast](../frontend/ast.md)
- [frontend.parser](../frontend/parser.md)
- [compile](../compile.md)
- [compile.resolver](../compile/resolver.md)
- [compile.bytecode](../compile/bytecode.md)
- [compile.proto](../compile/proto.md)
- [runtime.types](../runtime/types.md)
- [runtime](../runtime.md)
- [runtime.chunk](../runtime/chunk.md)
- [reflection](../reflection.md)
- [runtime.state](../runtime/state.md)
- [stdlib](../stdlib.md)
- [stdlib.base](../stdlib/base.md)
- [runtime.call](../runtime/call.md)
- [runtime.coroutine](../runtime/coroutine.md)
- [runtime.debug](../runtime/debug.md)
- [runtime.metatable](../runtime/metatable.md)
- [runtime.rollback](../runtime/rollback.md)
- [runtime.value](../runtime/value.md)
- [runtime.number_format](../runtime/number_format.md)
- [runtime.host](../runtime/host.md)
- [runtime.upvalue](../runtime/upvalue.md)
- [runtime.failure](../runtime/failure.md)
- [runtime.io](../runtime/io.md)
- [runtime.load](../runtime/load.md)
- [runtime.vm](../runtime/vm.md)
- [runtime.gc](../runtime/gc.md)
- [runtime.entry](../runtime/entry.md)
- [runtime.system](../runtime/system.md)
- [runtime.timezone](../runtime/timezone.md)
- [runtime.index](../runtime/index.md)
- [runtime.operators](../runtime/operators.md)
- [stdlib.table](../stdlib/table.md)
- [stdlib.string](../stdlib/string.md)
- [stdlib.math](../stdlib/math.md)
- [stdlib.utf8](../stdlib/utf8.md)
- [stdlib.coroutine](../stdlib/coroutine.md)
- [stdlib.debug](../stdlib/debug.md)
- [stdlib.io](../stdlib/io.md)
- [stdlib.static_strings](../stdlib/static_strings.md)
- [stdlib.os](../stdlib/os.md)
- [stdlib.package](../stdlib/package.md)
- [stdlib.json](../stdlib/json.md)
- [stdlib.zerde_lua](../stdlib/zerde_lua.md)
- [stdlib.toml](../stdlib/toml.md)
- [stdlib.msgpack](../stdlib/msgpack.md)
- [stdlib.csv](../stdlib/csv.md)
- [stdlib.fs](../stdlib/fs.md)
- [runtime.budget](../runtime/budget.md)
- [runtime.strings](../runtime/strings.md)
- [runtime.execute](../runtime/execute.md)
- [testing.process](../testing/process.md)
- [runtime.tests](../runtime/tests.md)
- [runtime.internal](../runtime/internal.md)
- [compile.compiler](../compile/compiler.md)
- [compile.fold](../compile/fold.md)
- [compile.disasm](../compile/disasm.md)
- [api](../api.md)
- [api.callbacks](../api/callbacks.md)
- [api.convert](../api/convert.md)
- [api.errors](../api/errors.md)
- [api.handle](../api/handle.md)
- [api.state](../api/state.md)
- [runtime.snapshot](../runtime/snapshot.md)
- [api.capabilities](../api/capabilities.md)
- [api.options](../api/options.md)
- [api.function](../api/function.md)
- [api.table](../api/table.md)
- [api.value](../api/value.md)
- [api.userdata](../api/userdata.md)
- [api.context](../api/context.md)
- [api.coroutine](../api/coroutine.md)
- [api.snapshot](../api/snapshot.md)
- [api.memory_limit](../api/memory_limit.md)
- [testing](../testing.md)
- [testing.clua](../testing/clua.md)
- [testing.bench_runner](../testing/bench_runner.md)
- [testing.bench.options](../testing/bench/options.md)
- [testing.bench.results](../testing/bench/results.md)
- [testing.bench.stats](../testing/bench/stats.md)
- [testing.bench.report](../testing/bench/report.md)
- [testing.bench.process](../testing/bench/process.md)
- [testing.bench.fixtures](../testing/bench/fixtures.md)
- [testing.bench.legacy_process](../testing/bench/legacy_process.md)
- [testing.bench.startup](../testing/bench/startup.md)
- [testing.bench.allocation](../testing/bench/allocation.md)
- [testing.bench.c_startup](../testing/bench/c_startup.md)
- [testing.bench.snapshots](../testing/bench/snapshots.md)
- [testing.bench.gc](../testing/bench/gc.md)
- [testing.diff_runner](../testing/diff_runner.md)
- [testing.fixtures](../testing/fixtures.md)
- [testing.expected_failures](../testing/expected_failures.md)
- [testing.metadata](../testing/metadata.md)
- [testing.normalizer](../testing/normalizer.md)
- [testing.extension_runner](../testing/extension_runner.md)
- [testing.official_suite](../testing/official_suite.md)

</details>

## Types

- [Context](#type-context)

<a id="type-context"></a>

## Context

Callback context for functions registered with `State.register`.

```zig
pub const Context = struct {
    lua: *State,
    raw: *runtime.ApiCallbackContext,
};
```

### Nested Declarations

| Name | Parameters | Return Type | Description |
| --- | --- | --- | --- |
| [state](#fn-context-state) | `self: *Context` | `*State` |  |
| [argCount](#fn-context-argcount) | `self: *Context` | `usize` |  |
| [arg](#fn-context-arg) | `self: *Context, index: usize, comptime T: type` | `!T` | A &#96;[]const u8&#96; argument borrows VM memory until the callback returns. |
| [optionalArg](#fn-context-optionalarg) | `self: *Context, index: usize, comptime T: type` | `!?T` | Returns null when absent or &#96;nil&#96;. |
| [pushReturn](#fn-context-pushreturn) | `self: *Context, value: anytype` | `!void` |  |
| [returnValues](#fn-context-returnvalues) | `self: *Context, values: anytype` | `!void` | Replaces callback returns; tuples like &#96;.{ a, b }&#96; return multiple values. |
| [raise](#fn-context-raise) | `self: *Context, value: anytype` | `error` | Raises &#96;value&#96; as the Lua error object. |
| [coroutine](#fn-context-coroutine) | `self: *Context` | `!Coroutine` | Rooted handle to this callback's coroutine, usable beyond the callback. |
| [isYieldable](#fn-context-isyieldable) | `self: *Context` | `bool` | Reports whether this callback can yield across the current native boundary. |
| [yield](#fn-context-yield) | `self: *Context, values: anytype` | `error` | Terminal yield: &#96;return ctx.yield(.{values});&#96;. Defers run before suspension; resume continues Lua with the resume arguments without reentering the Zig body. |
| [coroutineIdentity](#fn-context-coroutineidentity) | `self: *Context` | `usize` | Coroutine token valid only during this callback and until reset. |
| [callNonYielding](#fn-context-callnonyielding) | `self: *Context, function: Function, args: anytype, comptime R: type` | `!R` | Calls Lua on this coroutine within its budget; yielding is forbidden and errors propagate. |

<a id="fn-context-state"></a>

### Context.state

```zig
pub fn state(self: *Context) *State
```

References: [`Context`](#type-context)

<a id="fn-context-argcount"></a>

### Context.argCount

```zig
pub fn argCount(self: *Context) usize
```

References: [`Context`](#type-context)

<a id="fn-context-arg"></a>

### Context.arg

A `[]const u8` argument borrows VM memory until the callback returns.

```zig
pub fn arg(self: *Context, index: usize, comptime T: type) !T
```

References: [`Context`](#type-context)

<a id="fn-context-optionalarg"></a>

### Context.optionalArg

Returns null when absent or `nil`.

```zig
pub fn optionalArg(self: *Context, index: usize, comptime T: type) !?T
```

References: [`Context`](#type-context)

<a id="fn-context-pushreturn"></a>

### Context.pushReturn

```zig
pub fn pushReturn(self: *Context, value: anytype) !void
```

References: [`Context`](#type-context)

<a id="fn-context-returnvalues"></a>

### Context.returnValues

Replaces callback returns; tuples like `.{ a, b }` return multiple values.

```zig
pub fn returnValues(self: *Context, values: anytype) !void
```

References: [`Context`](#type-context)

<a id="fn-context-raise"></a>

### Context.raise

Raises `value` as the Lua error object.

```zig
pub fn raise(self: *Context, value: anytype) error{ LuaError, OutOfMemory, InvalidHandle }
```

References: [`Context`](#type-context)

<a id="fn-context-coroutine"></a>

### Context.coroutine

Rooted handle to this callback's coroutine, usable beyond the callback.

```zig
pub fn coroutine(self: *Context) !Coroutine
```

References: [`Context`](#type-context)

<a id="fn-context-isyieldable"></a>

### Context.isYieldable

Reports whether this callback can yield across the current native boundary.

```zig
pub fn isYieldable(self: *Context) bool
```

References: [`Context`](#type-context)

<a id="fn-context-yield"></a>

### Context.yield

Terminal yield: `return ctx.yield(.{values});`. Defers run before suspension; resume
continues Lua with the resume arguments without reentering the Zig body.

```zig
pub fn yield(self: *Context, values: anytype) error{ HostCallbackYield, LuaError, OutOfMemory, InvalidHandle }
```

References: [`Context`](#type-context)

<a id="fn-context-coroutineidentity"></a>

### Context.coroutineIdentity

Coroutine token valid only during this callback and until reset.

```zig
pub fn coroutineIdentity(self: *Context) usize
```

References: [`Context`](#type-context)

<a id="fn-context-callnonyielding"></a>

### Context.callNonYielding

Calls Lua on this coroutine within its budget; yielding is forbidden and errors propagate.

```zig
pub fn callNonYielding(self: *Context, function: Function, args: anytype, comptime R: type) !R
```

References: [`Context`](#type-context)

