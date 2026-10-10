const std = @import("std");
const zlua = @import("zlua");

const ast = zlua.frontend.ast;
const Dir = std.Io.Dir;
const File = std.Io.File;

const DumpMode = enum {
    none,
    ast,
    scope,
    bytecode,
};

const CliOptions = struct {
    evals: std.ArrayList([]const u8) = .empty,
    script_path: ?[]const u8 = null,
    script_index: ?usize = null,
    interactive: bool = false,
    debug_errors: bool = false,
    trace_vm: bool = false,
    print_version: bool = false,
    print_help: bool = false,
    dump_mode: DumpMode = .none,
    stdlib: zlua.runtime.StdlibMode = .full,

    fn deinit(self: *CliOptions, allocator: std.mem.Allocator) void {
        self.evals.deinit(allocator);
        self.* = undefined;
    }
};

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const arena_allocator = init.arena.allocator();

    const raw_args = try init.minimal.args.toSlice(arena_allocator);
    const args = try arena_allocator.alloc([]const u8, raw_args.len);
    for (raw_args, 0..) |arg, index| args[index] = arg;

    const exit_code = try runCliProgram(arena_allocator, io, init.environ_map, args);
    std.process.exit(exit_code);
}

fn runCliProgram(
    allocator: std.mem.Allocator,
    io: std.Io,
    environ_map: *const std.process.Environ.Map,
    args: []const []const u8,
) !u8 {
    var options = parseCliOptions(allocator, args) catch |err| {
        try stderrPrint(io, "zlua: {s}\n", .{@errorName(err)});
        return 2;
    };
    defer options.deinit(allocator);

    if (options.print_help) {
        try printUsage(io);
        return 0;
    }
    if (options.print_version) try printVersion(io);

    if (options.dump_mode != .none) {
        return runDumpMode(allocator, io, &options);
    }

    const no_input = options.evals.items.len == 0 and options.script_path == null;
    if (options.print_version and no_input and !options.interactive and try stdinIsTty(io)) return 0;
    if (no_input and !options.interactive and try stdinIsTty(io)) {
        options.interactive = true;
    }

    // Lua output streams like C stdio: stdout is line buffered on a terminal
    // and block buffered otherwise, stderr is unbuffered, and stdin is read
    // only as far as each request needs. The REPL shares the same stdin.
    var stdout_buffer: [4096]u8 = undefined;
    var stdout_writer = File.stdout().writerStreaming(io, &stdout_buffer);
    var stderr_buffer: [0]u8 = undefined;
    var stderr_writer = File.stderr().writerStreaming(io, &stderr_buffer);
    var stdin_buffer: [64 * 1024]u8 = undefined;
    var stdin_reader = File.stdin().readerStreaming(io, &stdin_buffer);
    const stdout_tty = File.stdout().isTty(io) catch false;
    var cli: Cli = .{ .io = io, .stdout = &stdout_writer.interface, .stdin = &stdin_reader.interface };

    const state_allocator = std.heap.smp_allocator;
    var state = try zlua.runtime.State.initWithOptions(state_allocator, .{
        .stdlib = options.stdlib,
        .io = io,
        .stdout = cli.stdout,
        .stderr = &stderr_writer.interface,
        .stdout_flush = if (stdout_tty) .line else .print,
        .stderr_flush = .always,
        .capture_output = false,
        .stdin_reader = cli.stdin,
        .filesystem = .host_cwd,
        .environment = .{ .map = environ_map },
        .process = .enabled,
        .debug_errors = options.debug_errors,
        .trace_vm = options.trace_vm,
    });
    defer state.deinit();
    // Runs before `state.deinit` on every exit path, like C `exit` flushing
    // all open streams after the error message (if any) was written.
    defer cli.finish(&state);

    try installArgTable(state_allocator, &state, args, options.script_index);

    for (options.evals.items) |source| {
        if (try executeChunkNamed(state_allocator, io, &state, source, "=(command line)")) |exit_code| return exit_code;
    }

    if (options.script_path) |path| {
        if (std.mem.eql(u8, path, "-")) {
            const source = cli.readStdinAlloc(state_allocator) catch |err| {
                try stderrPrint(io, "cannot read stdin: {s}\n", .{@errorName(err)});
                return 1;
            };
            defer state_allocator.free(source);
            if (try executeChunkNamed(state_allocator, io, &state, stripInitialShebang(source), "@stdin")) |exit_code| return exit_code;
        } else {
            const source = Dir.cwd().readFileAlloc(io, path, state_allocator, .limited(zlua.runtime.default_max_file_bytes)) catch |err| {
                try stderrPrint(io, "cannot read script {s}: {s}\n", .{ path, @errorName(err) });
                return 1;
            };
            defer state_allocator.free(source);
            const source_name = try std.fmt.allocPrint(state_allocator, "@{s}", .{path});
            defer state_allocator.free(source_name);
            if (try executeChunkNamed(state_allocator, io, &state, stripInitialShebang(source), source_name)) |exit_code| return exit_code;
        }
    } else if (no_input and !options.interactive) {
        const source = cli.readStdinAlloc(state_allocator) catch |err| {
            try stderrPrint(io, "cannot read stdin: {s}\n", .{@errorName(err)});
            return 1;
        };
        defer state_allocator.free(source);
        if (try executeChunkNamed(state_allocator, io, &state, stripInitialShebang(source), "@stdin")) |exit_code| return exit_code;
    }

    if (options.interactive) if (try runRepl(state_allocator, &cli, &state)) |exit_code| return exit_code;

    return 0;
}

