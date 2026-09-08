const std = @import("std");
const compile = @import("compile.zig");
const runtime = @import("runtime.zig");

pub const base = @import("stdlib/base.zig");
pub const table = @import("stdlib/table.zig");
pub const string = @import("stdlib/string.zig");
pub const math = @import("stdlib/math.zig");
pub const utf8 = @import("stdlib/utf8.zig");
pub const coroutine = @import("stdlib/coroutine.zig");
pub const debug = @import("stdlib/debug.zig");
pub const package = @import("stdlib/package.zig");
pub const io = @import("stdlib/io.zig");
pub const os = @import("stdlib/os.zig");
pub const json = @import("stdlib/json.zig");
pub const toml = @import("stdlib/toml.zig");
pub const msgpack = @import("stdlib/msgpack.zig");
pub const csv = @import("stdlib/csv.zig");
pub const fs = @import("stdlib/fs.zig");
pub const static_strings = @import("stdlib/static_strings.zig");

const bytecode = compile.bytecode;
const State = runtime.State;
const Thread = runtime.Thread;
const Value = runtime.Value;
const TableEntry = @import("runtime/types.zig").TableEntry;

pub const LibrarySelection = union(enum) {
    none,
    base,
    safe,
    full,
    libraries: LibrarySet,

    pub fn toSet(self: LibrarySelection) LibrarySet {
        return switch (self) {
            .none => .{},
            .base => .{ .base = true },
            .safe => LibrarySet.safe(),
            .full => LibrarySet.full(),
            .libraries => |libraries| libraries,
        };
    }

    pub fn isEmpty(self: LibrarySelection) bool {
        return self.toSet().isEmpty();
    }
};

pub const LibrarySet = struct {
    base: bool = false,
    table: bool = false,
    string: bool = false,
    math: bool = false,
    utf8: bool = false,
    coroutine: bool = false,
    io: bool = false,
    os: bool = false,
    debug: bool = false,
    package: bool = false,
    json: bool = false,
    toml: bool = false,
    msgpack: bool = false,
    csv: bool = false,
    fs: bool = false,

    pub fn safe() LibrarySet {
        return .{
            .base = true,
            .table = true,
            .string = true,
            .math = true,
            .utf8 = true,
            .coroutine = true,
            .json = true,
            .toml = true,
            .msgpack = true,
            .csv = true,
        };
    }

    pub fn full() LibrarySet {
        var libraries = safe();
        libraries.io = true;
        libraries.os = true;
        libraries.debug = true;
        libraries.package = true;
        libraries.fs = true;
        return libraries;
    }

    pub fn isEmpty(self: LibrarySet) bool {
        return !self.base and !self.table and !self.string and !self.math and !self.utf8 and !self.coroutine and !self.io and !self.os and !self.debug and !self.package and !self.json and !self.toml and !self.msgpack and !self.csv and !self.fs;
    }
};

pub const InitHints = struct {
    globals: u32,
    strings: usize,
    tables: usize,
};

pub fn initHints(selection: LibrarySelection) InitHints {
    return initHintsWithStdin(selection, "");
}

pub fn initHintsWithStdin(selection: LibrarySelection, stdin: []const u8) InitHints {
    const libraries = selection.toSet();
    var globals: u32 = 1; // _G
    var strings: usize = 0;
    var tables: usize = 1; // _G

    if (libraries.base) globals += 22;
    if (libraries.table) {
        globals += 1;
        tables += 1;
    }
    if (libraries.string) {
        globals += 1;
        tables += 2;
    }
    if (libraries.math) {
        globals += 1;
        tables += 1;
    }
    if (libraries.utf8) {
        globals += 1;
        tables += 1;
    }
    if (libraries.coroutine) {
        globals += 1;
        tables += 1;
    }
    if (libraries.io) {
        globals += 1;
        strings += @intFromBool(stdin.len != 0 and static_strings.canonical(stdin) == null);
        tables += 5;
    }
    if (libraries.os) {
        globals += 1;
        tables += 1;
    }
    if (libraries.debug) {
        globals += 1;
        tables += 1;
    }
    if (libraries.json) {
        globals += 1;
        tables += 1;
    }
    if (libraries.toml) {
        globals += 1;
        tables += 1;
    }
    if (libraries.msgpack) {
        globals += 1;
        tables += 1;
    }
    if (libraries.csv) {
        globals += 1;
        tables += 1;
    }
    if (libraries.json or libraries.msgpack or libraries.csv) tables += 4;
    if (libraries.fs) {
        globals += 1;
        tables += 2;
    }
    if (libraries.package) {
        globals += 4;
        tables += 4;
    }
    return .{ .globals = globals, .strings = strings, .tables = tables };
}

const StaticField = struct {
    name: []const u8,
    value: Value,
};

