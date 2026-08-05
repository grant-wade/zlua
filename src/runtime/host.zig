const std = @import("std");

pub const MemoryFile = struct {
    path: []const u8,
    contents: []const u8,
};

pub const FileKind = enum {
    block_device,
    character_device,
    directory,
    named_pipe,
    sym_link,
    file,
    unix_domain_socket,
    whiteout,
    door,
    event_port,
    unknown,

    pub fn fromStd(kind: std.Io.File.Kind) FileKind {
        return @enumFromInt(@intFromEnum(kind));
    }
};

pub const FileStat = struct {
    inode: u64 = 0,
    nlink: u64 = 1,
    size: u64 = 0,
    permissions: u64 = 0,
    kind: FileKind,
    atime: ?std.Io.Timestamp = null,
    mtime: std.Io.Timestamp = .{ .nanoseconds = 0 },
    ctime: std.Io.Timestamp = .{ .nanoseconds = 0 },
    block_size: u32 = 1,

    pub fn fromStd(stat: std.Io.File.Stat) FileStat {
        return .{
            .inode = @intCast(stat.inode),
            .nlink = @intCast(stat.nlink),
            .size = stat.size,
            .permissions = @intCast(@intFromEnum(stat.permissions)),
            .kind = .fromStd(stat.kind),
            .atime = stat.atime,
            .mtime = stat.mtime,
            .ctime = stat.ctime,
            .block_size = stat.block_size,
        };
    }
};

pub const DirectoryEntry = struct {
    name: []const u8,
    kind: FileKind,
    inode: u64 = 0,
};

pub fn deinitDirectoryEntries(allocator: std.mem.Allocator, entries: []DirectoryEntry) void {
    for (entries) |entry| allocator.free(entry.name);
    allocator.free(entries);
}

