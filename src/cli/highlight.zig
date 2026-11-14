const std = @import("std");
const zlua = @import("zlua");
const term = @import("term.zig");

const Paint = term.Paint;

pub const Kind = enum {
    space,
    identifier,
    keyword,
    builtin,
    string,
    number,
    comment,
    symbol,
};

pub const Token = struct {
    kind: Kind,
    start: usize,
    end: usize,

    pub fn text(self: Token, source: []const u8) []const u8 {
        return source[self.start..self.end];
    }
};

pub const keywords = [_][]const u8{
    "and", "break", "do",  "else", "elseif", "end",    "false",  "for",  "function", "global", "goto",  "if",
    "in",  "local", "nil", "not",  "or",     "repeat", "return", "then", "true",     "until",  "while",
};

const builtins = [_][]const u8{
    "_ENV",     "_G",      "_VERSION", "assert",   "collectgarbage", "coroutine",    "csv",
    "datetime", "debug",   "dofile",   "error",    "fs",             "getmetatable", "io",
    "ipairs",   "json",    "load",     "loadfile", "math",           "msgpack",      "next",
    "os",       "package", "pairs",    "pcall",    "print",          "rawequal",     "rawget",
    "rawlen",   "rawset",  "require",  "select",   "self",           "setmetatable", "string",
    "table",    "toml",    "tonumber", "tostring", "type",           "utf8",         "warn",
    "xpcall",
};

/// Tokenizes Lua source for display; every byte belongs to a token.
pub const Scanner = struct {
    source: []const u8,
    index: usize = 0,

    pub fn next(self: *Scanner) ?Token {
        const source = self.source;
        const start = self.index;
        if (start >= source.len) return null;
        const byte = source[start];
        const kind: Kind = if (isSpace(byte)) blk: {
            while (self.index < source.len and isSpace(source[self.index])) self.index += 1;
            break :blk .space;
        } else if (isIdentifierStart(byte)) blk: {
            while (self.index < source.len and isIdentifierPart(source[self.index])) self.index += 1;
            const word = source[start..self.index];
            if (zlua.frontend.token.keywordTag(word) != null) break :blk .keyword;
            for (builtins) |name| if (std.mem.eql(u8, name, word)) break :blk .builtin;
            break :blk .identifier;
        } else if (isDigit(byte) or (byte == '.' and start + 1 < source.len and isDigit(source[start + 1]))) blk: {
            self.scanNumber();
            break :blk .number;
        } else if (byte == '"' or byte == '\'') blk: {
            self.scanShortString(byte);
            break :blk .string;
        } else if (byte == '-' and start + 1 < source.len and source[start + 1] == '-') blk: {
            self.index += 2;
            if (self.longBracketLevel()) |level| {
                self.scanLongBracket(level);
            } else {
                while (self.index < source.len and source[self.index] != '\n') self.index += 1;
            }
            break :blk .comment;
        } else if (byte == '[') blk: {
            if (self.longBracketLevel()) |level| {
                self.scanLongBracket(level);
                break :blk .string;
            }
            self.index += 1;
            break :blk .symbol;
        } else if (byte == '.') blk: {
            while (self.index < source.len and self.index - start < 3 and source[self.index] == '.') self.index += 1;
            break :blk .symbol;
        } else blk: {
            self.index = @min(start + term.sequenceLength(byte), source.len);
            break :blk .symbol;
        };
        return .{ .kind = kind, .start = start, .end = self.index };
    }

    fn scanNumber(self: *Scanner) void {
        const source = self.source;
        var previous: u8 = 0;
        while (self.index < source.len) : (self.index += 1) {
            const byte = source[self.index];
            const exponent_sign = (byte == '+' or byte == '-') and (previous == 'e' or previous == 'E' or previous == 'p' or previous == 'P');
            if (!isIdentifierPart(byte) and byte != '.' and !exponent_sign) break;
            if (byte == '.' and self.index + 1 < source.len and source[self.index + 1] == '.') break;
            previous = byte;
        }
    }

    fn scanShortString(self: *Scanner, quote: u8) void {
        const source = self.source;
        self.index += 1;
        while (self.index < source.len) {
            const byte = source[self.index];
            if (byte == '\n') return;
            self.index += 1;
            if (byte == quote) return;
            if (byte == '\\' and self.index < source.len) {
                if (source[self.index] == 'z') {
                    self.index += 1;
                    while (self.index < source.len and isSpace(source[self.index])) self.index += 1;
                } else {
                    self.index += 1;
                }
            }
        }
    }

    fn longBracketLevel(self: *const Scanner) ?usize {
        const source = self.source;
        if (self.index >= source.len or source[self.index] != '[') return null;
        var end = self.index + 1;
        while (end < source.len and source[end] == '=') end += 1;
        if (end >= source.len or source[end] != '[') return null;
        return end - self.index - 1;
    }

    fn scanLongBracket(self: *Scanner, level: usize) void {
        const source = self.source;
        self.index += level + 2;
        while (self.index < source.len) : (self.index += 1) {
            if (source[self.index] != ']') continue;
            const close_end = self.index + level + 2;
            if (close_end > source.len or source[close_end - 1] != ']') continue;
            if (std.mem.allEqual(u8, source[self.index + 1 .. close_end - 1], '=')) {
                self.index = close_end;
                return;
            }
        }
    }
};

fn roleOf(kind: Kind) ?term.Role {
    return switch (kind) {
        .keyword => .keyword,
        .builtin => .builtin,
        .string => .string,
        .number => .number,
        .comment => .comment,
        .space, .identifier, .symbol => null,
    };
}

