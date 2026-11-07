const std = @import("std");
const compile = @import("../compile.zig");
const runtime = @import("../runtime.zig");

const bytecode = compile.bytecode;
const Proto = compile.proto.Proto;
const Allocator = std.mem.Allocator;

/// Source of choices for generators, backed by a fuzzer or a seeded random stream.
pub const Picker = struct {
    context: *anyopaque,
    next: *const fn (*anyopaque, u32) u32,

    pub fn fromSmith(smith: *std.testing.Smith) Picker {
        return .{ .context = smith, .next = struct {
            fn next(context: *anyopaque, limit: u32) u32 {
                const source: *std.testing.Smith = @ptrCast(@alignCast(context));
                return source.valueRangeLessThan(u32, 0, limit);
            }
        }.next };
    }

    pub fn fromRandom(random: *std.Random) Picker {
        return .{ .context = random, .next = struct {
            fn next(context: *anyopaque, limit: u32) u32 {
                const source: *std.Random = @ptrCast(@alignCast(context));
                return source.uintLessThan(u32, limit);
            }
        }.next };
    }

    /// A value below `limit`, which must not be zero.
    pub fn below(self: Picker, limit: u32) u32 {
        return self.next(self.context, limit);
    }

    pub fn chance(self: Picker, percent: u32) bool {
        return self.below(100) < percent;
    }

    pub fn pick(self: Picker, comptime T: type, items: []const T) T {
        return items[self.below(@intCast(items.len))];
    }
};

const program_prelude =
    \\local function show(...)
    \\  local parts = table.pack(...)
    \\  for i = 1, parts.n do
    \\    local v = parts[i]
    \\    local t = type(v)
    \\    if t == "table" or t == "function" or t == "thread" or t == "userdata" then parts[i] = t
    \\    elseif t == "string" then
    \\      local text = v:gsub("^[^\n]-:%d+: ", ""):gsub(" %(%a+ '.-'%)", ""):gsub("0x%x+", "0x")
    \\      parts[i] = "[" .. #text .. "]" .. text:sub(1, 80)
    \\    else parts[i] = tostring(v) end
    \\  end
    \\  print(table.concat(parts, " ", 1, parts.n))
    \\end
    \\local closable = setmetatable({}, {__close = function() end})
    \\local mt = setmetatable({}, {__index = function(t, k) return k end, __call = function(self, a) return a end,
    \\  __add = function(a, b) return 1 end, __concat = function(a, b) return "c" end, __eq = function() return true end,
    \\  __lt = function() return false end, __le = function() return true end, __len = function() return 3 end,
    \\  __unm = function() return 7 end, __tostring = function() return "mt" end, __newindex = function() end})
    \\local v1, v2, v3, v4, v5, v6 = 1, 2.5, "text", {1, 2, 3, x = 4}, mt, function(a, b) return a, b end
    \\
;

const scalar_literals = [_][]const u8{
    "nil",             "true",            "false",     "0",       "1",            "-1",   "2",   "3",    "7",   "16",   "255",
    "math.maxinteger", "math.mininteger", "0.5",       "-0.0",    "1e308",        "2^53", "1/0", "-1/0", "0/0", "\"\"", "\"abc\"",
    "\"10\"",          "\"0x10\"",        "\"%d %s\"", "\"a,b\"", "\"\\0\\255\"",
};

const binary_operators = [_][]const u8{ "+", "-", "*", "/", "//", "%", "^", "..", "==", "~=", "<", "<=", ">", ">=", "and", "or", "&", "|", "~", "<<", ">>" };
const unary_operators = [_][]const u8{ "- ", "not ", "#", "~" };
const variables = [_][]const u8{ "v1", "v2", "v3", "v4", "v5", "v6" };

/// Standard library functions with deterministic results, safe to compare across interpreters.
const pure_functions = [_][]const u8{
    "tostring",       "tonumber",       "type",             "select",           "rawequal",         "rawlen",          "rawget",                "next",         "pcall",
    "string.byte",    "string.char",    "string.find",      "string.format",    "string.gmatch",    "string.gsub",     "string.len",            "string.lower", "string.match",
    "string.reverse", "string.sub",     "string.upper",     "string.pack",      "string.packsize",  "string.unpack",   "table.concat",          "table.insert", "table.move",
    "table.pack",     "table.remove",   "table.sort",       "table.unpack",     "math.abs",         "math.ceil",       "math.floor",            "math.fmod",    "math.max",
    "math.min",       "math.modf",      "math.tointeger",   "math.type",        "math.ult",         "utf8.char",       "utf8.codepoint",        "utf8.len",     "utf8.offset",
    "utf8.codes",     "coroutine.wrap", "coroutine.create", "coroutine.resume", "coroutine.status", "coroutine.close", "coroutine.isyieldable", "getmetatable", "setmetatable",
};

