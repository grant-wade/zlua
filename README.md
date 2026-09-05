# zlua

zlua is a source-compatible Lua 5.5 implementation written in Zig. You can use it as a command-line interpreter or embed it in a Zig application with control over what Lua can access.

zlua is pre-1.0 and currently targets Zig `0.16.0`. The Zig embedding API is the main public interface; internals, binary chunks, and C API coverage may still change.

## Quickstart

1. Add zlua to your Zig package dependencies:

```sh
zig fetch --save git+https://codeberg.org/gron/zlua#v0.4.3
```

2. Wire the dependency into your executable in `build.zig`:

```zig
const zlua_dep = b.dependency("zlua", .{
    .target = target,
    .optimize = optimize,
});

exe.root_module.addImport("zlua", zlua_dep.module("zlua"));
```

3. Import zlua from Zig and run a Lua chunk:

```zig
const std = @import("std");
const zlua = @import("zlua");

const Budget = struct {
    remaining: i64,

    pub fn init(amount: i64) @This() {
        return .{ .remaining = amount };
    }

    pub fn spend(self: *@This(), amount: i64) i64 {
        self.remaining = @max(self.remaining - amount, 0);
        return self.remaining;
    }
};

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;

    var lua = try zlua.State.init(allocator, .{});
    defer lua.deinit();

    var new_budget = try lua.registerUserdataInitializerWith(Budget, "new_budget", Budget.init, .{});
    defer new_budget.deinit();
    try lua.setGlobal("new_budget", new_budget);

    var chunk = try lua.loadString(
        \\local budget = new_budget(25)
        \\budget:spend(7)
        \\budget:spend(20)
        \\return budget
    , .{ .name = "=readme" });
    defer chunk.deinit();

    var budget = try chunk.call(.{}, zlua.Userdata(Budget));
    defer budget.deinit();

    std.debug.print("remaining={d}\n", .{(try budget.ptr()).remaining});
}
```

Output:

```text
remaining=0
```

By default, a state opens sandbox-friendly standard libraries. Hosts can opt into filesystem access, output, clocks, processes, bytecode, callbacks, userdata, and resource limits.

## Goals

zlua follows the official Lua 5.5 implementation as closely as practical, including parser behavior, runtime semantics, standard libraries, diagnostics, and the C API. It aims to:

- Run Lua 5.5 programs from the command line.
- Make Lua straightforward to embed in Zig.
- Give hosts explicit control over capabilities and resource limits.
- Provide useful, test-backed Lua C API compatibility.

## Common Commands

Build the CLI and Lua 5.5 reference binary:

```sh
zig build
```

Run a Lua script through the build runner:

```sh
zig build run -- path/to/script.lua
```

Compile the Zig embedding examples:

```sh
zig build examples
```

Run the full check suite:

```sh
zig build ci
```

## Compatibility

The build downloads the Lua 5.5 sources and official tests, then builds a local `lua5.5` as a reference. You do not need a system Lua installation.

`zig build ci` runs:

- Zig unit tests for the compiler, runtime, and public API.
- Small Lua programs against both zlua and the official implementation.
- The upstream Lua 5.5 test suite.
- Zig embedding examples.
- C API compatibility tests.

## More Documentation

The [documentation index](docs/README.md) covers embedding, the standard library, commands, testing, architecture, C API compatibility, and development workflows.

## License

zlua is available under the [MIT License](LICENSE).
