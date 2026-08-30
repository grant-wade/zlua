# Benchmarking

zlua has two benchmark paths:

- Process benchmarks compare complete Lua programs under downloaded Lua 5.5 and a ReleaseFast zlua CLI.
- Startup benchmarks measure state creation and a first trivial chunk inside already-running processes.

## Process Benchmarks

```sh
just bench
just bench --list
just bench --category table
just bench table/pairs_iteration --iterations=20
just bench vm/locals --iterations=20 --no-warmup
```

Write machine-readable reports with:

```sh
just bench --iterations=20 --json /tmp/zlua-bench.json
just bench --iterations=20 --csv /tmp/zlua-bench.csv
```

The recipe runs:

```sh
zig build -Doptimize=ReleaseFast --summary all run-test-bench -- <args>
```

Each sample includes process launch, runtime initialization, source loading, compilation, execution, and shutdown. This catches broad regressions but does not isolate VM dispatch, table lookup, GC, or individual library calls.

Human output reports min, median, mean, max, standard deviation, and the zlua/Lua 5.5 ratio. JSON and CSV include raw nanosecond samples.

### Fixtures

Fixtures live under `tests/bench/**/*.lua`. Top-of-file metadata controls a run:

```lua
-- name: table/array_reads
-- category: table
-- iterations: 10
-- warmup: 1
-- timeout-ms: 60000
```

| Key | Default | Notes |
| --- | --- | --- |
| `name` | Fixture path | Display name and selector. |
| `category` | `misc` | Free-form filter. |
| `iterations` | `5` | Measured process runs. |
| `warmup` | `1` | Unmeasured runs. |
| `timeout-ms` | `60000` | Per-process timeout. |
| `expect` | `pass` | Also accepts `fail` or `skip`; those require `reason`. |

Selectors can match a name, path, directory, basename, or basename without `.lua`.

## Performance Workflow

1. Capture a JSON or CSV baseline.
2. Reproduce the relevant category with enough iterations to see variance.
3. Profile before changing broad runtime structures.
4. Preserve or add a fixture for the target path.
5. Run correctness checks before judging the result.
6. Capture an after report and compare raw samples as well as summaries.

Typical checks for runtime work:

```sh
zig build test
zig build test-diff
zig build test-extensions
zig build test-official
just bench --category <category> --iterations=20 --json /tmp/after.json
```


## Startup Benchmarks

Process launch hides state initialization costs, so startup has a separate in-process benchmark:

```sh
just bench-startup --iterations=1000 --warmup=100
# equivalent:
zig build bench-startup -- --iterations=1000 --warmup=100
```

The step builds measured components in ReleaseFast and runs:

1. Native zlua with `none`, `base`, `safe`, and `full` library selections.
2. The zlua C API through `lua_newstate`, `luaL_openlibs`, and a trivial chunk.
3. Lua 5.5 through the same C source and counting allocator.

Native initialization is split into state containers, global-table setup, library opening, and GC baseline setup. The report also includes load, call, teardown, complete startup, and time through the first successful chunk. C API reports split `newstate`, `openlibs`, load, call, and close.

| Column | Meaning |
| --- | --- |
| `median-ns`, `p95-ns` | In-process phase timing; executable launch is excluded. |
| `alloc`, `resize` | Successful allocator operations. |
| `requested-B` | New bytes requested, including positive resize growth. |
| `live-B` | Requested bytes still live after the phase. |
| `peak-B` | Peak live requested bytes during the phase. |
| `runtime-B` | Native runtime/GC object estimate. |

The zlua and Lua 5.5 C runs share `tools/bench_c_api_startup.c` and the same allocator instrumentation.

