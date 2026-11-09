pub const version = "0.8.1";
pub const lua_target_version = "Lua 5.5";

pub const frontend = @import("frontend.zig");
pub const compile = @import("compile.zig");
pub const errors = @import("errors.zig");
pub const api = @import("api.zig");
pub const runtime = @import("runtime.zig");
pub const stdlib = @import("stdlib.zig");
pub const testing = @import("testing.zig");

pub const State = api.State;
pub const Snapshot = api.Snapshot;
pub const UserdataSnapshotHooks = api.UserdataSnapshotHooks;
pub const Options = api.Options;
pub const GcMode = api.GcMode;
pub const GcParam = api.GcParam;
pub const GcParams = api.GcParams;
pub const GcOptions = api.GcOptions;
pub const GcStepResult = api.GcStepResult;
pub const Stdlib = api.Stdlib;
pub const LibrarySet = api.LibrarySet;
pub const Value = api.Value;
pub const Ref = api.Ref;
pub const String = api.String;
pub const HandleScope = api.HandleScope;
pub const Table = api.Table;
pub const Function = api.Function;
pub const Coroutine = api.Coroutine;
pub const CoroutineStatus = api.CoroutineStatus;
pub const ResumeResult = api.ResumeResult;
pub const ErrorRef = api.ErrorRef;
pub const CallOptions = api.CallOptions;
pub const ResumeOptions = api.ResumeOptions;
pub const InterruptHandle = api.InterruptHandle;
pub const Context = api.Context;
pub const Host = api.Host;
pub const Caller = api.Caller;
pub const Error = api.Error;
pub const BytecodeLoadOptions = api.BytecodeLoadOptions;
pub const BytecodeDumpOptions = api.BytecodeDumpOptions;
pub const Tuple = api.Tuple;
pub const deinit = api.deinit;
pub const HostFn = api.HostFn;
pub const Analysis = api.Analysis;
pub const GlobalUse = api.GlobalUse;
pub const analyze = api.analyze;
pub const Decoder = api.Decoder;
pub const DecodeError = api.DecodeError;
pub const DecodeOptions = api.DecodeOptions;
pub const Diagnostic = api.Diagnostic;
pub const FieldOptions = api.FieldOptions;
pub const decode = api.decode;
pub const defaultValue = api.defaultValue;
pub const fieldKeys = api.fieldKeys;
pub const fieldOptions = api.fieldOptions;
pub const Userdata = api.Userdata;
pub const AnyUserdata = api.AnyUserdata;
pub const UserdataType = api.UserdataType;
pub const MemoryFile = api.MemoryFile;
pub const MemoryFilesystem = api.MemoryFilesystem;
pub const FilesystemCapability = api.FilesystemCapability;
pub const CustomFilesystem = api.CustomFilesystem;
pub const HostDirectory = api.HostDirectory;
pub const FilesystemFileKind = api.FilesystemFileKind;
pub const FilesystemFileStat = api.FilesystemFileStat;
pub const FilesystemDirectoryEntry = api.FilesystemDirectoryEntry;
pub const deinitFilesystemDirectoryEntries = api.deinitFilesystemDirectoryEntries;
pub const EnvironmentCapability = api.EnvironmentCapability;
pub const CustomEnvironment = api.CustomEnvironment;
pub const ClockCapability = api.ClockCapability;
pub const CustomClock = api.CustomClock;
pub const ProcessCapability = api.ProcessCapability;
pub const CustomProcess = api.CustomProcess;
pub const ProcessResult = api.ProcessResult;
pub const ProcessStatus = api.ProcessStatus;
pub const OutputFlush = api.OutputFlush;
pub const UnsupportedOption = api.UnsupportedOption;
pub const ConversionError = api.ConversionError;
pub const HostData = api.HostData;
pub const Limits = api.Limits;
pub const InstructionBudget = api.InstructionBudget;
pub const DebugOptions = api.DebugOptions;
pub const LoadMode = api.LoadMode;
pub const LoadOptions = api.LoadOptions;
pub const TableOptions = api.TableOptions;
pub const IoCapability = api.IoCapability;
pub const FixedClock = api.FixedClock;
pub const UtcOffset = api.UtcOffset;
pub const PopenResult = api.PopenResult;
pub const ExitRequest = api.ExitRequest;
pub const WarningHandler = api.WarningHandler;
pub const Capabilities = api.Capabilities;
pub const UserdataOptions = api.UserdataOptions;

test "root exports the types host callbacks must name" {
    comptime {
        for ([_]type{ UtcOffset, PopenResult, ExitRequest, IoCapability, FixedClock, Limits, LoadOptions }) |T| {
            _ = T;
        }
    }
}

test {
    _ = frontend;
    _ = compile;
    _ = errors;
    _ = api;
    _ = runtime;
    _ = stdlib;
    _ = testing;
}
