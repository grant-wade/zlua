# stdlib.io

## Navigation

- [API Index](../README.md)
- Parent: [stdlib](../stdlib.md)

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

- [fileTypeId](#fn-filetypeid)
- [fileOf](#fn-fileof)
- [newFile](#fn-newfile)
- [finalizeFile](#fn-finalizefile)
- [closeFinalizerOrder](#fn-closefinalizerorder)
- [hasOpenFiles](#fn-hasopenfiles)
- [closeOpenFiles](#fn-closeopenfiles)
- [read](#fn-read)
- [write](#fn-write)
- [open](#fn-open)
- [prepareWrite](#fn-preparewrite)
- [popen](#fn-popen)
- [fileTostring](#fn-filetostring)
- [input](#fn-input)
- [output](#fn-output)
- [close](#fn-close)
- [flush](#fn-flush)
- [lines](#fn-lines)
- [tmpfile](#fn-tmpfile)
- [typeValue](#fn-typevalue)
- [fileRead](#fn-fileread)
- [fileWrite](#fn-filewrite)
- [fileClose](#fn-fileclose)
- [fileGc](#fn-filegc)
- [fileSeek](#fn-fileseek)
- [fileFlush](#fn-fileflush)
- [fileLines](#fn-filelines)
- [fileSetvbuf](#fn-filesetvbuf)
- [linesIter](#fn-linesiter)
- [linesNext](#fn-linesnext)
- [readAllStdin](#fn-readallstdin)
- [readStdinLine](#fn-readstdinline)
- [readRemaining](#fn-readremaining)
- [truncateFile](#fn-truncatefile)
- [flushOpenFiles](#fn-flushopenfiles)
- [checkedFile](#fn-checkedfile)
- [parseMode](#fn-parsemode)
- [newStandardFile](#fn-newstandardfile)

## Types

- [File](#type-file)
- [FileOptions](#type-fileoptions)
- [ParsedMode](#type-parsedmode)

<a id="type-file"></a>

## File

The payload of every Lua file handle. Standard streams, `io.open`,
`io.tmpfile`, `io.popen`, `io.lines`, and `fs.open` all return `FILE*`
userdata around one of these, so no handle state is visible from Lua.

A handle buffers the whole file, like a C stream with a whole-file buffer.
Sequential writes append to `content`, so they cost time linear in the
bytes written. Snapshots copy the payload and rollback copies it before
its first change after a baseline, so changes go through `writable`.

```zig
pub const File = struct {
    kind: Kind,
    /// Regular file path or popen command, owned by the handle; empty otherwise.
    path: []const u8 = "",
    readable: bool,
    writable: bool,
    /// Every write goes to the end of the file.
    append: bool = false,
    closed: bool = false,
    buffer_mode: BufferMode = .full,
    /// The handle opened a directory: C `fopen` succeeds, then reads fail.
    is_directory: bool = false,
    /// `/dev/full` has buffered writes that its next flush fails to write.
    device_pending: bool = false,
    content: std.ArrayList(u8) = .empty,
    /// Zero-based position.
    pos: usize = 0,
    /// Bytes known to match the host file, which is no longer than that.
    /// The handle has unflushed writes while this is below `content.len`.
    synced: usize = 0,
    /// `State.file_generation` when the handle last matched the filesystem.
    generation: u64 = 0,
    /// The command's status once a popen command has run.
    popen_result: ?host.ProcessResult = null,
    /// Creation order on the scale of `Table.finalizer_order`.
    finalizer_order: u64 = 0,
};
```

### Nested Declarations

| Name | Parameters | Return Type | Description |
| --- | --- | --- | --- |
| [Kind](#type-file-kind) |  |  |  |
| [BufferMode](#type-file-buffermode) |  |  |  |

<a id="type-file-kind"></a>

### File.Kind

```zig
pub const Kind = enum {
    stdin,
    stdout,
    stderr,
    /// A file of the filesystem capability.
    regular,
    popen,
    /// `/dev/null`: writes are discarded and reads see no bytes.
    null_device,
    /// Linux `/dev/full`: reads see endless zero bytes, and writing
    /// buffered bytes out fails with `ENOSPC`.
    full_device,
    /// `io.tmpfile`: memory only; it never touches a filesystem.
    anonymous,
};
```

<a id="type-file-buffermode"></a>

### File.BufferMode

```zig
pub const BufferMode = enum {
    no,
    full,
    line,
};
```

<a id="fn-filetypeid"></a>

## fileTypeId

Userdata type identity of file handles.

```zig
pub fn fileTypeId() usize
```

<a id="fn-fileof"></a>

## fileOf

The file behind a handle, for reading only; null for other values.

```zig
pub fn fileOf(value: Value) ?*const File
```

References: [`File`](#type-file)

<a id="type-fileoptions"></a>

## FileOptions

```zig
pub const FileOptions = struct {
    kind: File.Kind = .regular,
    path: []const u8 = "",
    mode: ParsedMode,
    /// Initial bytes allocated by the state allocator. `newFile` takes them,
    /// even when it fails.
    contents: []const u8 = "",
    buffer_mode: File.BufferMode = .full,
    is_directory: bool = false,
    popen_result: ?host.ProcessResult = null,
    /// `fs` handles also have the `fs` file methods.
    fs_methods: bool = false,
};
```

<a id="fn-newfile"></a>

## newFile

```zig
pub fn newFile(state: *State, options: FileOptions) !Value
```

References: [`FileOptions`](#type-fileoptions)

<a id="fn-finalizefile"></a>

## finalizeFile

Closes an unreachable open handle for the collector, like PUC's `__gc`:
buffered writes are flushed and the file is closed. Failures are ignored,
as `__gc` ignores the result of C `fclose`.

```zig
pub fn finalizeFile(state: *State, userdata: *Userdata) void
```

<a id="fn-closefinalizerorder"></a>

## closeFinalizerOrder

The finalization order of an open handle `State.deinit` must close, or null.

```zig
pub fn closeFinalizerOrder(userdata: *Userdata) ?u64
```

<a id="fn-hasopenfiles"></a>

## hasOpenFiles

```zig
pub fn hasOpenFiles(state: *State) bool
```

<a id="fn-closeopenfiles"></a>

## closeOpenFiles

Closes every open file handle, newest first, like `lua_close` running
their `__gc`: buffered writes are flushed and failures are ignored.
`State.deinit` calls this; reset discards handles without closing them.

```zig
pub fn closeOpenFiles(state: *State) void
```

<a id="fn-read"></a>

## read

```zig
pub fn read(state: *State, thread: *Thread, op: bytecode.Call) !void
```

<a id="fn-write"></a>

## write

```zig
pub fn write(state: *State, thread: *Thread, op: bytecode.Call) !void
```

<a id="fn-open"></a>

## open

```zig
pub fn open(state: *State, thread: *Thread, op: bytecode.Call) !void
```

<a id="fn-preparewrite"></a>

## prepareWrite

Readies the file of an open for its mode, like `fopen`: "w" truncates it,
and "a" creates it when missing or checks it is writable without
rewriting it, so bytes other writers append meanwhile survive.

```zig
pub fn prepareWrite(state: *State, path: []const u8, parsed: ParsedMode, exists: bool) anyerror!void
```

References: [`ParsedMode`](#type-parsedmode)

<a id="fn-popen"></a>

## popen

```zig
pub fn popen(state: *State, thread: *Thread, op: bytecode.Call) !void
```

<a id="fn-filetostring"></a>

## fileTostring

```zig
pub fn fileTostring(state: *State, thread: *Thread, op: bytecode.Call) !void
```

<a id="fn-input"></a>

## input

```zig
pub fn input(state: *State, thread: *Thread, op: bytecode.Call) !void
```

<a id="fn-output"></a>

## output

```zig
pub fn output(state: *State, thread: *Thread, op: bytecode.Call) !void
```

<a id="fn-close"></a>

## close

```zig
pub fn close(state: *State, thread: *Thread, op: bytecode.Call) !void
```

<a id="fn-flush"></a>

## flush

```zig
pub fn flush(state: *State, thread: *Thread, op: bytecode.Call) !void
```

<a id="fn-lines"></a>

## lines

```zig
pub fn lines(state: *State, thread: *Thread, op: bytecode.Call) !void
```

<a id="fn-tmpfile"></a>

## tmpfile

```zig
pub fn tmpfile(state: *State, thread: *Thread, op: bytecode.Call) !void
```

<a id="fn-typevalue"></a>

## typeValue

```zig
pub fn typeValue(state: *State, thread: *Thread, op: bytecode.Call) !void
```

<a id="fn-fileread"></a>

## fileRead

```zig
pub fn fileRead(state: *State, thread: *Thread, op: bytecode.Call) !void
```

<a id="fn-filewrite"></a>

## fileWrite

```zig
pub fn fileWrite(state: *State, thread: *Thread, op: bytecode.Call) !void
```

<a id="fn-fileclose"></a>

## fileClose

```zig
pub fn fileClose(state: *State, thread: *Thread, op: bytecode.Call) !void
```

<a id="fn-filegc"></a>

## fileGc

`__gc` and `__close`: closes an open handle and ignores closed and
standard ones, like PUC's `f_gc`.

```zig
pub fn fileGc(state: *State, thread: *Thread, op: bytecode.Call) !void
```

<a id="fn-fileseek"></a>

## fileSeek

```zig
pub fn fileSeek(state: *State, thread: *Thread, op: bytecode.Call) !void
```

<a id="fn-fileflush"></a>

## fileFlush

```zig
pub fn fileFlush(state: *State, thread: *Thread, op: bytecode.Call) !void
```

<a id="fn-filelines"></a>

## fileLines

```zig
pub fn fileLines(state: *State, thread: *Thread, op: bytecode.Call) !void
```

<a id="fn-filesetvbuf"></a>

## fileSetvbuf

```zig
pub fn fileSetvbuf(state: *State, thread: *Thread, op: bytecode.Call) !void
```

<a id="fn-linesiter"></a>

## linesIter

```zig
pub fn linesIter(state: *State, thread: *Thread, op: bytecode.Call) !void
```

<a id="fn-linesnext"></a>

## linesNext

```zig
pub fn linesNext(state: *State, iterator: Value) ![]const Value
```

<a id="fn-readallstdin"></a>

## readAllStdin

Reads the rest of standard input for `dofile()` and `loadfile()`, sharing
the `io.stdin` position. The caller owns the bytes.

```zig
pub fn readAllStdin(state: *State) ![]u8
```

<a id="fn-readstdinline"></a>

## readStdinLine

Reads one line, including its newline, from standard input; null at end of input.

```zig
pub fn readStdinLine(state: *State) !?[]const u8
```

<a id="fn-readremaining"></a>

## readRemaining

Returns the unread bytes of an open, readable file and moves it to the
end, for decoders that accept a FILE*. The bytes stay valid until the
handle is next used.

```zig
pub fn readRemaining(state: *State, userdata: *Userdata) ![]const u8
```

<a id="fn-truncatefile"></a>

## truncateFile

Sets a file's size for `fs` file `truncate` and writes the result through
the filesystem capability. The handle keeps its bytes if the write fails.

```zig
pub fn truncateFile(state: *State, userdata: *Userdata, size: usize) !void
```

<a id="fn-flushopenfiles"></a>

## flushOpenFiles

Writes the buffered output of every open file handle, as C `exit` flushes
all streams. Used by the CLI before the process ends; errors are ignored.

```zig
pub fn flushOpenFiles(state: *State) void
```

<a id="fn-checkedfile"></a>

## checkedFile

The handle behind a value, checked like `luaL_testudata(L, i, "FILE*")`:
a file userdata whose metatable is still a file metatable. A handle given
another metatable with `debug.setmetatable` is not a file.

```zig
pub fn checkedFile(state: *State, value: Value) ?*Userdata
```

<a id="type-parsedmode"></a>

## ParsedMode

```zig
pub const ParsedMode = struct {
    kind: u8,
    append: bool,
    reads_existing: bool,
    plus: bool = false,
};
```

### Nested Declarations

| Name | Parameters | Return Type | Description |
| --- | --- | --- | --- |
| [readable](#fn-parsedmode-readable) | `self: ParsedMode` | `bool` |  |
| [writable](#fn-parsedmode-writable) | `self: ParsedMode` | `bool` |  |

<a id="fn-parsedmode-readable"></a>

### ParsedMode.readable

```zig
pub fn readable(self: ParsedMode) bool
```

References: [`ParsedMode`](#type-parsedmode)

<a id="fn-parsedmode-writable"></a>

### ParsedMode.writable

```zig
pub fn writable(self: ParsedMode) bool
```

References: [`ParsedMode`](#type-parsedmode)

<a id="fn-parsemode"></a>

## parseMode

```zig
pub fn parseMode(mode: []const u8) ?ParsedMode
```

References: [`ParsedMode`](#type-parsedmode)

<a id="fn-newstandardfile"></a>

## newStandardFile

Wraps a standard stream for `io.stdin`, `io.stdout`, and `io.stderr`.
Standard streams read and write through the state's stdin source and
output writers, never through a buffer.

```zig
pub fn newStandardFile(state: *State, kind: File.Kind) !Value
```

References: [`File.Kind`](#type-file-kind)