fn writeExpr(picker: Picker, out: *std.Io.Writer, depth: u32) anyerror!void {
    const choice = if (depth == 0) picker.below(2) else picker.below(10);
    switch (choice) {
        0 => try out.writeAll(picker.pick([]const u8, &scalar_literals)),
        1 => try out.writeAll(picker.pick([]const u8, &variables)),
        2, 3 => {
            try out.writeByte('(');
            try writeExpr(picker, out, depth - 1);
            try out.print(" {s} ", .{picker.pick([]const u8, &binary_operators)});
            try writeExpr(picker, out, depth - 1);
            try out.writeByte(')');
        },
        4 => {
            try out.print("({s}", .{picker.pick([]const u8, &unary_operators)});
            try writeExpr(picker, out, depth - 1);
            try out.writeByte(')');
        },
        5, 6 => {
            try out.print("{s}(", .{picker.pick([]const u8, &pure_functions)});
            try writeArguments(picker, out, depth - 1);
            try out.writeByte(')');
        },
        7 => {
            try out.writeByte('{');
            try writeArguments(picker, out, depth - 1);
            try out.writeByte('}');
        },
        8 => {
            try out.writeAll("(function(...) ");
            try writeStatements(picker, out, depth - 1);
            try out.writeAll(" return ");
            try writeExpr(picker, out, depth - 1);
            try out.writeAll(" end)");
        },
        else => {
            try out.writeByte('(');
            try writeExpr(picker, out, depth - 1);
            try out.writeAll(")[");
            try writeExpr(picker, out, depth - 1);
            try out.writeByte(']');
        },
    }
}

fn writeArguments(picker: Picker, out: *std.Io.Writer, depth: u32) anyerror!void {
    const count = picker.below(4);
    for (0..count) |index| {
        if (index != 0) try out.writeAll(", ");
        try writeExpr(picker, out, depth);
    }
}

fn writeStatements(picker: Picker, out: *std.Io.Writer, depth: u32) anyerror!void {
    const count = picker.below(3);
    for (0..count) |_| {
        try writeStatement(picker, out, depth);
        try out.writeAll("; ");
    }
}

fn writeStatement(picker: Picker, out: *std.Io.Writer, depth: u32) anyerror!void {
    switch (picker.below(11)) {
        0 => {
            try out.print("{s} = ", .{picker.pick([]const u8, &variables)});
            try writeExpr(picker, out, depth);
        },
        1 => {
            try out.writeAll("local a <const> = ");
            try writeExpr(picker, out, depth);
        },
        2 => {
            try out.writeAll("do local c <close> = closable; ");
            try writeStatements(picker, out, depth -| 1);
            try out.writeAll("end");
        },
        3 => {
            try out.writeAll("if ");
            try writeExpr(picker, out, depth);
            try out.writeAll(" then ");
            try writeStatements(picker, out, depth -| 1);
            try out.writeAll("else ");
            try writeStatements(picker, out, depth -| 1);
            try out.writeAll("end");
        },
        4 => {
            try out.print("for i = 1, {d} do ", .{picker.below(5)});
            try writeStatements(picker, out, depth -| 1);
            try out.writeAll("end");
        },
        5 => {
            try out.writeAll("for k, v in pairs(");
            try writeExpr(picker, out, depth);
            try out.writeAll(") do ");
            try writeStatements(picker, out, depth -| 1);
            try out.writeAll("end");
        },
        6 => {
            try out.writeAll("do local n = 0; while n < 3 do n = n + 1; ");
            try writeStatements(picker, out, depth -| 1);
            try out.writeAll("end end");
        },
        7 => {
            try out.writeByte('(');
            try writeExpr(picker, out, depth);
            try out.writeAll(")[1] = ");
            try writeExpr(picker, out, depth);
        },
        8 => {
            try out.writeAll("show(");
            try writeArguments(picker, out, depth);
            try out.writeByte(')');
        },
        9 => {
            try out.writeAll("local co = coroutine.wrap(function(...) coroutine.yield(...) ");
            try writeStatements(picker, out, depth -| 1);
            try out.writeAll("end) show(pcall(co, 1)) show(pcall(co))");
        },
        else => {
            try out.writeAll("show(select('#'");
            for (0..picker.below(3)) |_| {
                try out.writeAll(", ");
                try writeExpr(picker, out, depth);
            }
            try out.writeAll("))");
        },
    }
}

