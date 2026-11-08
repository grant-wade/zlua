const std = @import("std");
const runtime = @import("../runtime.zig");
const runtime_types = @import("../runtime/types.zig");
const stack_guard = @import("../stack_guard.zig");
const stdlib = @import("../stdlib.zig");
const Capabilities = @import("capabilities.zig").Capabilities;
const Function = @import("function.zig").Function;
const Table = @import("table.zig").Table;

pub const LibrarySet = stdlib.LibrarySet;
pub const Stdlib = union(enum) {
    none,
    base,
    /// Libraries safe for sandboxed embedding.
    safe,
    /// All libraries; host capabilities still gate ambient access.
    full,
    custom: LibrarySet,
};

pub const Limits = struct {
    /// Starting limits for code you don't trust.
    pub const untrusted: Limits = .{
        .max_memory = 64 << 20,
        .max_instructions = 100_000_000,
        .max_call_frames = 10_000,
        .max_stack_values = 100_000,
        .max_output_bytes = 16 << 20,
        .max_file_bytes = 16 << 20,
    };

    /// Bytes allocated through the state's runtime allocator; null is unlimited.
    max_memory: ?usize = null,
    /// Null uses the runtime default.
    max_stack_values: ?usize = null,
    /// Null uses the runtime default.
    max_call_frames: ?usize = null,
    /// Instructions since the last budget reset; null is unlimited.
    max_instructions: ?u64 = null,
    /// Native stack bytes a host call may use before Lua sees `C stack overflow`. Must leave room
    /// on the thread for the deepest native call.
    max_native_stack: usize = stack_guard.default_max_bytes,
    /// Instructions for finalizers run by each `deinit`, `collect`, or `stepGc`; later ones then
    /// fail with a warning, while host finalizers still run. Null is unlimited.
    max_finalizer_instructions: ?u64 = 1_000_000,
    /// Bytes Lua may write to stdout and stderr; see `State.resetOutputLimit`. Null is unlimited.
    max_output_bytes: ?u64 = null,
    /// Largest single file read by `io`, `loadfile`, `dofile`, `require`, `fs`, and `loadFile`.
    /// Reads also count against `max_memory`.
    max_file_bytes: usize = runtime.default_max_file_bytes,
};

/// Options for `Function.callWith` and `Function.protectedCallWith`.
pub const CallOptions = struct {
    /// Per-call instruction budget covering nested calls and coroutines; nested budgets keep
    /// the tighter limit, and `Limits.max_instructions` still applies.
    max_instructions: ?u64 = null,
    /// Capture a traceback before failing frames unwind; read it via `ErrorRef.traceback`.
    traceback: bool = false,
    /// `xpcall`-style handler run at the error point before `__close` handlers; its first
    /// result becomes the error value. Must belong to the called state.
    message_handler: ?Function = null,
};

/// Options for `Coroutine.protectedResumeWith`.
pub const ResumeOptions = struct {
    /// Instruction budget for this resume, covering nested calls and coroutines; nested budgets
    /// keep the tighter limit, and `Limits.max_instructions` still applies.
    max_instructions: ?u64 = null,
    /// Capture a traceback of the failed coroutine; read it via `ErrorRef.traceback`.
    traceback: bool = false,
};

pub const InstructionBudget = struct {
    limit: ?u64,
    /// Instructions since state creation or the last reset.
    used: u64,
    remaining: ?u64,
};

pub const GcMode = runtime_types.GcMode;
pub const GcParam = runtime_types.GcParam;
/// Percentages, except stepsize, which is measured in bytes.
pub const GcParams = runtime_types.GcParams;

pub const GcOptions = struct {
    mode: GcMode = .generational,
    running: bool = true,
    params: GcParams = .{},
};

pub const DebugOptions = struct {
    /// Richer internal error diagnostics.
    errors: bool = false,
    trace_vm: bool = false,
};

pub const Options = struct {
    stdlib: Stdlib = .safe,
    capabilities: Capabilities = .sandboxed,
    limits: Limits = .{},
    /// Lets Lua's `load` accept binary chunks. Host calls to `State.loadBytecode` always can.
    binary_chunks: bool = false,
    gc: GcOptions = .{},
    debug: DebugOptions = .{},
};

pub const LoadMode = enum {
    source_only,
    binary_only,
    source_or_binary,
};

pub const LoadOptions = struct {
    /// Chunk name for diagnostics, Lua-style `=name` or `@path`.
    name: ?[]const u8 = null,
    /// Table used as the chunk's `_ENV`.
    environment: ?Table = null,
    mode: LoadMode = .source_only,
};

pub const BytecodeLoadOptions = struct {
    /// Table used as the loaded function's `_ENV`.
    environment: ?Table = null,
};

pub const BytecodeDumpOptions = struct {
    strip_debug: bool = false,
};

pub const TableOptions = struct {
    array_hint: u32 = 0,
    hash_hint: u32 = 0,
};

pub const GcStepResult = enum {
    /// A major cycle (incremental or generational) completed.
    complete,
    /// No major cycle completed, even if a minor collection ran.
    pending,
};

pub fn validateGcParam(value: i64) !void {
    if (value < 0 or value > std.math.maxInt(i32)) return error.InvalidGcParam;
}

pub fn runtimeOptions(options: Options) runtime.StateOptions {
    return .{
        .stdlib = toRuntimeStdlib(options.stdlib),
        .io = options.capabilities.io.runtime,
        .stdout = options.capabilities.io.stdout,
        .stderr = options.capabilities.io.stderr,
        .stdout_flush = options.capabilities.io.stdout_flush,
        .stderr_flush = options.capabilities.io.stderr_flush,
        .warnings = options.capabilities.io.warnings,
        .warning_handler = options.capabilities.io.warning_handler,
        .filesystem = options.capabilities.filesystem,
        .environment = options.capabilities.environment,
        .clock = options.capabilities.clock,
        .process = options.capabilities.process,
        .stdin = options.capabilities.io.stdin,
        .max_file_bytes = options.limits.max_file_bytes,
        .max_memory = options.limits.max_memory,
        .max_stack_values = options.limits.max_stack_values,
        .max_call_frames = options.limits.max_call_frames,
        .max_instructions = options.limits.max_instructions,
        .max_native_stack = options.limits.max_native_stack,
        .max_finalizer_instructions = options.limits.max_finalizer_instructions,
        .max_output_bytes = options.limits.max_output_bytes,
        .binary_chunks = options.binary_chunks,
        .debug_errors = options.debug.errors,
        .trace_vm = options.debug.trace_vm,
        .capture_output = false,
    };
}

pub fn toRuntimeStdlib(selection: Stdlib) runtime.StdlibMode {
    return switch (selection) {
        .none => .none,
        .base => .base,
        .safe => .safe,
        .full => .full,
        .custom => |libraries| .{ .libraries = libraries },
    };
}
