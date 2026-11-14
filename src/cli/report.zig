const std = @import("std");
const zlua = @import("zlua");
const term = @import("term.zig");
const highlight = @import("highlight.zig");

const errors = zlua.errors;
const frontend = zlua.frontend;
const runtime = zlua.runtime;
const Paint = term.Paint;
const State = runtime.State;
const Table = runtime.Table;

pub const Sources = struct {
    context: *anyopaque,
    /// The source of the chunk a traceback calls `name`, or null when it can't be read.
    lookup: *const fn (context: *anyopaque, name: []const u8) ?[]const u8,
};

/// Byte range within one source line.
const Mark = struct {
    start: usize,
    end: usize,
};

const Writer = struct {
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    paint: Paint,

    fn text(self: Writer, bytes: []const u8) !void {
        try self.out.appendSlice(self.allocator, bytes);
    }

    fn painted(self: Writer, role: term.Role, bytes: []const u8) !void {
        try self.text(self.paint.on(role));
        try self.text(bytes);
        try self.text(self.paint.off());
    }

    fn location(self: Writer, name: []const u8, line: ?usize, what: ?[]const u8) !void {
        try self.text("  ");
        try self.painted(.location, name);
        if (line) |number| {
            var buffer: [24]u8 = undefined;
            try self.text(", line ");
            try self.painted(.location, std.fmt.bufPrint(&buffer, "{d}", .{number}) catch unreachable);
        }
        if (what) |description| {
            try self.text(", in ");
            try self.painted(.location, description);
        }
        try self.text("\n");
    }

    fn sourceLine(self: Writer, line: []const u8, mark: ?Mark) !void {
        const indent = line.len - std.mem.trimStart(u8, line, " \t").len;
        const shown = std.mem.trimEnd(u8, line[indent..], " \t\r");
        if (shown.len == 0) return;
        try self.text("    ");
        try highlight.append(self.allocator, self.out, self.paint, shown);
        try self.text("\n");
        const range = mark orelse return;
        const start = @min(range.start -| indent, shown.len);
        const end = @min(@max(range.end -| indent, start), shown.len);
        try self.text("    ");
        try self.out.appendNTimes(self.allocator, ' ', term.textWidth(shown[0..start]));
        try self.text(self.paint.on(.caret));
        try self.out.appendNTimes(self.allocator, '^', @max(term.textWidth(shown[start..end]), 1));
        try self.text(self.paint.off());
        try self.text("\n");
    }

    fn labeled(self: Writer, role: term.Role, label: []const u8, message: []const u8) !void {
        try self.painted(role, label);
        try self.text(": ");
        if (role == .title) try self.painted(.message, message) else try self.text(message);
        try self.text("\n");
    }
};

/// `number` is 1-based.
fn lineAt(source: []const u8, number: usize) ?[]const u8 {
    var lines = std.mem.splitScalar(u8, source, '\n');
    var current: usize = 1;
    while (lines.next()) |line| : (current += 1) {
        if (current == number) return line;
    }
    return null;
}

fn diagnosticSpan(diagnostic: errors.Diagnostic) ?frontend.source.Span {
    return switch (diagnostic) {
        .syntax => |syntax| switch (syntax) {
            .unexpected => |unexpected| unexpected.token.span,
            .expected => |expected| expected.near.span,
            .expected_close => |expected| expected.near.span,
        },
        .resolve => |resolve| switch (resolve) {
            .duplicate_label => |err| err.span,
            .missing_label => |err| err.span,
            .goto_into_scope => |err| err.span,
            .break_outside_loop => |span| span,
            .assign_const => |err| err.span,
            .undeclared_global => |err| err.span,
            .invalid_close => |err| err.span,
            .unknown_attribute => |err| err.span,
            .invalid_assignment_target => |span| span,
            .invalid_environment => |err| err.span,
            .native_stack_overflow => null,
        },
        .compile, .argument => null,
    };
}

