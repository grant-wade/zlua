# compile.bytecode

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
- [stack_guard](../stack_guard.md)
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
- [runtime.budget](../runtime/budget.md)
- [runtime.failure](../runtime/failure.md)
- [runtime.debug](../runtime/debug.md)
- [runtime.io](../runtime/io.md)
- [runtime.host](../runtime/host.md)
- [runtime.value](../runtime/value.md)
- [runtime.number_format](../runtime/number_format.md)
- [stdlib.static_strings](../stdlib/static_strings.md)
- [runtime.table_index](../runtime/table_index.md)
- [runtime.metatable](../runtime/metatable.md)
- [runtime.rollback](../runtime/rollback.md)
- [runtime.strings](../runtime/strings.md)
- [runtime.operators](../runtime/operators.md)
- [runtime.vm](../runtime/vm.md)
- [runtime.gc](../runtime/gc.md)
- [runtime.entry](../runtime/entry.md)
- [runtime.coroutine](../runtime/coroutine.md)
- [runtime.load](../runtime/load.md)
- [runtime.upvalue](../runtime/upvalue.md)
- [runtime.system](../runtime/system.md)
- [runtime.timezone](../runtime/timezone.md)
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
- [api.analyze](../api/analyze.md)
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
- [api.decode](../api/decode.md)
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
- [testing.sandbox_runner](../testing/sandbox_runner.md)
- [testing.generators](../testing/generators.md)

</details>

## Functions

