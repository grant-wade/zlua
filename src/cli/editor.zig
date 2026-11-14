const std = @import("std");
const term = @import("term.zig");
const highlight = @import("highlight.zig");

const Dir = std.Io.Dir;
const Paint = term.Paint;

const indent_width = 2;
const max_history_entries = 1000;
const max_history_bytes = 4 << 20;
const max_menu_rows = 8;

pub const Completion = struct {
    /// Byte offset in the source where every candidate starts.
    start: usize = 0,
    /// Valid until the next call to the completer.
    candidates: []const []const u8 = &.{},
};

pub const Hooks = struct {
    context: *anyopaque,
    /// Whether Enter submits `source`.
    isComplete: *const fn (context: *anyopaque, source: []const u8) bool,
    complete: *const fn (context: *anyopaque, source: []const u8, cursor: usize) Completion,
};

pub const Result = union(enum) {
    /// Valid until the next `readLine`.
    line: []const u8,
    eof,
    interrupted,
};

pub const History = struct {
    allocator: std.mem.Allocator,
    entries: std.ArrayList([]u8) = .empty,

    pub fn deinit(self: *History) void {
        for (self.entries.items) |entry| self.allocator.free(entry);
        self.entries.deinit(self.allocator);
    }

    pub fn add(self: *History, text: []const u8) !void {
        if (std.mem.trim(u8, text, " \t\n").len == 0) return;
        const entries = self.entries.items;
        if (entries.len != 0 and std.mem.eql(u8, entries[entries.len - 1], text)) return;
        const copy = try self.allocator.dupe(u8, text);
        errdefer self.allocator.free(copy);
        try self.entries.append(self.allocator, copy);
    }

    pub fn load(self: *History, io: std.Io, path: []const u8) !void {
        const bytes = try Dir.cwd().readFileAlloc(io, path, self.allocator, .limited(max_history_bytes));
        defer self.allocator.free(bytes);
        try self.parse(bytes);
    }

    pub fn save(self: *const History, io: std.Io, path: []const u8) !void {
        const bytes = try self.serialize();
        defer self.allocator.free(bytes);
        try Dir.cwd().writeFile(io, .{ .sub_path = path, .data = bytes });
    }

    fn serialize(self: *const History) ![]u8 {
        var out = std.ArrayList(u8).empty;
        errdefer out.deinit(self.allocator);
        const entries = self.entries.items;
        for (entries[entries.len -| max_history_entries..]) |entry| {
            for (entry) |byte| switch (byte) {
                '\n' => try out.appendSlice(self.allocator, "\\n"),
                '\\' => try out.appendSlice(self.allocator, "\\\\"),
                else => try out.append(self.allocator, byte),
            };
            try out.append(self.allocator, '\n');
        }
        return out.toOwnedSlice(self.allocator);
    }

    fn parse(self: *History, bytes: []const u8) !void {
        var entry = std.ArrayList(u8).empty;
        defer entry.deinit(self.allocator);
        var lines = std.mem.splitScalar(u8, bytes, '\n');
        while (lines.next()) |line| {
            entry.clearRetainingCapacity();
            var index: usize = 0;
            while (index < line.len) : (index += 1) {
                if (line[index] == '\\' and index + 1 < line.len) {
                    index += 1;
                    try entry.append(self.allocator, if (line[index] == 'n') '\n' else line[index]);
                } else {
                    try entry.append(self.allocator, line[index]);
                }
            }
            if (isEditable(entry.items)) try self.add(entry.items);
        }
    }
};

fn isEditable(text: []const u8) bool {
    if (!std.unicode.utf8ValidateSlice(text)) return false;
    for (text) |byte| if (byte < 0x20 and byte != '\n' and byte != '\t') return false;
    return std.mem.indexOfScalar(u8, text, 0x7f) == null;
}

const Key = enum {
    text,
    paste,
    enter,
    newline,
    tab,
    backspace,
    delete,
    left,
    right,
    up,
    down,
    home,
    end,
    word_left,
    word_right,
    delete_word_back,
    delete_word_forward,
    kill_to_end,
    kill_to_start,
    yank,
    clear_screen,
    interrupt,
    eof_or_delete,
    suspend_process,
    search,
    cancel,
    eof,
    ignore,
};

const Search = struct {
    query: std.ArrayList(u8) = .empty,
    /// Index of the matching history entry.
    match: ?usize = null,
};

const Line = struct {
    start: usize,
    end: usize,
    rows: usize,
};

const Position = struct {
    row: usize = 0,
    col: usize = 0,
};

