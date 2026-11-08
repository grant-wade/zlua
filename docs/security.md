# Running Untrusted Lua

This guide covers what zlua protects a host from when it runs code it doesn't
trust, and how to configure a state for that.

## Contents

- [Guarantees](#guarantees)
- [Configuration](#configuration)
- [What Each Limit Covers](#what-each-limit-covers)
- [Outside the Guarantees](#outside-the-guarantees)
- [Host Responsibilities](#host-responsibilities)

## Guarantees

For a state with the `safe` libraries, default capabilities, and
`Limits.untrusted`, Lua code cannot:

| Goal | Enforced by |
| --- | --- |
| Crash or corrupt the host | Native stack limit, nesting limits, memory-safe VM |
| Hang the host | Instruction budget, finalizer budget, interrupts |
| Reach anything the host did not grant | Capabilities |
| Exceed its memory or output allowance | `max_memory`, `max_output_bytes` |
| Break host resource lifetimes | Userdata finalization rules |

A crash, hang, or limit overrun reachable from Lua under this configuration is a
bug in zlua.

## Configuration

```zig
var lua = try zlua.State.init(allocator, .{
    .limits = zlua.Limits.untrusted,
});
```

`Limits.untrusted` sets memory, instruction, call frame, stack value, output,
and file size limits. Adjust each one to the host. Set `max_native_stack` when
the state runs on a thread with less than 8 MiB of stack:

```zig
var limits = zlua.Limits.untrusted;
limits.max_native_stack = thread_stack_bytes * 3 / 4;
```

Leave room below the limit for the deepest native call, about 128 KiB in Debug
builds.

## What Each Limit Covers

| Limit | Covers | When it runs out |
| --- | --- | --- |
| `max_instructions` | VM instructions, and native work charged by its size: string and table operations, pattern matching, `load`, `collectgarbage`, and the data format libraries. | `instruction limit exceeded`, which `pcall` cannot catch. |
| `max_memory` | Every allocation through the state. Garbage is collected first when an allocation may not fit. | `memory limit exceeded`. |
| `max_output_bytes` | Bytes written to stdout and stderr, and warnings. | `output limit exceeded`, which `pcall` cannot catch, until `resetOutputLimit`. |
| `max_native_stack` | Native stack used by recursion through metamethods, callbacks, coroutines, and the compiler. | A catchable `C stack overflow`, or a syntax error while compiling. |
| `max_finalizer_instructions` | Lua `__gc` run by each `deinit`, `collect`, or `stepGc`. | Remaining Lua finalizers fail with a warning. Host finalizers still run. |
| `max_call_frames`, `max_stack_values` | Lua call depth and stack size. | A catchable `stack overflow`. |
| `max_file_bytes` | Each file read or write. | An error from the file operation. |

Budgets count work, not time. Use an
[`InterruptHandle`](embedding.md#interrupts) from another thread for a
wall-clock deadline. Interrupts are polled by the VM, native loops, and the compiler. A
collection cycle or a TOML or CSV parse finishes before the interrupt takes effect.

A table or the string intern set that sees a long probe chain switches to SipHash
with a secret per-process key. The key comes from OS randomness, or from addresses
on `freestanding` targets and where the OS provides none.

`load`, `loadfile`, `dofile`, and `require` reject binary chunks unless
`Options.binary_chunks` is set.
`State.loadBytecode` always accepts them. Binary chunks pass a structural
verifier, and you should only enable them for chunks you trust.

## Outside the Guarantees

- Host callbacks and any library the host opens beyond `safe`. The `debug`
  library can read and change any local, upvalue, or metatable in the state,
  including those of other scripts.
- Capabilities the host grants. A host directory or process capability gives
  scripts that access.
- Isolation between scripts in one state. Scripts share globals and the string
  metatable, so use one state or `Snapshot` worker per trust domain.
- Side channels. Scripts can measure time through their own work and can see
  object addresses through `tostring` and `%p`.
- Other programs writing to a `host_dir` root. Paths are checked for symlinks
  before each open, and Lua has no API to create them.
- Disk use and open files under a host filesystem capability. Set
  `MemoryFilesystem.Options.max_bytes` to limit a memory filesystem.

## Host Responsibilities

- Release resources in `UserdataOptions.finalizer`, which Lua can't call or
  remove. A `__gc` method of the userdata type runs at most once per object,
  and later typed access to that object fails with `userdata is closed`.
- Keep userdata metatables hidden. `UserdataType.expose_metatable` lets
  `getmetatable` return them, and scripts can then change the methods of every
  object of that type.
- Treat callback arguments as hostile. `decode` rejects values nested more than
  200 levels deep, and tables can be cyclic.
- Bound what callbacks do on a script's behalf. Work in a callback isn't charged
  to the budget.
