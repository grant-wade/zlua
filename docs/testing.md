# Testing

Lua-visible behavior is checked against the official Lua 5.5 C implementation built by this repository. When a compatibility question comes up, compare both runtimes and keep the smallest useful fixture.

## Test Layers

| Layer | Command | Covers |
| --- | --- | --- |
| Zig tests | `zig build test` | Library, CLI, runtime, API, test utilities, and x86_64/wasm32 freestanding smoke builds. |
| WASM smoke | `zig build test-wasm` | Runs the freestanding custom-host profile in wasm32 using Node.js. |
| Embedding examples | `zig build examples` | Compiles and runs all registered embedding examples. |
| Differential fixtures | `zig build test-diff` | Runs `tests/diff/**/*.lua` under Lua 5.5 and zlua. |
| Extension fixtures | `zig build test-extensions` | Checks zlua-only libraries and functions against checked-in output. |
| Official suite | `zig build test-official` | Runs downloaded Lua 5.5 tests under both interpreters. |
| C API fixtures | `zig build test-c-api` | Compiles and runs each C fixture against both libraries. |
| Full check | `zig build ci` | All layers above. |

`just test`, `just diff`, `just extensions`, `just official`, `just c-api`, and `just ci` are convenience wrappers.

## Lua 5.5 Reference

`zig build fetch-lua` downloads source and tests into `.zlua-deps/`; normal builds produce `zig-out/bin/lua5.5`. Harnesses find CLua in this order:

```text
--clua
ZLUA_CLUA
zig-out/bin/lua5.5
lua5.5
lua5.5.0
lua
```

A fallback binary is accepted only if it identifies as Lua 5.5.

## Differential Fixtures

A fixture under `tests/diff/` may start with metadata comments:

```lua
-- expect: pass
-- stage: runtime
-- feature: table
-- normalize: none

print(({ 10, 20, 30 })[2])
```

| Key | Values | Default |
| --- | --- | --- |
| `expect` | `pass`, `fail`, `skip` | `pass` |
| `stage` | `lex`, `parse`, `resolve`, `compile`, `runtime`, `stdlib`, `official` | `runtime` |
| `feature` | Free-form tag | `uncategorized` |
| `normalize` | `none`, `paths` | `none` |
| `reason`, `issue` | Free-form text | empty |

The first four stages compare load-time acceptance while stopping zlua at the named compiler stage. Runtime-style stages also compare stdout and stderr. Normalization is opt-in and should only remove unstable paths, never semantic differences.

Useful focused runs:

```sh
just diff tests/diff/runtime/tables.lua
just diff --stage=parse
just diff --feature=table
just diff --gc-stress
just diff --show-clua --show-zlua tests/diff/runtime/errors.lua
```

`--bless` and `--update-expected-failures` are accepted but are currently no-ops.

### Expected Failures

Expected failures can be declared in fixture metadata or `tests/fixtures/expected_failures.toml`. They require a reason, and an expected failure that starts passing is reported as a failure so stale entries are removed. The inventory is currently empty.

## Extension Fixtures

Fixtures under `tests/extensions/` cover zlua additions that cannot be compared with standard Lua, including data formats, `fs`, and string/table helpers. A fixture's expected stdout is stored in `<fixture>.lua.out`; optional `.err` and `.exit` files set stderr and exit status.

```sh
just extensions
just extensions tests/extensions/string
just extensions --show-output tests/extensions/fs/basic.lua
```

The harness uses safe libraries by default and full libraries for fixtures under `tests/extensions/fs`.

## Official Suite

Downloaded tests live under `.zlua-deps/lua-5.5.0-tests`. The default run uses every top-level `.lua` file except `all.lua` with the basic compatibility prelude.

```sh
zig build test-official
just official calls db locals
just official --mode=complete strings.lua
zig build test-official -Dofficial-memory-limit-mb=0
```

The build step applies a 256 MiB child-process cap on Linux by default and no cap elsewhere. Direct harness runs default to no timeout or memory cap. `--mode=internal` is parsed but skipped because `testC` builds are not wired.

## C API Fixtures

`tests/c-api/**/*.c` is compiled twice: once against downloaded Lua 5.5 and once against `zlua-c`. Compatible builds, exit status, stdout, and stderr are required.

```sh
zig build ci-c-api
just c-api tests/c-api/stack/stack_manipulation.c
just c-api tests/c-api/coroutines
```

`tests/fixtures/c_api_status.toml` tracks public symbols. `tested-clua-diff` means at least one differential C fixture covers the symbol.

## Debugging a Failure

1. Run the narrowest fixture with both outputs visible.
2. Compare output, exit code, signal, and timeout.
3. Reduce broad official failures to a small permanent fixture.
4. Fix and rerun the focused target.
5. Run `zig build ci` before finishing a shared runtime or API change.

```sh
just diff --show-clua --show-zlua path/to/case.lua
just official --show-clua --show-zlua calls
just c-api --show-build tests/c-api/values/roundtrip.c
```

Benchmarks are deliberately separate from correctness checks and are not part of `zig build ci`.
