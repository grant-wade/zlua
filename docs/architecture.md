# Architecture

zlua is a Lua 5.5 implementation with a frontend, bytecode compiler, runtime, standard libraries, and two embedding layers. Compatibility is measured against the official Lua 5.5 implementation; it is the reference for accepted syntax, runtime behavior, diagnostics, libraries, and the C API.

## Main Boundaries

| Area | Source | Role |
| --- | --- | --- |
| Package facade | `src/root.zig` | Exports the supported Zig API and lower-level subsystems. |
| Zig embedding API | `src/api.zig` | Typed states, handles, callbacks, userdata, capabilities, and limits. |
| CLI | `src/main.zig` | REPL, scripts, `-e`, dump modes, and test commands. |
| Frontend and compiler | `src/frontend/`, `src/compile/` | Lexes, parses, resolves, and compiles Lua source. |
| Runtime | `src/runtime.zig`, `src/runtime/` | Values, VM execution, calls, coroutines, GC, errors, and host services. |
| Standard libraries | `src/stdlib.zig`, `src/stdlib/` | Lua-visible native functions and library setup. |
| C API | `src/c_api.zig` | Lua 5.5 C API compatibility backed by the zlua runtime. |

`src/api.zig`, re-exported through `src/root.zig`, is the intended Zig embedding boundary. Direct runtime imports expose object layouts, stack frames, GC bookkeeping, and bytecode details that may change.

## Source to Execution

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

The CLI, embedding API, and test harnesses use this pipeline through different wrappers:

- The CLI handles files, stdin, shebangs, `arg`, and host-oriented defaults.
- The Zig API turns load results into rooted `Function` handles and maps Lua failures to API errors or protected-call results.
- Differential tests can stop after lexing, parsing, resolving, or compiling, or continue through execution.

### Frontend

`src/frontend/` contains the lexer, parser, AST, source spans, tokens, and diagnostics. An `Ast` owns an arena, so its nodes and strings are released together.

The parser handles Lua 5.5 syntax such as `global` declarations, `<const>` and `<close>` locals, named varargs, labels, gotos, and both forms of `for`. Rules that need scope information are left to the resolver.

### Resolver

`src/compile/resolver.zig` checks declaration order, `_ENV` visibility, local attributes, writes to const and loop variables, named varargs, upvalue capture, and to-be-closed lifetimes. These checks happen before bytecode generation so load-time behavior can be compared directly with Lua 5.5.

### Compiler and Proto

The compiler lowers the resolved AST into `compile.proto.Proto`, the plan for a chunk or Lua function. A proto contains register-based instructions, constants, nested protos, upvalue descriptors, register requirements, function shape, line/local debug data, and operand origins for runtime errors.

The instruction set is small enough to group by purpose:

| Family | Examples |
| --- | --- |
| Values and moves | `load_nil`, `load_bool`, `load_const`, `move` |
| Globals, upvalues, and tables | `get_global`, `set_global`, `get_table`, `set_field`, `new_table` |
| Operators | arithmetic, bitwise, comparison, length, and concatenation instructions |
| Control flow | jumps, tests, numeric `for`, and generic `for` |
| Calls | `call`, `tail_call`, `ret`, and `vararg` |
| Closures and cleanup | `closure`, `close`, `check_close`, and `close_tbc` |

Constants keep numeric source text until loaded so conversion follows Lua rules. `Proto.error_sites` records where operands came from, allowing errors to name a local, global, field, method, or constant instead of reporting only a generic VM failure.

## Runtime Model

### State Ownership

`runtime.State` owns a Lua universe. Its main state falls into a few groups:

| Group | Contents |
| --- | --- |
| Environment | The global table and primitive metatables. |
| Interning | Dynamic interned strings and their allocation index. |
| Heap objects | Tables, userdata, closures, upvalues, coroutines, loaded protos, and retained source buffers. |
| Execution | Current thread, callback dispatch, instruction count, output buffers, and error state. |
| Lifetime control | API roots, GC state, allocation totals, and host options. |

The global environment table is the single source of truth for globals. `_G` points back to that table, including for states opened with no standard libraries. There is no separate native globals map to keep in sync.