fn newStaticTable(state: *State, comptime fields: []const StaticField, extra_fields: u32) !Value {
    const entries = comptime blk: {
        @setEvalBranchQuota(10000);
        var entries: [fields.len]TableEntry = undefined;
        for (fields, 0..) |field, index| {
            if (field.value == .nil) @compileError("static fields must be non-nil");
            for (fields[0..index]) |previous| {
                if (std.mem.eql(u8, field.name, previous.name)) @compileError("duplicate static field: " ++ field.name);
            }
            entries[index] = .{ .key = .{ .string = static_strings.get(field.name) }, .value = field.value };
        }
        break :blk entries;
    };
    const value = try state.newTableWithHints(0, @intCast(fields.len + @as(usize, extra_fields)));
    value.table.entries.appendSliceAssumeCapacity(&entries);
    if (value.table.entry_index.capacity() != 0) {
        for (entries, 0..) |entry, index| value.table.entry_index.putAssumeCapacityNoClobber(entry.key, index);
    }
    return value;
}

fn setStaticField(state: *State, table_value: Value, comptime name: []const u8, value: Value) !void {
    try state.setTableRaw(table_value.table, .{ .string = static_strings.get(name) }, value);
}

fn putStaticGlobal(state: *State, comptime name: []const u8, value: Value) !void {
    try state.putGlobal(static_strings.get(name), value);
}

pub fn openLibraries(state: *State, selection: LibrarySelection) !void {
    if (state.global_table == null) try installGlobalTable(state);
    const libraries = selection.toSet();
    if (libraries.base) try openBase(state);
    if (libraries.table) try openTable(state);
    if (libraries.string) try openString(state);
    if (libraries.math) try openMath(state);
    if (libraries.utf8) try openUtf8(state);
    if (libraries.coroutine) try openCoroutine(state);
    if (libraries.io) try openIo(state);
    if (libraries.os) try openOs(state);
    if (libraries.debug) try openDebug(state);
    if (libraries.json) try openJson(state);
    if (libraries.toml) try openToml(state);
    if (libraries.msgpack) try openMsgpack(state);
    if (libraries.csv) try openCsv(state);
    if (libraries.fs) try openFs(state);
    if (libraries.package) try openPackage(state, libraries);
}

pub fn installGlobalTable(state: *State) !void {
    return installGlobalTableWithHint(state, 1);
}

pub fn installGlobalTableWithHint(state: *State, hash_hint: u32) !void {
    const global_table = state.global_table orelse blk: {
        const global = try state.newTableWithHints(0, @max(hash_hint, 1));
        state.global_table = global.table;
        break :blk global.table;
    };
    const key = static_strings.get("_G");
    try state.setTableRaw(global_table, .{ .string = key }, .{ .table = global_table });
}

fn openBase(state: *State) !void {
    const global_table = state.global_table orelse return error.RuntimeError;
    try putStaticGlobal(state, "_G", .{ .table = global_table });
    const fields = comptime [_]StaticField{
        .{ .name = "print", .value = .native_print },
        .{ .name = "tostring", .value = .native_tostring },
        .{ .name = "getmetatable", .value = .native_getmetatable },
        .{ .name = "setmetatable", .value = .native_setmetatable },
        .{ .name = "rawequal", .value = .native_rawequal },
        .{ .name = "rawget", .value = .native_rawget },
        .{ .name = "rawset", .value = .native_rawset },
        .{ .name = "rawlen", .value = .native_rawlen },
        .{ .name = "next", .value = .native_next },
        .{ .name = "pairs", .value = .native_pairs },
        .{ .name = "ipairs", .value = .native_ipairs },
        .{ .name = "select", .value = .native_select },
        .{ .name = "assert", .value = .native_assert },
        .{ .name = "error", .value = .native_error },
        .{ .name = "pcall", .value = .native_pcall },
        .{ .name = "xpcall", .value = .native_xpcall },
        .{ .name = "collectgarbage", .value = .native_collectgarbage },
        .{ .name = "load", .value = .{ .native = .load } },
        .{ .name = "type", .value = .{ .native = .type } },
        .{ .name = "tonumber", .value = .{ .native = .tonumber } },
        .{ .name = "warn", .value = .{ .native = .warn } },
        .{ .name = "_VERSION", .value = .{ .string = static_strings.get("Lua 5.5") } },
    };
    inline for (fields) |field| try putStaticGlobal(state, field.name, field.value);
}

fn openTable(state: *State) !void {
    const fields = comptime [_]StaticField{
        .{ .name = "concat", .value = .{ .native = .table_concat } },
        .{ .name = "dedup", .value = .{ .native = .table_dedup } },
        .{ .name = "insert", .value = .{ .native = .table_insert } },
        .{ .name = "move", .value = .{ .native = .table_move } },
        .{ .name = "pack", .value = .{ .native = .table_pack } },
        .{ .name = "remove", .value = .{ .native = .table_remove } },
        .{ .name = "sort", .value = .{ .native = .table_sort } },
        .{ .name = "unpack", .value = .{ .native = .table_unpack } },
        .{ .name = "create", .value = .native_table_create },
    };
    try putStaticGlobal(state, "table", try newStaticTable(state, &fields, 0));
}

