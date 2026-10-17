# Testing

zlua checks its Lua-visible behavior against the official Lua 5.5 C implementation, which the build compiles for you. When a compatibility question comes up, run the code under both and keep the smallest fixture that shows the difference.

## Test Layers

The checks come in layers, from fast unit tests up to the full upstream suite. `zig build ci` runs all of them except the WASM smoke test.

| Layer | Command | Covers |
| --- | --- | --- |
| Zig tests | `zig build test` | Library, CLI, runtime, API, test utilities, and x86_64/wasm32 freestanding smoke builds. |
| WASM smoke | `zig build test-wasm` | Runs the freestanding custom-host profile in wasm32 using Node.js. |
| Embedding examples | `zig build examples` | Compiles and runs all registered embedding examples. |
| Differential fixtures | `zig build test-diff` | Runs `tests/diff/**/*.lua` under Lua 5.5 and zlua. |
| Extension fixtures | `zig build test-extensions` | Checks zlua-only libraries and functions against checked-in output. |
| Official suite | `zig build test-official` | Runs downloaded Lua 5.5 tests under both interpreters. |
| Complete official suite | `zig build test-official-complete` | Runs the same tests with their full-size and non-portable sections enabled. |
| GC stress | `zig build test-gc-stress` | Runs the differential fixtures under both GC stress modes. |
| Full check | `zig build ci` | Unit tests, freestanding smoke builds, examples, differential fixtures, extension fixtures, and official suite. |

`just test`, `just diff`, `just extensions`, `just official`, and `just ci` are shorter wrappers around the same steps. The complete official suite and GC stress runs take longer, so `zig build ci` leaves them to the extended CI job.

The unit tests include fuzz targets for source loading, binary chunk verification, and string library inputs (patterns, `string.format`, and `string.pack`). A normal test run only checks their seed inputs. To search for crashes, run the fuzzer with an optional iteration limit:

```sh
zig build test --fuzz=100K
```

## GitHub Actions

Every push runs `zig build ci test-wasm check-tools` with Zig `0.16.0` and `0.17.0`
on Linux and macOS (x64 and ARM64), plus Windows and FreeBSD x64. You can also start
the full matrix manually. Each job then builds, runs, and tests the downstream embedding
project in `examples/project` against the current checkout.

An extended job on Linux runs `zig build test-official-complete test-gc-stress` with
both Zig versions.

The `PR checks` job passes only when every full-suite and extended job passes. A
failed, cancelled, or skipped job makes it fail. That makes `PR checks` the
one to select as the required status check in the branch protection rule or ruleset
for `main`.

The minimum Zig version in `build.zig.zon` stays at `0.16.0`, and CI tests both
supported versions explicitly. To keep runs fast, the setup action caches Zig
downloads and build outputs, with a separate build cache for each compiler version,
OS, architecture, and dependency manifest. Full-suite jobs also cache the Lua source
and test downloads. A new commit cancels older runs for the same event and branch.

## Lua 5.5 Reference

`zig build fetch-lua` downloads the source and tests into `.zlua-deps/`, and a normal build produces `zig-out/bin/lua5.5`. The harnesses look for CLua in this order:

```text
--clua
ZLUA_CLUA
zig-out/bin/lua5.5
lua5.5
lua5.5.0
lua
```

Whichever binary is found has to identify itself as Lua 5.5. If an explicit `--clua` or `ZLUA_CLUA` path doesn't, the harness reports an error; a fallback that doesn't is skipped.

## Differential Fixtures

Differential fixtures are plain Lua files under `tests/diff/`. The harness runs each one under both interpreters and compares the results. A fixture can start with metadata comments that tell the harness how to treat it:

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
| `gc-stress` | `run`, `skip` | `run` |
| `skip-os` | Space- or comma-separated OS names (`linux`, `macos`, `windows`, ...) | empty |
| `reason`, `issue` | Free-form text | empty |

The first four stages compare only whether the code loads, and stop zlua at the named compiler stage. The runtime-style stages also compare stdout and stderr. Normalization is opt-in, and it should only remove unstable paths, never hide a real semantic difference.

Use `skip-os` (with a `reason`) only when the host C Lua's behavior depends on something zlua cannot see, such as the limits of the host filesystem.

A few useful focused runs:

