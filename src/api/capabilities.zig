const std = @import("std");
const runtime = @import("../runtime.zig");

pub const MemoryFile = runtime.MemoryFile;
/// Writable in-memory filesystem.
pub const MemoryFilesystem = runtime.MemoryFilesystem;

/// When Lua output writers are flushed beyond explicit flush points.
pub const OutputFlush = runtime.OutputFlush;

pub const IoCapability = struct {
    /// Required by host-backed filesystem, clock, and process operations.
    runtime: ?std.Io = null,
    /// Bytes returned by Lua stdin reads.
    stdin: []const u8 = "",
    /// Receives `print` and `io.write` output.
    stdout: ?*std.Io.Writer = null,
    stderr: ?*std.Io.Writer = null,
    /// Flush policy beyond `io.flush`, `os.exit`, and child process starts.
    stdout_flush: OutputFlush = .explicit,
    stderr_flush: OutputFlush = .explicit,
    /// Start with warnings on, like `lua -W`.
    warnings: bool = false,
    /// Receives complete warnings instead of `stderr`; must not call back into the state.
    warning_handler: ?WarningHandler = null,

    pub const disabled: IoCapability = .{};
};

/// Filesystem access granted to Lua file APIs, `loadfile`, `dofile`, and `require`.
pub const FilesystemCapability = runtime.FilesystemCapability;
pub const CustomFilesystem = runtime.CustomFilesystem;
/// Borrowed directory root that scopes host filesystem access.
pub const HostDirectory = runtime.HostDirectory;
pub const FilesystemFileKind = runtime.FilesystemFileKind;
pub const FilesystemFileStat = runtime.FilesystemFileStat;
pub const FilesystemDirectoryEntry = runtime.FilesystemDirectoryEntry;
pub const deinitFilesystemDirectoryEntries = runtime.deinitFilesystemDirectoryEntries;

/// Environment-variable access granted to `os.getenv` and enabled child processes.
pub const EnvironmentCapability = runtime.EnvironmentCapability;
pub const CustomEnvironment = runtime.CustomEnvironment;

/// Clock access granted to `os.time`, `os.date`, and `os.clock`.
pub const ClockCapability = runtime.ClockCapability;
pub const CustomClock = runtime.CustomClock;
pub const FixedClock = runtime.FixedClock;
pub const UtcOffset = runtime.UtcOffset;
/// Process access granted to `os.execute`, `io.popen`, and `os.exit`.
pub const ProcessCapability = runtime.ProcessCapability;
pub const CustomProcess = runtime.CustomProcess;
pub const ProcessResult = runtime.ProcessResult;
pub const ProcessStatus = runtime.ProcessStatus;
pub const PopenResult = runtime.PopenResult;
/// Exit code and close flag recorded by `os.exit`; see `State.exitRequest`.
pub const ExitRequest = runtime.ExitRequest;
pub const WarningHandler = runtime.WarningHandler;

/// Host services available to opened standard libraries; all denied by default.
pub const Capabilities = struct {
    io: IoCapability = .disabled,
    filesystem: FilesystemCapability = .disabled,
    environment: EnvironmentCapability = .disabled,
    clock: ClockCapability = .disabled,
    process: ProcessCapability = .disabled,

    pub const sandboxed: Capabilities = .{};
};