pub const Editor = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    in: term.Input,
    out: *std.Io.Writer,
    paint: Paint,
    hooks: Hooks,
    history: History,
    prompt: []const u8 = "> ",
    continuation: []const u8 = ">> ",
    /// Used in place of the terminal's size.
    fixed_size: ?term.Size = null,
    raw_mode: bool = true,
    /// Start each read on an empty line, marking output that had no final line break.
    fresh_line: bool = false,

    buffer: std.ArrayList(u8) = .empty,
    /// Byte offset into `buffer`, always on a code point boundary.
    cursor: usize = 0,
    /// Index into the history, or its length while editing the draft.
    history_index: usize = 0,
    draft: std.ArrayList(u8) = .empty,
    killed: std.ArrayList(u8) = .empty,
    menu: std.ArrayList(u8) = .empty,
    pasted: std.ArrayList(u8) = .empty,
    frame: std.ArrayList(u8) = .empty,
    lines: std.ArrayList(Line) = .empty,
    search: ?Search = null,
    typed: [4]u8 = undefined,
    typed_len: usize = 0,
    /// Screen rows between the first drawn row and the cursor.
    cursor_row: usize = 0,

    pub fn init(allocator: std.mem.Allocator, io: std.Io, in: term.Input, out: *std.Io.Writer, paint: Paint, hooks: Hooks) Editor {
        return .{ .allocator = allocator, .io = io, .in = in, .out = out, .paint = paint, .hooks = hooks, .history = .{ .allocator = allocator } };
    }

    pub fn deinit(self: *Editor) void {
        const allocator = self.allocator;
        self.history.deinit();
        self.buffer.deinit(allocator);
        self.draft.deinit(allocator);
        self.killed.deinit(allocator);
        self.menu.deinit(allocator);
        self.pasted.deinit(allocator);
        self.frame.deinit(allocator);
        self.lines.deinit(allocator);
        if (self.search) |*search| search.query.deinit(allocator);
    }

    pub fn readLine(self: *Editor) !Result {
        self.buffer.clearRetainingCapacity();
        self.menu.clearRetainingCapacity();
        self.cursor = 0;
        self.cursor_row = 0;
        self.history_index = self.history.entries.items.len;
        self.endSearch();

        const raw = if (self.raw_mode) term.RawMode.enter() else null;
        defer if (raw) |mode| mode.leave();
        if (self.fresh_line) try self.startFreshLine();
        try self.out.writeAll("\x1b[?2004h");
        defer {
            self.out.writeAll("\x1b[?2004l") catch {};
            self.out.flush() catch {};
        }

        try self.draw(.live);
        while (true) {
            const key = self.readKey() catch |err| switch (err) {
                error.EndOfStream => Key.eof,
                else => return err,
            };
            self.menu.clearRetainingCapacity();
            if (self.search != null and try self.handleSearchKey(key)) {
                try self.draw(.live);
                continue;
            }
            switch (key) {
                .text => try self.insert(self.typed[0..self.typed_len]),
                .paste => try self.insert(self.pasted.items),
                .enter => {
                    const on_last_line = self.lineEnd(self.cursor) == self.buffer.items.len;
                    if (on_last_line and self.hooks.isComplete(self.hooks.context, self.buffer.items)) return self.submit();
                    try self.insertNewline();
                },
                .newline => try self.insertNewline(),
                .tab => try self.tab(),
                .backspace => self.backspace(),
                .delete => self.remove(self.cursor, self.nextBoundary(self.cursor)),
                .left => self.cursor = self.previousBoundary(self.cursor),
                .right => self.cursor = self.nextBoundary(self.cursor),
                .up => try self.moveVertically(.up),
                .down => try self.moveVertically(.down),
                .home => self.cursor = self.lineStart(self.cursor),
                .end => self.cursor = self.lineEnd(self.cursor),
                .word_left => self.cursor = self.wordLeft(self.cursor),
                .word_right => self.cursor = self.wordRight(self.cursor),
                .delete_word_back => try self.kill(self.wordLeft(self.cursor), self.cursor),
                .delete_word_forward => try self.kill(self.cursor, self.wordRight(self.cursor)),
                .kill_to_end => {
                    const end = self.lineEnd(self.cursor);
                    try self.kill(self.cursor, if (end == self.cursor) self.nextBoundary(end) else end);
                },
                .kill_to_start => try self.kill(self.lineStart(self.cursor), self.cursor),
                .yank => try self.insert(self.killed.items),
                .clear_screen => {
                    try self.out.writeAll("\x1b[H\x1b[2J");
                    self.cursor_row = 0;
                },
                .interrupt => {
                    try self.draw(.final);
                    self.buffer.clearRetainingCapacity();
                    return .interrupted;
                },
                .eof_or_delete => {
                    if (self.buffer.items.len == 0) return self.finishEof();
                    self.remove(self.cursor, self.nextBoundary(self.cursor));
                },
                .suspend_process => if (!term.RawMode.can_suspend) {
                    if (self.buffer.items.len == 0) return self.finishEof();
                } else if (raw) |mode| {
                    try self.draw(.final);
                    try self.out.flush();
                    mode.suspendProcess();
                },
                .eof => return self.finishEof(),
                .search => self.search = .{},
                .cancel, .ignore => {},
            }
            try self.draw(.live);
        }
    }

    fn startFreshLine(self: *Editor) !void {
        try self.out.print("{s}%{s}", .{ self.paint.on(.mark), self.paint.off() });
        try self.out.splatByteAll(' ', self.size().cols - 1);
        try self.out.writeAll("\r");
    }

    fn submit(self: *Editor) !Result {
        try self.draw(.final);
        try self.history.add(self.buffer.items);
        return .{ .line = self.buffer.items };
    }

    fn finishEof(self: *Editor) !Result {
        try self.draw(.final);
        return .eof;
    }

    fn readKey(self: *Editor) !Key {
        const byte = try self.in.takeByte();
        return switch (byte) {
            '\r', '\n' => .enter,
            '\t' => .tab,
            0x7f, 0x08 => .backspace,
            0x01 => .home,
            0x02 => .left,
            0x03 => .interrupt,
            0x04 => .eof_or_delete,
            0x05 => .end,
            0x06 => .right,
            0x07 => .cancel,
            0x0b => .kill_to_end,
            0x0c => .clear_screen,
            0x0e => .down,
            0x10 => .up,
            0x12 => .search,
            0x15 => .kill_to_start,
            0x17 => .delete_word_back,
            0x19 => .yank,
            0x1a => .suspend_process,
            0x1b => self.readEscape(),
            0x00, 0x0f, 0x11, 0x13, 0x14, 0x16, 0x18, 0x1c...0x1f => .ignore,
            else => self.readText(byte),
        };
    }

    fn readText(self: *Editor, first: u8) !Key {
        const len = std.unicode.utf8ByteSequenceLength(first) catch return .ignore;
        self.typed[0] = first;
        for (self.typed[1..len]) |*slot| {
            const next = try self.in.peekByte();
            if (next & 0xc0 != 0x80) return .ignore;
            slot.* = try self.in.takeByte();
        }
        if (!std.unicode.utf8ValidateSlice(self.typed[0..len])) return .ignore;
        self.typed_len = len;
        return .text;
    }

    fn readEscape(self: *Editor) !Key {
        const introducer = try self.in.takeByte();
        switch (introducer) {
            '[' => {},
            'O' => return switch (try self.in.takeByte()) {
                'A' => .up,
                'B' => .down,
                'C' => .right,
                'D' => .left,
                'H' => .home,
                'F' => .end,
                else => .ignore,
            },
            '\r', '\n' => return .newline,
            0x7f, 0x08 => return .delete_word_back,
            'b' => return .word_left,
            'f' => return .word_right,
            'd' => return .delete_word_forward,
            else => return .ignore,
        }
        var parameters: [16]u8 = undefined;
        var count: usize = 0;
        const final = while (true) {
            const byte = try self.in.takeByte();
            if (byte >= 0x40 and byte <= 0x7e) break byte;
            if (count < parameters.len) {
                parameters[count] = byte;
                count += 1;
            }
        };
        const params = parameters[0..count];
        const modified = std.mem.endsWith(u8, params, ";5") or std.mem.endsWith(u8, params, ";3");
        return switch (final) {
            'A' => .up,
            'B' => .down,
            'C' => if (modified) .word_right else .right,
            'D' => if (modified) .word_left else .left,
            'H' => .home,
            'F' => .end,
            '~' => if (eql(params, "200"))
                self.readPaste()
            else if (eql(params, "1") or eql(params, "7"))
                .home
            else if (eql(params, "4") or eql(params, "8"))
                .end
            else if (eql(params, "3"))
                .delete
            else if (eql(params, "3;5") or eql(params, "3;3"))
                .delete_word_forward
            else
                .ignore,
            else => .ignore,
        };
    }

    fn readPaste(self: *Editor) !Key {
        const terminator = "\x1b[201~";
        var raw = std.ArrayList(u8).empty;
        defer raw.deinit(self.allocator);
        while (!std.mem.endsWith(u8, raw.items, terminator)) {
            const byte = self.in.takeByte() catch |err| switch (err) {
                error.EndOfStream => break,
                error.ReadFailed => return err,
            };
            try raw.append(self.allocator, byte);
        }
        const text = if (std.mem.endsWith(u8, raw.items, terminator)) raw.items[0 .. raw.items.len - terminator.len] else raw.items;

        self.pasted.clearRetainingCapacity();
        var index: usize = 0;
        while (index < text.len) {
            const byte = text[index];
            const len = std.unicode.utf8ByteSequenceLength(byte) catch 1;
            if (byte == '\r') {
                try self.pasted.append(self.allocator, '\n');
                if (index + 1 < text.len and text[index + 1] == '\n') index += 1;
            } else if (byte == '\n' or byte == '\t') {
                try self.pasted.append(self.allocator, byte);
            } else if (byte >= 0x20 and byte != 0x7f and index + len <= text.len and std.unicode.utf8ValidateSlice(text[index..][0..len])) {
                try self.pasted.appendSlice(self.allocator, text[index..][0..len]);
                index += len - 1;
            }
            index += 1;
        }
        return .paste;
    }

    /// Returns false when `key` ends the search and still needs handling.
    fn handleSearchKey(self: *Editor, key: Key) !bool {
        const search = &self.search.?;
        const newest = self.history.entries.items.len;
        switch (key) {
            .text => {
                try search.query.appendSlice(self.allocator, self.typed[0..self.typed_len]);
                search.match = self.findMatch(if (search.match) |match| match + 1 else newest);
            },
            .backspace => {
                const query = search.query.items;
                var len = query.len;
                while (len > 0) {
                    len -= 1;
                    if (query[len] & 0xc0 != 0x80) break;
                }
                search.query.items.len = len;
                search.match = self.findMatch(newest);
            },
            .search => if (self.findMatch(search.match orelse newest)) |older| {
                search.match = older;
            },
            .cancel, .interrupt => self.endSearch(),
            else => {
                if (search.match) |match| {
                    self.history_index = match;
                    try self.setBuffer(self.history.entries.items[match]);
                }
                self.endSearch();
                return key == .enter;
            },
        }
        return true;
    }

    fn findMatch(self: *const Editor, before: usize) ?usize {
        const query = self.search.?.query.items;
        var index = before;
        while (index > 0) {
            index -= 1;
            if (std.mem.indexOf(u8, self.history.entries.items[index], query) != null) return index;
        }
        return null;
    }

    fn endSearch(self: *Editor) void {
        if (self.search) |*search| search.query.deinit(self.allocator);
        self.search = null;
    }

    fn insert(self: *Editor, text: []const u8) !void {
        try self.buffer.insertSlice(self.allocator, self.cursor, text);
        self.cursor += text.len;
    }

    fn remove(self: *Editor, start: usize, end: usize) void {
        self.buffer.replaceRangeAssumeCapacity(start, end - start, &.{});
        self.cursor = start;
    }

    fn kill(self: *Editor, start: usize, end: usize) !void {
        if (start == end) return;
        self.killed.clearRetainingCapacity();
        try self.killed.appendSlice(self.allocator, self.buffer.items[start..end]);
        self.remove(start, end);
    }

    fn setBuffer(self: *Editor, text: []const u8) !void {
        self.buffer.clearRetainingCapacity();
        try self.buffer.appendSlice(self.allocator, text);
        self.cursor = text.len;
    }

    fn insertNewline(self: *Editor) !void {
        const start = self.lineStart(self.cursor);
        const before = self.buffer.items[start..self.cursor];
        var indent: usize = 0;
        while (indent < before.len and before[indent] == ' ') indent += 1;
        if (highlight.opensBlock(before)) indent += indent_width;
        try self.insert("\n");
        for (0..indent) |_| try self.insert(" ");
    }

    fn backspace(self: *Editor) void {
        if (self.cursor == 0) return;
        const before = self.buffer.items[self.lineStart(self.cursor)..self.cursor];
        if (before.len != 0 and std.mem.allEqual(u8, before, ' ')) {
            const count = (before.len - 1) % indent_width + 1;
            return self.remove(self.cursor - count, self.cursor);
        }
        self.remove(self.previousBoundary(self.cursor), self.cursor);
    }

    fn tab(self: *Editor) !void {
        const before = self.buffer.items[self.lineStart(self.cursor)..self.cursor];
        if (std.mem.allEqual(u8, before, ' ')) {
            return self.insert(("  ")[0 .. indent_width - before.len % indent_width]);
        }
        const completion = self.hooks.complete(self.hooks.context, self.buffer.items, self.cursor);
        const candidates = completion.candidates;
        if (candidates.len == 0 or completion.start > self.cursor) return;
        var common = candidates[0];
        for (candidates[1..]) |candidate| common = common[0 .. std.mem.indexOfDiff(u8, common, candidate) orelse common.len];
        const typed_len = self.cursor - completion.start;
        if (common.len > typed_len) {
            try self.buffer.replaceRange(self.allocator, completion.start, typed_len, common);
            self.cursor = completion.start + common.len;
            return;
        }
        if (candidates.len > 1) try self.buildMenu(candidates);
    }

    fn buildMenu(self: *Editor, candidates: []const []const u8) !void {
        const width = self.size().cols;
        var widest: usize = 0;
        for (candidates) |candidate| widest = @max(widest, term.textWidth(candidate));
        const column = widest + 2;
        const per_row = @max(1, (width - 1) / column);
        const shown = @min(candidates.len, per_row * max_menu_rows);
        for (candidates[0..shown], 0..) |candidate, index| {
            if (index != 0 and index % per_row == 0) try self.menu.append(self.allocator, '\n');
            try self.menu.appendSlice(self.allocator, candidate);
            if ((index + 1) % per_row != 0 and index + 1 != shown) {
                try self.menu.appendNTimes(self.allocator, ' ', column - term.textWidth(candidate));
            }
        }
        if (shown < candidates.len) {
            var note: [32]u8 = undefined;
            try self.menu.appendSlice(self.allocator, std.fmt.bufPrint(&note, "\n... {d} more", .{candidates.len - shown}) catch unreachable);
        }
    }

    fn moveVertically(self: *Editor, direction: enum { up, down }) !void {
        const items = self.buffer.items;
        const start = self.lineStart(self.cursor);
        const column = term.textWidth(items[start..self.cursor]);
        const entries = self.history.entries.items;
        switch (direction) {
            .up => if (start > 0) {
                self.cursor = self.offsetAtColumn(self.lineStart(start - 1), column);
            } else if (self.history_index > 0) {
                if (self.history_index == entries.len) {
                    self.draft.clearRetainingCapacity();
                    try self.draft.appendSlice(self.allocator, items);
                }
                self.history_index -= 1;
                try self.setBuffer(entries[self.history_index]);
            },
            .down => {
                const end = self.lineEnd(self.cursor);
                if (end < items.len) {
                    self.cursor = self.offsetAtColumn(end + 1, column);
                } else if (self.history_index < entries.len) {
                    self.history_index += 1;
                    try self.setBuffer(if (self.history_index == entries.len) self.draft.items else entries[self.history_index]);
                }
            },
        }
    }

    fn offsetAtColumn(self: *const Editor, line_start: usize, column: usize) usize {
        const end = self.lineEnd(line_start);
        var offset = line_start;
        var width: usize = 0;
        while (offset < end) {
            const next = self.nextBoundary(offset);
            width += term.textWidth(self.buffer.items[offset..next]);
            if (width > column) break;
            offset = next;
        }
        return offset;
    }

    fn lineStart(self: *const Editor, offset: usize) usize {
        const newline = std.mem.lastIndexOfScalar(u8, self.buffer.items[0..offset], '\n') orelse return 0;
        return newline + 1;
    }

    fn lineEnd(self: *const Editor, offset: usize) usize {
        return std.mem.indexOfScalarPos(u8, self.buffer.items, offset, '\n') orelse self.buffer.items.len;
    }

    fn codePointStart(self: *const Editor, offset: usize) usize {
        var start = offset - 1;
        while (start > 0 and self.buffer.items[start] & 0xc0 == 0x80) start -= 1;
        return start;
    }

    fn widthAt(self: *const Editor, offset: usize) usize {
        const items = self.buffer.items;
        if (items[offset] == '\n') return 1;
        return term.textWidth(items[offset..][0..term.sequenceLength(items[offset])]);
    }

    fn previousBoundary(self: *const Editor, offset: usize) usize {
        var start = offset;
        while (start > 0) {
            start = self.codePointStart(start);
            if (self.widthAt(start) != 0) break;
        }
        return start;
    }

    fn nextBoundary(self: *const Editor, offset: usize) usize {
        const items = self.buffer.items;
        if (offset >= items.len) return items.len;
        var end = offset + term.sequenceLength(items[offset]);
        while (end < items.len and self.widthAt(end) == 0) end += term.sequenceLength(items[end]);
        return @min(end, items.len);
    }

    fn wordLeft(self: *const Editor, offset: usize) usize {
        const items = self.buffer.items;
        var start = offset;
        while (start > 0 and !isWordByte(items[start - 1])) start -= 1;
        while (start > 0 and isWordByte(items[start - 1])) start -= 1;
        return start;
    }

    fn wordRight(self: *const Editor, offset: usize) usize {
        const items = self.buffer.items;
        var end = offset;
        while (end < items.len and !isWordByte(items[end])) end += 1;
        while (end < items.len and isWordByte(items[end])) end += 1;
        return end;
    }

    fn size(self: *const Editor) term.Size {
        const actual = self.fixed_size orelse term.windowSize(self.io);
        return .{ .cols = @max(actual.cols, 16), .rows = @max(actual.rows, 4) };
    }

    fn promptFor(self: *const Editor, line_index: usize) []const u8 {
        return if (line_index == 0) self.prompt else self.continuation;
    }

    fn advance(position: *Position, text: []const u8, width: usize) void {
        var index: usize = 0;
        while (index < text.len) {
            const len = term.sequenceLength(text[index]);
            const char_width = term.textWidth(text[index..@min(index + len, text.len)]);
            if (char_width != 0 and position.col + char_width > width) {
                position.row += 1;
                position.col = 0;
            }
            position.col += char_width;
            index += len;
        }
    }

    fn measureLines(self: *Editor, width: usize) !void {
        self.lines.clearRetainingCapacity();
        const items = self.buffer.items;
        var start: usize = 0;
        while (true) {
            const end = self.lineEnd(start);
            var position: Position = .{ .col = term.textWidth(self.promptFor(self.lines.items.len)) };
            advance(&position, items[start..end], width);
            try self.lines.append(self.allocator, .{ .start = start, .end = end, .rows = position.row + 1 });
            if (end == items.len) break;
            start = end + 1;
        }
    }

    fn draw(self: *Editor, mode: enum { live, final }) !void {
        const allocator = self.allocator;
        const screen = self.size();
        const width = screen.cols;
        const frame = &self.frame;
        frame.clearRetainingCapacity();
        try frame.appendSlice(allocator, "\x1b[?25l");
        if (self.cursor_row > 0) try appendFmt(allocator, frame, "\x1b[{d}A", .{self.cursor_row});
        try frame.appendSlice(allocator, "\r\x1b[J");

        var end: Position = .{};
        var target: Position = .{};
        if (mode == .live and self.search != null) {
            try self.appendSearchLine(width, &end);
            target = end;
        } else {
            try self.measureLines(width);
            const lines = self.lines.items;
            var first: usize = 0;
            var last: usize = lines.len - 1;
            if (mode == .live) {
                var current: usize = 0;
                while (lines[current].end < self.cursor) current += 1;
                const menu_rows = if (self.menu.items.len == 0) 0 else std.mem.count(u8, self.menu.items, "\n") + 1;
                const limit = @max(screen.rows -| (menu_rows + 1), 1);
                first = current;
                last = current;
                var total = lines[current].rows;
                while (first > 0 and total + lines[first - 1].rows <= limit) {
                    first -= 1;
                    total += lines[first].rows;
                }
                while (last + 1 < lines.len and total + lines[last + 1].rows <= limit) {
                    last += 1;
                    total += lines[last].rows;
                }
            }
            for (lines[first .. last + 1], first..) |line, index| {
                if (index != first) {
                    try frame.appendSlice(allocator, "\r\n");
                    end = .{ .row = end.row + 1 };
                }
                const prompt = self.promptFor(index);
                try frame.appendSlice(allocator, self.paint.on(.prompt));
                try frame.appendSlice(allocator, prompt);
                try frame.appendSlice(allocator, self.paint.off());
                try highlight.appendRange(allocator, frame, self.paint, self.buffer.items, line.start, line.end);
                end.col = term.textWidth(prompt);
                if (self.cursor >= line.start and self.cursor <= line.end) {
                    target = end;
                    advance(&target, self.buffer.items[line.start..self.cursor], width);
                    if (target.col == width and self.cursor < line.end) target = .{ .row = target.row + 1 };
                }
                advance(&end, self.buffer.items[line.start..line.end], width);
            }
        }

        if (mode == .final) {
            try frame.appendSlice(allocator, "\x1b[?25h\r\n");
            self.cursor_row = 0;
        } else {
            const at_end = target.row == end.row and target.col == end.col;
            if (self.menu.items.len != 0) {
                var rows = std.mem.splitScalar(u8, self.menu.items, '\n');
                while (rows.next()) |row| {
                    try frame.appendSlice(allocator, "\r\n");
                    try frame.appendSlice(allocator, self.paint.on(.dim));
                    try frame.appendSlice(allocator, row);
                    try frame.appendSlice(allocator, self.paint.off());
                    end = .{ .row = end.row + 1 };
                }
            }
            if (target.col == width) {
                if (at_end and self.menu.items.len == 0) {
                    try frame.appendSlice(allocator, "\r\n");
                    end = .{ .row = end.row + 1 };
                    target = end;
                } else {
                    target.col = width - 1;
                }
            }
            if (end.row > target.row) try appendFmt(allocator, frame, "\x1b[{d}A", .{end.row - target.row});
            try frame.append(allocator, '\r');
            if (target.col > 0) try appendFmt(allocator, frame, "\x1b[{d}C", .{target.col});
            try frame.appendSlice(allocator, "\x1b[?25h");
            self.cursor_row = target.row;
        }
        try self.out.writeAll(frame.items);
        try self.out.flush();
    }

    fn appendSearchLine(self: *Editor, width: usize, end: *Position) !void {
        const allocator = self.allocator;
        const search = self.search.?;
        const frame = &self.frame;
        const start = frame.items.len;
        try frame.appendSlice(allocator, "(search) '");
        try frame.appendSlice(allocator, search.query.items);
        try frame.appendSlice(allocator, "': ");
        var used = term.textWidth(frame.items[start..]);
        try frame.insertSlice(allocator, start, self.paint.on(.prompt));
        try frame.appendSlice(allocator, self.paint.off());
        if (search.match) |match| {
            const entry = self.history.entries.items[match];
            var index: usize = 0;
            while (index < entry.len) {
                const len = term.sequenceLength(entry[index]);
                const piece: []const u8 = if (entry[index] == '\n' or entry[index] == '\t') " " else entry[index..@min(index + len, entry.len)];
                const piece_width = term.textWidth(piece);
                if (used + piece_width >= width) break;
                try frame.appendSlice(allocator, piece);
                used += piece_width;
                index += len;
            }
        }
        end.col = @min(used, width - 1);
    }
};

