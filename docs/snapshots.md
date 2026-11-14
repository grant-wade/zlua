# Snapshots

A `Snapshot` is an immutable capture of a configured `State`.
`Snapshot.newState` creates independent workers from it, and `State.reset`
returns a worker to its baseline. See [Embedding](embedding.md#snapshots) for
the basic flow.

## Contents

- [Capture and Baselines](#capture-and-baselines)
- [Busy and Unsupported States](#busy-and-unsupported-states)
- [Threads](#threads)
- [What Reset Does](#what-reset-does)
- [Memory and Allocators](#memory-and-allocators)
- [Userdata Payloads](#userdata-payloads)
  - [Copy Hooks](#copy-hooks)
  - [Scoped Tracking](#scoped-tracking)
- [Host Bindings](#host-bindings)
- [Reset Costs](#reset-costs)

## Capture and Baselines

Capturing copies the VM heap, including suspended Lua coroutines, shared
references, module caches, I/O buffers, random state, and GC settings. It runs
no collection or cleanup callbacks. Workers share the snapshot's immutable
bytecode. Closures, caches, and other mutable VM objects are private to each
worker.

The point a state resets to is its baseline:

- `snapshot()` makes the capture the source state's baseline, and `newState()`
  gives the worker that same baseline.
- A fresh state has no baseline, and `reset()` returns `error.NoSnapshot`.
- Capturing again installs a later baseline. Older snapshots remain usable with
  `newState()`.
- A state keeps its baseline after every public `Snapshot` handle is destroyed.
- Snapshots are reusable, can outlive the source state, and have no persistence
  format.

To switch a worker to another template, construct the replacement before
releasing the old state. A failed construction leaves the old state usable:

```zig
const replacement = try other_snapshot.newState(allocator);
old.deinit();
old = replacement;
```

## Busy and Unsupported States

Snapshot and reset require an idle VM. They return `error.SnapshotBusy` if a
call is active, a collection is running, a scoped userdata access is open, or a
snapshot operation is called recursively. While the state is being destroyed,
`snapshot()` returns `error.SnapshotBusy` and `reset()` returns
`error.NoSnapshot`. Runtime objects zlua does not track return
`error.SnapshotUnsupported`.

## Threads

Serialize all use of each `State` externally, including reset.

Independently owned `Snapshot` handles share one immutable backing and can call
`newState()` concurrently. `snapshot.retain()` returns another handle to move to
its owner, and `deinit()` consumes only that handle. A bit copy of a `Snapshot`
is not a retain. Serialize each individual handle against mutation or `deinit`,
and keep an owned handle live throughout any `newState()` or `retain()` call.
The source state and the original handle can be destroyed before workers finish.

With a thread-safe allocator `a` that outlives the joined workers:

```zig
const Worker = struct {
    fn run(owned: zlua.Snapshot, allocator: std.mem.Allocator) void {
        var snapshot = owned; // ownership moved from the spawning thread
        const vm = snapshot.newState(allocator) catch {
            snapshot.deinit();
            return;
        };
        snapshot.deinit(); // vm retains its own baseline
        defer vm.deinit();
        vm.doString("result = 42", .{}) catch return;
        vm.reset() catch return;
    }
};
var snapshot = try lua.snapshot(a);
defer snapshot.deinit();
var threads: [4]std.Thread = undefined;
var started: usize = 0;
defer for (threads[0..started]) |thread| thread.join();
for (&threads) |*thread| {
    var owned = snapshot.retain();
    thread.* = std.Thread.spawn(.{}, Worker.run, .{ owned, a }) catch |err| {
        owned.deinit();
        return err;
    };
    started += 1; // the worker owns the retained handle
}
```

## What Reset Does

Reset fails atomically: a failure leaves the state, its handles, and its
baseline usable.

A successful reset:

- Invalidates every earlier handle, borrowed VM slice, and pointer. Operations
  on a stale handle return `error.InvalidHandle`, and `deinit` on one is
  harmless. Reacquire objects through globals or modules.
- Keeps worker-local addresses of tables, closures, upvalues, and threads.
- Restores options, host bindings, the error value (not a captured traceback),
  instruction usage, state-owned memory files, input positions, and GC settings.
- Runs no Lua `__gc` or `__close` handlers. Run application teardown first if
  you need it.
- Discards file handles opened since the baseline without flushing them.
- Does not restore the progress of an in-flight collection cycle, so collections
  and finalizers may run at different points.

Address-based strings, such as `tostring({})` or `%p` output, can differ after a
reset. Generational collection focuses on allocations made since the snapshot,
and a later full collection reclaims unreachable snapshot objects.

## Memory and Allocators

| Storage | Allocator | Counts against |
| --- | --- | --- |
| Snapshot backing | `snapshot_allocator` | Nothing, unless it is `state.allocator()`, which charges that state's limit and keeps its allocator infrastructure alive. |
| Worker VM | The allocator given to `newState` | The worker's memory limit, inherited from the capture. Includes rollback records, retained storage, private copies, and later allocations. |

Retained rollback storage is not a Lua GC root. The GC byte estimate leaves it
out and can be smaller than allocator usage.

A successful capture or `newState()` retains the backing as the state's
baseline. A worker also retains the owner of its borrowed bytecode.
`Snapshot.deinit` releases the public wrapper, and the backing is freed after
the last retaining state or handle releases it. `snapshot_allocator` must stay
valid for that whole lifetime, and an arena used for snapshot storage must not
be reset while a retaining state exists. Host-owned results can be freed through
the state allocator while the state lives.

When owners live on different threads, the final destruction of the backing, of
userdata, and of retained allocator infrastructure can happen on any of them,
with no deferred reclamation on an owner thread:

- These allocators must support overlapping allocation and free calls across
  threads, including freeing on another thread. A thread-confined arena does
  not.
- Worker-local allocators need no extra synchronization unless their storage is
  shared or exported.
- zlua's memory-limit allocator supports concurrent frees from shared owners.
  Allocation, resize, and state operations through `state.allocator()` stay with
  the state's owner, and the allocator underneath must meet the same
  requirements.

## Userdata Payloads

Payloads are shared by default, and changes to them survive reset. A Lua-owned
payload is finalized and freed once its last owner releases it. A borrowed
payload must outlive every state and snapshot that references it. zlua
synchronizes the lifetime bookkeeping and finalizes or disposes each payload at
most once. Synchronizing mutable payload access and owning external resources is
up to the host.

### Copy Hooks

Hooks passed to `newUserdata` or `wrapUserdata` give each worker its own copy:

```zig
const Counter = struct {
    value: i64,

    fn copy(allocator: std.mem.Allocator, source: *const @This()) !*@This() {
        const result = try allocator.create(@This());
        result.* = source.*;
        return result;
    }

    fn dispose(allocator: std.mem.Allocator, value: *@This()) void {
        allocator.destroy(value);
    }
};

var counter = try lua.newUserdata(Counter, .{ .value = 7 }, .{
    .snapshot = .{ .copy = Counter.copy, .dispose = Counter.dispose },
});
defer counter.deinit();
try lua.setGlobal("counter", counter);
```

- `copy` allocates all nested storage with the allocator it receives, and
  `dispose` releases that storage, including when construction fails or a
  snapshot is destroyed.
- Hooks must not hold source VM pointers or reenter snapshot operations.
- `copy` can run concurrently on one payload, so it must allow concurrent reads
  of the source and synchronize shared counters or resources.
- `dispose` and finalizers can run on different owner threads. zlua does not
  serialize host hooks.
- Capture skips application finalizers. Reset and discard skip them for hook
  copies and scoped payloads, and run them for other payloads they release:
  hookless or eager userdata created since the baseline, and a source state's
  original eager payload on its first reset.
- Normal finalizers must not free storage owned by `dispose`.

`.tracking` defaults to eager, which runs `copy` on every reset.

### Scoped Tracking

`.tracking = .scoped` copies a payload at capture, at `newState()`, and on its
first mutable access after the baseline, but not on reset:

```zig
var tracked = try lua.newUserdata(Counter, .{ .value = 7 }, .{
    .snapshot = .{
        .copy = Counter.copy,
        .dispose = Counter.dispose,
        .tracking = .scoped,
    },
});
defer tracked.deinit();
try tracked.withMut(@as(i64, 3), struct {
    fn add(value: *Counter, amount: i64) void { value.value += amount; }
}.add);
const count = try tracked.withRead({}, struct {
    fn read(value: *const Counter, _: void) i64 { return value.value; }
}.read);
```

- Scope callbacks receive `(payload, context)`. Payload pointers, including
  pointers to nested storage, must not escape.
- A read scope forbids mutating anything reachable from the payload, including
  slice contents.
- Scope results must not contain pointers. To copy out a buffer, pass
  caller-owned storage through the context.
- A read scope overlapping a write scope on one payload returns
  `error.ScopedAccessConflict`. Overlapping write scopes are allowed.
- Typed callbacks and auto-bound methods open a read scope for `*const T`
  arguments and a mutable scope for `*T` arguments.
- `ptr` and `Context.arg(..., *T)` return `error.ScopedAccessRequired`.
- Scoped tracking requires owned userdata, and `wrapUserdata` rejects it.
- A failed mutable scope keeps its writes, and the payload stays dirty.
- Reset disposes of the private copy and restores the pristine storage.
  Unchanged payloads need no copies.
- Finalization preserves the pristine storage first, and reset never restores a
  finalized resource.
- `dispose` releases both the initial payload and any copies, including nested
  storage.

## Host Bindings

Callbacks and host capabilities stay external, and must stay valid. Reset cannot
undo output already sent to the host or changes made outside the VM. During
capture, the source state takes ownership of copies of borrowed stdin and
read-only memory-file bytes.

## Reset Costs

Reset allocates nothing and traverses no heap when the baseline is unchanged and
no eager hooks exist. The costs are first writes, which copy an object's whole
storage, allocation-registry detachment, private-allocation cleanup, and eager
resource copies. Compare the `mutation` and `cycle`
[benchmarks](benchmark.md#snapshot-reset-measurements) with the reset-only
timings.

Runtime setters take part in tracking. Direct writes to raw object storage are
not tracked.
