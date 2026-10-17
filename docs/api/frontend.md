# frontend

## Navigation

- [API Index](README.md)
- Submodules: [frontend.source](frontend/source.md), [frontend.token](frontend/token.md), [frontend.diagnostic](frontend/diagnostic.md), [frontend.lexer](frontend/lexer.md), [frontend.ast](frontend/ast.md), [frontend.parser](frontend/parser.md)

<details>
<summary>All documents</summary>

- [root](root.md)
- [frontend](frontend.md)
- [errors](errors.md)
- [frontend.source](frontend/source.md)
- [frontend.token](frontend/token.md)
- [frontend.diagnostic](frontend/diagnostic.md)
- [frontend.lexer](frontend/lexer.md)
- [frontend.ast](frontend/ast.md)
- [frontend.parser](frontend/parser.md)
- [compile](compile.md)
- [compile.resolver](compile/resolver.md)
- [compile.bytecode](compile/bytecode.md)
- [compile.proto](compile/proto.md)
- [runtime.types](runtime/types.md)
- [runtime](runtime.md)
- [runtime.chunk](runtime/chunk.md)
- [reflection](reflection.md)
- [runtime.state](runtime/state.md)
- [stdlib](stdlib.md)
- [stdlib.base](stdlib/base.md)
- [runtime.call](runtime/call.md)
- [runtime.coroutine](runtime/coroutine.md)
- [runtime.debug](runtime/debug.md)
- [runtime.metatable](runtime/metatable.md)
- [runtime.rollback](runtime/rollback.md)
- [runtime.value](runtime/value.md)
- [runtime.number_format](runtime/number_format.md)
- [runtime.table_index](runtime/table_index.md)
- [runtime.host](runtime/host.md)
- [runtime.upvalue](runtime/upvalue.md)
- [runtime.failure](runtime/failure.md)
- [runtime.io](runtime/io.md)
- [runtime.load](runtime/load.md)
- [runtime.vm](runtime/vm.md)
- [runtime.gc](runtime/gc.md)
- [runtime.entry](runtime/entry.md)
- [runtime.system](runtime/system.md)
- [runtime.timezone](runtime/timezone.md)
- [runtime.index](runtime/index.md)
- [runtime.operators](runtime/operators.md)
- [stdlib.table](stdlib/table.md)
- [stdlib.string](stdlib/string.md)
- [stdlib.string.format](stdlib/string/format.md)
- [stdlib.string.pack](stdlib/string/pack.md)
- [stdlib.string.pattern](stdlib/string/pattern.md)
- [stdlib.math](stdlib/math.md)
- [stdlib.utf8](stdlib/utf8.md)
- [stdlib.coroutine](stdlib/coroutine.md)
- [stdlib.debug](stdlib/debug.md)
- [stdlib.io](stdlib/io.md)
- [stdlib.static_strings](stdlib/static_strings.md)
- [stdlib.os](stdlib/os.md)
- [stdlib.package](stdlib/package.md)
- [stdlib.json](stdlib/json.md)
- [stdlib.zerde_lua](stdlib/zerde_lua.md)
- [stdlib.toml](stdlib/toml.md)
- [stdlib.msgpack](stdlib/msgpack.md)
- [stdlib.csv](stdlib/csv.md)
- [stdlib.fs](stdlib/fs.md)
- [runtime.budget](runtime/budget.md)
- [runtime.strings](runtime/strings.md)
- [runtime.execute](runtime/execute.md)
- [testing.process](testing/process.md)
- [runtime.tests](runtime/tests.md)
- [runtime.internal](runtime/internal.md)
- [runtime.native_fn](runtime/native_fn.md)
- [runtime.address_index](runtime/address_index.md)
- [compile.compiler](compile/compiler.md)
- [compile.fold](compile/fold.md)
- [compile.disasm](compile/disasm.md)
- [api](api.md)
- [api.callbacks](api/callbacks.md)
- [api.convert](api/convert.md)
- [api.errors](api/errors.md)
- [api.handle](api/handle.md)
- [api.state](api/state.md)
- [runtime.snapshot](runtime/snapshot.md)
- [api.capabilities](api/capabilities.md)
- [api.options](api/options.md)
- [api.function](api/function.md)
- [api.table](api/table.md)
- [api.value](api/value.md)
- [api.userdata](api/userdata.md)
- [api.context](api/context.md)
- [api.coroutine](api/coroutine.md)
- [api.snapshot](api/snapshot.md)
- [api.memory_limit](api/memory_limit.md)
- [testing](testing.md)
- [testing.clua](testing/clua.md)
- [testing.bench_runner](testing/bench_runner.md)
- [testing.bench.options](testing/bench/options.md)
- [testing.bench.results](testing/bench/results.md)
- [testing.bench.stats](testing/bench/stats.md)
- [testing.bench.report](testing/bench/report.md)
- [testing.bench.process](testing/bench/process.md)
- [testing.bench.fixtures](testing/bench/fixtures.md)
- [testing.bench.legacy_process](testing/bench/legacy_process.md)
- [testing.bench.startup](testing/bench/startup.md)
- [testing.bench.allocation](testing/bench/allocation.md)
- [testing.bench.c_startup](testing/bench/c_startup.md)
- [testing.bench.snapshots](testing/bench/snapshots.md)
- [testing.bench.gc](testing/bench/gc.md)
- [testing.diff_runner](testing/diff_runner.md)
- [testing.fixtures](testing/fixtures.md)
- [testing.expected_failures](testing/expected_failures.md)
- [testing.metadata](testing/metadata.md)
- [testing.normalizer](testing/normalizer.md)
- [testing.parallel](testing/parallel.md)
- [testing.extension_runner](testing/extension_runner.md)
- [testing.official_suite](testing/official_suite.md)

