# zlua

zlua is a source-compatible Lua 5.5 implementation written in Zig. You can use it as a command-line interpreter, or embed it in a Zig application and decide exactly what Lua code is allowed to touch.

zlua is pre-1.0 and supports Zig `0.16.0` and `0.17.0`. The Zig embedding API is the main public interface. Internals and the binary chunk format may still change between releases.

Development happens on GitHub, and Codeberg hosts a source mirror.

## Quickstart

1. Add zlua to your Zig package dependencies through github or codeberg:

```sh
zig fetch --save git+https://github.com/grant-wade/zlua#v0.7.3

zig fetch --save git+https://codeberg.org/gron/zlua#0.7.3
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

By default, a new state opens only the sandbox-friendly standard libraries. Everything else is up to the host: filesystem access, output, clocks, processes, bytecode, callbacks, userdata, and resource limits are all opt-in.

## Goals

zlua follows the official Lua 5.5 implementation as closely as practical, from parser behavior and runtime semantics to the standard libraries and diagnostics. Beyond compatibility, the project has three goals:

- Run Lua 5.5 programs from the command line.
- Make Lua straightforward to embed in Zig.
- Give hosts explicit control over what Lua can access and how many resources it can use.

## Common Commands

These are the commands you will reach for most often. Build the CLI and the Lua 5.5 reference binary:

```sh
zig build
```

Run a Lua script through the build runner:

```sh
zig build run -- path/to/script.lua
```

Compile and run the Zig embedding examples:

```sh
zig build examples
```

Run the full check suite before you send a change:

```sh
zig build ci
```

## Compatibility

Compatibility is checked against the real thing. The build downloads the Lua 5.5 sources and official tests, then builds a local `lua5.5` to compare against, so you do not need Lua installed on your system.

`zig build ci` brings all of this together. It runs:

- Zig unit tests for the compiler, runtime, and public API.
- Small Lua programs under both zlua and the official implementation, comparing the results.
- The upstream Lua 5.5 test suite.
- The Zig embedding examples.

## More Documentation

The [documentation index](docs/README.md) links to guides on embedding, the standard library, commands, testing, architecture, and the development workflow. Release notes are in the [changelog](CHANGELOG.md).

## License

zlua is available under the [MIT License](LICENSE).

zlua gratefully acknowledges [Lua](https://www.lua.org/), created and maintained by the Lua team at PUC-Rio. The Lua language and reference implementation guide zlua's compatibility, and the project uses the official implementation and test suite for validation. Lua's copyright and MIT license are reproduced in [THIRD_PARTY_NOTICES](THIRD_PARTY_NOTICES).
