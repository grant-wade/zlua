# Architecture

zlua is a Lua 5.5 implementation made up of a frontend, a bytecode compiler, a runtime, the standard libraries, and a Zig embedding API. The official Lua 5.5 implementation is the reference throughout: when there's a question about accepted syntax, runtime behavior, diagnostics, or library results, zlua aims to match what Lua 5.5 does.

## Main Boundaries

The source tree splits into a handful of areas, each with a clear job:

| Area | Source | Role |
| --- | --- | --- |
| Package facade | `src/root.zig` | Exports the supported Zig API and lower-level subsystems. |
| Zig embedding API | `src/api.zig`, `src/api/` | Typed states, handles, callbacks, userdata, capabilities, and limits. |
| CLI | `src/main.zig` | REPL, scripts, `-e`, dump modes, and test commands. |
| Frontend and compiler | `src/frontend/`, `src/compile/` | Lexes, parses, resolves, and compiles Lua source. |
| Runtime | `src/runtime.zig`, `src/runtime/` | Values, VM execution, calls, coroutines, GC, errors, and host services. |
| Standard libraries | `src/stdlib.zig`, `src/stdlib/` | Lua-visible native functions and library setup. |

If you're embedding zlua, `src/api.zig` (re-exported through `src/root.zig`) is the boundary you should build against. You can import the runtime directly, but doing so exposes object layouts, stack frames, GC bookkeeping, and bytecode details that may change between versions.

## Source to Execution

Every piece of Lua code takes the same path from source bytes to running instructions:

```text
source bytes
  -> lexer
  -> AST
  -> resolver
  -> compiler Proto
  -> runtime Closure
  -> Thread stack and CallFrames
  -> VM dispatch
  -> Lua or native calls
```

The CLI, the embedding API, and the test harnesses all share this pipeline and differ only in how they wrap it. The CLI deals with files, stdin, shebangs, `arg`, and host-oriented defaults. The Zig API turns load results into rooted `Function` handles and maps Lua failures to API errors or protected-call results. Differential tests can stop after lexing, parsing, resolving, or compiling, or carry on through execution.

### Frontend

`src/frontend/` holds the lexer, parser, AST, source spans, tokens, and diagnostics. Each `Ast` owns an arena, so all of its nodes and strings are released together.

The parser understands Lua 5.5 syntax, including `global` declarations, `<const>` and `<close>` locals, named varargs, labels, gotos, and both forms of `for`. It doesn't try to enforce rules that depend on scope; those are left to the resolver.

### Resolver

`src/compile/resolver.zig` handles the scope-dependent checks: declaration order, `_ENV` visibility, local attributes, writes to const and loop variables, named varargs, upvalue capture, and to-be-closed lifetimes. Running these checks before bytecode generation means load-time behavior can be compared directly against Lua 5.5.

### Compiler and Proto

The compiler lowers the resolved AST into a `compile.proto.Proto`, which is the plan for a chunk or a Lua function. A proto carries register-based instructions, constants, nested protos, upvalue descriptors, register requirements, the function's shape, line and local debug data, and operand origins used for runtime errors.

The instruction set is small enough to describe by purpose:

| Family | Examples |
| --- | --- |
| Values and moves | `load_nil`, `load_bool`, `load_const`, `move` |
| Globals, upvalues, and tables | `get_global`, `set_global`, `get_table`, `set_field`, `new_table` |
| Operators | arithmetic, bitwise, comparison, length, and concatenation instructions |
| Control flow | jumps, tests, numeric `for`, and generic `for` |
| Calls | `call`, `tail_call`, `ret`, and `vararg` |
| Closures and cleanup | `closure`, `close`, `check_close`, and `close_tbc` |

Numeric constants keep their source text until they're loaded, so the conversion follows Lua's rules. `Proto.error_sites` records where each operand came from, which lets an error name the local, global, field, method, or constant involved rather than reporting a generic VM failure.

## Runtime Model

### State Ownership

A `runtime.State` owns an entire Lua universe. Its contents fall into a few groups:

| Group | Contents |
| --- | --- |
| Environment | The global table and primitive metatables. |
| Interning | The intern set. |
| Heap objects | Tables, userdata, closures, upvalues, coroutines, loaded protos, and retained source buffers. |
| Execution | Current thread, callback dispatch, instruction count, output buffers, and error state. |
| Lifetime control | API roots, GC state, allocation totals, and host options. |

Globals live in exactly one place: the global environment table. `_G` points back to that table, even in states opened with no standard libraries, and there is no separate native globals map that would need to be kept in sync.

