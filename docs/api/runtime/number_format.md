# runtime.number_format

## Navigation

- [API Index](../README.md)
- Parent: [runtime](../runtime.md)

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
- [runtime.value](../runtime/value.md)
- [runtime.number_format](../runtime/number_format.md)
- [runtime.execute](../runtime/execute.md)
- [testing.process](../testing/process.md)
- [runtime.state](../runtime/state.md)
- [runtime.rollback](../runtime/rollback.md)
- [runtime.call](../runtime/call.md)
- [runtime.coroutine](../runtime/coroutine.md)
- [runtime.debug](../runtime/debug.md)
- [runtime.gc](../runtime/gc.md)
- [runtime.host](../runtime/host.md)
- [runtime.timezone](../runtime/timezone.md)
- [stdlib](../stdlib.md)
- [stdlib.base](../stdlib/base.md)
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
- [runtime.vm](../runtime/vm.md)
- [runtime.tests](../runtime/tests.md)
- [runtime.internal](../runtime/internal.md)
- [compile.compiler](../compile/compiler.md)
- [compile.fold](../compile/fold.md)
- [compile.disasm](../compile/disasm.md)
- [api](../api.md)
- [runtime.snapshot](../runtime/snapshot.md)
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

## Overview

Exact C `printf`-compatible float formatting and Lua's float-to-string conversion.
Where libcs disagree (`%a` rounding, subnormals, NaN sign), the target's libc is followed.

## Functions

- [formatFloat](#fn-formatfloat)
- [formatLuaFloat](#fn-formatluafloat)

## Types

- [Spec](#type-spec)

## Constants

- [max_formatted_len](#const-max_formatted_len)
- [max_lua_float_len](#const-max_lua_float_len)

<a id="type-spec"></a>

## Spec

A parsed conversion such as `%-+012.3e`.

```zig
pub const Spec = struct {
    /// One of `e E f g G a A`.
    conversion: u8,
    left_align: bool = false,
    force_sign: bool = false,
    space_sign: bool = false,
    alternate: bool = false,
    zero_pad: bool = false,
    width: usize = 0,
    precision: ?usize = null,
};
```

<a id="const-max_formatted_len"></a>

## max_formatted_len

Fits width and precision up to Lua's limit of 99; `%.99f` of the largest double needs 410.

```zig
pub const max_formatted_len = 512;
```

<a id="const-max_lua_float_len"></a>

## max_lua_float_len

Fits every `tostring` rendering of a float (`%.17g` plus `.0`).

```zig
pub const max_lua_float_len = 32;
```

<a id="fn-formatfloat"></a>

## formatFloat

Formats `value` like C `snprintf`, clamping width and precision to 99.

```zig
pub fn formatFloat(buffer: *[max_formatted_len]u8, spec: Spec, value: f64) []const u8
```

References: [`Spec`](#type-spec)

<a id="fn-formatluafloat"></a>

## formatLuaFloat

Converts a float like Lua's `tostring`: `%.15g`, or `%.17g` when needed to round-trip,
plus `.0` when it looks like an integer.

```zig
pub fn formatLuaFloat(buffer: *[max_lua_float_len]u8, value: f64) []const u8
```

