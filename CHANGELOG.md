# Changelog

## Unreleased

### Breaking changes

- Strings read from Lua are `String` handles, including `Value.string`.
- Reading a `[]const u8` or `*T` anywhere but a callback argument is a compile
  error.
- Reading an enum, struct, or non-byte slice outside `decode` is a compile
  error.
- `State.createModule`, `DoOptions`, `GcBudget`, `Table.rawNext`,
  `DebugOptions.capture_output`, and `Userdata.method`, `metamethod`, and
  `bindMethods` are removed.
- `State.stepGc` takes a step count.
- Registering a function again under the same name returns the same Lua
  function.
- `newUserdata` binds the methods of `T` and defines `T` on first use, and
  `wrapUserdata` wraps host-owned storage. `newUserdataAuto`, `newUserdataPtr`,
  `newUserdataPtrAuto`, and `UserdataPtrOptions` are removed.
- `registerUserdataInitializerWith` is `registerConstructor`.
- `State.init` and `Snapshot.newState` return `*State`, and `deinit` frees it.
- `protectedCall`, `protectedCallWith`, `protectedResume`,
  `protectedResumeWith`, `protectedClose`, and `CallResult` are removed. Lua
  failures return `error.LuaError`, and `State.takeError` returns the error.
- `Coroutine.resumeCoroutineWith` takes `ResumeOptions`.
- `State.errorMessage`, `describeError`, and `takeErrorValue` are
  `writeError` and `takeError`, and `ErrorRef.message` is `writeMessage`.
- `Function.dumpBytecode` writes to a `std.Io.Writer`.

### Data Formats

- JSON, TOML, MessagePack, and CSV are built into zlua, which has no package
  dependencies.
- Reader errors give the line and column, or the byte offset for MessagePack.
- Writer errors give the path to the value, such as `$.servers[2].port`.
- `toml.read` accepts TOML 1.1 and reads dates and times as `datetime` values.
- MessagePack timestamps read and write as `datetime` values, and other
  extension types as values from `msgpack.extension`.
- `msgpack.read` reads a `uint64` above the integer range as a float.
- `msgpack.write` writes floats as `float32` when that is exact.
- `toml.write` writes `inf`, `-inf`, and `nan`, and `msgpack.write` writes
  non-finite floats.
- `csv.write` writes floats with a fraction or exponent.
- `csv.read` accepts cells that aren't valid UTF-8 and reads a quoted empty
  cell as `""`, and `csv.write` writes an empty string as `""`.
- MessagePack map keys that aren't valid UTF-8 are written and read as `bin`.
- `toml.write` writes an empty inline table as `{}`.
- The null sentinel and the array and object metatables are named `null`,
  `array`, and `object`.

### Datetime

- The `datetime` library parses, builds, compares, formats, and adds to dates and
  times. It is in `safe` and `full`, and `datetime.now` needs `os`.

### Performance

- `string.find`, `string.match`, `string.gmatch`, and `string.gsub` match
  patterns faster.
- Numeric `for` loops, backward jumps, and instruction dispatch are faster.
- Reading and writing upvalues is faster.
- Copying values between registers, upvalues, and tables is faster.
- Float arithmetic is faster.
- Lua function calls and returns are faster.
- `pcall` and `xpcall` of a Lua function are faster.
- Calls from Zig into Lua pass their arguments without allocating.

### Packaging

- `THIRD_PARTY_NOTICES` is now `THIRD_PARTY_NOTICES.md`, installed to
  `share/licenses/zlua/THIRD_PARTY_NOTICES.md`, and also lists the conformance
  suites.

### Testing

- `zig build test-formats` runs toml-test, msgpack-test-suite, JSONTestSuite,
  and csv-spectrum, and `zig build ci` includes it.
- `fetch-lua` and `fetch-format-tests` download archives with a Zig tool instead
  of a shell script.
- The scheduled fuzz workflow is removed.
- Harness steps build only the binaries they run.
- Unit test fuzz sweeps run across threads.

### Fixes

- Strings returned by `Function.call`, `Table.get`, and other reads could be
  freed while still in use.
- Registering callbacks, and creating userdata with a shared metatable, added
  callback entries that were never freed.
- Setting a numeric `for` variable with `debug.setlocal` changed how many times
  the loop ran.
- `msgpack.read` panicked on an array or map length longer than the input.

## 0.8.1

### Breaking changes

- Binary chunks from earlier versions no longer load.

### Performance

- Instructions are 8 bytes instead of 16.
- Table stores, returns, and conditions read local registers without copying
  them.
