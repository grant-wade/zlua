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
const pattern_match_max_depth: usize = 100;

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
    if (pattern.len == 0) return .{ .range = .{ .start = @min(start, source.len), .end = @min(start, source.len) }, .captures = .{} };
    if (repeatedEscapePattern(pattern)) |repeated| return findRepeatedEscape(source, repeated, start);
    if (simpleOneOrMoreEscape(pattern)) |code| return findOneOrMoreEscape(source, code, start);
    switch (findFixedWidthPattern(source, pattern, start)) {
        .found => |matched| return matched,
        .not_found => return null,
        .unsupported => {},
    }
    if (pattern[0] == '^') {
        const anchored_start = @min(start, source.len);
        const matched = (try matchSimplePatternAt(state, source, pattern[1..], anchored_start)) orelse return null;
        return .{ .range = .{ .start = anchored_start, .end = matched.end }, .captures = matched.captures };
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

fn matchPatternFrom(state: *State, source: []const u8, pattern: []const u8, source_index: usize, pattern_index: usize, depth: usize, captures: CaptureState) !?MatchResult {
    if (depth > pattern_match_max_depth) return state.failLibrary("pattern too complex");
    if (pattern_index >= pattern.len) {
        if (capturesHaveUnfinished(captures)) return state.failLibrary("unfinished capture");
        return .{ .end = source_index, .captures = captures };
    }
    if (pattern[pattern_index] == '$' and pattern_index + 1 == pattern.len) return if (source_index == source.len) .{ .end = source_index, .captures = captures } else null;
    if (pattern[pattern_index] == '(') {
        const updated = if (pattern_index + 1 < pattern.len and pattern[pattern_index + 1] == ')')
            try appendCapture(state, captures, .{ .position = source_index })
        else
            try appendCapture(state, captures, .{ .unfinished = source_index });
        const next_index = pattern_index + @as(usize, if (pattern_index + 1 < pattern.len and pattern[pattern_index + 1] == ')') 2 else 1);
        return matchPatternFrom(state, source, pattern, source_index, next_index, depth + 1, updated);
    }
    if (pattern[pattern_index] == ')') return matchPatternFrom(state, source, pattern, source_index, pattern_index + 1, depth + 1, try closeCapture(state, captures, source_index));

    const atom_start = pattern_index;
    const atom_end = nextPatternAtom(pattern, atom_start);
    try validatePatternAtom(state, pattern, atom_start, atom_end);
    const quantifier = if (atom_end < pattern.len and std.mem.indexOfScalar(u8, "*+-?", pattern[atom_end]) != null) pattern[atom_end] else 0;
    const next_index = atom_end + @as(usize, if (quantifier != 0) 1 else 0);
    const atom = pattern[atom_start..atom_end];

    switch (quantifier) {
        0 => {
            const item_end = (try matchPatternItem(state, source, atom, source_index, captures)) orelse return null;
            return matchPatternFrom(state, source, pattern, item_end, next_index, depth + 1, captures);
        },
        '?' => {
            if (try matchPatternItem(state, source, atom, source_index, captures)) |item_end| {
                if (item_end > source_index) {
                    if (try matchPatternFrom(state, source, pattern, item_end, next_index, depth + 1, captures)) |end| return end;
                }
            }
            return matchPatternFrom(state, source, pattern, source_index, next_index, depth + 1, captures);
        },
        '*', '+' => {
            var ends = std.ArrayList(usize).empty;
            defer ends.deinit(state.allocator);
            var end = source_index;
            while (ends.items.len < 4096) {
                const item_end = (try matchPatternItem(state, source, atom, end, captures)) orelse break;
                if (item_end == end) break;
                end = item_end;
                try ends.append(state.allocator, end);
            }
            if (quantifier == '+' and end == source_index) return null;
            var index = ends.items.len;
            while (index > 0) {
                index -= 1;
                try state.budget.checkInterrupt();
                if (try matchPatternFrom(state, source, pattern, ends.items[index], next_index, depth + 1, captures)) |matched_end| return matched_end;
            }
            if (quantifier == '*') return matchPatternFrom(state, source, pattern, source_index, next_index, depth + 1, captures);
            return null;
        },
        '-' => {
            var candidate = source_index;
            while (true) {
                try state.budget.checkInterrupt();
                if (try matchPatternFrom(state, source, pattern, candidate, next_index, depth + 1, captures)) |matched_end| return matched_end;
                const item_end = (try matchPatternItem(state, source, atom, candidate, captures)) orelse return null;
                if (item_end == candidate) return null;
                candidate = item_end;
            }
        },
        else => unreachable,
    }
}

fn validatePatternAtom(state: *State, pattern: []const u8, atom_start: usize, atom_end: usize) !void {
    if (pattern[atom_start] == '[' and atom_end == atom_start + 1) return state.failLibrary("malformed pattern (missing ']')");
    if (pattern[atom_start] != '%') return;
    if (atom_start + 1 >= pattern.len) return state.failLibrary("malformed pattern (ends with '%')");
    switch (pattern[atom_start + 1]) {
        'b' => if (atom_start + 3 >= pattern.len) return state.failLibrary("malformed pattern (missing arguments to '%b')"),
        'f' => if (atom_start + 2 >= pattern.len or pattern[atom_start + 2] != '[' or atom_end == atom_start + 1) return state.failLibrary("missing '[' after '%f' in pattern"),
        else => {},
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

fn matchPatternItem(state: *State, source: []const u8, atom: []const u8, source_index: usize, captures: CaptureState) !?usize {
    if (atom.len == 0) return null;
    if (atom.len == 1) {
        if (source_index >= source.len) return null;
        return if (atom[0] == '.' or atom[0] == source[source_index]) source_index + 1 else null;
    }
    if (atom[0] == '%') {
        if (atom.len >= 4 and atom[1] == 'b') return matchBalanced(source, source_index, atom[2], atom[3]);
        if (atom.len >= 4 and atom[1] == 'f' and atom[2] == '[') {
            const previous = if (source_index == 0) 0 else source[source_index - 1];
            const current = if (source_index < source.len) source[source_index] else 0;
            return if (!patternAtomMatches(atom[2..], previous) and patternAtomMatches(atom[2..], current)) source_index else null;
        }
        if (atom[1] == '0') {
            try invalidCaptureIndex(state, 0);
            unreachable;
        }
        if (atom[1] >= '1' and atom[1] <= '9') return matchCaptureReference(state, source, source_index, captures, atom[1] - '0');
        if (source_index >= source.len) return null;
        return if (patternEscapeMatches(atom[1], source[source_index])) source_index + 1 else null;
    }
    if (atom[0] == '[' and atom[atom.len - 1] == ']') {
        if (source_index >= source.len) return null;
        return if (patternAtomMatches(atom, source[source_index])) source_index + 1 else null;
    }
    return null;
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

fn matchCaptureReference(state: *State, source: []const u8, source_index: usize, captures: CaptureState, one_based: u8) !?usize {
    const index: usize = one_based - 1;
    if (index >= captures.count) {
        try invalidCaptureIndex(state, one_based);
        unreachable;
    }
    const range = switch (captures.slots[index]) {
        .range => |range| range,
        else => {
            try invalidCaptureIndex(state, one_based);
            unreachable;
        },
    };
    const captured = source[range.start..range.end];
    if (source_index + captured.len > source.len) return null;
    return if (std.mem.eql(u8, source[source_index .. source_index + captured.len], captured)) source_index + captured.len else null;
}

fn nextPatternAtom(pattern: []const u8, index: usize) usize {
    if (pattern[index] == '%' and index + 1 < pattern.len) {
        if (pattern[index + 1] == 'b' and index + 3 < pattern.len) return index + 4;
        if (pattern[index + 1] == 'f' and index + 2 < pattern.len and pattern[index + 2] == '[') return classAtomEnd(pattern, index + 2);
        return index + 2;
    }
    if (pattern[index] == '[') {
        const end = classAtomEnd(pattern, index);
        if (end > index) return end;
    }
    return index + 1;
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
    return state.failLibrary(try state.strings.intern(message.items));
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
