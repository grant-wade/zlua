const std = @import("std");
const runtime = @import("../../runtime.zig");

const State = runtime.State;
const Value = runtime.Value;

const MatchRange = struct { start: usize, end: usize };
pub const max_captures = 32;
const CaptureSlot = union(enum) {
    unfinished: usize,
    range: MatchRange,
    position: usize,
};
const CaptureState = struct {
    slots: [max_captures]CaptureSlot = undefined,
    count: usize = 0,
};
pub const Match = struct { range: MatchRange, captures: CaptureState };
const MatchResult = struct { end: usize, captures: CaptureState };
const pattern_match_max_depth: usize = 200;
const MatchError = runtime.RuntimeError || error{ Interrupted, OutOfMemory };

pub fn patternHasSpecials(pattern: []const u8) bool {
    for (pattern) |ch| {
        if (std.mem.indexOfScalar(u8, "^$*+?.([%-", ch) != null) return true;
    }
    return false;
}

pub fn patternHasMagic(pattern: []const u8) bool {
    for (pattern) |ch| {
        if (std.mem.indexOfScalar(u8, "^$()%.[]*+-?", ch) != null) return true;
    }
    return false;
}

pub fn plainFind(source: []const u8, pattern: []const u8, start: usize) ?Match {
    if (pattern.len == 0) return .{ .range = .{ .start = @min(start, source.len), .end = @min(start, source.len) }, .captures = .{} };
    if (start > source.len) return null;
    if (pattern.len > source.len - start) return null;
    if (pattern.len == 1) {
        const index = std.mem.indexOfScalarPos(u8, source, start, pattern[0]) orelse return null;
        return .{ .range = .{ .start = index, .end = index + 1 }, .captures = .{} };
    }

    const last_start = source.len - pattern.len;
    var candidate = start;
    while (candidate <= last_start) {
        const haystack = source[candidate .. last_start + 1];
        const relative = std.mem.indexOfScalar(u8, haystack, pattern[0]) orelse return null;
        candidate += relative;
        if (std.mem.eql(u8, source[candidate .. candidate + pattern.len], pattern)) return .{ .range = .{ .start = candidate, .end = candidate + pattern.len }, .captures = .{} };
        candidate += 1;
    }
    return null;
}

pub fn simplePatternFind(state: *State, source: []const u8, pattern: []const u8, start: usize) !?Match {
    if (pattern.len > 0 and pattern[0] == '^') {
        const anchored_start = @min(start, source.len);
        const matched = (try matchSimplePatternAt(state, source, pattern[1..], anchored_start)) orelse return null;
        return .{ .range = .{ .start = anchored_start, .end = matched.end }, .captures = matched.captures };
    }
    return unanchoredPatternFind(state, source, pattern, start);
}

pub fn unanchoredPatternFind(state: *State, source: []const u8, pattern: []const u8, start: usize) !?Match {
    if (pattern.len == 0) return .{ .range = .{ .start = @min(start, source.len), .end = @min(start, source.len) }, .captures = .{} };
    if (repeatedEscapePattern(pattern)) |repeated| return findRepeatedEscape(source, repeated, start);
    if (simpleOneOrMoreEscape(pattern)) |code| return findOneOrMoreEscape(source, code, start);
    switch (findFixedWidthPattern(source, pattern, start)) {
        .found => |matched| return matched,
        .not_found => return null,
        .unsupported => {},
    }
    var candidate = start;
    while (candidate <= source.len) : (candidate += 1) {
        try state.budget.checkInterrupt();
        if (try matchSimplePatternAt(state, source, pattern, candidate)) |matched| return .{ .range = .{ .start = candidate, .end = matched.end }, .captures = matched.captures };
    }
    return null;
}

const FixedPatternFind = union(enum) {
    unsupported,
    not_found,
    found: Match,
};

fn findFixedWidthPattern(source: []const u8, pattern: []const u8, start: usize) FixedPatternFind {
    const width = fixedWidthPatternLength(pattern) orelse return .unsupported;
    if (width == 0) return .unsupported;
    const first_atom_end = fixedPatternAtomEnd(pattern, 0).?;
    const first_atom = pattern[0..first_atom_end];
    const bounded_start = @min(start, source.len);
    if (width > source.len - bounded_start) return .not_found;

    const last_start = source.len - width;
    var candidate = bounded_start;
    while (candidate <= last_start) {
        candidate = findFixedAtom(source, first_atom, candidate, last_start) orelse return .not_found;
        const end = matchFixedWidthPatternAt(source, pattern, candidate).?;
        if (end != 0) return .{ .found = .{ .range = .{ .start = candidate, .end = end }, .captures = .{} } };
        candidate += 1;
    }
    return .not_found;
}

