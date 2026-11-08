# zlua

zlua is a source-compatible Lua 5.5 implementation written in Zig. You can use
it as a command-line interpreter, or embed it in a Zig application and decide
exactly what Lua code is allowed to touch.

zlua is pre-1.0 and supports Zig `0.16.0` and `0.17.1`. The Zig embedding API is
the main public interface. Internals and the binary chunk format may still
change between releases.

Development happens on GitHub, and Codeberg hosts a source mirror.

## Quickstart

1. Add zlua to your Zig package dependencies through github or codeberg:

```sh
zig fetch --save git+https://github.com/grant-wade/zlua#v0.8.0

zig fetch --save git+https://codeberg.org/gron/zlua#v0.8.0
```

2. Wire the dependency into your executable in `build.zig`:

```zig
const zlua_dep = b.dependency("zlua", .{
    .target = target,
    .optimize = optimize,
});

exe.root_module.addImport("zlua", zlua_dep.module("zlua"));
```

3. Call Zig from Lua, and Lua from Zig:

```zig
const std = @import("std");
const zlua = @import("zlua");

fn add(a: i64, b: i64) i64 {
    return a + b;
}

pub fn main(init: std.process.Init) !void {
    var lua = try zlua.State.init(init.gpa, .{
        .limits = .{ .max_instructions = 1_000_000 },
    });
    defer lua.deinit();

    var add_fn = try lua.registerTyped("add", add);
    defer add_fn.deinit();
    try lua.setGlobal("add", add_fn);

    try lua.doString(
        \\function greet(name)
        \\  return "hello, " .. name .. "! 2 + 3 = " .. add(2, 3)
        \\end
    , .{ .name = "=readme" });

    var greet = try lua.getGlobal("greet", zlua.Function);
    defer greet.deinit();
    const message = try greet.call(.{"zlua"}, []const u8);
    std.debug.print("{s}\n", .{message});
}
```

Output:

```text
hello, zlua! 2 + 3 = 5
```

The [embedding guide](docs/embedding.md) covers decoding tables into Zig
structs, userdata, coroutines, snapshots, and more, with runnable programs in
[`examples/`](examples).

By default, a new state opens only the sandbox-friendly standard libraries.
Everything else is up to the host: filesystem access, output, clocks, processes,
bytecode, callbacks, userdata, and resource limits are all opt-in. To run code
you don't trust, see [Running Untrusted Lua](docs/security.md).

## Goals

zlua follows the official Lua 5.5 implementation as closely as practical, from
parser behavior and runtime semantics to the standard libraries and diagnostics.
Beyond compatibility, the project has three goals:

- Run Lua 5.5 programs from the command line.
- Make Lua straightforward to embed in Zig.
- Give hosts explicit control over what Lua can access and how many resources it
  can use.

## Compatibility

Compatibility is checked against the real thing. The build downloads the Lua 5.5
sources and official tests, then builds a local `lua5.5` to compare against, so
you do not need Lua installed on your system.

`zig build ci` brings all of this together. It runs:

- Zig unit tests for the compiler, runtime, and public API.
- x86_64 and wasm32 freestanding smoke builds.
- Small Lua programs under both zlua and the official implementation, comparing
  the results.
- zlua-only library fixtures, checked against stored output.
- The upstream Lua 5.5 test suite.
- The Zig embedding examples.

## More Documentation

[Commands](docs/commands.md) covers building, running scripts, and running the
checks. The [documentation index](docs/README.md) links to guides on embedding,
the standard library, testing, architecture, and development. Release notes are
in the [changelog](CHANGELOG.md).

## License

zlua is available under the [MIT License](LICENSE).

zlua builds on [Lua](https://www.lua.org/) by PUC-Rio, and parts of it are
translated from the Lua sources. Lua's license is in
[THIRD_PARTY_NOTICES](THIRD_PARTY_NOTICES).
