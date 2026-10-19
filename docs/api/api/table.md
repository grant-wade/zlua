# api.table

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

## Types

- [Table](#type-table)

<a id="type-table"></a>

## Table

Rooted handle to a Lua table.

```zig
pub const Table = struct {
    ref: Ref,
};
```

### Nested Declarations

| Name | Parameters | Return Type | Description |
| --- | --- | --- | --- |
| [deinit](#fn-table-deinit) | `self: *Table` | `void` |  |
| [get](#fn-table-get) | `self: Table, key: anytype, comptime T: type` | `!T` | Reads &#96;t[key]&#96; honoring &#96;__index&#96;; metamethods cannot yield and fail with &#96;error.LuaError&#96;. A &#96;[]const u8&#96; result borrows VM memory; see &#96;Value.string&#96;. |
| [set](#fn-table-set) | `self: Table, key: anytype, value: anytype` | `!void` | Assigns &#96;t[key]&#96; honoring &#96;__newindex&#96;; metamethods cannot yield. A nil or NaN key returns &#96;error.LuaError&#96;. |
| [rawSet](#fn-table-rawset) | `self: Table, key: anytype, value: anytype` | `!void` | Like &#96;set&#96; without &#96;__newindex&#96;; a nil or NaN key returns &#96;error.LuaError&#96;. |
| [append](#fn-table-append) | `self: Table, value: anytype` | `!void` | Raw-appends at &#96;rawLen() + 1&#96;; appending nil is a no-op. |
| [len](#fn-table-len) | `self: Table` | `!i64` | Lua &#96;#t&#96; honoring &#96;__len&#96;, which cannot yield; a non-integer result returns &#96;error.LuaError&#96;. |
| [rawLen](#fn-table-rawlen) | `self: Table` | `!i64` |  |
| [identity](#fn-table-identity) | `self: Table` | `!usize` | State-local, non-retaining token valid while rooted and until reset. |
| [getMetatable](#fn-table-getmetatable) | `self: Table` | `!?Table` | Ignores &#96;__metatable&#96;. The caller must &#96;deinit&#96; the result. |
| [setMetatable](#fn-table-setmetatable) | `self: Table, metatable: ?Table` | `!void` | Sets or removes the metatable, ignoring &#96;__metatable&#96; like &#96;lua_setmetatable&#96;. |
| [rawGet](#fn-table-rawget) | `self: Table, key: anytype, comptime T: type` | `!T` | A &#96;[]const u8&#96; result borrows VM memory; see &#96;Value.string&#96;. |
| [toSlice](#fn-table-toslice) | `self: Table, comptime T: type, allocator: std.mem.Allocator` | `![]T` | Reads raw entries &#96;1..rawLen()&#96;; holes fail with &#96;error.TypeMismatch&#96; unless &#96;T&#96; is optional. The caller frees the slice and deinits handle elements; string elements borrow VM memory. |
| [Entry](#type-table-entry) |  |  | String fields borrow VM memory; see &#96;Value.string&#96;. |
| [rawNext](#fn-table-rawnext) | `self: Table, key: anytype` | `!?Entry` | Lua &#96;next&#96;: start with null or &#96;.nil&#96;; deinit each entry. Prefer &#96;rawIterator&#96;. |
| [rawIterator](#fn-table-rawiterator) | `self: Table` | `!Iterator` | Raw-entry iterator like Lua &#96;next&#96;; the caller must &#96;deinit&#96; it. Existing fields may be assigned or cleared during traversal; adding keys is undefined. |
| [pairs](#fn-table-pairs) | `self: Table` | `!Iterator` | Iterator like Lua &#96;pairs(t)&#96;, honoring &#96;__pairs&#96;; its calls cannot yield. A closing value gets &#96;__close&#96; when iteration ends, fails, or &#96;close&#96; is called, but not on &#96;deinit&#96;. |
| [Iterator](#type-table-iterator) |  |  | Owns each returned &#96;Entry&#96; until the next &#96;next&#96;, &#96;close&#96;, or &#96;deinit&#96;; do not deinit entries. Reset invalidates the iterator. |

<a id="fn-table-deinit"></a>

### Table.deinit

```zig
pub fn deinit(self: *Table) void
```

References: [`Table`](#type-table)

<a id="fn-table-get"></a>

### Table.get

Reads `t[key]` honoring `__index`; metamethods cannot yield and fail with `error.LuaError`.
A `[]const u8` result borrows VM memory; see `Value.string`.

```zig
pub fn get(self: Table, key: anytype, comptime T: type) !T
```

References: [`Table`](#type-table)

<a id="fn-table-set"></a>

### Table.set

Assigns `t[key]` honoring `__newindex`; metamethods cannot yield.
A nil or NaN key returns `error.LuaError`.

```zig
pub fn set(self: Table, key: anytype, value: anytype) !void
```

References: [`Table`](#type-table)

<a id="fn-table-rawset"></a>

### Table.rawSet

Like `set` without `__newindex`; a nil or NaN key returns `error.LuaError`.

```zig
pub fn rawSet(self: Table, key: anytype, value: anytype) !void
```

References: [`Table`](#type-table)

<a id="fn-table-append"></a>

### Table.append

Raw-appends at `rawLen() + 1`; appending nil is a no-op.

```zig
pub fn append(self: Table, value: anytype) !void
```

References: [`Table`](#type-table)

<a id="fn-table-len"></a>

### Table.len

Lua `#t` honoring `__len`, which cannot yield; a non-integer result returns `error.LuaError`.

```zig
pub fn len(self: Table) !i64
```

References: [`Table`](#type-table)

<a id="fn-table-rawlen"></a>

### Table.rawLen

```zig
pub fn rawLen(self: Table) !i64
```

References: [`Table`](#type-table)

<a id="fn-table-identity"></a>

### Table.identity

State-local, non-retaining token valid while rooted and until reset.

```zig
pub fn identity(self: Table) !usize
```

References: [`Table`](#type-table)

<a id="fn-table-getmetatable"></a>

### Table.getMetatable

Ignores `__metatable`. The caller must `deinit` the result.

```zig
pub fn getMetatable(self: Table) !?Table
```

References: [`Table`](#type-table)

<a id="fn-table-setmetatable"></a>

### Table.setMetatable

Sets or removes the metatable, ignoring `__metatable` like `lua_setmetatable`.

```zig
pub fn setMetatable(self: Table, metatable: ?Table) !void
```

References: [`Table`](#type-table)

<a id="fn-table-rawget"></a>

### Table.rawGet

A `[]const u8` result borrows VM memory; see `Value.string`.

```zig
pub fn rawGet(self: Table, key: anytype, comptime T: type) !T
```

References: [`Table`](#type-table)

<a id="fn-table-toslice"></a>

### Table.toSlice

Reads raw entries `1..rawLen()`; holes fail with `error.TypeMismatch` unless `T` is optional.
The caller frees the slice and deinits handle elements; string elements borrow VM memory.

```zig
pub fn toSlice(self: Table, comptime T: type, allocator: std.mem.Allocator) ![]T
```

References: [`Table`](#type-table)

<a id="type-table-entry"></a>

### Table.Entry

String fields borrow VM memory; see `Value.string`.

```zig
pub const Entry = struct {
    key: Value,
    value: Value,
};
```

#### Nested Declarations

| Name | Parameters | Return Type | Description |
| --- | --- | --- | --- |
| [deinit](#fn-entry-deinit) | `self: *Entry` | `void` | Only for &#96;rawNext&#96; entries; &#96;Iterator&#96; owns the entries it returns. |

<a id="fn-entry-deinit"></a>

#### Entry.deinit

Only for `rawNext` entries; `Iterator` owns the entries it returns.

```zig
pub fn deinit(self: *Entry) void
```

References: [`Entry`](#type-table-entry)

<a id="fn-table-rawnext"></a>

### Table.rawNext

Lua `next`: start with null or `.nil`; deinit each entry. Prefer `rawIterator`.

```zig
pub fn rawNext(self: Table, key: anytype) !?Entry
```

References: [`Table`](#type-table), [`Entry`](#type-table-entry)

<a id="fn-table-rawiterator"></a>

### Table.rawIterator

Raw-entry iterator like Lua `next`; the caller must `deinit` it. Existing fields may be
assigned or cleared during traversal; adding keys is undefined.

```zig
pub fn rawIterator(self: Table) !Iterator
```

References: [`Table`](#type-table), [`Iterator`](#type-table-iterator)

<a id="fn-table-pairs"></a>

### Table.pairs

[Iterator](#type-table-iterator) like Lua `pairs(t)`, honoring `__pairs`; its calls cannot yield. A closing value
gets `__close` when iteration ends, fails, or `close` is called, but not on `deinit`.

```zig
pub fn pairs(self: Table) !Iterator
```

References: [`Table`](#type-table), [`Iterator`](#type-table-iterator)

<a id="type-table-iterator"></a>

### Table.Iterator

Owns each returned `Entry` until the next `next`, `close`, or `deinit`; do not deinit entries.
Reset invalidates the iterator.

```zig
pub const Iterator = struct {
    state: *State,
    generation: u64,
    mode: Mode,
    roots: [slot_count]?usize = @splat(null),
    entry: ?Entry = null,
    done: bool = false,
};
```

#### Nested Declarations

| Name | Parameters | Return Type | Description |
| --- | --- | --- | --- |
| [next](#fn-iterator-next) | `self: *Iterator` | `!?Entry` | Returns the next entry, or null at the end; the previous entry is released first. |
| [close](#fn-iterator-close) | `self: *Iterator` | `!void` | Ends traversal early, running a pending closing value like &#96;break&#96;; still call &#96;deinit&#96;. |
| [deinit](#fn-iterator-deinit) | `self: *Iterator` | `void` | Releases roots without calling Lua. |

<a id="fn-iterator-next"></a>

#### Iterator.next

Returns the next entry, or null at the end; the previous entry is released first.

```zig
pub fn next(self: *Iterator) !?Entry
```

References: [`Iterator`](#type-table-iterator), [`Entry`](#type-table-entry)

<a id="fn-iterator-close"></a>

#### Iterator.close

Ends traversal early, running a pending closing value like `break`; still call `deinit`.

```zig
pub fn close(self: *Iterator) !void
```

References: [`Iterator`](#type-table-iterator)

<a id="fn-iterator-deinit"></a>

#### Iterator.deinit

Releases roots without calling Lua.

```zig
pub fn deinit(self: *Iterator) void
```

References: [`Iterator`](#type-table-iterator)