Every object a state allocates is tracked in a state-owned list. The GC uses those same lists for marking, sweeping, finalization, and memory accounting. When you call `State.deinit`, it first runs any pending finalizers, as `lua_close` does, and then walks the lists and releases everything.

### State Startup

Startup is planned around the standard libraries you choose, so the state can size its storage up front instead of growing it as libraries install themselves:

1. `stdlib.initHints` predicts global entries, dynamic strings, and tables. Stdin bytes stay with the I/O capability and are not interned.
2. The state reserves its string and table tracking capacity.
3. The global table is created with the expected hash capacity and installs `_G`.
4. Selected libraries: 
  a. create their tables with exact capacity hints
  b. copy compile-time entries
  c. build their hash indexes without duplicate-key searches.
5. The initial GC threshold is set after library setup.

Common library names and fixed values live in `src/stdlib/static_strings.zig`. These are process-lifetime `String` objects in read-only memory, shared by every state. Each state's intern set starts with them, and `state.strings.intern` returns the static string when one exists.

Library setup avoids repeating object layouts in the same spirit. For example, file handles are `FILE*` userdata that all share one lazily created metatable.

For measurement, `State.initWithOptionsObserved` exposes the startup phases (state containers, globals, libraries, and GC baseline) to the in-process startup benchmark. Normally you won't call it: high-level callers use `zlua.State.init`, and internal runtime callers use `initWithOptions`.

### Runtime Modules

`runtime.State` holds the VM's data and keeps a small set of methods that the standard libraries and the Zig API use everywhere: lifecycle, roots, object allocation, globals, and argument and library errors. Subsystems that own their own fields are facets on the state (`state.gc`, `state.budget`, `state.strings`), and everything else lives in modules that take `*State` explicitly. Libraries that need private per-state tables, such as the zerde null sentinel, get rooted, snapshot-safe slots in `state.library_tables`, keyed by `stdlib.LibraryTable`, rather than `State` fields:

| Module | Contents |
| --- | --- |
| `vm.zig` | Instruction dispatch, jumps and numeric `for`, constants, fast table paths, interrupts, and instruction budgets. |
| `call.zig` | Calls, returns, tail calls, varargs, protected calls, `pcall`/`xpcall`, and message handlers. |
| `entry.zig` | Host entry points: running chunks and calling functions from Zig on host threads. |
| `load.zig` | Loading source and binary chunks, string literal decoding, and root closures. |
| `index.zig` | Table reads and writes through `__index`/`__newindex`, raw access, `next`/`pairs`/`ipairs`, and generic `for`. |
| `metatable.zig` | Metatable lookup and assignment, metamethod resolution, and `__gc` registration. |
| `operators.zig` | Arithmetic, bitwise, comparison, length, and concatenation, with their metamethods. |
| `upvalue.zig` | Upvalues, to-be-closed variables, and frame unwinding. |
| `io.zig`, `system.zig` | Capability-gated files, output, and filesystem operations; environment, clocks, processes, and exit. |
| `failure.zig` | Runtime error messages with source locations. |
| `gc.zig` | The collector as `State.gc` (`state.gc.collect()`, barriers, allocation accounting), with its own fields. |
| `budget.zig` | Instruction counting, `max_instructions` and per-call budgets, and host interrupts as `State.budget`. |
| `strings.zig` | String creation, interning, and `Builder` as `State.strings` (`state.strings.intern(...)`). |
| `object_pool.zig` | Size-class slabs for tables, upvalues, closures, and strings of up to 128 bytes, in blocks from the state allocator. |
| `debug.zig`, `coroutine.zig` | Debug info, hooks, and tracebacks; coroutines. |

### Values and Heap Objects

`runtime.types.Value` is a 16-byte tagged union that holds Lua scalars, object pointers, native functions, and a few internal callable values. The heap objects it can point to are:

| Object | Key data |
| --- | --- |
| `String` | Length, cached hash, interning flags, and GC state, followed by the bytes in the same allocation. |
| `Closure` | Proto, lazily loaded constants, and debug-strip state, followed by its upvalue pointers in the same allocation. |
| `Upvalue` | An open stack slot or a closed stored value. |
| `Table` | Array part, hash entries and index, metatable, and GC flags. |
| `Userdata` | Native pointer, type information, metatable, `__gc` registration, host finalizer, and deinit hook. |
| `Thread` | Value stack, call frames, continuations, open upvalues, hooks, and coroutine status. |

Strings of up to 40 bytes are always interned. Longer strings are not, and compute their hash on first use as a table key. String constants are interned at any length.

Tables store positive integer keys in an array part and all other keys in hash entries backed by an index map. Don't rely on iteration order: it isn't a stable API, except where compatibility tests pin down Lua's behavior.

