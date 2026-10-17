const std = @import("std");
const builtin = @import("builtin");
const errors = @import("../errors.zig");
const stdlib = @import("../stdlib.zig");
const host = @import("host.zig");
const state_mod = @import("state.zig");
const types = @import("types.zig");
const value_mod = @import("value.zig");

const State = state_mod.State;
const Dir = std.Io.Dir;
const RuntimeError = types.RuntimeError;
const Value = types.Value;
const appendFmt = value_mod.appendFmt;
const OutputFlush = state_mod.OutputFlush;

/// Failures raise PUC `loadfile`-style messages such as "cannot open name.lua: No such file or directory".
pub fn readFileAlloc(self: *State, path: []const u8) ![]const u8 {
    return readFileRaw(self, path) catch |err| {
        if (err == error.OutOfMemory) return error.OutOfMemory;
        const info = host.fileError(err);
        const message = if (err == error.IsDir)
            try std.fmt.allocPrint(self.allocator, "cannot read {s}", .{path})
        else
            try std.fmt.allocPrint(self.allocator, "cannot {s} {s}: {s}", .{ if (info.read_phase) "read" else "open", path, info.message });
        defer self.allocator.free(message);
        return self.fail(try self.strings.intern(message));
    };
}

/// Like `readFileAlloc`, but returns filesystem errors unchanged.
pub fn readFileRaw(self: *State, path: []const u8) anyerror![]const u8 {
    return fsReadFileAlloc(self, path, self.options.max_file_bytes);
}

/// Raises "<path>: <strerror message>" for a failed file operation.
fn failFileOperation(self: *State, path: []const u8, err: anyerror) anyerror {
    if (err == error.OutOfMemory) return error.OutOfMemory;
    const message = try std.fmt.allocPrint(self.allocator, "{s}: {s}", .{ path, host.fileError(err).message });
    defer self.allocator.free(message);
    return self.fail(try self.strings.intern(message));
}

pub fn writeStdout(self: *State, bytes: []const u8) !void {
    if (self.options.capture_output) {
        if (self.rollback) |journal| try journal.outputWritable(self);
        try self.stdout.appendSlice(self.allocator, bytes);
    }
    if (self.options.stdout) |writer| try writeOutput(writer, self.options.stdout_flush, bytes);
}

/// Emits one warning made of `parts`, like continued `lua_warning` calls. A single
/// part starting with `@` is a control message.
pub fn warn(self: *State, parts: []const []const u8) !void {
    if (parts.len == 1 and std.mem.startsWith(u8, parts[0], "@")) {
        const control = parts[0][1..];
        if (std.mem.eql(u8, control, "on")) self.warnings_on = true;
        if (std.mem.eql(u8, control, "off")) self.warnings_on = false;
        return;
    }
    if (!self.warnings_on) return;
    if (self.options.warning_handler) |handler| {
        const message = try std.mem.concat(self.allocator, u8, parts);
        defer self.allocator.free(message);
        handler.emit(handler.context, message);
        return;
    }
    try writeStderr(self, "Lua warning: ");
    for (parts) |part| try writeStderr(self, part);
    try writeStderr(self, "\n");
}

/// Like `luaE_warnerror`: warns `error in <where> (<message>)`.
pub fn warnError(self: *State, where: []const u8, error_value: Value) void {
    const message = switch (error_value) {
        .string => |text| text,
        .nil => "<no error object>",
        else => "error object is not a string",
    };
    warn(self, &.{ "error in ", where, " (", message, ")" }) catch {};
}

pub fn writeStderr(self: *State, bytes: []const u8) !void {
    if (self.options.capture_output) {
        if (self.rollback) |journal| try journal.outputWritable(self);
        try self.stderr.appendSlice(self.allocator, bytes);
    }
    if (self.options.stderr) |writer| try writeOutput(writer, self.options.stderr_flush, bytes);
}

fn writeOutput(writer: *std.Io.Writer, policy: OutputFlush, bytes: []const u8) !void {
    try writer.writeAll(bytes);
    switch (policy) {
        .explicit, .print => {},
        .line => if (std.mem.indexOfScalar(u8, bytes, '\n') != null) try writer.flush(),
        .always => try writer.flush(),
    }
}

pub fn flushStdoutAfterPrint(self: *State) !void {
    if (self.options.stdout_flush == .print) try flushStdout(self);
}