fn openString(state: *State) !void {
    const fields = comptime [_]StaticField{
        .{ .name = "byte", .value = .{ .native = .string_byte } },
        .{ .name = "char", .value = .{ .native = .string_char } },
        .{ .name = "dump", .value = .{ .native = .string_dump } },
        .{ .name = "find", .value = .{ .native = .string_find } },
        .{ .name = "format", .value = .{ .native = .string_format } },
        .{ .name = "gmatch", .value = .{ .native = .string_gmatch } },
        .{ .name = "gsub", .value = .{ .native = .string_gsub } },
        .{ .name = "len", .value = .{ .native = .string_len } },
        .{ .name = "lower", .value = .{ .native = .string_lower } },
        .{ .name = "match", .value = .{ .native = .string_match } },
        .{ .name = "pack", .value = .{ .native = .string_pack } },
        .{ .name = "packsize", .value = .{ .native = .string_packsize } },
        .{ .name = "rep", .value = .{ .native = .string_rep } },
        .{ .name = "reverse", .value = .{ .native = .string_reverse } },
        .{ .name = "rsplit", .value = .{ .native = .string_rsplit } },
        .{ .name = "split", .value = .{ .native = .string_split } },
        .{ .name = "strip", .value = .{ .native = .string_strip } },
        .{ .name = "sub", .value = .{ .native = .string_sub } },
        .{ .name = "unpack", .value = .{ .native = .string_unpack } },
        .{ .name = "upper", .value = .{ .native = .string_upper } },
    };
    const string_lib = try newStaticTable(state, &fields, 0);
    try putStaticGlobal(state, "string", string_lib);

    const string_metatable = try state.newTableWithHints(0, 1);
    try setStaticField(state, string_metatable, "__index", string_lib);
    state.string_metatable = string_metatable.table;
}

fn openMath(state: *State) !void {
    const fields = comptime [_]StaticField{
        .{ .name = "abs", .value = .{ .native = .math_abs } },
        .{ .name = "acos", .value = .{ .native = .math_acos } },
        .{ .name = "asin", .value = .{ .native = .math_asin } },
        .{ .name = "atan", .value = .{ .native = .math_atan } },
        .{ .name = "ceil", .value = .{ .native = .math_ceil } },
        .{ .name = "cos", .value = .{ .native = .math_cos } },
        .{ .name = "deg", .value = .{ .native = .math_deg } },
        .{ .name = "exp", .value = .{ .native = .math_exp } },
        .{ .name = "floor", .value = .{ .native = .math_floor } },
        .{ .name = "fmod", .value = .{ .native = .math_fmod } },
        .{ .name = "frexp", .value = .{ .native = .math_frexp } },
        .{ .name = "huge", .value = .{ .number = std.math.inf(f64) } },
        .{ .name = "ldexp", .value = .{ .native = .math_ldexp } },
        .{ .name = "log", .value = .{ .native = .math_log } },
        .{ .name = "maxinteger", .value = .{ .integer = std.math.maxInt(i64) } },
        .{ .name = "max", .value = .{ .native = .math_max } },
        .{ .name = "mininteger", .value = .{ .integer = std.math.minInt(i64) } },
        .{ .name = "min", .value = .{ .native = .math_min } },
        .{ .name = "modf", .value = .{ .native = .math_modf } },
        .{ .name = "pi", .value = .{ .number = std.math.pi } },
        .{ .name = "rad", .value = .{ .native = .math_rad } },
        .{ .name = "random", .value = .{ .native = .math_random } },
        .{ .name = "randomseed", .value = .{ .native = .math_randomseed } },
        .{ .name = "sin", .value = .{ .native = .math_sin } },
        .{ .name = "sqrt", .value = .{ .native = .math_sqrt } },
        .{ .name = "tan", .value = .{ .native = .math_tan } },
        .{ .name = "tointeger", .value = .{ .native = .math_tointeger } },
        .{ .name = "type", .value = .{ .native = .math_type } },
        .{ .name = "ult", .value = .{ .native = .math_ult } },
    };
    try putStaticGlobal(state, "math", try newStaticTable(state, &fields, 0));
}

fn openUtf8(state: *State) !void {
    const fields = comptime [_]StaticField{
        .{ .name = "char", .value = .{ .native = .utf8_char } },
        .{ .name = "charpattern", .value = .{ .string = static_strings.get("[\x00-\x7F\xC2-\xFD][\x80-\xBF]*") } },
        .{ .name = "codepoint", .value = .{ .native = .utf8_codepoint } },
        .{ .name = "codes", .value = .{ .native = .utf8_codes } },
        .{ .name = "len", .value = .{ .native = .utf8_len } },
        .{ .name = "offset", .value = .{ .native = .utf8_offset } },
    };
    try putStaticGlobal(state, "utf8", try newStaticTable(state, &fields, 0));
}

fn openCoroutine(state: *State) !void {
    const fields = comptime [_]StaticField{
        .{ .name = "create", .value = .native_coroutine_create },
        .{ .name = "resume", .value = .native_coroutine_resume },
        .{ .name = "yield", .value = .native_coroutine_yield },
        .{ .name = "status", .value = .native_coroutine_status },
        .{ .name = "running", .value = .native_coroutine_running },
        .{ .name = "isyieldable", .value = .native_coroutine_isyieldable },
        .{ .name = "close", .value = .native_coroutine_close },
        .{ .name = "wrap", .value = .native_coroutine_wrap },
    };
    try putStaticGlobal(state, "coroutine", try newStaticTable(state, &fields, 0));
}

