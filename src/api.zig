//! Zig-native embedding API for zlua: a Lua 5.5 state driven with Zig values,
//! explicit host capabilities, rooted handles, and Zig errors.
//!
//! Rooted handles (`Table`, `Function`, `Coroutine`, `Ref`, `Userdata(T)`, `AnyUserdata`,
//! `ErrorRef`, and `Value`s holding them) must be released with `deinit`. `State.reset`
//! invalidates prior handles and borrowed VM slices. The `runtime` module is internal.
//! See `docs/embedding.md` for capabilities, error handling, snapshots, and ownership.

const callbacks = @import("api/callbacks.zig");
const capabilities = @import("api/capabilities.zig");
const context = @import("api/context.zig");
const coroutine = @import("api/coroutine.zig");
const errors = @import("api/errors.zig");
const function = @import("api/function.zig");
const handle = @import("api/handle.zig");
const options = @import("api/options.zig");
const snapshot = @import("api/snapshot.zig");
const state = @import("api/state.zig");
const table = @import("api/table.zig");
const userdata = @import("api/userdata.zig");
const value = @import("api/value.zig");

pub const Error = errors.Error;
pub const UnsupportedOption = errors.UnsupportedOption;
pub const ConversionError = errors.ConversionError;
pub const CallResult = errors.CallResult;
pub const ErrorRef = errors.ErrorRef;

pub const State = state.State;
pub const InterruptHandle = state.InterruptHandle;
pub const Snapshot = snapshot.Snapshot;

pub const LibrarySet = options.LibrarySet;
pub const Stdlib = options.Stdlib;
pub const Limits = options.Limits;
pub const CallOptions = options.CallOptions;
pub const InstructionBudget = options.InstructionBudget;
pub const GcMode = options.GcMode;
pub const GcParam = options.GcParam;
pub const GcParams = options.GcParams;
pub const GcOptions = options.GcOptions;
pub const DebugOptions = options.DebugOptions;
pub const Options = options.Options;
pub const LoadMode = options.LoadMode;
pub const LoadOptions = options.LoadOptions;
pub const DoOptions = options.DoOptions;
pub const BytecodeLoadOptions = options.BytecodeLoadOptions;
pub const BytecodeDumpOptions = options.BytecodeDumpOptions;
pub const TableOptions = options.TableOptions;
pub const GcBudget = options.GcBudget;
pub const GcStepResult = options.GcStepResult;

pub const MemoryFile = capabilities.MemoryFile;
pub const MemoryFilesystem = capabilities.MemoryFilesystem;
pub const OutputFlush = capabilities.OutputFlush;
pub const IoCapability = capabilities.IoCapability;
pub const FilesystemCapability = capabilities.FilesystemCapability;
pub const CustomFilesystem = capabilities.CustomFilesystem;
pub const HostDirectory = capabilities.HostDirectory;
pub const FilesystemFileKind = capabilities.FilesystemFileKind;
pub const FilesystemFileStat = capabilities.FilesystemFileStat;
pub const FilesystemDirectoryEntry = capabilities.FilesystemDirectoryEntry;
pub const deinitFilesystemDirectoryEntries = capabilities.deinitFilesystemDirectoryEntries;
pub const EnvironmentCapability = capabilities.EnvironmentCapability;
pub const CustomEnvironment = capabilities.CustomEnvironment;
pub const ClockCapability = capabilities.ClockCapability;
pub const CustomClock = capabilities.CustomClock;
pub const FixedClock = capabilities.FixedClock;
pub const UtcOffset = capabilities.UtcOffset;
pub const ProcessCapability = capabilities.ProcessCapability;
pub const CustomProcess = capabilities.CustomProcess;
pub const ProcessResult = capabilities.ProcessResult;
pub const ProcessStatus = capabilities.ProcessStatus;
pub const PopenResult = capabilities.PopenResult;
pub const ExitRequest = capabilities.ExitRequest;
pub const WarningHandler = capabilities.WarningHandler;
pub const Capabilities = capabilities.Capabilities;

pub const Value = value.Value;
pub const Tuple = value.Tuple;
pub const Ref = handle.Ref;
pub const Table = table.Table;
pub const Function = function.Function;
pub const Coroutine = coroutine.Coroutine;
pub const CoroutineStatus = coroutine.CoroutineStatus;
pub const ResumeResult = coroutine.ResumeResult;

pub const Userdata = userdata.Userdata;
pub const AnyUserdata = userdata.AnyUserdata;
pub const UserdataOptions = userdata.UserdataOptions;
pub const UserdataPtrOptions = userdata.UserdataPtrOptions;
pub const UserdataSnapshotHooks = userdata.UserdataSnapshotHooks;

pub const HostFn = callbacks.HostFn;
pub const Context = context.Context;

test {
    _ = @import("api/memory_limit.zig");
    _ = @import("testing/api_state_tests.zig");
    _ = @import("testing/api_callback_tests.zig");
    _ = @import("testing/api_userdata_tests.zig");
    _ = @import("testing/api_capability_tests.zig");
    _ = @import("testing/api_resource_limit_tests.zig");
    _ = @import("testing/api_snapshot_tests.zig");
    _ = @import("testing/api_host_tests.zig");
    _ = @import("testing/api_file_tests.zig");
    _ = @import("testing/api_coroutine_tests.zig");
    _ = @import("testing/api_limit_tests.zig");
    _ = @import("testing/api_table_tests.zig");
    _ = @import("testing/api_fuzz_tests.zig");
}