/// Flushes line-buffered or unbuffered stdout before blocking on stdin, as C stdio does.
fn flushStdoutForInput(self: *State) void {
    switch (self.options.stdout_flush) {
        .explicit, .print => {},
        .line, .always => flushStdout(self) catch {},
    }
}

pub fn flushStdout(self: *State) !void {
    if (self.options.stdout) |writer| try writer.flush();
}

pub fn flushStderr(self: *State) !void {
    if (self.options.stderr) |writer| try writer.flush();
}

pub fn writeFile(self: *State, path: []const u8, data: []const u8) !void {
    fsWriteFile(self, path, data) catch |err| return failFileOperation(self, path, err);
}

pub fn removeFile(self: *State, path: []const u8) !void {
    fsRemovePath(self, path, false) catch |err| return failFileOperation(self, path, err);
}

pub fn renameFile(self: *State, old_path: []const u8, new_path: []const u8) !void {
    fsRenamePath(self, old_path, new_path) catch |err| return failFileOperation(self, old_path, err);
}

/// Also capped by `max_file_bytes`.
pub fn fsReadFileAlloc(self: *State, path: []const u8, requested_max_bytes: usize) anyerror![]const u8 {
    const max_bytes = @min(requested_max_bytes, self.options.max_file_bytes);
    switch (self.options.filesystem) {
        .disabled => return error.FilesystemDisabled,
        .memory => |files| {
            const normalized = try host.MemoryFilesystem.normalizePathAlloc(self.allocator, path, host.MemoryFilesystem.default_max_path_len);
            defer self.allocator.free(normalized);
            for (files) |file| {
                if (std.mem.eql(u8, file.path, normalized)) {
                    if (file.contents.len > max_bytes) return error.StreamTooLong;
                    return self.allocator.dupe(u8, file.contents);
                }
            }
            for (files) |file| {
                if (file.path.len > normalized.len and std.mem.startsWith(u8, file.path, normalized) and file.path[normalized.len] == '/') return error.IsDir;
            }
            return error.FileNotFound;
        },
        .memory_rw => |filesystem| {
            const bytes = try filesystem.readFileAlloc(self.allocator, path);
            if (bytes.len > max_bytes) {
                self.allocator.free(bytes);
                return error.StreamTooLong;
            }
            return bytes;
        },
        .custom => |filesystem| {
            const bytes = try filesystem.read_file_alloc(filesystem.context, self.allocator, path);
            if (bytes.len > max_bytes) {
                self.allocator.free(bytes);
                return error.StreamTooLong;
            }
            return bytes;
        },
        .host_cwd => if (comptime builtin.os.tag == .freestanding) return error.OperationUnsupported else {
            const io = self.options.io orelse return error.IoUnavailable;
            return Dir.cwd().readFileAlloc(io, path, self.allocator, .limited(max_bytes));
        },
        .host_dir => |root| if (comptime builtin.os.tag == .freestanding) return error.OperationUnsupported else {
            const io = self.options.io orelse return error.IoUnavailable;
            const normalized = try host.MemoryFilesystem.normalizePathAlloc(self.allocator, path, host.MemoryFilesystem.default_max_path_len);
            defer self.allocator.free(normalized);
            return root.dir.readFileAlloc(io, normalized, self.allocator, .limited(max_bytes));
        },
    }
}

pub fn fsWriteFile(self: *State, path: []const u8, data: []const u8) anyerror!void {
    self.file_generation +%= 1;
    switch (self.options.filesystem) {
        .disabled, .memory => return error.FilesystemReadOnly,
        .memory_rw => |filesystem| return filesystem.writeFile(path, data),
        .custom => |filesystem| {
            const write = filesystem.write_file orelse return error.OperationUnsupported;
            return write(filesystem.context, path, data);
        },
        .host_cwd => if (comptime builtin.os.tag == .freestanding) return error.OperationUnsupported else {
            const io = self.options.io orelse return error.IoUnavailable;
            return Dir.cwd().writeFile(io, .{ .sub_path = path, .data = data });
        },
        .host_dir => |root| if (comptime builtin.os.tag == .freestanding) return error.OperationUnsupported else {
            if (root.read_only) return error.FilesystemReadOnly;
            const io = self.options.io orelse return error.IoUnavailable;
            const normalized = try host.MemoryFilesystem.normalizePathAlloc(self.allocator, path, host.MemoryFilesystem.default_max_path_len);
            defer self.allocator.free(normalized);
            return root.dir.writeFile(io, .{ .sub_path = normalized, .data = data });
        },
    }
}