pub const MemoryFilesystem = struct {
    pub const default_max_path_len: usize = 4096;

    pub const Options = struct {
        max_path_len: usize = default_max_path_len,
        max_bytes: ?usize = null,
    };

    allocator: std.mem.Allocator,
    files: std.ArrayList(MemoryFile) = .empty,
    directories: std.ArrayList([]const u8) = .empty,
    options: Options = .{},
    bytes_used: usize = 0,

    pub fn init(allocator: std.mem.Allocator) MemoryFilesystem {
        return initWithOptions(allocator, .{});
    }

    pub fn initWithOptions(allocator: std.mem.Allocator, options: Options) MemoryFilesystem {
        return .{ .allocator = allocator, .options = options };
    }

    pub fn initWithFiles(allocator: std.mem.Allocator, files: []const MemoryFile) !MemoryFilesystem {
        return initWithFilesAndOptions(allocator, files, .{});
    }

    pub fn initWithFilesAndOptions(allocator: std.mem.Allocator, files: []const MemoryFile, options: Options) !MemoryFilesystem {
        var filesystem = initWithOptions(allocator, options);
        errdefer filesystem.deinit();
        for (files) |file| try filesystem.writeFile(file.path, file.contents);
        return filesystem;
    }

    pub fn deinit(self: *MemoryFilesystem) void {
        for (self.files.items) |file| {
            self.allocator.free(file.path);
            self.allocator.free(file.contents);
        }
        for (self.directories.items) |path| self.allocator.free(path);
        self.files.deinit(self.allocator);
        self.directories.deinit(self.allocator);
        self.* = undefined;
    }

    pub fn readFileAlloc(self: *const MemoryFilesystem, allocator: std.mem.Allocator, path: []const u8) ![]const u8 {
        const normalized = try normalizePathAlloc(self.allocator, path, self.options.max_path_len);
        defer self.allocator.free(normalized);
        const index = self.findNormalized(normalized) orelse return error.FileNotFound;
        return allocator.dupe(u8, self.files.items[index].contents);
    }

    pub fn writeFile(self: *MemoryFilesystem, path: []const u8, contents: []const u8) !void {
        const normalized = try normalizePathAlloc(self.allocator, path, self.options.max_path_len);
        errdefer self.allocator.free(normalized);
        if (self.findDirNormalized(normalized) != null) return error.IsDir;

        if (self.findNormalized(normalized)) |index| {
            const contents_copy = try self.allocator.dupe(u8, contents);
            errdefer self.allocator.free(contents_copy);
            const old_len = self.files.items[index].contents.len;
            try self.ensureQuota(old_len, contents_copy.len);
            self.allocator.free(self.files.items[index].contents);
            self.bytes_used = self.bytes_used - old_len + contents_copy.len;
            self.files.items[index].contents = contents_copy;
            self.allocator.free(normalized);
            return;
        }

        try self.ensureParentDirectories(normalized);
        const contents_copy = try self.allocator.dupe(u8, contents);
        errdefer self.allocator.free(contents_copy);
        try self.ensureQuota(0, contents_copy.len);
        try self.files.append(self.allocator, .{ .path = normalized, .contents = contents_copy });
        self.bytes_used += contents_copy.len;
    }

    pub fn makeDir(self: *MemoryFilesystem, path: []const u8, parents: bool) !void {
        const normalized = try normalizePathAlloc(self.allocator, path, self.options.max_path_len);
        defer self.allocator.free(normalized);
        if (self.findNormalized(normalized) != null) return error.PathAlreadyExists;
        if (self.findDirNormalized(normalized) != null) return error.PathAlreadyExists;
        const parent = std.fs.path.dirname(normalized) orelse "";
        if (parent.len != 0 and self.findDirNormalized(parent) == null) {
            if (!parents) return error.FileNotFound;
            try self.ensureParentDirectories(normalized);
        }
        try self.addDirectory(normalized);
    }

    pub fn statPath(self: *const MemoryFilesystem, path: []const u8) !FileStat {
        const normalized = try normalizeRootPathAlloc(self.allocator, path, self.options.max_path_len);
        defer self.allocator.free(normalized);
        if (normalized.len == 0 or self.findDirNormalized(normalized) != null) {
            return .{ .kind = .directory, .inode = memoryInode(normalized), .permissions = 0o777 };
        }
        const index = self.findNormalized(normalized) orelse return error.FileNotFound;
        return .{
            .kind = .file,
            .inode = memoryInode(normalized),
            .size = self.files.items[index].contents.len,
            .permissions = 0o666,
        };
    }

    pub fn readDirAlloc(self: *const MemoryFilesystem, allocator: std.mem.Allocator, path: []const u8) ![]DirectoryEntry {
        const normalized = try normalizeRootPathAlloc(self.allocator, path, self.options.max_path_len);
        defer self.allocator.free(normalized);
        if (normalized.len != 0 and self.findDirNormalized(normalized) == null) {
            if (self.findNormalized(normalized) != null) return error.NotDir;
            return error.FileNotFound;
        }

        var entries: std.ArrayList(DirectoryEntry) = .empty;
        errdefer {
            for (entries.items) |entry| allocator.free(entry.name);
            entries.deinit(allocator);
        }
        for (self.directories.items) |dir_path| {
            if (directChild(normalized, dir_path)) |name| {
                try appendUniqueEntry(allocator, &entries, name, .directory, memoryInode(dir_path));
            }
        }
        for (self.files.items) |file| {
            if (directChild(normalized, file.path)) |name| {
                try appendUniqueEntry(allocator, &entries, name, .file, memoryInode(file.path));
            }
        }
        return entries.toOwnedSlice(allocator);
    }

    pub fn removeFile(self: *MemoryFilesystem, path: []const u8) !void {
        const normalized = try normalizePathAlloc(self.allocator, path, self.options.max_path_len);
        defer self.allocator.free(normalized);
        const index = self.findNormalized(normalized) orelse return error.FileNotFound;
        self.removeAt(index);
    }

    pub fn removePath(self: *MemoryFilesystem, path: []const u8, recursive: bool) !void {
        const normalized = try normalizePathAlloc(self.allocator, path, self.options.max_path_len);
        defer self.allocator.free(normalized);
        if (self.findNormalized(normalized)) |index| {
            self.removeAt(index);
            return;
        }
        const dir_index = self.findDirNormalized(normalized) orelse return error.FileNotFound;
        if (!recursive and self.hasDescendants(normalized)) return error.DirNotEmpty;
        self.removeDescendants(normalized);
        const owned = self.directories.swapRemove(dir_index);
        self.allocator.free(owned);
    }

    pub fn renameFile(self: *MemoryFilesystem, old_path: []const u8, new_path: []const u8) !void {
        const old_normalized = try normalizePathAlloc(self.allocator, old_path, self.options.max_path_len);
        defer self.allocator.free(old_normalized);
        const new_normalized = try normalizePathAlloc(self.allocator, new_path, self.options.max_path_len);
        errdefer self.allocator.free(new_normalized);

        _ = self.findNormalized(old_normalized) orelse return error.FileNotFound;
        if (std.mem.eql(u8, old_normalized, new_normalized)) {
            self.allocator.free(new_normalized);
            return;
        }
        if (self.findDirNormalized(new_normalized) != null) return error.IsDir;
        if (self.findNormalized(new_normalized)) |index| self.removeAt(index);
        try self.ensureParentDirectories(new_normalized);

        const index = self.findNormalized(old_normalized) orelse return error.FileNotFound;
        self.allocator.free(self.files.items[index].path);
        self.files.items[index].path = new_normalized;
    }

    pub fn renamePath(self: *MemoryFilesystem, old_path: []const u8, new_path: []const u8) !void {
        const old_normalized = try normalizePathAlloc(self.allocator, old_path, self.options.max_path_len);
        defer self.allocator.free(old_normalized);
        if (self.findNormalized(old_normalized) != null) return self.renameFile(old_path, new_path);
        if (self.findDirNormalized(old_normalized) == null) return error.FileNotFound;

        const new_normalized = try normalizePathAlloc(self.allocator, new_path, self.options.max_path_len);
        defer self.allocator.free(new_normalized);
        if (std.mem.startsWith(u8, new_normalized, old_normalized) and new_normalized.len > old_normalized.len and new_normalized[old_normalized.len] == '/') return error.InvalidPath;
        if (self.findNormalized(new_normalized) != null or self.findDirNormalized(new_normalized) != null) return error.PathAlreadyExists;
        try self.ensureParentDirectories(new_normalized);

        var changed_dirs: std.ArrayList(struct { index: usize, path: []const u8 }) = .empty;
        defer changed_dirs.deinit(self.allocator);
        var changed_files: std.ArrayList(struct { index: usize, path: []const u8 }) = .empty;
        defer changed_files.deinit(self.allocator);
        errdefer {
            for (changed_dirs.items) |item| self.allocator.free(item.path);
            for (changed_files.items) |item| self.allocator.free(item.path);
        }
        for (self.directories.items, 0..) |dir_path, index| {
            if (sameOrDescendant(old_normalized, dir_path)) {
                try changed_dirs.append(self.allocator, .{ .index = index, .path = try replacePrefix(self.allocator, old_normalized, new_normalized, dir_path) });
            }
        }
        for (self.files.items, 0..) |file, index| {
            if (sameOrDescendant(old_normalized, file.path)) {
                try changed_files.append(self.allocator, .{ .index = index, .path = try replacePrefix(self.allocator, old_normalized, new_normalized, file.path) });
            }
        }
        for (changed_dirs.items) |item| {
            self.allocator.free(self.directories.items[item.index]);
            self.directories.items[item.index] = item.path;
        }
        for (changed_files.items) |item| {
            self.allocator.free(self.files.items[item.index].path);
            self.files.items[item.index].path = item.path;
        }
    }

    pub fn copyFile(self: *MemoryFilesystem, source: []const u8, destination: []const u8, overwrite: bool) !void {
        const source_normalized = try normalizePathAlloc(self.allocator, source, self.options.max_path_len);
        defer self.allocator.free(source_normalized);
        const index = self.findNormalized(source_normalized) orelse return error.FileNotFound;
        const destination_normalized = try normalizePathAlloc(self.allocator, destination, self.options.max_path_len);
        defer self.allocator.free(destination_normalized);
        if (!overwrite and self.findNormalized(destination_normalized) != null) return error.PathAlreadyExists;
        try self.writeFile(destination_normalized, self.files.items[index].contents);
    }

    fn removeAt(self: *MemoryFilesystem, index: usize) void {
        const file = self.files.swapRemove(index);
        self.bytes_used -= @min(self.bytes_used, file.contents.len);
        self.allocator.free(file.path);
        self.allocator.free(file.contents);
    }

    fn findNormalized(self: *const MemoryFilesystem, path: []const u8) ?usize {
        for (self.files.items, 0..) |file, index| {
            if (std.mem.eql(u8, file.path, path)) return index;
        }
        return null;
    }

    fn findDirNormalized(self: *const MemoryFilesystem, path: []const u8) ?usize {
        for (self.directories.items, 0..) |dir_path, index| {
            if (std.mem.eql(u8, dir_path, path)) return index;
        }
        return null;
    }

    fn ensureQuota(self: *const MemoryFilesystem, old_len: usize, new_len: usize) !void {
        const max_bytes = self.options.max_bytes orelse return;
        if (self.bytes_used - old_len + new_len > max_bytes) return error.QuotaExceeded;
    }

    fn addDirectory(self: *MemoryFilesystem, path: []const u8) !void {
        if (path.len == 0 or self.findDirNormalized(path) != null) return;
        if (self.findNormalized(path) != null) return error.NotDir;
        try self.directories.append(self.allocator, try self.allocator.dupe(u8, path));
    }

    fn ensureParentDirectories(self: *MemoryFilesystem, path: []const u8) !void {
        var index: usize = 0;
        while (std.mem.indexOfScalarPos(u8, path, index, '/')) |slash| {
            try self.addDirectory(path[0..slash]);
            index = slash + 1;
        }
    }

    fn hasDescendants(self: *const MemoryFilesystem, path: []const u8) bool {
        for (self.directories.items) |candidate| if (!std.mem.eql(u8, candidate, path) and sameOrDescendant(path, candidate)) return true;
        for (self.files.items) |file| if (sameOrDescendant(path, file.path)) return true;
        return false;
    }

    fn removeDescendants(self: *MemoryFilesystem, path: []const u8) void {
        var file_index: usize = 0;
        while (file_index < self.files.items.len) {
            if (sameOrDescendant(path, self.files.items[file_index].path)) self.removeAt(file_index) else file_index += 1;
        }
        var dir_index: usize = 0;
        while (dir_index < self.directories.items.len) {
            const candidate = self.directories.items[dir_index];
            if (!std.mem.eql(u8, candidate, path) and sameOrDescendant(path, candidate)) {
                const owned = self.directories.swapRemove(dir_index);
                self.allocator.free(owned);
            } else dir_index += 1;
        }
    }

    pub fn normalizePathAlloc(allocator: std.mem.Allocator, path: []const u8, max_path_len: usize) ![]u8 {
        const normalized = try normalizeRootPathAlloc(allocator, path, max_path_len);
        if (normalized.len == 0) {
            allocator.free(normalized);
            return error.InvalidPath;
        }
        return normalized;
    }

    pub fn normalizeRootPathAlloc(allocator: std.mem.Allocator, path: []const u8, max_path_len: usize) ![]u8 {
        if (path.len != 0 and path[0] == '/') return error.InvalidPath;

        var normalized = std.ArrayList(u8).empty;
        errdefer normalized.deinit(allocator);
        var parts = std.mem.splitScalar(u8, path, '/');
        while (parts.next()) |part| {
            if (part.len == 0 or std.mem.eql(u8, part, ".")) continue;
            if (std.mem.eql(u8, part, "..")) return error.InvalidPath;
            if (std.mem.indexOfScalar(u8, part, '\\') != null) return error.InvalidPath;
            if (std.mem.indexOfScalar(u8, part, 0) != null) return error.InvalidPath;
            if (normalized.items.len != 0) try normalized.append(allocator, '/');
            try normalized.appendSlice(allocator, part);
            if (normalized.items.len > max_path_len) return error.PathTooLong;
        }
        return normalized.toOwnedSlice(allocator);
    }
};