/// Writes a Lua program whose output depends only on Lua semantics.
pub fn writeProgram(picker: Picker, out: *std.Io.Writer) !void {
    try out.writeAll(program_prelude);
    for (0..picker.below(12) + 1) |_| {
        try out.writeAll("show(pcall(function() ");
        try writeStatement(picker, out, 3);
        try out.writeAll(" end))\n");
    }
}

const library_functions = [_][]const u8{
    "tostring",         "tonumber",              "type",             "select",            "rawequal",         "rawlen",          "rawget",          "rawset",         "next",
    "pairs",            "ipairs",                "pcall",            "xpcall",            "error",            "assert",          "load",            "getmetatable",   "setmetatable",
    "collectgarbage",   "warn",                  "print",            "string.byte",       "string.char",      "string.dump",     "string.find",     "string.format",  "string.gmatch",
    "string.gsub",      "string.len",            "string.lower",     "string.match",      "string.pack",      "string.packsize", "string.rep",      "string.reverse", "string.rsplit",
    "string.split",     "string.strip",          "string.sub",       "string.unpack",     "string.upper",     "table.concat",    "table.create",    "table.dedup",    "table.insert",
    "table.move",       "table.pack",            "table.remove",     "table.sort",        "table.unpack",     "math.abs",        "math.acos",       "math.asin",      "math.atan",
    "math.ceil",        "math.cos",              "math.deg",         "math.exp",          "math.floor",       "math.fmod",       "math.frexp",      "math.ldexp",     "math.log",
    "math.max",         "math.min",              "math.modf",        "math.rad",          "math.random",      "math.randomseed", "math.sin",        "math.sqrt",      "math.tan",
    "math.tointeger",   "math.type",             "math.ult",         "utf8.char",         "utf8.codepoint",   "utf8.codes",      "utf8.len",        "utf8.offset",    "coroutine.close",
    "coroutine.create", "coroutine.isyieldable", "coroutine.resume", "coroutine.running", "coroutine.status", "coroutine.wrap",  "coroutine.yield", "json.read",      "json.write",
    "toml.read",        "toml.write",            "msgpack.read",     "msgpack.write",     "csv.read",         "csv.write",
};

const hostile_arguments = [_][]const u8{
    "nil",                                                   "true",                                                        "0",                              "1",                                                       "-1",                                                         "2",
    "255",                                                   "1 << 31",                                                     "1 << 32",                        "1 << 53",                                                 "1 << 62",                                                    "math.maxinteger",
    "math.mininteger",                                       "0.5",                                                         "-0.5",                           "1e308",                                                   "1/0",                                                        "-1/0",
    "0/0",                                                   "\"\"",                                                        "\"abc\"",                        "\"%\"",                                                   "\"%d\"",                                                     "\"%s%s%s\"",
    "\"%99999d\"",                                           "\"%5.2f\"",                                                   "\"[\"",                          "\"(\"",                                                   "\"%b\"",                                                     "\"%f\"",
    "\"(()\"",                                               "\"^a*$\"",                                                    "\"i16\"",                        "\"!16 Xi16\"",                                            "\"<s1\"",                                                    "\"z\"",
    "\"\\xff\\xfe\"",                                        "\"\\0\"",                                                     "(\"x\"):rep(300)",               "{}",                                                      "{1, 2, 3}",                                                  "{x = 1}",
    "{{{}}}",                                                "print",                                                       "tostring",                       "function() end",                                          "function(...) return ... end",                               "function() error('x') end",
    "function(...) return coroutine.yield(...) end",         "coroutine.create(function() end)",                            "coroutine.wrap(function() end)", "setmetatable({}, {__index = function() error('x') end})", "setmetatable({}, {__newindex = function() error('x') end})", "setmetatable({}, {__len = function() return 1 << 40 end})",
    "setmetatable({}, {__len = function() return -1 end})",  "setmetatable({}, {__tostring = function() return 1 end})",    "setmetatable({}, {__name = 1})", "setmetatable({}, {__metatable = false})",                 "setmetatable({}, {__close = function() error('x') end})",    "setmetatable({}, {__gc = function() error('x') end})",
    "setmetatable({}, {__pairs = function() return 1 end})", "setmetatable({1, 2, 3}, {__lt = function() error('x') end})", "string",                         "_G",
};