const RepeatedEscapePattern = struct {
    code: u8,
    count: usize,
};

fn repeatedEscapePattern(pattern: []const u8) ?RepeatedEscapePattern {
    if (pattern.len < 2 or pattern.len % 2 != 0) return null;
    var index: usize = 0;
    var code: ?u8 = null;
    var count: usize = 0;
    while (index < pattern.len) : (index += 2) {
        if (pattern[index] != '%') return null;
        const current = pattern[index + 1];
        switch (current) {
            'b', 'f', '0'...'9' => return null,
            else => {},
        }
        if (code) |expected| {
            if (current != expected) return null;
        } else {
            code = current;
        }
        count += 1;
    }
    return .{ .code = code.?, .count = count };
}

fn findRepeatedEscape(source: []const u8, repeated: RepeatedEscapePattern, start: usize) ?Match {
    const bounded_start = @min(start, source.len);
    if (repeated.count > source.len - bounded_start) return null;
    const last_start = source.len - repeated.count;
    var candidate = bounded_start;
    while (candidate <= last_start) {
        candidate = findEscapeMatch(source, repeated.code, candidate, last_start) orelse return null;
        var offset: usize = 1;
        while (offset < repeated.count and patternEscapeMatches(repeated.code, source[candidate + offset])) : (offset += 1) {}
        if (offset == repeated.count) return .{ .range = .{ .start = candidate, .end = candidate + repeated.count }, .captures = .{} };
        candidate += 1;
    }
    return null;
}

fn fixedWidthPatternLength(pattern: []const u8) ?usize {
    var index: usize = 0;
    var width: usize = 0;
    while (index < pattern.len) {
        const atom_end = fixedPatternAtomEnd(pattern, index) orelse return null;
        if (atom_end < pattern.len and isPatternQuantifier(pattern[atom_end])) return null;
        width += 1;
        index = atom_end;
    }
    return width;
}

fn fixedPatternAtomEnd(pattern: []const u8, index: usize) ?usize {
    return switch (pattern[index]) {
        '.' => index + 1,
        '%' => blk: {
            if (index + 1 >= pattern.len) break :blk null;
            break :blk switch (pattern[index + 1]) {
                'b', 'f', '0'...'9' => null,
                else => index + 2,
            };
        },
        '[' => blk: {
            const end = classAtomEnd(pattern, index);
            break :blk if (end > index) end else null;
        },
        '^', '$', '(', ')', ']', '*', '+', '-', '?' => null,
        else => index + 1,
    };
}

fn isPatternQuantifier(code: u8) bool {
    return code == '*' or code == '+' or code == '-' or code == '?';
}

fn findFixedAtom(source: []const u8, atom: []const u8, start: usize, last_start: usize) ?usize {
    if (atom.len == 1 and atom[0] != '.') {
        const relative = std.mem.indexOfScalar(u8, source[start .. last_start + 1], atom[0]) orelse return null;
        return start + relative;
    }
    if (atom.len == 2 and atom[0] == '%' and atom[1] == 'd') return findAsciiDigit(source, start, last_start);
    var candidate = start;
    while (candidate <= last_start) : (candidate += 1) {
        if (patternAtomMatches(atom, source[candidate])) return candidate;
    }
    return null;
}

fn findEscapeMatch(source: []const u8, code: u8, start: usize, last_start: usize) ?usize {
    if (code == 'd') return findAsciiDigit(source, start, last_start);
    var candidate = start;
    while (candidate <= last_start) : (candidate += 1) {
        if (patternEscapeMatches(code, source[candidate])) return candidate;
    }
    return null;
}

fn findAsciiDigit(source: []const u8, start: usize, last_start: usize) ?usize {
    var index = start;
    const end = last_start + 1;
    const vector_len = std.simd.suggestVectorLength(u8) orelse 16;
    const Block = @Vector(vector_len, u8);
    const zero: Block = @splat('0');
    const nine: Block = @splat('9');
    while (index + vector_len <= end) : (index += vector_len) {
        const block: Block = source[index..][0..vector_len].*;
        const matches = (block >= zero) & (block <= nine);
        if (@reduce(.Or, matches)) return index + std.simd.firstTrue(matches).?;
    }
    while (index <= last_start) : (index += 1) {
        if (std.ascii.isDigit(source[index])) return index;
    }
    return null;
}