- Method lookups, upvalue table fields, integer-constant indexes, and constant
  field stores each take one instruction.
- Entering a Lua function clears only its missing parameters.
- Lua tail calls, closure creation, returns that close upvalues, and returns to
  multiple-result calls run in the fast loop.
- Natives such as `table.sort` and `pcall` push fixed-parameter Lua frames
  directly.

### Lua Compatibility

- The reference interpreter and official test suite are Lua 5.5.1.
- `table.unpack` raises an argument error for values that can't act as a table.
- Table functions accept non-table values whose metatables provide the
  metamethods they use, and strings need no `__len`.
- Locals of a block stay visible to `debug.getlocal` while its to-be-closed
  variables close.
- `table.sort` reads and writes elements in place in the same order as Lua, so
  `__index`, `__newindex`, comparators, and errors see the same table states.
- `table.sort` accepts up to `INT_MAX - 1` elements instead of 1,000,000.
- Line hooks reported line 1 for table constructor instructions.
- Multiple assignments store from right to left, and indexed targets read local
  keys and tables when the store runs.
- Error messages name `t["k"]`, `t[1]`, other indexed values, and a nil `_ENV`
  like Lua 5.5.
- Long chains of left-associative operators compile instead of failing with too
  many registers.

### Embedding API

- Zig functions convert to Lua functions wherever Zig values are passed to Lua.
- Struct and enum types, including Zig files, convert to tables of their public
  declarations, and enum types also map each tag to its name.
- `State.setGlobals` sets a global for each field of a struct.
- `State.createTableFrom` creates a table from a struct.
- `Table.setFields` assigns each field of a struct to a table.
- A typed callback parameter that Lua can't pass is a compile error.

### Testing

- CI runs on Zig 0.16.0 and 0.17.1.

### Fixes

- `table.remove` could free the removed value when removing the last element
  of a proxy table ran `__newindex`.
- Growing a table's array part past integer keys held in its hash part hid those
  keys, and `pairs` over the table never finished.

## 0.8.0

### Breaking changes

- `Value.unsupported` is removed.
- Userdata finalizers take the state's allocator as a second parameter.
- Typed callbacks and userdata methods release handle parameters when they
  return, and must not deinitialize them.
- `load`, `loadfile`, `dofile`, and `require` reject binary chunks in embedded
  states unless `Options.binary_chunks` is set.
- `getmetatable` returns false for userdata metatables zlua creates, unless
  `UserdataType.expose_metatable` is set.
- States keep a copy of Lua output only when `DebugOptions.capture_output` is
  set.

### Sandbox

- Long `f()()`, `or`, `and`, and arithmetic chains no longer overflow the native stack in the compiler.
- `toml.read` rejects nesting deeper than 64 levels instead of overflowing the native stack.
- zerde is updated to 0.3.4, which parses TOML iteratively.
- `Limits.max_native_stack` limits native stack use, raising `C stack overflow`.
- `max_instructions` and per-call budgets charge native work by its size.
- The compiler polls for interrupts.
- `Limits.max_finalizer_instructions` bounds Lua `__gc` run by `deinit`, `collect`, and `stepGc`, and defaults to 1,000,000.
- `Limits.max_output_bytes` limits Lua output, with `State.outputBytes` and `State.resetOutputLimit`.
- `Limits.untrusted` is a preset for code you don't trust.
- Garbage is collected before `max_memory` fails an allocation.
- A bound `__gc` runs at most once per object, and typed access afterward fails with `error.UserdataClosed`.
- `decode` rejects values nested more than 200 levels deep.
- A numeric `for` over non-numbers in a binary chunk raises an error message.
- Table keys and strings chosen to collide made table and string interning operations slow.
- A crafted TZif file no longer overflows an integer in the timezone parser.
- `utf8.offset` with `math.mininteger` aborted the process.
- `tonumber` with a base aborted the process when the value overflowed an integer.
- Converting the float `2^63` to a Zig integer aborted the process.
- Dotted `require` names failed on Windows with memory and `host_dir` filesystems.
- A collector step as a coroutine finished with a finalizer pending aborted the process.
- `json`, `toml`, `msgpack`, and `csv` functions reported exceeding `max_memory` as `WriteFailed`.
- `host_dir` filesystems reject drive-relative paths, alternate data streams, and device names on Windows.

### Lua Compatibility