/// `name` is the chunk name as a traceback prints it.
pub fn appendLoadError(allocator: std.mem.Allocator, out: *std.ArrayList(u8), paint: Paint, name: []const u8, source: []const u8, diagnostic: errors.Diagnostic) !void {
    const writer: Writer = .{ .allocator = allocator, .out = out, .paint = paint };
    const chunk_name = try std.fmt.allocPrint(allocator, "={s}", .{name});
    defer allocator.free(chunk_name);
    const rendered = try errors.renderLoadDiagnostic(allocator, chunk_name, source, diagnostic);
    defer allocator.free(rendered);
    const message = if (std.mem.indexOf(u8, rendered, ": ")) |colon| rendered[colon + 2 ..] else rendered;

    if (diagnosticSpan(diagnostic)) |span| {
        var start = @min(span.start.offset, source.len);
        var end = @min(@max(span.end.offset, start), source.len);
        if (start == source.len) {
            while (start > 0 and std.mem.indexOfScalar(u8, " \t\r\n", source[start - 1]) != null) start -= 1;
            end = start;
        }
        const line_start = if (std.mem.lastIndexOfScalar(u8, source[0..start], '\n')) |newline| newline + 1 else 0;
        const line_end = std.mem.indexOfScalarPos(u8, source, start, '\n') orelse source.len;
        try writer.location(name, std.mem.count(u8, source[0..line_start], "\n") + 1, null);
        try writer.sourceLine(source[line_start..line_end], .{ .start = start - line_start, .end = @min(end, line_end) - line_start });
    }
    try writer.labeled(.title, "syntax error", message);
    if (try syntaxHint(allocator, source, diagnostic)) |hint| {
        defer allocator.free(hint);
        try writer.labeled(.hint, "hint", hint);
    }
}

fn syntaxHint(allocator: std.mem.Allocator, source: []const u8, diagnostic: errors.Diagnostic) !?[]u8 {
    const span = diagnosticSpan(diagnostic) orelse return null;
    const offset = @min(span.start.offset, source.len);
    const rest = source[offset..];
    const before = std.mem.trimEnd(u8, source[0..offset], " \t");
    const fixed: ?[]const u8 = if (std.mem.startsWith(u8, rest, "!="))
        "Lua writes not-equal as '~='"
    else if (std.mem.startsWith(u8, rest, "!"))
        "Lua writes logical negation as 'not'"
    else if (std.mem.startsWith(u8, rest, "&") and std.mem.endsWith(u8, before, "&"))
        "Lua writes logical and as 'and'"
    else if (std.mem.startsWith(u8, rest, "|") and std.mem.endsWith(u8, before, "|"))
        "Lua writes logical or as 'or'"
    else if (rest.len >= 2 and std.mem.indexOfScalar(u8, "+-*/%^", rest[0]) != null and rest[1] == '=')
        "Lua has no compound assignment; write 'x = x + 1'"
    else if (std.mem.startsWith(u8, rest, "..="))
        "Lua has no compound assignment; write 's = s .. t'"
    else if (std.mem.startsWith(u8, rest, "++") or std.mem.startsWith(u8, rest, "+ +"))
        "Lua has no increment operator; write 'x = x + 1'"
    else if (diagnostic == .syntax and diagnostic.syntax == .expected and rest.len != 0 and rest[0] == '=' and
        (std.mem.eql(u8, diagnostic.syntax.expected.expected, "'then'") or std.mem.eql(u8, diagnostic.syntax.expected.expected, "'do'")))
        "use '==' to compare"
    else
        null;
    if (fixed) |hint| return try allocator.dupe(u8, hint);
    if (diagnostic != .syntax) return null;
    const keyword = try misspelledKeyword(allocator, source, offset) orelse return null;
    return try std.fmt.allocPrint(allocator, "did you mean '{s}'?", .{keyword});
}