fn isWordByte(byte: u8) bool {
    return highlight.isIdentifierPart(byte) or byte >= 0x80;
}

fn eql(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}

fn appendFmt(allocator: std.mem.Allocator, out: *std.ArrayList(u8), comptime fmt: []const u8, args: anytype) !void {
    var buffer: [64]u8 = undefined;
    try out.appendSlice(allocator, std.fmt.bufPrint(&buffer, fmt, args) catch unreachable);
}

const TestHooks = struct {
    const candidates = [_][]const u8{ "print", "println" };

    fn isComplete(_: *anyopaque, source: []const u8) bool {
        return std.mem.count(u8, source, "do") <= std.mem.count(u8, source, "end");
    }

    fn complete(_: *anyopaque, source: []const u8, cursor: usize) Completion {
        const start = std.mem.lastIndexOfScalar(u8, source[0..cursor], ' ') orelse return .{ .candidates = &candidates };
        return .{ .start = start + 1, .candidates = &candidates };
    }

    var context: u8 = 0;
    const hooks: Hooks = .{ .context = &context, .isComplete = isComplete, .complete = complete };
};

/// Tracks the cursor of a terminal with deferred wrapping while it receives editor output.
const TestScreen = struct {
    width: usize,
    row: usize = 0,
    col: usize = 0,
    wrap_pending: bool = false,

    fn feed(self: *TestScreen, bytes: []const u8) !void {
        var index: usize = 0;
        while (index < bytes.len) {
            const byte = bytes[index];
            if (byte == 0x1b) {
                index += 2;
                const start = index;
                while (bytes[index] < 0x40 or bytes[index] > 0x7e) index += 1;
                const count = std.fmt.parseInt(usize, bytes[start..index], 10) catch 1;
                switch (bytes[index]) {
                    'A' => self.row -= count,
                    'C' => self.col = @min(self.col + count, self.width - 1),
                    else => {},
                }
                if (bytes[index] == 'A' or bytes[index] == 'C') self.wrap_pending = false;
                index += 1;
            } else if (byte == '\r') {
                self.col = 0;
                self.wrap_pending = false;
                index += 1;
            } else if (byte == '\n') {
                self.row += 1;
                index += 1;
            } else {
                const len = term.sequenceLength(byte);
                const char_width = term.textWidth(bytes[index..][0..len]);
                if (char_width != 0 and (self.wrap_pending or self.col + char_width > self.width)) {
                    self.row += 1;
                    self.col = 0;
                    self.wrap_pending = false;
                }
                self.col += char_width;
                if (self.col == self.width) {
                    self.col = self.width - 1;
                    self.wrap_pending = true;
                }
                index += len;
            }
        }
    }
};

