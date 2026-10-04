# Contributing

zlua is compatibility-driven. When Lua-visible behavior is in question, use the official Lua 5.5 implementation as the oracle and add a regression test.

## Setup

Use Zig `0.16.0` or `0.17.0`. Validate compatibility changes with both versions.

```sh
zig version
zig build fetch-lua
```

`fetch-lua` downloads Lua 5.5 source and official tests into `.zlua-deps/`, which is ignored by Git.

## Workflow

For behavior changes:

1. Add or update a fixture, unit test, or embedding example.
2. Verify expected behavior against CLua when the behavior is Lua-visible.
3. Make the smallest implementation change that preserves compatibility.
4. Run a focused check first.
5. Run broader checks before submitting.

Default CI-equivalent check:

```sh
zig build ci test-wasm check-tools
```

Format touched Zig files with Zig `0.16.0`. The `0.17.0` formatter rewrites some
builtins into forms that `0.16.0` cannot parse. Point `just` at the older compiler:

```sh
just --set zig /path/to/zig-0.16.0/zig fmt
```

## Docs

Detailed conventions live in:

| Document | Scope |
| --- | --- |
| [Development](docs/development.md) | Project shape, commands, source conventions, and local workflow. |
| [Testing](docs/testing.md) | Differential fixtures, official dashboard and CI policy. |
| [Benchmarking](docs/benchmark.md) | Performance workflow and benchmark interpretation. |
| [Architecture](docs/architecture.md) | Implementation structure and invariants. |
| [Embedding](docs/embedding.md) | Public Zig embedding API. |
