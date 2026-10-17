# Benchmarking

Run the whole suite with `zig build bench` (or `just bench`). It runs each group below in turn and produces a single report:

| Group | Measures |
| --- | --- |
| Process | Complete Lua programs under zlua, zlua snapshot, and Lua 5.5, including process launch, compilation, and shutdown. |
| Startup | State creation, library opening, and the first chunk, through both the native Zig API and upstream Lua’s C API. |
| Snapshots | Capture, new State creation (`new_state`), first-work mutation, reset-only, no-op reset, full work/reset cycles, and an equivalent rebuild. |
| GC | Single basic collector steps over several workloads, including transient garbage, stable heaps, weak tables, and finalizers, with setup excluded. |

Every benchmark builds both zlua and C Lua with ReleaseFast, including the process comparisons and the C startup workers, whatever `-Doptimize` you pass. The in-process groups (startup, snapshots, and GC) don't include process launch in their timings. Startup totals are the sum of the measured phases, not a separately timed operation.

## Running a benchmark

```sh
zig build bench -- --list
zig build bench -- table/pairs_iteration --iterations=20
zig build bench -- sustained --iterations=10 --warmup=2
zig build bench -- startup --iterations=1000 --warmup=100
zig build bench -- callbacks --verbose
zig build bench -- --json /tmp/bench.json --csv /tmp/bench.csv
```

Every group accepts `--list`, selectors, `--iterations`, `--warmup` (or `--no-warmup`), `--verbose`, `--json`, and `--csv`, and options that take a value also accept `--option=value`. What a selector matches depends on the group. For process benchmarks it matches fixture names, paths, or directories. For the in-process groups it matches a case, an engine, or one of the paths printed by `--list`.

Process fixtures default to 30 samples per engine and 1 warmup unless their metadata says otherwise. The startup, snapshot, and GC groups default to 1,000 samples and 100 warmups. `--category` selects either a process metadata category or one of the `startup`, `snapshots`, or `gc` groups.

If you want to measure longer-running Lua code without process startup dominating the result, use the `sustained` fixtures. They default to 10 samples and 2 warmups. Stick with the shorter fixtures when startup time matters to your application.

## Reading the results

The main tables show medians and sample counts. The process table shows three ratios: zlua/Lua, snapshot/Lua, and snapshot/zlua. **A ratio below 1 means the numerator is faster.** The snapshot tables report speedup instead, where **a speedup above 1 is faster**. Break-even estimates how many resets it takes to recover the cost of a capture: `ceil(capture / (rebuild - reset))`. A dash means there is no saving or the result is unavailable.

Use `--verbose` to see phase timings, p95, spread, and allocation details. With only a few samples, p95 is usually just the maximum, so collect more samples before drawing conclusions.

Allocation counts and bytes are medians across samples, and each operation counts storage a little differently:

- Requested bytes include positive resize growth. Live bytes are the storage held after the operation, and peak includes storage that was already live when it started.
- Capture counts only the new snapshot. `new_state` counts only the new worker, not the retained snapshot storage.
- Reset and rebuild count VM storage, including retained rollback storage. Reset restores the State’s own baseline by swapping storage. Worker journal storage created during capture shows up in later VM live totals.
- The native runtime column estimates GC objects separately.

In the allocation columns, too, a dash means unavailable, not zero.

Both report formats store nanoseconds and bytes. JSON format 2 includes run metadata, raw samples, summaries, and comparisons for every group, and keeps the existing process records and their mean-based ratio under `benchmarks`. CSV format 2 has one row per operation sample, and an operation that failed or was skipped still gets a row even though it has no samples.

To compare a change, save a baseline, make the change, and repeat the same command on an otherwise idle machine. Look at the samples and spread, not just the ratio. Process runs rotate all three engines through each execution position. Outside the timer, they also check both zlua variants against Lua 5.5 for every sample's exit status and output.

## Snapshot program comparisons

The top Process table runs every selected Lua fixture three ways: in an ordinary zlua state, in a zlua state restored from a snapshot, and under Lua 5.5. The snapshot worker opens the full libraries and installs `arg`, captures that baseline, calls `Snapshot.newState`, and then loads and executes the fixture in the restored state. Snapshot tracking stays active for the whole run.

All three columns time complete processes. The snapshot column includes baseline initialization, capture, restoration, compilation, execution, and teardown, so it does not show the amortized startup savings you would get from reusing a snapshot. When you are comparing general execution performance, use the `sustained` fixtures to reduce the influence of those setup costs. The snapshot capture and reset microbenchmarks have their own section, described below.

`zig build bench` supplies a ReleaseFast snapshot worker automatically. If you run `zlua-test-bench` directly, it defaults to the installed sibling `zlua-test-bench-snapshot`, and `--zlua-snapshot PATH` overrides that. JSON and CSV reports identify this third engine as `zlua_snapshot` and include its samples and comparisons.

## Snapshot reset measurements

Each snapshot operation isolates a different part of the cost:

- `reset_only` times restoration after the workload.
- `noop_reset` resets immediately after restoration, with no Lua call or mutation in between.
- `mutation` includes the first writes and the overhead of calling from the host into Lua.
- `cycle` times the work plus the reset, so the cost of copying on first write can't drop out of the reported number.
- The existing `reset` operation still includes teardown, so it can be compared with `rebuild`.

The cases cover small and large unchanged baselines, sparse and dense writes across 10,000 tables, a single write to a 100,000-entry array, resuming suspended coroutines, collecting baseline objects, modules, callbacks, and both eager and scoped resource hooks. `no_op_small` and `no_op_large` show how reset time and allocations scale with heap size. A no-op reset should allocate nothing for baselines without eager hooks. A sparse reset restores dirty records and cleans up private allocations, but a first write can copy a whole table or allocation registry, so compare `mutation` and `cycle` as well as `reset_only`.

```sh
zig build bench -- --family=snapshots --iterations=20 --warmup=3 --verbose
zig build bench -- no_op_small no_op_large --json /tmp/noop-reset.json
```

## Adding a case

For a complete-program comparison, add a Lua fixture under `tests/bench/<category>/`:

```lua
-- name: table/array_reads
-- category: table
-- iterations: 10
-- warmup: 1
-- timeout-ms: 60000
```

Without metadata, the name is the fixture path and the category is `misc`. `expect: skip` or `expect: fail` excludes a fixture, and either one requires a `reason`.

For an in-process case, add it to `src/testing/bench/startup.zig`, `snapshots.zig`, or `gc.zig`. Keep setup and cleanup visibly outside the timer unless they are the operation you are measuring. The upstream Lua worker in `tools/bench_c_api_startup.c` returns raw measurements to the same Zig reporter.