fn misspelledKeyword(allocator: std.mem.Allocator, source: []const u8, error_offset: usize) !?[]const u8 {
    const tokens = frontend.lex(allocator, source) catch |err| switch (err) {
        error.OutOfMemory => return err,
        else => return null,
    };
    defer allocator.free(tokens);
    var at: usize = 0;
    while (at < tokens.len and tokens[at].span.start.offset < error_offset) at += 1;

    var best: ?[]const u8 = null;
    var best_distance: usize = 3;
    var best_parses = false;
    var candidate = at -| 1;
    while (candidate <= at and candidate < tokens.len) : (candidate += 1) {
        const token = tokens[candidate];
        if (token.tag != .identifier) continue;
        for (highlight.keywords) |keyword| {
            const distance = editDistance(token.lexeme, keyword);
            if (distance > 2 or distance >= token.lexeme.len) continue;
            const patched = try std.mem.concat(allocator, u8, &.{ source[0..token.span.start.offset], keyword, source[token.span.end.offset..] });
            defer allocator.free(patched);
            var diagnostic: ?errors.Diagnostic = null;
            var parses = true;
            if (frontend.parseWithDiagnostic(allocator, patched, &diagnostic)) |parsed| {
                var tree = parsed;
                tree.deinit();
            } else |err| {
                if (err == error.OutOfMemory) return err;
                parses = false;
                const span = diagnosticSpan(diagnostic orelse continue) orelse continue;
                if (span.start.offset + token.lexeme.len <= error_offset + keyword.len) continue;
            }
            if (best_parses and !parses) continue;
            if (parses == best_parses and distance >= best_distance) continue;
            best = keyword;
            best_distance = distance;
            best_parses = parses;
        }
    }
    return best;
}

/// Counts a swap of neighbors as one edit and ignores ASCII case.
pub fn editDistance(a: []const u8, b: []const u8) usize {
    const max_len = 48;
    if (a.len > max_len or b.len > max_len) return max_len;
    var rows: [3][max_len + 1]usize = undefined;
    for (0..b.len + 1) |column| rows[1][column] = column;
    for (a, 1..) |a_byte, row| {
        const current = &rows[(row + 1) % 3];
        const previous = &rows[row % 3];
        const before_previous = &rows[(row + 2) % 3];
        current[0] = row;
        for (b, 1..) |b_byte, column| {
            const same = std.ascii.toLower(a_byte) == std.ascii.toLower(b_byte);
            var best = @min(previous[column] + 1, current[column - 1] + 1);
            best = @min(best, previous[column - 1] + @intFromBool(!same));
            if (row > 1 and column > 1 and std.ascii.toLower(a_byte) == std.ascii.toLower(b[column - 2]) and std.ascii.toLower(a[row - 2]) == std.ascii.toLower(b_byte)) {
                best = @min(best, before_previous[column - 2] + 1);
            }
            current[column] = best;
        }
    }
    return rows[(a.len + 1) % 3][b.len];
}

const Suggestion = struct {
    name: ?[]const u8 = null,
    distance: usize = std.math.maxInt(usize),

    fn offer(self: *Suggestion, wanted: []const u8, candidate: []const u8) void {
        if (std.mem.eql(u8, wanted, candidate)) return;
        const distance = editDistance(wanted, candidate);
        if (distance >= wanted.len or distance > @max(wanted.len / 3, 1)) return;
        if (distance > self.distance) return;
        if (distance == self.distance and !std.mem.lessThan(u8, candidate, self.name.?)) return;
        self.* = .{ .name = candidate, .distance = distance };
    }

    fn offerKeys(self: *Suggestion, wanted: []const u8, table: *const Table) void {
        for (table.entries()) |entry| {
            if (entry.key == .string and entry.value != .nil) self.offer(wanted, entry.key.string.bytes());
        }
    }
};