/// Writes a chunk that calls standard library functions with hostile arguments.
pub fn writeLibraryCalls(picker: Picker, out: *std.Io.Writer) !void {
    for (0..picker.below(6) + 1) |_| {
        try out.print("pcall({s}", .{picker.pick([]const u8, &library_functions)});
        for (0..picker.below(5)) |_| try out.print(", {s}", .{picker.pick([]const u8, &hostile_arguments)});
        try out.writeAll(")\n");
    }
}

const format_tokens = [_][]const u8{
    "[",      "]",    "{",    "}",      ",",            ":",                    "=",                    ".",                    "\n",   " ",
    "\"a\"",  "'b'",  "1",    "-2.5e3", "true",         "null",                 "a",                    "x.y",                  "[t]",  "[[t]]",
    "\"\"\"", "'''",  "#c\n", "\\",     "\\u00e9",      "\\x",                  "1979-05-27T07:32:00Z", "nan",                  "inf",  "0x1f",
    "\xc0",   "\x91", "\x81", "\xa1",   "\xdc\xff\xff", "\xdd\xff\xff\xff\xff", "\xd9\xff",             "\xdb\xff\xff\xff\xff", "\xcb", "\xff",
};

/// Writes text mixing the tokens of the data formats.
pub fn writeFormatText(picker: Picker, out: *std.Io.Writer) !void {
    for (0..picker.below(48)) |_| try out.writeAll(picker.pick([]const u8, &format_tokens));
}

const typed_int = 0;
const typed_float = 1;
const typed_string = 2;
const typed_table = 3;
const typed_function = 4;
const first_scratch = 5;

const chunk_constants = [_]bytecode.Constant{
    .{ .integer = "1" },           .{ .integer = "2" },               .{ .integer = "-1" },           .{ .integer = "0" },
    .{ .number = "2.5" },          .{ .string = "\"s\"" },            .{ .string = "\"x\"" },         .{ .string = "\"pcall\"" },
    .{ .string = "\"tostring\"" }, .{ .string = "\"select\"" },       .{ .string = "\"coroutine\"" }, .{ .string = "\"wrap\"" },
    .{ .string = "\"yield\"" },    .{ .string = "\"setmetatable\"" }, .{ .string = "\"__close\"" },   .{ .string = "\"__index\"" },
    .nil,                          .{ .boolean = true },
};
const constant_integer = 0;
const constant_number = 4;
const constant_string = 5;
const constant_pcall = 7;
const constant_tostring = 8;
const constant_select = 9;
const constant_coroutine = 10;
const constant_wrap = 11;
const numeric_constants = [_]u32{ 0, 1, 2, 3, 4 };
const global_names = [_]u32{ constant_pcall, constant_tostring, constant_select, constant_coroutine };

