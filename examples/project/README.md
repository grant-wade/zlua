# zlua-test

`zlua-test` is a small project that checks zlua works as a dependency of another Zig project, on both Zig `0.16.0` and `0.17.0`. CI builds, runs, and tests it on every push.

It depends on this checkout of `zlua` through `.path = "../.."` in `build.zig.zon`, wires the dependency into `build.zig`, and imports it in `src/main.zig` with `@import("zlua")`.

## Usage

Run these commands from this directory. Build the executable:

```sh
zig build
```

Run the example program:

```sh
zig build run
```

Run the tests:

```sh
zig build test
```

## Dependency Setup

In your own project you will usually depend on a published release instead, added with `zig fetch --save` as shown in the root README. Either way, the module wiring in `build.zig` is the same:

```zig
const zlua_dep = b.dependency("zlua", .{
    .target = target,
    .optimize = optimize,
});

exe.root_module.addImport("zlua", zlua_dep.module("zlua"));
```