fn openIo(state: *State) !void {
    const fields = comptime [_]StaticField{
        .{ .name = "read", .value = .{ .native = .io_read } },
        .{ .name = "write", .value = .{ .native = .io_write } },
        .{ .name = "open", .value = .{ .native = .io_open } },
        .{ .name = "input", .value = .{ .native = .io_input } },
        .{ .name = "output", .value = .{ .native = .io_output } },
        .{ .name = "close", .value = .{ .native = .io_close } },
        .{ .name = "flush", .value = .{ .native = .io_flush } },
        .{ .name = "lines", .value = .{ .native = .io_lines } },
        .{ .name = "tmpfile", .value = .{ .native = .io_tmpfile } },
        .{ .name = "type", .value = .{ .native = .io_type } },
    };
    const io_lib = try newStaticTable(state, &fields, 5);
    const stdin = try newStandardFile(state, static_strings.get("stdin"), static_strings.get("r"));
    const stdout = try newStandardFile(state, static_strings.get("stdout"), static_strings.get("w"));
    const stderr = try newStandardFile(state, static_strings.get("stderr"), static_strings.get("w"));
    try setStaticField(state, io_lib, "stdin", stdin);
    try setStaticField(state, io_lib, "stdout", stdout);
    try setStaticField(state, io_lib, "stderr", stderr);
    try setStaticField(state, io_lib, "__zlua_input", stdin);
    try setStaticField(state, io_lib, "__zlua_output", stdout);
    try putStaticGlobal(state, "io", io_lib);
}

fn openOs(state: *State) !void {
    const fields = comptime [_]StaticField{
        .{ .name = "time", .value = .{ .native = .os_time } },
        .{ .name = "clock", .value = .{ .native = .os_clock } },
        .{ .name = "date", .value = .{ .native = .os_date } },
        .{ .name = "getenv", .value = .{ .native = .os_getenv } },
        .{ .name = "setlocale", .value = .{ .native = .os_setlocale } },
        .{ .name = "execute", .value = .{ .native = .os_execute } },
        .{ .name = "remove", .value = .{ .native = .os_remove } },
        .{ .name = "rename", .value = .{ .native = .os_rename } },
        .{ .name = "tmpname", .value = .{ .native = .os_tmpname } },
        .{ .name = "difftime", .value = .{ .native = .os_difftime } },
    };
    try putStaticGlobal(state, "os", try newStaticTable(state, &fields, 0));
}

fn openDebug(state: *State) !void {
    const fields = comptime [_]StaticField{
        .{ .name = "traceback", .value = .native_debug_traceback },
        .{ .name = "getinfo", .value = .{ .native = .debug_getinfo } },
        .{ .name = "getupvalue", .value = .{ .native = .debug_getupvalue } },
        .{ .name = "setupvalue", .value = .{ .native = .debug_setupvalue } },
        .{ .name = "upvalueid", .value = .{ .native = .debug_upvalueid } },
        .{ .name = "upvaluejoin", .value = .{ .native = .debug_upvaluejoin } },
        .{ .name = "getlocal", .value = .{ .native = .debug_getlocal } },
        .{ .name = "setlocal", .value = .{ .native = .debug_setlocal } },
        .{ .name = "getregistry", .value = .{ .native = .debug_getregistry } },
        .{ .name = "sethook", .value = .{ .native = .debug_sethook } },
        .{ .name = "gethook", .value = .{ .native = .debug_gethook } },
        .{ .name = "setmetatable", .value = .{ .native = .debug_setmetatable } },
        .{ .name = "setuservalue", .value = .{ .native = .debug_setuservalue } },
        .{ .name = "getuservalue", .value = .{ .native = .debug_getuservalue } },
    };
    try putStaticGlobal(state, "debug", try newStaticTable(state, &fields, 0));
}

fn openJson(state: *State) !void {
    const fields = comptime [_]StaticField{
        .{ .name = "read", .value = .{ .native = .json_read } },
        .{ .name = "write", .value = .{ .native = .json_write } },
    };
    const json_lib = try newStaticTable(state, &fields, 1);
    try setStaticField(state, json_lib, "null", try json.nullValue(state));
    try putStaticGlobal(state, "json", json_lib);
}

fn openToml(state: *State) !void {
    const fields = comptime [_]StaticField{
        .{ .name = "read", .value = .{ .native = .toml_read } },
        .{ .name = "write", .value = .{ .native = .toml_write } },
    };
    try putStaticGlobal(state, "toml", try newStaticTable(state, &fields, 0));
}

fn openMsgpack(state: *State) !void {
    const fields = comptime [_]StaticField{
        .{ .name = "read", .value = .{ .native = .msgpack_read } },
        .{ .name = "write", .value = .{ .native = .msgpack_write } },
    };
    const msgpack_lib = try newStaticTable(state, &fields, 1);
    try setStaticField(state, msgpack_lib, "null", try msgpack.nullValue(state));
    try putStaticGlobal(state, "msgpack", msgpack_lib);
}