- Indexing a non-table with a nil or NaN key raises an error, and such keys reach `__index`.
- `__index` functions receive float keys unchanged.
- `math.type` requires an argument, and `math.modf` keeps integers exact.
- `select` with an index past its arguments returns nothing.
- `setmetatable` requires its second argument, and `error` checks its level.
- `tonumber`, `string.gmatch`, `utf8.codepoint`, and `utf8.offset` check arguments in Lua's order.
- `string.pack` reports bad arguments as argument errors, and format strings end at a NUL byte.
- `coroutine.close` on the main thread and missing expressions after `return` use Lua's messages.

### Embedding API

- `Context.currentLine` returns the line of the running Lua function.
- `Function` and `Value.function` accept standard library functions and their
  iterators.
- `Value.typeName` returns the name Lua's `type` gives a value.
- `UserdataOptions.external_bytes` and `Userdata.setExternalBytes` report host
  storage to the collector.
- `State.defineUserdata` gives a userdata type one metatable, with typed methods
  and a name used by `tostring` and argument errors.
- `newUserdataAuto` and `newUserdataPtrAuto` share one metatable per type.
- `State.setHost` attaches a typed host pointer, read with `State.host`,
  `Context.host`, or a `Host(T)` typed callback parameter.
- `Context.functionName` returns the name a callback was registered under.
- `Context.raisef` raises a formatted error with the Lua position,
  `Context.argError` raises a `bad argument` error, and `Context.caller` returns
  a Lua function's source and line.
- `State.describeError` returns the Lua message or the name of an error from a
  state call.
- `decode` and `Decoder` read Lua values into Zig values by type with
  path-tracked errors, and `fromLua` hooks customize a type.
- Typed callbacks that return `void` keep return values set with
  `Context.returnValues`.
- Typed callbacks and userdata methods decode enum, array, vector, slice,
  struct, and `fromLua` parameters, and `Context.decodeArg` does the same in
  plain callbacks.
- Conversions to Lua turn enums into names, follow `lua` field options, and
  handle vectors, `std.EnumArray`, `std.EnumSet`, and `toLua` hooks.
- `State.handleScope` releases the handles created until its `end`.
- `analyze` lists a chunk's global reads and writes without running it.
- `Coroutine.protectedResumeWith` takes `ResumeOptions` for a traceback and a
  per-resume instruction budget.
- `Caller.short_source_len` gives the buffer length for `Caller.shortSource`.
- `UtcOffset`, `PopenResult`, and the other embedding types are exported from
  the package root.

### Performance

- Code under an instruction budget runs in the VM's fast loop.

### Fixes

- `Context.optionalArg` failed to compile.
- Callback integer arguments given a fractional number report that it has no
  integer representation.
- A large allocation ran only one collector step, so garbage holding large
  allocations outpaced collection.
- A minor collection ran at most one host userdata finalizer.
- Rooting a nil value let the next handle share its slot, so releasing one
  cleared the other.
- `fs.path.relative` aborted the process for most relative paths.
- A rooted host directory followed symlinks out of its root.
- Child processes inherited the host environment when the environment capability
  was disabled or custom.
- `State.reset` leaked a time zone loaded after the baseline.
- `fs.write` ignored `max_file_bytes`.
- `fs.move` failed across devices, and `os.rename` reported the wrong error.
- `json.write` and `toml.write` printed floats as integers, which the readers
  could reject.
- `--trace-vm` and `--debug-errors` printed nothing in the CLI.
- The differential harness passed without running fixtures when CLua was
  missing.
- `package.loaded` lacked `_G` and libraries opened by a separate `openLibs`
  call.
- Using a file handle in the wrong mode returned a different error from C Lua,
  and `lines` iterator errors lacked a position.
- `just` recipes re-parsed their arguments through bash.
- An `os.exit` inside a finalizer skipped the remaining finalizers in
  `State.deinit`.
- Process benchmark paths printed by `--list` did not work as selectors.

### Testing

- `zig build test-sandbox` runs hostile Lua scripts in Debug, ReleaseSafe, and
  ReleaseFast.
- `zig build test-diff-generated` compares generated programs under Lua 5.5 and
  zlua.
- `zig build test-stack-stress` runs the differential fixtures, moving the Lua
  stack on every growth check.
- CI runs these suites and the unit and differential tests in ReleaseSafe.
- A daily workflow runs the fuzz targets.

### Documentation

- The guides are rewritten against the implementation.
- `docs/security.md` covers running untrusted Lua, and `docs/snapshots.md` covers
  snapshots.

## 0.7.3

### Embedding API

- `Context.io` returns the state's configured `std.Io`.

### Fixes

- `require` ignored `package.searchers`, including custom searchers.
- `require` replaced a `package.loaded` entry set by a nil-returning loader with
  `true`.
