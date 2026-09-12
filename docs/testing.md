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
| Full check | `zig build ci` | Unit tests, freestanding smoke builds, examples, differential fixtures, extension fixtures, and official suite. |

`just test`, `just diff`, `just extensions`, `just official`, and `just ci` are convenience wrappers.

## GitHub Actions

Every push runs `zig build test test-wasm` on Linux x64. Pull requests targeting
`main` run `zig build ci test-wasm` on Linux, macOS, and Windows, each on x64 and
ARM64 native runners. The full matrix can also be started manually.

The `PR checks` job succeeds only when the entire full-suite matrix passes; failed,
cancelled, or skipped matrix jobs prevent it from passing. Select `PR checks` as
the required status check in the branch protection rule or ruleset for `main`.

CI uses the Zig version declared in `build.zig.zon`. The setup action caches Zig
downloads and build outputs, with separate build caches for each OS, architecture,
and dependency manifest. Full-suite jobs also cache Lua source and test downloads.
New commits cancel older runs for the same event and branch or pull request.

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
just diff --gc-step-stress
just diff --show-clua --show-zlua tests/diff/runtime/errors.lua
```

Use `--gc-stress` to look for values that are collected too early, or `--gc-step-stress` to test changes made between collection steps. Add `--feature=gc` to run just the GC fixtures. Both modes respect Lua's stop/restart controls.

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

Every failure, signal, or timeout from either interpreter makes the harness exit nonzero. Failure categories are diagnostic labels only; the official harness has no automatic expected failures. Failed child output is always printed, and the summary reports `clua_failed` and `zlua_failed` separately.

```sh
zig build test-official
just official calls db locals
just official --mode=complete strings.lua
zig build test-official -Dofficial-memory-limit-mb=0
```

The build step applies a 256 MiB child-process cap on Linux by default and no cap elsewhere. It also limits each child to 120 seconds (`-Dofficial-timeout-ms=0` disables this). The allocator-exhaustion test `heavy.lua` is skipped on macOS and Windows because the harness cannot cap child memory there. The `files.lua` prelude emulates `/dev/full` on those platforms and maps `/dev/null` to `NUL` on Windows. Direct harness runs default to no timeout or memory cap. `--mode=internal` is parsed but skipped because `testC` builds are not wired.

Differential and extension output comparisons treat CRLF and LF as equivalent; lone carriage returns, spaces, and missing final newlines remain significant. Fixtures normalize platform-dependent paths explicitly where they print or assert them.

CI covers Linux and macOS on x64 and ARM64, plus Windows x64. Windows ARM64 is currently excluded because of Zig compiler and C runtime failures.

## Debugging a Failure

1. Run the narrowest fixture with both outputs visible.
2. Compare output, exit code, signal, and timeout.
3. Reduce broad official failures to a small permanent fixture.
4. Fix and rerun the focused target.
5. Run `zig build ci` before finishing a shared runtime or API change.

```sh
just diff --show-clua --show-zlua path/to/case.lua
just official --show-clua --show-zlua calls
```

Benchmarks are deliberately separate from correctness checks and are not part of `zig build ci`.