Objects allocated by a state are tracked in state-owned lists. `State.deinit` walks those lists and releases them. The GC uses the same lists for marking, sweeping, finalization, and memory accounting.

### State Startup

State initialization is planned around the chosen standard libraries:

1. `stdlib.initHintsWithStdin` predicts global entries, dynamic strings, and tables.
2. The state reserves its string and table tracking capacity.
3. The global table is created with the expected hash capacity and installs `_G`.
4. Selected libraries: 
  a. create their tables with exact capacity hints
  b. copy compile-time entries
  c. build their hash indexes without duplicate-key searches.
5. The initial GC threshold is set after library setup.

Common library names and fixed values live in `src/stdlib/static_strings.zig`. They are process-lifetime strings stored in the executable, so each state can reuse them without allocating or GC-tracking copies. `State.intern` returns the canonical static slice when one exists and uses the per-state interning table for all other strings.

Library setup also avoids repeated object layouts. Standard file handles share one lazily created method metatable instead of copying methods into every file table.

`State.initWithOptionsObserved` exposes the startup phases—state containers, globals, libraries, and GC baseline—to the in-process startup benchmark. High-level callers use `zlua.State.init`; internal runtime callers use `initWithOptions`.

### Values and Heap Objects

`runtime.types.Value` is a tagged union containing Lua scalars, object pointers, native functions, and a few internal callable values.

| Object | Key data |
| --- | --- |
| `Closure` | Proto, Lua upvalues, lazily loaded constants, and debug-strip state. |
| `CClosure` | C function identity and C upvalues. |
| `Upvalue` | An open stack slot or a closed stored value. |
| `Table` | Array part, hash entries and index, metatable, and GC flags. |
| `Userdata` | Native pointer, type information, metatable, finalizer, and deinit hook. |
| `Thread` | Value stack, call frames, continuations, open upvalues, hooks, and coroutine status. |

Tables keep positive integer keys in an array part and other keys in hash entries backed by an index map. Iteration order is not a stable API except where compatibility tests pin Lua behavior.

### Calls and Coroutines

Each thread owns a value stack and `CallFrame` stack. Calls enter through helpers in `runtime/state.zig` and `runtime/call.zig`:

```text
value + arguments
  -> invokeValue
  -> Lua frame, C closure, native function, or __call
  -> runThreadUntil
  -> adjust results for the caller
```

Protected calls save enough state to restore stacks, frames, results, and prior error information. This path supports Lua `pcall`/`xpcall`, Zig `Function.protectedCall`, and C `lua_pcallk`.

Yielding is continuation-based. Threads retain continuation records for protected calls, generic loops, branches, tail calls, and single calls so execution can resume in the correct opcode after a native call or metamethod yields.

### VM and Limits

The instruction dispatcher lives in `runtime/state.zig`; `runtime/vm.zig` performs cross-cutting limit checks. The VM handles Lua-specific result adjustment, varargs, tail calls, metamethods, to-be-closed unwinding, primitive metatables, debug hooks, and stack overflow guards.

- `max_instructions` is a cumulative state budget that can be queried and reset through the Zig API.
- `max_memory` combines allocator limits in the embedding API with runtime allocation accounting and conservative GC checks at instruction boundaries.

### Garbage Collection

The collector marks from the global table, API roots, active threads and stacks, closures, upvalues, metatables, current errors, and callback state. It also handles weak tables and userdata/table finalizers.

Collection must remain safe across protected calls, yields, close handlers, finalizers, and host callbacks. Conservative collection is used where an in-progress operation temporarily holds values outside normal roots.

`collectgarbage("step")` and `State.stepGc` currently do full-collection-style work rather than a truly incremental step. Runtime mode and tuning controls exist for Lua compatibility, but a full generational collector is still future work.

## Standard Libraries and Host Access

`src/stdlib.zig` chooses libraries, creates their tables, and installs native functions. Implementations are split by library under `src/stdlib/`. The CLI opens the full set; the Zig API defaults to the safe set. Both layers also support an explicit per-library selection.