/// Process streams shared by Lua and the CLI.
const Cli = struct {
    io: std.Io,
    stdout: *std.Io.Writer,
    stdin: *std.Io.Reader,

    fn flushStdout(self: *Cli) void {
        self.stdout.flush() catch {};
    }

    fn finish(self: *Cli, state: *zlua.runtime.State) void {
        zlua.stdlib.io.flushOpenFiles(state);
        self.flushStdout();
    }

    fn readStdinAlloc(self: *Cli, allocator: std.mem.Allocator) ![]u8 {
        return self.stdin.allocRemaining(allocator, .limited(zlua.runtime.default_max_file_bytes));
    }
};

fn parseCliOptions(allocator: std.mem.Allocator, args: []const []const u8) !CliOptions {
    var options: CliOptions = .{};
    errdefer options.deinit(allocator);

    var index: usize = 1;
    while (index < args.len) : (index += 1) {
        const arg = args[index];
        if (std.mem.eql(u8, arg, "--")) {
            index += 1;
            if (index < args.len) {
                options.script_path = args[index];
                options.script_index = index;
            }
            break;
        } else if (std.mem.eql(u8, arg, "--version") or std.mem.eql(u8, arg, "-v")) {
            options.print_version = true;
        } else if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            options.print_help = true;
        } else if (std.mem.eql(u8, arg, "--debug-errors")) {
            options.debug_errors = true;
        } else if (std.mem.eql(u8, arg, "--trace-vm")) {
            options.trace_vm = true;
        } else if (std.mem.eql(u8, arg, "-i")) {
            options.interactive = true;
        } else if (std.mem.eql(u8, arg, "--dump-ast")) {
            options.dump_mode = .ast;
        } else if (std.mem.eql(u8, arg, "--dump-scope")) {
            options.dump_mode = .scope;
        } else if (std.mem.eql(u8, arg, "--dump-bytecode")) {
            options.dump_mode = .bytecode;
        } else if (std.mem.eql(u8, arg, "--stdlib")) {
            index += 1;
            if (index >= args.len) return error.MissingOptionValue;
            options.stdlib = try parseStdlibMode(args[index]);
        } else if (std.mem.startsWith(u8, arg, "--stdlib=")) {
            options.stdlib = try parseStdlibMode(arg[9..]);
        } else if (std.mem.eql(u8, arg, "-e")) {
            index += 1;
            if (index >= args.len) return error.MissingOptionValue;
            try options.evals.append(allocator, args[index]);
        } else if (std.mem.startsWith(u8, arg, "-e") and arg.len > 2) {
            try options.evals.append(allocator, arg[2..]);
        } else if (std.mem.eql(u8, arg, "-")) {
            options.script_path = arg;
            options.script_index = index;
            break;
        } else if (std.mem.startsWith(u8, arg, "-")) {
            return error.UnknownOption;
        } else {
            options.script_path = arg;
            options.script_index = index;
            break;
        }
    }

    return options;
}