fn openCsv(state: *State) !void {
    const fields = comptime [_]StaticField{
        .{ .name = "read", .value = .{ .native = .csv_read } },
        .{ .name = "write", .value = .{ .native = .csv_write } },
    };
    const csv_lib = try newStaticTable(state, &fields, 1);
    try setStaticField(state, csv_lib, "null", try csv.nullValue(state));
    try putStaticGlobal(state, "csv", csv_lib);
}

fn openFs(state: *State) !void {
    const fields = comptime [_]StaticField{
        .{ .name = "read", .value = .{ .native = .fs_read } },
        .{ .name = "write", .value = .{ .native = .fs_write } },
        .{ .name = "open", .value = .{ .native = .fs_open } },
        .{ .name = "stat", .value = .{ .native = .fs_stat } },
        .{ .name = "exists", .value = .{ .native = .fs_exists } },
        .{ .name = "list", .value = .{ .native = .fs_list } },
        .{ .name = "scandir", .value = .{ .native = .fs_scandir } },
        .{ .name = "walk", .value = .{ .native = .fs_walk } },
        .{ .name = "mkdir", .value = .{ .native = .fs_mkdir } },
        .{ .name = "remove", .value = .{ .native = .fs_remove } },
        .{ .name = "copy", .value = .{ .native = .fs_copy } },
        .{ .name = "rename", .value = .{ .native = .fs_rename } },
        .{ .name = "move", .value = .{ .native = .fs_move } },
        .{ .name = "touch", .value = .{ .native = .fs_touch } },
        .{ .name = "open_dir", .value = .{ .native = .fs_open_dir } },
    };
    const fs_lib = try newStaticTable(state, &fields, 1);

    const path_fields = comptime [_]StaticField{
        .{ .name = "join", .value = .{ .native = .fs_path_join } },
        .{ .name = "normalize", .value = .{ .native = .fs_path_normalize } },
        .{ .name = "basename", .value = .{ .native = .fs_path_basename } },
        .{ .name = "dirname", .value = .{ .native = .fs_path_dirname } },
        .{ .name = "extension", .value = .{ .native = .fs_path_extension } },
        .{ .name = "stem", .value = .{ .native = .fs_path_stem } },
        .{ .name = "is_absolute", .value = .{ .native = .fs_path_is_absolute } },
        .{ .name = "relative", .value = .{ .native = .fs_path_relative } },
        .{ .name = "separator", .value = .{ .string = static_strings.get(&.{std.fs.path.sep}) } },
    };
    const path_lib = try newStaticTable(state, &path_fields, 0);
    try setStaticField(state, fs_lib, "path", path_lib);
    try putStaticGlobal(state, "fs", fs_lib);
}

fn openPackage(state: *State, libraries: LibrarySet) !void {
    try putStaticGlobal(state, "loadfile", .{ .native = .loadfile });
    try putStaticGlobal(state, "dofile", .{ .native = .dofile });
    try putStaticGlobal(state, "require", .{ .native = .require });

    const loaded_count: u32 = 1 + @as(u32, @intFromBool(libraries.coroutine)) + @as(u32, @intFromBool(libraries.debug)) +
        @as(u32, @intFromBool(libraries.io)) + @as(u32, @intFromBool(libraries.math)) + @as(u32, @intFromBool(libraries.os)) +
        @as(u32, @intFromBool(libraries.string)) + @as(u32, @intFromBool(libraries.table)) + @as(u32, @intFromBool(libraries.utf8)) +
        @as(u32, @intFromBool(libraries.json)) + @as(u32, @intFromBool(libraries.toml)) + @as(u32, @intFromBool(libraries.msgpack)) +
        @as(u32, @intFromBool(libraries.csv)) + @as(u32, @intFromBool(libraries.fs));
    const package_lib = try state.newTableWithHints(0, 7);
    const loaded = try state.newTableWithHints(0, loaded_count);
    const preload = try state.newTableWithHints(0, 4);
    const searchers = try state.newTableWithHints(2, 0);
    try state.setTableRaw(searchers.table, .{ .integer = 1 }, .{ .native = .package_searcher_preload });
    try state.setTableRaw(searchers.table, .{ .integer = 2 }, .{ .native = .package_searcher_lua });
    if (libraries.coroutine) try setStaticField(state, loaded, "coroutine", state.getGlobal("coroutine"));
    if (libraries.debug) try setStaticField(state, loaded, "debug", state.getGlobal("debug"));
    if (libraries.io) try setStaticField(state, loaded, "io", state.getGlobal("io"));
    if (libraries.math) try setStaticField(state, loaded, "math", state.getGlobal("math"));
    if (libraries.os) try setStaticField(state, loaded, "os", state.getGlobal("os"));
    if (libraries.string) try setStaticField(state, loaded, "string", state.getGlobal("string"));
    if (libraries.table) try setStaticField(state, loaded, "table", state.getGlobal("table"));
    if (libraries.utf8) try setStaticField(state, loaded, "utf8", state.getGlobal("utf8"));
    if (libraries.json) try setStaticField(state, loaded, "json", state.getGlobal("json"));
    if (libraries.toml) try setStaticField(state, loaded, "toml", state.getGlobal("toml"));
    if (libraries.msgpack) try setStaticField(state, loaded, "msgpack", state.getGlobal("msgpack"));
    if (libraries.csv) try setStaticField(state, loaded, "csv", state.getGlobal("csv"));
    if (libraries.fs) try setStaticField(state, loaded, "fs", state.getGlobal("fs"));
    try setStaticField(state, loaded, "package", package_lib);
    try setStaticField(state, package_lib, "loaded", loaded);
    try setStaticField(state, package_lib, "preload", preload);
    try setStaticField(state, package_lib, "searchers", searchers);
    try setStaticField(state, package_lib, "searchpath", .{ .native = .package_searchpath });
    try setStaticField(state, package_lib, "path", .{ .string = static_strings.get("./?.lua;./?/init.lua") });
    try setStaticField(state, package_lib, "cpath", .{ .string = static_strings.get("") });
    try setStaticField(state, package_lib, "config", .{ .string = static_strings.get("/\n;\n?\n!\n-\n") });
    try putStaticGlobal(state, "package", package_lib);
}