fn matchFixedWidthPatternAt(source: []const u8, pattern: []const u8, start: usize) ?usize {
    var source_index = start;
    var pattern_index: usize = 0;
    while (pattern_index < pattern.len) {
        if (source_index >= source.len) return 0;
        const atom_end = fixedPatternAtomEnd(pattern, pattern_index) orelse return null;
        if (!patternAtomMatches(pattern[pattern_index..atom_end], source[source_index])) return 0;
        source_index += 1;
        pattern_index = atom_end;
    }
    return source_index;
}

fn simpleOneOrMoreEscape(pattern: []const u8) ?u8 {
    if (pattern.len != 3 or pattern[0] != '%' or pattern[2] != '+') return null;
    return switch (pattern[1]) {
        'b', 'f', '0'...'9' => null,
        else => pattern[1],
    };
}

fn findOneOrMoreEscape(source: []const u8, code: u8, start: usize) ?Match {
    var candidate = @min(start, source.len);
    while (candidate < source.len and !patternEscapeMatches(code, source[candidate])) : (candidate += 1) {}
    if (candidate >= source.len) return null;

    var end = candidate + 1;
    while (end < source.len and patternEscapeMatches(code, source[end])) : (end += 1) {}
    return .{ .range = .{ .start = candidate, .end = end }, .captures = .{} };
}

fn matchSimplePatternAt(state: *State, source: []const u8, pattern: []const u8, start: usize) !?MatchResult {
    return matchPatternFrom(state, source, pattern, start, 0, 0, .{});
}

/// Mirrors `match` in lstrlib.c; `depth` counts nested calls toward Lua's limit.
fn matchPatternFrom(state: *State, source: []const u8, pattern: []const u8, source_start: usize, pattern_start: usize, depth: usize, captures: CaptureState) MatchError!?MatchResult {
    if (depth >= pattern_match_max_depth) return state.failLibrary("pattern too complex");
    var s = source_start;
    var p = pattern_start;
    while (true) {
        if (p >= pattern.len) {
            if (capturesHaveUnfinished(captures)) return state.failLibrary("unfinished capture");
            return .{ .end = s, .captures = captures };
        }
        switch (pattern[p]) {
            '(' => {
                if (p + 1 < pattern.len and pattern[p + 1] == ')') {
                    return matchPatternFrom(state, source, pattern, s, p + 2, depth + 1, try appendCapture(state, captures, .{ .position = s }));
                }
                return matchPatternFrom(state, source, pattern, s, p + 1, depth + 1, try appendCapture(state, captures, .{ .unfinished = s }));
            },
            ')' => return matchPatternFrom(state, source, pattern, s, p + 1, depth + 1, try closeCapture(state, captures, s)),
            '$' => if (p + 1 == pattern.len) return if (s == source.len) .{ .end = s, .captures = captures } else null,
            '%' => if (p + 1 < pattern.len) switch (pattern[p + 1]) {
                'b' => {
                    if (p + 3 >= pattern.len) return state.failLibrary("malformed pattern (missing arguments to '%b')");
                    s = matchBalanced(source, s, pattern[p + 2], pattern[p + 3]) orelse return null;
                    p += 4;
                    continue;
                },
                'f' => {
                    p += 2;
                    if (p >= pattern.len or pattern[p] != '[') return state.failLibrary("missing '[' after '%f' in pattern");
                    const class_end = try singleItemEnd(state, pattern, p);
                    const class = pattern[p..class_end];
                    const previous = if (s == 0) 0 else source[s - 1];
                    const current = if (s < source.len) source[s] else 0;
                    if (patternAtomMatches(class, previous) or !patternAtomMatches(class, current)) return null;
                    p = class_end;
                    continue;
                },
                '0'...'9' => {
                    s = (try matchCaptureReference(state, source, s, captures, pattern[p + 1])) orelse return null;
                    p += 2;
                    continue;
                },
                else => {},
            },
            else => {},
        }

        const item_end = try singleItemEnd(state, pattern, p);
        const item = pattern[p..item_end];
        const quantifier: u8 = if (item_end < pattern.len) pattern[item_end] else 0;
        if (!singleMatch(source, s, item)) {
            switch (quantifier) {
                '*', '?', '-' => {
                    p = item_end + 1;
                    continue;
                },
                else => return null,
            }
        }
        switch (quantifier) {
            '?' => {
                if (try matchPatternFrom(state, source, pattern, s + 1, item_end + 1, depth + 1, captures)) |matched| return matched;
                p = item_end + 1;
            },
            '+' => return maxExpand(state, source, pattern, s + 1, item, item_end + 1, depth, captures),
            '*' => return maxExpand(state, source, pattern, s, item, item_end + 1, depth, captures),
            '-' => return minExpand(state, source, pattern, s, item, item_end + 1, depth, captures),
            else => {
                s += 1;
                p = item_end;
            },
        }
    }
}

