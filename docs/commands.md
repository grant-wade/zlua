# Commands

Use `just` for short local commands and `zig build` for the underlying build graph. Arguments after `zig build <step> --` are forwarded to the step's executable.

## Common Commands

```sh
zig build                         # build zlua and downloaded Lua 5.5
zig build run -- script.lua       # run a script
zig build test                    # Zig tests
zig build ci                      # all correctness checks
zig build examples                # compile and run embedding examples
just diff path/to/fixture.lua
just extensions tests/extensions/string
just official calls
just c-api tests/c-api/stack
just bench --category table
just bench
```

## just Recipes

Most recipes wrap a similarly named build step:

| Recipe | Action |
| --- | --- |
| `just build`, `just release` | Default build, or a ReleaseSafe build. |
| `just docs`, `just docs-serve`, `just docs-serve-pub` | Build Zig HTML docs and optionally serve them locally. The public form binds `0.0.0.0`. |
| `just fetch-lua` | Download Lua 5.5 source and tests. |
| `just test`, `just ci` | Run Zig tests or the complete check. |
| `just example [filters...]` | Run all or selected embedding examples. |
| `just run [args...]` | Run the zlua CLI. |
| `just version`, `just clua-version` | Print zlua or downloaded Lua version information. |
| `just diff [args...]` | Run differential tests with `--debug-errors`. |
| `just extensions [args...]` | Run zlua extension fixtures. |
| `just official [args...]` | Run official tests with debug errors and a 256 MiB Linux child cap. |
| `just c-api [args...]` | Run C API fixtures. |
| `just bench [args...]` | Run the full benchmark suite, or selected cases. |
| `just fmt` | Format top-level source, testing, build, and example files. |
| `just clean` | Remove `zig-out/` and `.zig-cache/`. |

Example filters accept a key, executable name, path, basename, or basename without `.zig`.

## Build Options

| Option | Meaning |
| --- | --- |
| `-Dtarget=<target>` | Zig target selection. |
| `-Doptimize=<mode>` | `Debug`, `ReleaseSafe`, `ReleaseFast`, or `ReleaseSmall`. |
| `-Dofficial-memory-limit-mb=<n>` | Child cap for official tests on Linux. Defaults to `256` on Linux and `0` elsewhere; `0` disables it. |

## Build Steps

| Step | Purpose |
| --- | --- |
| `zig build` | Install `zlua`, `lua5.5`, and the differential, extension, official, and benchmark harnesses. |
| `fetch-lua` | Download and verify Lua 5.5 source and official tests. |
| `run -- [args...]` | Run the zlua CLI. |
| `docs` | Generate Zig HTML docs under `zig-out/docs`. |
| `docs-md` | Regenerate Markdown API docs under `docs/api/`. |
| `docs-serve -- [host] [port]` | Serve `zig-out/docs`; defaults to `127.0.0.1:8000`. |
| `test` | Run Zig unit tests and the freestanding smoke test. |
| `test-freestanding` | Build the x86_64 freestanding custom-host smoke test; run it on x86_64 Linux hosts. |
| `examples` | Compile every embedding example. |
| `run-example -- [filters...]` | Run all or selected examples. |
| `test-diff` | Run all CLua differential fixtures. |
| `run-test-diff -- [args...]` | Run the differential harness with filters/options. |
| `test-extensions` | Run all zlua extension fixtures. |
| `run-test-extensions -- [args...]` | Run the extension harness with filters/options. |
| `test-official` | Run the complete official-suite dashboard. |
| `run-test-official -- [args...]` | Run selected official tests or modes. |
| `bench -- [args...]` | Run all benchmark groups sequentially with one combined report. |
| `c-api` | Install `libzlua-c.a`, Lua headers, and the C fixture harness. |
| `test-c-api -- [args...]` | Compile and compare C fixtures. |
| `ci-c-api` | Build and test the C API layer. |
| `ci` | Run tests, examples, differential, extension, official, and C API checks. |

## zlua CLI

```sh
zlua [options] [script [args...]]
```

The CLI starts with full libraries and host filesystem, environment, process, clock, and I/O access. Zig embedding defaults are sandboxed instead.

| Option | Meaning |
| --- | --- |
| `-h`, `--help` | Print usage. |
| `-v`, `--version` | Print zlua and target Lua versions. With no other input on a TTY, exit afterward. |
| `--stdlib MODE` or `--stdlib=MODE` | Select `none`, `base`, `safe`, `full`, or a comma/plus-separated library list. |
| `-e CHUNK` or `-eCHUNK` | Execute a command-line chunk; may be repeated. |
| `-i` | Enter the REPL after command-line chunks and a script. |
| `--debug-errors` | Include internal runtime diagnostics. |
| `--trace-vm` | Trace VM instructions. |
| `--dump-ast` | Parse and print an AST-oriented dump. |
| `--dump-scope` | Parse, resolve, and print scope information. |
| `--dump-bytecode` | Compile and disassemble zlua bytecode. |
| `--` | Stop option parsing. |
| `-` | Read the script from stdin. |

