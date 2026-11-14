const std = @import("std");
const builtin = @import("builtin");

const posix = std.posix;
const File = std.Io.File;
const EnvMap = std.process.Environ.Map;

const is_windows = builtin.os.tag == .windows;
const is_posix = switch (builtin.os.tag) {
    .linux, .macos, .freebsd, .netbsd, .openbsd, .dragonfly => true,
    else => false,
};

pub const has_raw_mode = is_posix or is_windows;

const console = struct {
    const Handle = std.os.windows.HANDLE;

    const enable_processed_input: u32 = 0x1;
    const enable_line_input: u32 = 0x2;
    const enable_echo_input: u32 = 0x4;
    const enable_virtual_terminal_input: u32 = 0x200;
    const enable_processed_output: u32 = 0x1;
    const enable_virtual_terminal_processing: u32 = 0x4;
    const utf8_code_page: u32 = 65001;
    const ctrl_c_event: u32 = 0;

    /// `CONSOLE_SCREEN_BUFFER_INFO`; `window` is left, top, right, bottom.
    const ScreenBufferInfo = extern struct {
        size: [2]i16,
        cursor: [2]i16,
        attributes: u16,
        window: [4]i16,
        maximum_window_size: [2]i16,
    };

    const CtrlHandler = *const fn (ctrl_type: u32) callconv(.winapi) c_int;

    extern "kernel32" fn GetConsoleMode(handle: Handle, mode: *u32) callconv(.winapi) c_int;
    extern "kernel32" fn SetConsoleMode(handle: Handle, mode: u32) callconv(.winapi) c_int;
    extern "kernel32" fn GetConsoleOutputCP() callconv(.winapi) u32;
    extern "kernel32" fn SetConsoleOutputCP(code_page: u32) callconv(.winapi) c_int;
    extern "kernel32" fn GetConsoleScreenBufferInfo(handle: Handle, info: *ScreenBufferInfo) callconv(.winapi) c_int;
    extern "kernel32" fn ReadConsoleW(handle: Handle, buffer: [*]u16, count: u32, read: *u32, control: ?*anyopaque) callconv(.winapi) c_int;
    extern "kernel32" fn SetConsoleCtrlHandler(handler: ?CtrlHandler, add: c_int) callconv(.winapi) c_int;
};

pub const Role = enum {
    prompt,
    keyword,
    builtin,
    string,
    number,
    comment,
    object,
    location,
    title,
    message,
    caret,
    hint,
    dim,
    mark,
};

/// Emits SGR sequences for a stream, or nothing when color is off.
pub const Paint = struct {
    enabled: bool = false,

    pub fn on(self: Paint, role: Role) []const u8 {
        if (!self.enabled) return "";
        return switch (role) {
            .prompt, .title => "\x1b[1;35m",
            .keyword => "\x1b[1;34m",
            .builtin, .object => "\x1b[36m",
            .string => "\x1b[32m",
            .number => "\x1b[33m",
            .comment, .dim => "\x1b[2m",
            .location, .message => "\x1b[35m",
            .caret => "\x1b[1;31m",
            .hint => "\x1b[1;36m",
            .mark => "\x1b[7m",
        };
    }

    pub fn off(self: Paint) []const u8 {
        return if (self.enabled) "\x1b[0m" else "";
    }
};

pub const ColorMode = enum {
    auto,
    always,
    never,

    pub fn parse(text: []const u8) ?ColorMode {
        return std.meta.stringToEnum(ColorMode, text);
    }
};

pub fn detectPaint(io: std.Io, file: File, mode: ColorMode, env: *const EnvMap) Paint {
    switch (mode) {
        .never => return .{},
        .always => {
            file.enableAnsiEscapeCodes(io) catch {};
            return .{ .enabled = true };
        },
        .auto => {},
    }
    if (envSet(env, "NO_COLOR")) return .{};
    const forced = envSet(env, "FORCE_COLOR") or envSet(env, "CLICOLOR_FORCE");
    if (!forced and isDumb(env)) return .{};
    file.enableAnsiEscapeCodes(io) catch return .{ .enabled = forced };
    return .{ .enabled = true };
}

pub fn isDumb(env: *const EnvMap) bool {
    const term = env.get("TERM") orelse return false;
    return std.mem.eql(u8, term, "dumb");
}

fn envSet(env: *const EnvMap, name: []const u8) bool {
    const value = env.get(name) orelse return false;
    return value.len != 0;
}

