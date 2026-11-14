const std = @import("std");
const zlua = @import("zlua");
const repl = @import("cli/repl.zig");
const term = @import("cli/term.zig");
const entry_mod = zlua.runtime.entry;
const failure_mod = zlua.runtime.failure;

const ast = zlua.frontend.ast;
const Dir = std.Io.Dir;
const File = std.Io.File;
const EnvMap = std.process.Environ.Map;

const DumpMode = enum {
    none,
    ast,
    scope,
    bytecode,
};

/// A command-line step that runs before the script, in the order given.
const Action = union(enum) {
    eval: []const u8,
    /// `NAME` or `GLOBAL=NAME` from `-l`.
    require: []const u8,
    warnings_on,
};

const CliOptions = struct {
    actions: std.ArrayList(Action) = .empty,
    script_path: ?[]const u8 = null,
    script_index: ?usize = null,
    interactive: bool = false,
    ignore_env: bool = false,
    debug_errors: bool = false,
    trace_vm: bool = false,
    print_version: bool = false,
    print_help: bool = false,
    dump_mode: DumpMode = .none,
    stdlib: zlua.runtime.StdlibMode = .full,
    color: term.ColorMode = .auto,
    /// The argument a parse error is about.
    rejected: []const u8 = "",

    fn deinit(self: *CliOptions, allocator: std.mem.Allocator) void {
        self.actions.deinit(allocator);
        self.* = undefined;
    }

    fn hasEval(self: *const CliOptions) bool {
        for (self.actions.items) |action| if (action == .eval) return true;
        return false;
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
    var options: CliOptions = .{};
    defer options.deinit(allocator);
    parseCliOptions(allocator, args, &options) catch |err| {
        const rejected = options.rejected;
        switch (err) {
            error.OutOfMemory => return err,
            error.UnknownOption => try stderrPrint(io, "zlua: unrecognized option '{s}'\n", .{rejected}),
            error.MissingOptionValue => try stderrPrint(io, "zlua: '{s}' needs argument\n", .{rejected}),
            error.InvalidStdlibMode => try stderrPrint(io, "zlua: invalid --stdlib value '{s}'\n", .{rejected}),
            error.InvalidColorMode => try stderrPrint(io, "zlua: invalid --color value '{s}' (expected auto, always, or never)\n", .{rejected}),
        }
        try stderrPrint(io, "{s}", .{usage});
        return 1;
    };

    if (options.print_help) {
        try stdoutPrint(io, "{s}", .{usage});
        return 0;
    }
    if (options.print_version) try printVersion(io);

    if (options.dump_mode != .none) {
        return runDumpMode(allocator, io, &options);
    }

    const no_input = !options.hasEval() and options.script_path == null;
    if (options.print_version and no_input and !options.interactive and try stdinIsTty(io)) return 0;
    if (no_input and !options.interactive and try stdinIsTty(io)) {
        options.interactive = true;
    }

    var stdout_buffer: [4096]u8 = undefined;
    var stdout_writer = File.stdout().writerStreaming(io, &stdout_buffer);
    var stderr_buffer: [0]u8 = undefined;
    var stderr_writer = File.stderr().writerStreaming(io, &stderr_buffer);
    var stdin_buffer: [64 * 1024]u8 = undefined;
    var stdin_reader = File.stdin().readerStreaming(io, &stdin_buffer);
    const stdout_tty = File.stdout().isTty(io) catch false;
    var cli: Cli = .{ .io = io, .stdout = &stdout_writer.interface, .stdin = &stdin_reader.interface, .env = environ_map };

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
    const exit_code = runCliChunks(state_allocator, &cli, &state, args, &options) catch |err| {
        _ = cli.close(&state);
        return err;
    };
    return cli.close(&state) orelse exit_code;
}

fn runCliChunks(
    state_allocator: std.mem.Allocator,
    cli: *Cli,
    state: *zlua.runtime.State,
    args: []const []const u8,
    options: *CliOptions,
) !u8 {
    const io = cli.io;
    const no_input = !options.hasEval() and options.script_path == null;
    try installArgTable(state_allocator, state, args, options.script_index);

    if (!options.ignore_env) {
        try applyPathVariables(state_allocator, state, cli.env);
        if (cli.env.get("LUA_INIT_5_5") orelse cli.env.get("LUA_INIT")) |init| {
            if (std.mem.startsWith(u8, init, "@")) {
                if (try executeFile(state_allocator, io, state, init[1..], .chunk)) |exit_code| return exit_code;
            } else {
                if (try executeChunkNamed(state_allocator, io, state, init, "=LUA_INIT")) |exit_code| return exit_code;
            }
        }
    }

    for (options.actions.items) |action| switch (action) {
        .eval => |source| if (try executeChunkNamed(state_allocator, io, state, source, "=(command line)")) |exit_code| return exit_code,
        .require => |spec| if (try requireLibrary(state_allocator, io, state, spec)) |exit_code| return exit_code,
        .warnings_on => state.warnings_on = true,
    };

    if (options.script_path) |path| {
        if (std.mem.eql(u8, path, "-")) {
            const source = cli.readStdinAlloc(state_allocator) catch |err| {
                try stderrPrint(io, "zlua: cannot read stdin: {s}\n", .{zlua.runtime.fileError(err).message});
                return 1;
            };
            defer state_allocator.free(source);
            if (try executeScript(state_allocator, io, state, scriptSource(source), "@stdin")) |exit_code| return exit_code;
        } else {
            if (try executeFile(state_allocator, io, state, path, .script)) |exit_code| return exit_code;
        }
    } else if (no_input and !options.interactive) {
        const source = cli.readStdinAlloc(state_allocator) catch |err| {
            try stderrPrint(io, "zlua: cannot read stdin: {s}\n", .{zlua.runtime.fileError(err).message});
            return 1;
        };
        defer state_allocator.free(source);
        if (try executeChunkNamed(state_allocator, io, state, scriptSource(source), "@stdin")) |exit_code| return exit_code;
    }

    if (options.interactive) {
        const outcome = try repl.run(.{
            .allocator = state_allocator,
            .io = io,
            .state = state,
            .stdin = cli.stdin,
            .stdout = cli.stdout,
            .env = cli.env,
            .color = options.color,
            .banner = !options.print_version,
        });
        if (outcome == .exit_requested) return exitCode(state);
    }

    return 0;
}

fn executeFile(allocator: std.mem.Allocator, io: std.Io, state: *zlua.runtime.State, path: []const u8, kind: enum { script, chunk }) !?u8 {
    const source = Dir.cwd().readFileAlloc(io, path, allocator, .limited(zlua.runtime.default_max_file_bytes)) catch |err| {
        const failure = zlua.runtime.fileError(err);
        try stderrPrint(io, "zlua: cannot {s} {s}: {s}\n", .{ if (failure.read_phase) "read" else "open", path, failure.message });
        return 1;
    };
    defer allocator.free(source);
    const source_name = try std.fmt.allocPrint(allocator, "@{s}", .{path});
    defer allocator.free(source_name);
    return switch (kind) {
        .script => executeScript(allocator, io, state, scriptSource(source), source_name),
        .chunk => executeChunkNamed(allocator, io, state, scriptSource(source), source_name),
    };
}

fn requireLibrary(allocator: std.mem.Allocator, io: std.Io, state: *zlua.runtime.State, spec: []const u8) !?u8 {
    var global = spec;
    var module = spec;
    if (std.mem.indexOfScalar(u8, spec, '=')) |equals| {
        global = spec[0..equals];
        module = spec[equals + 1 ..];
    } else if (std.mem.indexOfScalar(u8, spec, '-')) |mark| {
        global = spec[0..mark];
    }
    const require = state.getGlobalValue("require");
    const argument: zlua.runtime.Value = .{ .string = try state.strings.intern(module) };
    const results = entry_mod.callFunctionHandled(state, require, &.{argument}, cli_error_handler) catch |err| return try reportFailure(allocator, io, state, err);
    defer state.allocator.free(results);
    var roots: zlua.runtime.ValueRoots = undefined;
    state.pushValueRoots(&roots, results);
    defer state.popValueRoots(&roots);
    try state.putGlobal(global, if (results.len == 0) .nil else results[0]);
    return null;
}

fn applyPathVariables(allocator: std.mem.Allocator, state: *zlua.runtime.State, env: *const EnvMap) !void {
    const package = state.getGlobalValue("package");
    if (package != .table) return;
    const variables = [_][3][]const u8{
        .{ "path", "LUA_PATH_5_5", "LUA_PATH" },
        .{ "cpath", "LUA_CPATH_5_5", "LUA_CPATH" },
    };
    for (variables) |variable| {
        const value = env.get(variable[1]) orelse env.get(variable[2]) orelse continue;
        const default = package.table.getBytes(variable[0]);
        const path = try expandPathVariable(allocator, value, if (default == .string) default.string.bytes() else "");
        defer allocator.free(path);
        const key = try state.strings.intern(variable[0]);
        try state.setTableRaw(package.table, .{ .string = key }, .{ .string = try state.strings.intern(path) });
    }
}

fn expandPathVariable(allocator: std.mem.Allocator, value: []const u8, default: []const u8) ![]u8 {
    const mark = std.mem.indexOf(u8, value, ";;") orelse return allocator.dupe(u8, value);
    const before = value[0..mark];
    const after = value[mark + 2 ..];
    return std.mem.concat(allocator, u8, &.{ before, if (before.len != 0) ";" else "", default, if (after.len != 0) ";" else "", after });
}

const Cli = struct {
    io: std.Io,
    stdout: *std.Io.Writer,
    stdin: *std.Io.Reader,
    env: *const EnvMap,

    fn flushStdout(self: *Cli) void {
        self.stdout.flush() catch {};
    }

    fn close(self: *Cli, state: *zlua.runtime.State) ?u8 {
        zlua.stdlib.io.flushOpenFiles(state);
        self.flushStdout();
        const exit_code = closeState(state);
        self.flushStdout();
        return exit_code;
    }

    fn readStdinAlloc(self: *Cli, allocator: std.mem.Allocator) ![]u8 {
        return self.stdin.allocRemaining(allocator, .limited(zlua.runtime.default_max_file_bytes));
    }
};

fn closeState(state: *zlua.runtime.State) ?u8 {
    const request = state.exit_request;
    if (request != null and !request.?.close) {
        state.deinitWithoutFinalizers();
        return null;
    }
    state.exit_request = null;
    state.gc.runCloseFinalizers(.stop);
    const finalizer_exit: ?u8 = if (state.exit_request != null) exitCode(state) else null;
    state.deinitWithoutFinalizers();
    return finalizer_exit;
}

const ParseError = error{ OutOfMemory, UnknownOption, MissingOptionValue, InvalidStdlibMode, InvalidColorMode };

fn parseCliOptions(allocator: std.mem.Allocator, args: []const []const u8, options: *CliOptions) ParseError!void {
    var index: usize = 1;
    while (index < args.len) : (index += 1) {
        const arg = args[index];
        options.rejected = arg;
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
        } else if (std.mem.eql(u8, arg, "-E")) {
            options.ignore_env = true;
        } else if (std.mem.eql(u8, arg, "-W")) {
            try options.actions.append(allocator, .warnings_on);
        } else if (std.mem.eql(u8, arg, "--dump-ast")) {
            options.dump_mode = .ast;
        } else if (std.mem.eql(u8, arg, "--dump-scope")) {
            options.dump_mode = .scope;
        } else if (std.mem.eql(u8, arg, "--dump-bytecode")) {
            options.dump_mode = .bytecode;
        } else if (std.mem.eql(u8, arg, "--stdlib") or std.mem.eql(u8, arg, "--color")) {
            index += 1;
            if (index >= args.len) return error.MissingOptionValue;
            options.rejected = args[index];
            if (std.mem.eql(u8, arg, "--stdlib")) {
                options.stdlib = try parseStdlibMode(args[index]);
            } else {
                options.color = term.ColorMode.parse(args[index]) orelse return error.InvalidColorMode;
            }
        } else if (std.mem.startsWith(u8, arg, "--stdlib=")) {
            options.rejected = arg[9..];
            options.stdlib = try parseStdlibMode(arg[9..]);
        } else if (std.mem.startsWith(u8, arg, "--color=")) {
            options.rejected = arg[8..];
            options.color = term.ColorMode.parse(arg[8..]) orelse return error.InvalidColorMode;
        } else if (std.mem.startsWith(u8, arg, "-e") or std.mem.startsWith(u8, arg, "-l")) {
            var value = arg[2..];
            if (value.len == 0) {
                index += 1;
                if (index >= args.len) return error.MissingOptionValue;
                value = args[index];
            }
            try options.actions.append(allocator, if (arg[1] == 'e') .{ .eval = value } else .{ .require = value });
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
    } else if (std.mem.eql(u8, name, "datetime")) {
        libraries.datetime = true;
    } else if (std.mem.eql(u8, name, "fs")) {
        libraries.fs = true;
    } else {
        return error.InvalidStdlibMode;
    }
}

fn runDumpMode(allocator: std.mem.Allocator, io: std.Io, options: *const CliOptions) !u8 {
    var source_info = readDumpInput(allocator, io, options) catch |err| {
        switch (err) {
            error.OutOfMemory => return err,
            error.MissingInput => try stderrPrint(io, "zlua: a dump option needs a script or an -e chunk\n", .{}),
            else => try stderrPrint(io, "zlua: cannot read {s}: {s}\n", .{ options.script_path orelse "stdin", zlua.runtime.fileError(err).message }),
        }
        return 1;
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
    if (options.hasEval()) {
        var source = std.ArrayList(u8).empty;
        errdefer source.deinit(allocator);
        for (options.actions.items) |action| {
            if (action != .eval) continue;
            try source.appendSlice(allocator, action.eval);
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

fn executeChunkNamed(allocator: std.mem.Allocator, io: std.Io, state: *zlua.runtime.State, source: []const u8, source_name: []const u8) !?u8 {
    entry_mod.executeSourceChunkNamedHandled(state, source, source_name, cli_error_handler) catch |err| return try reportFailure(allocator, io, state, err);
    return null;
}

/// The script's arguments are the positive entries of the `arg` table.
fn executeScript(allocator: std.mem.Allocator, io: std.Io, state: *zlua.runtime.State, source: []const u8, source_name: []const u8) !?u8 {
    const arg = state.getGlobalValue("arg");
    if (arg != .table) {
        try stderrPrint(io, "zlua: 'arg' is not a table\n", .{});
        return 1;
    }
    const loaded = zlua.runtime.load.loadSourceAsClosureNamed(state, source, source_name) catch |err| return try reportFailure(allocator, io, state, err);
    const args = try allocator.alloc(zlua.runtime.Value, @intCast(@max(arg.table.len(), 0)));
    defer allocator.free(args);
    for (args, 1..) |*value, position| value.* = arg.table.get(.{ .integer = @intCast(position) });
    const results = entry_mod.callFunctionHandled(state, loaded, args, cli_error_handler) catch |err| return try reportFailure(allocator, io, state, err);
    state.allocator.free(results);
    return null;
}

fn reportFailure(allocator: std.mem.Allocator, io: std.Io, state: *zlua.runtime.State, err: anyerror) !u8 {
    if (err == error.LuaExit) return exitCode(state);
    const message = try errorReportAlloc(allocator, state, err);
    defer allocator.free(message);
    try stderrWrite(io, message);
    return 1;
}

const cli_error_handler: zlua.runtime.HostErrorHandler = .{
    .message_handler = .{ .native = .traceback_message_handler },
    .host_frame = true,
};

fn errorReportAlloc(allocator: std.mem.Allocator, state: *zlua.runtime.State, err: anyerror) ![]u8 {
    if (state.last_error != null) {
        const value = state.currentErrorValue();
        if (value == .string) return std.fmt.allocPrint(allocator, "zlua: {s}\n", .{value.string.bytes()});
    }
    const detail = try failure_mod.errorDetailAlloc(state, allocator, err);
    defer allocator.free(detail);
    return std.fmt.allocPrint(allocator, "zlua: {s}\n", .{detail});
}

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
        try state.setTableRaw(table, .{ .integer = key }, .{ .string = try state.strings.intern(arg) });
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

fn scriptSource(source: []u8) []const u8 {
    zlua.stdlib.package.prepareTextFileSource(source);
    return source;
}

fn printVersion(io: std.Io) !void {
    try stdoutPrint(io, "zlua {s} ({s} target)\n", .{ zlua.version, zlua.lua_target_version });
}

const usage =
    \\Usage: zlua [options] [script [args...]]
    \\
    \\Options:
    \\  -e CHUNK          run CHUNK
    \\  -l NAME           require NAME into the global NAME
    \\  -l GLOBAL=NAME    require NAME into the global GLOBAL
    \\  -i                enter the REPL after the script
    \\  -E                ignore LUA_INIT, LUA_PATH, and LUA_CPATH
    \\  -W                turn warnings on
    \\  -v, --version     print the version
    \\  -h, --help        print this help
    \\  --stdlib=MODE     open none, base, safe, full, or a comma-separated list of libraries
    \\  --color=WHEN      color the REPL: auto, always, or never
    \\  --debug-errors    print internal runtime diagnostics
    \\  --trace-vm        print each VM instruction
    \\  --dump-ast        print the parsed script
    \\  --dump-scope      print the resolved scopes of the script
    \\  --dump-bytecode   print the compiled script
    \\  --                stop handling options
    \\  -                 run stdin as the script
    \\
;

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

test {
    _ = repl;
}

test "version constants are wired" {
    try std.testing.expect(std.mem.eql(u8, zlua.lua_target_version, "Lua 5.5"));
}

test "a script's byte order mark and shebang line keep its line numbers" {
    var source = "\xEF\xBB\xBF#!lua\nerror('x')".*;
    var state = try zlua.runtime.State.initWithOptions(std.testing.allocator, .{ .stdlib = .base });
    defer state.deinit();
    try std.testing.expectError(error.RuntimeError, entry_mod.executeSourceChunkNamed(&state, scriptSource(&source), "@script.lua"));
    try std.testing.expectEqualStrings("script.lua:2: x", state.currentErrorValue().string.bytes());
}

test "CLI parser reads options up to the script" {
    const args = [_][]const u8{ "zlua", "--stdlib=safe", "--trace-vm", "-E", "--color", "never", "-i", "-e", "x=1", "script.lua", "-e", "a" };
    var options: CliOptions = .{};
    defer options.deinit(std.testing.allocator);
    try parseCliOptions(std.testing.allocator, &args, &options);
    try std.testing.expectEqual(zlua.runtime.StdlibMode.safe, options.stdlib);
    try std.testing.expect(options.trace_vm);
    try std.testing.expect(options.interactive);
    try std.testing.expect(options.ignore_env);
    try std.testing.expectEqual(term.ColorMode.never, options.color);
    try std.testing.expectEqual(@as(usize, 1), options.actions.items.len);
    try std.testing.expectEqualStrings("script.lua", options.script_path.?);
    try std.testing.expectEqual(@as(usize, 9), options.script_index.?);
}

test "CLI parser keeps -e, -l, and -W in order" {
    const args = [_][]const u8{ "zlua", "-e", "a()", "-W", "-lmod", "-l", "g=mod", "-eb()" };
    var options: CliOptions = .{};
    defer options.deinit(std.testing.allocator);
    try parseCliOptions(std.testing.allocator, &args, &options);
    const actions = options.actions.items;
    try std.testing.expectEqual(@as(usize, 5), actions.len);
    try std.testing.expectEqualStrings("a()", actions[0].eval);
    try std.testing.expect(actions[1] == .warnings_on);
    try std.testing.expectEqualStrings("mod", actions[2].require);
    try std.testing.expectEqualStrings("g=mod", actions[3].require);
    try std.testing.expectEqualStrings("b()", actions[4].eval);
}

test "CLI parser names the argument it rejects" {
    const cases = [_]struct { args: []const []const u8, err: ParseError, rejected: []const u8 }{
        .{ .args = &.{ "zlua", "--bogus" }, .err = error.UnknownOption, .rejected = "--bogus" },
        .{ .args = &.{ "zlua", "-e" }, .err = error.MissingOptionValue, .rejected = "-e" },
        .{ .args = &.{ "zlua", "--stdlib=base,nope" }, .err = error.InvalidStdlibMode, .rejected = "base,nope" },
        .{ .args = &.{ "zlua", "--color=blue" }, .err = error.InvalidColorMode, .rejected = "blue" },
    };
    for (cases) |case| {
        var options: CliOptions = .{};
        defer options.deinit(std.testing.allocator);
        try std.testing.expectError(case.err, parseCliOptions(std.testing.allocator, case.args, &options));
        try std.testing.expectEqualStrings(case.rejected, options.rejected);
    }
}

test "a script receives the arg table's positive entries" {
    var buffer: [64]u8 = undefined;
    var stdout: std.Io.Writer = .fixed(&buffer);
    var state = try zlua.runtime.State.initWithOptions(std.testing.allocator, .{ .stdlib = .base, .stdout = &stdout, .capture_output = false });
    defer state.deinit();
    const args = [_][]const u8{ "zlua", "script.lua", "a", "b" };
    try installArgTable(std.testing.allocator, &state, &args, 1);
    try std.testing.expect(try executeScript(std.testing.allocator, std.testing.io, &state, "print(select('#', ...), ...)", "@script.lua") == null);
    try std.testing.expectEqualStrings("2\ta\tb\n", stdout.buffered());
}

test "-l stores the required module in a global" {
    var state = try zlua.runtime.State.initWithOptions(std.testing.allocator, .{ .stdlib = .full });
    defer state.deinit();
    try entry_mod.executeSourceChunkNamed(&state, "package.preload['mod-v2'] = function() return {answer = 42} end", "=setup");
    try std.testing.expect(try requireLibrary(std.testing.allocator, std.testing.io, &state, "mod-v2") == null);
    try std.testing.expect(try requireLibrary(std.testing.allocator, std.testing.io, &state, "m=mod-v2") == null);
    try entry_mod.executeSourceChunkNamed(&state, "assert(mod.answer == 42 and m == mod)", "=check");
}

test "LUA_PATH replaces ;; with the default path" {
    const cases = [_][2][]const u8{
        .{ "./?.lua", "./?.lua" },
        .{ ";;", "DEFAULT" },
        .{ "a/?.lua;;", "a/?.lua;DEFAULT" },
        .{ ";;b/?.lua", "DEFAULT;b/?.lua" },
        .{ "a/?.lua;;b/?.lua", "a/?.lua;DEFAULT;b/?.lua" },
    };
    for (cases) |case| {
        const path = try expandPathVariable(std.testing.allocator, case[0], "DEFAULT");
        defer std.testing.allocator.free(path);
        try std.testing.expectEqualStrings(case[1], path);
    }
}

test "CLI parser accepts granular stdlib libraries" {
    const args = [_][]const u8{ "zlua", "--stdlib=base,string,json,toml,msgpack,csv,fs", "-e", "print('ok')" };
    var options: CliOptions = .{};
    defer options.deinit(std.testing.allocator);
    try parseCliOptions(std.testing.allocator, &args, &options);

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
    try std.testing.expectEqualStrings("zlua", arg.get(.{ .integer = -3 }).string.bytes());
    try std.testing.expectEqualStrings("-e", arg.get(.{ .integer = -2 }).string.bytes());
    try std.testing.expectEqualStrings("code", arg.get(.{ .integer = -1 }).string.bytes());
    try std.testing.expectEqualStrings("script.lua", arg.get(.{ .integer = 0 }).string.bytes());
    try std.testing.expectEqualStrings("a", arg.get(.{ .integer = 1 }).string.bytes());
}

fn cliErrorReport(source: []const u8) ![]u8 {
    var state = try zlua.runtime.State.initWithOptions(std.testing.allocator, .{ .stdlib = .full });
    defer state.deinit();
    entry_mod.executeSourceChunkNamedHandled(&state, source, "=(command line)", cli_error_handler) catch |err| {
        return errorReportAlloc(std.testing.allocator, &state, err);
    };
    return error.TestExpectedError;
}

test "uncaught error objects are reported like lua.c's message handler" {
    const plain_trace = "stack traceback:\n\t[C]: in global 'error'\n\t(command line):1: in main chunk\n\t[C]: in ?\n";
    const cases = [_][2][]const u8{
        .{ "error({})", "zlua: (error object is a table value)\n" ++ plain_trace },
        .{ "error(nil)", "zlua: (error object is a nil value)\n" ++ plain_trace },
        .{ "error(42)", "zlua: 42\n" ++ plain_trace },
        .{ "error(true)", "zlua: (error object is a boolean value)\n" ++ plain_trace },
        .{ "error(setmetatable({}, {__tostring = function() return 'custom' end}))", "zlua: custom\n" },
        .{ "error(setmetatable({}, {__tostring = function() return 7 end}))", "zlua: (error object is a table value)\n" ++ plain_trace },
        .{
            "error(setmetatable({}, {__tostring = function() error('x') end}))",
            "zlua: (command line):1: x\nstack traceback:\n\t[C]: in global 'error'\n\t(command line):1: in function <(command line):1>\n\t[C]: in ?\n\t[C]: in global 'error'\n\t(command line):1: in main chunk\n\t[C]: in ?\n",
        },
    };
    for (cases) |case| {
        const report = try cliErrorReport(case[0]);
        defer std.testing.allocator.free(report);
        try std.testing.expectEqualStrings(case[1], report);
    }
    const file_report = try cliErrorReport("error(io.stdout)");
    defer std.testing.allocator.free(file_report);
    try std.testing.expect(std.mem.startsWith(u8, file_report, "zlua: file (0x") and std.mem.endsWith(u8, file_report, ")\n"));
}

test "closing the CLI state runs finalizers unless os.exit skips lua_close" {
    const cases = [_][2][]const u8{
        .{ "KEEP = setmetatable({}, {__gc = function() print('bye') end})", "bye\n" },
        .{ "KEEP = setmetatable({}, {__gc = function() print('bye') end}) error('x')", "bye\n" },
        .{ "KEEP = setmetatable({}, {__gc = function() print('bye') end}) os.exit(true, true)", "bye\n" },
        .{ "KEEP = setmetatable({}, {__gc = function() print('bye') end}) local x <close> = setmetatable({}, {__close = function() print('closed') end}) os.exit(0, true)", "closed\nbye\n" },
        .{ "KEEP = setmetatable({}, {__gc = function() print('bye') end}) local x <close> = setmetatable({}, {__close = function() print('closed') end}) os.exit(3)", "" },
    };
    for (cases) |case| {
        var buffer: [64]u8 = undefined;
        var stdout: std.Io.Writer = .fixed(&buffer);
        var state = try zlua.runtime.State.initWithOptions(std.testing.allocator, .{ .stdlib = .full, .process = .enabled, .stdout = &stdout, .capture_output = false });
        entry_mod.executeSourceChunkNamed(&state, case[0], "=(command line)") catch {};
        _ = closeState(&state);
        try std.testing.expectEqualStrings(case[1], stdout.buffered());
    }
}

test "the CLI message handler runs at the error point" {
    const cases = [_][2][]const u8{
        .{
            "local x <close> = setmetatable({}, {__close = function(_, e) print('close:', e) end}) error('boom')",
            "close:\t(command line):1: boom\nstack traceback:\n\t[C]: in global 'error'\n\t(command line):1: in main chunk\n\t[C]: in ?\n",
        },
        .{
            "print(load(function() error('rd') end))",
            "nil\t(command line):1: rd\nstack traceback:\n\t[C]: in global 'error'\n\t(command line):1: in function <(command line):1>\n\t[C]: in global 'load'\n\t(command line):1: in main chunk\n\t[C]: in ?\n",
        },
    };
    for (cases) |case| {
        var buffer: [512]u8 = undefined;
        var stdout: std.Io.Writer = .fixed(&buffer);
        var state = try zlua.runtime.State.initWithOptions(std.testing.allocator, .{ .stdlib = .full, .stdout = &stdout, .capture_output = false });
        defer state.deinit();
        entry_mod.executeSourceChunkNamedHandled(&state, case[0], "=(command line)", cli_error_handler) catch {};
        try std.testing.expectEqualStrings(case[1], stdout.buffered());
    }
}

test "os.exit in a finalizer while closing sets the CLI status" {
    const Case = struct { source: []const u8, output: []const u8, code: ?u8 };
    const cases = [_]Case{
        .{
            .source = "A = setmetatable({}, {__gc = function() print('older') end}) B = setmetatable({}, {__gc = function() print('exit') os.exit(7) end}) C = setmetatable({}, {__gc = function() print('newest') end})",
            .output = "newest\nexit\n",
            .code = 7,
        },
        .{ .source = "B = setmetatable({}, {__gc = function() os.exit(true) end}) error('x')", .output = "", .code = 0 },
        .{ .source = "B = setmetatable({}, {__gc = function() io.write('buffered') os.exit(false, true) end})", .output = "buffered", .code = 1 },
        .{ .source = "B = setmetatable({}, {__gc = function() print('no exit') end})", .output = "no exit\n", .code = null },
    };
    for (cases) |case| {
        var buffer: [64]u8 = undefined;
        var stdout: std.Io.Writer = .fixed(&buffer);
        var state = try zlua.runtime.State.initWithOptions(std.testing.allocator, .{ .stdlib = .full, .process = .enabled, .stdout = &stdout, .capture_output = false });
        entry_mod.executeSourceChunkNamed(&state, case.source, "=(command line)") catch {};
        try std.testing.expectEqual(case.code, closeState(&state));
        try std.testing.expectEqualStrings(case.output, stdout.buffered());
    }
}
