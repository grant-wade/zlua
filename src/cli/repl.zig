const std = @import("std");
const builtin = @import("builtin");
const zlua = @import("zlua");
const term = @import("term.zig");
const editor_mod = @import("editor.zig");
const highlight = @import("highlight.zig");
const inspect = @import("inspect.zig");
const report = @import("report.zig");

const Dir = std.Io.Dir;
const File = std.Io.File;
const EnvMap = std.process.Environ.Map;
const Editor = editor_mod.Editor;
const Paint = term.Paint;
const errors = zlua.errors;
const frontend = zlua.frontend;
const runtime = zlua.runtime;
const State = runtime.State;
const Table = runtime.Table;
const Value = runtime.Value;

const expression_prefix = "local function results(...values) return values end return results(";
const expression_suffix = "\n)";
const input_prefix = "input#";
const max_source_file_bytes = 8 << 20;

pub const Options = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    state: *State,
    stdin: *std.Io.Reader,
    stdout: *std.Io.Writer,
    env: *const EnvMap,
    color: term.ColorMode = .auto,
    /// Print the version line when the session is on a terminal.
    banner: bool = true,
};

pub const Outcome = enum {
    /// Input ended.
    finished,
    /// Lua called `os.exit`; the state holds the exit request.
    exit_requested,
};

pub fn run(options: Options) !Outcome {
    const io = options.io;
    const stdin_tty = File.stdin().isTty(io) catch false;
    const stdout_tty = File.stdout().isTty(io) catch false;
    var repl: Repl = .{
        .allocator = options.allocator,
        .io = io,
        .state = options.state,
        .in = options.stdin,
        .out = options.stdout,
        .interactive = stdin_tty,
        .editing = stdin_tty and stdout_tty and !term.isDumb(options.env) and term.canEdit(),
        .paint_out = if (stdin_tty) term.detectPaint(io, File.stdout(), options.color, options.env) else .{},
        .paint_err = if (stdin_tty) term.detectPaint(io, File.stderr(), options.color, options.env) else .{},
        .files = .init(options.allocator),
        .completions = .init(options.allocator),
    };
    defer repl.deinit();
    const encoding: term.Utf8Output = if (stdin_tty and stdout_tty) .begin() else .{};
    defer encoding.end();
    if (stdin_tty) {
        if (options.banner) try repl.out.print("zlua {s} ({s})\n", .{ zlua.version, zlua.lua_target_version });
        try repl.out.print("{s}Type exit or press Ctrl-D to leave.{s}\n", .{ repl.paint_out.on(.dim), repl.paint_out.off() });
    }
    return repl.run(options.env);
}