fn expectEdit(keys: []const u8, history: []const []const u8, expected: []const u8) !void {
    var in: std.Io.Reader = .fixed(keys);
    var out: std.Io.Writer.Discarding = .init(&.{});
    var editor = Editor.init(std.testing.allocator, std.testing.io, .fromReader(&in), &out.writer, .{}, TestHooks.hooks);
    defer editor.deinit();
    editor.raw_mode = false;
    editor.fixed_size = .{ .cols = 40, .rows = 10 };
    for (history) |entry| try editor.history.add(entry);
    switch (try editor.readLine()) {
        .line => |line| try std.testing.expectEqualStrings(expected, line),
        else => return error.TestExpectedLine,
    }
}

test "typed text is edited with cursor keys" {
    try expectEdit("helo\x1b[Dl\r", &.{}, "hello");
    try expectEdit("abc\x01X\x05Y\r", &.{}, "XabcY");
    try expectEdit("abc\x7f\x7fd\r", &.{}, "ad");
    try expectEdit("one two\x17three\r", &.{}, "one three");
    try expectEdit("one two\x1bb\x0b2\r", &.{}, "one 2");
    try expectEdit("one two\x15\x19!\r", &.{}, "one two!");
    try expectEdit("ab\x1b[D\x1b[3~\r", &.{}, "a");
    try expectEdit("h\xc3\xa9llo\x1b[D\x1b[D\x1b[D\x7f\r", &.{}, "hllo");
    try expectEdit("e\xcc\x81x\x1b[D\x7f\r", &.{}, "x");
}