- `require`, the default searchers, and `package.searchpath` report
  module-not-found and load errors with Lua 5.5's messages.
- `package.searchers` includes the C and all-in-one searchers, which report
  `package.cpath` matches as dynamic libraries not enabled.
- `require` and the embedding package helpers followed reassignments of the
  `package` global, `package.loaded`, and `package.preload`.
- `package.config`, `package.searchpath`, and the default searchers used `/`
  instead of `\` as the directory separator on Windows.
- Line-buffered writes to `/dev/full` on Linux, and `setvbuf` with pending
  output, returned different results than glibc.

## 0.7.2

### Performance

- Strings store their header and bytes in one allocation, and `Value` is 16
  bytes instead of 24. Short strings are always interned and compare by pointer,
  and string hashes are cached.
- Concatenation, `string.rep`, `string.format`, `string.gsub`, `string.upper`,
  `string.lower`, `string.reverse`, `string.char`, `table.concat`, and
  `utf8.char` build results in place or in a reused buffer.
- The collector keeps mark state and registry positions in a 16-byte header
  shared by every object type, and closures store their upvalue pointers in the
  same allocation.
- Snapshot workers find the objects created since capture by registry position,
  without a per-object hash table.
- Faster `#`, numeric and generic `for` loops, and write barriers.
- Arithmetic and comparisons with a numeric constant operand use dedicated
  instructions.
- Varargs stay on the caller's stack, and vararg calls and `...` run in the VM's
  fast loop.
- `pcall` and `xpcall` call their function in place without copying arguments or
  results.
- Table constructors reserve their exact size, table storage grows to
  power-of-two capacities, and each table's hash entries and index share one
  allocation.
- Each loaded chunk interns its string constants once for all of its closures,
  and field and global lookups compare those strings by pointer.
- Upvalues are 56 bytes instead of 72.
- Call frames are 40 bytes instead of 136.
- Tables, upvalues, closures, and strings of up to 128 bytes come from per-state
  size-class slabs.
- Tables are 64 bytes instead of 104.
- Field reads and writes start at the entry position where the key string was
  last found.

### Fixes

- A collection during a protected call could free the error value that the call
  restores on failure.
- `string.format` signs NaN like the host C library on FreeBSD and Windows, and
  raises an error for `%a` and `%A` with modifiers on Windows.
- `/dev/full` streams on FreeBSD report write and flush failures like FreeBSD's
  C library.
- Installs and the package include `THIRD_PARTY_NOTICES` with Lua's copyright
  and license.

### Testing

- CI runs on FreeBSD, and official-suite child processes have a 512 MiB memory
  cap on Linux and FreeBSD.
- `zig build bench` prints the host system and labels builds with the running
  Zig version's optimize mode name.

## 0.7.1

### Lua compatibility

- Pattern matching follows Lua's matcher: `*` and `+` no longer stop after 4096
  repetitions, long patterns no longer fail with `pattern too complex`, and
  quantifiers after `%b`, `%f`, and back-references are literal characters.
- `string.gsub` with a `^` anchor replaces at most once, and `string.gmatch`
  treats a leading `^` as a literal.
- A back-reference to a position capture fails to match instead of raising an
  error, and `%f[` without a closing `]` is a malformed pattern.
- Hexadecimal numerals with many digits or large exponents convert like Lua
  (`0xe03` followed by 1000 zeros and `p-4000` is `3587.0`, not `nan`).
- `coroutine.resume` returns `false, "too many results to resume"` when the
  results do not fit on the caller's stack, instead of raising a stack overflow.

### Fixes

- States without an instruction limit no longer hang on wasm32; fast-loop
  instruction accounting now wraps at 64 bits on 32-bit targets.
- Function prototypes created by `load`, `loadfile`, and coroutines were never
  freed, so a state that kept loading chunks grew without bound. The collector
  now frees a chunk's prototypes with its last closure.
- In generational mode, objects created while a major collection was sweeping,
  or before switching to generational mode, became old immediately, so minor
  collections never freed them or ran their finalizers.
- Automatic collections kept dead values in stack slots above the running
  function alive.
- An incremental sweep could fall behind objects allocated during it and never
  finish.

### Performance

- More calls, returns, table operations, and generic loops stay in the VM's fast
  loop.
- Faster table indexing, precomputed hashes for constant keys, and integer array
  access fast paths.
- GC registries use an address index, and `table.sort` uses Lua 5.5's sorting
  algorithm.

### Testing

- `zig build test-official-complete` runs the official suite without `_soft` and
  `_port`, and `zig build test-gc-stress` runs the differential fixtures under
  both GC stress modes. CI runs both on Linux.