fn directChild(parent: []const u8, candidate: []const u8) ?[]const u8 {
    const rest = if (parent.len == 0)
        candidate
    else blk: {
        if (!sameOrDescendant(parent, candidate) or candidate.len == parent.len) return null;
        break :blk candidate[parent.len + 1 ..];
    };
    if (rest.len == 0 or std.mem.indexOfScalar(u8, rest, '/') != null) return null;
    return rest;
}

fn sameOrDescendant(parent: []const u8, candidate: []const u8) bool {
    return std.mem.eql(u8, parent, candidate) or (candidate.len > parent.len and std.mem.startsWith(u8, candidate, parent) and candidate[parent.len] == '/');
}

fn replacePrefix(allocator: std.mem.Allocator, old: []const u8, new: []const u8, path: []const u8) ![]const u8 {
    return std.mem.concat(allocator, u8, &.{ new, path[old.len..] });
}

fn memoryInode(path: []const u8) u64 {
    return std.hash.Wyhash.hash(0, path);
}

fn appendUniqueEntry(allocator: std.mem.Allocator, entries: *std.ArrayList(DirectoryEntry), name: []const u8, kind: FileKind, inode: u64) !void {
    for (entries.items) |entry| if (std.mem.eql(u8, entry.name, name)) return;
    try entries.append(allocator, .{ .name = try allocator.dupe(u8, name), .kind = kind, .inode = inode });
}