</details>

## Functions

- [lex](#fn-lex)
- [parse](#fn-parse)
- [parseWithDiagnostic](#fn-parsewithdiagnostic)

## Aliases

- [Lexer](#alias-lexer)
- [Token](#alias-token)
- [TokenTag](#alias-tokentag)
- [Ast](#alias-ast)

## Imports

- [source](#import-source) `@import("frontend/source.zig")`
- [diagnostic](#import-diagnostic) `@import("frontend/diagnostic.zig")`
- [token](#import-token) `@import("frontend/token.zig")`
- [lexer](#import-lexer) `@import("frontend/lexer.zig")`
- [ast](#import-ast) `@import("frontend/ast.zig")`
- [parser](#import-parser) `@import("frontend/parser.zig")`

<a id="import-source"></a>

## source

```zig
pub const source = @import("frontend/source.zig");
```

<a id="import-diagnostic"></a>

## diagnostic

```zig
pub const diagnostic = @import("frontend/diagnostic.zig");
```

<a id="import-token"></a>

## token

```zig
pub const token = @import("frontend/token.zig");
```

<a id="import-lexer"></a>

## lexer

```zig
pub const lexer = @import("frontend/lexer.zig");
```

<a id="import-ast"></a>

## ast

```zig
pub const ast = @import("frontend/ast.zig");
```

<a id="import-parser"></a>

## parser

```zig
pub const parser = @import("frontend/parser.zig");
```

<a id="alias-lexer"></a>

## Lexer

```zig
pub const Lexer = lexer.Lexer;
```

References: [`lexer.Lexer`](frontend/lexer.md#type-lexer)

<a id="alias-token"></a>

## Token

```zig
pub const Token = token.Token;
```

References: [`token.Token`](frontend/token.md#type-token)

<a id="alias-tokentag"></a>

## TokenTag

```zig
pub const TokenTag = token.Tag;
```

References: [`token.Tag`](frontend/token.md#type-tag)

<a id="alias-ast"></a>

## Ast

```zig
pub const Ast = ast.Ast;
```

References: [`ast.Ast`](frontend/ast.md#type-ast)

<a id="fn-lex"></a>

## lex

```zig
pub fn lex(allocator: std.mem.Allocator, source_text: []const u8) ![]Token
```

References: [`Token`](#alias-token)

<a id="fn-parse"></a>

## parse

```zig
pub fn parse(allocator: std.mem.Allocator, source_text: []const u8) !Ast
```

References: [`Ast`](#alias-ast)

<a id="fn-parsewithdiagnostic"></a>

## parseWithDiagnostic

```zig
pub fn parseWithDiagnostic(allocator: std.mem.Allocator, source_text: []const u8, error_diagnostic: *?errors.Diagnostic) !Ast
```

References: [`errors.Diagnostic`](errors.md#type-diagnostic), [`Ast`](#alias-ast)

