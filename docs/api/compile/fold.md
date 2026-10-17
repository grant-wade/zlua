# compile.fold

## Navigation

- [API Index](../README.md)
- Parent: [compile](../compile.md)

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

Numeric constant folding, mirroring PUC Lua 5.5 `constfolding`/`validop`.
Erroring operations and NaN or zero float results are left to the VM.

## Functions

- [literal](#fn-literal)
- [foldsUnary](#fn-foldsunary)
- [foldsBinary](#fn-foldsbinary)
- [unary](#fn-unary)
- [binary](#fn-binary)
- [constant](#fn-constant)

## Types

- [Numeral](#type-numeral)

## Constants

- [render_buffer_len](#const-render_buffer_len)

<a id="type-numeral"></a>

## Numeral

```zig
pub const Numeral = union(enum) {
    integer: i64,
    number: f64,
};
```

<a id="const-render_buffer_len"></a>

## render_buffer_len

Large enough for any rendered i64 or shortest round-trip f64.

```zig
pub const render_buffer_len = 40;
```

<a id="fn-literal"></a>

## literal

```zig
pub fn literal(expr: *const ast.Expr) ?Numeral
```

References: [`Numeral`](#type-numeral)

<a id="fn-foldsunary"></a>

## foldsUnary

```zig
pub fn foldsUnary(op: ast.UnaryOp) bool
```

<a id="fn-foldsbinary"></a>

## foldsBinary

```zig
pub fn foldsBinary(op: ast.BinaryOp) bool
```

<a id="fn-unary"></a>

## unary

```zig
pub fn unary(op: ast.UnaryOp, operand: Numeral) ?Numeral
```

References: [`Numeral`](#type-numeral)

<a id="fn-binary"></a>

## binary

```zig
pub fn binary(op: ast.BinaryOp, lhs: Numeral, rhs: Numeral) ?Numeral
```

References: [`Numeral`](#type-numeral)

<a id="fn-constant"></a>

## constant

Renders a folded value in the lexeme form the VM's constant loader parses.

```zig
pub fn constant(buffer: *[render_buffer_len]u8, value: Numeral) bytecode.Constant
```

References: [`Numeral`](#type-numeral)