/// Reserves a new empty file like `mkstemp`, failing with `error.PathAlreadyExists`.
/// Only host filesystems create exclusively; others check first.
pub fn fsCreateFileExclusive(self: *State, path: []const u8) anyerror!void {
    switch (self.options.filesystem) {
        .disabled => return error.FilesystemDisabled,
        .memory => return error.FilesystemReadOnly,
        .memory_rw => |filesystem| {
            if (filesystem.statPath(path)) |_| return error.PathAlreadyExists else |err| if (err != error.FileNotFound) return err;
            try filesystem.writeFile(path, "");
        },
        .custom => |filesystem| {
            const write = filesystem.write_file orelse return error.OperationUnsupported;
            if (filesystem.stat) |stat| {
                if (stat(filesystem.context, path, false)) |_| return error.PathAlreadyExists else |err| if (err != error.FileNotFound) return err;
            } else if (filesystem.read_file_alloc(filesystem.context, self.allocator, path)) |bytes| {
                self.allocator.free(bytes);
                return error.PathAlreadyExists;
            } else |err| switch (err) {
                error.FileNotFound => {},
                error.IsDir => return error.PathAlreadyExists,
                else => return err,
            }
            try write(filesystem.context, path, "");
        },
        .host_cwd => if (comptime builtin.os.tag == .freestanding) return error.OperationUnsupported else {
            const io = self.options.io orelse return error.IoUnavailable;
            const file = if (std.fs.path.isAbsolute(path))
                try Dir.createFileAbsolute(io, path, .{ .exclusive = true })
            else
                try Dir.cwd().createFile(io, path, .{ .exclusive = true });
            file.close(io);
        },
        .host_dir => |root| if (comptime builtin.os.tag == .freestanding) return error.OperationUnsupported else {
            if (root.read_only) return error.FilesystemReadOnly;
            const io = self.options.io orelse return error.IoUnavailable;
            const normalized = try host.MemoryFilesystem.normalizePathAlloc(self.allocator, path, host.MemoryFilesystem.default_max_path_len);
            defer self.allocator.free(normalized);
            const file = try root.dir.createFile(io, normalized, .{ .exclusive = true });
            file.close(io);
        },
    }
    self.file_generation +%= 1;
}

/// Writes into an existing file without truncating it. Returns `error.OperationUnsupported`
/// without positional writes; callers then fall back to `fsWriteFile`.
pub fn fsWriteFileAt(self: *State, path: []const u8, offset: usize, data: []const u8) anyerror!void {
    return fsWritePositioned(self, path, offset, data);
}

/// Custom filesystems lack positional writes, so the whole file is rewritten.
pub fn fsAppendFile(self: *State, path: []const u8, data: []const u8) anyerror!void {
    if (self.options.filesystem != .custom) return fsWritePositioned(self, path, null, data);
    const old = try readFileRaw(self, path);
    defer self.allocator.free(old);
    const joined = try std.mem.concat(self.allocator, u8, &.{ old, data });
    defer self.allocator.free(joined);
    try fsWriteFile(self, path, joined);
}

/// A null `offset` appends.
fn fsWritePositioned(self: *State, path: []const u8, offset: ?usize, data: []const u8) anyerror!void {
    switch (self.options.filesystem) {
        .disabled, .memory => return error.FilesystemReadOnly,
        .memory_rw => |filesystem| {
            const position = offset orelse std.math.cast(usize, (try filesystem.statPath(path)).size) orelse return error.FileTooBig;
            try filesystem.writeAt(path, position, data);
            self.file_generation +%= 1;
        },
        .custom => return error.OperationUnsupported,
        .host_cwd, .host_dir => {
            if (comptime builtin.os.tag == .freestanding) return error.OperationUnsupported;
            const io = self.options.io orelse return error.IoUnavailable;
            const root: Dir = switch (self.options.filesystem) {
                .host_cwd => Dir.cwd(),
                .host_dir => |value| blk: {
                    if (value.read_only) return error.FilesystemReadOnly;
                    break :blk value.dir;
                },
                else => unreachable,
            };
            const owned = if (self.options.filesystem == .host_dir) try host.MemoryFilesystem.normalizePathAlloc(self.allocator, path, host.MemoryFilesystem.default_max_path_len) else null;
            defer if (owned) |normalized| self.allocator.free(normalized);
            const sub_path = owned orelse path;
            // Zig 0.16 sizes a Windows handle with a query write-only handles may not make.
            const position: u64 = offset orelse (try root.statFile(io, sub_path, .{})).size;
            var file = try root.openFile(io, sub_path, .{ .mode = .write_only, .allow_directory = false });
            defer file.close(io);
            self.file_generation +%= 1;
            try file.writePositionalAll(io, data, position);
        },
    }
}