const Frame = struct {
    /// Chunk name as the traceback prints it, or the whole line for a note.
    name: []const u8,
    line: ?usize = null,
    what: ?[]const u8 = null,

    fn isNative(self: Frame) bool {
        return std.mem.eql(u8, self.name, "[C]");
    }

    /// The last name in a description such as `function 'string.rep'` or `local 'f'`.
    fn calledName(self: Frame) ?[]const u8 {
        const what = self.what orelse return null;
        const open = std.mem.indexOfScalar(u8, what, '\'') orelse return null;
        const close = std.mem.lastIndexOfScalar(u8, what, '\'') orelse return null;
        if (close <= open) return null;
        const quoted = what[open + 1 .. close];
        const separator = std.mem.lastIndexOfAny(u8, quoted, ".:") orelse return quoted;
        return quoted[separator + 1 ..];
    }
};

fn parseFrames(allocator: std.mem.Allocator, traceback: []const u8) ![]Frame {
    var frames = std.ArrayList(Frame).empty;
    errdefer frames.deinit(allocator);
    var lines = std.mem.splitScalar(u8, traceback, '\n');
    _ = lines.next();
    while (lines.next()) |raw| {
        const line = std.mem.trimStart(u8, raw, "\t");
        if (line.len == 0) continue;
        const split = std.mem.indexOf(u8, line, ": in ") orelse {
            try frames.append(allocator, .{ .name = line });
            continue;
        };
        var frame: Frame = .{ .name = line[0..split], .what = line[split + 5 ..] };
        if (std.mem.lastIndexOfScalar(u8, frame.name, ':')) |colon| {
            if (std.fmt.parseInt(usize, frame.name[colon + 1 ..], 10)) |number| {
                frame.line = number;
                frame.name = frame.name[0..colon];
            } else |_| {}
        }
        try frames.append(allocator, frame);
    }
    return frames.toOwnedSlice(allocator);
}

/// The name in a trailing note such as ` (global 'x')`, with its kind.
const Named = struct {
    kind: []const u8,
    name: []const u8,

    fn parse(message: []const u8) ?Named {
        if (!std.mem.endsWith(u8, message, "')")) return null;
        const open = std.mem.lastIndexOf(u8, message, " (") orelse return null;
        const note = message[open + 2 .. message.len - 2];
        const quote = std.mem.indexOf(u8, note, " '") orelse return null;
        return .{ .kind = note[0..quote], .name = note[quote + 2 ..] };
    }
};

const removed_functions = [_][2][]const u8{
    .{ "unpack", "use table.unpack" },
    .{ "loadstring", "use load" },
    .{ "setfenv", "Lua 5.2 replaced function environments with _ENV" },
    .{ "getfenv", "Lua 5.2 replaced function environments with _ENV" },
    .{ "getn", "use the length operator '#'" },
    .{ "pow", "use the '^' operator" },
    .{ "atan2", "use math.atan(y, x)" },
    .{ "log10", "use math.log(x, 10)" },
};

fn runtimeHint(allocator: std.mem.Allocator, state: *State, message: []const u8, line: ?[]const u8) !?[]u8 {
    if (std.mem.indexOf(u8, message, "a nil value") == null) return null;
    const named = Named.parse(message) orelse return null;
    const is_global = std.mem.eql(u8, named.kind, "global");
    const is_member = std.mem.eql(u8, named.kind, "field") or std.mem.eql(u8, named.kind, "method");
    if (!is_global and !is_member) return null;
    for (removed_functions) |removed| {
        if (std.mem.eql(u8, removed[0], named.name)) return try allocator.dupe(u8, removed[1]);
    }

    var suggestion: Suggestion = .{};
    if (is_global) {
        suggestion.offerKeys(named.name, state.global_table orelse return null);
        for (highlight.keywords) |keyword| suggestion.offer(named.name, keyword);
    } else {
        const owner = memberOwner(state, line orelse return null, named.name) orelse return null;
        suggestion.offerKeys(named.name, owner);
        if (owner.metatable) |metatable| {
            const index = metatable.getBytes("__index");
            if (index == .table) suggestion.offerKeys(named.name, index.table);
        }
    }
    const found = suggestion.name orelse return null;
    return try std.fmt.allocPrint(allocator, "did you mean '{s}'?", .{found});
}

