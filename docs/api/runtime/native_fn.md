# runtime.native_fn

## Navigation

- [API Index](../README.md)
- Parent: [runtime](../runtime.md)

<details>
<summary>All documents</summary>

- [root](../root.md)
- [frontend](../frontend.md)
- [errors](../errors.md)
- [frontend.source](../frontend/source.md)
- [frontend.token](../frontend/token.md)
- [frontend.diagnostic](../frontend/diagnostic.md)
- [frontend.lexer](../frontend/lexer.md)
- [frontend.ast](../frontend/ast.md)
- [frontend.parser](../frontend/parser.md)
- [compile](../compile.md)
- [compile.resolver](../compile/resolver.md)
- [compile.bytecode](../compile/bytecode.md)
- [compile.proto](../compile/proto.md)
- [runtime.types](../runtime/types.md)
- [runtime](../runtime.md)
- [runtime.chunk](../runtime/chunk.md)
- [reflection](../reflection.md)
- [runtime.state](../runtime/state.md)
- [stdlib](../stdlib.md)
- [stdlib.base](../stdlib/base.md)
- [runtime.call](../runtime/call.md)
- [runtime.coroutine](../runtime/coroutine.md)
- [runtime.debug](../runtime/debug.md)
- [runtime.metatable](../runtime/metatable.md)
- [runtime.rollback](../runtime/rollback.md)
- [runtime.value](../runtime/value.md)
- [runtime.number_format](../runtime/number_format.md)
- [runtime.host](../runtime/host.md)
- [runtime.upvalue](../runtime/upvalue.md)
- [runtime.failure](../runtime/failure.md)
- [runtime.io](../runtime/io.md)
- [runtime.load](../runtime/load.md)
- [runtime.vm](../runtime/vm.md)
- [runtime.gc](../runtime/gc.md)
- [runtime.entry](../runtime/entry.md)
- [runtime.system](../runtime/system.md)
- [runtime.timezone](../runtime/timezone.md)
- [runtime.index](../runtime/index.md)
- [runtime.operators](../runtime/operators.md)
- [stdlib.table](../stdlib/table.md)
- [stdlib.string](../stdlib/string.md)
- [stdlib.string.format](../stdlib/string/format.md)
- [stdlib.string.pack](../stdlib/string/pack.md)
- [stdlib.string.pattern](../stdlib/string/pattern.md)
- [stdlib.math](../stdlib/math.md)
- [stdlib.utf8](../stdlib/utf8.md)
- [stdlib.coroutine](../stdlib/coroutine.md)
- [stdlib.debug](../stdlib/debug.md)
- [stdlib.io](../stdlib/io.md)
- [stdlib.static_strings](../stdlib/static_strings.md)
- [stdlib.os](../stdlib/os.md)
- [stdlib.package](../stdlib/package.md)
- [stdlib.json](../stdlib/json.md)
- [stdlib.zerde_lua](../stdlib/zerde_lua.md)
- [stdlib.toml](../stdlib/toml.md)
- [stdlib.msgpack](../stdlib/msgpack.md)
- [stdlib.csv](../stdlib/csv.md)
- [stdlib.fs](../stdlib/fs.md)
- [runtime.budget](../runtime/budget.md)
- [runtime.strings](../runtime/strings.md)
- [runtime.execute](../runtime/execute.md)
- [testing.process](../testing/process.md)
- [runtime.tests](../runtime/tests.md)
- [runtime.internal](../runtime/internal.md)
- [runtime.native_fn](../runtime/native_fn.md)
- [compile.compiler](../compile/compiler.md)
- [compile.fold](../compile/fold.md)
- [compile.disasm](../compile/disasm.md)
- [api](../api.md)
- [api.callbacks](../api/callbacks.md)
- [api.convert](../api/convert.md)
- [api.errors](../api/errors.md)
- [api.handle](../api/handle.md)
- [api.state](../api/state.md)
- [runtime.snapshot](../runtime/snapshot.md)
- [api.capabilities](../api/capabilities.md)
- [api.options](../api/options.md)
- [api.function](../api/function.md)
- [api.table](../api/table.md)
- [api.value](../api/value.md)
- [api.userdata](../api/userdata.md)
- [api.context](../api/context.md)
- [api.coroutine](../api/coroutine.md)
- [api.snapshot](../api/snapshot.md)
- [api.memory_limit](../api/memory_limit.md)
- [testing](../testing.md)
- [testing.clua](../testing/clua.md)
- [testing.bench_runner](../testing/bench_runner.md)
- [testing.bench.options](../testing/bench/options.md)
- [testing.bench.results](../testing/bench/results.md)
- [testing.bench.stats](../testing/bench/stats.md)
- [testing.bench.report](../testing/bench/report.md)
- [testing.bench.process](../testing/bench/process.md)
- [testing.bench.fixtures](../testing/bench/fixtures.md)
- [testing.bench.legacy_process](../testing/bench/legacy_process.md)
- [testing.bench.startup](../testing/bench/startup.md)
- [testing.bench.allocation](../testing/bench/allocation.md)
- [testing.bench.c_startup](../testing/bench/c_startup.md)
- [testing.bench.snapshots](../testing/bench/snapshots.md)
- [testing.bench.gc](../testing/bench/gc.md)
- [testing.diff_runner](../testing/diff_runner.md)
- [testing.fixtures](../testing/fixtures.md)
- [testing.expected_failures](../testing/expected_failures.md)
- [testing.metadata](../testing/metadata.md)
- [testing.normalizer](../testing/normalizer.md)
- [testing.parallel](../testing/parallel.md)
- [testing.extension_runner](../testing/extension_runner.md)
- [testing.official_suite](../testing/official_suite.md)