/// Checks an existing file is writable without changing it, as `fopen` does for append modes.
pub fn fsCheckWritable(self: *State, path: []const u8) anyerror!void {
    switch (self.options.filesystem) {
        .custom => |filesystem| if (filesystem.write_file == null) return error.OperationUnsupported,
        else => try fsWriteFileAt(self, path, 0, ""),
    }
}

pub fn fsStat(self: *State, path: []const u8, follow_symlinks: bool) anyerror!host.FileStat {
    switch (self.options.filesystem) {
        .disabled => return error.FilesystemDisabled,
        .memory => |files| {
            var view = try host.MemoryFilesystem.initWithFiles(self.allocator, files);
            defer view.deinit();
            return view.statPath(path);
        },
        .memory_rw => |filesystem| return filesystem.statPath(path),
        .custom => |filesystem| {
            const stat = filesystem.stat orelse return error.OperationUnsupported;
            return stat(filesystem.context, path, follow_symlinks);
        },
        .host_cwd => if (comptime builtin.os.tag == .freestanding) return error.OperationUnsupported else {
            const io = self.options.io orelse return error.IoUnavailable;
            return .fromStd(try Dir.cwd().statFile(io, path, .{ .follow_symlinks = follow_symlinks }));
        },
        .host_dir => |root| if (comptime builtin.os.tag == .freestanding) return error.OperationUnsupported else {
            const io = self.options.io orelse return error.IoUnavailable;
            const normalized = try host.MemoryFilesystem.normalizeRootPathAlloc(self.allocator, path, host.MemoryFilesystem.default_max_path_len);
            defer self.allocator.free(normalized);
            if (normalized.len == 0) return .fromStd(try root.dir.stat(io));
            return .fromStd(try root.dir.statFile(io, normalized, .{ .follow_symlinks = follow_symlinks }));
        },
    }
}

pub fn fsReadDirAlloc(self: *State, path: []const u8) anyerror![]host.DirectoryEntry {
    switch (self.options.filesystem) {
        .disabled => return error.FilesystemDisabled,
        .memory => |files| {
            var view = try host.MemoryFilesystem.initWithFiles(self.allocator, files);
            defer view.deinit();
            return view.readDirAlloc(self.allocator, path);
        },
        .memory_rw => |filesystem| return filesystem.readDirAlloc(self.allocator, path),
        .custom => |filesystem| {
            const read_dir = filesystem.read_dir_alloc orelse return error.OperationUnsupported;
            return read_dir(filesystem.context, self.allocator, path);
        },
        .host_cwd, .host_dir => {
            if (comptime builtin.os.tag == .freestanding) return error.OperationUnsupported;
            const io = self.options.io orelse return error.IoUnavailable;
            const base: Dir = switch (self.options.filesystem) {
                .host_cwd => Dir.cwd(),
                .host_dir => |root| root.dir,
                else => unreachable,
            };
            const owned_path = if (self.options.filesystem == .host_dir)
                try host.MemoryFilesystem.normalizeRootPathAlloc(self.allocator, path, host.MemoryFilesystem.default_max_path_len)
            else
                null;
            defer if (owned_path) |normalized| self.allocator.free(normalized);
            const open_path = if (owned_path) |normalized| if (normalized.len == 0) "." else normalized else path;
            var dir = try base.openDir(io, open_path, .{ .iterate = true });
            defer dir.close(io);
            var iterator = dir.iterate();
            var entries: std.ArrayList(host.DirectoryEntry) = .empty;
            errdefer {
                for (entries.items) |entry| self.allocator.free(entry.name);
                entries.deinit(self.allocator);
            }
            while (try iterator.next(io)) |entry| {
                try entries.append(self.allocator, .{
                    .name = try self.allocator.dupe(u8, entry.name),
                    .kind = .fromStd(entry.kind),
                    .inode = @intCast(entry.inode),
                });
            }
            return entries.toOwnedSlice(self.allocator);
        },
    }
}