fn parseStdlibMode(value: []const u8) !zlua.runtime.StdlibMode {
    if (std.mem.eql(u8, value, "none")) return .none;
    if (std.mem.eql(u8, value, "base")) return .base;
    if (std.mem.eql(u8, value, "safe")) return .safe;
    if (std.mem.eql(u8, value, "full")) return .full;

    var libraries: zlua.stdlib.LibrarySet = .{};
    var start: usize = 0;
    for (value, 0..) |byte, index| {
        if (byte == ',' or byte == '+') {
            try parseStdlibLibrary(value[start..index], &libraries);
            start = index + 1;
        }
    }
    try parseStdlibLibrary(value[start..], &libraries);

    if (libraries.isEmpty()) return error.InvalidStdlibMode;
    return .{ .libraries = libraries };
}

fn parseStdlibLibrary(name: []const u8, libraries: *zlua.stdlib.LibrarySet) !void {
    if (name.len == 0) return error.InvalidStdlibMode;
    if (std.mem.eql(u8, name, "base")) {
        libraries.base = true;
    } else if (std.mem.eql(u8, name, "table")) {
        libraries.table = true;
    } else if (std.mem.eql(u8, name, "string")) {
        libraries.string = true;
    } else if (std.mem.eql(u8, name, "math")) {
        libraries.math = true;
    } else if (std.mem.eql(u8, name, "utf8")) {
        libraries.utf8 = true;
    } else if (std.mem.eql(u8, name, "coroutine")) {
        libraries.coroutine = true;
    } else if (std.mem.eql(u8, name, "io")) {
        libraries.io = true;
    } else if (std.mem.eql(u8, name, "os")) {
        libraries.os = true;
    } else if (std.mem.eql(u8, name, "debug")) {
        libraries.debug = true;
    } else if (std.mem.eql(u8, name, "package")) {
        libraries.package = true;
    } else if (std.mem.eql(u8, name, "json")) {
        libraries.json = true;
    } else if (std.mem.eql(u8, name, "toml")) {
        libraries.toml = true;
    } else if (std.mem.eql(u8, name, "msgpack")) {
        libraries.msgpack = true;
    } else if (std.mem.eql(u8, name, "csv")) {
        libraries.csv = true;
    } else if (std.mem.eql(u8, name, "fs")) {
        libraries.fs = true;
    } else {
        return error.InvalidStdlibMode;
    }
}

fn runDumpMode(allocator: std.mem.Allocator, io: std.Io, options: *const CliOptions) !u8 {
    var source_info = readDumpInput(allocator, io, options) catch |err| {
        try stderrPrint(io, "zlua: {s}\n", .{@errorName(err)});
        return 2;
    };
    defer source_info.deinit(allocator);

    var buffer: [4096]u8 = undefined;
    var writer = File.stdout().writer(io, &buffer);
    const out = &writer.interface;

    const ok = switch (options.dump_mode) {
        .none => unreachable,
        .ast => try dumpAst(allocator, out, source_info.source, source_info.name),
        .scope => try dumpScope(allocator, out, source_info.source, source_info.name),
        .bytecode => try dumpBytecode(allocator, out, source_info.source, source_info.name),
    };
    try out.flush();
    return if (ok) 0 else 1;
}

const DumpInput = struct {
    source: []u8,
    name: []u8,

    fn deinit(self: *DumpInput, allocator: std.mem.Allocator) void {
        allocator.free(self.source);
        allocator.free(self.name);
        self.* = undefined;
    }
};

fn readDumpInput(allocator: std.mem.Allocator, io: std.Io, options: *const CliOptions) !DumpInput {
    if (options.script_path) |path| {
        if (std.mem.eql(u8, path, "-")) {
            return .{ .source = try readStdinAlloc(allocator, io), .name = try allocator.dupe(u8, "@stdin") };
        }
        return .{
            .source = try Dir.cwd().readFileAlloc(io, path, allocator, .limited(zlua.runtime.default_max_file_bytes)),
            .name = try std.fmt.allocPrint(allocator, "@{s}", .{path}),
        };
    }
    if (options.evals.items.len != 0) {
        var source = std.ArrayList(u8).empty;
        errdefer source.deinit(allocator);
        for (options.evals.items) |eval| {
            try source.appendSlice(allocator, eval);
            try source.append(allocator, '\n');
        }
        return .{ .source = try source.toOwnedSlice(allocator), .name = try allocator.dupe(u8, "=(command line)") };
    }
    return error.MissingInput;
}