fn newStandardFile(state: *State, path: []const u8, mode: []const u8) !Value {
    const value = try state.newTableWithHints(0, 8);
    const file = value.table;
    try setStaticField(state, value, "__zlua_file", .{ .boolean = true });
    try setStaticField(state, value, "__zlua_file_path", .{ .string = path });
    try setStaticField(state, value, "__zlua_file_mode", .{ .string = mode });
    const contents = if (!std.mem.eql(u8, path, "stdin") or state.options.stdin.len == 0)
        static_strings.get("")
    else
        try state.intern(state.options.stdin);
    try setStaticField(state, value, "__zlua_file_content", .{ .string = contents });
    try setStaticField(state, value, "__zlua_file_pos", .{ .integer = 1 });
    try setStaticField(state, value, "__zlua_file_closed", .{ .boolean = false });
    try setStaticField(state, value, "__zlua_file_standard", .{ .boolean = true });
    try setStaticField(state, value, "__zlua_file_buffer_mode", .{ .string = static_strings.get("full") });
    state.setTableMetatableRaw(file, try state.fileMetatable());
    return value;
}

pub const NativeFn = runtime.NativeFn;

pub fn callNative(state: *State, native: NativeFn, thread: *Thread, op: bytecode.Call) !void {
    switch (native) {
        .load => try base.load(state, thread, op),
        .type => try base.typeValue(state, thread, op),
        .tonumber => try base.tonumber(state, thread, op),
        .warn => try base.warn(state, thread, op),
        .table_concat => try table.concat(state, thread, op),
        .table_dedup => try table.dedup(state, thread, op),
        .table_insert => try table.insert(state, thread, op),
        .table_move => try table.move(state, thread, op),
        .table_pack => try table.pack(state, thread, op),
        .table_remove => try table.remove(state, thread, op),
        .table_sort => try table.sort(state, thread, op),
        .table_unpack => try table.unpack(state, thread, op),
        .string_byte => try string.byte(state, thread, op),
        .string_char => try string.char(state, thread, op),
        .string_dump => try string.dump(state, thread, op),
        .string_find => try string.find(state, thread, op),
        .string_format => try string.format(state, thread, op),
        .string_gmatch => try string.gmatch(state, thread, op),
        .string_gmatch_iter => try string.gmatchIter(state, thread, op),
        .string_gsub => try string.gsub(state, thread, op),
        .string_len => try string.len(state, thread, op),
        .string_lower => try string.lower(state, thread, op),
        .string_match => try string.match(state, thread, op),
        .string_pack => try string.pack(state, thread, op),
        .string_packsize => try string.packsize(state, thread, op),
        .string_rep => try string.rep(state, thread, op),
        .string_reverse => try string.reverse(state, thread, op),
        .string_rsplit => try string.rsplit(state, thread, op),
        .string_split => try string.split(state, thread, op),
        .string_strip => try string.strip(state, thread, op),
        .string_sub => try string.sub(state, thread, op),
        .string_unpack => try string.unpack(state, thread, op),
        .string_upper => try string.upper(state, thread, op),
        .math_abs => try math.abs(state, thread, op),
        .math_acos => try math.acos(state, thread, op),
        .math_asin => try math.asin(state, thread, op),
        .math_atan => try math.atan(state, thread, op),
        .math_ceil => try math.ceil(state, thread, op),
        .math_cos => try math.cos(state, thread, op),
        .math_deg => try math.deg(state, thread, op),
        .math_exp => try math.exp(state, thread, op),
        .math_floor => try math.floor(state, thread, op),
        .math_fmod => try math.fmod(state, thread, op),
        .math_frexp => try math.frexp(state, thread, op),
        .math_ldexp => try math.ldexp(state, thread, op),
        .math_log => try math.log(state, thread, op),
        .math_max => try math.max(state, thread, op),
        .math_min => try math.min(state, thread, op),
        .math_modf => try math.modf(state, thread, op),
        .math_rad => try math.rad(state, thread, op),
        .math_random => try math.random(state, thread, op),
        .math_randomseed => try math.randomseed(state, thread, op),
        .math_sin => try math.sin(state, thread, op),
        .math_sqrt => try math.sqrt(state, thread, op),
        .math_tan => try math.tan(state, thread, op),
        .math_tointeger => try math.tointeger(state, thread, op),
        .math_type => try math.typeValue(state, thread, op),
        .math_ult => try math.ult(state, thread, op),
        .utf8_char => try utf8.char(state, thread, op),
        .utf8_codepoint => try utf8.codepoint(state, thread, op),
        .utf8_codes => try utf8.codes(state, thread, op),
        .utf8_codes_iter => try utf8.codesIter(state, thread, op),
        .utf8_len => try utf8.len(state, thread, op),
        .utf8_offset => try utf8.offset(state, thread, op),
        .loadfile => try package.loadfile(state, thread, op),
        .dofile => try package.dofile(state, thread, op),
        .require => try package.require(state, thread, op),
        .package_searchpath => try package.searchpath(state, thread, op),
        .package_searcher_preload => try package.searcherPreload(state, thread, op),
        .package_searcher_lua => try package.searcherLua(state, thread, op),
        .io_read => try io.read(state, thread, op),
        .io_write => try io.write(state, thread, op),
        .io_open => try io.open(state, thread, op),
        .io_input => try io.input(state, thread, op),
        .io_output => try io.output(state, thread, op),
        .io_close => try io.close(state, thread, op),
        .io_flush => try io.flush(state, thread, op),
        .io_lines => try io.lines(state, thread, op),
        .io_tmpfile => try io.tmpfile(state, thread, op),
        .io_type => try io.typeValue(state, thread, op),
        .io_file_read => try io.fileRead(state, thread, op),
        .io_file_write => try io.fileWrite(state, thread, op),
        .io_file_close => try io.fileClose(state, thread, op),
        .io_file_seek => try io.fileSeek(state, thread, op),
        .io_file_flush => try io.fileFlush(state, thread, op),
        .io_file_lines => try io.fileLines(state, thread, op),
        .io_file_setvbuf => try io.fileSetvbuf(state, thread, op),
        .io_lines_iter => try io.linesIter(state, thread, op),
        .os_time => try os.time(state, thread, op),
        .os_clock => try os.clock(state, thread, op),
        .os_date => try os.date(state, thread, op),
        .os_getenv => try os.getenv(state, thread, op),
        .os_setlocale => try os.setlocale(state, thread, op),
        .os_execute => try os.execute(state, thread, op),
        .os_remove => try os.remove(state, thread, op),
        .os_rename => try os.rename(state, thread, op),
        .os_tmpname => try os.tmpname(state, thread, op),
        .os_difftime => try os.difftime(state, thread, op),
        .debug_getinfo => try debug.getinfo(state, thread, op),
        .debug_getupvalue => try debug.getupvalue(state, thread, op),
        .debug_setupvalue => try debug.setupvalue(state, thread, op),
        .debug_upvalueid => try debug.upvalueid(state, thread, op),
        .debug_upvaluejoin => try debug.upvaluejoin(state, thread, op),
        .debug_getlocal => try debug.getlocal(state, thread, op),
        .debug_setlocal => try debug.setlocal(state, thread, op),
        .debug_getregistry => try debug.getregistry(state, thread, op),
        .debug_sethook => try debug.sethook(state, thread, op),
        .debug_gethook => try debug.gethook(state, thread, op),
        .debug_setmetatable => try debug.setmetatable(state, thread, op),
        .debug_setuservalue => try debug.setuservalue(state, thread, op),
        .debug_getuservalue => try debug.getuservalue(state, thread, op),
        .json_read => try json.read(state, thread, op),
        .json_write => try json.write(state, thread, op),
        .toml_read => try toml.read(state, thread, op),
        .toml_write => try toml.write(state, thread, op),
        .msgpack_read => try msgpack.read(state, thread, op),
        .msgpack_write => try msgpack.write(state, thread, op),
        .csv_read => try csv.read(state, thread, op),
        .csv_write => try csv.write(state, thread, op),
        .fs_read => try fs.read(state, thread, op),
        .fs_write => try fs.write(state, thread, op),
        .fs_open => try fs.open(state, thread, op),
        .fs_stat => try fs.stat(state, thread, op),
        .fs_exists => try fs.exists(state, thread, op),
        .fs_list => try fs.list(state, thread, op),
        .fs_scandir => try fs.scandir(state, thread, op),
        .fs_walk => try fs.walk(state, thread, op),
        .fs_mkdir => try fs.mkdir(state, thread, op),
        .fs_remove => try fs.remove(state, thread, op),
        .fs_copy => try fs.copy(state, thread, op),
        .fs_rename => try fs.rename(state, thread, op),
        .fs_move => try fs.move(state, thread, op),
        .fs_touch => try fs.touch(state, thread, op),
        .fs_open_dir => try fs.openDir(state, thread, op),
        .fs_iterator_next => try fs.iteratorNextNative(state, thread, op),
        .fs_iterator_close => try fs.iteratorClose(state, thread, op),
        .fs_iterator_skip => try fs.iteratorSkip(state, thread, op),
        .fs_error_tostring => try fs.errorTostring(state, thread, op),
        .fs_file_stat => try fs.fileStat(state, thread, op),
        .fs_file_tell => try fs.fileTell(state, thread, op),
        .fs_file_truncate => try fs.fileTruncate(state, thread, op),
        .fs_file_path => try fs.filePath(state, thread, op),
        .fs_dir_entries => try fs.dirEntries(state, thread, op),
        .fs_dir_walk => try fs.dirWalk(state, thread, op),
        .fs_dir_open => try fs.dirOpen(state, thread, op),
        .fs_dir_stat => try fs.dirStat(state, thread, op),
        .fs_dir_mkdir => try fs.dirMkdir(state, thread, op),
        .fs_dir_remove => try fs.dirRemove(state, thread, op),
        .fs_dir_close => try fs.dirClose(state, thread, op),
        .fs_path_join => try fs.pathJoin(state, thread, op),
        .fs_path_normalize => try fs.pathNormalize(state, thread, op),
        .fs_path_basename => try fs.pathBasename(state, thread, op),
        .fs_path_dirname => try fs.pathDirname(state, thread, op),
        .fs_path_extension => try fs.pathExtension(state, thread, op),
        .fs_path_stem => try fs.pathStem(state, thread, op),
        .fs_path_is_absolute => try fs.pathIsAbsolute(state, thread, op),
        .fs_path_relative => try fs.pathRelative(state, thread, op),
    }
}