const Repl = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    state: *State,
    in: *std.Io.Reader,
    out: *std.Io.Writer,
    /// Stdin is a terminal: results are inspected and errors show their source.
    interactive: bool,
    /// The line editor reads input.
    editing: bool,
    paint_out: Paint,
    paint_err: Paint,
    /// Source of `input#N` at index N - 1.
    inputs: std.ArrayList([]u8) = .empty,
    files: std.heap.ArenaAllocator,
    completions: std.heap.ArenaAllocator,
    /// Receives error output in place of stderr.
    error_output: ?*std.Io.Writer = null,

    fn deinit(self: *Repl) void {
        for (self.inputs.items) |input| self.allocator.free(input);
        self.inputs.deinit(self.allocator);
        self.files.deinit();
        self.completions.deinit();
    }

    fn run(self: *Repl, env: *const EnvMap) !Outcome {
        if (!self.editing) return self.runPlain();

        var console_input: term.ConsoleInput = .{};
        const input: term.Input = if (builtin.os.tag == .windows) console_input.input() else .fromReader(self.in);
        var editor = Editor.init(self.allocator, self.io, input, self.out, self.paint_out, .{
            .context = self,
            .isComplete = isCompleteHook,
            .complete = completeHook,
        });
        defer editor.deinit();
        editor.fresh_line = true;
        const history_path = try historyPath(self.allocator, env);
        defer if (history_path) |path| self.allocator.free(path);
        if (history_path) |path| editor.history.load(self.io, path) catch {};
        defer if (history_path) |path| editor.history.save(self.io, path) catch {};

        while (true) {
            editor.prompt = self.promptText("_PROMPT", "> ");
            editor.continuation = self.promptText("_PROMPT2", ">> ");
            switch (try editor.readLine()) {
                .eof => return .finished,
                .interrupted => {},
                .line => |line| if (try self.evaluate(line)) |outcome| return outcome,
            }
        }
    }

    fn runPlain(self: *Repl) !Outcome {
        var source = std.ArrayList(u8).empty;
        defer source.deinit(self.allocator);
        while (true) {
            if (self.interactive) {
                const prompt = if (source.items.len == 0) self.promptText("_PROMPT", "> ") else self.promptText("_PROMPT2", ">> ");
                try self.out.print("{s}{s}{s}", .{ self.paint_out.on(.prompt), prompt, self.paint_out.off() });
            }
            try self.out.flush();
            const line = self.in.takeDelimiter('\n') catch |err| switch (err) {
                error.StreamTooLong => {
                    try self.writeError("input line too long\n");
                    self.in.tossBuffered();
                    source.clearRetainingCapacity();
                    continue;
                },
                error.ReadFailed => return err,
            } orelse break;
            try source.appendSlice(self.allocator, line);
            try source.append(self.allocator, '\n');
            if (!self.isComplete(source.items)) continue;
            if (try self.evaluate(source.items)) |outcome| return outcome;
            source.clearRetainingCapacity();
        }
        if (source.items.len != 0) {
            if (try self.evaluate(source.items)) |outcome| return outcome;
        }
        if (self.interactive) {
            try self.out.writeAll("\n");
            try self.out.flush();
        }
        return .finished;
    }

    fn promptText(self: *Repl, global: []const u8, default: []const u8) []const u8 {
        const value = self.state.getGlobalValue(global);
        if (value != .string) return default;
        const text = value.string.bytes();
        return if (std.unicode.utf8ValidateSlice(text) and std.mem.indexOfAny(u8, text, "\n\r\x1b") == null) text else default;
    }

    fn canParse(self: *Repl, source: []const u8) bool {
        var tree = frontend.parse(self.allocator, source) catch return false;
        tree.deinit();
        return true;
    }

    fn expressionChunk(self: *Repl, body: []const u8) !?[]u8 {
        const chunk = try std.mem.concat(self.allocator, u8, &.{ expression_prefix, body, expression_suffix });
        if (self.canParse(chunk)) return chunk;
        self.allocator.free(chunk);
        return null;
    }

    fn isComplete(self: *Repl, source: []const u8) bool {
        const body = chunkBody(source);
        if (body.len == 0) return true;
        if (self.expressionChunk(body) catch return true) |chunk| {
            self.allocator.free(chunk);
            return true;
        }
        if (self.stopsAtEof(body)) return false;
        const returned = std.mem.concat(self.allocator, u8, &.{ "return ", body }) catch return true;
        defer self.allocator.free(returned);
        return !self.stopsAtEof(returned);
    }

    fn stopsAtEof(self: *Repl, source: []const u8) bool {
        var diagnostic: ?errors.Diagnostic = null;
        var tree = frontend.parseWithDiagnostic(self.allocator, source, &diagnostic) catch return endsAtEof(diagnostic);
        tree.deinit();
        return false;
    }

    fn isCompleteHook(context: *anyopaque, source: []const u8) bool {
        const self: *Repl = @ptrCast(@alignCast(context));
        return self.isComplete(source);
    }

    /// Returns an outcome when the REPL ends.
    fn evaluate(self: *Repl, source: []const u8) !?Outcome {
        const allocator = self.allocator;
        const state = self.state;
        const body = chunkBody(source);
        if (body.len == 0) return null;
        if (self.interactive and (std.mem.eql(u8, body, "exit") or std.mem.eql(u8, body, "quit")) and state.getGlobalValue(body) == .nil) return .finished;

        var name_buffer: [40]u8 = undefined;
        var name: []const u8 = "=stdin";
        if (self.interactive) {
            const copy = try allocator.dupe(u8, body);
            errdefer allocator.free(copy);
            try self.inputs.append(allocator, copy);
            name = std.fmt.bufPrint(&name_buffer, "=" ++ input_prefix ++ "{d}", .{self.inputs.items.len}) catch unreachable;
        }

        const expression = try self.expressionChunk(body);
        defer if (expression) |chunk| allocator.free(chunk);
        if (expression == null and self.interactive) {
            if (try self.loadDiagnostic(body)) |diagnostic| {
                var text = std.ArrayList(u8).empty;
                defer text.deinit(allocator);
                try report.appendLoadError(allocator, &text, self.paint_err, name[1..], body, diagnostic);
                try self.writeError(text.items);
                return null;
            }
        }

        if (expression == null and (std.mem.startsWith(u8, body, "local ") or std.mem.startsWith(u8, body, "local\t"))) {
            try self.writeErrorPainted(.hint, "warning: locals do not survive across lines in interactive mode");
        }

        const loaded = runtime.load.loadSourceAsClosureNamed(state, expression orelse body, name) catch |err| {
            try self.reportFailure(err, null);
            return null;
        };

        const control = try state.budget.interruptControl();
        control.clear();
        var traceback: ?[]u8 = null;
        defer if (traceback) |text| state.allocator.free(text);
        const handler: runtime.HostErrorHandler = if (self.interactive)
            .{ .traceback = &traceback }
        else
            .{ .message_handler = .{ .native = .traceback_message_handler }, .host_frame = true };

        const guard = term.InterruptGuard.install(&control.requested);
        const call = runtime.entry.callFunctionHandled(state, loaded, &.{}, handler);
        guard.remove();
        const results = call catch |err| {
            self.out.flush() catch {};
            switch (err) {
                error.LuaExit => return .exit_requested,
                error.Interrupted => {
                    state.budget.clearInterrupt();
                    if (self.interactive) try self.writeError("\n");
                    try self.writeErrorPainted(.title, if (self.interactive) "interrupted" else "interrupted!");
                },
                else => try self.reportFailure(err, traceback),
            }
            return null;
        };
        defer state.allocator.free(results);

        var roots: runtime.ValueRoots = undefined;
        state.pushValueRoots(&roots, results);
        defer state.popValueRoots(&roots);
        var values: []const Value = results;
        var unpacked: []Value = &.{};
        defer allocator.free(unpacked);
        if (expression != null and results.len == 1 and results[0] == .table) {
            const packed_values = results[0].table;
            const count = packed_values.getBytes("n");
            unpacked = try allocator.alloc(Value, if (count == .integer and count.integer > 0) @intCast(count.integer) else 0);
            for (unpacked, 1..) |*value, position| value.* = packed_values.get(.{ .integer = @intCast(position) });
            values = unpacked;
        }
        if (values.len != 0) self.showResults(values) catch |err| switch (err) {
            error.LuaExit => return .exit_requested,
            error.OutOfMemory, error.WriteFailed => return err,
            else => try self.reportFailure(err, null),
        };
        try self.out.flush();
        return null;
    }

    fn loadDiagnostic(self: *Repl, body: []const u8) !?errors.Diagnostic {
        var diagnostic: ?errors.Diagnostic = null;
        var tree = frontend.parseWithDiagnostic(self.allocator, body, &diagnostic) catch |err| switch (err) {
            error.OutOfMemory => return err,
            else => return diagnostic,
        };
        defer tree.deinit();
        zlua.compile.resolver.resolveWithDiagnostic(self.allocator, &tree, &diagnostic) catch |err| switch (err) {
            error.OutOfMemory => return err,
            else => return diagnostic,
        };
        return null;
    }

    /// `values` must be reachable from a GC root.
    fn showResults(self: *Repl, values: []const Value) !void {
        const allocator = self.allocator;
        const state = self.state;
        if (!self.interactive) {
            const printed = runtime.entry.callFunctionHandled(state, state.getGlobalValue("print"), values, .{}) catch |err| switch (err) {
                error.RuntimeError => {
                    var message = std.ArrayList(u8).empty;
                    defer message.deinit(allocator);
                    try message.appendSlice(allocator, "error calling 'print' (");
                    try runtime.appendErrorValue(allocator, &message, state.currentErrorValue());
                    try message.appendSlice(allocator, ")\n");
                    return self.writeError(message.items);
                },
                else => return err,
            };
            state.allocator.free(printed);
            return;
        }

        var text = std.ArrayList(u8).empty;
        defer text.deinit(allocator);
        const width = term.windowSize(self.io).cols;
        var multiline = false;
        var starts = std.ArrayList(usize).empty;
        defer starts.deinit(allocator);
        for (values) |value| {
            const start = text.items.len;
            try starts.append(allocator, start);
            try inspect.append(state, allocator, &text, value, .{ .paint = self.paint_out, .width = width });
            if (std.mem.indexOfScalar(u8, text.items[start..], '\n') != null) multiline = true;
        }
        for (starts.items, 0..) |start, index| {
            const end = if (index + 1 < starts.items.len) starts.items[index + 1] else text.items.len;
            if (index != 0) try self.out.writeAll(if (multiline) "\n" else "\t");
            try self.out.writeAll(text.items[start..end]);
        }
        try self.out.writeAll("\n");
    }

    fn reportFailure(self: *Repl, err: anyerror, traceback: ?[]const u8) !void {
        const allocator = self.allocator;
        const state = self.state;
        if (err == error.OutOfMemory) return err;
        self.out.flush() catch {};

        var message = std.ArrayList(u8).empty;
        defer message.deinit(allocator);
        const value = state.currentErrorValue();
        if (state.last_error == null) {
            try message.appendSlice(allocator, @errorName(err));
        } else if (value == .string or value == .integer or value == .number or !self.interactive) {
            try runtime.appendErrorValue(allocator, &message, value);
        } else {
            var roots: runtime.ValueRoots = undefined;
            const rooted = [_]Value{value};
            state.pushValueRoots(&roots, &rooted);
            defer state.popValueRoots(&roots);
            try inspect.append(state, allocator, &message, value, .{ .width = std.math.maxInt(usize) });
        }

        if (!self.interactive) {
            try message.append(allocator, '\n');
            return self.writeError(message.items);
        }
        _ = self.files.reset(.retain_capacity);
        var text = std.ArrayList(u8).empty;
        defer text.deinit(allocator);
        try report.appendRuntimeError(allocator, &text, self.paint_err, .{ .context = self, .lookup = lookupSource }, state, .{ .message = message.items, .traceback = traceback });
        try self.writeError(text.items);
    }

    fn lookupSource(context: *anyopaque, name: []const u8) ?[]const u8 {
        const self: *Repl = @ptrCast(@alignCast(context));
        if (std.mem.startsWith(u8, name, input_prefix)) {
            const number = std.fmt.parseInt(usize, name[input_prefix.len..], 10) catch return null;
            if (number == 0 or number > self.inputs.items.len) return null;
            return self.inputs.items[number - 1];
        }
        if (name.len == 0 or name[0] == '[' or name[0] == '?' or std.mem.startsWith(u8, name, "...")) return null;
        return Dir.cwd().readFileAlloc(self.io, name, self.files.allocator(), .limited(max_source_file_bytes)) catch null;
    }

    fn writeError(self: *Repl, bytes: []const u8) !void {
        self.out.flush() catch {};
        if (self.error_output) |output| return output.writeAll(bytes);
        var buffer: [1024]u8 = undefined;
        var writer = File.stderr().writerStreaming(self.io, &buffer);
        try writer.interface.writeAll(bytes);
        try writer.interface.flush();
    }

    fn writeErrorPainted(self: *Repl, role: term.Role, bytes: []const u8) !void {
        const text = try std.mem.concat(self.allocator, u8, &.{ self.paint_err.on(role), bytes, self.paint_err.off(), "\n" });
        defer self.allocator.free(text);
        try self.writeError(text);
    }

    fn completeHook(context: *anyopaque, source: []const u8, cursor: usize) editor_mod.Completion {
        const self: *Repl = @ptrCast(@alignCast(context));
        return self.complete(source, cursor) catch .{};
    }

    fn complete(self: *Repl, source: []const u8, cursor: usize) !editor_mod.Completion {
        _ = self.completions.reset(.retain_capacity);
        const arena = self.completions.allocator();

        var scanner: highlight.Scanner = .{ .source = source };
        while (scanner.next()) |token| {
            if (token.start >= cursor) break;
            if (token.end >= cursor and (token.kind == .string or token.kind == .comment or token.kind == .number)) return .{};
        }

        var start = cursor;
        while (start > 0 and highlight.isIdentifierPart(source[start - 1])) start -= 1;
        const partial = source[start..cursor];

        var segments = std.ArrayList([]const u8).empty;
        var position = start;
        while (position > 0 and (source[position - 1] == '.' or source[position - 1] == ':')) {
            const end = position - 1;
            var begin = end;
            while (begin > 0 and highlight.isIdentifierPart(source[begin - 1])) begin -= 1;
            if (begin == end) return .{};
            try segments.insert(arena, 0, source[begin..end]);
            position = begin;
        }

        var owner = self.state.global_table orelse return .{};
        for (segments.items) |segment| {
            owner = switch (owner.getBytes(segment)) {
                .table => |table| table,
                .string => self.stringMethods() orelse return .{},
                else => return .{},
            };
        }

        var candidates = std.ArrayList([]const u8).empty;
        try appendKeys(arena, &candidates, owner, partial);
        if (owner.metatable) |metatable| {
            const index = metatable.getBytes("__index");
            if (index == .table) try appendKeys(arena, &candidates, index.table, partial);
        }
        if (segments.items.len == 0) {
            for (highlight.keywords) |keyword| {
                if (std.mem.startsWith(u8, keyword, partial)) try candidates.append(arena, keyword);
            }
        }
        std.mem.sort([]const u8, candidates.items, {}, struct {
            fn lessThan(_: void, a: []const u8, b: []const u8) bool {
                return std.mem.lessThan(u8, a, b);
            }
        }.lessThan);
        var unique: usize = 0;
        for (candidates.items) |candidate| {
            if (unique != 0 and std.mem.eql(u8, candidates.items[unique - 1], candidate)) continue;
            candidates.items[unique] = candidate;
            unique += 1;
        }
        return .{ .start = start, .candidates = candidates.items[0..unique] };
    }

    fn stringMethods(self: *Repl) ?*Table {
        const metatable = self.state.string_metatable orelse return null;
        const index = metatable.getBytes("__index");
        return if (index == .table) index.table else null;
    }
};

