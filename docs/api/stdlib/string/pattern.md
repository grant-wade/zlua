# stdlib.string.pattern

## Navigation

- [API Index](../../README.md)
- Parent: [stdlib.string](../../stdlib/string.md)

<details>
<summary>All documents</summary>

- [root](../../root.md)
- [frontend](../../frontend.md)
- [errors](../../errors.md)
- [frontend.source](../../frontend/source.md)
- [frontend.token](../../frontend/token.md)
- [frontend.diagnostic](../../frontend/diagnostic.md)
- [frontend.lexer](../../frontend/lexer.md)
- [frontend.ast](../../frontend/ast.md)
- [frontend.parser](../../frontend/parser.md)
- [compile](../../compile.md)
- [compile.resolver](../../compile/resolver.md)
- [compile.bytecode](../../compile/bytecode.md)
- [compile.proto](../../compile/proto.md)
- [runtime.types](../../runtime/types.md)
- [runtime](../../runtime.md)
- [runtime.chunk](../../runtime/chunk.md)
- [reflection](../../reflection.md)
- [runtime.state](../../runtime/state.md)
- [stdlib](../../stdlib.md)
- [stdlib.base](../../stdlib/base.md)
- [runtime.call](../../runtime/call.md)
- [runtime.coroutine](../../runtime/coroutine.md)
- [runtime.debug](../../runtime/debug.md)
- [runtime.metatable](../../runtime/metatable.md)
- [runtime.rollback](../../runtime/rollback.md)
- [runtime.value](../../runtime/value.md)
- [runtime.number_format](../../runtime/number_format.md)
- [runtime.table_index](../../runtime/table_index.md)
- [runtime.host](../../runtime/host.md)
- [runtime.upvalue](../../runtime/upvalue.md)
- [runtime.failure](../../runtime/failure.md)
- [runtime.io](../../runtime/io.md)
- [runtime.load](../../runtime/load.md)
- [runtime.vm](../../runtime/vm.md)
- [runtime.gc](../../runtime/gc.md)
- [runtime.entry](../../runtime/entry.md)
- [runtime.system](../../runtime/system.md)
- [runtime.timezone](../../runtime/timezone.md)
- [runtime.index](../../runtime/index.md)
- [runtime.operators](../../runtime/operators.md)
- [stdlib.table](../../stdlib/table.md)
- [stdlib.string](../../stdlib/string.md)
- [stdlib.string.format](../../stdlib/string/format.md)
- [stdlib.string.pack](../../stdlib/string/pack.md)
- [stdlib.string.pattern](../../stdlib/string/pattern.md)
- [stdlib.math](../../stdlib/math.md)
- [stdlib.utf8](../../stdlib/utf8.md)
- [stdlib.coroutine](../../stdlib/coroutine.md)
- [stdlib.debug](../../stdlib/debug.md)
- [stdlib.io](../../stdlib/io.md)
- [stdlib.static_strings](../../stdlib/static_strings.md)
- [stdlib.os](../../stdlib/os.md)
- [stdlib.package](../../stdlib/package.md)
- [stdlib.json](../../stdlib/json.md)
- [stdlib.zerde_lua](../../stdlib/zerde_lua.md)
- [stdlib.toml](../../stdlib/toml.md)
- [stdlib.msgpack](../../stdlib/msgpack.md)
- [stdlib.csv](../../stdlib/csv.md)
- [stdlib.fs](../../stdlib/fs.md)
- [runtime.budget](../../runtime/budget.md)
- [runtime.strings](../../runtime/strings.md)
- [runtime.execute](../../runtime/execute.md)
- [testing.process](../../testing/process.md)
- [runtime.tests](../../runtime/tests.md)
- [runtime.internal](../../runtime/internal.md)
- [runtime.native_fn](../../runtime/native_fn.md)
- [runtime.address_index](../../runtime/address_index.md)
- [compile.compiler](../../compile/compiler.md)
- [compile.fold](../../compile/fold.md)
- [compile.disasm](../../compile/disasm.md)
- [api](../../api.md)
- [api.callbacks](../../api/callbacks.md)
- [api.convert](../../api/convert.md)
- [api.errors](../../api/errors.md)
- [api.handle](../../api/handle.md)
- [api.state](../../api/state.md)
- [runtime.snapshot](../../runtime/snapshot.md)
- [api.capabilities](../../api/capabilities.md)
- [api.options](../../api/options.md)
- [api.function](../../api/function.md)
- [api.table](../../api/table.md)
- [api.value](../../api/value.md)
- [api.userdata](../../api/userdata.md)
- [api.context](../../api/context.md)
- [api.coroutine](../../api/coroutine.md)
- [api.snapshot](../../api/snapshot.md)
- [api.memory_limit](../../api/memory_limit.md)
- [testing](../../testing.md)
- [testing.clua](../../testing/clua.md)
- [testing.bench_runner](../../testing/bench_runner.md)
- [testing.bench.options](../../testing/bench/options.md)
- [testing.bench.results](../../testing/bench/results.md)
- [testing.bench.stats](../../testing/bench/stats.md)
- [testing.bench.report](../../testing/bench/report.md)
- [testing.bench.process](../../testing/bench/process.md)
- [testing.bench.fixtures](../../testing/bench/fixtures.md)
- [testing.bench.legacy_process](../../testing/bench/legacy_process.md)
- [testing.bench.startup](../../testing/bench/startup.md)
- [testing.bench.allocation](../../testing/bench/allocation.md)
- [testing.bench.c_startup](../../testing/bench/c_startup.md)
- [testing.bench.snapshots](../../testing/bench/snapshots.md)
- [testing.bench.gc](../../testing/bench/gc.md)
- [testing.diff_runner](../../testing/diff_runner.md)
- [testing.fixtures](../../testing/fixtures.md)
- [testing.expected_failures](../../testing/expected_failures.md)
- [testing.metadata](../../testing/metadata.md)
- [testing.normalizer](../../testing/normalizer.md)
- [testing.parallel](../../testing/parallel.md)
- [testing.extension_runner](../../testing/extension_runner.md)
- [testing.official_suite](../../testing/official_suite.md)

