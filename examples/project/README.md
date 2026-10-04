# zlua-test

`zlua-test` is a small test project for validating how a downstream Zig project consumes zlua on Zig `0.16.0` and `0.17.0`.

The project depends on this checkout of `zlua` through `.path = "../.."` in `build.zig.zon`, wires the dependency into `build.zig`, and imports it from `src/main.zig` as `@import("zlua")`.

## Usage

Build the executable:

```sh
zig build
```

Run the example program:

```sh
zig build run
```

Run tests:

```sh
zig build test
```

## Dependency Setup

When using a published release in your own project, add zlua with `zig fetch --save` as shown in the root README. The module wiring is the same for a local or fetched dependency:

```zig
const zlua_dep = b.dependency("zlua", .{
    .target = target,
    .optimize = optimize,
});

exe.root_module.addImport("zlua", zlua_dep.module("zlua"));
```