```sh
just diff tests/diff/runtime/tables.lua
just diff --stage=parse
just diff --feature=table
just diff --gc-stress
just diff --gc-step-stress
just diff --show-clua --show-zlua tests/diff/runtime/errors.lua
```

The two GC stress modes are for collector bugs. Both collect at every safepoint reached after an allocation. Use `--gc-stress` to look for values that are collected too early, and `--gc-step-stress` to test changes made between collection steps. Add `--feature=gc` to run only the GC fixtures. Both modes respect Lua's stop/restart controls. Fixtures that allocate heavily on purpose can set `gc-stress: skip` (with a `reason`) to sit out `--gc-stress`.

### Expected Failures

You can declare an expected failure in fixture metadata or in `tests/fixtures/expected_failures.toml`. Each one needs a reason. If an expected failure starts passing, the harness reports it as a failure, so stale entries get noticed and removed. The inventory is currently empty.

## Extension Fixtures

Some zlua features have no counterpart in standard Lua, so there is nothing to compare them against. These include the data formats, `fs`, and the string and table helpers. Their fixtures live under `tests/extensions/` and are checked against stored output instead. A fixture's expected stdout is in `<fixture>.lua.out`, and optional `.err` and `.exit` files set the expected stderr and exit status.

```sh
just extensions
just extensions tests/extensions/string
just extensions --show-output tests/extensions/fs/basic.lua
```

The harness uses the safe libraries by default, and the full libraries for fixtures under `tests/extensions/fs`.

When you have changed output on purpose, `--bless` rewrites the expected `.out`, `.err`, and `.exit` files from the actual run:

```sh
just extensions --bless tests/extensions/string/split_edges.lua
```

## Official Suite

The upstream Lua 5.5 tests are downloaded to `.zlua-deps/lua-5.5.0-tests`. By default the harness runs every top-level `.lua` file except `all.lua`, using the basic compatibility prelude.

Any failure, signal, or timeout from either interpreter makes the harness exit nonzero. The failure categories it prints are labels to help you diagnose a problem; the official harness has no automatic expected failures. Output from a failed child is always printed, and the summary reports `clua_failed` and `zlua_failed` separately.

```sh
zig build test-official
just official calls db locals
just official --mode=complete strings.lua
zig build test-official -Dofficial-memory-limit-mb=0
zig build test-official-complete
```

Basic mode sets `_soft` and `_port`, which shrink the stress sections and skip non-portable checks. Complete mode leaves them unset, and it skips the four files that only work under `all.lua`'s driver: `attrib.lua` and `main.lua` need the C test libraries and module paths it sets up, `big.lua` must run inside its coroutine, and `files.lua` expects a non-seekable stdin.

Limits differ depending on how you run the suite. The build step caps each child process at 512 MiB on Linux and FreeBSD by default, with no cap elsewhere, and limits each child to 120 seconds (`-Dofficial-timeout-ms=0` disables the timeout). The complete-mode step caps children at 2048 MiB instead (`-Dofficial-complete-memory-limit-mb`), because its full-size sections need more memory under zlua than under C Lua. Running the harness directly applies no timeout or memory cap by default.

Some tests need help on particular platforms. The allocator-exhaustion test `heavy.lua` is skipped on macOS and Windows, because the harness cannot cap child memory there. On those platforms the `files.lua` prelude emulates `/dev/full`, and on Windows it maps `/dev/null` to `NUL`. `--mode=internal` is rejected because it requires `testC` builds of both interpreters, which are not supported.

When the differential and extension harnesses compare output, they treat CRLF and LF as equivalent. Lone carriage returns, spaces, and missing final newlines still count. Fixtures that print or assert platform-dependent paths normalize them explicitly.

CI covers Linux and macOS on x64 and ARM64, plus Windows x64. Windows ARM64 is excluded for now because of Zig compiler and C runtime failures.

## Debugging a Failure

When something fails, narrow it down before you fix it:

1. Run the narrowest fixture you can, with both outputs visible.
2. Compare the output, exit code, signal, and timeout.
3. If an official test fails broadly, reduce it to a small permanent fixture.
4. Fix the problem and rerun the focused target.
5. Run `zig build ci` before you finish a change to shared runtime or API code.

```sh
just diff --show-clua --show-zlua path/to/case.lua
just official --show-clua --show-zlua calls
```

Benchmarks are kept separate from the correctness checks on purpose, and they are not part of `zig build ci`.