</details>

## Functions

- [patternHasSpecials](#fn-patternhasspecials)
- [patternHasMagic](#fn-patternhasmagic)
- [plainFind](#fn-plainfind)
- [simplePatternFind](#fn-simplepatternfind)
- [unanchoredPatternFind](#fn-unanchoredpatternfind)
- [invalidCaptureIndex](#fn-invalidcaptureindex)
- [firstMatchValue](#fn-firstmatchvalue)
- [appendMatchValues](#fn-appendmatchvalues)
- [appendCaptureValues](#fn-appendcapturevalues)
- [captureValue](#fn-capturevalue)

## Types

- [Match](#type-match)

## Constants

- [max_captures](#const-max_captures)

<a id="const-max_captures"></a>

## max_captures

```zig
pub const max_captures = 32;
```

<a id="type-match"></a>

## Match

```zig
pub const Match = struct {
    range: MatchRange,
    captures: CaptureState,
};
```

<a id="fn-patternhasspecials"></a>

## patternHasSpecials

```zig
pub fn patternHasSpecials(pattern: []const u8) bool
```

<a id="fn-patternhasmagic"></a>

## patternHasMagic

```zig
pub fn patternHasMagic(pattern: []const u8) bool
```

<a id="fn-plainfind"></a>

## plainFind

```zig
pub fn plainFind(source: []const u8, pattern: []const u8, start: usize) ?Match
```

References: [`Match`](#type-match)

<a id="fn-simplepatternfind"></a>

## simplePatternFind

```zig
pub fn simplePatternFind(state: *State, source: []const u8, pattern: []const u8, start: usize) !?Match
```

References: [`Match`](#type-match)

<a id="fn-unanchoredpatternfind"></a>

## unanchoredPatternFind

```zig
pub fn unanchoredPatternFind(state: *State, source: []const u8, pattern: []const u8, start: usize) !?Match
```

References: [`Match`](#type-match)

<a id="fn-invalidcaptureindex"></a>

## invalidCaptureIndex

```zig
pub fn invalidCaptureIndex(state: *State, one_based: u8) !void
```

<a id="fn-firstmatchvalue"></a>

## firstMatchValue

```zig
pub fn firstMatchValue(state: *State, source: []const u8, matched: Match) !Value
```

References: [`Match`](#type-match)

<a id="fn-appendmatchvalues"></a>

## appendMatchValues

```zig
pub fn appendMatchValues(state: *State, values: *std.ArrayList(Value), source: []const u8, matched: Match) !void
```

References: [`Match`](#type-match)

<a id="fn-appendcapturevalues"></a>

## appendCaptureValues

```zig
pub fn appendCaptureValues(state: *State, values: *std.ArrayList(Value), source: []const u8, captures: CaptureState) !void
```

<a id="fn-capturevalue"></a>

## captureValue

```zig
pub fn captureValue(state: *State, source: []const u8, slot: CaptureSlot) !Value
```