fn dumpAst(allocator: std.mem.Allocator, out: anytype, source: []const u8, name: []const u8) !bool {
    var tree = parseOrPrintDiagnostic(allocator, out, source, name) catch return false;
    defer tree.deinit();
    try out.print("chunk {s}\n", .{name});
    try dumpBlock(out, tree.statements, 1);
    return true;
}

fn dumpScope(allocator: std.mem.Allocator, out: anytype, source: []const u8, name: []const u8) !bool {
    var tree = parseOrPrintDiagnostic(allocator, out, source, name) catch return false;
    defer tree.deinit();
    var diagnostic: ?zlua.errors.Diagnostic = null;
    zlua.compile.resolver.resolveWithDiagnostic(allocator, &tree, &diagnostic) catch {
        try printDiagnostic(allocator, out, source, name, diagnostic, "cannot resolve source");
        return false;
    };
    try out.print("scope {s}: ok\n", .{name});
    try dumpScopeBlock(out, tree.statements, 1);
    return true;
}

fn dumpBytecode(allocator: std.mem.Allocator, out: anytype, source: []const u8, name: []const u8) !bool {
    var tree = parseOrPrintDiagnostic(allocator, out, source, name) catch return false;
    defer tree.deinit();
    var diagnostic: ?zlua.errors.Diagnostic = null;
    zlua.compile.resolver.resolveWithDiagnostic(allocator, &tree, &diagnostic) catch {
        try printDiagnostic(allocator, out, source, name, diagnostic, "cannot resolve source");
        return false;
    };
    var proto = zlua.compile.compileWithDiagnostic(allocator, &tree, &diagnostic) catch {
        try printDiagnostic(allocator, out, source, name, diagnostic, "cannot compile source");
        return false;
    };
    defer proto.deinit();
    const text = try zlua.compile.disasm.disassembleAlloc(allocator, &proto);
    defer allocator.free(text);
    try out.writeAll(text);
    return true;
}

fn parseOrPrintDiagnostic(allocator: std.mem.Allocator, out: anytype, source: []const u8, name: []const u8) !ast.Ast {
    var diagnostic: ?zlua.errors.Diagnostic = null;
    return zlua.frontend.parseWithDiagnostic(allocator, source, &diagnostic) catch {
        try printDiagnostic(allocator, out, source, name, diagnostic, "cannot parse source");
        return error.ParseError;
    };
}

fn printDiagnostic(allocator: std.mem.Allocator, out: anytype, source: []const u8, name: []const u8, diagnostic: ?zlua.errors.Diagnostic, fallback: []const u8) !void {
    const rendered = if (diagnostic) |diag|
        try zlua.errors.renderLoadDiagnostic(allocator, name, source, diag)
    else
        try allocator.dupe(u8, fallback);
    defer allocator.free(rendered);
    try out.print("{s}\n", .{rendered});
}

fn dumpBlock(out: anytype, statements: []const ast.Stmt, depth: usize) !void {
    for (statements) |statement| {
        try indent(out, depth);
        try out.print("{s}", .{@tagName(statement)});
        switch (statement) {
            .local_decl => |decl| try dumpBindings(out, decl.bindings),
            .global_decl => |decl| if (decl.all) try out.writeAll(" *") else try dumpBindings(out, decl.names),
            .function_decl => |decl| try out.print(" {s}", .{decl.name.root.name}),
            .local_function_decl => |decl| try out.print(" {s}", .{decl.name.name}),
            .goto_stmt, .label_stmt => |name| try out.print(" {s}", .{name.name}),
            else => {},
        }
        try out.writeAll("\n");
        switch (statement) {
            .if_stmt => |stmt| {
                for (stmt.branches) |branch| try dumpBlock(out, branch.body, depth + 1);
                if (stmt.else_block) |block| try dumpBlock(out, block, depth + 1);
            },
            .while_stmt => |stmt| try dumpBlock(out, stmt.body, depth + 1),
            .repeat_stmt => |stmt| try dumpBlock(out, stmt.body, depth + 1),
            .numeric_for => |stmt| try dumpBlock(out, stmt.body, depth + 1),
            .generic_for => |stmt| try dumpBlock(out, stmt.body, depth + 1),
            .do_block => |block| try dumpBlock(out, block, depth + 1),
            .function_decl => |stmt| try dumpBlock(out, stmt.body.body, depth + 1),
            .local_function_decl => |stmt| try dumpBlock(out, stmt.body.body, depth + 1),
            else => {},
        }
    }
}