pub const Size = struct {
    cols: usize = 80,
    rows: usize = 24,
};

pub fn windowSize(io: std.Io) Size {
    if (is_windows) {
        var info: console.ScreenBufferInfo = undefined;
        if (console.GetConsoleScreenBufferInfo(File.stdout().handle, &info) == 0) return .{};
        const rows = @as(i32, info.window[3]) - info.window[1] + 1;
        if (info.size[0] <= 0 or rows <= 0) return .{};
        return .{ .cols = @intCast(info.size[0]), .rows = @intCast(rows) };
    }
    if (!is_posix) return .{};
    var winsize: posix.winsize = .{ .row = 0, .col = 0, .xpixel = 0, .ypixel = 0 };
    const result = io.operate(.{ .device_io_control = .{
        .file = File.stdout(),
        .code = posix.T.IOCGWINSZ,
        .arg = &winsize,
    } }) catch return .{};
    if (result.device_io_control < 0 or winsize.col == 0 or winsize.row == 0) return .{};
    return .{ .cols = winsize.col, .rows = winsize.row };
}

/// Bytes typed at the terminal, as UTF-8.
pub const Input = struct {
    context: *anyopaque,
    read: *const fn (context: *anyopaque) ReadError!u8,
    peeked: ?u8 = null,

    pub const ReadError = error{ EndOfStream, ReadFailed };

    pub fn fromReader(reader: *std.Io.Reader) Input {
        return .{ .context = reader, .read = readFromReader };
    }

    fn readFromReader(context: *anyopaque) ReadError!u8 {
        const reader: *std.Io.Reader = @ptrCast(@alignCast(context));
        return reader.takeByte();
    }

    pub fn takeByte(self: *Input) ReadError!u8 {
        if (self.peeked) |byte| {
            self.peeked = null;
            return byte;
        }
        return self.read(self.context);
    }

    pub fn peekByte(self: *Input) ReadError!u8 {
        if (self.peeked == null) self.peeked = try self.read(self.context);
        return self.peeked.?;
    }
};

/// Reads the Windows console as UTF-16 and yields UTF-8.
pub const ConsoleInput = struct {
    pending: [4]u8 = undefined,
    start: usize = 0,
    end: usize = 0,
    high_surrogate: ?u16 = null,

    pub fn input(self: *ConsoleInput) Input {
        return .{ .context = self, .read = readByte };
    }

    fn readByte(context: *anyopaque) Input.ReadError!u8 {
        if (!is_windows) return error.ReadFailed;
        const self: *ConsoleInput = @ptrCast(@alignCast(context));
        while (self.start == self.end) {
            var unit: [1]u16 = undefined;
            var count: u32 = 0;
            if (console.ReadConsoleW(File.stdin().handle, &unit, 1, &count, null) == 0) return error.ReadFailed;
            if (count == 0) return error.EndOfStream;
            self.push(unit[0]);
        }
        defer self.start += 1;
        return self.pending[self.start];
    }

    fn push(self: *ConsoleInput, unit: u16) void {
        var code_point: u21 = unit;
        if (unit >= 0xD800 and unit <= 0xDBFF) {
            self.high_surrogate = unit;
            return;
        }
        if (unit >= 0xDC00 and unit <= 0xDFFF) {
            const high = self.high_surrogate orelse return;
            code_point = 0x10000 + ((@as(u21, high) - 0xD800) << 10) + (unit - 0xDC00);
        }
        self.high_surrogate = null;
        self.start = 0;
        self.end = std.unicode.utf8Encode(code_point, &self.pending) catch 0;
    }
};

/// While held, the Windows console decodes output as UTF-8.
pub const Utf8Output = struct {
    previous_code_page: u32 = 0,

    pub fn begin() Utf8Output {
        if (!is_windows) return .{};
        const previous = console.GetConsoleOutputCP();
        _ = console.SetConsoleOutputCP(console.utf8_code_page);
        return .{ .previous_code_page = previous };
    }

    pub fn end(self: Utf8Output) void {
        if (is_windows and self.previous_code_page != 0) _ = console.SetConsoleOutputCP(self.previous_code_page);
    }
};

pub fn canEdit() bool {
    const mode = RawMode.enter() orelse return false;
    mode.leave();
    return true;
}

pub const RawMode = if (is_posix) PosixRawMode else if (is_windows) WindowsRawMode else NoRawMode;