test "startup uses canonical globals, static strings, and exact table hints" {
    inline for (.{ LibrarySelection.none, LibrarySelection.base, LibrarySelection.safe, LibrarySelection.full }) |selection| {
        var state = try State.initWithOptions(std.testing.allocator, .{ .stdlib = selection });
        defer state.deinit();

        try std.testing.expectEqual(initHints(selection).tables, state.table_allocations.items.len);
        try std.testing.expectEqual(@as(usize, 0), state.string_allocations.items.len);
        try std.testing.expect(state.getGlobal("_G").table == state.global_table.?);
    }
}

test "startup plans the non-static stdin string" {
    const selection: LibrarySelection = .{ .libraries = .{ .io = true } };
    const stdin = "dynamic stdin contents";
    var state = try State.initWithOptions(std.testing.allocator, .{ .stdlib = selection, .stdin = stdin });
    defer state.deinit();

    const hints = initHintsWithStdin(selection, stdin);
    try std.testing.expectEqual(@as(usize, 1), hints.strings);
    try std.testing.expectEqual(hints.strings, state.string_allocations.items.len);
    try std.testing.expectEqual(hints.tables, state.table_allocations.items.len);
}

test "IO files share one method metatable" {
    var state = try State.initWithOptions(std.testing.allocator, .{ .stdlib = .{ .libraries = .{ .io = true } } });
    defer state.deinit();

    const io_table = state.getGlobal("io").table;
    const stdin = io_table.get(.{ .string = static_strings.get("stdin") }).table;
    const stdout = io_table.get(.{ .string = static_strings.get("stdout") }).table;
    const stderr = io_table.get(.{ .string = static_strings.get("stderr") }).table;
    try std.testing.expect(stdin.metatable == stdout.metatable);
    try std.testing.expect(stdin.metatable == stderr.metatable);
    try std.testing.expect(stdin.get(.{ .string = static_strings.get("read") }) == .nil);
    try std.testing.expect(stdin.metatable.?.get(.{ .string = static_strings.get("read") }) == .native);
}

