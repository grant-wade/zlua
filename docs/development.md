# Development

zlua supports Zig `0.16.0` and `0.17.1` and has no package dependencies. The
build downloads the Lua 5.5 source and official tests into `.zlua-deps/`, a
directory Git ignores, so you don't need Lua installed on your system.

[Architecture](architecture.md#main-boundaries) maps the source tree,
[Commands](commands.md) lists build steps and harness options, and
[Contributing](../CONTRIBUTING.md) describes the change workflow.

## Source Conventions

A few conventions keep the codebase consistent:

- Follow the Zig 0.16 `std.Io` model. CLI and test code pass explicit I/O
  handles instead of relying on process-global helpers.
- Treat Lua 5.5 `global` declarations and `<const>`/`<close>` attributes as
  supported language features.
- Keep imports and commonly used type aliases at file scope.
- If a host needs something new, prefer a small addition to the embedding API
  over exposing runtime internals. Put it in the matching `src/api/` module and
  re-export public names from `src/api.zig`.
- Keep `runtime.State` methods to its widely used core. Runtime subsystems live
  in their own modules as functions that take `*State`, called directly (for
  example `call_mod.invokeValue(state, ...)`); don't add thin `State` methods
  that only forward to them. A subsystem that owns state can be a field instead,
  like `state.gc.collect()`, `state.budget.reset()`, or
  `state.strings.intern(...)`.
- Give a standard library private per-state tables by adding a
  `stdlib.LibraryTable` member, not a `State` field; the runtime roots and
  snapshots every slot.
- Keep the public methods of API types limited to what hosts should call.
  Helpers that other `src/api/` files need become `pub fn`s at file scope in the
  module that owns the concept (for example
  `errors.captureLuaError(state, err)`), not `pub` methods.
- Keep zlua binary chunks internal. They are not a stable ABI, and they are not
  the PUC Lua `luac` format.
- When a Lua-visible edge case is unclear, let the downloaded Lua 5.5 behavior
  and tests decide it.

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

The recipe formats `build.zig`, top-level `src/*.zig`, `src/testing/*.zig`, and
`examples/*.zig`. For changed files in other nested source directories, run
`zig fmt` on them directly.

Format with Zig `0.16.0`. The `0.17.1` formatter can produce syntax that
`0.16.0` cannot parse, and the recipe rejects other versions. If `zig` on your
`PATH` is a different version, point the recipe at a 0.16 compiler:

```sh
just --set zig /path/to/zig-0.16.0/zig fmt
```

## Dependency Cache

`tools/fetch-lua.sh` downloads the Lua archives into `.zlua-deps/` and verifies
them. If you use a local mirror, you can override the URLs:

```sh
ZLUA_LUA_URL=https://example.invalid/lua-5.5.1.tar.gz \
ZLUA_LUA_TESTS_URL=https://example.invalid/lua-5.5.1-tests.tar.gz \
zig build fetch-lua
```

Build outputs live under `zig-out/` and `.zig-cache/`.