### Calls and Coroutines

Each thread owns a value stack and a stack of `CallFrame`s. Calls go through `runtime/call.zig`, and host code enters Lua through `runtime/entry.zig`:

```text
value + arguments
  -> invokeValue
  -> Lua frame, built-in native, host API callback, or __call
  -> runThreadUntil
  -> adjust results for the caller
```

A protected call saves enough state to restore the stacks, frames, results, prior error information, and the thread's message handler if something fails. The same path backs Lua's `pcall` and `xpcall` and Zig's `Function.protectedCall`.

That message handler plays the role of Lua's `errfunc`, and each thread has one. `xpcall` and host calls that supply a handler install it, and it runs at the point where the error is raised, before the failing frames unwind.

Yielding is built on continuations. A thread keeps continuation records for protected calls, generic loops, branches, tail calls, and single calls, so that when a native call or metamethod yields, execution can later resume at the right opcode.

### VM and Limits

The instruction dispatcher and the limit checks that cut across it live in `runtime/vm.zig`. The VM is responsible for Lua-specific result adjustment, varargs, tail calls, metamethods, to-be-closed unwinding, primitive metatables, debug hooks, and stack overflow guards.

Several limits keep running code in check:

- `max_instructions` is a cumulative budget for the whole state. You can query and reset it through the Zig API, and host calls can narrow it further with per-call deadlines.
- Instruction budgets and interrupt polls share a single checkpoint in the dispatch loop.
- Interrupts use an atomic flag that survives state moves and resets. `error.Interrupted` bypasses `pcall`, `xpcall`, and `__close` handlers.
- `max_memory` is enforced by the embedding API's bounded allocator, which sees object pool blocks rather than individual objects. If you use the runtime directly, you need to supply your own bounded allocator.

### Garbage Collection

The collector never moves objects, so their addresses stay stable. It supports two modes: generational mode, the default, concentrates on recently allocated objects, while incremental mode spreads a full collection across VM safepoints and calls to `State.stepGc`.

Each object type has a registry in the state, with old objects before young ones. Every object embeds the same collector header, holding its mark, age, and generation, and for objects other than strings its registry position.

Collection starts from globals, embedding handles, active calls, and suspended coroutines and follows references from there. Write barriers keep those references valid when Lua or host code changes an object between steps. Thread stacks are the exception, since they have no per-register barrier. Instead, running threads are revisited at each atomic step, and an old thread is remembered for minor collections when it runs, suspends, or has a register written from another thread. Collections mark each frame's registers up to its pending call, much like Lua's stack top, and clear the dead registers above it. Only collections that start inside a debug hook, which can interrupt an instruction, mark whole stacks. In generational mode, a major collection ages its survivors at the atomic step, as Lua's `atomic2gen` does, so objects allocated while it sweeps stay young. A loaded chunk's prototypes are freed once none of its closures are marked; minor collections only consider chunks loaded since the previous collection. Prototypes are shared with snapshots. Each state interns a chunk's string constants when it loads the chunk, and the chunk's closures share them.

Weak tables and finalizers get special handling, so unreachable objects can be cleared or finalized without losing objects that become reachable again. Tables and userdata registered for a Lua `__gc` share one finalizer queue, which runs newest first. A userdata's host finalizer waits until the userdata is unreachable after its `__gc` has run. Errors raised inside `__gc` become Lua warnings.

Snapshots interact with the collector too. Taking a snapshot saves the heap and GC settings without running a collection. Resetting restores the saved objects without repeating a full-heap scan, after which generational collections focus on new allocations. Each registry keeps the objects that existed at capture before those created since, and reset frees the objects past that prefix. In such a state, switching to generational mode leaves the objects that existed at capture to major collections. The storage kept for reset still counts toward the state's memory limit, even when it is no longer part of the live Lua heap.