fn appendKeys(arena: std.mem.Allocator, candidates: *std.ArrayList([]const u8), table: *const Table, prefix: []const u8) !void {
    for (table.entries()) |entry| {
        if (entry.key != .string or entry.value == .nil) continue;
        const key = entry.key.string.bytes();
        if (std.mem.startsWith(u8, key, prefix) and highlight.isIdentifier(key)) try candidates.append(arena, try arena.dupe(u8, key));
    }
}

/// The chunk to run for an input, without surrounding space or the `=` shorthand.
fn chunkBody(source: []const u8) []const u8 {
    const trimmed = std.mem.trim(u8, source, " \t\r\n");
    return if (std.mem.startsWith(u8, trimmed, "=")) std.mem.trimStart(u8, trimmed[1..], " \t") else trimmed;
}

fn endsAtEof(diagnostic: ?errors.Diagnostic) bool {
    const found = diagnostic orelse return false;
    return switch (found) {
        .syntax => |syntax| switch (syntax) {
            .unexpected => |unexpected| unexpected.token.tag == .eof,
            .expected => |expected| expected.near.tag == .eof,
            .expected_close => |expected| expected.near.tag == .eof,
        },
        else => false,
    };
}

/// Null when history is off.
fn historyPath(allocator: std.mem.Allocator, env: *const EnvMap) !?[]u8 {
    if (env.get("ZLUA_HISTORY")) |path| return if (path.len == 0) null else try allocator.dupe(u8, path);
    const home = env.get("HOME") orelse env.get("USERPROFILE") orelse return null;
    if (home.len == 0) return null;
    return try std.fs.path.join(allocator, &.{ home, ".zlua_history" });
}