Native library functions use the runtime's existing thread and frame machinery for arguments, returns, errors, metamethods, and yields. There is no second internal stack API.

Opening a library and granting host access are separate decisions:

| Capability | Available modes |
| --- | --- |
| I/O | Optional Zig `std.Io`, stdin bytes, and output writers. |
| Filesystem | Disabled, read-only memory files, mutable memory filesystem, host cwd, rooted host directory, or callbacks. |
| Environment | Disabled, host-provided map, or callbacks. |
| Clock | Disabled, fixed, system, or callbacks. |
| Process | Disabled, std-backed, or callbacks. |

The memory filesystem normalizes sandbox-relative paths and rejects absolute paths and parent traversal. `io`, `os`, `package`, and `fs` all consume the same capability layer, so opening one of those libraries does not grant ambient access by itself.

## Embedding Layers

### Zig API

`src/api.zig` wraps runtime values in typed, rooted handles such as `Table`, `Function`, `Ref`, `Userdata(T)`, `AnyUserdata`, `Value`, and `ErrorRef`. Handles that own a root must be deinitialized by the host.

The API maps options into runtime options, converts values in both directions, binds host callbacks and userdata, exposes module and memory-filesystem helpers, and captures Lua errors. Registered host functions are native values containing state-local callback IDs. Active callback contexts root their arguments and pending returns across reentrant calls and collection. Installing a handle into Lua gives Lua its own reference; it does not consume the host handle.

### C API

`src/c_api.zig` is a compatibility layer, not a direct cast of `runtime.State`. Its `lua_State` owns a C-facing stack, registry, strings, tables, userdata, threads, and continuations alongside a runtime state.

Values that cross the boundary keep stable peers where identity matters:

- C strings are indexed by content and may cache their runtime string.
- C tables and runtime tables are linked in both directions.
- Linked runtime tables stay rooted while used by the C layer.
- Recursive synchronization uses in-progress guards and per-traversal visitation generations. 
- The C global table is linked to the runtime's canonical global table.

This bridge lets loaded Lua closures call through C-created tables without replacing table identity on every conversion. The C layer also implements stack indices, pseudo-indices, `luaL_*` helpers, coroutine continuations, status codes, and C-compatible exports matching the installed Lua headers.

## Errors and Binary Chunks

Load-time failures use `errors.Diagnostic`. Runtime failures use `RuntimeErrorPayload`, an error value, and traceback/debug context. The Zig API exposes these as `error.LuaError` or protected-call results; the C API maps them to Lua status codes.

zlua binary chunks serialize protos for zlua-to-zlua use. `string.dump`, `Function.dumpBytecode`, and `State.loadBytecode` use this format. It is version-sensitive, does not promise `luac` compatibility, and is not a stable external ABI.

## Testing Architecture

The test harnesses are Zig build artifacts under `src/testing/`:

| Layer | Reference |
| --- | --- |
| Unit tests | Zig assertions. |
| Differential fixtures | The same Lua program under zlua and downloaded Lua 5.5. |
| Extension fixtures | zlua-only libraries checked against committed output. |
| Official suite | Upstream Lua 5.5 tests under both runtimes. |
| C API fixtures | The same C fixture linked against zlua and Lua 5.5. |
| Benchmarks | Process-level and in-process startup measurements. |

Staged differential tests can compare frontend, resolver, and compiler acceptance without depending on VM execution. Startup tests separately check allocation hints, static strings, global-table identity, and shared file metatables.

## Invariants

Changes should preserve these rules:

- Official Lua behavior wins over intuition.
- `src/api.zig` is the stable Zig embedding boundary.
- The runtime global table is the only runtime store for globals.
- State-owned values that escape into host code must be rooted.
- Static strings must have process lifetime and never enter state-owned deallocation paths.
- Standard-library startup changes must update capacity hints, the static-string catalog, and startup tests together.
- Protected calls must restore stack, frame, result, and error state.
- C/runtime value conversion must preserve table identity and cycles.
- Host effects remain explicit capabilities.
- Binary chunks and VM layouts remain internal.
- Performance work must still pass differential, extension, official, embedding, and C API tests.