fn dumpScopeBlock(out: anytype, statements: []const ast.Stmt, depth: usize) !void {
    for (statements) |statement| {
        switch (statement) {
            .local_decl => |decl| {
                try indent(out, depth);
                try out.writeAll("locals");
                try dumpBindings(out, decl.bindings);
                try out.writeAll("\n");
            },
            .global_decl => |decl| {
                try indent(out, depth);
                try out.writeAll("globals");
                if (decl.all) try out.writeAll(" *") else try dumpBindings(out, decl.names);
                try out.writeAll("\n");
            },
            .local_function_decl => |decl| {
                try indent(out, depth);
                try out.print("local function {s}\n", .{decl.name.name});
                try dumpScopeBlock(out, decl.body.body, depth + 1);
            },
            .function_decl => |decl| {
                try indent(out, depth);
                try out.print("function {s}\n", .{decl.name.root.name});
                try dumpScopeBlock(out, decl.body.body, depth + 1);
            },
            .if_stmt => |stmt| {
                for (stmt.branches) |branch| try dumpScopeBlock(out, branch.body, depth + 1);
                if (stmt.else_block) |block| try dumpScopeBlock(out, block, depth + 1);
            },
            .while_stmt => |stmt| try dumpScopeBlock(out, stmt.body, depth + 1),
            .repeat_stmt => |stmt| try dumpScopeBlock(out, stmt.body, depth + 1),
            .numeric_for => |stmt| try dumpScopeBlock(out, stmt.body, depth + 1),
            .generic_for => |stmt| try dumpScopeBlock(out, stmt.body, depth + 1),
            .do_block => |block| try dumpScopeBlock(out, block, depth + 1),
            else => {},
        }
    }
}

fn dumpBindings(out: anytype, bindings: []const ast.Binding) !void {
    for (bindings) |binding| {
        try out.print(" {s}", .{binding.name.name});
        if (binding.attribute) |attribute| try out.print("<{s}>", .{attribute.name});
    }
}

fn indent(out: anytype, depth: usize) !void {
    for (0..depth) |_| try out.writeAll("  ");
}

fn runRepl(allocator: std.mem.Allocator, cli: *Cli, state: *zlua.runtime.State) !?u8 {
    const io = cli.io;
    const tty = try stdinIsTty(io);
    var source = std.ArrayList(u8).empty;
    defer source.deinit(allocator);

    while (true) {
        if (tty) cli.stdout.writeAll(if (source.items.len == 0) "> " else ">> ") catch {};
        cli.flushStdout();
        const maybe_line = cli.stdin.takeDelimiter('\n') catch |err| switch (err) {
            error.StreamTooLong => {
                try stderrPrint(io, "input line too long\n", .{});
                cli.stdin.tossBuffered();
                source.items.len = 0;
                continue;
            },
            error.ReadFailed => return err,
        };
        const line = maybe_line orelse break;
        try source.appendSlice(allocator, line);
        try source.append(allocator, '\n');

        if (std.mem.trim(u8, source.items, " \t\r\n").len == 0) {
            source.items.len = 0;
            continue;
        }
        if (sourceLooksIncomplete(allocator, source.items)) continue;

        const repl_source = try replSourceAlloc(allocator, source.items);
        defer allocator.free(repl_source);
        if (try executeReplChunk(allocator, cli, state, repl_source)) |exit_code| return exit_code;
        source.items.len = 0;
    }

    if (source.items.len != 0) {
        const repl_source = try replSourceAlloc(allocator, source.items);
        defer allocator.free(repl_source);
        if (try executeReplChunk(allocator, cli, state, repl_source)) |exit_code| return exit_code;
    }
    return null;
}

fn replSourceAlloc(allocator: std.mem.Allocator, source: []const u8) ![]u8 {
    const trimmed_left = std.mem.trimStart(u8, source, " \t");
    if (std.mem.startsWith(u8, trimmed_left, "=")) {
        return std.fmt.allocPrint(allocator, "print({s})", .{trimmed_left[1..]});
    }
    if (canParseChunk(allocator, source)) return allocator.dupe(u8, source);

    const echo = try std.fmt.allocPrint(allocator, "print({s})", .{source});
    if (canParseChunk(allocator, echo)) return echo;
    allocator.free(echo);
    return allocator.dupe(u8, source);
}

fn canParseChunk(allocator: std.mem.Allocator, source: []const u8) bool {
    var tree = zlua.frontend.parse(allocator, source) catch return false;
    tree.deinit();
    return true;
}

