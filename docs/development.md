# Development

zlua supports Zig `0.16.0` and `0.17.0`. Its only package dependency is `zerde`. The build also downloads the Lua 5.5 source and official tests into `.zlua-deps/`, a directory Git ignores, so you don't need Lua installed on your system.

## Repository Map

The source tree follows the path a Lua program takes: the frontend parses it, the compiler turns it into bytecode, and the runtime executes it with the standard libraries.

| Path | Purpose |
| --- | --- |
| `src/root.zig` | Package facade and top-level exports. |
| `src/api.zig`, `src/api/` | Supported Zig embedding API: the facade and the modules behind it. |
| `src/frontend/` | Lexer, parser, AST, source spans, and diagnostics. |
| `src/compile/` | Resolver, bytecode, protos, compiler, and disassembler. |
| `src/runtime/` | VM, calls, coroutines, GC, host services, and chunks. |
| `src/stdlib/` | Lua libraries and zlua extensions. |
| `src/testing/` | Differential, extension, official, and benchmark harnesses. |
| `examples/` | Zig embedding examples and API smoke tests. |
| `tests/` | Lua, extension, and benchmark fixtures. |

Applications that embed zlua should go through `zlua.State` from `src/api.zig`. The runtime types are available to zlua itself and its tests, but they are not a stable contract for hosts.

## Everyday Commands

```sh
zig build                 # build zlua and the Lua 5.5 reference binary
zig build run -- file.lua # run a script
zig build test            # Zig tests and freestanding smoke test
zig build ci              # all correctness checks
zig build examples        # compile and run embedding examples
just diff path/to/test.lua
just official calls
just extensions tests/extensions/string
just bench --category table
```

For the full list of build steps, run `zig build --help`. Harness flags are documented in `docs/commands.md`.

## Source Conventions

A few conventions keep the codebase consistent:

- Follow the Zig 0.16 `std.Io` model. CLI and test code pass explicit I/O handles instead of relying on process-global helpers.
- Treat Lua 5.5 `global` declarations and `<const>`/`<close>` attributes as supported language features.
- Keep imports and commonly used type aliases at file scope.
- If a host needs something new, prefer a small addition to the embedding API over exposing runtime internals. Put it in the matching `src/api/` module and re-export public names from `src/api.zig`.
- Keep `runtime.State` methods to its widely used core. Runtime subsystems live in their own modules as functions that take `*State`, called directly (for example `call_mod.invokeValue(state, ...)`); don't add thin `State` methods that only forward to them. A subsystem that owns state can be a field instead, like `state.gc.collect()`, `state.budget.reset()`, or `state.strings.intern(...)`.
- Give a standard library private per-state tables by adding a `stdlib.LibraryTable` member, not a `State` field; the runtime roots and snapshots every slot.
- Keep the public methods of API types limited to what hosts should call. Helpers that other `src/api/` files need become `pub fn`s at file scope in the module that owns the concept (for example `errors.captureLuaError(state, err)`), not `pub` methods.
- Keep zlua binary chunks internal. They are not a stable ABI, and they are not the PUC Lua `luac` format.
- When a Lua-visible edge case is unclear, let the downloaded Lua 5.5 behavior and tests decide it.

For imports, prefer this:

```zig
const std = @import("std");
const Dir = std.Io.Dir;
```

over repeating inline imports or long qualified names throughout a file.

### Formatting

```sh
just fmt
```

The recipe formats `build.zig`, top-level `src/*.zig`, `src/testing/*.zig`, and `examples/*.zig`, and it requires Zig 0.16. For changed files in other nested source directories, run `zig fmt` on them directly.

## Workflow

When you change behavior, work from a test outward:

1. Add the smallest Lua fixture, extension fixture, Zig test, or embedding example that demonstrates the behavior.
2. Compare the Lua-visible behavior with the downloaded Lua 5.5.
3. Make the narrowest change that stays compatible.
4. Run the focused test first. If the change touches shared compiler, runtime, GC, stdlib, or API code, run `zig build ci` as well.

When an official test turns up a bug, add a smaller permanent regression fixture if you can. Any expected failure needs a reason, and it should be removed as soon as the behavior works. Benchmarks are a diagnostic tool, not a correctness gate.

## Dependency Cache

`tools/fetch-lua.sh` downloads the Lua archives into `.zlua-deps/` and verifies them. If you use a local mirror, you can override the URLs:

```sh
ZLUA_LUA_URL=https://example.invalid/lua-5.5.0.tar.gz \
ZLUA_LUA_TESTS_URL=https://example.invalid/lua-5.5.0-tests.tar.gz \
zig build fetch-lua
```

Build outputs live under `zig-out/` and `.zig-cache/`.