const TestRepl = struct {
    state: State,
    out: std.Io.Writer.Allocating,
    errors: std.Io.Writer.Allocating,
    in: std.Io.Reader,
    repl: Repl,

    fn init(self: *TestRepl, input: []const u8, interactive: bool) !void {
        const allocator = std.testing.allocator;
        self.out = .init(allocator);
        self.errors = .init(allocator);
        self.in = .fixed(input);
        self.state = try State.initWithOptions(allocator, .{ .stdlib = .full, .process = .enabled, .stdout = &self.out.writer, .capture_output = false });
        self.repl = .{
            .allocator = allocator,
            .io = std.testing.io,
            .state = &self.state,
            .in = &self.in,
            .out = &self.out.writer,
            .interactive = interactive,
            .editing = false,
            .paint_out = .{},
            .paint_err = .{},
            .files = .init(allocator),
            .completions = .init(allocator),
            .error_output = &self.errors.writer,
        };
    }

    fn deinit(self: *TestRepl) void {
        self.repl.deinit();
        self.state.deinit();
        self.out.deinit();
        self.errors.deinit();
    }
};

fn expectPlainOutput(input: []const u8, expected: []const u8) !void {
    var session: TestRepl = undefined;
    try session.init(input, false);
    defer session.deinit();
    try std.testing.expectEqual(Outcome.finished, try session.repl.runPlain());
    try std.testing.expectEqualStrings(expected, session.out.written());
}