- [constantEql](#fn-constanteql)
- [Branch](#fn-branch)

## Types

- [Constant](#type-constant)
- [Instruction](#type-instruction)
- [LoadBool](#type-loadbool)
- [LoadConst](#type-loadconst)
- [Move](#type-move)
- [GlobalAccess](#type-globalaccess)
- [GlobalDeclare](#type-globaldeclare)
- [UpvalueAccess](#type-upvalueaccess)
- [TableAccess](#type-tableaccess)
- [TableSet](#type-tableset)
- [ArraySet](#type-arrayset)
- [FieldAccess](#type-fieldaccess)
- [FieldSet](#type-fieldset)
- [MethodAccess](#type-methodaccess)
- [UpvalueFieldAccess](#type-upvaluefieldaccess)
- [UpvalueFieldSet](#type-upvaluefieldset)
- [IndexAccess](#type-indexaccess)
- [IndexSet](#type-indexset)
- [FieldSetConstant](#type-fieldsetconstant)
- [NewTable](#type-newtable)
- [SetList](#type-setlist)
- [Unary](#type-unary)
- [Binary](#type-binary)
- [BinaryConstant](#type-binaryconstant)
- [ConcatRange](#type-concatrange)
- [CompareBranchOp](#type-comparebranchop)
- [CompareBranch](#type-comparebranch)
- [CompareBranchConstant](#type-comparebranchconstant)
- [CompareConstantOp](#type-compareconstantop)
- [Test](#type-test)
- [TestSet](#type-testset)
- [Call](#type-call)
- [CallInstruction](#type-callinstruction)
- [Return](#type-return)
- [Vararg](#type-vararg)
- [Closure](#type-closure)
- [ForLoop](#type-forloop)
- [GenericFor](#type-genericfor)

## Constants

- [multret_count](#const-multret_count)
- [multret_arg_count](#const-multret_arg_count)
- [set_list_multret](#const-set_list_multret)

## Aliases

- [Register](#alias-register)
- [ConstantIndex](#alias-constantindex)
- [ProtoIndex](#alias-protoindex)
- [UpvalueIndex](#alias-upvalueindex)
- [LocalIndex](#alias-localindex)
- [JumpOffset](#alias-jumpoffset)
- [BranchOffset](#alias-branchoffset)

<a id="alias-register"></a>

## Register

```zig
pub const Register = u8;
```

<a id="alias-constantindex"></a>

## ConstantIndex

```zig
pub const ConstantIndex = u32;
```

<a id="alias-protoindex"></a>

## ProtoIndex

```zig
pub const ProtoIndex = u32;
```

<a id="alias-upvalueindex"></a>

## UpvalueIndex

```zig
pub const UpvalueIndex = u8;
```

<a id="alias-localindex"></a>

## LocalIndex

```zig
pub const LocalIndex = u16;
```

<a id="alias-jumpoffset"></a>

## JumpOffset

```zig
pub const JumpOffset = i32;
```

<a id="alias-branchoffset"></a>

## BranchOffset

Jump offset stored in a `Branch`.

```zig
pub const BranchOffset = i28;
```

<a id="const-multret_count"></a>

## multret_count

```zig
pub const multret_count: u16 = std.math.maxInt(u16);
```

<a id="const-multret_arg_count"></a>

## multret_arg_count

```zig
pub const multret_arg_count: u32 = std.math.maxInt(u32);
```

<a id="const-set_list_multret"></a>

## set_list_multret

`SetList.count` when the values end with multiple results.

```zig
pub const set_list_multret: u8 = std.math.maxInt(u8);
```

<a id="type-constant"></a>

## Constant

```zig
pub const Constant = union(enum) {
    nil,
    boolean: bool,
    integer: []const u8,
    number: []const u8,
    string: []const u8,
};
```

<a id="fn-constanteql"></a>

## constantEql

```zig
pub fn constantEql(lhs: Constant, rhs: Constant) bool
```

References: [`Constant`](#type-constant)

<a id="type-instruction"></a>

## Instruction

```zig
pub const Instruction = union(enum(u8)) {
    load_nil: Register,
    load_bool: LoadBool,
    load_const: LoadConst,
    move: Move,
    get_global: GlobalAccess,
    set_global: GlobalAccess,
    declare_global: GlobalDeclare,
    get_upvalue: UpvalueAccess,
    set_upvalue: UpvalueAccess,
    get_table: TableAccess,
    set_table: TableSet,
    set_array: ArraySet,
    get_field: FieldAccess,
    set_field: FieldSet,
    new_table: NewTable,
    set_list: SetList,
    add: Binary,
    sub: Binary,
    mul: Binary,
    div: Binary,
    idiv: Binary,
    mod: Binary,
    pow: Binary,
    unm: Unary,
    band: Binary,
    bor: Binary,
    bxor: Binary,
    bnot: Unary,
    shl: Binary,
    shr: Binary,
    eq: Binary,
    lt: Binary,
    le: Binary,
    not: Unary,
    len: Unary,
    concat: Binary,
    jmp: JumpOffset align(1),
    compare_branch: CompareBranch,
    test_op: Test,
    test_set: TestSet,
    call: CallInstruction,
    tail_call: CallInstruction,
    ret: Return,
    vararg: Vararg,
    closure: Closure,
    close: Register,
    check_close: Register,
    close_tbc: Register,
    for_prep: ForLoop,
    for_loop: ForLoop,
    tfor_prep: GenericFor,
    tfor_call: GenericFor,
    tfor_loop: GenericFor,
    concat_range: ConcatRange,
    add_k: BinaryConstant,
    sub_k: BinaryConstant,
    mul_k: BinaryConstant,
    div_k: BinaryConstant,
    idiv_k: BinaryConstant,
    mod_k: BinaryConstant,
    band_k: BinaryConstant,
    bor_k: BinaryConstant,
    bxor_k: BinaryConstant,
    shl_k: BinaryConstant,
    shr_k: BinaryConstant,
    compare_branch_k: CompareBranchConstant,
    get_method: MethodAccess,
    get_upvalue_field: UpvalueFieldAccess,
    set_upvalue_field: UpvalueFieldSet,
    get_index: IndexAccess,
    set_index: IndexSet,
    set_field_k: FieldSetConstant,
};
```

### Nested Declarations

| Name | Parameters | Return Type | Description |
| --- | --- | --- | --- |
| [jumpOffset](#fn-instruction-jumpoffset) | `self: Instruction` | `?JumpOffset` | The jump offset of a jumping instruction, or null. |
| [setJumpOffset](#fn-instruction-setjumpoffset) | `self: *Instruction, offset: JumpOffset` | `error` | The instruction must carry a jump offset. |

<a id="fn-instruction-jumpoffset"></a>

### Instruction.jumpOffset

The jump offset of a jumping instruction, or null.

```zig
pub fn jumpOffset(self: Instruction) ?JumpOffset
```

References: [`Instruction`](#type-instruction), [`JumpOffset`](#alias-jumpoffset)

<a id="fn-instruction-setjumpoffset"></a>

### Instruction.setJumpOffset

The instruction must carry a jump offset.

```zig
pub fn setJumpOffset(self: *Instruction, offset: JumpOffset) error{JumpOutOfRange}!void
```

References: [`Instruction`](#type-instruction), [`JumpOffset`](#alias-jumpoffset)

<a id="type-loadbool"></a>

## LoadBool

```zig
pub const LoadBool = struct {
    dest: Register,
    value: bool,
};
```

<a id="type-loadconst"></a>

## LoadConst

```zig
pub const LoadConst = struct {
    dest: Register,
    constant: ConstantIndex align(1),
};
```

<a id="type-move"></a>

## Move

```zig
pub const Move = struct {
    dest: Register,
    source: Register,
};
```

<a id="type-globalaccess"></a>

## GlobalAccess

```zig
pub const GlobalAccess = struct {
    register: Register,
    name: ConstantIndex align(1),
};
```

<a id="type-globaldeclare"></a>

## GlobalDeclare

```zig
pub const GlobalDeclare = struct {
    table: Register,
    value: Register,
    name: ConstantIndex align(1),
};
```

<a id="type-upvalueaccess"></a>

## UpvalueAccess

```zig
pub const UpvalueAccess = struct {
    register: Register,
    upvalue: UpvalueIndex,
};
```

<a id="type-tableaccess"></a>

## TableAccess

```zig
pub const TableAccess = struct {
    dest: Register,
    table: Register,
    key: Register,
};
```

<a id="type-tableset"></a>

## TableSet

```zig
pub const TableSet = struct {
    table: Register,
    key: Register,
    value: Register,
};
```

<a id="type-arrayset"></a>

## ArraySet

```zig
pub const ArraySet = struct {
    table: Register,
    index: u32 align(1),
    value: Register,
};
```

<a id="type-fieldaccess"></a>

## FieldAccess

```zig
pub const FieldAccess = struct {
    dest: Register,
    table: Register,
    name: ConstantIndex align(1),
};
```

<a id="type-fieldset"></a>

## FieldSet

```zig
pub const FieldSet = struct {
    table: Register,
    name: ConstantIndex align(1),
    value: Register,
};
```

<a id="type-methodaccess"></a>

## MethodAccess

Loads `table[name]` into `dest` and `table` into `dest + 1`.

```zig
pub const MethodAccess = struct {
    dest: Register,
    table: Register,
    name: ConstantIndex align(1),
};
```

<a id="type-upvaluefieldaccess"></a>

## UpvalueFieldAccess

```zig
pub const UpvalueFieldAccess = struct {
    dest: Register,
    upvalue: UpvalueIndex,
    name: ConstantIndex align(1),
};
```

<a id="type-upvaluefieldset"></a>

## UpvalueFieldSet

```zig
pub const UpvalueFieldSet = struct {
    upvalue: UpvalueIndex,
    name: ConstantIndex align(1),
    value: Register,
};
```

<a id="type-indexaccess"></a>

## IndexAccess

Reads `table[index]` for an integer constant `index`.

```zig
pub const IndexAccess = struct {
    dest: Register,
    table: Register,
    index: u32 align(1),
};
```

<a id="type-indexset"></a>

## IndexSet

```zig
pub const IndexSet = struct {
    table: Register,
    index: u32 align(1),
    value: Register,
};
```

<a id="type-fieldsetconstant"></a>

## FieldSetConstant

Assigns constant `constant` to `table[name]`.

```zig
pub const FieldSetConstant = struct {
    table: Register,
    name: ConstantIndex align(1),
    constant: u16 align(1),
};
```

<a id="type-newtable"></a>

## NewTable

Creates a table in `dest`, which is above every live register of the frame.

```zig
pub const NewTable = struct {
    dest: Register,
    array_hint: u32 align(1) = 0,
    hash_hint: u16 align(1) = 0,
};
```

<a id="type-setlist"></a>

## SetList

```zig
pub const SetList = struct {
    table: Register,
    first: Register,
    /// `set_list_multret` when the values end with multiple results.
    count: u8,
    start_index: u32 align(1),
};
```

<a id="type-unary"></a>

## Unary

```zig
pub const Unary = struct {
    dest: Register,
    source: Register,
};
```

<a id="type-binary"></a>

## Binary

```zig
pub const Binary = struct {
    dest: Register,
    left: Register,
    right: Register,
};
```

<a id="type-binaryconstant"></a>

## BinaryConstant

`left` op a numeric constant.

```zig
pub const BinaryConstant = struct {
    dest: Register,
    left: Register,
    constant: ConstantIndex align(1),
};
```

<a id="type-concatrange"></a>

## ConcatRange

Concatenates `count` (at least 2) registers from `first` right to left into `dest`,
like PUC OP_CONCAT. Operand registers are scratch space.

```zig
pub const ConcatRange = struct {
    dest: Register,
    first: Register,
    count: u16 align(1),
};
```

<a id="type-comparebranchop"></a>

## CompareBranchOp

```zig
pub const CompareBranchOp = enum(u3) {
    eq,
    lt,
    le,
};
```

<a id="fn-branch"></a>

## Branch

A comparison and the jump taken when its result equals `jump_if_truthy`.

```zig
pub fn Branch(comptime Op: type) type
```

<a id="type-comparebranch"></a>

## CompareBranch

```zig
pub const CompareBranch = struct {
    left: Register,
    right: Register,
    branch: Branch(CompareBranchOp) align(1),
};
```

<a id="type-comparebranchconstant"></a>

## CompareBranchConstant

Compares a register with a numeric constant; `gt` and `ge` put the constant on the left.

```zig
pub const CompareBranchConstant = struct {
    register: Register,
    constant: u16 align(1),
    branch: Branch(CompareConstantOp) align(1),
};
```

<a id="type-compareconstantop"></a>

## CompareConstantOp

```zig
pub const CompareConstantOp = enum(u3) {
    eq,
    lt,
    le,
    gt,
    ge,
};
```

<a id="type-test"></a>

## Test

```zig
pub const Test = struct {
    register: Register,
    jump_if_truthy: bool,
    offset: JumpOffset align(1),
};
```

<a id="type-testset"></a>

## TestSet

```zig
pub const TestSet = struct {
    dest: Register,
    source: Register,
    jump_if_truthy: bool,
    offset: JumpOffset align(1),
};
```

<a id="type-call"></a>

## Call

```zig
pub const Call = struct {
    base: u32,
    /// `multret_arg_count` when arguments end with multiple results.
    arg_count: u32,
    return_count: u16,
};
```

<a id="type-callinstruction"></a>

## CallInstruction

The operands of a `call` or `tail_call` instruction.

```zig
pub const CallInstruction = struct {
    base: Register,
    /// `multret_count` when arguments end with multiple results.
    arg_count: u16 align(1),
    return_count: u16 align(1),
};
```

### Nested Declarations

| Name | Parameters | Return Type | Description |
| --- | --- | --- | --- |
| [wide](#fn-callinstruction-wide) | `self: CallInstruction` | `Call` |  |

<a id="fn-callinstruction-wide"></a>

### CallInstruction.wide

```zig
pub fn wide(self: CallInstruction) Call
```

References: [`CallInstruction`](#type-callinstruction), [`Call`](#type-call)

<a id="type-return"></a>

## Return

```zig
pub const Return = struct {
    first: Register,
    count: u16 align(1),
};
```

<a id="type-vararg"></a>

## Vararg

```zig
pub const Vararg = struct {
    dest: Register,
    count: u16 align(1),
};
```

<a id="type-closure"></a>

## Closure

```zig
pub const Closure = struct {
    dest: Register,
    proto: ProtoIndex align(1),
};
```

<a id="type-forloop"></a>

## ForLoop

```zig
pub const ForLoop = struct {
    base: Register,
    offset: JumpOffset align(1),
};
```

<a id="type-genericfor"></a>

## GenericFor

```zig
pub const GenericFor = struct {
    base: Register,
    variable_count: u16 align(1),
    offset: JumpOffset align(1),
};
```