fn sourceLooksIncomplete(allocator: std.mem.Allocator, source: []const u8) bool {
    var diagnostic: ?zlua.errors.Diagnostic = null;
    var tree = zlua.frontend.parseWithDiagnostic(allocator, source, &diagnostic) catch return diagnosticNearEof(diagnostic);
    tree.deinit();
    return false;
}

fn diagnosticNearEof(diagnostic: ?zlua.errors.Diagnostic) bool {
    const diag = diagnostic orelse return false;
    return switch (diag) {
        .syntax => |syntax| switch (syntax) {
            .unexpected => |unexpected| unexpected.token.tag == .eof,
            .expected => |expected| expected.near.tag == .eof,
            .expected_close => |expected| expected.near.tag == .eof,
        },
        else => false,
    };
}

/// Lua output is already streaming; the error goes straight to stderr and any
/// buffered stdout follows when the CLI exits, as with C `lua`.
fn executeChunkNamed(allocator: std.mem.Allocator, io: std.Io, state: *zlua.runtime.State, source: []const u8, source_name: []const u8) !?u8 {
    var traceback: ?[]u8 = null;
    defer if (traceback) |text| state.allocator.free(text);
    state.executeSourceChunkNamedHandled(source, source_name, .{ .traceback = &traceback, .host_frame = true }) catch |err| {
        if (err == error.LuaExit) return exitCode(state);
        const message = try errorReportAlloc(allocator, state, err, traceback);
        defer allocator.free(message);
        try stderrWrite(io, message);
        return 1;
    };
    return null;
}

fn executeReplChunk(allocator: std.mem.Allocator, cli: *Cli, state: *zlua.runtime.State, source: []const u8) !?u8 {
    defer cli.flushStdout();
    var traceback: ?[]u8 = null;
    defer if (traceback) |text| state.allocator.free(text);
    state.executeSourceChunkNamedHandled(source, "=stdin", .{ .traceback = &traceback, .host_frame = true }) catch |err| {
        if (err == error.LuaExit) return exitCode(state);
        const message = try errorReportAlloc(allocator, state, err, traceback);
        defer allocator.free(message);
        cli.flushStdout();
        try stderrWrite(cli.io, message);
        return null;
    };
    return null;
}

/// Formats an error like `lua.c`: `zlua: message`, followed by the traceback
/// captured at the error point for runtime errors.
fn errorReportAlloc(allocator: std.mem.Allocator, state: *zlua.runtime.State, err: anyerror, traceback: ?[]const u8) ![]u8 {
    const detail = try state.errorDetailAlloc(allocator, err);
    defer allocator.free(detail);
    if (traceback) |text| return std.fmt.allocPrint(allocator, "zlua: {s}\n{s}\n", .{ detail, text });
    return std.fmt.allocPrint(allocator, "zlua: {s}\n", .{detail});
}

/// `os.exit` unwound the state after flushing Lua output: exit with the low
/// byte of the requested code, as C `exit` does. The state is closed on the way out.
fn exitCode(state: *zlua.runtime.State) u8 {
    const request = state.exit_request orelse return 0;
    return @truncate(@as(u32, @bitCast(request.code)));
}

fn installArgTable(
    _: std.mem.Allocator,
    state: *zlua.runtime.State,
    args: []const []const u8,
    script_index: ?usize,
) !void {
    const zero_index = script_index orelse 0;
    const arg_value = try state.newTableWithHints(@intCast(args.len), 0);
    const table = arg_value.table;
    for (args, 0..) |arg, index| {
        const key: i64 = @as(i64, @intCast(index)) - @as(i64, @intCast(zero_index));
        try state.setTableRaw(table, .{ .integer = key }, .{ .string = try state.intern(arg) });
    }
    try state.putGlobal("arg", arg_value);
}

fn readStdinAlloc(allocator: std.mem.Allocator, io: std.Io) ![]u8 {
    var buffer: [8192]u8 = undefined;
    var reader = File.stdin().readerStreaming(io, &buffer);
    return reader.interface.allocRemaining(allocator, .limited(zlua.runtime.default_max_file_bytes));
}

fn stdinIsTty(io: std.Io) !bool {
    return File.stdin().isTty(io) catch false;
}

