# Changelog

## Unreleased

### Embedding API

- `Context.io` returns the state's configured `std.Io`.

### Fixes

- `require` ignored `package.searchers`, including custom searchers.
- `require` replaced a `package.loaded` entry set by a nil-returning loader with `true`.
- `require`, the default searchers, and `package.searchpath` report module-not-found and load errors with Lua 5.5's messages.
- `package.searchers` includes the C and all-in-one searchers, which report `package.cpath` matches as dynamic libraries not enabled.
- `require` and the embedding package helpers followed reassignments of the `package` global, `package.loaded`, and `package.preload`.
- `package.config`, `package.searchpath`, and the default searchers used `/` instead of `\` as the directory separator on Windows.
- Line-buffered writes to `/dev/full` on Linux, and `setvbuf` with pending output, returned different results than glibc.

## 0.7.2

### Performance

- Strings store their header and bytes in one allocation, and `Value` is 16 bytes instead of 24. Short strings are always interned and compare by pointer, and string hashes are cached.
- Concatenation, `string.rep`, `string.format`, `string.gsub`, `string.upper`, `string.lower`, `string.reverse`, `string.char`, `table.concat`, and `utf8.char` build results in place or in a reused buffer.
- The collector keeps mark state and registry positions in a 16-byte header shared by every object type, and closures store their upvalue pointers in the same allocation.
- Snapshot workers find the objects created since capture by registry position, without a per-object hash table.
- Faster `#`, numeric and generic `for` loops, and write barriers.
- Arithmetic and comparisons with a numeric constant operand use dedicated instructions.
- Varargs stay on the caller's stack, and vararg calls and `...` run in the VM's fast loop.
- `pcall` and `xpcall` call their function in place without copying arguments or results.
- Table constructors reserve their exact size, table storage grows to power-of-two capacities, and each table's hash entries and index share one allocation.
- Each loaded chunk interns its string constants once for all of its closures, and field and global lookups compare those strings by pointer.
- Upvalues are 56 bytes instead of 72.
- Call frames are 40 bytes instead of 136.
- Tables, upvalues, closures, and strings of up to 128 bytes come from per-state size-class slabs.
- Tables are 64 bytes instead of 104.
- Field reads and writes start at the entry position where the key string was last found.

### Fixes

- A collection during a protected call could free the error value that the call restores on failure.
- `string.format` signs NaN like the host C library on FreeBSD and Windows, and raises an error for `%a` and `%A` with modifiers on Windows.
- `/dev/full` streams on FreeBSD report write and flush failures like FreeBSD's C library.
- Installs and the package include `THIRD_PARTY_NOTICES` with Lua's copyright and license.

### Testing

- CI runs on FreeBSD, and official-suite child processes have a 512 MiB memory cap on Linux and FreeBSD.
- `zig build bench` prints the host system and labels builds with the running Zig version's optimize mode name.

## 0.7.1

### Lua compatibility

- Pattern matching follows Lua's matcher: `*` and `+` no longer stop after 4096 repetitions, long patterns no longer fail with `pattern too complex`, and quantifiers after `%b`, `%f`, and back-references are literal characters.
- `string.gsub` with a `^` anchor replaces at most once, and `string.gmatch` treats a leading `^` as a literal.
- A back-reference to a position capture fails to match instead of raising an error, and `%f[` without a closing `]` is a malformed pattern.
- Hexadecimal numerals with many digits or large exponents convert like Lua (`0xe03` followed by 1000 zeros and `p-4000` is `3587.0`, not `nan`).
- `coroutine.resume` returns `false, "too many results to resume"` when the results do not fit on the caller's stack, instead of raising a stack overflow.

### Fixes

- States without an instruction limit no longer hang on wasm32; fast-loop instruction accounting now wraps at 64 bits on 32-bit targets.
- Function prototypes created by `load`, `loadfile`, and coroutines were never freed, so a state that kept loading chunks grew without bound. The collector now frees a chunk's prototypes with its last closure.
- In generational mode, objects created while a major collection was sweeping, or before switching to generational mode, became old immediately, so minor collections never freed them or ran their finalizers.
- Automatic collections kept dead values in stack slots above the running function alive.
- An incremental sweep could fall behind objects allocated during it and never finish.

### Performance

- More calls, returns, table operations, and generic loops stay in the VM's fast loop.
- Faster table indexing, precomputed hashes for constant keys, and integer array access fast paths.
- GC registries use an address index, and `table.sort` uses Lua 5.5's sorting algorithm.

### Testing

