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
- [runtime.state](../runtime/state.md)
- [stdlib](../stdlib.md)
- [stdlib.base](../stdlib/base.md)
- [runtime.call](../runtime/call.md)
- [runtime.coroutine](../runtime/coroutine.md)
- [runtime.debug](../runtime/debug.md)
- [runtime.metatable](../runtime/metatable.md)
- [runtime.rollback](../runtime/rollback.md)
- [runtime.value](../runtime/value.md)
- [runtime.number_format](../runtime/number_format.md)
- [runtime.host](../runtime/host.md)
- [runtime.upvalue](../runtime/upvalue.md)
- [runtime.failure](../runtime/failure.md)
- [runtime.io](../runtime/io.md)
- [runtime.load](../runtime/load.md)
- [runtime.vm](../runtime/vm.md)
- [runtime.gc](../runtime/gc.md)
- [runtime.entry](../runtime/entry.md)
- [runtime.system](../runtime/system.md)
- [runtime.timezone](../runtime/timezone.md)
- [runtime.index](../runtime/index.md)
- [runtime.operators](../runtime/operators.md)
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
- [stdlib.static_strings](../stdlib/static_strings.md)
- [stdlib.os](../stdlib/os.md)
- [stdlib.package](../stdlib/package.md)
- [stdlib.json](../stdlib/json.md)
- [stdlib.zerde_lua](../stdlib/zerde_lua.md)
- [stdlib.toml](../stdlib/toml.md)
- [stdlib.msgpack](../stdlib/msgpack.md)
- [stdlib.csv](../stdlib/csv.md)
- [stdlib.fs](../stdlib/fs.md)
- [runtime.budget](../runtime/budget.md)
- [runtime.strings](../runtime/strings.md)
- [runtime.execute](../runtime/execute.md)
- [testing.process](../testing/process.md)
- [runtime.tests](../runtime/tests.md)
- [runtime.internal](../runtime/internal.md)
- [runtime.native_fn](../runtime/native_fn.md)
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
- [testing.parallel](../testing/parallel.md)
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

Payload of every `FILE*` userdata; buffers the whole file. Mutate only
through `writable` so rollback can copy it before the first change.

```zig
pub const File = struct {
    kind: Kind,
    /// Owned file path or popen command; empty otherwise.
    path: []const u8 = "",
    readable: bool,
    writable: bool,
    append: bool = false,
    closed: bool = false,
    buffer_mode: BufferMode = .full,
    /// C `fopen` succeeds on directories; reads then fail.
    is_directory: bool = false,
    device_pending: bool = false,
    content: std.ArrayList(u8) = .empty,
    pos: usize = 0,
    /// Prefix of `content` known to match the host file.
    synced: usize = 0,
    /// `State.file_generation` when the handle last matched the filesystem.
    generation: u64 = 0,
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
    regular,
    popen,
    null_device,
    /// Linux `/dev/full`: endless zero reads; flushing fails with `ENOSPC`.
    full_device,
    /// `io.tmpfile`: memory only.
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

```zig
pub fn fileTypeId() usize
```

<a id="fn-fileof"></a>

## fileOf

Read-only view of a handle's file; null for other values.

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
    /// Allocated by the state allocator; `newFile` takes ownership even on failure.
    contents: []const u8 = "",
    buffer_mode: File.BufferMode = .full,
    is_directory: bool = false,
    popen_result: ?host.ProcessResult = null,
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

Collector finalizer: flushes and closes an open handle, ignoring failures like PUC's `__gc`.

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

Flushes and closes every open handle, newest first, like `lua_close` running their `__gc`.

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

Like `fopen`: "w" truncates; "a" creates the file or checks it is writable
without rewriting it, so concurrent appends by other writers survive.

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

`__gc` and `__close`, like PUC's `f_gc`.

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

Reads the rest of stdin, sharing the `io.stdin` position. Caller owns the bytes.

```zig
pub fn readAllStdin(state: *State) ![]u8
```

<a id="fn-readstdinline"></a>

## readStdinLine

Reads one line from stdin, keeping the newline; null at end of input.

```zig
pub fn readStdinLine(state: *State) !?[]const u8
```

<a id="fn-readremaining"></a>

## readRemaining

Consumes the unread bytes of a file; they stay valid until the handle is next used.

```zig
pub fn readRemaining(state: *State, userdata: *Userdata) ![]const u8
```

<a id="fn-truncatefile"></a>

## truncateFile

Resizes the file through the filesystem capability; the handle is unchanged on failure.

```zig
pub fn truncateFile(state: *State, userdata: *Userdata, size: usize) !void
```

<a id="fn-flushopenfiles"></a>

## flushOpenFiles

Flushes every open handle, as C `exit` does; errors are ignored.

```zig
pub fn flushOpenFiles(state: *State) void
```

<a id="fn-checkedfile"></a>

## checkedFile

Like `luaL_testudata(L, i, "FILE*")`: a handle whose metatable was replaced is not a file.

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
| [opensAtEnd](#fn-parsedmode-opensatend) | `self: ParsedMode` | `bool` | Whether the host's &#96;fopen&#96; starts at the end: BSD for every append mode, glibc only for "a", musl and the Windows CRT never. |

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

<a id="fn-parsedmode-opensatend"></a>

### ParsedMode.opensAtEnd

Whether the host's `fopen` starts at the end: BSD for every append mode,
glibc only for "a", musl and the Windows CRT never.

```zig
pub fn opensAtEnd(self: ParsedMode) bool
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

Unbuffered handle over the state's stdin source or output writers.

```zig
pub fn newStandardFile(state: *State, kind: File.Kind) !Value
```

References: [`File.Kind`](#type-file-kind)