fn stripInitialShebang(source: []const u8) []const u8 {
    if (source.len == 0 or source[0] != '#') return source;
    const newline = std.mem.indexOfScalar(u8, source, '\n') orelse return "";
    return source[newline + 1 ..];
}

fn printVersion(io: std.Io) !void {
    try stdoutPrint(io, "zlua {s} ({s} target)\n", .{ zlua.version, zlua.lua_target_version });
}

fn printUsage(io: std.Io) !void {
    try stdoutPrint(io,
        \\Usage: zlua [options] [script [args...]]
        \\
        \\Options:
        \\  --version, -v
        \\  --debug-errors
        \\  --stdlib=none|base|safe|full|LIB[,LIB...]
        \\  -e 'chunk'
        \\  -i
        \\  --dump-ast [script]
        \\  --dump-scope [script]
        \\  --dump-bytecode [script]
        \\  --trace-vm [script]
        \\
    , .{});
}

fn stdoutPrint(io: std.Io, comptime fmt: []const u8, args: anytype) !void {
    var buffer: [4096]u8 = undefined;
    var writer = File.stdout().writerStreaming(io, &buffer);
    try writer.interface.print(fmt, args);
    try writer.interface.flush();
}

fn stderrPrint(io: std.Io, comptime fmt: []const u8, args: anytype) !void {
    var buffer: [4096]u8 = undefined;
    var writer = File.stderr().writerStreaming(io, &buffer);
    try writer.interface.print(fmt, args);
    try writer.interface.flush();
}

fn stderrWrite(io: std.Io, bytes: []const u8) !void {
    var buffer: [4096]u8 = undefined;
    var writer = File.stderr().writerStreaming(io, &buffer);
    try writer.interface.writeAll(bytes);
    try writer.interface.flush();
}

test "version constants are wired" {
    try std.testing.expect(std.mem.eql(u8, zlua.lua_target_version, "Lua 5.5"));
}

test "strips initial shebang for script execution" {
    try std.testing.expect(std.mem.eql(u8, stripInitialShebang("#!lua\nprint(1)"), "print(1)"));
}

test "CLI parser accepts milestone 20 options" {
    const args = [_][]const u8{ "zlua", "--stdlib=safe", "--trace-vm", "-i", "-e", "x=1", "script.lua", "a" };
    var options = try parseCliOptions(std.testing.allocator, &args);
    defer options.deinit(std.testing.allocator);
    try std.testing.expectEqual(zlua.runtime.StdlibMode.safe, options.stdlib);
    try std.testing.expect(options.trace_vm);
    try std.testing.expect(options.interactive);
    try std.testing.expectEqual(@as(usize, 1), options.evals.items.len);
    try std.testing.expectEqualStrings("script.lua", options.script_path.?);
    try std.testing.expectEqual(@as(usize, 6), options.script_index.?);
}

test "CLI parser accepts granular stdlib libraries" {
    const args = [_][]const u8{ "zlua", "--stdlib=base,string,json,toml,msgpack,csv,fs", "-e", "print('ok')" };
    var options = try parseCliOptions(std.testing.allocator, &args);
    defer options.deinit(std.testing.allocator);

    const libraries = options.stdlib.libraries;
    try std.testing.expect(libraries.base);
    try std.testing.expect(libraries.string);
    try std.testing.expect(libraries.json);
    try std.testing.expect(libraries.toml);
    try std.testing.expect(libraries.msgpack);
    try std.testing.expect(libraries.csv);
    try std.testing.expect(libraries.fs);
    try std.testing.expect(!libraries.table);
    try std.testing.expect(!libraries.io);
}

test "CLI arg table indexing matches Lua script position" {
    var state = try zlua.runtime.State.initWithOptions(std.testing.allocator, .{ .stdlib = .base });
    defer state.deinit();
    const args = [_][]const u8{ "zlua", "-e", "code", "script.lua", "a" };
    try installArgTable(std.testing.allocator, &state, &args, 3);
    const arg = state.getGlobal("arg").table;
    try std.testing.expectEqualStrings("zlua", arg.get(.{ .integer = -3 }).string);
    try std.testing.expectEqualStrings("-e", arg.get(.{ .integer = -2 }).string);
    try std.testing.expectEqualStrings("code", arg.get(.{ .integer = -1 }).string);
    try std.testing.expectEqualStrings("script.lua", arg.get(.{ .integer = 0 }).string);
    try std.testing.expectEqualStrings("a", arg.get(.{ .integer = 1 }).string);
}