pub const FilesystemCapability = union(enum) {
    disabled,
    memory: []const MemoryFile,
    memory_rw: *MemoryFilesystem,
    host_cwd,
    host_dir: HostDirectory,
    custom: CustomFilesystem,
};

pub const HostDirectory = struct {
    dir: std.Io.Dir,
    read_only: bool = false,
};

pub const CustomFilesystem = struct {
    context: ?*anyopaque = null,
    read_file_alloc: *const fn (context: ?*anyopaque, allocator: std.mem.Allocator, path: []const u8) anyerror![]const u8,
    write_file: ?*const fn (context: ?*anyopaque, path: []const u8, contents: []const u8) anyerror!void = null,
    remove_file: ?*const fn (context: ?*anyopaque, path: []const u8) anyerror!void = null,
    rename_file: ?*const fn (context: ?*anyopaque, old_path: []const u8, new_path: []const u8) anyerror!void = null,
    stat: ?*const fn (context: ?*anyopaque, path: []const u8, follow_symlinks: bool) anyerror!FileStat = null,
    read_dir_alloc: ?*const fn (context: ?*anyopaque, allocator: std.mem.Allocator, path: []const u8) anyerror![]DirectoryEntry = null,
    make_dir: ?*const fn (context: ?*anyopaque, path: []const u8, parents: bool) anyerror!void = null,
    remove_path: ?*const fn (context: ?*anyopaque, path: []const u8, recursive: bool) anyerror!void = null,
    copy_file: ?*const fn (context: ?*anyopaque, source: []const u8, destination: []const u8, overwrite: bool) anyerror!void = null,
};