pub fn appendRange(allocator: std.mem.Allocator, out: *std.ArrayList(u8), paint: Paint, source: []const u8, from: usize, to: usize) !void {
    var scanner: Scanner = .{ .source = source };
    while (scanner.next()) |token| {
        if (token.end <= from) continue;
        if (token.start >= to) break;
        const piece = source[@max(token.start, from)..@min(token.end, to)];
        if (roleOf(token.kind)) |role| {
            try out.appendSlice(allocator, paint.on(role));
            try appendExpanded(allocator, out, piece);
            try out.appendSlice(allocator, paint.off());
        } else {
            try appendExpanded(allocator, out, piece);
        }
    }
}

pub fn append(allocator: std.mem.Allocator, out: *std.ArrayList(u8), paint: Paint, source: []const u8) !void {
    return appendRange(allocator, out, paint, source, 0, source.len);
}

fn appendExpanded(allocator: std.mem.Allocator, out: *std.ArrayList(u8), text: []const u8) !void {
    for (text) |byte| {
        if (byte == '\t') try out.appendSlice(allocator, "    ") else try out.append(allocator, byte);
    }
}

pub fn uniqueIdentifier(line: []const u8, name: []const u8) ?Token {
    var found: ?Token = null;
    var scanner: Scanner = .{ .source = line };
    while (scanner.next()) |token| {
        if (token.kind != .identifier and token.kind != .builtin) continue;
        if (!std.mem.eql(u8, token.text(line), name)) continue;
        if (found != null) return null;
        found = token;
    }
    return found;
}

/// Closers at the start of `line` don't count against its openers.
pub fn opensBlock(line: []const u8) bool {
    var delta: isize = 0;
    var lowest: isize = 0;
    var scanner: Scanner = .{ .source = line };
    while (scanner.next()) |token| {
        const text = token.text(line);
        switch (token.kind) {
            .keyword => {
                const closers = [_][]const u8{ "end", "until", "else", "elseif" };
                const openers = [_][]const u8{ "function", "do", "then", "repeat", "else" };
                for (closers) |word| {
                    if (std.mem.eql(u8, text, word)) delta -= 1;
                }
                lowest = @min(lowest, delta);
                for (openers) |word| {
                    if (std.mem.eql(u8, text, word)) delta += 1;
                }
            },
            .symbol => switch (text[0]) {
                '{', '(', '[' => delta += 1,
                '}', ')', ']' => delta -= 1,
                else => {},
            },
            else => {},
        }
        lowest = @min(lowest, delta);
    }
    return delta > lowest;
}

pub fn isIdentifierStart(byte: u8) bool {
    return (byte >= 'a' and byte <= 'z') or (byte >= 'A' and byte <= 'Z') or byte == '_';
}

pub fn isIdentifierPart(byte: u8) bool {
    return isIdentifierStart(byte) or isDigit(byte);
}

pub fn isIdentifier(text: []const u8) bool {
    if (text.len == 0 or !isIdentifierStart(text[0])) return false;
    for (text[1..]) |byte| if (!isIdentifierPart(byte)) return false;
    return zlua.frontend.token.keywordTag(text) == null;
}

fn isDigit(byte: u8) bool {
    return byte >= '0' and byte <= '9';
}

fn isSpace(byte: u8) bool {
    return byte == ' ' or byte == '\t' or byte == '\n' or byte == '\r';
}

fn expectKinds(source: []const u8, expected: []const Kind) !void {
    var scanner: Scanner = .{ .source = source };
    var covered: usize = 0;
    var index: usize = 0;
    while (scanner.next()) |token| {
        try std.testing.expectEqual(covered, token.start);
        covered = token.end;
        if (token.kind == .space) continue;
        try std.testing.expect(index < expected.len);
        try std.testing.expectEqual(expected[index], token.kind);
        index += 1;
    }
    try std.testing.expectEqual(source.len, covered);
    try std.testing.expectEqual(expected.len, index);
}

test "scanner classifies tokens and covers the source" {
    try expectKinds("local x = print(1.5e-3, 'a\\'b') -- done", &.{ .keyword, .identifier, .symbol, .builtin, .symbol, .number, .symbol, .string, .symbol, .comment });
    try expectKinds("a[[x]] .. [==[ ]] ]==] --[[ c ]] b", &.{ .identifier, .string, .symbol, .string, .comment, .identifier });
    try expectKinds("t[1] = 0x1p-2", &.{ .identifier, .symbol, .number, .symbol, .symbol, .number });
    try expectKinds("a..2 ...", &.{ .identifier, .symbol, .number, .symbol });
}

test "unfinished strings and comments end at the line or source" {
    try expectKinds("x = 'abc\ny", &.{ .identifier, .symbol, .string, .identifier });
    try expectKinds("x = [[abc\ny", &.{ .identifier, .symbol, .string });
    try expectKinds("--[==[ abc\ny", &.{.comment});
    try expectKinds("é = 1", &.{ .symbol, .symbol, .number });
}

test "uniqueIdentifier ignores strings and repeated names" {
    try std.testing.expectEqual(@as(usize, 6), uniqueIdentifier("print(foo, 'bar')", "foo").?.start);
    try std.testing.expect(uniqueIdentifier("print('foo')", "foo") == null);
    try std.testing.expect(uniqueIdentifier("foo(foo)", "foo") == null);
}

test "opensBlock ignores leading closers" {
    try std.testing.expect(opensBlock("for i = 1, 3 do"));
    try std.testing.expect(opensBlock("local t = {"));
    try std.testing.expect(opensBlock("else"));
    try std.testing.expect(opensBlock("end, function(x)"));
    try std.testing.expect(!opensBlock("if x then y() end"));
    try std.testing.expect(!opensBlock("end -- do"));
    try std.testing.expect(!opensBlock("x = 'do'"));
}
