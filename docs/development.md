# Development

zlua targets Zig `0.16.0`. The package depends on `zerde`; the build also downloads Lua 5.5 source and official tests into the ignored `.zlua-deps/` directory. A system Lua installation is not required.

## Repository Map

| Path | Purpose |
| --- | --- |
| `src/root.zig` | Package facade and top-level exports. |
| `src/api.zig` | Supported Zig embedding API. |
| `src/frontend/` | Lexer, parser, AST, source spans, and diagnostics. |
| `src/compile/` | Resolver, bytecode, protos, compiler, and disassembler. |
| `src/runtime/` | VM, calls, coroutines, GC, host services, and chunks. |
| `src/stdlib/` | Lua libraries and zlua extensions. |
| `src/c_api.zig` | Lua 5.5 C API layer. |
| `src/testing/` | Differential, extension, official, C API, and benchmark harnesses. |
| `examples/` | Zig embedding examples and API smoke tests. |
| `tests/` | Lua, C API, extension, and benchmark fixtures. |

Embedding applications should use `zlua.State` from `src/api.zig`. Runtime types are available to zlua itself and its tests but are not a stable host contract.

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
just c-api tests/c-api/stack
just bench --category table
```

Use `zig build --help` for build steps and `docs/commands.md` for harness flags.

## Source Conventions

- Follow the Zig 0.16 `std.Io` model. CLI and test code pass explicit I/O handles rather than relying on process-global helpers.
- Treat Lua 5.5 `global` declarations and `<const>`/`<close>` attributes as supported language features.
- Keep imports and commonly used type aliases at file scope.
- Prefer a small addition to `src/api.zig` over exposing runtime internals.
- Keep zlua binary chunks internal; they are not a stable ABI or PUC Lua `luac` format.
- Let downloaded Lua 5.5 behavior and tests decide Lua-visible edge cases.

Prefer:

```zig
const std = @import("std");
const Dir = std.Io.Dir;
```

rather than repeating inline imports or long qualified names throughout a file.

### Formatting

```sh
just fmt
```

The recipe formats `build.zig`, top-level `src/*.zig`, `src/testing/*.zig`, and `examples/*.zig`. Run `zig fmt` directly for changed files in nested source directories.

## Workflow

For a behavior change:

1. Add the smallest Lua fixture, C fixture, Zig test, or embedding example that demonstrates it.
2. Compare Lua-visible behavior with downloaded Lua 5.5.
3. Make the narrowest compatible change.
4. Run the focused test first, then `zig build ci` when the change crosses shared compiler, runtime, GC, stdlib, or API code.

When an official test finds a bug, add a smaller permanent regression fixture when practical. Expected failures need a reason and should be removed as soon as the behavior works. Benchmarks are diagnostics, not correctness gates.

## Dependency Cache

`tools/fetch-lua.sh` downloads and verifies Lua archives under `.zlua-deps/`. Local mirrors can override the URLs:

```sh
ZLUA_LUA_URL=https://example.invalid/lua-5.5.0.tar.gz \
ZLUA_LUA_TESTS_URL=https://example.invalid/lua-5.5.0-tests.tar.gz \
zig build fetch-lua
```

Build outputs live under `zig-out/` and `.zig-cache/`.