</details>

## Types

- [NativeFn](#type-nativefn)

<a id="type-nativefn"></a>

## NativeFn

```zig
pub const NativeFn = enum {
    load,
    type,
    tonumber,
    warn,
    table_concat,
    table_dedup,
    table_insert,
    table_move,
    table_pack,
    table_remove,
    table_sort,
    table_unpack,
    string_byte,
    string_char,
    string_dump,
    string_find,
    string_format,
    string_gmatch,
    string_gmatch_iter,
    string_gsub,
    string_len,
    string_lower,
    string_match,
    string_pack,
    string_packsize,
    string_rep,
    string_reverse,
    string_rsplit,
    string_split,
    string_strip,
    string_sub,
    string_unpack,
    string_upper,
    math_abs,
    math_acos,
    math_asin,
    math_atan,
    math_ceil,
    math_cos,
    math_deg,
    math_exp,
    math_floor,
    math_fmod,
    math_frexp,
    math_ldexp,
    math_log,
    math_max,
    math_min,
    math_modf,
    math_rad,
    math_random,
    math_randomseed,
    math_sin,
    math_sqrt,
    math_tan,
    math_tointeger,
    math_type,
    math_ult,
    utf8_char,
    utf8_codepoint,
    utf8_codes,
    utf8_codes_iter,
    utf8_len,
    utf8_offset,
    loadfile,
    dofile,
    require,
    package_searchpath,
    package_searcher_preload,
    package_searcher_lua,
    package_loadlib,
    io_read,
    io_write,
    io_open,
    io_input,
    io_output,
    io_close,
    io_flush,
    io_lines,
    io_tmpfile,
    io_type,
    io_popen,
    io_file_read,
    io_file_write,
    io_file_close,
    io_file_seek,
    io_file_flush,
    io_file_lines,
    io_file_setvbuf,
    io_file_tostring,
    io_file_gc,
    io_lines_iter,
    os_time,
    os_clock,
    os_date,
    os_getenv,
    os_setlocale,
    os_execute,
    os_remove,
    os_rename,
    os_tmpname,
    os_difftime,
    os_exit,
    debug_getinfo,
    debug_getupvalue,
    debug_setupvalue,
    debug_upvalueid,
    debug_upvaluejoin,
    debug_getlocal,
    debug_setlocal,
    debug_getregistry,
    debug_sethook,
    debug_gethook,
    debug_setmetatable,
    debug_setuservalue,
    debug_getuservalue,
    debug_getmetatable,
    debug_debug,
    traceback_message_handler,
    json_read,
    json_write,
    toml_read,
    toml_write,
    msgpack_read,
    msgpack_write,
    csv_read,
    csv_write,
    fs_read,
    fs_write,
    fs_open,
    fs_stat,
    fs_exists,
    fs_list,
    fs_scandir,
    fs_walk,
    fs_mkdir,
    fs_remove,
    fs_copy,
    fs_rename,
    fs_move,
    fs_touch,
    fs_open_dir,
    fs_iterator_next,
    fs_iterator_close,
    fs_iterator_skip,
    fs_error_tostring,
    fs_file_stat,
    fs_file_tell,
    fs_file_truncate,
    fs_file_path,
    fs_dir_entries,
    fs_dir_walk,
    fs_dir_open,
    fs_dir_stat,
    fs_dir_mkdir,
    fs_dir_remove,
    fs_dir_close,
    fs_path_join,
    fs_path_normalize,
    fs_path_basename,
    fs_path_dirname,
    fs_path_extension,
    fs_path_stem,
    fs_path_is_absolute,
    fs_path_relative,
};
```

### Nested Declarations

| Name | Parameters | Return Type | Description |
| --- | --- | --- | --- |
| [name](#fn-nativefn-name) | `self: NativeFn` | `[]const u8` |  |

<a id="fn-nativefn-name"></a>

### NativeFn.name

```zig
pub fn name(self: NativeFn) []const u8
```

References: [`NativeFn`](#type-nativefn)