Explicit library names are `base`, `table`, `string`, `math`, `utf8`, `coroutine`, `io`, `os`, `debug`, `package`, `json`, `toml`, `msgpack`, `csv`, and `fs`.

With no input, zlua starts a REPL on a TTY or executes piped stdin. Script and stdin reads are capped at 1 MiB, and an initial shebang is stripped. The REPL supports multiline input and `=expr` shorthand.

## Harnesses

### Differential

```sh
zig build run-test-diff -- [options] [path]
just diff [options] [path]
```

| Option | Meaning |
| --- | --- |
| `path` | File or directory; defaults to `tests/diff`. |
| `--clua PATH`, `--clua=PATH` | Reference interpreter. |
| `--stage=STAGE` | `lex`, `parse`, `resolve`, `compile`, `runtime`, `stdlib`, or `official`. |
| `--feature=TAG` | Filter fixture metadata. |
| `--timeout-ms=N` | Per-process timeout; default `5000`. |
| `--show-clua`, `--show-zlua` | Print engine output. |
| `--gc-stress` | Collect aggressively during zlua execution. |
| `--debug-errors` | Enable zlua internal diagnostics. |
| `--bless`, `--update-expected-failures` | Accepted no-ops; fixture updates remain manual. |

CLua discovery is: explicit option, `ZLUA_CLUA`, `zig-out/bin/lua5.5`, then a Lua 5.5 binary on `PATH`.

### zlua Extensions

```sh
zig build run-test-extensions -- [options] [path]
just extensions [options] [path]
```

| Option | Meaning |
| --- | --- |
| `path` | File or directory; defaults to `tests/extensions`. |
| `--zlua PATH`, `--zlua=PATH` | zlua executable. |
| `--stdlib MODE`, `--stdlib=MODE` | Library selection; defaults to `safe`. `fs` fixtures use `full`. |
| `--timeout-ms=N` | Per-process timeout; default `5000`. |
| `--show-output` | Print fixture stdout and stderr. |

### Official Suite

```sh
zig build run-test-official -- [options] [files...]
just official [options] [files...]
```

| Option | Meaning |
| --- | --- |
| `files...` | Test basenames/files. No arguments runs every top-level `.lua` except `all.lua`. |
| `--clua PATH`, `--clua=PATH` | Reference interpreter. |
| `--zlua PATH`, `--zlua=PATH` | zlua executable. |
| `--suite-path PATH`, `--suite-path=PATH` | Alternate extracted test directory. |
| `--mode=basic|complete|internal` | Prelude mode. `internal` is currently skipped. |
| `--timeout-ms=N` | Per-process timeout; `0` means none. |
| `--memory-limit-mb=N` | Linux child cap; `0` means none. |
| `--show-clua`, `--show-zlua` | Print engine output. |
| `--debug-errors` | Enable zlua internal diagnostics. |

### Benchmarks

```sh
zig build bench -- [options] [selectors...]
just bench [options] [selectors...]
```

| Option | Meaning |
| --- | --- |
| `selectors...` | Group, case, or process fixture name/path. |
| `--list` | List selected benchmark cases. |
| `--clua PATH`, `--zlua PATH` | Override executables; `=PATH` forms also work. |
| `--iterations N` | Override measured runs; must be positive. |
| `--warmup N`, `--no-warmup` | Override warmup runs. |
| `--timeout-ms N` | Positive per-process timeout. |
| `--category NAME` | Filter metadata category. |
| `--json PATH`, `--csv PATH` | Write reports. |
| `--debug-errors` | Enable zlua internal diagnostics. |
| `--verbose` | Show timing spread, phases, and allocation details. |

The value-taking options above also accept `--name=value` forms.

With no selectors, every group runs. You can still narrow a run when needed:

```sh
zig build bench -- startup --iterations=1000 --warmup=100
zig build bench -- callbacks --verbose
zig build bench -- --json /tmp/bench.json
```

### C API

```sh
zig build test-c-api -- [options] [path]
just c-api [options] [path]
```

| Option | Meaning |
| --- | --- |
| `path` | C fixture or directory; defaults to `tests/c-api`. |
| `--zig PATH` | Zig executable used to compile fixtures. |
| `--clua-include PATH`, `--clua-lib PATH` | Lua 5.5 headers and static library. |
| `--zlua-include PATH`, `--zlua-lib PATH` | zlua headers and static library. |
| `--status PATH` | Symbol inventory; defaults to `tests/fixtures/c_api_status.toml`. |
| `--timeout-ms=N` | Run timeout; default `5000`. |
| `--compile-timeout-ms=N` | Compile timeout; default `60000`. |
| `--show-build` | Print compile and link details. |

Without both library paths, the standalone harness validates the inventory and skips execution. The build step supplies all paths automatically.

## Dependency Environment

| Variable | Meaning |
| --- | --- |
| `ZLUA_CLUA` | Preferred reference interpreter when `--clua` is absent. |
| `ZLUA_LUA_URL` | Override the Lua source archive URL. |
| `ZLUA_LUA_TESTS_URL` | Override the official-tests archive URL. |

Downloaded Lua files live under `.zlua-deps/`; build outputs live under `zig-out/` and `.zig-cache/`.
