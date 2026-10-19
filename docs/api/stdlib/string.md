# stdlib.string

## Navigation

- [API Index](../README.md)
- Parent: [stdlib](../stdlib.md)
- Submodules: [stdlib.string.format](../stdlib/string/format.md), [stdlib.string.pack](../stdlib/string/pack.md), [stdlib.string.pattern](../stdlib/string/pattern.md)

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
- [stdlib.static_strings](../stdlib/static_strings.md)
- [runtime.table_index](../runtime/table_index.md)
- [runtime.value](../runtime/value.md)
- [runtime.number_format](../runtime/number_format.md)
- [runtime.coroutine](../runtime/coroutine.md)
- [runtime.debug](../runtime/debug.md)
- [runtime.metatable](../runtime/metatable.md)
- [runtime.rollback](../runtime/rollback.md)
- [runtime.strings](../runtime/strings.md)
- [runtime.operators](../runtime/operators.md)
- [runtime.failure](../runtime/failure.md)
- [runtime.io](../runtime/io.md)
- [runtime.host](../runtime/host.md)
- [runtime.load](../runtime/load.md)
- [runtime.vm](../runtime/vm.md)
- [runtime.gc](../runtime/gc.md)
- [runtime.entry](../runtime/entry.md)
- [runtime.system](../runtime/system.md)
- [runtime.timezone](../runtime/timezone.md)
- [runtime.upvalue](../runtime/upvalue.md)
- [runtime.index](../runtime/index.md)
- [stdlib.table](../stdlib/table.md)
- [stdlib.string](../stdlib/string.md)
- [stdlib.string.format](../stdlib/string/format.md)
- [stdlib.string.pack](../stdlib/string/pack.md)
- [stdlib.string.pattern](../stdlib/string/pattern.md)
- [stdlib.math](../stdlib/math.md)
- [stdlib.utf8](../stdlib/utf8.md)
- [stdlib.coroutine](../stdlib/coroutine.md)
- [stdlib.debug](../stdlib/debug.md)
- [stdlib.io](../stdlib/io.md)
- [stdlib.os](../stdlib/os.md)
- [stdlib.package](../stdlib/package.md)
- [stdlib.json](../stdlib/json.md)
- [stdlib.zerde_lua](../stdlib/zerde_lua.md)
- [stdlib.toml](../stdlib/toml.md)
- [stdlib.msgpack](../stdlib/msgpack.md)
- [stdlib.csv](../stdlib/csv.md)
- [stdlib.fs](../stdlib/fs.md)
- [runtime.budget](../runtime/budget.md)
- [runtime.object_pool](../runtime/object_pool.md)
- [runtime.execute](../runtime/execute.md)
- [testing.process](../testing/process.md)
- [runtime.tests](../runtime/tests.md)
- [runtime.internal](../runtime/internal.md)
- [runtime.native_fn](../runtime/native_fn.md)
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
- [testing.bench.system](../testing/bench/system.md)
- [testing.diff_runner](../testing/diff_runner.md)
- [testing.fixtures](../testing/fixtures.md)
- [testing.expected_failures](../testing/expected_failures.md)
- [testing.metadata](../testing/metadata.md)
- [testing.normalizer](../testing/normalizer.md)
- [testing.parallel](../testing/parallel.md)
- [testing.extension_runner](../testing/extension_runner.md)
- [testing.official_suite](../testing/official_suite.md)

</details>

## Functions