test "piped input prints expression results like lua" {
    try expectPlainOutput("1 + 1\n", "2\n");
    try expectPlainOutput("t = {x = 3}\nt.x\n= t.x * 2\n", "3\n6\n");
    try expectPlainOutput("string.rep('ab', 2), nil, 3\n", "abab\tnil\t3\n");
    try expectPlainOutput("x = 5\nx\nprint('after')\n", "5\nafter\n");
    try expectPlainOutput("for i = 1, 2 do\n  print(i)\nend\n", "1\n2\n");
    try expectPlainOutput("print('no newline at the end')", "no newline at the end\n");
    try expectPlainOutput("local a = 1; print(a)\na\n", "1\nnil\n");
    try expectPlainOutput("local a = 2 return a, a * 2\n", "2\t4\n");
}

test "errors and warnings go to the error stream" {
    var session: TestRepl = undefined;
    try session.init("local a = 1\nprint = nil\n5\nx = = 1\n", false);
    defer session.deinit();
    try std.testing.expectEqual(Outcome.finished, try session.repl.runPlain());
    try std.testing.expectEqualStrings("", session.out.written());
    try std.testing.expectEqualStrings("warning: locals do not survive across lines in interactive mode\n" ++
        "error calling 'print' (attempt to call a nil value)\n" ++
        "stdin:1: unexpected symbol near '='\n", session.errors.written());
}