test "enter continues an incomplete chunk with indentation" {
    try expectEdit("for i = 1, 2 do\rprint(i)\r\x7fend\r", &.{}, "for i = 1, 2 do\n  print(i)\nend");
    try expectEdit("a\x1b\rb\r", &.{}, "a\nb");
    try expectEdit("x do\ry\x1b[A\x01!\x1b[B\x05\x7f\x7fend\r", &.{}, "!x do\nend");
}

test "history is recalled and searched" {
    const history = [_][]const u8{ "first = 1", "second = 2", "third = 3" };
    try expectEdit("\x1b[A\r", &history, "third = 3");
    try expectEdit("draft\x1b[A\x1b[A\x1b[B\x1b[B!\r", &history, "draft!");
    try expectEdit("\x10\x10\x0e\r", &history, "third = 3");
    try expectEdit("\x12sec\r\r", &history, "second = 2");
    try expectEdit("\x12= \x12\x12\r\r", &history, "first = 1");
    try expectEdit("kept\x12zzz\x07\r", &history, "kept");
}

test "pasted text keeps line breaks without submitting" {
    try expectEdit("\x1b[200~a = 1\r\nb = 2\x00\x1b[201~\r", &.{}, "a = 1\nb = 2");
}

test "tab indents or completes" {
    try expectEdit("\tx\r", &.{}, "  x");
    try expectEdit("y = pr\t\r", &.{}, "y = print");
}