pub fn fsMakeDir(self: *State, path: []const u8, parents: bool) anyerror!void {
    switch (self.options.filesystem) {
        .disabled, .memory => return error.FilesystemReadOnly,
        .memory_rw => |filesystem| return filesystem.makeDir(path, parents),
        .custom => |filesystem| {
            const make_dir = filesystem.make_dir orelse return error.OperationUnsupported;
            return make_dir(filesystem.context, path, parents);
        },
        .host_cwd, .host_dir => {
            if (comptime builtin.os.tag == .freestanding) return error.OperationUnsupported;
            const root: Dir = switch (self.options.filesystem) {
                .host_cwd => Dir.cwd(),
                .host_dir => |value| blk: {
                    if (value.read_only) return error.FilesystemReadOnly;
                    break :blk value.dir;
                },
                else => unreachable,
            };
            const io = self.options.io orelse return error.IoUnavailable;
            const owned = if (self.options.filesystem == .host_dir) try host.MemoryFilesystem.normalizePathAlloc(self.allocator, path, host.MemoryFilesystem.default_max_path_len) else null;
            defer if (owned) |normalized| self.allocator.free(normalized);
            const actual = owned orelse path;
            if (parents) return root.createDirPath(io, actual);
            return root.createDir(io, actual, .default_dir);
        },
    }
}

pub fn fsRemovePath(self: *State, path: []const u8, recursive: bool) anyerror!void {
    self.file_generation +%= 1;
    switch (self.options.filesystem) {
        .disabled, .memory => return error.FilesystemReadOnly,
        .memory_rw => |filesystem| return filesystem.removePath(path, recursive),
        .custom => |filesystem| {
            if (filesystem.remove_path) |remove_path| return remove_path(filesystem.context, path, recursive);
            if (!recursive) if (filesystem.remove_file) |remove_file| return remove_file(filesystem.context, path);
            return error.OperationUnsupported;
        },
        .host_cwd, .host_dir => {
            if (comptime builtin.os.tag == .freestanding) return error.OperationUnsupported;
            const root: Dir = switch (self.options.filesystem) {
                .host_cwd => Dir.cwd(),
                .host_dir => |value| blk: {
                    if (value.read_only) return error.FilesystemReadOnly;
                    break :blk value.dir;
                },
                else => unreachable,
            };
            const io = self.options.io orelse return error.IoUnavailable;
            const owned = if (self.options.filesystem == .host_dir) try host.MemoryFilesystem.normalizePathAlloc(self.allocator, path, host.MemoryFilesystem.default_max_path_len) else null;
            defer if (owned) |normalized| self.allocator.free(normalized);
            const actual = owned orelse path;
            if (recursive) return root.deleteTree(io, actual);
            const stat = try root.statFile(io, actual, .{ .follow_symlinks = false });
            return if (stat.kind == .directory) root.deleteDir(io, actual) else root.deleteFile(io, actual);
        },
    }
}

pub fn fsRenamePath(self: *State, old_path: []const u8, new_path: []const u8) anyerror!void {
    self.file_generation +%= 1;
    switch (self.options.filesystem) {
        .disabled, .memory => return error.FilesystemReadOnly,
        .memory_rw => |filesystem| return filesystem.renamePath(old_path, new_path),
        .custom => |filesystem| {
            const rename = filesystem.rename_file orelse return error.OperationUnsupported;
            return rename(filesystem.context, old_path, new_path);
        },
        .host_cwd, .host_dir => {
            if (comptime builtin.os.tag == .freestanding) return error.OperationUnsupported;
            const root: Dir = switch (self.options.filesystem) {
                .host_cwd => Dir.cwd(),
                .host_dir => |value| blk: {
                    if (value.read_only) return error.FilesystemReadOnly;
                    break :blk value.dir;
                },
                else => unreachable,
            };
            const io = self.options.io orelse return error.IoUnavailable;
            const old_owned = if (self.options.filesystem == .host_dir) try host.MemoryFilesystem.normalizePathAlloc(self.allocator, old_path, host.MemoryFilesystem.default_max_path_len) else null;
            defer if (old_owned) |normalized| self.allocator.free(normalized);
            const new_owned = if (self.options.filesystem == .host_dir) try host.MemoryFilesystem.normalizePathAlloc(self.allocator, new_path, host.MemoryFilesystem.default_max_path_len) else null;
            defer if (new_owned) |normalized| self.allocator.free(normalized);
            return root.rename(old_owned orelse old_path, root, new_owned orelse new_path, io);
        },
    }
}