/// The table that `line` reads `member` from, when it is a global table or a string.
fn memberOwner(state: *State, line: []const u8, member: []const u8) ?*const Table {
    var tokens: [4]highlight.Token = undefined;
    var count: usize = 0;
    var found: ?[4]highlight.Token = null;
    var found_count: usize = 0;
    var scanner: highlight.Scanner = .{ .source = line };
    while (scanner.next()) |token| {
        if (token.kind == .space or token.kind == .comment) continue;
        if ((token.kind == .identifier or token.kind == .builtin) and std.mem.eql(u8, token.text(line), member)) {
            if (found != null) return null;
            found = tokens;
            found_count = count;
        }
        if (count == tokens.len) {
            std.mem.copyForwards(highlight.Token, tokens[0 .. tokens.len - 1], tokens[1..]);
            count -= 1;
        }
        tokens[count] = token;
        count += 1;
    }
    const before = (found orelse return null)[0..found_count];
    if (before.len < 2) return null;
    const separator = before[before.len - 1].text(line);
    if (!std.mem.eql(u8, separator, ".") and !std.mem.eql(u8, separator, ":")) return null;
    const receiver = before[before.len - 2];
    const receiver_text = receiver.text(line);
    const string_methods: ?*const Table = if (state.string_metatable) |metatable| blk: {
        const index = metatable.getBytes("__index");
        break :blk if (index == .table) index.table else null;
    } else null;
    switch (receiver.kind) {
        .string => return string_methods,
        .identifier, .builtin => {
            if (before.len >= 3) {
                const earlier = before[before.len - 3].text(line);
                if (std.mem.eql(u8, earlier, ".") or std.mem.eql(u8, earlier, ":")) return null;
            }
            return switch (state.getGlobalValue(receiver_text)) {
                .table => |table| table,
                .string => string_methods,
                else => null,
            };
        },
        .symbol => {
            if (!std.mem.eql(u8, receiver_text, ")") or before.len < 3) return null;
            return if (before[before.len - 3].kind == .string) string_methods else null;
        },
        else => return null,
    }
}

pub const RuntimeError = struct {
    message: []const u8,
    /// A `debug.traceback` result that starts at the `stack traceback:` line.
    traceback: ?[]const u8 = null,
};

pub fn appendRuntimeError(allocator: std.mem.Allocator, out: *std.ArrayList(u8), paint: Paint, sources: Sources, state: *State, failure: RuntimeError) !void {
    const writer: Writer = .{ .allocator = allocator, .out = out, .paint = paint };
    const frames = try parseFrames(allocator, failure.traceback orelse "");
    defer allocator.free(frames);

    var message = failure.message;
    var failed_frame: ?usize = null;
    for (frames, 0..) |frame, index| {
        const line = frame.line orelse continue;
        var buffer: [24]u8 = undefined;
        const suffix = std.fmt.bufPrint(&buffer, ":{d}: ", .{line}) catch unreachable;
        if (!std.mem.startsWith(u8, message, frame.name) or !std.mem.startsWith(u8, message[frame.name.len..], suffix)) continue;
        message = message[frame.name.len + suffix.len ..];
        failed_frame = index;
        break;
    }

    var innermost: usize = 0;
    if (frames.len > 1 and frames[0].isNative()) {
        if (frames[0].calledName()) |name| {
            if (std.mem.eql(u8, name, "error")) innermost = 1;
        }
    }

    var failed_line: ?[]const u8 = null;
    if (frames.len > innermost) try writer.text("Traceback (most recent call last):\n");
    var index = frames.len;
    while (index > innermost) {
        index -= 1;
        const frame = frames[index];
        if (frame.what == null) {
            try writer.text("  ");
            try writer.painted(.dim, frame.name);
            try writer.text("\n");
            continue;
        }
        try writer.location(frame.name, frame.line, frame.what);
        const line = lineAt(sources.lookup(sources.context, frame.name) orelse continue, frame.line orelse continue) orelse continue;
        if (failed_frame == index) failed_line = line;

        var marked: ?[]const u8 = null;
        if (failed_frame == index) {
            if (Named.parse(message)) |named| {
                marked = named.name;
            } else if (std.mem.startsWith(u8, message, "bad argument #")) {
                const open = std.mem.indexOfScalar(u8, message, '\'');
                const close = if (open) |start| std.mem.indexOfScalarPos(u8, message, start + 1, '\'') else null;
                if (close) |end| marked = message[open.? + 1 .. end];
            }
        }
        if (marked == null and index > 0) marked = frames[index - 1].calledName();
        const token = if (marked) |name| highlight.uniqueIdentifier(line, name) else null;
        try writer.sourceLine(line, if (token) |found| .{ .start = found.start, .end = found.end } else null);
    }

    try writer.labeled(.title, "error", message);
    if (try runtimeHint(allocator, state, message, failed_line)) |hint| {
        defer allocator.free(hint);
        try writer.labeled(.hint, "hint", hint);
    }
}