- Fuzz targets for source loading, binary chunk verification, and string library
  inputs run with `zig build test --fuzz`.
- Test harnesses run cases in parallel, and the benchmark suite includes
  whole-program workloads.

## 0.7.0

### Breaking changes

- `State.preloadModule(name, loader)` now takes a loader `Function` and installs
  it in `package.preload`, so `require` loads the module lazily. The old
  behavior, writing a table straight into `package.loaded`, is now
  `State.setLoadedModule(name, module)`.
- `stdlib.initHintsWithStdin` was removed; use `stdlib.initHints`.
- Number formatting now matches Lua 5.5: large and small floats print as `1e+15`
  and `9.2233720368547758e+18` instead of long decimal strings.
- Bitwise operators no longer convert strings (`"3" | 0` raises an error, as in
  Lua 5.5).
- `State.deinit` runs pending `__gc` finalizers and closes open files, like
  `lua_close`.

### Embedding API

- Interrupt a running state from another thread with `State.interruptHandle()`.
  Interrupts can't be caught by `pcall` and surface as `error.Interrupted`.
- Per-call instruction budgets and tracebacks through `Function.callWith` /
  `protectedCallWith` and `CallOptions`. `ErrorRef.traceback()` returns the
  captured traceback.
- `Table` gains `len`, `rawLen`, `rawSet`, `append`, `setMetatable`, `toSlice`,
  `rawIterator`, and `pairs`. `get`/`set` now call function
  `__index`/`__newindex` metamethods.
- New module helpers: `preloadModuleFn`, `setLoadedModule`, and a host-side
  `require`.
- New `limits.max_file_bytes` (default 256 MiB) shared by `io`, `fs`,
  `loadfile`, and `require`.
- `os.exit` returns `error.LuaExit` to embedders instead of exiting the host
  process.
- Output flush policies for stdout/stderr writers, and an incremental stdin
  reader option.
- Binary chunks are verified before they run.
- Warnings can be turned on with `IoCapability.warnings` or routed to
  `IoCapability.warning_handler`.

### Lua compatibility

- New: `os.exit`, `io.popen`, `debug.getmetatable`, `debug.debug`,
  `package.loadlib`.
- `os.clock` reports CPU time; `os.date` and `os.time` support local time zones.
- `loadfile` and `dofile` are base functions.
- `xpcall` handlers run at the error point, so `debug.traceback` sees the
  failing frames.
- `warn` works, and the CLI supports `-W`.
- `__gc` works on userdata.
- File handles are real `FILE*` userdata. `io.tmpfile` is in-memory and leaves
  nothing behind, and `os.tmpname` returns unique names.
- Failed `close` and `flush` return `nil, message, errno` instead of raising.
- The Lua stack limit matches PUC Lua (1,000,000 slots), and nested native calls
  stop at 200 with `C stack overflow`.
- String library functions accept numbers.
- Argument errors use Lua's wording, position prefixes, and function names.
- `io.open` and friends return Lua-style error messages and errno values.
- The file metatable matches PUC Lua's layout, and `io` no longer exposes
  internal fields.
- Fixed `string.gmatch` dropping captures after the second, `next` returning an
  extra value, and `table.create` edge cases.

### CLI

- Output streams as the script runs instead of appearing when a chunk finishes.
- `io.read` reads stdin incrementally.
- Uncaught errors print a Lua-style stack traceback.

### Performance

- Constant folding and single-instruction concat chains.
- Lua function calls are about 25% faster; metamethod lookups are cached and
  constants are decoded once per function.
- Sequential file writes are linear instead of quadratic.

### Fixes

- Generational GC could free values held by suspended coroutines.
- Explicit `collectgarbage()` could free live temporaries and crash.
- Fixed GC crashes in the official coroutine tests.
- Library functions called through `pcall` or `xpcall` could have their
  arguments overwritten when they invoked a metamethod.
- Calls with more than 65535 arguments crashed.
- `table.sort` and `table.unpack` could lose elements when a callback triggered
  a collection.
- Errors caught after a coroutine yielded across `pcall` could leave stale
  continuations that crashed later.
- `file:seek` with an offset that overflows returns `nil, message, errno`
  instead of crashing.
- `file:lines` with several formats stops at the first one that fails, like
  `file:read`.
- `io.open` in append mode no longer rewrites the existing file, and appends
  from separate handles are kept.
- `table.unpack` accepts any indexable value, and `table.insert`/`table.remove`
  follow Lua's bounds rules for extreme lengths.