fn maxExpand(state: *State, source: []const u8, pattern: []const u8, start: usize, item: []const u8, rest: usize, depth: usize, captures: CaptureState) MatchError!?MatchResult {
    var count: usize = 0;
    while (singleMatch(source, start + count, item)) count += 1;
    while (true) {
        try state.budget.checkInterrupt();
        if (try matchPatternFrom(state, source, pattern, start + count, rest, depth + 1, captures)) |matched| return matched;
        if (count == 0) return null;
        count -= 1;
    }
}

fn minExpand(state: *State, source: []const u8, pattern: []const u8, start: usize, item: []const u8, rest: usize, depth: usize, captures: CaptureState) MatchError!?MatchResult {
    var s = start;
    while (true) {
        try state.budget.checkInterrupt();
        if (try matchPatternFrom(state, source, pattern, s, rest, depth + 1, captures)) |matched| return matched;
        if (!singleMatch(source, s, item)) return null;
        s += 1;
    }
}

fn singleMatch(source: []const u8, index: usize, item: []const u8) bool {
    return index < source.len and patternAtomMatches(item, source[index]);
}

fn singleItemEnd(state: *State, pattern: []const u8, index: usize) !usize {
    switch (pattern[index]) {
        '%' => {
            if (index + 1 >= pattern.len) return state.failLibrary("malformed pattern (ends with '%')");
            return index + 2;
        },
        '[' => {
            const end = classAtomEnd(pattern, index);
            if (end == index) return state.failLibrary("malformed pattern (missing ']')");
            return end;
        },
        else => return index + 1,
    }
}

fn appendCapture(state: *State, captures: CaptureState, slot: CaptureSlot) !CaptureState {
    if (captures.count >= max_captures) return state.failLibrary("too many captures");
    var updated = captures;
    updated.slots[updated.count] = slot;
    updated.count += 1;
    return updated;
}

fn closeCapture(state: *State, captures: CaptureState, end: usize) !CaptureState {
    var updated = captures;
    var index = updated.count;
    while (index > 0) {
        index -= 1;
        switch (updated.slots[index]) {
            .unfinished => |start| {
                updated.slots[index] = .{ .range = .{ .start = start, .end = end } };
                return updated;
            },
            else => {},
        }
    }
    return state.failLibrary("invalid pattern capture");
}

fn capturesHaveUnfinished(captures: CaptureState) bool {
    for (captures.slots[0..captures.count]) |slot| switch (slot) {
        .unfinished => return true,
        else => {},
    };
    return false;
}

fn matchBalanced(source: []const u8, source_index: usize, open: u8, close: u8) ?usize {
    if (source_index >= source.len or source[source_index] != open) return null;
    var depth: usize = 1;
    var index = source_index + 1;
    while (index < source.len) : (index += 1) {
        if (source[index] == close) {
            depth -= 1;
            if (depth == 0) return index + 1;
        } else if (source[index] == open) {
            depth += 1;
        }
    }
    return null;
}

fn matchCaptureReference(state: *State, source: []const u8, source_index: usize, captures: CaptureState, digit: u8) !?usize {
    const one_based = digit - '0';
    if (one_based == 0 or one_based > captures.count) {
        try invalidCaptureIndex(state, one_based);
        unreachable;
    }
    const range = switch (captures.slots[one_based - 1]) {
        .range => |range| range,
        .position => return null,
        .unfinished => {
            try invalidCaptureIndex(state, one_based);
            unreachable;
        },
    };
    const captured = source[range.start..range.end];
    if (captured.len > source.len - source_index) return null;
    return if (std.mem.eql(u8, source[source_index .. source_index + captured.len], captured)) source_index + captured.len else null;
}