test "end of input and interrupts are reported" {
    var in: std.Io.Reader = .fixed("abc\x03\x04");
    var out: std.Io.Writer.Discarding = .init(&.{});
    var editor = Editor.init(std.testing.allocator, std.testing.io, .fromReader(&in), &out.writer, .{}, TestHooks.hooks);
    defer editor.deinit();
    editor.raw_mode = false;
    editor.fixed_size = .{};
    try std.testing.expect(try editor.readLine() == .interrupted);
    try std.testing.expect(try editor.readLine() == .eof);
}

test "history survives a round trip through its file format" {
    var history: History = .{ .allocator = std.testing.allocator };
    defer history.deinit();
    try history.add("for i = 1, 2 do\n  print('a\\n')\nend");
    try history.add("x = 1");
    try history.add("   ");
    const bytes = try history.serialize();
    defer std.testing.allocator.free(bytes);

    var loaded: History = .{ .allocator = std.testing.allocator };
    defer loaded.deinit();
    try loaded.parse(bytes);
    try loaded.parse("bad\x01entry\n");
    try std.testing.expectEqual(@as(usize, 2), loaded.entries.items.len);
    try std.testing.expectEqualStrings(history.entries.items[0], loaded.entries.items[0]);
    try std.testing.expectEqualStrings("x = 1", loaded.entries.items[1]);
}

