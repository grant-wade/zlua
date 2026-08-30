# Lua C API

zlua provides a source-compatible Lua 5.5 C API as the static library `zlua-c`. It is meant for C code rebuilt against zlua, not as an ABI-compatible replacement for an installed `liblua`.

For Zig hosts, `zlua.State` remains the preferred API: it provides typed values, rooted handles, capabilities, and resource limits without C stack discipline.

## Build and Link

Build the library, Lua headers, and fixture harness:

```sh
zig build c-api
```

This installs:

```text
zig-out/lib/libzlua-c.a
zig-out/include/lua.h
zig-out/include/lauxlib.h
zig-out/include/lualib.h
zig-out/include/luaconf.h
zig-out/bin/zlua-test-c-api
```

The headers come from the downloaded Lua 5.5 source, so normal includes work:

```c
#include "lua.h"
#include "lauxlib.h"
#include "lualib.h"
```

A minimal link command is:

```sh
zig cc -std=c99 -Wall -Wextra \
  -I zig-out/include \
  main.c zig-out/lib/libzlua-c.a \
  -o main
```

Rebuild `zlua-c` with the target and optimization settings used by the consuming application.

## Verification

Run the complete C API check or a focused fixture:

```sh
zig build ci-c-api
zig build test-c-api -- tests/c-api/stack
zig build test-c-api -- tests/c-api/coroutines/newthread_resume.c
```

Each fixture is compiled against both downloaded Lua 5.5 and `zlua-c`; the harness compares exit status, stdout, and stderr. `tests/fixtures/c_api_status.toml` is the tracked public-symbol inventory and is validated before fixtures run.

## Boundaries

| Boundary | What it means |
| --- | --- |
| Static integration | Rebuild C code against zlua's installed headers and library. Existing Lua binaries and dynamic modules are not ABI-compatible by promise. |
| Lua 5.5 only | Multi-version modes and LuaJIT compatibility are out of scope. |
| zlua bytecode | `lua_dump` produces zlua chunks, not PUC Lua `luac` chunks. |
| No native module loader | LuaRocks-style dynamic C modules are not supported. Statically linked hosts and Lua source modules are supported. |
| Entry-point behavior | The CLI, Zig API, and C API initialize host access differently. Test C hosts with the libraries and services they actually open. |

Changes to C behavior should include a focused fixture under `tests/c-api` and keep the affected symbol marked `tested-clua-diff`.