- [byte](#fn-byte)
- [char](#fn-char)
- [dump](#fn-dump)
- [find](#fn-find)
- [gmatch](#fn-gmatch)
- [gmatchIter](#fn-gmatchiter)
- [gmatchNext](#fn-gmatchnext)
- [gsub](#fn-gsub)
- [len](#fn-len)
- [lower](#fn-lower)
- [match](#fn-match)
- [rep](#fn-rep)
- [reverse](#fn-reverse)
- [rsplit](#fn-rsplit)
- [split](#fn-split)
- [strip](#fn-strip)
- [sub](#fn-sub)
- [upper](#fn-upper)

## Types

- [GmatchValues](#type-gmatchvalues)

## Aliases

- [format](#alias-format)
- [pack](#alias-pack)
- [packsize](#alias-packsize)
- [unpack](#alias-unpack)

<a id="alias-format"></a>

## format

```zig
pub const format = format_mod.format;
```

<a id="alias-pack"></a>

## pack

```zig
pub const pack = pack_mod.pack;
```

<a id="alias-packsize"></a>

## packsize

```zig
pub const packsize = pack_mod.packsize;
```

<a id="alias-unpack"></a>

## unpack

```zig
pub const unpack = pack_mod.unpack;
```

<a id="fn-byte"></a>

## byte

```zig
pub fn byte(state: *State, thread: *Thread, op: bytecode.Call) !void
```

<a id="fn-char"></a>

## char

```zig
pub fn char(state: *State, thread: *Thread, op: bytecode.Call) !void
```

<a id="fn-dump"></a>

## dump

```zig
pub fn dump(state: *State, thread: *Thread, op: bytecode.Call) !void
```

<a id="fn-find"></a>

## find

```zig
pub fn find(state: *State, thread: *Thread, op: bytecode.Call) !void
```

<a id="fn-gmatch"></a>

## gmatch

```zig
pub fn gmatch(state: *State, thread: *Thread, op: bytecode.Call) !void
```

<a id="fn-gmatchiter"></a>

## gmatchIter

```zig
pub fn gmatchIter(state: *State, thread: *Thread, op: bytecode.Call) !void
```

<a id="type-gmatchvalues"></a>

## GmatchValues

Captures (or the whole match) of one `string.gmatch` step; empty when exhausted.

```zig
pub const GmatchValues = struct {
    buffer: [pattern_mod.max_captures]Value = undefined,
    len: usize = 0,
};
```

### Nested Declarations

| Name | Parameters | Return Type | Description |
| --- | --- | --- | --- |
| [slice](#fn-gmatchvalues-slice) | `self: *const GmatchValues` | `[]const Value` |  |

<a id="fn-gmatchvalues-slice"></a>

### GmatchValues.slice

```zig
pub fn slice(self: *const GmatchValues) []const Value
```

References: [`GmatchValues`](#type-gmatchvalues)

<a id="fn-gmatchnext"></a>

## gmatchNext

```zig
pub fn gmatchNext(state: *State, state_value: Value) !GmatchValues
```

References: [`GmatchValues`](#type-gmatchvalues)

<a id="fn-gsub"></a>

## gsub

```zig
pub fn gsub(state: *State, thread: *Thread, op: bytecode.Call) !void
```

<a id="fn-len"></a>

## len

```zig
pub fn len(state: *State, thread: *Thread, op: bytecode.Call) !void
```

<a id="fn-lower"></a>

## lower

```zig
pub fn lower(state: *State, thread: *Thread, op: bytecode.Call) !void
```

<a id="fn-match"></a>

## match

```zig
pub fn match(state: *State, thread: *Thread, op: bytecode.Call) !void
```

<a id="fn-rep"></a>

## rep

```zig
pub fn rep(state: *State, thread: *Thread, op: bytecode.Call) !void
```

<a id="fn-reverse"></a>

## reverse

```zig
pub fn reverse(state: *State, thread: *Thread, op: bytecode.Call) !void
```

<a id="fn-rsplit"></a>

## rsplit

Like `split`, but splits from the right.

```zig
pub fn rsplit(state: *State, thread: *Thread, op: bytecode.Call) !void
```

<a id="fn-split"></a>

## split

Splits on the separator, or ASCII whitespace when omitted, up to an optional maximum count.

```zig
pub fn split(state: *State, thread: *Thread, op: bytecode.Call) !void
```

<a id="fn-strip"></a>

## strip

Trims ASCII whitespace, or bytes in the optional character set.

```zig
pub fn strip(state: *State, thread: *Thread, op: bytecode.Call) !void
```

<a id="fn-sub"></a>

## sub

```zig
pub fn sub(state: *State, thread: *Thread, op: bytecode.Call) !void
```

<a id="fn-upper"></a>

## upper

```zig
pub fn upper(state: *State, thread: *Thread, op: bytecode.Call) !void
```