See [Garbage Collection](embedding.md#garbage-collection) for the controls available to embedders.

## Standard Libraries and Host Access

`src/stdlib.zig` decides which libraries to open, creates their tables, and installs their native functions, while the implementations themselves are split by library under `src/stdlib/`. The CLI opens the full set and the Zig API defaults to the safe set, though both let you pick libraries one by one.

Native library functions reuse the runtime's existing thread and frame machinery for arguments, returns, errors, metamethods, and yields. There's no second internal stack API to learn.

Opening a library and granting it access to the host are separate decisions. A library only reaches the outside world through capabilities, which you configure independently:

| Capability | Available modes |
| --- | --- |
| I/O | Optional Zig `std.Io`, stdin bytes (or a runtime-level stdin reader, used by the CLI), and output writers with flush policies. |
| Filesystem | Disabled, read-only memory files, mutable memory filesystem, host cwd, rooted host directory, or callbacks. |
| Environment | Disabled, host-provided map, or callbacks. |
| Clock | Disabled, fixed (optionally with a local offset), system, or callbacks. |
| Process | Disabled, std-backed, or callbacks. |

The memory filesystem normalizes sandbox-relative paths and rejects absolute paths and parent traversal. Because `io`, `os`, `package`, and `fs` all go through this same capability layer, opening one of those libraries doesn't grant any ambient access on its own.

## Embedding Layers

### Zig API

`src/api.zig` is a facade that re-exports the public API from the modules in `src/api/`. The API wraps runtime values in typed, rooted handles such as `Table`, `Function`, `Ref`, `Userdata(T)`, `AnyUserdata`, `Value`, and `ErrorRef`. When a handle owns a root, you are responsible for deinitializing it.

| Module | Contents |
| --- | --- |
| `state.zig` | `State`, `InterruptHandle`, memory-file bookkeeping, and the GC boundary. |
| `snapshot.zig` | `Snapshot`, snapshot capture, `reset`, and rollback metadata. |
| `options.zig`, `capabilities.zig` | State, load, call, and GC options, and host capability types. |
| `handle.zig` | `Ref` and the validation and rooting shared by every handle. |
| `value.zig`, `table.zig`, `function.zig`, `coroutine.zig`, `userdata.zig` | `Value`, `Tuple`, and the handle types. |
| `errors.zig` | Error sets, `ErrorRef`, `CallResult`, and last-error capture. |
| `convert.zig` | Conversion between Zig values, API handles, and runtime values. |
| `callbacks.zig`, `context.zig` | Host callback registration and dispatch, typed adapters, and `Context`. |
| `memory_limit.zig` | The allocator wrapper that enforces `Limits.max_memory`. |

Beyond handles, the API maps its options onto runtime options, converts values in both directions, binds host callbacks and userdata, provides module and memory-filesystem helpers, and captures Lua errors. A registered host function is a native value carrying a state-local callback ID. While a callback is active, its context roots the arguments and pending returns, so they survive reentrant calls and collection. Installing a handle into Lua gives Lua its own reference; your host handle stays valid and still needs its own cleanup.

## Errors and Binary Chunks

Failures come in two kinds. Load-time failures use `errors.Diagnostic`. Runtime failures carry a `RuntimeErrorPayload`, an error value, and traceback and debug context. The Zig API surfaces both as `error.LuaError` or as protected-call results.

zlua's binary chunks serialize protos for zlua-to-zlua use, and `string.dump`, `Function.dumpBytecode`, and `State.loadBytecode` all use this format. It is version-sensitive, makes no promise of `luac` compatibility, and is not a stable external ABI.

Because the VM indexes registers, constants, upvalues, protos, and jump targets without bounds checks, every loaded chunk is checked first by `verifyProto` in `src/runtime/chunk.zig`. If you add an opcode, you must extend the verifier to cover it.

## Testing Architecture

The test harnesses are Zig build artifacts under `src/testing/`, and each layer checks zlua against a different reference:

| Layer | Reference |
| --- | --- |
| Unit tests | Zig assertions. |
| Differential fixtures | The same Lua program under zlua and downloaded Lua 5.5. |
| Extension fixtures | zlua-only libraries checked against committed output. |
| Official suite | Upstream Lua 5.5 tests under both runtimes. |
| Benchmarks | Process-level and in-process startup measurements. |

Staged differential tests can compare what the frontend, resolver, and compiler accept without depending on VM execution. Startup tests separately check allocation hints, static strings, global-table identity, and the shared file metatable and method table.

## Invariants

These rules hold across the codebase, and changes should preserve them:

- Official Lua behavior wins over intuition.
- `src/api.zig` is the stable Zig embedding boundary.
- The runtime global table is the only runtime store for globals.
- State-owned values that escape into host code must be rooted.
- Static strings have process lifetime, are never written, and never enter state-owned deallocation paths.
- Every string of up to 40 bytes is interned.
- A table entry with a nil value never outlives its key.
- Standard-library startup changes must update capacity hints, the static-string catalog, and startup tests together.
- Protected calls must restore stack, frame, result, and error state.
- Zig API/runtime value conversion must preserve table identity and cycles.
- Host effects remain explicit capabilities.
- Binary chunks and VM layouts remain internal.
- Loaded binary chunks are verified before they run.
- Performance work must still pass differential, extension, official, and embedding tests.
