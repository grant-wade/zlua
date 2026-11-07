const std = @import("std");

pub const Register = u8;
pub const ConstantIndex = u32;
pub const ProtoIndex = u32;
pub const UpvalueIndex = u8;
pub const LocalIndex = u16;
pub const JumpOffset = i32;
/// Jump offset stored in a `Branch`.
pub const BranchOffset = i28;
pub const multret_count: u16 = std.math.maxInt(u16);
pub const multret_arg_count: u32 = std.math.maxInt(u32);
/// `SetList.count` when the values end with multiple results.
pub const set_list_multret: u8 = std.math.maxInt(u8);

pub const Constant = union(enum) {
    nil,
    boolean: bool,
    integer: []const u8,
    number: []const u8,
    string: []const u8,
};

pub fn constantEql(lhs: Constant, rhs: Constant) bool {
    if (std.meta.activeTag(lhs) != std.meta.activeTag(rhs)) return false;
    return switch (lhs) {
        .nil => true,
        .boolean => |value| value == rhs.boolean,
        .integer => |value| std.mem.eql(u8, value, rhs.integer),
        .number => |value| std.mem.eql(u8, value, rhs.number),
        .string => |value| std.mem.eql(u8, value, rhs.string),
    };
}

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

    /// The jump offset of a jumping instruction, or null.
    pub fn jumpOffset(self: Instruction) ?JumpOffset {
        return switch (self) {
            .jmp => |offset| offset,
            inline .compare_branch, .compare_branch_k => |op| op.branch.offset,
            inline .test_op, .test_set, .for_loop, .for_prep, .tfor_prep, .tfor_loop => |op| op.offset,
            else => null,
        };
    }

    /// The instruction must carry a jump offset.
    pub fn setJumpOffset(self: *Instruction, offset: JumpOffset) error{JumpOutOfRange}!void {
        switch (self.*) {
            .jmp => |*value| value.* = offset,
            inline .compare_branch, .compare_branch_k => |*op| op.branch.offset = std.math.cast(BranchOffset, offset) orelse return error.JumpOutOfRange,
            inline .test_op, .test_set, .for_loop, .for_prep, .tfor_prep, .tfor_call, .tfor_loop => |*op| op.offset = offset,
            else => unreachable,
        }
    }
};

pub const LoadBool = struct {
    dest: Register,
    value: bool,
};

pub const LoadConst = struct {
    dest: Register,
    constant: ConstantIndex align(1),
};

pub const Move = struct {
    dest: Register,
    source: Register,
};

pub const GlobalAccess = struct {
    register: Register,
    name: ConstantIndex align(1),
};

pub const GlobalDeclare = struct {
    table: Register,
    value: Register,
    name: ConstantIndex align(1),
};

pub const UpvalueAccess = struct {
    register: Register,
    upvalue: UpvalueIndex,
};

pub const TableAccess = struct {
    dest: Register,
    table: Register,
    key: Register,
};

pub const TableSet = struct {
    table: Register,
    key: Register,
    value: Register,
};

pub const ArraySet = struct {
    table: Register,
    index: u32 align(1),
    value: Register,
};

pub const FieldAccess = struct {
    dest: Register,
    table: Register,
    name: ConstantIndex align(1),
};

pub const FieldSet = struct {
    table: Register,
    name: ConstantIndex align(1),
    value: Register,
};

/// Loads `table[name]` into `dest` and `table` into `dest + 1`.
pub const MethodAccess = struct {
    dest: Register,
    table: Register,
    name: ConstantIndex align(1),
};

pub const UpvalueFieldAccess = struct {
    dest: Register,
    upvalue: UpvalueIndex,
    name: ConstantIndex align(1),
};

pub const UpvalueFieldSet = struct {
    upvalue: UpvalueIndex,
    name: ConstantIndex align(1),
    value: Register,
};

/// Reads `table[index]` for an integer constant `index`.
pub const IndexAccess = struct {
    dest: Register,
    table: Register,
    index: u32 align(1),
};

pub const IndexSet = struct {
    table: Register,
    index: u32 align(1),
    value: Register,
};

/// Assigns constant `constant` to `table[name]`.
pub const FieldSetConstant = struct {
    table: Register,
    name: ConstantIndex align(1),
    constant: u16 align(1),
};

/// Creates a table in `dest`, which is above every live register of the frame.
pub const NewTable = struct {
    dest: Register,
    array_hint: u32 align(1) = 0,
    hash_hint: u16 align(1) = 0,
};

pub const SetList = struct {
    table: Register,
    first: Register,
    /// `set_list_multret` when the values end with multiple results.
    count: u8,
    start_index: u32 align(1),
};

pub const Unary = struct {
    dest: Register,
    source: Register,
};

pub const Binary = struct {
    dest: Register,
    left: Register,
    right: Register,
};

/// `left` op a numeric constant.
pub const BinaryConstant = struct {
    dest: Register,
    left: Register,
    constant: ConstantIndex align(1),
};

/// Concatenates `count` (at least 2) registers from `first` right to left into `dest`,
/// like PUC OP_CONCAT. Operand registers are scratch space.
pub const ConcatRange = struct {
    dest: Register,
    first: Register,
    count: u16 align(1),
};

pub const CompareBranchOp = enum(u3) {
    eq,
    lt,
    le,
};

/// A comparison and the jump taken when its result equals `jump_if_truthy`.
pub fn Branch(comptime Op: type) type {
    return packed struct(u32) {
        op: Op,
        jump_if_truthy: bool,
        offset: BranchOffset,
    };
}

pub const CompareBranch = struct {
    left: Register,
    right: Register,
    branch: Branch(CompareBranchOp) align(1),
};

/// Compares a register with a numeric constant; `gt` and `ge` put the constant on the left.
pub const CompareBranchConstant = struct {
    register: Register,
    constant: u16 align(1),
    branch: Branch(CompareConstantOp) align(1),
};

pub const CompareConstantOp = enum(u3) {
    eq,
    lt,
    le,
    gt,
    ge,
};

pub const Test = struct {
    register: Register,
    jump_if_truthy: bool,
    offset: JumpOffset align(1),
};

pub const TestSet = struct {
    dest: Register,
    source: Register,
    jump_if_truthy: bool,
    offset: JumpOffset align(1),
};

pub const Call = struct {
    base: u32,
    /// `multret_arg_count` when arguments end with multiple results.
    arg_count: u32,
    return_count: u16,
};

/// The operands of a `call` or `tail_call` instruction.
pub const CallInstruction = struct {
    base: Register,
    /// `multret_count` when arguments end with multiple results.
    arg_count: u16 align(1),
    return_count: u16 align(1),

    pub fn wide(self: CallInstruction) Call {
        return .{
            .base = self.base,
            .arg_count = if (self.arg_count == multret_count) multret_arg_count else self.arg_count,
            .return_count = self.return_count,
        };
    }
};

pub const Return = struct {
    first: Register,
    count: u16 align(1),
};

pub const Vararg = struct {
    dest: Register,
    count: u16 align(1),
};

pub const Closure = struct {
    dest: Register,
    proto: ProtoIndex align(1),
};

pub const ForLoop = struct {
    base: Register,
    offset: JumpOffset align(1),
};

pub const GenericFor = struct {
    base: Register,
    variable_count: u16 align(1),
    offset: JumpOffset align(1),
};

comptime {
    std.debug.assert(@sizeOf(Instruction) == 8);
}