pub const EnvironmentCapability = union(enum) {
    disabled,
    map: *const std.process.Environ.Map,
    custom: CustomEnvironment,
};

pub const CustomEnvironment = struct {
    context: ?*anyopaque = null,
    get: *const fn (context: ?*anyopaque, name: []const u8) ?[]const u8,
};

pub const ClockCapability = union(enum) {
    disabled,
    fixed: i64,
    system,
    custom: CustomClock,
};

pub const CustomClock = struct {
    context: ?*anyopaque = null,
    now: *const fn (context: ?*anyopaque) anyerror!i64,
};

pub const ProcessCapability = union(enum) {
    disabled,
    enabled,
    custom: CustomProcess,
};

pub const CustomProcess = struct {
    context: ?*anyopaque = null,
    execute: *const fn (context: ?*anyopaque, command: []const u8) anyerror!ProcessResult,
};

pub const ProcessResult = struct {
    status: ProcessStatus,
    code: i64,
};

pub const ProcessStatus = enum {
    exit,
    signal,
};

test "memory filesystem normalizes relative paths" {
    var filesystem = MemoryFilesystem.init(std.testing.allocator);
    defer filesystem.deinit();
    try filesystem.writeFile("./plugins//main.lua", "return 42");
    const source = try filesystem.readFileAlloc(std.testing.allocator, "plugins/main.lua");
    defer std.testing.allocator.free(source);
    try std.testing.expectEqualStrings("return 42", source);
}