test "the drawn cursor matches the edit position at every width" {
    const allocator = std.testing.allocator;
    const text = "local s = 'ab日本語cd' .. tostring(12345)\n  return s, s, s -- trailing comment\nend";
    for ([_]usize{ 16, 17, 20, 23, 40, 80 }) |width| {
        var offset: usize = 0;
        while (offset <= text.len) : (offset += 1) {
            if (offset < text.len and text[offset] & 0xc0 == 0x80) continue;
            var in: std.Io.Reader = .fixed("");
            var out: std.Io.Writer.Allocating = .init(allocator);
            defer out.deinit();
            var editor = Editor.init(allocator, std.testing.io, .fromReader(&in), &out.writer, .{ .enabled = true }, TestHooks.hooks);
            defer editor.deinit();
            editor.fixed_size = .{ .cols = width, .rows = 50 };
            try editor.buffer.appendSlice(allocator, text);
            editor.cursor = offset;
            try editor.draw(.live);

            var expected: Position = .{};
            var line_start: usize = 0;
            var line_index: usize = 0;
            while (std.mem.indexOfScalarPos(u8, text, line_start, '\n')) |newline| {
                if (newline >= offset) break;
                var line_end: Position = .{ .col = term.textWidth(editor.promptFor(line_index)) };
                Editor.advance(&line_end, text[line_start..newline], width);
                expected.row += line_end.row + 1;
                line_start = newline + 1;
                line_index += 1;
            }
            var in_line: Position = .{ .col = term.textWidth(editor.promptFor(line_index)) };
            Editor.advance(&in_line, text[line_start..offset], width);
            expected.row += in_line.row;
            expected.col = in_line.col;
            const line_end = std.mem.indexOfScalarPos(u8, text, offset, '\n') orelse text.len;
            if (expected.col == width) {
                if (offset == text.len) {
                    expected = .{ .row = expected.row + 1 };
                } else if (offset == line_end) {
                    expected.col = width - 1;
                } else {
                    expected = .{ .row = expected.row + 1 };
                }
            }

            var screen: TestScreen = .{ .width = width };
            try screen.feed(out.written());
            try std.testing.expectEqual(expected.row, screen.row);
            try std.testing.expectEqual(expected.col, screen.col);
            try std.testing.expectEqual(expected.row, editor.cursor_row);
        }
    }
}
