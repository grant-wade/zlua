# Contributing

zlua is driven by compatibility. Whenever there is a question about Lua-visible behavior, the official Lua 5.5 implementation is the oracle: check what it does, match it, and add a regression test so the behavior stays put.

## Setup

You need Zig `0.16.0` or `0.17.0`, and compatibility changes should be validated with both.

```sh
zig version
zig build fetch-lua
```

`fetch-lua` downloads the Lua 5.5 source and official tests into `.zlua-deps/`, which Git ignores.

## Workflow

A behavior change usually goes like this:

1. Add or update a fixture, unit test, or embedding example that shows the behavior.
2. If the behavior is visible from Lua, confirm what CLua does.
3. Make the smallest implementation change that keeps zlua compatible.
4. Run a focused check first.
5. Run the broader checks before you submit.

To run the main checks that CI runs:

```sh
zig build ci test-wasm check-tools
```

Format the Zig files you touch with Zig `0.16.0`. The `0.17.0` formatter rewrites some
builtins into forms that `0.16.0` cannot parse, so point `just` at the older compiler:

```sh
just --set zig /path/to/zig-0.16.0/zig fmt
```

## Docs

The detailed conventions live in these guides:

| Document | Scope |
| --- | --- |
| [Development](docs/development.md) | Project shape, commands, source conventions, and local workflow. |
| [Testing](docs/testing.md) | Differential fixtures, the official dashboard, and CI policy. |
| [Benchmarking](docs/benchmark.md) | Performance workflow and how to read benchmark results. |
| [Architecture](docs/architecture.md) | Implementation structure and invariants. |
| [Embedding](docs/embedding.md) | Public Zig embedding API. |
