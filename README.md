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

3. Run a Lua plugin from Zig:

```zig
const std = @import("std");
const zlua = @import("zlua");

const Alert = struct {
    name: []const u8,
    limit: i64 = 100,
    tags: []const []const u8 = &.{},
};

fn clamp(value: i64, min: i64, max: i64) i64 {
    return @min(@max(value, min), max);
}

const plugin =
    \\local plugin = {
    \\  alert = { name = "disk", limit = clamp(250, 0, 90), tags = { "ops" } },
    \\}
    \\
    \\function plugin.check(used)
    \\  if used < 0 then while true do end end
    \\  return used > plugin.alert.limit
    \\end
    \\
    \\return plugin
;

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;

    var lua = try zlua.State.init(gpa, .{ .limits = zlua.Limits.untrusted });
    defer lua.deinit();

    var clamp_fn = try lua.registerTyped("clamp", clamp);
    defer clamp_fn.deinit();
    try lua.setGlobal("clamp", clamp_fn);

    var chunk = try lua.loadString(plugin, .{ .name = "=plugin" });
    defer chunk.deinit();
    var module = try chunk.call(.{}, zlua.Table);
    defer module.deinit();

    var arena: std.heap.ArenaAllocator = .init(gpa);
    defer arena.deinit();
    var diagnostic: zlua.Diagnostic = .{ .gpa = gpa };
    defer diagnostic.deinit();
    var alert_value = try module.get("alert", zlua.Value);
    defer alert_value.deinit();
    const alert = try zlua.decode(Alert, alert_value, .{
        .allocator = arena.allocator(),
        .diagnostic = &diagnostic,
    });

    var check = try module.get("check", zlua.Function);
    defer check.deinit();
    const over = try check.call(.{95}, bool);
    std.debug.print("{s} limit={d} tags={d} over={}\n", .{ alert.name, alert.limit, alert.tags.len, over });

    switch (try check.protectedCallWith(.{-1}, bool, .{ .max_instructions = 10_000 })) {
        .ok => unreachable,
        .lua_error => |error_ref| {
            var err = error_ref;
            defer err.deinit();
            const message = try err.message();
            defer gpa.free(message);
            std.debug.print("stopped: {s}\n", .{message});
        },
    }
}
```

Output:

```text
disk limit=90 tags=1 over=true
stopped: plugin:6: instruction limit exceeded
```

The plugin runs under the `untrusted` resource limits and calls a typed Zig
function. The host decodes the plugin's table into a Zig struct, calls its Lua
function, and stops a runaway call with a per-call instruction budget.

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