pub fn fsCopyFile(self: *State, source: []const u8, destination: []const u8, overwrite: bool) anyerror!void {
    self.file_generation +%= 1;
    switch (self.options.filesystem) {
        .disabled, .memory => return error.FilesystemReadOnly,
        .memory_rw => |filesystem| return filesystem.copyFile(source, destination, overwrite),
        .custom => |filesystem| {
            if (filesystem.copy_file) |copy| return copy(filesystem.context, source, destination, overwrite);
            const bytes = try filesystem.read_file_alloc(filesystem.context, self.allocator, source);
            defer self.allocator.free(bytes);
            const write = filesystem.write_file orelse return error.OperationUnsupported;
            return write(filesystem.context, destination, bytes);
        },
        .host_cwd, .host_dir => {
            if (comptime builtin.os.tag == .freestanding) return error.OperationUnsupported;
            const root: Dir = switch (self.options.filesystem) {
                .host_cwd => Dir.cwd(),
                .host_dir => |value| blk: {
                    if (value.read_only) return error.FilesystemReadOnly;
                    break :blk value.dir;
                },
                else => unreachable,
            };
            const io = self.options.io orelse return error.IoUnavailable;
            const source_owned = if (self.options.filesystem == .host_dir) try host.MemoryFilesystem.normalizePathAlloc(self.allocator, source, host.MemoryFilesystem.default_max_path_len) else null;
            defer if (source_owned) |normalized| self.allocator.free(normalized);
            const destination_owned = if (self.options.filesystem == .host_dir) try host.MemoryFilesystem.normalizePathAlloc(self.allocator, destination, host.MemoryFilesystem.default_max_path_len) else null;
            defer if (destination_owned) |normalized| self.allocator.free(normalized);
            return root.copyFile(source_owned orelse source, root, destination_owned orelse destination, io, .{ .replace = overwrite });
        },
    }
}

pub fn requireIo(self: *State, unavailable_message: []const u8) RuntimeError!std.Io {
    return self.options.io orelse self.fail(unavailable_message);
}

/// Reads the host `stdin_reader`, or the `stdin` bytes from `stdin_pos`.
const StdinSource = struct {
    state: *State,
    fixed: std.Io.Reader,
    host: ?*std.Io.Reader,

    pub fn reader(self: *StdinSource) *std.Io.Reader {
        return self.host orelse &self.fixed;
    }

    /// Records the memory bytes consumed through `reader`.
    pub fn finish(self: *StdinSource) void {
        if (self.host == null) self.state.stdin_pos += self.fixed.seek;
    }
};

/// Callers read through `reader()` and then call `finish()`.
pub fn stdinSource(self: *State) StdinSource {
    if (self.options.stdin_reader) |reader| {
        flushStdoutForInput(self);
        return .{ .state = self, .fixed = .fixed(""), .host = reader };
    }
    const input = self.options.stdin;
    return .{ .state = self, .fixed = .fixed(input[@min(self.stdin_pos, input.len)..]), .host = null };
}

pub fn stdinIsStream(self: *const State) bool {
    return self.options.stdin_reader != null;
}

/// Like `appendValue`, but a nil error object becomes `<no error object>`.
pub fn appendErrorValue(allocator: std.mem.Allocator, out: *std.ArrayList(u8), value: Value) !void {
    if (value == .nil) return out.appendSlice(allocator, "<no error object>");
    return appendValue(allocator, out, value);
}

/// Formats without metamethods; file handles format like their `__tostring`.
pub fn appendValue(allocator: std.mem.Allocator, out: *std.ArrayList(u8), value: Value) !void {
    if (stdlib.io.fileOf(value)) |file| {
        if (file.closed) return out.appendSlice(allocator, "file (closed)");
        return appendFmt(allocator, out, "file (0x{x})", .{@intFromPtr(value.userdata)});
    }
    return value_mod.appendValue(allocator, out, value);
}

pub fn isFileValue(value: Value) bool {
    return stdlib.io.fileOf(value) != null;
}

pub fn isClosedFileValue(value: Value) bool {
    const file = stdlib.io.fileOf(value) orelse return false;
    return file.closed;
}