const ChunkBuilder = struct {
    picker: Picker,
    proto: *Proto,
    registers: u16,
    children: u32,
    upvalues: u16,
    length: u32,

    fn emit(self: *ChunkBuilder, instruction: bytecode.Instruction) !void {
        _ = try self.proto.emit(instruction, 1);
    }

    fn any(self: *ChunkBuilder) bytecode.Register {
        return @intCast(self.picker.below(self.registers));
    }

    /// A register holding an expected type, or now and then any register.
    fn typed(self: *ChunkBuilder, register: u16) bytecode.Register {
        if (register >= self.registers or self.picker.chance(2)) return self.any();
        return @intCast(register);
    }

    fn scratch(self: *ChunkBuilder) bytecode.Register {
        if (self.registers <= first_scratch) return self.any();
        return @intCast(first_scratch + self.picker.below(self.registers - first_scratch));
    }

    fn jump(self: *ChunkBuilder, pc: u32) i32 {
        const remaining: i32 = @intCast(self.length -| pc);
        if (self.picker.chance(10)) return -@as(i32, @intCast(@min(pc, self.picker.below(5)))) - 1;
        return @min(@as(i32, @intCast(self.picker.below(6))), remaining);
    }

    fn number(self: *ChunkBuilder) bytecode.Register {
        return self.typed(if (self.picker.chance(50)) typed_int else typed_float);
    }

    fn step(self: *ChunkBuilder, pc: u32) !void {
        const p = self.picker;
        switch (p.below(32)) {
            0 => try self.emit(.{ .load_nil = self.scratch() }),
            1 => try self.emit(.{ .load_bool = .{ .dest = self.scratch(), .value = p.chance(50) } }),
            2 => try self.emit(.{ .load_const = .{ .dest = self.scratch(), .constant = p.below(chunk_constants.len) } }),
            3 => try self.emit(.{ .move = .{ .dest = self.scratch(), .source = self.any() } }),
            4 => try self.emit(.{ .get_global = .{ .register = self.scratch(), .name = p.pick(u32, &global_names) } }),
            5 => if (self.upvalues != 0) {
                try self.emit(.{ .get_upvalue = .{ .register = self.scratch(), .upvalue = @intCast(p.below(self.upvalues)) } });
            } else try self.emit(.{ .load_nil = self.scratch() }),
            6 => if (self.upvalues != 0) {
                try self.emit(.{ .set_upvalue = .{ .register = self.any(), .upvalue = @intCast(p.below(self.upvalues)) } });
            } else try self.emit(.{ .load_nil = self.scratch() }),
            7 => try self.emit(.{ .get_table = .{ .dest = self.scratch(), .table = self.typed(typed_table), .key = self.any() } }),
            8 => try self.emit(.{ .set_table = .{ .table = self.typed(typed_table), .key = self.typed(typed_int), .value = self.any() } }),
            9 => try self.emit(.{ .set_array = .{ .table = self.typed(typed_table), .index = p.below(8) + 1, .value = self.any() } }),
            10 => try self.emit(.{ .get_field = .{ .dest = self.scratch(), .table = self.typed(typed_table), .name = constant_string + p.below(2) } }),
            11 => try self.emit(.{ .set_field = .{ .table = self.typed(typed_table), .name = constant_string + p.below(2), .value = self.any() } }),
            12 => try self.emit(.{ .new_table = .{ .dest = self.scratch() } }),
            13 => {
                const first = self.scratch();
                const count: u8 = if (p.chance(4)) bytecode.set_list_multret else @intCast(p.below(@as(u32, self.registers - first) + 1));
                try self.emit(.{ .set_list = .{ .table = self.typed(typed_table), .first = first, .count = count, .start_index = p.below(4) + 1 } });
            },
            14, 15 => {
                const binary: bytecode.Binary = .{ .dest = self.scratch(), .left = self.number(), .right = self.number() };
                try self.emit(switch (p.below(13)) {
                    0 => .{ .add = binary },
                    1 => .{ .sub = binary },
                    2 => .{ .mul = binary },
                    3 => .{ .div = binary },
                    4 => .{ .idiv = binary },
                    5 => .{ .mod = binary },
                    6 => .{ .pow = binary },
                    7 => .{ .band = binary },
                    8 => .{ .bor = binary },
                    9 => .{ .bxor = binary },
                    10 => .{ .shl = binary },
                    11 => .{ .shr = binary },
                    else => .{ .eq = binary },
                });
            },
            16 => {
                const left = self.typed(typed_string);
                const binary: bytecode.Binary = .{ .dest = self.scratch(), .left = left, .right = self.typed(typed_string) };
                try self.emit(switch (p.below(3)) {
                    0 => .{ .concat = binary },
                    1 => .{ .lt = binary },
                    else => .{ .le = binary },
                });
            },
            17 => {
                const unary: bytecode.Unary = .{ .dest = self.scratch(), .source = self.number() };
                try self.emit(switch (p.below(4)) {
                    0 => .{ .unm = unary },
                    1 => .{ .bnot = unary },
                    2 => .{ .not = unary },
                    else => .{ .len = .{ .dest = unary.dest, .source = self.typed(typed_table) } },
                });
            },
            18 => {
                const constant: bytecode.BinaryConstant = .{ .dest = self.scratch(), .left = self.number(), .constant = p.pick(u32, &numeric_constants) };
                try self.emit(switch (p.below(6)) {
                    0 => .{ .add_k = constant },
                    1 => .{ .sub_k = constant },
                    2 => .{ .mul_k = constant },
                    3 => .{ .div_k = constant },
                    4 => .{ .mod_k = constant },
                    else => .{ .band_k = constant },
                });
            },
            19 => try self.emit(.{ .jmp = self.jump(pc) }),
            20 => try self.emit(.{ .compare_branch = .{ .left = self.number(), .right = self.number(), .branch = .{ .op = p.pick(bytecode.CompareBranchOp, &.{ .eq, .lt, .le }), .jump_if_truthy = p.chance(50), .offset = @intCast(self.jump(pc)) } } }),
            21 => try self.emit(.{ .compare_branch_k = .{ .register = self.number(), .constant = @intCast(p.pick(u32, &numeric_constants)), .branch = .{ .op = p.pick(bytecode.CompareConstantOp, &.{ .eq, .lt, .le, .gt, .ge }), .jump_if_truthy = p.chance(50), .offset = @intCast(self.jump(pc)) } } }),
            22 => try self.emit(.{ .test_op = .{ .register = self.any(), .jump_if_truthy = p.chance(50), .offset = self.jump(pc) } }),
            23 => try self.emit(.{ .test_set = .{ .dest = self.scratch(), .source = self.any(), .jump_if_truthy = p.chance(50), .offset = self.jump(pc) } }),
            24, 25, 26 => {
                const base = self.scratch();
                try self.emit(.{ .move = .{ .dest = base, .source = self.typed(typed_function) } });
                const room: u32 = self.registers - base - 1;
                const args = p.below(room + 1);
                const arg_count: u16 = if (p.chance(3)) bytecode.multret_count else @intCast(args);
                const room_with_base: u32 = self.registers - base;
                const return_count: u16 = if (p.chance(30)) bytecode.multret_count else @intCast(p.below(room_with_base + 1));
                const call: bytecode.CallInstruction = .{ .base = base, .arg_count = arg_count, .return_count = return_count };
                try self.emit(if (p.chance(3)) .{ .tail_call = call } else .{ .call = call });
            },
            27 => {
                if (!p.chance(10)) return self.emit(.{ .load_nil = self.scratch() });
                const first = self.scratch();
                try self.emit(.{ .ret = .{ .first = first, .count = if (p.chance(30)) bytecode.multret_count else @intCast(p.below(@as(u32, self.registers - first) + 1)) } });
            },
            28 => {
                const first = self.scratch();
                try self.emit(.{ .vararg = .{ .dest = first, .count = if (p.chance(50)) bytecode.multret_count else @intCast(p.below(@as(u32, self.registers - first) + 1)) } });
            },
            29 => if (self.children != 0) {
                try self.emit(.{ .closure = .{ .dest = self.scratch(), .proto = p.below(self.children) } });
            } else try self.emit(.{ .close = @intCast(p.below(@as(u32, self.registers) + 1)) }),
            30 => switch (p.below(3)) {
                0 => try self.emit(.{ .close = @intCast(p.below(@as(u32, self.registers) + 1)) }),
                1 => {
                    const register = self.scratch();
                    if (!p.chance(5)) try self.emit(.{ .load_nil = register });
                    try self.emit(.{ .check_close = register });
                },
                else => try self.emit(.{ .close_tbc = self.any() }),
            },
            else => {
                if (self.registers < 8) return self.emit(.{ .load_nil = self.scratch() });
                const base: bytecode.Register = @intCast(first_scratch + p.below(self.registers - 7 - (first_scratch - 1)));
                const jump_offset = self.jump(pc);
                switch (p.below(4)) {
                    0, 1 => {
                        for (0..3) |offset| try self.emit(.{ .load_const = .{ .dest = base + @as(bytecode.Register, @intCast(offset)), .constant = if (p.chance(70)) constant_integer + p.below(2) else constant_number } });
                        if (p.chance(70)) try self.emit(.{ .for_prep = .{ .base = base, .offset = jump_offset } });
                        try self.emit(.{ .for_loop = .{ .base = base, .offset = if (p.chance(50)) jump_offset else -1 } });
                    },
                    2 => {
                        try self.emit(.{ .get_global = .{ .register = base, .name = constant_tostring } });
                        try self.emit(.{ .tfor_call = .{ .base = base, .variable_count = @intCast(p.below(3)), .offset = jump_offset } });
                    },
                    else => {
                        const count = 2 + @as(u16, @intCast(p.below(4)));
                        for (0..count) |offset| try self.emit(.{ .move = .{ .dest = base + @as(bytecode.Register, @intCast(offset)), .source = if (p.chance(50)) typed_string else typed_int } });
                        try self.emit(.{ .concat_range = .{ .dest = self.scratch(), .first = base, .count = count } });
                    },
                }
            },
        }
    }
};

