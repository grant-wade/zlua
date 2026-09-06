# runtime.host

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
- [compile.compiler](../compile/compiler.md)
- [compile.disasm](../compile/disasm.md)
- [api](../api.md)
- [runtime](../runtime.md)
- [runtime.chunk](../runtime/chunk.md)
- [runtime.types](../runtime/types.md)
- [runtime.value](../runtime/value.md)
- [runtime.execute](../runtime/execute.md)
- [testing.process](../testing/process.md)
- [runtime.state](../runtime/state.md)
- [runtime.call](../runtime/call.md)
- [runtime.coroutine](../runtime/coroutine.md)
- [runtime.debug](../runtime/debug.md)
- [runtime.gc](../runtime/gc.md)
- [runtime.host](../runtime/host.md)
- [stdlib](../stdlib.md)
- [stdlib.base](../stdlib/base.md)
- [stdlib.table](../stdlib/table.md)
- [stdlib.string](../stdlib/string.md)
- [stdlib.math](../stdlib/math.md)
- [stdlib.utf8](../stdlib/utf8.md)
- [stdlib.coroutine](../stdlib/coroutine.md)
- [stdlib.debug](../stdlib/debug.md)
- [stdlib.package](../stdlib/package.md)
- [stdlib.io](../stdlib/io.md)
- [stdlib.os](../stdlib/os.md)
- [stdlib.json](../stdlib/json.md)
- [stdlib.zerde_lua](../stdlib/zerde_lua.md)
- [stdlib.toml](../stdlib/toml.md)
- [stdlib.msgpack](../stdlib/msgpack.md)
- [stdlib.csv](../stdlib/csv.md)
- [stdlib.fs](../stdlib/fs.md)
- [stdlib.static_strings](../stdlib/static_strings.md)
- [runtime.vm](../runtime/vm.md)
- [runtime.tests](../runtime/tests.md)
- [runtime.internal](../runtime/internal.md)
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
- [testing.c_api_runner](../testing/c_api_runner.md)
- [testing.fixtures](../testing/fixtures.md)
- [testing.diff_runner](../testing/diff_runner.md)
- [testing.expected_failures](../testing/expected_failures.md)
- [testing.metadata](../testing/metadata.md)
- [testing.normalizer](../testing/normalizer.md)
- [testing.extension_runner](../testing/extension_runner.md)
- [testing.official_suite](../testing/official_suite.md)

</details>

## Functions

