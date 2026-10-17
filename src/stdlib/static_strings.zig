const std = @import("std");
const value_mod = @import("../runtime/value.zig");

// Canonical static names, so states don't allocate and GC-track their own copies.
pub const names = [_][]const u8{
    "",
    "/",
    "\\",
    "r",
    "w",
    "_G",
    "fs",
    "io",
    "os",
    "pi",
    "abs",
    "cos",
    "csv",
    "deg",
    "exp",
    "len",
    "log",
    "max",
    "min",
    "rad",
    "rep",
    "sin",
    "sub",
    "tan",
    "ult",
    "__gc",
    "acos",
    "asin",
    "atan",
    "byte",
    "ceil",
    "char",
    "copy",
    "date",
    "dump",
    "find",
    "fmod",
    "full",
    "gsub",
    "huge",
    "join",
    "json",
    "list",
    "load",
    "math",
    "modf",
    "move",
    "next",
    "null",
    "open",
    "pack",
    "path",
    "read",
    "seek",
    "sort",
    "sqrt",
    "stat",
    "stem",
    "exit",
    "time",
    "toml",
    "type",
    "utf8",
    "walk",
    "warn",
    "wrap",
    "FILE*",
    "clock",
    "close",
    "codes",
    "cpath",
    "debug",
    "dedup",
    "error",
    "popen",
    "floor",
    "flush",
    "frexp",
    "input",
    "ldexp",
    "lines",
    "lower",
    "match",
    "mkdir",
    "pairs",
    "pcall",
    "print",
    "split",
    "stdin",
    "strip",
    "table",
    "touch",
    "upper",
    "write",
    "yield",
    "__name",
    "assert",
    "concat",
    "config",
    "create",
    "dofile",
    "exists",
    "format",
    "getenv",
    "gmatch",
    "insert",
    "ipairs",
    "loaded",
    "offset",
    "output",
    "random",
    "rawget",
    "rawlen",
    "rawset",
    "remove",
    "rename",
    "resume",
    "rsplit",
    "select",
    "status",
    "stderr",
    "stdout",
    "string",
    "unpack",
    "xpcall",
    "Lua 5.5",
    "__close",
    "__index",
    "__metatable",
    "dirname",
    "execute",
    "loadlib",
    "gethook",
    "getinfo",
    "msgpack",
    "package",
    "preload",
    "require",
    "reverse",
    "running",
    "scandir",
    "sethook",
    "setvbuf",
    "tmpfile",
    "tmpname",
    "_VERSION",
    "basename",
    "difftime",
    "getlocal",
    "loadfile",
    "open_dir",
    "packsize",
    "rawequal",
    "relative",
    "setlocal",
    "tonumber",
    "tostring",
    "codepoint",
    "coroutine",
    "extension",
    "normalize",
    "searchers",
    "separator",
    "setlocale",
    "tointeger",
    "traceback",
    "upvalueid",
    "/\n;\n?\n!\n-\n",
    "__tostring",
    "getupvalue",
    "maxinteger",
    "mininteger",
    "randomseed",
    "searchpath",
    "setupvalue",
    "zerde null",
    "charpattern",
    "getregistry",
    "is_absolute",
    "isyieldable",
    "upvaluejoin",
    "zerde array",
    "getmetatable",
    "getuservalue",
    "setmetatable",
    "setuservalue",
    "zerde object",
    "[\x00-\x7F\xC2-\xFD][\x80-\xBF]*",
    "collectgarbage",
    "./?.lua;./?/init.lua",
};

const StaticMap = std.StaticStringMap(usize);
const canonical_map: StaticMap = blk: {
    var entries: [names.len]struct { []const u8, usize } = undefined;
    for (names, 0..) |name, index| entries[index] = .{ name, index };
    break :blk StaticMap.initComptime(entries);
};

pub fn canonical(bytes: []const u8) ?[]const u8 {
    const index = canonical_map.get(bytes) orelse return null;
    return names[index];
}

const hashed_mask = std.math.ceilPowerOfTwoAssert(usize, names.len * 2) - 1;
/// Open-addressed by `value.hashString`; holds name positions plus one.
const hashed_slots: [hashed_mask + 1]u16 = blk: {
    @setEvalBranchQuota(1_000_000);
    var slots: [hashed_mask + 1]u16 = @splat(0);
    for (names, 0..) |name, index| {
        var position: usize = @intCast(value_mod.hashString(name) & hashed_mask);
        while (slots[position] != 0) position = (position + 1) & hashed_mask;
        slots[position] = index + 1;
    }
    break :blk slots;
};

/// `canonical` for callers that already computed `value.hashString(bytes)`.
pub fn canonicalHashed(bytes: []const u8, hash: u64) ?[]const u8 {
    var position: usize = @intCast(hash & hashed_mask);
    while (hashed_slots[position] != 0) : (position = (position + 1) & hashed_mask) {
        const name = names[hashed_slots[position] - 1];
        if (name.len == bytes.len and std.mem.eql(u8, name, bytes)) return name;
    }
    return null;
}

pub fn get(comptime bytes: []const u8) []const u8 {
    return comptime canonical(bytes) orelse @compileError("missing standard-library static string: " ++ bytes);
}

test "all static strings are canonical" {
    for (names) |name| {
        const value = canonical(name) orelse return error.TestUnexpectedResult;
        try std.testing.expectEqual(name.ptr, value.ptr);
    }
}
