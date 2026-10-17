# compile.proto

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

- [LineInfo](#type-lineinfo)
- [LocalDebug](#type-localdebug)
- [UpvalueDesc](#type-upvaluedesc)
- [ErrorOp](#type-errorop)
- [OperandOrigin](#type-operandorigin)
- [ErrorSite](#type-errorsite)
- [ErrorSiteEntry](#type-errorsiteentry)
- [Proto](#type-proto)

<a id="type-lineinfo"></a>

## LineInfo

```zig
pub const LineInfo = struct {
    line: usize,
};
```

<a id="type-localdebug"></a>

## LocalDebug

```zig
pub const LocalDebug = struct {
    name: []const u8,
    register: bytecode.Register,
    start_pc: usize,
    end_pc: usize = 0,
    to_close: bool = false,
};
```

<a id="type-upvaluedesc"></a>

## UpvalueDesc

```zig
pub const UpvalueDesc = struct {
    name: []const u8,
    in_stack: bool,
    index: u16,
};
```

<a id="type-errorop"></a>

## ErrorOp

```zig
pub const ErrorOp = enum {
    arithmetic,
    bitwise,
    concat,
    compare,
    call,
    index,
    newindex,
    length,
    numeric_for,
};
```

<a id="type-operandorigin"></a>

## OperandOrigin

```zig
pub const OperandOrigin = union(enum) {
    temporary,
    local: []const u8,
    upvalue: []const u8,
    global: []const u8,
    field: []const u8,
    method: []const u8,
    metamethod: []const u8,
    constant: []const u8,
};
```

<a id="type-errorsite"></a>

## ErrorSite

```zig
pub const ErrorSite = struct {
    line: usize,
    op: ErrorOp,
    operands: []const OperandOrigin = &.{},
    call_name: ?OperandOrigin = null,
};
```

<a id="type-errorsiteentry"></a>

## ErrorSiteEntry

```zig
pub const ErrorSiteEntry = struct {
    pc: usize,
    site: ErrorSite,
};
```

<a id="type-proto"></a>

## Proto

```zig
pub const Proto = struct {
    allocator: std.mem.Allocator,
    arena: std.heap.ArenaAllocator,
    constants: std.ArrayList(bytecode.Constant) = .empty,
    instructions: std.ArrayList(bytecode.Instruction) = .empty,
    line_info: std.ArrayList(LineInfo) = .empty,
    locals: std.ArrayList(LocalDebug) = .empty,
    upvalues: std.ArrayList(UpvalueDesc) = .empty,
    error_sites: std.ArrayList(ErrorSiteEntry) = .empty,
    children: std.ArrayList(*Proto) = .empty,
    max_registers: u16 = 0,
    param_count: u16 = 0,
    is_vararg: bool = false,
    named_vararg: bool = false,
    source_name: []const u8 = "zlua",
    debug_name: ?[]const u8 = null,
    defined_line: usize = 0,
    last_defined_line: usize = 0,
    has_to_close_locals: bool = false,
    /// Runtime metadata set once by `prepareProtoTree`; prepared prototypes are immutable
    /// and shareable. Defaults select the general VM paths.
    runtime_prepared: bool = false,
    named_vararg_readonly: bool = false,
    /// No to-be-closed locals and a last opcode that stops dispatch, so the fast loop may run it.
    fast_loop_entry: bool = false,
    /// `fast_loop_entry` with fixed parameters, so calls need not capture varargs.
    fast_loop_call: bool = false,
    /// Decoded constants indexed like `constants`; `.string` slots are per-State via the closure cache.
    constant_values: []const RuntimeValue = &.{},
};
```

### Nested Declarations

| Name | Parameters | Return Type | Description |
| --- | --- | --- | --- |
| [init](#fn-proto-init) | `allocator: std.mem.Allocator` | `Proto` |  |
| [deinit](#fn-proto-deinit) | `self: *Proto` | `void` |  |
| [pc](#fn-proto-pc) | `self: Proto` | `usize` |  |
| [hasReadOnlyNamedVararg](#fn-proto-hasreadonlynamedvararg) | `self: *const Proto` | `bool` | True when the named vararg is never written, captured, or escaped, so reads can use the argument slice. |
| [emit](#fn-proto-emit) | `self: *Proto, instruction: bytecode.Instruction, line: usize` | `!usize` |  |
| [patchJump](#fn-proto-patchjump) | `self: *Proto, index: usize, target_pc: usize` | `!void` |  |
| [addConstant](#fn-proto-addconstant) | `self: *Proto, constant: bytecode.Constant` | `!bytecode.ConstantIndex` | Linear-time deduplicating insert; the compiler uses &#96;appendConstant&#96; with its own index. |
| [appendConstant](#fn-proto-appendconstant) | `self: *Proto, constant: bytecode.Constant` | `!bytecode.ConstantIndex` | Appends an owned copy without searching for an existing entry. |
| [addLocal](#fn-proto-addlocal) | `self: *Proto, local: LocalDebug` | `!usize` |  |
| [addUpvalue](#fn-proto-addupvalue) | `self: *Proto, upvalue: UpvalueDesc` | `!bytecode.UpvalueIndex` |  |
| [addChild](#fn-proto-addchild) | `self: *Proto, child: *Proto` | `!bytecode.ProtoIndex` |  |
| [addErrorSite](#fn-proto-adderrorsite) | `self: *Proto, pc_index: usize, site: ErrorSite` | `!void` |  |
| [errorSiteAt](#fn-proto-errorsiteat) | `self: Proto, pc_index: usize` | `?ErrorSite` |  |
| [setDebugName](#fn-proto-setdebugname) | `self: *Proto, name: []const u8` | `!void` |  |

<a id="fn-proto-init"></a>

### Proto.init

```zig
pub fn init(allocator: std.mem.Allocator) Proto
```

References: [`Proto`](#type-proto)

<a id="fn-proto-deinit"></a>

### Proto.deinit

```zig
pub fn deinit(self: *Proto) void
```

References: [`Proto`](#type-proto)

<a id="fn-proto-pc"></a>

### Proto.pc

```zig
pub fn pc(self: Proto) usize
```

References: [`Proto`](#type-proto)

<a id="fn-proto-hasreadonlynamedvararg"></a>

### Proto.hasReadOnlyNamedVararg

True when the named vararg is never written, captured, or escaped, so reads can use the argument slice.

```zig
pub fn hasReadOnlyNamedVararg(self: *const Proto) bool
```

References: [`Proto`](#type-proto)

<a id="fn-proto-emit"></a>

### Proto.emit

```zig
pub fn emit(self: *Proto, instruction: bytecode.Instruction, line: usize) !usize
```

References: [`Proto`](#type-proto)

<a id="fn-proto-patchjump"></a>

### Proto.patchJump

```zig
pub fn patchJump(self: *Proto, index: usize, target_pc: usize) !void
```

References: [`Proto`](#type-proto)

<a id="fn-proto-addconstant"></a>

### Proto.addConstant

Linear-time deduplicating insert; the compiler uses `appendConstant` with its own index.

```zig
pub fn addConstant(self: *Proto, constant: bytecode.Constant) !bytecode.ConstantIndex
```

References: [`Proto`](#type-proto)

<a id="fn-proto-appendconstant"></a>

### Proto.appendConstant

Appends an owned copy without searching for an existing entry.

```zig
pub fn appendConstant(self: *Proto, constant: bytecode.Constant) !bytecode.ConstantIndex
```

References: [`Proto`](#type-proto)

<a id="fn-proto-addlocal"></a>

### Proto.addLocal

```zig
pub fn addLocal(self: *Proto, local: LocalDebug) !usize
```

References: [`Proto`](#type-proto), [`LocalDebug`](#type-localdebug)

<a id="fn-proto-addupvalue"></a>

### Proto.addUpvalue

```zig
pub fn addUpvalue(self: *Proto, upvalue: UpvalueDesc) !bytecode.UpvalueIndex
```

References: [`Proto`](#type-proto), [`UpvalueDesc`](#type-upvaluedesc)

<a id="fn-proto-addchild"></a>

### Proto.addChild

```zig
pub fn addChild(self: *Proto, child: *Proto) !bytecode.ProtoIndex
```

References: [`Proto`](#type-proto)

<a id="fn-proto-adderrorsite"></a>

### Proto.addErrorSite

```zig
pub fn addErrorSite(self: *Proto, pc_index: usize, site: ErrorSite) !void
```

References: [`Proto`](#type-proto), [`ErrorSite`](#type-errorsite)

<a id="fn-proto-errorsiteat"></a>

### Proto.errorSiteAt

```zig
pub fn errorSiteAt(self: Proto, pc_index: usize) ?ErrorSite
```

References: [`Proto`](#type-proto), [`ErrorSite`](#type-errorsite)

<a id="fn-proto-setdebugname"></a>

### Proto.setDebugName

```zig
pub fn setDebugName(self: *Proto, name: []const u8) !void
```

References: [`Proto`](#type-proto)