const NoRawMode = struct {
    pub const can_suspend = false;

    pub fn enter() ?NoRawMode {
        return null;
    }

    pub fn leave(_: NoRawMode) void {}

    pub fn suspendProcess(_: NoRawMode) void {}
};

const WindowsRawMode = struct {
    input_mode: u32,
    output_mode: u32,

    pub const can_suspend = false;

    pub fn enter() ?WindowsRawMode {
        const input = File.stdin().handle;
        const output = File.stdout().handle;
        var saved: WindowsRawMode = .{ .input_mode = 0, .output_mode = 0 };
        if (console.GetConsoleMode(input, &saved.input_mode) == 0) return null;
        if (console.GetConsoleMode(output, &saved.output_mode) == 0) return null;
        const cooked = console.enable_line_input | console.enable_echo_input | console.enable_processed_input;
        if (console.SetConsoleMode(input, (saved.input_mode & ~cooked) | console.enable_virtual_terminal_input) == 0) return null;
        if (console.SetConsoleMode(output, saved.output_mode | console.enable_processed_output | console.enable_virtual_terminal_processing) == 0) {
            _ = console.SetConsoleMode(input, saved.input_mode);
            return null;
        }
        return saved;
    }

    pub fn leave(self: WindowsRawMode) void {
        _ = console.SetConsoleMode(File.stdin().handle, self.input_mode);
        _ = console.SetConsoleMode(File.stdout().handle, self.output_mode);
    }

    pub fn suspendProcess(_: WindowsRawMode) void {}
};

const PosixRawMode = struct {
    original: posix.termios,
    raw: posix.termios,

    pub const can_suspend = true;

    pub fn enter() ?PosixRawMode {
        const original = posix.tcgetattr(posix.STDIN_FILENO) catch return null;
        var raw = original;
        raw.iflag.BRKINT = false;
        raw.iflag.ICRNL = false;
        raw.iflag.INPCK = false;
        raw.iflag.ISTRIP = false;
        raw.iflag.IXON = false;
        raw.lflag.ECHO = false;
        raw.lflag.ICANON = false;
        raw.lflag.IEXTEN = false;
        raw.lflag.ISIG = false;
        raw.cc[@intFromEnum(posix.V.MIN)] = 1;
        raw.cc[@intFromEnum(posix.V.TIME)] = 0;
        posix.tcsetattr(posix.STDIN_FILENO, .NOW, raw) catch return null;
        return .{ .original = original, .raw = raw };
    }

    pub fn leave(self: PosixRawMode) void {
        posix.tcsetattr(posix.STDIN_FILENO, .NOW, self.original) catch {};
    }

    /// Returns in raw mode once the process continues.
    pub fn suspendProcess(self: PosixRawMode) void {
        self.leave();
        posix.raise(.TSTP) catch {};
        posix.tcsetattr(posix.STDIN_FILENO, .NOW, self.raw) catch {};
    }
};

var interrupt_target: std.atomic.Value(?*std.atomic.Value(bool)) = .init(null);

fn onInterrupt(_: posix.SIG) callconv(.c) void {
    if (interrupt_target.load(.acquire)) |flag| flag.store(true, .release);
}

fn onConsoleControl(ctrl_type: u32) callconv(.winapi) c_int {
    if (ctrl_type != console.ctrl_c_event) return 0;
    if (interrupt_target.load(.acquire)) |flag| flag.store(true, .release);
    return 1;
}

/// While installed, an interrupt from the terminal sets the flag.
pub const InterruptGuard = if (is_posix) struct {
    previous: posix.Sigaction,

    pub fn install(flag: *std.atomic.Value(bool)) @This() {
        interrupt_target.store(flag, .release);
        var previous: posix.Sigaction = undefined;
        const action: posix.Sigaction = .{
            .handler = .{ .handler = onInterrupt },
            .mask = posix.sigemptyset(),
            .flags = 0,
        };
        posix.sigaction(.INT, &action, &previous);
        return .{ .previous = previous };
    }

    pub fn remove(self: @This()) void {
        posix.sigaction(.INT, &self.previous, null);
        interrupt_target.store(null, .release);
    }
} else struct {
    pub fn install(flag: *std.atomic.Value(bool)) @This() {
        if (is_windows) {
            interrupt_target.store(flag, .release);
            _ = console.SetConsoleCtrlHandler(onConsoleControl, 1);
        }
        return .{};
    }

    pub fn remove(_: @This()) void {
        if (is_windows) {
            _ = console.SetConsoleCtrlHandler(onConsoleControl, 0);
            interrupt_target.store(null, .release);
        }
    }
};