- [deinitDirectoryEntries](#fn-deinitdirectoryentries)

## Types

- [MemoryFile](#type-memoryfile)
- [FileKind](#type-filekind)
- [FileStat](#type-filestat)
- [DirectoryEntry](#type-directoryentry)
- [MemoryFilesystem](#type-memoryfilesystem)
- [FilesystemCapability](#type-filesystemcapability)
- [HostDirectory](#type-hostdirectory)
- [CustomFilesystem](#type-customfilesystem)
- [EnvironmentCapability](#type-environmentcapability)
- [CustomEnvironment](#type-customenvironment)
- [ClockCapability](#type-clockcapability)
- [CustomClock](#type-customclock)
- [ProcessCapability](#type-processcapability)
- [CustomProcess](#type-customprocess)
- [ProcessResult](#type-processresult)
- [ProcessStatus](#type-processstatus)

<a id="type-memoryfile"></a>

## MemoryFile

```zig
pub const MemoryFile = struct {
    path: []const u8,
    contents: []const u8,
};
```

<a id="type-filekind"></a>

## FileKind

```zig
pub const FileKind = enum {
    block_device,
    character_device,
    directory,
    named_pipe,
    sym_link,
    file,
    unix_domain_socket,
    whiteout,
    door,
    event_port,
    unknown,
};
```

### Nested Declarations

| Name | Parameters | Return Type | Description |
| --- | --- | --- | --- |
| [fromStd](#fn-filekind-fromstd) | `kind: std.Io.File.Kind` | `FileKind` |  |

<a id="fn-filekind-fromstd"></a>

### FileKind.fromStd

```zig
pub fn fromStd(kind: std.Io.File.Kind) FileKind
```

References: [`FileKind`](#type-filekind)

<a id="type-filestat"></a>

## FileStat

```zig
pub const FileStat = struct {
    inode: u64 = 0,
    nlink: u64 = 1,
    size: u64 = 0,
    permissions: u64 = 0,
    kind: FileKind,
    atime: ?std.Io.Timestamp = null,
    mtime: std.Io.Timestamp = .{ .nanoseconds = 0 },
    ctime: std.Io.Timestamp = .{ .nanoseconds = 0 },
    block_size: u32 = 1,
};
```

### Nested Declarations

| Name | Parameters | Return Type | Description |
| --- | --- | --- | --- |
| [fromStd](#fn-filestat-fromstd) | `stat: std.Io.File.Stat` | `FileStat` |  |

<a id="fn-filestat-fromstd"></a>

### FileStat.fromStd

```zig
pub fn fromStd(stat: std.Io.File.Stat) FileStat
```

References: [`FileStat`](#type-filestat)

<a id="type-directoryentry"></a>

## DirectoryEntry

```zig
pub const DirectoryEntry = struct {
    name: []const u8,
    kind: FileKind,
    inode: u64 = 0,
};
```

<a id="fn-deinitdirectoryentries"></a>

## deinitDirectoryEntries

```zig
pub fn deinitDirectoryEntries(allocator: std.mem.Allocator, entries: []DirectoryEntry) void
```

References: [`DirectoryEntry`](#type-directoryentry)

<a id="type-memoryfilesystem"></a>

## MemoryFilesystem

```zig
pub const MemoryFilesystem = struct {
    allocator: std.mem.Allocator,
    files: std.ArrayList(MemoryFile) = .empty,
    directories: std.ArrayList([]const u8) = .empty,
    options: Options = .{},
    bytes_used: usize = 0,
};
```

### Nested Declarations

| Name | Parameters | Return Type | Description |
| --- | --- | --- | --- |
| [default_max_path_len](#const-memoryfilesystem-default_max_path_len) |  |  |  |
| [Options](#type-memoryfilesystem-options) |  |  |  |
| [init](#fn-memoryfilesystem-init) | `allocator: std.mem.Allocator` | `MemoryFilesystem` |  |
| [initWithOptions](#fn-memoryfilesystem-initwithoptions) | `allocator: std.mem.Allocator, options: Options` | `MemoryFilesystem` |  |
| [initWithFiles](#fn-memoryfilesystem-initwithfiles) | `allocator: std.mem.Allocator, files: []const MemoryFile` | `!MemoryFilesystem` |  |
| [initWithFilesAndOptions](#fn-memoryfilesystem-initwithfilesandoptions) | `allocator: std.mem.Allocator, files: []const MemoryFile, options: Options` | `!MemoryFilesystem` |  |
| [deinit](#fn-memoryfilesystem-deinit) | `self: *MemoryFilesystem` | `void` |  |
| [readFileAlloc](#fn-memoryfilesystem-readfilealloc) | `self: *const MemoryFilesystem, allocator: std.mem.Allocator, path: []const u8` | `![]const u8` |  |
| [writeFile](#fn-memoryfilesystem-writefile) | `self: *MemoryFilesystem, path: []const u8, contents: []const u8` | `!void` |  |
| [makeDir](#fn-memoryfilesystem-makedir) | `self: *MemoryFilesystem, path: []const u8, parents: bool` | `!void` |  |
| [statPath](#fn-memoryfilesystem-statpath) | `self: *const MemoryFilesystem, path: []const u8` | `!FileStat` |  |
| [readDirAlloc](#fn-memoryfilesystem-readdiralloc) | `self: *const MemoryFilesystem, allocator: std.mem.Allocator, path: []const u8` | `![]DirectoryEntry` |  |
| [removeFile](#fn-memoryfilesystem-removefile) | `self: *MemoryFilesystem, path: []const u8` | `!void` |  |
| [removePath](#fn-memoryfilesystem-removepath) | `self: *MemoryFilesystem, path: []const u8, recursive: bool` | `!void` |  |
| [renameFile](#fn-memoryfilesystem-renamefile) | `self: *MemoryFilesystem, old_path: []const u8, new_path: []const u8` | `!void` |  |
| [renamePath](#fn-memoryfilesystem-renamepath) | `self: *MemoryFilesystem, old_path: []const u8, new_path: []const u8` | `!void` |  |
| [copyFile](#fn-memoryfilesystem-copyfile) | `self: *MemoryFilesystem, source: []const u8, destination: []const u8, overwrite: bool` | `!void` |  |
| [normalizePathAlloc](#fn-memoryfilesystem-normalizepathalloc) | `allocator: std.mem.Allocator, path: []const u8, max_path_len: usize` | `![]u8` |  |
| [normalizeRootPathAlloc](#fn-memoryfilesystem-normalizerootpathalloc) | `allocator: std.mem.Allocator, path: []const u8, max_path_len: usize` | `![]u8` |  |

<a id="const-memoryfilesystem-default_max_path_len"></a>

### MemoryFilesystem.default_max_path_len

```zig
pub const default_max_path_len: usize = 4096;
```

<a id="type-memoryfilesystem-options"></a>

### MemoryFilesystem.Options

```zig
pub const Options = struct {
    max_path_len: usize = default_max_path_len,
    max_bytes: ?usize = null,
};
```

<a id="fn-memoryfilesystem-init"></a>

### MemoryFilesystem.init

```zig
pub fn init(allocator: std.mem.Allocator) MemoryFilesystem
```

References: [`MemoryFilesystem`](#type-memoryfilesystem)

<a id="fn-memoryfilesystem-initwithoptions"></a>

### MemoryFilesystem.initWithOptions

```zig
pub fn initWithOptions(allocator: std.mem.Allocator, options: Options) MemoryFilesystem
```

References: [`MemoryFilesystem`](#type-memoryfilesystem)

<a id="fn-memoryfilesystem-initwithfiles"></a>

### MemoryFilesystem.initWithFiles

```zig
pub fn initWithFiles(allocator: std.mem.Allocator, files: []const MemoryFile) !MemoryFilesystem
```

References: [`MemoryFile`](#type-memoryfile), [`MemoryFilesystem`](#type-memoryfilesystem)

<a id="fn-memoryfilesystem-initwithfilesandoptions"></a>

### MemoryFilesystem.initWithFilesAndOptions

```zig
pub fn initWithFilesAndOptions(allocator: std.mem.Allocator, files: []const MemoryFile, options: Options) !MemoryFilesystem
```

References: [`MemoryFile`](#type-memoryfile), [`MemoryFilesystem`](#type-memoryfilesystem)

<a id="fn-memoryfilesystem-deinit"></a>

### MemoryFilesystem.deinit

```zig
pub fn deinit(self: *MemoryFilesystem) void
```

References: [`MemoryFilesystem`](#type-memoryfilesystem)

<a id="fn-memoryfilesystem-readfilealloc"></a>

### MemoryFilesystem.readFileAlloc

```zig
pub fn readFileAlloc(self: *const MemoryFilesystem, allocator: std.mem.Allocator, path: []const u8) ![]const u8
```

References: [`MemoryFilesystem`](#type-memoryfilesystem)

<a id="fn-memoryfilesystem-writefile"></a>

### MemoryFilesystem.writeFile

```zig
pub fn writeFile(self: *MemoryFilesystem, path: []const u8, contents: []const u8) !void
```

References: [`MemoryFilesystem`](#type-memoryfilesystem)

<a id="fn-memoryfilesystem-makedir"></a>

### MemoryFilesystem.makeDir

```zig
pub fn makeDir(self: *MemoryFilesystem, path: []const u8, parents: bool) !void
```

References: [`MemoryFilesystem`](#type-memoryfilesystem)

<a id="fn-memoryfilesystem-statpath"></a>

### MemoryFilesystem.statPath

```zig
pub fn statPath(self: *const MemoryFilesystem, path: []const u8) !FileStat
```

References: [`MemoryFilesystem`](#type-memoryfilesystem), [`FileStat`](#type-filestat)

<a id="fn-memoryfilesystem-readdiralloc"></a>

### MemoryFilesystem.readDirAlloc

```zig
pub fn readDirAlloc(self: *const MemoryFilesystem, allocator: std.mem.Allocator, path: []const u8) ![]DirectoryEntry
```

References: [`MemoryFilesystem`](#type-memoryfilesystem), [`DirectoryEntry`](#type-directoryentry)

<a id="fn-memoryfilesystem-removefile"></a>

### MemoryFilesystem.removeFile

```zig
pub fn removeFile(self: *MemoryFilesystem, path: []const u8) !void
```

References: [`MemoryFilesystem`](#type-memoryfilesystem)

<a id="fn-memoryfilesystem-removepath"></a>

### MemoryFilesystem.removePath

```zig
pub fn removePath(self: *MemoryFilesystem, path: []const u8, recursive: bool) !void
```

References: [`MemoryFilesystem`](#type-memoryfilesystem)

<a id="fn-memoryfilesystem-renamefile"></a>

### MemoryFilesystem.renameFile

```zig
pub fn renameFile(self: *MemoryFilesystem, old_path: []const u8, new_path: []const u8) !void
```

References: [`MemoryFilesystem`](#type-memoryfilesystem)

<a id="fn-memoryfilesystem-renamepath"></a>

### MemoryFilesystem.renamePath

```zig
pub fn renamePath(self: *MemoryFilesystem, old_path: []const u8, new_path: []const u8) !void
```

References: [`MemoryFilesystem`](#type-memoryfilesystem)

<a id="fn-memoryfilesystem-copyfile"></a>

### MemoryFilesystem.copyFile

```zig
pub fn copyFile(self: *MemoryFilesystem, source: []const u8, destination: []const u8, overwrite: bool) !void
```

References: [`MemoryFilesystem`](#type-memoryfilesystem)

<a id="fn-memoryfilesystem-normalizepathalloc"></a>

### MemoryFilesystem.normalizePathAlloc

```zig
pub fn normalizePathAlloc(allocator: std.mem.Allocator, path: []const u8, max_path_len: usize) ![]u8
```

<a id="fn-memoryfilesystem-normalizerootpathalloc"></a>

### MemoryFilesystem.normalizeRootPathAlloc

```zig
pub fn normalizeRootPathAlloc(allocator: std.mem.Allocator, path: []const u8, max_path_len: usize) ![]u8
```

<a id="type-filesystemcapability"></a>

## FilesystemCapability

```zig
pub const FilesystemCapability = union(enum) {
    disabled,
    memory: []const MemoryFile,
    memory_rw: *MemoryFilesystem,
    host_cwd,
    host_dir: HostDirectory,
    custom: CustomFilesystem,
};
```

<a id="type-hostdirectory"></a>

## HostDirectory

```zig
pub const HostDirectory = struct {
    dir: std.Io.Dir,
    read_only: bool = false,
};
```

<a id="type-customfilesystem"></a>

## CustomFilesystem

```zig
pub const CustomFilesystem = struct {
    context: ?*anyopaque = null,
    read_file_alloc: *const fn (context: ?*anyopaque, allocator: std.mem.Allocator, path: []const u8) anyerror![]const u8,
    write_file: ?*const fn (context: ?*anyopaque, path: []const u8, contents: []const u8) anyerror!void = null,
    remove_file: ?*const fn (context: ?*anyopaque, path: []const u8) anyerror!void = null,
    rename_file: ?*const fn (context: ?*anyopaque, old_path: []const u8, new_path: []const u8) anyerror!void = null,
    stat: ?*const fn (context: ?*anyopaque, path: []const u8, follow_symlinks: bool) anyerror!FileStat = null,
    read_dir_alloc: ?*const fn (context: ?*anyopaque, allocator: std.mem.Allocator, path: []const u8) anyerror![]DirectoryEntry = null,
    make_dir: ?*const fn (context: ?*anyopaque, path: []const u8, parents: bool) anyerror!void = null,
    remove_path: ?*const fn (context: ?*anyopaque, path: []const u8, recursive: bool) anyerror!void = null,
    copy_file: ?*const fn (context: ?*anyopaque, source: []const u8, destination: []const u8, overwrite: bool) anyerror!void = null,
};
```

<a id="type-environmentcapability"></a>

## EnvironmentCapability

```zig
pub const EnvironmentCapability = union(enum) {
    disabled,
    map: *const std.process.Environ.Map,
    custom: CustomEnvironment,
};
```

<a id="type-customenvironment"></a>

## CustomEnvironment

```zig
pub const CustomEnvironment = struct {
    context: ?*anyopaque = null,
    get: *const fn (context: ?*anyopaque, name: []const u8) ?[]const u8,
};
```

<a id="type-clockcapability"></a>

## ClockCapability

```zig
pub const ClockCapability = union(enum) {
    disabled,
    fixed: i64,
    system,
    custom: CustomClock,
};
```

<a id="type-customclock"></a>

## CustomClock

```zig
pub const CustomClock = struct {
    context: ?*anyopaque = null,
    now: *const fn (context: ?*anyopaque) anyerror!i64,
};
```

<a id="type-processcapability"></a>

## ProcessCapability

```zig
pub const ProcessCapability = union(enum) {
    disabled,
    enabled,
    custom: CustomProcess,
};
```

<a id="type-customprocess"></a>

## CustomProcess

```zig
pub const CustomProcess = struct {
    context: ?*anyopaque = null,
    execute: *const fn (context: ?*anyopaque, command: []const u8) anyerror!ProcessResult,
};
```

<a id="type-processresult"></a>

## ProcessResult

```zig
pub const ProcessResult = struct {
    status: ProcessStatus,
    code: i64,
};
```

<a id="type-processstatus"></a>

## ProcessStatus

```zig
pub const ProcessStatus = enum {
    exit,
    signal,
};
```