- `zig build test-official-complete` runs the official suite without `_soft` and `_port`, and `zig build test-gc-stress` runs the differential fixtures under both GC stress modes. CI runs both on Linux.
- Fuzz targets for source loading, binary chunk verification, and string library inputs run with `zig build test --fuzz`.
- Test harnesses run cases in parallel, and the benchmark suite includes whole-program workloads.

## 0.7.0

### Breaking changes

- `State.preloadModule(name, loader)` now takes a loader `Function` and installs it in `package.preload`, so `require` loads the module lazily. The old behavior, writing a table straight into `package.loaded`, is now `State.setLoadedModule(name, module)`.
- `stdlib.initHintsWithStdin` was removed; use `stdlib.initHints`.
- Number formatting now matches Lua 5.5: large and small floats print as `1e+15` and `9.2233720368547758e+18` instead of long decimal strings.
- Bitwise operators no longer convert strings (`"3" | 0` raises an error, as in Lua 5.5).
- `State.deinit` runs pending `__gc` finalizers and closes open files, like `lua_close`.

### Embedding API

- Interrupt a running state from another thread with `State.interruptHandle()`. Interrupts can't be caught by `pcall` and surface as `error.Interrupted`.
- Per-call instruction budgets and tracebacks through `Function.callWith` / `protectedCallWith` and `CallOptions`. `ErrorRef.traceback()` returns the captured traceback.
- `Table` gains `len`, `rawLen`, `rawSet`, `append`, `setMetatable`, `toSlice`, `rawIterator`, and `pairs`. `get`/`set` now call function `__index`/`__newindex` metamethods.
- New module helpers: `preloadModuleFn`, `setLoadedModule`, and a host-side `require`.
- New `limits.max_file_bytes` (default 256 MiB) shared by `io`, `fs`, `loadfile`, and `require`.
- `os.exit` returns `error.LuaExit` to embedders instead of exiting the host process.
- Output flush policies for stdout/stderr writers, and an incremental stdin reader option.
- Binary chunks are verified before they run.
- Warnings can be turned on with `IoCapability.warnings` or routed to `IoCapability.warning_handler`.

### Lua compatibility

- New: `os.exit`, `io.popen`, `debug.getmetatable`, `debug.debug`, `package.loadlib`.
- `os.clock` reports CPU time; `os.date` and `os.time` support local time zones.
- `loadfile` and `dofile` are base functions.
- `xpcall` handlers run at the error point, so `debug.traceback` sees the failing frames.
- `warn` works, and the CLI supports `-W`.
- `__gc` works on userdata.
- File handles are real `FILE*` userdata. `io.tmpfile` is in-memory and leaves nothing behind, and `os.tmpname` returns unique names.
- Failed `close` and `flush` return `nil, message, errno` instead of raising.
- The Lua stack limit matches PUC Lua (1,000,000 slots), and nested native calls stop at 200 with `C stack overflow`.
- String library functions accept numbers.
- Argument errors use Lua's wording, position prefixes, and function names.
- `io.open` and friends return Lua-style error messages and errno values.
- The file metatable matches PUC Lua's layout, and `io` no longer exposes internal fields.
- Fixed `string.gmatch` dropping captures after the second, `next` returning an extra value, and `table.create` edge cases.

### CLI

- Output streams as the script runs instead of appearing when a chunk finishes.
- `io.read` reads stdin incrementally.
- Uncaught errors print a Lua-style stack traceback.

### Performance

- Constant folding and single-instruction concat chains.
- Lua function calls are about 25% faster; metamethod lookups are cached and constants are decoded once per function.
- Sequential file writes are linear instead of quadratic.

### Fixes

- Generational GC could free values held by suspended coroutines.
- Explicit `collectgarbage()` could free live temporaries and crash.
- Fixed GC crashes in the official coroutine tests.
- Library functions called through `pcall` or `xpcall` could have their arguments overwritten when they invoked a metamethod.
- Calls with more than 65535 arguments crashed.
- `table.sort` and `table.unpack` could lose elements when a callback triggered a collection.
- Errors caught after a coroutine yielded across `pcall` could leave stale continuations that crashed later.
- `file:seek` with an offset that overflows returns `nil, message, errno` instead of crashing.
- `file:lines` with several formats stops at the first one that fails, like `file:read`.
- `io.open` in append mode no longer rewrites the existing file, and appends from separate handles are kept.
- `table.unpack` accepts any indexable value, and `table.insert`/`table.remove` follow Lua's bounds rules for extreme lengths.
