# Commands

There are two ways to drive the project. `zig build` is the underlying build graph and exposes every step and option. `just` wraps the most common steps in shorter recipes for local work. When you pass arguments after `zig build <step> --`, they are forwarded to that step's executable.

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
just bench --category table
just bench
```

## just Recipes

Most recipes are thin wrappers around the build step of the same or a similar name:

| Recipe | Action |
| --- | --- |
| `just build`, `just release` | Run the default build, or a ReleaseSafe build. |
| `just docs`, `just docs-serve`, `just docs-serve-pub` | Build the Zig HTML docs and optionally serve them locally. The public form binds `0.0.0.0`. |
| `just fetch-lua` | Download the Lua 5.5 source and tests. |
| `just test`, `just ci` | Run the Zig tests or the complete check. |
| `just examples` | Compile and run all embedding examples. |
| `just run [args...]` | Run the zlua CLI. |
| `just version`, `just clua-version` | Print version information for zlua or the downloaded Lua. |
| `just diff [args...]` | Run the differential tests with `--debug-errors`. |
| `just extensions [args...]` | Run the zlua extension fixtures. |
| `just official [args...]` | Run the official tests with debug errors and a 256 MiB child cap on Linux. |
| `just bench [args...]` | Run the full benchmark suite, or only the cases you select. |
| `just fmt` | Format the top-level source, testing, build, and example files. |
| `just clean` | Remove `zig-out/` and `.zig-cache/`. |

Format with Zig `0.16.0`, because the Zig `0.17.0` formatter can introduce syntax that `0.16.0` cannot parse. If `zig` on your `PATH` is a newer version, point the recipe at a 0.16 compiler, for example `just --set zig /path/to/zig-0.16.0/zig fmt`.

## Build Options

| Option | Meaning |
| --- | --- |
| `-Dtarget=<target>` | Select the Zig target. |
| `--release=safe`, `--release=fast`, `--release=small` | Select a release mode; this spelling works on both supported Zig versions. Without it you get a debug build. |
| `-Doptimize=<mode>` | Zig 0.16: `Debug`, `ReleaseSafe`, `ReleaseFast`, `ReleaseSmall`. Zig 0.17: `debug`, `safe`, `fast`, `small`. |
| `-Dofficial-memory-limit-mb=<n>` | Memory cap for each official-test child process on Linux. Defaults to `256` on Linux and `0` elsewhere; `0` disables it. |
| `-Dofficial-complete-memory-limit-mb=<n>` | The same cap for `test-official-complete`. Defaults to `2048` on Linux and `0` elsewhere. |
| `-Dofficial-timeout-ms=<n>` | Timeout for each official-test child process. Defaults to `120000`; `0` disables it. |

## Build Steps

| Step | Purpose |
| --- | --- |
| `zig build` | Install `zlua`, `lua5.5`, and the differential, extension, official, and benchmark harnesses. |
| `fetch-lua` | Download and verify the Lua 5.5 source and official tests. |
| `run -- [args...]` | Run the zlua CLI. |
| `docs` | Generate the Zig HTML docs under `zig-out/docs`. |
| `docs-md` | Regenerate the Markdown API docs under `docs/api/`. |
| `check-tools` | Compile the documentation tools and run the documentation-generator tests. |
| `docs-serve -- [host] [port]` | Serve `zig-out/docs`; defaults to `127.0.0.1:8000`. |
| `test` | Run the Zig unit tests and the freestanding smoke tests. |
| `test-freestanding` | Build the x86_64 freestanding custom-host smoke test, and run it on x86_64 Linux hosts. |
| `test-wasm` | Run the freestanding smoke test in wasm32 using Node.js. |
| `examples` | Compile and run every embedding example. |
| `test-diff` | Run all CLua differential fixtures. |
| `run-test-diff -- [args...]` | Run the differential harness with your own filters and options. |
| `test-extensions` | Run all zlua extension fixtures. |
| `run-test-extensions -- [args...]` | Run the extension harness with your own filters and options. |
| `test-official` | Run the full official-suite dashboard in basic mode. |
| `test-official-complete` | Run the official suite in complete mode, with full-size and non-portable sections enabled. |
| `test-gc-stress` | Run the differential fixtures under `--gc-stress` and `--gc-step-stress`. |
| `run-test-official -- [args...]` | Run selected official tests or modes. |
| `bench -- [args...]` | Run all benchmark groups one after another and print one combined report. |
| `ci` | Run the tests, examples, and the differential, extension, and official checks. |

## zlua CLI

```sh
zlua [options] [script [args...]]
```

The CLI starts with the full standard library and access to the host filesystem, environment, processes, clocks, and I/O. Zig embedding works the other way around: a state starts sandboxed, and the host opts in to what it needs.

| Option | Meaning |
| --- | --- |
| `-h`, `--help` | Print usage. |
| `-v`, `--version` | Print the zlua and target Lua versions. If there is no other input and stdin is a TTY, exit afterward. |
| `--stdlib MODE` or `--stdlib=MODE` | Select `none`, `base`, `safe`, `full`, or a comma- or plus-separated list of libraries. |
| `-e CHUNK` or `-eCHUNK` | Execute a chunk given on the command line. You can repeat it. |
| `-i` | Enter the REPL after running any command-line chunks and the script. |
| `-W` | Turn warnings on. Like `lua`, the CLI starts with warnings off and applies `-W` and `-e` in the order given. |
| `--debug-errors` | Include internal runtime diagnostics. |
| `--trace-vm` | Trace VM instructions. |
| `--dump-ast` | Parse and print an AST-oriented dump. |
| `--dump-scope` | Parse, resolve, and print scope information. |
| `--dump-bytecode` | Compile and disassemble zlua bytecode. |
| `--` | Stop option parsing. |
| `-` | Read the script from stdin. |

The library names you can list explicitly are `base`, `table`, `string`, `math`, `utf8`, `coroutine`, `io`, `os`, `debug`, `package`, `json`, `toml`, `msgpack`, `csv`, and `fs`.

If you give zlua no input, it starts a REPL when stdin is a TTY and otherwise executes whatever is piped in. Script and stdin reads are capped at 1 MiB, and a leading shebang line is stripped. The REPL accepts multiline input and the `=expr` shorthand.

Lua output streams as it is produced and is buffered the same way C `lua` buffers it:

- On a terminal, stdout is line buffered. Otherwise it is block buffered, and `print` flushes it, as `lua_writeline` does.
- stderr is unbuffered.
- stdout is also flushed by `io.flush`, before a child process starts, and at exit.
- Open file handles that were never closed are flushed at exit, just as C `exit` flushes every stream.

Chunks run under `lua`'s message handler, so an uncaught error prints a traceback. `io.read`, `io.lines`, and `loadfile()` read stdin incrementally, which means scripts can prompt for input.

## Harnesses

### Differential

```sh
zig build run-test-diff -- [options] [path]
just diff [options] [path]
```

| Option | Meaning |
| --- | --- |
| `path` | File or directory to run; defaults to `tests/diff`. |
| `--clua PATH`, `--clua=PATH` | Reference interpreter. |
| `--stage=STAGE` | `lex`, `parse`, `resolve`, `compile`, `runtime`, `stdlib`, or `official`. |
| `--feature=TAG` | Filter on fixture metadata. |
| `--timeout-ms=N` | Per-process timeout; default `5000`. |
| `--show-clua`, `--show-zlua` | Print each engine's output. |
| `--gc-stress` | Collect aggressively while zlua runs. |
| `--gc-step-stress` | Run incremental collection steps while zlua runs. |
| `--debug-errors` | Enable zlua internal diagnostics. |

The harness looks for the reference interpreter in this order: the explicit option, `ZLUA_CLUA`, `zig-out/bin/lua5.5`, and then a Lua 5.5 binary on `PATH`.

### zlua Extensions

```sh
zig build run-test-extensions -- [options] [path]
just extensions [options] [path]
```

| Option | Meaning |
| --- | --- |
| `path` | File or directory to run; defaults to `tests/extensions`. |
| `--zlua PATH`, `--zlua=PATH` | zlua executable. |
| `--stdlib MODE`, `--stdlib=MODE` | Library selection; defaults to `safe`. `fs` fixtures use `full`. |
| `--timeout-ms=N` | Per-process timeout; default `5000`. |
| `--show-output` | Print fixture stdout and stderr. |
| `--bless` | Rewrite the `.out`, `.err`, and `.exit` expectations from the actual run and list the files that changed. |

### Official Suite

```sh
zig build run-test-official -- [options] [files...]
just official [options] [files...]
```

| Option | Meaning |
| --- | --- |
| `files...` | Test basenames or files. With no arguments, every top-level `.lua` file except `all.lua` runs. |
| `--clua PATH`, `--clua=PATH` | Reference interpreter. |
| `--zlua PATH`, `--zlua=PATH` | zlua executable. |
| `--suite-path PATH`, `--suite-path=PATH` | Use a different extracted test directory. |
| `--mode=basic|complete` | Prelude mode. `internal` is rejected because `testC` builds are not supported. |
| `--timeout-ms=N` | Per-process timeout; `0` means none. |
| `--memory-limit-mb=N` | Child memory cap on Linux; `0` means none. |
| `--show-clua`, `--show-zlua` | Print each engine's output. |
| `--debug-errors` | Enable zlua internal diagnostics. |

### Benchmarks

```sh
zig build bench -- [options] [selectors...]
just bench [options] [selectors...]
```

| Option | Meaning |
| --- | --- |
| `selectors...` | Group, case, or process fixture name or path. |
| `--list` | List the selected benchmark cases. |
| `--family=NAME` | Run one group: `process`, `startup`, `snapshots`, `gc`, or `all` (the default). |
| `--clua PATH`, `--zlua PATH`, `--zlua-snapshot PATH` | Override the process benchmark executables; the `=PATH` forms also work. |
| `--iterations N` | Override the number of measured runs; must be positive. |
| `--warmup N`, `--no-warmup` | Override the number of warmup runs. |
| `--timeout-ms N` | Per-process timeout; must be positive. |
| `--category NAME` | Filter on metadata category. |
| `--json PATH`, `--csv PATH` | Write reports to these files. |
| `--debug-errors` | Enable zlua internal diagnostics. |
| `--verbose` | Show timing spread, phases, and allocation details. |

The options above that take a value also accept the `--name=value` form.

With no selectors, every group runs. You can narrow a run when you only care about part of the suite:

```sh
zig build bench -- startup --iterations=1000 --warmup=100
zig build bench -- callbacks --verbose
zig build bench -- --json /tmp/bench.json
```

## Dependency Environment

These variables let you point the build and harnesses at a different reference interpreter or a local mirror of the Lua archives:

| Variable | Meaning |
| --- | --- |
| `ZLUA_CLUA` | Preferred reference interpreter when `--clua` is not given. |
| `ZLUA_LUA_URL` | Override the Lua source archive URL. |
| `ZLUA_LUA_TESTS_URL` | Override the official-tests archive URL. |

Downloaded Lua files are kept under `.zlua-deps/`, and build outputs go to `zig-out/` and `.zig-cache/`.