/// Terminal columns `code_point` occupies.
pub fn charWidth(code_point: u21) usize {
    if (code_point == '\t') return 4;
    if (code_point < 0x300) return 1;
    const zero_width = [_][2]u21{
        .{ 0x0300, 0x036F }, .{ 0x0483, 0x0489 }, .{ 0x0591, 0x05BD },   .{ 0x0610, 0x061A },
        .{ 0x064B, 0x065F }, .{ 0x1AB0, 0x1AFF }, .{ 0x1DC0, 0x1DFF },   .{ 0x200B, 0x200F },
        .{ 0x202A, 0x202E }, .{ 0x2060, 0x2064 }, .{ 0x20D0, 0x20FF },   .{ 0xFE00, 0xFE0F },
        .{ 0xFE20, 0xFE2F }, .{ 0xFEFF, 0xFEFF }, .{ 0x1F3FB, 0x1F3FF }, .{ 0xE0100, 0xE01EF },
    };
    for (zero_width) |range| if (code_point >= range[0] and code_point <= range[1]) return 0;
    const wide = [_][2]u21{
        .{ 0x1100, 0x115F },   .{ 0x231A, 0x231B },   .{ 0x23E9, 0x23EC },   .{ 0x2E80, 0x303E },
        .{ 0x3041, 0x33FF },   .{ 0x3400, 0x4DBF },   .{ 0x4E00, 0x9FFF },   .{ 0xA000, 0xA4CF },
        .{ 0xAC00, 0xD7A3 },   .{ 0xF900, 0xFAFF },   .{ 0xFE30, 0xFE4F },   .{ 0xFF00, 0xFF60 },
        .{ 0xFFE0, 0xFFE6 },   .{ 0x1F300, 0x1F64F }, .{ 0x1F680, 0x1F6FF }, .{ 0x1F900, 0x1FAFF },
        .{ 0x20000, 0x3FFFD },
    };
    for (wide) |range| if (code_point >= range[0] and code_point <= range[1]) return 2;
    return 1;
}

/// Terminal columns of valid UTF-8 `text` without line breaks.
pub fn textWidth(text: []const u8) usize {
    var width: usize = 0;
    var index: usize = 0;
    while (index < text.len) {
        const len = sequenceLength(text[index]);
        if (index + len > text.len) break;
        width += charWidth(std.unicode.utf8Decode(text[index..][0..len]) catch 0xFFFD);
        index += len;
    }
    return width;
}

pub fn sequenceLength(first_byte: u8) usize {
    return std.unicode.utf8ByteSequenceLength(first_byte) catch 1;
}

test "wide and combining characters have terminal widths" {
    try std.testing.expectEqual(@as(usize, 5), textWidth("hello"));
    try std.testing.expectEqual(@as(usize, 4), textWidth("日本"));
    try std.testing.expectEqual(@as(usize, 1), textWidth("e\u{301}"));
    try std.testing.expectEqual(@as(usize, 4), textWidth("\t"));
}

test "console input converts UTF-16 units to UTF-8" {
    var console_input: ConsoleInput = .{};
    var bytes: [16]u8 = undefined;
    var len: usize = 0;
    for ([_]u16{ 'a', 0xE9, 0x65E5, 0xD83D, 0xDE00, 0xDC00, 'z' }) |unit| {
        console_input.push(unit);
        while (console_input.start < console_input.end) : (console_input.start += 1) {
            bytes[len] = console_input.pending[console_input.start];
            len += 1;
        }
    }
    try std.testing.expectEqualStrings("a\u{e9}\u{65e5}\u{1f600}z", bytes[0..len]);
}

test "input peeks one byte ahead" {
    var reader: std.Io.Reader = .fixed("ab");
    var input: Input = .fromReader(&reader);
    try std.testing.expectEqual(@as(u8, 'a'), try input.peekByte());
    try std.testing.expectEqual(@as(u8, 'a'), try input.takeByte());
    try std.testing.expectEqual(@as(u8, 'b'), try input.takeByte());
    try std.testing.expectError(error.EndOfStream, input.takeByte());
}

test "color modes parse" {
    try std.testing.expectEqual(ColorMode.always, ColorMode.parse("always").?);
    try std.testing.expect(ColorMode.parse("sometimes") == null);
}