const TestSources = struct {
    name: []const u8,
    text: []const u8,

    fn lookup(context: *anyopaque, name: []const u8) ?[]const u8 {
        const self: *TestSources = @ptrCast(@alignCast(context));
        return if (std.mem.eql(u8, name, self.name)) self.text else null;
    }
};

fn expectLoadError(source: []const u8, expected: []const u8) !void {
    const allocator = std.testing.allocator;
    var diagnostic: ?errors.Diagnostic = null;
    if (frontend.parseWithDiagnostic(allocator, source, &diagnostic)) |parsed| {
        var tree = parsed;
        tree.deinit();
        return error.TestExpectedSyntaxError;
    } else |_| {}
    var out = std.ArrayList(u8).empty;
    defer out.deinit(allocator);
    try appendLoadError(allocator, &out, .{}, "input#1", source, diagnostic.?);
    try std.testing.expectEqualStrings(expected, out.items);
}

test "syntax errors point at the token" {
    try expectLoadError("local x = = 2",
        \\  input#1, line 1
        \\    local x = = 2
        \\              ^
        \\syntax error: unexpected symbol near '='
        \\
    );
    try expectLoadError("x = 1\n  y = (2 +\n",
        \\  input#1, line 2
        \\    y = (2 +
        \\            ^
        \\syntax error: unexpected symbol near <eof>
        \\
    );
}

test "syntax errors explain operators from other languages" {
    const cases = [_][2][]const u8{
        .{ "if a != b then end", "Lua writes not-equal as '~='" },
        .{ "x = a && b", "Lua writes logical and as 'and'" },
        .{ "x = a || b", "Lua writes logical or as 'or'" },
        .{ "x += 1", "Lua has no compound assignment; write 'x = x + 1'" },
        .{ "if x = 1 then end", "use '==' to compare" },
        .{ "fucntion f() end", "did you mean 'function'?" },
        .{ "whlie true do end", "did you mean 'while'?" },
        .{ "if x thn y() end", "did you mean 'then'?" },
        .{ "for i = 1, 3 od print(i) end", "did you mean 'do'?" },
    };
    for (cases) |case| {
        const allocator = std.testing.allocator;
        var diagnostic: ?errors.Diagnostic = null;
        if (frontend.parseWithDiagnostic(allocator, case[0], &diagnostic)) |parsed| {
            var tree = parsed;
            tree.deinit();
            return error.TestExpectedSyntaxError;
        } else |_| {}
        const hint = try syntaxHint(allocator, case[0], diagnostic.?) orelse {
            std.debug.print("no hint for: {s}\n", .{case[0]});
            return error.TestExpectedHint;
        };
        defer allocator.free(hint);
        try std.testing.expectEqualStrings(case[1], hint);
    }
}

test "valid identifiers near an error are not called misspelled keywords" {
    const allocator = std.testing.allocator;
    for ([_][]const u8{ "fo = = 1", "x = 1 ende", "local dog cat" }) |source| {
        var diagnostic: ?errors.Diagnostic = null;
        if (frontend.parseWithDiagnostic(allocator, source, &diagnostic)) |parsed| {
            var tree = parsed;
            tree.deinit();
            return error.TestExpectedSyntaxError;
        } else |_| {}
        try std.testing.expect(try syntaxHint(allocator, source, diagnostic.?) == null);
    }
}

test "edit distance counts swaps as one edit" {
    try std.testing.expectEqual(@as(usize, 0), editDistance("Print", "print"));
    try std.testing.expectEqual(@as(usize, 1), editDistance("pritn", "print"));
    try std.testing.expectEqual(@as(usize, 1), editDistance("prin", "print"));
    try std.testing.expectEqual(@as(usize, 2), editDistance("insrt", "inserts"));
    try std.testing.expectEqual(@as(usize, 3), editDistance("abc", "xyz"));
}

fn expectRuntimeError(source: []const u8, expected: []const u8) !void {
    const allocator = std.testing.allocator;
    var state = try State.initWithOptions(allocator, .{ .stdlib = .safe });
    defer state.deinit();
    var traceback: ?[]u8 = null;
    defer if (traceback) |text| allocator.free(text);
    const loaded = try runtime.load.loadSourceAsClosureNamed(&state, source, "=input#1");
    if (runtime.entry.callFunctionHandled(&state, loaded, &.{}, .{ .traceback = &traceback })) |results| {
        allocator.free(results);
        return error.TestExpectedRuntimeError;
    } else |_| {}
    var message = std.ArrayList(u8).empty;
    defer message.deinit(allocator);
    try runtime.appendErrorValue(allocator, &message, state.currentErrorValue());

    var sources: TestSources = .{ .name = "input#1", .text = source };
    var out = std.ArrayList(u8).empty;
    defer out.deinit(allocator);
    try appendRuntimeError(allocator, &out, .{}, .{ .context = &sources, .lookup = TestSources.lookup }, &state, .{ .message = message.items, .traceback = traceback });
    try std.testing.expectEqualStrings(expected, out.items);
}

test "runtime errors show the failing line and a suggestion" {
    try expectRuntimeError("pritn('hi')",
        \\Traceback (most recent call last):
        \\  input#1, line 1, in main chunk
        \\    pritn('hi')
        \\    ^^^^^
        \\error: attempt to call a nil value (global 'pritn')
        \\hint: did you mean 'print'?
        \\
    );
    try expectRuntimeError("local s = 'x'\nreturn string.uper(s)",
        \\Traceback (most recent call last):
        \\  input#1, line 2, in main chunk
        \\    return string.uper(s)
        \\                  ^^^^
        \\error: attempt to call a nil value (field 'uper')
        \\hint: did you mean 'upper'?
        \\
    );
    try expectRuntimeError("return ('x'):uper()",
        \\Traceback (most recent call last):
        \\  input#1, line 1, in main chunk
        \\    return ('x'):uper()
        \\                 ^^^^
        \\error: attempt to call a nil value (method 'uper')
        \\hint: did you mean 'upper'?
        \\
    );
    try expectRuntimeError("return unpack({1})",
        \\Traceback (most recent call last):
        \\  input#1, line 1, in main chunk
        \\    return unpack({1})
        \\           ^^^^^^
        \\error: attempt to call a nil value (global 'unpack')
        \\hint: use table.unpack
        \\
    );
}

test "runtime errors list frames from the outermost call" {
    try expectRuntimeError("local function check(v)\n  error('bad value: ' .. v)\nend\ncheck(3)",
        \\Traceback (most recent call last):
        \\  input#1, line 4, in main chunk
        \\    check(3)
        \\    ^^^^^
        \\  input#1, line 2, in local 'check'
        \\    error('bad value: ' .. v)
        \\    ^^^^^
        \\error: bad value: 3
        \\
    );
    try expectRuntimeError("return string.rep('x', {})",
        \\Traceback (most recent call last):
        \\  input#1, line 1, in main chunk
        \\    return string.rep('x', {})
        \\                  ^^^
        \\  [C], in field 'rep'
        \\error: bad argument #2 to 'rep' (number expected, got table)
        \\
    );
}