fn classAtomEnd(pattern: []const u8, index: usize) usize {
    var end = index + 1;
    if (end < pattern.len and pattern[end] == '^') end += 1;
    if (end < pattern.len and pattern[end] == ']') end += 1;
    while (end < pattern.len) {
        if (pattern[end] == '%' and end + 1 < pattern.len) {
            end += 2;
            continue;
        }
        if (pattern[end] == ']') return end + 1;
        end += 1;
    }
    return index;
}

fn patternAtomMatches(atom: []const u8, source_byte: u8) bool {
    if (atom.len == 1) return atom[0] == '.' or atom[0] == source_byte;
    if (atom[0] == '%') return patternEscapeMatches(atom[1], source_byte);
    if (atom[0] == '[' and atom[atom.len - 1] == ']') {
        const negated = atom.len > 2 and atom[1] == '^';
        const body = atom[if (negated) 2 else 1 .. atom.len - 1];
        var matched = false;
        var index: usize = 0;
        while (index < body.len) {
            if (body[index] == '%' and index + 1 < body.len) {
                matched = matched or patternEscapeMatches(body[index + 1], source_byte);
                index += 2;
            } else if (index + 2 < body.len and body[index + 1] == '-') {
                matched = matched or (body[index] <= source_byte and source_byte <= body[index + 2]);
                index += 3;
            } else {
                matched = matched or body[index] == source_byte;
                index += 1;
            }
        }
        return if (negated) !matched else matched;
    }
    return false;
}

fn patternEscapeMatches(code: u8, source_byte: u8) bool {
    return switch (code) {
        'a' => std.ascii.isAlphabetic(source_byte),
        'A' => !std.ascii.isAlphabetic(source_byte),
        'c' => isControl(source_byte),
        'C' => !isControl(source_byte),
        'd' => std.ascii.isDigit(source_byte),
        'D' => !std.ascii.isDigit(source_byte),
        'g' => source_byte > ' ' and source_byte < 0x7f,
        'G' => !(source_byte > ' ' and source_byte < 0x7f),
        'l' => std.ascii.isLower(source_byte),
        'L' => !std.ascii.isLower(source_byte),
        'p' => isPunctuation(source_byte),
        'P' => !isPunctuation(source_byte),
        's' => std.ascii.isWhitespace(source_byte),
        'S' => !std.ascii.isWhitespace(source_byte),
        'u' => std.ascii.isUpper(source_byte),
        'U' => !std.ascii.isUpper(source_byte),
        'w' => std.ascii.isAlphanumeric(source_byte),
        'W' => !std.ascii.isAlphanumeric(source_byte),
        'x' => std.ascii.isHex(source_byte),
        'X' => !std.ascii.isHex(source_byte),
        'z' => source_byte == 0,
        'Z' => source_byte != 0,
        else => code == source_byte,
    };
}

fn isControl(code: u8) bool {
    return code < 0x20 or code == 0x7f;
}

fn isPunctuation(code: u8) bool {
    return (code >= '!' and code <= '/') or (code >= ':' and code <= '@') or (code >= '[' and code <= '`') or (code >= '{' and code <= '~');
}

pub fn invalidCaptureIndex(state: *State, one_based: u8) !void {
    var message = std.ArrayList(u8).empty;
    defer message.deinit(state.allocator);
    try runtime.appendFmt(state.allocator, &message, "invalid capture index %{d}", .{one_based});
    return state.failLibrary(message.items);
}

pub fn firstMatchValue(state: *State, source: []const u8, matched: Match) !Value {
    if (matched.captures.count == 0) return .{ .string = try state.strings.intern(source[matched.range.start..matched.range.end]) };
    return captureValue(state, source, matched.captures.slots[0]);
}

pub fn appendMatchValues(state: *State, values: *std.ArrayList(Value), source: []const u8, matched: Match) !void {
    if (matched.captures.count == 0) {
        try values.append(state.allocator, .{ .string = try state.strings.intern(source[matched.range.start..matched.range.end]) });
        return;
    }
    try appendCaptureValues(state, values, source, matched.captures);
}

pub fn appendCaptureValues(state: *State, values: *std.ArrayList(Value), source: []const u8, captures: CaptureState) !void {
    for (captures.slots[0..captures.count]) |slot| try values.append(state.allocator, try captureValue(state, source, slot));
}

pub fn captureValue(state: *State, source: []const u8, slot: CaptureSlot) !Value {
    return switch (slot) {
        .range => |range| .{ .string = try state.strings.intern(source[range.start..range.end]) },
        .position => |position| .{ .integer = @intCast(position + 1) },
        .unfinished => state.failLibrary("unfinished capture"),
    };
}