test {
    _ = base;
    _ = table;
    _ = string;
    _ = math;
    _ = utf8;
    _ = coroutine;
    _ = debug;
    _ = package;
    _ = io;
    _ = os;
    _ = json;
    _ = toml;
    _ = msgpack;
    _ = csv;
    _ = fs;
}

test "bulk library tables retain ordinary lookup, iteration, and mutation" {
    var state = try State.initWithOptions(std.testing.allocator, .{ .stdlib = .full });
    defer state.deinit();
    try state.executeSourceChunk(
        \\assert(math.abs(-3) == 3 and math.pi > 3)
        \\assert(string.upper('abc') == 'ABC' and ('abc'):upper() == 'ABC')
        \\assert(utf8.charpattern ~= nil and fs.path.separator ~= nil)
        \\local count = 0
        \\for k, v in pairs(math) do
        \\  assert(rawget(math, k) == v)
        \\  count = count + 1
        \\end
        \\assert(count == 29)
        \\local m = math
        \\math.abs = nil
        \\math.pi = 7
        \\math.extra = 42
        \\math[1] = 'array'
        \\assert(m.abs == nil and m.pi == 7 and m.extra == 42 and #m == 1)
        \\assert(package.loaded.math == m)
        \\collectgarbage()
        \\assert(m.extra == 42 and m[1] == 'array')
    );
    try openLibraries(&state, .{ .libraries = .{ .math = true } });
    try state.executeSourceChunk("assert(math.abs(-3) == 3 and math.extra == nil and math.pi > 3)");
}

test "library initialization releases allocations on failure" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, struct {
        fn check(allocator: std.mem.Allocator) !void {
            var state = try State.initWithOptions(allocator, .{ .stdlib = .full });
            defer state.deinit();
        }
    }.check, .{});
}
