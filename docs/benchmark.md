# Benchmarking

Run the whole suite with `zig build bench` (or `just bench`). It runs these groups sequentially and produces one report:

| Group | Measures |
| --- | --- |
| Process | Complete Lua programs under zlua and Lua 5.5, including process launch, compilation, and shutdown. |
| Startup | State creation, library opening, and the first chunk through the native Zig API and upstream Lua’s C API. |
| Snapshots | Capture, new State creation (`new_state`), first-work mutation, reset-only, no-op reset, full work/reset cycles, and equivalent rebuild. |

All benchmarks use ReleaseFast for both zlua and C Lua, including process comparisons and C startup workers, regardless of `-Doptimize`. Startup and snapshot timings exclude process launch. Startup totals sum the measured phases; they are not another independently timed operation.

## Running a benchmark

```sh
zig build bench -- --list
zig build bench -- table/pairs_iteration --iterations=20
zig build bench -- sustained --iterations=10 --warmup=2
zig build bench -- startup --iterations=1000 --warmup=100
zig build bench -- callbacks --verbose
zig build bench -- --json /tmp/bench.json --csv /tmp/bench.csv
```

All groups accept `--list`, selectors, `--iterations`, `--warmup` (or `--no-warmup`), `--verbose`, `--json`, and `--csv`. Options with values also accept `--option=value`. Process selectors match fixture names, paths, or directories. Startup and snapshot selectors match a case, engine, or the paths printed by `--list`.

Process fixtures default to 30 samples per engine and 1 warmup unless their metadata says otherwise. Startup and snapshots default to 1,000 samples and 100 warmups. `--category` selects a process metadata category or the `startup` / `snapshots` group.

Use `sustained` to measure longer-running Lua code with less influence from process startup. These fixtures default to 10 samples and 2 warmups. Keep the shorter fixtures when startup time matters to your application.

## Reading the results

The main tables show medians and sample counts. For process comparisons, **zlua/Lua below 1 is faster**. For snapshots, **speedup above 1 is faster**. Break-even estimates how many resets recover the capture cost: `ceil(capture / (rebuild - reset))`. A dash means no saving or an unavailable result.

Use `--verbose` for phase timings, p95, spread, and allocation details. With very few samples, p95 is usually the maximum; use more samples before drawing conclusions.

Allocation counts and bytes are medians across samples. Requested bytes include positive resize growth. Live bytes are storage after the operation; peak includes storage already live at its start. Capture counts the new snapshot only. `new_state` counts the new worker only, excluding retained snapshot storage. Reset and rebuild count VM storage, including retained rollback storage. Reset restores the State’s own baseline using storage swaps. Worker journal storage created during capture appears in subsequent VM live totals. The native runtime column estimates GC objects separately. A dash means unavailable, not zero.

JSON format 2 includes run metadata, raw samples, summaries, and comparisons for every group. Existing process records and their mean-based ratio remain under `benchmarks`. CSV format 2 has one row per operation sample; failed or skipped operations with no samples still get a row. Both formats store nanoseconds and bytes.

Save a baseline, make the change, and repeat the same command on an otherwise idle machine. Look at the samples and spread as well as the ratio. Process runs alternate engine order and check every pair's exit status and output outside the timer.

## Snapshot reset measurements

`reset_only` times restoration after the workload; `noop_reset` resets immediately after restoration, with no intervening Lua call or mutation. `mutation` includes the first writes and host-to-Lua call overhead. `cycle` times work plus reset so first-write copying cannot disappear from the reported cost. The existing `reset` operation continues to include teardown for comparison with `rebuild`.

Cases cover small and large unchanged baselines, sparse and dense writes across 10,000 tables, a single write to a 100,000-entry array, suspended coroutine resumes, collection of baseline objects, modules, callbacks, and both eager and scoped resource hooks. `no_op_small` and `no_op_large` expose heap-size scaling in reset time and allocations. No-op reset should allocate nothing for baselines without eager hooks. Sparse reset restores dirty records and cleans private allocations; first writes can copy a whole table or allocation registry, so compare `mutation` and `cycle` as well as `reset_only`.

```sh
zig build bench -- --family=snapshots --iterations=20 --warmup=3 --verbose
zig build bench -- no_op_small no_op_large --json /tmp/noop-reset.json
```

## Adding a case

Add a Lua fixture under `tests/bench/<category>/` for a complete-program comparison:

```lua
-- name: table/array_reads
-- category: table
-- iterations: 10
-- warmup: 1
-- timeout-ms: 60000
```

Without metadata, the name is the fixture path and the category is `misc`. `expect: skip` or `expect: fail` excludes a fixture and requires a `reason`.

For an in-process case, add it to `src/testing/bench/startup.zig` or `snapshots.zig`. Keep setup and cleanup visibly outside the timer unless they are the operation being measured. The upstream Lua worker in `tools/bench_c_api_startup.c` returns raw measurements to the same Zig reporter.
