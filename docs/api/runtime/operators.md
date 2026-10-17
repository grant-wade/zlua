# runtime.operators

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

## Functions

- [lengthInteger](#fn-lengthinteger)
- [lengthToInteger](#fn-lengthtointeger)
- [concatRangeToRegister](#fn-concatrangetoregister)
- [finishConcatRange](#fn-finishconcatrange)
- [binaryOpToRegister](#fn-binaryoptoregister)
- [unaryOpToRegister](#fn-unaryoptoregister)
- [equalValuesToRegister](#fn-equalvaluestoregister)
- [compareValuesToRegister](#fn-comparevaluestoregister)
- [compareBranch](#fn-comparebranch)
- [jumpIfBranchResult](#fn-jumpifbranchresult)
- [lengthToRegister](#fn-lengthtoregister)
- [compareValues](#fn-comparevalues)
- [arithmeticVerb](#fn-arithmeticverb)
- [rawNumericBinaryOpFast](#fn-rawnumericbinaryopfast)
- [rawIntegerBitwiseOpFast](#fn-rawintegerbitwiseopfast)
- [equalityHasMetamethod](#fn-equalityhasmetamethod)
- [rawCompareBranchResult](#fn-rawcomparebranchresult)
- [floorModNumber](#fn-floormodnumber)
- [toBitwiseInteger](#fn-tobitwiseinteger)
- [isNumber](#fn-isnumber)
- [rawCompare](#fn-rawcompare)
- [lessThan](#fn-lessthan)

## Types

- [BinaryOp](#type-binaryop)
- [UnaryMetamethodOp](#type-unarymetamethodop)
- [CompareOp](#type-compareop)

<a id="fn-lengthinteger"></a>

## lengthInteger

Like `luaL_len`.

```zig
pub fn lengthInteger(self: *State, thread: *Thread, value: Value) !i64
```

<a id="fn-lengthtointeger"></a>

## lengthToInteger

```zig
pub fn lengthToInteger(self: *State, length: Value) !i64
```

<a id="fn-concatrangetoregister"></a>

## concatRangeToRegister

```zig
pub fn concatRangeToRegister(self: *State, thread: *Thread, op: bytecode.ConcatRange) !void
```

<a id="fn-finishconcatrange"></a>

## finishConcatRange

Like `luaV_concat`. Partial results stay in the operand slots so a yielding
`__concat` can resume.

```zig
pub fn finishConcatRange(self: *State, thread: *Thread, dest: usize, first: usize, count_in: usize) !void
```

<a id="fn-binaryoptoregister"></a>

## binaryOpToRegister

```zig
pub fn binaryOpToRegister(self: *State, thread: *Thread, op: bytecode.Binary, kind: BinaryOp) !void
```

References: [`BinaryOp`](#type-binaryop)

<a id="fn-unaryoptoregister"></a>

## unaryOpToRegister

```zig
pub fn unaryOpToRegister(self: *State, thread: *Thread, op: bytecode.Unary, kind: UnaryMetamethodOp) !void
```

References: [`UnaryMetamethodOp`](#type-unarymetamethodop)

<a id="fn-equalvaluestoregister"></a>

## equalValuesToRegister

```zig
pub fn equalValuesToRegister(self: *State, thread: *Thread, op: bytecode.Binary) !void
```

<a id="fn-comparevaluestoregister"></a>

## compareValuesToRegister

```zig
pub fn compareValuesToRegister(self: *State, thread: *Thread, op: bytecode.Binary, kind: CompareOp) !void
```

References: [`CompareOp`](#type-compareop)

<a id="fn-comparebranch"></a>

## compareBranch

```zig
pub fn compareBranch(self: *State, thread: *Thread, op: bytecode.CompareBranch) !void
```

<a id="fn-jumpifbranchresult"></a>

## jumpIfBranchResult

```zig
pub fn jumpIfBranchResult(self: *State, thread: *Thread, result: bool, jump_if_truthy: bool, offset: bytecode.JumpOffset) !void
```

<a id="fn-lengthtoregister"></a>

## lengthToRegister

```zig
pub fn lengthToRegister(self: *State, thread: *Thread, op: bytecode.Unary) !void
```

<a id="fn-comparevalues"></a>

## compareValues

```zig
pub fn compareValues(self: *State, thread: *Thread, lhs: Value, rhs: Value, op: CompareOp) !bool
```

References: [`CompareOp`](#type-compareop)

<a id="type-binaryop"></a>

## BinaryOp

```zig
pub const BinaryOp = enum {
    add,
    sub,
    mul,
    div,
    idiv,
    mod,
    pow,
    band,
    bor,
    bxor,
    shl,
    shr,
    concat,
};
```

<a id="type-unarymetamethodop"></a>

## UnaryMetamethodOp

```zig
pub const UnaryMetamethodOp = enum {
    unm,
    bnot,
};
```

<a id="type-compareop"></a>

## CompareOp

```zig
pub const CompareOp = enum {
    lt,
    le,
};
```

<a id="fn-arithmeticverb"></a>

## arithmeticVerb

```zig
pub fn arithmeticVerb(op: BinaryOp) []const u8
```

References: [`BinaryOp`](#type-binaryop)

<a id="fn-rawnumericbinaryopfast"></a>

## rawNumericBinaryOpFast

```zig
pub inline fn rawNumericBinaryOpFast(lhs: Value, rhs: Value, comptime op: BinaryOp) ?Value
```

References: [`BinaryOp`](#type-binaryop)

<a id="fn-rawintegerbitwiseopfast"></a>

## rawIntegerBitwiseOpFast

```zig
pub inline fn rawIntegerBitwiseOpFast(lhs: Value, rhs: Value, comptime op: BinaryOp) ?Value
```

References: [`BinaryOp`](#type-binaryop)

<a id="fn-equalityhasmetamethod"></a>

## equalityHasMetamethod

```zig
pub fn equalityHasMetamethod(lhs: Value, rhs: Value) bool
```

<a id="fn-rawcomparebranchresult"></a>

## rawCompareBranchResult

```zig
pub fn rawCompareBranchResult(lhs: Value, rhs: Value, op: bytecode.CompareBranchOp) ?bool
```

<a id="fn-floormodnumber"></a>

## floorModNumber

```zig
pub fn floorModNumber(left: f64, right: f64) f64
```

<a id="fn-tobitwiseinteger"></a>

## toBitwiseInteger

```zig
pub fn toBitwiseInteger(value: Value) ?i64
```

<a id="fn-isnumber"></a>

## isNumber

```zig
pub fn isNumber(value: Value) bool
```

<a id="fn-rawcompare"></a>

## rawCompare

```zig
pub fn rawCompare(lhs: Value, rhs: Value, op: CompareOp) ?bool
```

References: [`CompareOp`](#type-compareop)

<a id="fn-lessthan"></a>

## lessThan

```zig
pub fn lessThan(lhs: Value, rhs: Value) !bool
```

