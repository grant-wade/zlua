# stdlib.fs

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
- [runtime.vm](../runtime/vm.md)
- [runtime.tests](../runtime/tests.md)
- [runtime.internal](../runtime/internal.md)
- [testing](../testing.md)
- [testing.clua](../testing/clua.md)
- [testing.bench_runner](../testing/bench_runner.md)
- [testing.c_api_runner](../testing/c_api_runner.md)
- [testing.diff_runner](../testing/diff_runner.md)
- [testing.expected_failures](../testing/expected_failures.md)
- [testing.metadata](../testing/metadata.md)
- [testing.normalizer](../testing/normalizer.md)
- [testing.extension_runner](../testing/extension_runner.md)
- [testing.official_suite](../testing/official_suite.md)

</details>

## Functions

- [read](#fn-read)
- [write](#fn-write)
- [open](#fn-open)
- [stat](#fn-stat)
- [exists](#fn-exists)
- [list](#fn-list)
- [scandir](#fn-scandir)
- [walk](#fn-walk)
- [mkdir](#fn-mkdir)
- [remove](#fn-remove)
- [copy](#fn-copy)
- [rename](#fn-rename)
- [move](#fn-move)
- [touch](#fn-touch)
- [openDir](#fn-opendir)
- [iteratorNextNative](#fn-iteratornextnative)
- [iteratorNext](#fn-iteratornext)
- [iteratorClose](#fn-iteratorclose)
- [iteratorSkip](#fn-iteratorskip)
- [errorTostring](#fn-errortostring)
- [fileStat](#fn-filestat)
- [fileTell](#fn-filetell)
- [fileTruncate](#fn-filetruncate)
- [filePath](#fn-filepath)
- [dirEntries](#fn-direntries)
- [dirWalk](#fn-dirwalk)
- [dirOpen](#fn-diropen)
- [dirStat](#fn-dirstat)
- [dirMkdir](#fn-dirmkdir)
- [dirRemove](#fn-dirremove)
- [dirClose](#fn-dirclose)
- [pathJoin](#fn-pathjoin)
- [pathNormalize](#fn-pathnormalize)
- [pathBasename](#fn-pathbasename)
- [pathExtension](#fn-pathextension)
- [pathStem](#fn-pathstem)
- [pathDirname](#fn-pathdirname)
- [pathIsAbsolute](#fn-pathisabsolute)
- [pathRelative](#fn-pathrelative)

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

<a id="fn-stat"></a>

## stat

```zig
pub fn stat(state: *State, thread: *Thread, op: bytecode.Call) !void
```

<a id="fn-exists"></a>

## exists

```zig
pub fn exists(state: *State, thread: *Thread, op: bytecode.Call) !void
```

<a id="fn-list"></a>

## list

```zig
pub fn list(state: *State, thread: *Thread, op: bytecode.Call) !void
```

<a id="fn-scandir"></a>

## scandir

```zig
pub fn scandir(state: *State, thread: *Thread, op: bytecode.Call) !void
```

<a id="fn-walk"></a>

## walk

```zig
pub fn walk(state: *State, thread: *Thread, op: bytecode.Call) !void
```

<a id="fn-mkdir"></a>

## mkdir

```zig
pub fn mkdir(state: *State, thread: *Thread, op: bytecode.Call) !void
```

<a id="fn-remove"></a>

## remove

```zig
pub fn remove(state: *State, thread: *Thread, op: bytecode.Call) !void
```

<a id="fn-copy"></a>

## copy

```zig
pub fn copy(state: *State, thread: *Thread, op: bytecode.Call) !void
```

<a id="fn-rename"></a>

## rename

```zig
pub fn rename(state: *State, thread: *Thread, op: bytecode.Call) !void
```

<a id="fn-move"></a>

## move

```zig
pub fn move(state: *State, thread: *Thread, op: bytecode.Call) !void
```

<a id="fn-touch"></a>

## touch

```zig
pub fn touch(state: *State, thread: *Thread, op: bytecode.Call) !void
```

<a id="fn-opendir"></a>

## openDir

```zig
pub fn openDir(state: *State, thread: *Thread, op: bytecode.Call) !void
```

<a id="fn-iteratornextnative"></a>

## iteratorNextNative

```zig
pub fn iteratorNextNative(state: *State, thread: *Thread, op: bytecode.Call) !void
```

<a id="fn-iteratornext"></a>

## iteratorNext

```zig
pub fn iteratorNext(state: *State, iterator: Value) ![]const Value
```

<a id="fn-iteratorclose"></a>

## iteratorClose

```zig
pub fn iteratorClose(state: *State, thread: *Thread, op: bytecode.Call) !void
```

<a id="fn-iteratorskip"></a>

## iteratorSkip

```zig
pub fn iteratorSkip(state: *State, thread: *Thread, op: bytecode.Call) !void
```

<a id="fn-errortostring"></a>

## errorTostring

```zig
pub fn errorTostring(state: *State, thread: *Thread, op: bytecode.Call) !void
```

<a id="fn-filestat"></a>

## fileStat

```zig
pub fn fileStat(state: *State, thread: *Thread, op: bytecode.Call) !void
```

<a id="fn-filetell"></a>

## fileTell

```zig
pub fn fileTell(state: *State, thread: *Thread, op: bytecode.Call) !void
```

<a id="fn-filetruncate"></a>

## fileTruncate

```zig
pub fn fileTruncate(state: *State, thread: *Thread, op: bytecode.Call) !void
```

<a id="fn-filepath"></a>

## filePath

```zig
pub fn filePath(state: *State, thread: *Thread, op: bytecode.Call) !void
```

<a id="fn-direntries"></a>

## dirEntries

```zig
pub fn dirEntries(state: *State, thread: *Thread, op: bytecode.Call) !void
```

<a id="fn-dirwalk"></a>

## dirWalk

```zig
pub fn dirWalk(state: *State, thread: *Thread, op: bytecode.Call) !void
```

<a id="fn-diropen"></a>

## dirOpen

```zig
pub fn dirOpen(state: *State, thread: *Thread, op: bytecode.Call) !void
```

<a id="fn-dirstat"></a>

## dirStat

```zig
pub fn dirStat(state: *State, thread: *Thread, op: bytecode.Call) !void
```

<a id="fn-dirmkdir"></a>

## dirMkdir

```zig
pub fn dirMkdir(state: *State, thread: *Thread, op: bytecode.Call) !void
```

<a id="fn-dirremove"></a>

## dirRemove

```zig
pub fn dirRemove(state: *State, thread: *Thread, op: bytecode.Call) !void
```

<a id="fn-dirclose"></a>

## dirClose

```zig
pub fn dirClose(state: *State, thread: *Thread, op: bytecode.Call) !void
```

<a id="fn-pathjoin"></a>

## pathJoin

```zig
pub fn pathJoin(state: *State, thread: *Thread, op: bytecode.Call) !void
```

<a id="fn-pathnormalize"></a>

## pathNormalize

```zig
pub fn pathNormalize(state: *State, thread: *Thread, op: bytecode.Call) !void
```

<a id="fn-pathbasename"></a>

## pathBasename

```zig
pub fn pathBasename(state: *State, thread: *Thread, op: bytecode.Call) !void
```

<a id="fn-pathextension"></a>

## pathExtension

```zig
pub fn pathExtension(state: *State, thread: *Thread, op: bytecode.Call) !void
```

<a id="fn-pathstem"></a>

## pathStem

```zig
pub fn pathStem(state: *State, thread: *Thread, op: bytecode.Call) !void
```

<a id="fn-pathdirname"></a>

## pathDirname

```zig
pub fn pathDirname(state: *State, thread: *Thread, op: bytecode.Call) !void
```

<a id="fn-pathisabsolute"></a>

## pathIsAbsolute

```zig
pub fn pathIsAbsolute(state: *State, thread: *Thread, op: bytecode.Call) !void
```

<a id="fn-pathrelative"></a>

## pathRelative

```zig
pub fn pathRelative(state: *State, thread: *Thread, op: bytecode.Call) !void
```