test "a terminal session reports errors with their source" {
    var session: TestRepl = undefined;
    try session.init("", true);
    defer session.deinit();
    const repl = &session.repl;
    try std.testing.expect(try repl.evaluate("function half(n) return n / 2 end") == null);
    try std.testing.expect(try repl.evaluate("half()") == null);
    try std.testing.expectEqualStrings(
        \\Traceback (most recent call last):
        \\  input#2, line 1, in main chunk
        \\    half()
        \\    ^^^^
        \\  input#1, line 1, in global 'half'
        \\    function half(n) return n / 2 end
        \\error: attempt to perform arithmetic on a nil value (local 'n')
        \\
    , session.errors.written());
}

test "a terminal session inspects results and stops at exit" {
    var session: TestRepl = undefined;
    try session.init("", true);
    defer session.deinit();
    const repl = &session.repl;
    try std.testing.expect(try repl.evaluate("{1, 2, name = 'x'}") == null);
    try std.testing.expect(try repl.evaluate("'text', 2") == null);
    try std.testing.expect(try repl.evaluate("print('printed')") == null);
    try std.testing.expectEqualStrings("{1, 2, name = \"x\"}\n\"text\"\t2\nprinted\n", session.out.written());
    try std.testing.expectEqual(Outcome.finished, (try repl.evaluate("exit")).?);
    try std.testing.expect(try repl.evaluate("exit = 1") == null);
    try std.testing.expect(try repl.evaluate("exit") == null);
    try std.testing.expectEqual(Outcome.exit_requested, (try repl.evaluate("os.exit(3)")).?);
}

test "chunks are complete unless they stop at the end of input" {
    var session: TestRepl = undefined;
    try session.init("", true);
    defer session.deinit();
    const repl = &session.repl;
    for ([_][]const u8{ "", "x", "x = 1", "f()", "x = = 1", "end", "= 1 +" }) |source| {
        const expected = !std.mem.eql(u8, source, "= 1 +");
        try std.testing.expectEqual(expected, repl.isComplete(source));
    }
    for ([_][]const u8{ "for i = 1, 2 do", "x = {", "function f()", "if x then\n  y()", "print(", "{1,", "x = [[long" }) |source| {
        try std.testing.expect(!repl.isComplete(source));
    }
}

fn expectCompletion(repl: *Repl, source: []const u8, expected_start: usize, expected: []const []const u8) !void {
    const completion = try repl.complete(source, source.len);
    try std.testing.expectEqual(expected.len, completion.candidates.len);
    for (expected, completion.candidates) |want, got| try std.testing.expectEqualStrings(want, got);
    if (expected.len != 0) try std.testing.expectEqual(expected_start, completion.start);
}

test "completion follows globals, fields, and string methods" {
    var session: TestRepl = undefined;
    try session.init("", true);
    defer session.deinit();
    const repl = &session.repl;
    try std.testing.expect(try repl.evaluate("config = {server = {port = 80, path = '/'}, name = 'x'}") == null);
    try expectCompletion(repl, "x = conf", 4, &.{"config"});
    try expectCompletion(repl, "config.server.p", 14, &.{ "path", "port" });
    try expectCompletion(repl, "config.name:up", 12, &.{"upper"});
    try expectCompletion(repl, "whi", 0, &.{"while"});
    try expectCompletion(repl, "print('conf", 0, &.{});
    try expectCompletion(repl, "f().x", 0, &.{});
}