test "memory filesystem represents directories and lists entries" {
    var filesystem = MemoryFilesystem.init(std.testing.allocator);
    defer filesystem.deinit();
    try filesystem.writeFile("src/lib/a.lua", "a");
    try filesystem.writeFile("src/main.lua", "main");
    const entries = try filesystem.readDirAlloc(std.testing.allocator, "src");
    defer deinitDirectoryEntries(std.testing.allocator, entries);
    try std.testing.expectEqual(@as(usize, 2), entries.len);
    try std.testing.expectEqual(FileKind.directory, (try filesystem.statPath("src/lib")).kind);
}

test "memory filesystem rejects sandbox escape paths" {
    var filesystem = MemoryFilesystem.init(std.testing.allocator);
    defer filesystem.deinit();
    try std.testing.expectError(error.InvalidPath, filesystem.writeFile("/tmp/plugin.lua", ""));
    try std.testing.expectError(error.InvalidPath, filesystem.writeFile("plugins/../secret.lua", ""));
    try std.testing.expectError(error.InvalidPath, filesystem.writeFile("plugins\\secret.lua", ""));
}

test "memory filesystem enforces path length and byte quota" {
    var filesystem = MemoryFilesystem.initWithOptions(std.testing.allocator, .{ .max_path_len = 8, .max_bytes = 5 });
    defer filesystem.deinit();
    try std.testing.expectError(error.PathTooLong, filesystem.writeFile("too-long-name.lua", "x"));
    try filesystem.writeFile("a.lua", "123");
    try std.testing.expectError(error.QuotaExceeded, filesystem.writeFile("b.lua", "456"));
    try filesystem.writeFile("a.lua", "12345");
    try std.testing.expectError(error.QuotaExceeded, filesystem.writeFile("a.lua", "123456"));
}

test "memory filesystem enforces byte quota while seeding files" {
    const files = [_]MemoryFile{ .{ .path = "a.lua", .contents = "123" }, .{ .path = "b.lua", .contents = "456" } };
    try std.testing.expectError(error.QuotaExceeded, MemoryFilesystem.initWithFilesAndOptions(std.testing.allocator, &files, .{ .max_bytes = 5 }));
}

test "memory filesystem rename overwrites normalized target" {
    var filesystem = MemoryFilesystem.init(std.testing.allocator);
    defer filesystem.deinit();
    try filesystem.writeFile("old.lua", "old");
    try filesystem.writeFile("dir/target.lua", "target");
    try filesystem.renameFile("./old.lua", "dir//target.lua");
    const source = try filesystem.readFileAlloc(std.testing.allocator, "dir/target.lua");
    defer std.testing.allocator.free(source);
    try std.testing.expectEqualStrings("old", source);
    try std.testing.expectError(error.FileNotFound, filesystem.readFileAlloc(std.testing.allocator, "old.lua"));
}