fn fillProto(picker: Picker, allocator: Allocator, proto: *Proto, depth: u32, parent_registers: u16, parent_upvalues: u16) anyerror!void {
    const registers: u16 = @intCast(picker.pick(u32, &.{ 12, 16, 24, 32, 64 }));
    proto.max_registers = registers;
    proto.source_name = "=generated";
    proto.param_count = @intCast(picker.below(3));
    proto.is_vararg = picker.chance(50);
    for (chunk_constants) |constant| _ = try proto.appendConstant(constant);

    if (depth == 0) {
        try proto.upvalues.append(proto.allocator, .{ .name = "_ENV", .in_stack = true, .index = 0 });
    } else if (picker.chance(70)) {
        const in_stack = parent_upvalues == 0 or picker.chance(70);
        try proto.upvalues.append(proto.allocator, .{ .name = "u", .in_stack = in_stack, .index = @intCast(if (in_stack) picker.below(parent_registers) else picker.below(parent_upvalues)) });
    }

    const child_count: u32 = if (depth < 2) picker.below(3) else 0;
    for (0..child_count) |_| {
        const child = try allocator.create(Proto);
        child.* = Proto.init(allocator);
        try proto.children.append(proto.allocator, child);
        try fillProto(picker, allocator, child, depth + 1, registers, @intCast(proto.upvalues.items.len));
    }

    var builder: ChunkBuilder = .{
        .picker = picker,
        .proto = proto,
        .registers = registers,
        .children = child_count,
        .upvalues = @intCast(proto.upvalues.items.len),
        .length = 16 + picker.below(48),
    };
    try builder.emit(.{ .load_const = .{ .dest = typed_int, .constant = constant_integer } });
    try builder.emit(.{ .load_const = .{ .dest = typed_float, .constant = constant_number } });
    try builder.emit(.{ .load_const = .{ .dest = typed_string, .constant = constant_string } });
    try builder.emit(.{ .new_table = .{ .dest = typed_table } });
    if (child_count != 0 and picker.chance(70)) {
        try builder.emit(.{ .closure = .{ .dest = typed_function, .proto = 0 } });
    } else {
        try builder.emit(.{ .get_global = .{ .register = typed_function, .name = picker.pick(u32, &.{ constant_pcall, constant_tostring }) } });
    }
    const body = builder.length;
    builder.length = 5 + body * 2;
    var pc: u32 = 5;
    for (0..body) |_| {
        try builder.step(pc);
        pc = @intCast(proto.instructions.items.len);
    }
    try builder.emit(.{ .ret = .{ .first = 0, .count = 0 } });

    const code_length: i64 = @intCast(proto.instructions.items.len);
    for (proto.instructions.items, 0..) |*instruction, index| {
        const offset = switch (instruction.*) {
            .tfor_call => |op| op.offset,
            else => instruction.jumpOffset(),
        };
        if (offset) |target| {
            const here: i64 = @intCast(index);
            const destination = std.math.clamp(here + 1 + target, 0, code_length - 1);
            instruction.setJumpOffset(@intCast(destination - here - 1)) catch unreachable;
        }
    }
}

/// Appends a binary chunk that passes verification, biased to run past its first instructions.
pub fn appendChunk(picker: Picker, allocator: Allocator, out: *std.ArrayList(u8)) !void {
    var root = Proto.init(allocator);
    defer root.deinit();
    try fillProto(picker, allocator, &root, 0, 0, 0);
    try runtime.appendBinaryChunk(allocator, out, &root);
}
