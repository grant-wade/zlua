# runtime.io

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

- [readFileAlloc](#fn-readfilealloc)
- [readFileRaw](#fn-readfileraw)
- [writeStdout](#fn-writestdout)
- [warn](#fn-warn)
- [warnError](#fn-warnerror)
- [writeStderr](#fn-writestderr)
- [flushStdoutAfterPrint](#fn-flushstdoutafterprint)
- [flushStdout](#fn-flushstdout)
- [flushStderr](#fn-flushstderr)
- [writeFile](#fn-writefile)
- [removeFile](#fn-removefile)
- [renameFile](#fn-renamefile)
- [fsReadFileAlloc](#fn-fsreadfilealloc)
- [fsWriteFile](#fn-fswritefile)
- [fsCreateFileExclusive](#fn-fscreatefileexclusive)
- [fsWriteFileAt](#fn-fswritefileat)
- [fsAppendFile](#fn-fsappendfile)
- [fsCheckWritable](#fn-fscheckwritable)
- [fsStat](#fn-fsstat)
- [fsReadDirAlloc](#fn-fsreaddiralloc)
- [fsMakeDir](#fn-fsmakedir)
- [fsRemovePath](#fn-fsremovepath)
- [fsRenamePath](#fn-fsrenamepath)
- [fsCopyFile](#fn-fscopyfile)
- [requireIo](#fn-requireio)
- [stdinSource](#fn-stdinsource)
- [stdinIsStream](#fn-stdinisstream)
- [appendErrorValue](#fn-appenderrorvalue)
- [appendValue](#fn-appendvalue)
- [isFileValue](#fn-isfilevalue)
- [isClosedFileValue](#fn-isclosedfilevalue)

<a id="fn-readfilealloc"></a>

## readFileAlloc

Failures raise PUC `loadfile`-style messages such as "cannot open name.lua: No such file or directory".

```zig
pub fn readFileAlloc(self: *State, path: []const u8) ![]const u8
```

<a id="fn-readfileraw"></a>

## readFileRaw

Like `readFileAlloc`, but returns filesystem errors unchanged.

```zig
pub fn readFileRaw(self: *State, path: []const u8) anyerror![]const u8
```

<a id="fn-writestdout"></a>

## writeStdout

```zig
pub fn writeStdout(self: *State, bytes: []const u8) !void
```

<a id="fn-warn"></a>

## warn

Emits one warning made of `parts`, like continued `lua_warning` calls. A single
part starting with `@` is a control message.

```zig
pub fn warn(self: *State, parts: []const []const u8) !void
```

<a id="fn-warnerror"></a>

## warnError

Like `luaE_warnerror`: warns `error in <where> (<message>)`.

```zig
pub fn warnError(self: *State, where: []const u8, error_value: Value) void
```

<a id="fn-writestderr"></a>

## writeStderr

```zig
pub fn writeStderr(self: *State, bytes: []const u8) !void
```

<a id="fn-flushstdoutafterprint"></a>

## flushStdoutAfterPrint

```zig
pub fn flushStdoutAfterPrint(self: *State) !void
```

<a id="fn-flushstdout"></a>

## flushStdout

```zig
pub fn flushStdout(self: *State) !void
```

<a id="fn-flushstderr"></a>

## flushStderr

```zig
pub fn flushStderr(self: *State) !void
```

<a id="fn-writefile"></a>

## writeFile

```zig
pub fn writeFile(self: *State, path: []const u8, data: []const u8) !void
```

<a id="fn-removefile"></a>

## removeFile

```zig
pub fn removeFile(self: *State, path: []const u8) !void
```

<a id="fn-renamefile"></a>

## renameFile

```zig
pub fn renameFile(self: *State, old_path: []const u8, new_path: []const u8) !void
```

<a id="fn-fsreadfilealloc"></a>

## fsReadFileAlloc

Also capped by `max_file_bytes`.

```zig
pub fn fsReadFileAlloc(self: *State, path: []const u8, requested_max_bytes: usize) anyerror![]const u8
```

<a id="fn-fswritefile"></a>

## fsWriteFile

```zig
pub fn fsWriteFile(self: *State, path: []const u8, data: []const u8) anyerror!void
```

<a id="fn-fscreatefileexclusive"></a>

## fsCreateFileExclusive

Reserves a new empty file like `mkstemp`, failing with `error.PathAlreadyExists`.
Only host filesystems create exclusively; others check first.

```zig
pub fn fsCreateFileExclusive(self: *State, path: []const u8) anyerror!void
```

<a id="fn-fswritefileat"></a>

## fsWriteFileAt

Writes into an existing file without truncating it. Returns `error.OperationUnsupported`
without positional writes; callers then fall back to `fsWriteFile`.

```zig
pub fn fsWriteFileAt(self: *State, path: []const u8, offset: usize, data: []const u8) anyerror!void
```

<a id="fn-fsappendfile"></a>

## fsAppendFile

Custom filesystems lack positional writes, so the whole file is rewritten.

```zig
pub fn fsAppendFile(self: *State, path: []const u8, data: []const u8) anyerror!void
```

<a id="fn-fscheckwritable"></a>

## fsCheckWritable

Checks an existing file is writable without changing it, as `fopen` does for append modes.

```zig
pub fn fsCheckWritable(self: *State, path: []const u8) anyerror!void
```

<a id="fn-fsstat"></a>

## fsStat

```zig
pub fn fsStat(self: *State, path: []const u8, follow_symlinks: bool) anyerror!host.FileStat
```

<a id="fn-fsreaddiralloc"></a>

## fsReadDirAlloc

```zig
pub fn fsReadDirAlloc(self: *State, path: []const u8) anyerror![]host.DirectoryEntry
```

<a id="fn-fsmakedir"></a>

## fsMakeDir

```zig
pub fn fsMakeDir(self: *State, path: []const u8, parents: bool) anyerror!void
```

<a id="fn-fsremovepath"></a>

## fsRemovePath

```zig
pub fn fsRemovePath(self: *State, path: []const u8, recursive: bool) anyerror!void
```

<a id="fn-fsrenamepath"></a>

## fsRenamePath

```zig
pub fn fsRenamePath(self: *State, old_path: []const u8, new_path: []const u8) anyerror!void
```

<a id="fn-fscopyfile"></a>

## fsCopyFile

```zig
pub fn fsCopyFile(self: *State, source: []const u8, destination: []const u8, overwrite: bool) anyerror!void
```

<a id="fn-requireio"></a>

## requireIo

```zig
pub fn requireIo(self: *State, unavailable_message: []const u8) RuntimeError!std.Io
```

<a id="fn-stdinsource"></a>

## stdinSource

Callers read through `reader()` and then call `finish()`.

```zig
pub fn stdinSource(self: *State) StdinSource
```

<a id="fn-stdinisstream"></a>

## stdinIsStream

```zig
pub fn stdinIsStream(self: *const State) bool
```

<a id="fn-appenderrorvalue"></a>

## appendErrorValue

Like `appendValue`, but a nil error object becomes `<no error object>`.

```zig
pub fn appendErrorValue(allocator: std.mem.Allocator, out: *std.ArrayList(u8), value: Value) !void
```

<a id="fn-appendvalue"></a>

## appendValue

Formats without metamethods; file handles format like their `__tostring`.

```zig
pub fn appendValue(allocator: std.mem.Allocator, out: *std.ArrayList(u8), value: Value) !void
```

<a id="fn-isfilevalue"></a>

## isFileValue

```zig
pub fn isFileValue(value: Value) bool
```

<a id="fn-isclosedfilevalue"></a>

## isClosedFileValue

```zig
pub fn isClosedFileValue(value: Value) bool
```

