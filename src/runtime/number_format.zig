//! Exact C `printf`-compatible float formatting and Lua's float-to-string conversion.
//! Where libcs disagree (`%a` rounding, subnormals, NaN sign), the target's libc is followed.

const std = @import("std");
const builtin = @import("builtin");

const darwin_printf = builtin.os.tag.isDarwin();

/// A parsed conversion such as `%-+012.3e`.
pub const Spec = struct {
    /// One of `e E f g G a A`.
    conversion: u8,
    left_align: bool = false,
    force_sign: bool = false,
    space_sign: bool = false,
    alternate: bool = false,
    zero_pad: bool = false,
    width: usize = 0,
    precision: ?usize = null,
};

/// Fits width and precision up to Lua's limit of 99; `%.99f` of the largest double needs 410.
pub const max_formatted_len = 512;

/// Fits every `tostring` rendering of a float (`%.17g` plus `.0`).
pub const max_lua_float_len = 32;

/// Formats `value` like C `snprintf`, clamping width and precision to 99.
pub fn formatFloat(buffer: *[max_formatted_len]u8, spec: Spec, value: f64) []const u8 {
    var clamped = spec;
    clamped.width = @min(spec.width, 99);
    if (spec.precision) |precision| clamped.precision = @min(precision, 99);

    const conversion = std.ascii.toLower(clamped.conversion);
    const upper = std.ascii.isUpper(clamped.conversion);
    var body_buffer: [max_formatted_len]u8 = undefined;
    var body = Out{ .buf = &body_buffer };
    const negative = std.math.signbit(value);
    var numeric = true;
    var allow_sign = true;
    if (std.math.isNan(value)) {
        body.pushSlice("nan");
        numeric = false;
        if (darwin_printf or builtin.os.tag == .windows) allow_sign = false;
    } else if (std.math.isInf(value)) {
        body.pushSlice("inf");
        numeric = false;
    } else {
        const magnitude = @abs(value);
        switch (conversion) {
            'a' => appendHex(&body, magnitude, clamped.precision, clamped.alternate),
            'e', 'f', 'g' => {
                var decimal: Decimal = .{};
                if (magnitude != 0) exactDecimal(magnitude, &decimal);
                switch (conversion) {
                    'e' => {
                        const precision = clamped.precision orelse 6;
                        roundDecimal(&decimal, @as(isize, @intCast(precision)) + 1);
                        appendExponentStyle(&body, &decimal, precision, clamped.alternate);
                    },
                    'f' => {
                        const precision = clamped.precision orelse 6;
                        roundDecimal(&decimal, @as(isize, decimal.exponent) + 1 + @as(isize, @intCast(precision)));
                        appendFixedStyle(&body, &decimal, precision, clamped.alternate);
                    },
                    else => appendGeneralStyle(&body, &decimal, clamped.precision, clamped.alternate),
                }
            },
            else => unreachable,
        }
    }
    if (upper) {
        for (body.slice()) |*byte| byte.* = std.ascii.toUpper(byte.*);
    }

    const sign: ?u8 = if (!allow_sign)
        null
    else if (negative)
        '-'
    else if (clamped.force_sign)
        '+'
    else if (clamped.space_sign)
        ' '
    else
        null;

    var out = Out{ .buf = buffer };
    const sign_len: usize = if (sign != null) 1 else 0;
    const total = sign_len + body.len;
    const padding = if (clamped.width > total) clamped.width - total else 0;
    const text = body.slice();
    if (clamped.left_align) {
        if (sign) |byte| out.push(byte);
        out.pushSlice(text);
        out.pushN(' ', padding);
    } else if (clamped.zero_pad and numeric) {
        if (sign) |byte| out.push(byte);
        const prefix_len: usize = if (conversion == 'a') 2 else 0;
        out.pushSlice(text[0..prefix_len]);
        out.pushN('0', padding);
        out.pushSlice(text[prefix_len..]);
    } else {
        out.pushN(' ', padding);
        if (sign) |byte| out.push(byte);
        out.pushSlice(text);
    }
    return out.slice();
}

/// Converts a float like Lua's `tostring`: `%.15g`, or `%.17g` when needed to round-trip,
/// plus `.0` when it looks like an integer.
pub fn formatLuaFloat(buffer: *[max_lua_float_len]u8, value: f64) []const u8 {
    var scratch: [max_formatted_len]u8 = undefined;
    const text = if (std.math.isFinite(value)) luaFiniteFloat(&scratch, value) else formatFloat(&scratch, .{ .conversion = 'g', .precision = 15 }, value);
    @memcpy(buffer[0..text.len], text);
    var len = text.len;
    if (looksLikeInteger(text)) {
        buffer[len..][0..2].* = ".0".*;
        len += 2;
    }
    return buffer[0..len];
}

fn luaFiniteFloat(scratch: *[max_formatted_len]u8, value: f64) []const u8 {
    var decimal: Decimal = .{};
    var precision: usize = 15;
    const magnitude = @abs(value);
    if (magnitude != 0 and magnitude < std.math.floatMin(f64)) {
        const text = formatFloat(scratch, .{ .conversion = 'g', .precision = 15 }, value);
        if ((std.fmt.parseFloat(f64, text) catch value) == value) return text;
        return formatFloat(scratch, .{ .conversion = 'g', .precision = 17 }, value);
    }
    if (magnitude != 0) {
        shortestDecimal(magnitude, &decimal);
        if (decimal.len == 16) {
            decimal = .{};
            exactDecimal(magnitude, &decimal);
            precision = 17;
        } else if (decimal.len == 17) {
            precision = 17;
        }
    }
    var out = Out{ .buf = scratch };
    if (std.math.signbit(value)) out.push('-');
    appendGeneralStyle(&out, &decimal, precision, false);
    return out.slice();
}

fn shortestDecimal(value: f64, out: *Decimal) void {
    var buffer: [64]u8 = undefined;
    const text = std.fmt.bufPrint(&buffer, "{e}", .{value}) catch unreachable;
    const marker = std.mem.indexOfScalar(u8, text, 'e') orelse text.len;
    var len: usize = 0;
    for (text[0..marker]) |byte| {
        if (byte == '.') continue;
        out.digits[len] = byte;
        len += 1;
    }
    const exponent = if (marker < text.len) std.fmt.parseInt(i32, text[marker + 1 ..], 10) catch unreachable else 0;
    while (len > 0 and out.digits[len - 1] == '0') len -= 1;
    out.len = len;
    out.exponent = exponent;
}

fn looksLikeInteger(text: []const u8) bool {
    for (text) |byte| switch (byte) {
        '-', '0'...'9' => {},
        else => return false,
    };
    return true;
}

const Out = struct {
    buf: []u8,
    len: usize = 0,

    fn push(self: *Out, byte: u8) void {
        self.buf[self.len] = byte;
        self.len += 1;
    }

    fn pushSlice(self: *Out, bytes: []const u8) void {
        @memcpy(self.buf[self.len..][0..bytes.len], bytes);
        self.len += bytes.len;
    }

    fn pushN(self: *Out, byte: u8, count: usize) void {
        @memset(self.buf[self.len..][0..count], byte);
        self.len += count;
    }

    fn slice(self: *Out) []u8 {
        return self.buf[0..self.len];
    }
};

const max_digits = 800;

const Decimal = struct {
    digits: [max_digits]u8 = undefined,
    len: usize = 0,
    exponent: i32 = 0,

    fn digitAt(self: *const Decimal, index: isize) u8 {
        if (index < 0 or index >= self.len) return '0';
        return self.digits[@intCast(index)];
    }
};

const BigInt = struct {
    limbs: [90]u32 = undefined,
    len: usize = 0,

    fn init(value: u64) BigInt {
        var big = BigInt{};
        big.limbs[0] = @truncate(value);
        big.limbs[1] = @truncate(value >> 32);
        big.len = if (big.limbs[1] != 0) 2 else if (big.limbs[0] != 0) 1 else 0;
        return big;
    }

    fn mulSmall(self: *BigInt, factor: u32) void {
        var carry: u64 = 0;
        for (self.limbs[0..self.len]) |*limb| {
            const product = @as(u64, limb.*) * factor + carry;
            limb.* = @truncate(product);
            carry = product >> 32;
        }
        if (carry != 0) {
            self.limbs[self.len] = @intCast(carry);
            self.len += 1;
        }
    }

    fn shiftLeft(self: *BigInt, bits: u32) void {
        if (self.len == 0) return;
        const bit_shift: u5 = @intCast(bits % 32);
        if (bit_shift != 0) {
            const back: u5 = @intCast(32 - @as(u32, bit_shift));
            var carry: u32 = 0;
            for (self.limbs[0..self.len]) |*limb| {
                const next = limb.* >> back;
                limb.* = (limb.* << bit_shift) | carry;
                carry = next;
            }
            if (carry != 0) {
                self.limbs[self.len] = carry;
                self.len += 1;
            }
        }
        const limb_shift: usize = bits / 32;
        if (limb_shift != 0) {
            std.mem.copyBackwards(u32, self.limbs[limb_shift..][0..self.len], self.limbs[0..self.len]);
            @memset(self.limbs[0..limb_shift], 0);
            self.len += limb_shift;
        }
    }

    fn divSmall(self: *BigInt, divisor: u32) u32 {
        var remainder: u64 = 0;
        var index = self.len;
        while (index > 0) {
            index -= 1;
            const current = (remainder << 32) | self.limbs[index];
            self.limbs[index] = @intCast(current / divisor);
            remainder = current % divisor;
        }
        while (self.len > 0 and self.limbs[self.len - 1] == 0) self.len -= 1;
        return @intCast(remainder);
    }
};

fn exactDecimal(value: f64, out: *Decimal) void {
    const bits: u64 = @bitCast(value);
    const exponent_bits: u32 = @intCast((bits >> 52) & 0x7ff);
    var mantissa: u64 = bits & ((@as(u64, 1) << 52) - 1);
    var exponent: i32 = -1074;
    if (exponent_bits != 0) {
        mantissa |= @as(u64, 1) << 52;
        exponent = @as(i32, @intCast(exponent_bits)) - 1075;
    }
    while (mantissa & 1 == 0) {
        mantissa >>= 1;
        exponent += 1;
    }

    var big = BigInt.init(mantissa);
    var scale: i32 = 0;
    if (exponent >= 0) {
        big.shiftLeft(@intCast(exponent));
    } else {
        scale = -exponent;
        var remaining: u32 = @intCast(-exponent);
        while (remaining >= 13) : (remaining -= 13) big.mulSmall(1220703125); // 5^13
        var factor: u32 = 1;
        while (remaining > 0) : (remaining -= 1) factor *= 5;
        if (factor != 1) big.mulSmall(factor);
    }

    var chunks: [max_digits / 9 + 2]u32 = undefined;
    var chunk_count: usize = 0;
    while (big.len > 0) {
        chunks[chunk_count] = big.divSmall(1_000_000_000);
        chunk_count += 1;
    }

    var len: usize = 0;
    var index = chunk_count;
    var first = true;
    while (index > 0) {
        index -= 1;
        var chunk = chunks[index];
        var scratch: [9]u8 = undefined;
        var pos: usize = 9;
        while (pos > 0) {
            pos -= 1;
            scratch[pos] = '0' + @as(u8, @intCast(chunk % 10));
            chunk /= 10;
            if (first and chunk == 0) break;
        }
        first = false;
        const digits = scratch[pos..];
        @memcpy(out.digits[len..][0..digits.len], digits);
        len += digits.len;
    }
    out.exponent = @as(i32, @intCast(len)) - 1 - scale;
    while (len > 0 and out.digits[len - 1] == '0') len -= 1;
    out.len = len;
}

fn roundDecimal(decimal: *Decimal, count: isize) void {
    if (decimal.len == 0 or count >= decimal.len) return;
    if (count < 0) {
        decimal.len = 0;
        decimal.exponent = 0;
        return;
    }
    const keep: usize = @intCast(count);
    const next = decimal.digits[keep];
    const round_up = if (next > '5')
        true
    else if (next < '5')
        false
    else if (decimal.len > keep + 1)
        true
    else
        keep > 0 and (decimal.digits[keep - 1] - '0') % 2 == 1;

    decimal.len = keep;
    if (round_up) {
        var index = keep;
        var carry = true;
        while (index > 0 and carry) {
            index -= 1;
            if (decimal.digits[index] == '9') {
                decimal.digits[index] = '0';
            } else {
                decimal.digits[index] += 1;
                carry = false;
            }
        }
        if (carry) {
            decimal.digits[0] = '1';
            decimal.len = 1;
            decimal.exponent += 1;
        }
    }
    while (decimal.len > 0 and decimal.digits[decimal.len - 1] == '0') decimal.len -= 1;
    if (decimal.len == 0) decimal.exponent = 0;
}

fn appendExponentStyle(out: *Out, decimal: *const Decimal, precision: usize, alternate: bool) void {
    out.push(decimal.digitAt(0));
    if (precision > 0 or alternate) out.push('.');
    for (1..precision + 1) |index| out.push(decimal.digitAt(@intCast(index)));
    out.push('e');
    const exponent = if (decimal.len == 0) 0 else decimal.exponent;
    out.push(if (exponent < 0) '-' else '+');
    const magnitude: u32 = @abs(exponent);
    if (magnitude < 10) out.push('0');
    var scratch: [8]u8 = undefined;
    out.pushSlice(std.fmt.bufPrint(&scratch, "{d}", .{magnitude}) catch unreachable);
}

fn appendFixedStyle(out: *Out, decimal: *const Decimal, precision: usize, alternate: bool) void {
    if (decimal.len == 0 or decimal.exponent < 0) {
        out.push('0');
    } else {
        var index: isize = 0;
        while (index <= decimal.exponent) : (index += 1) out.push(decimal.digitAt(index));
    }
    if (precision > 0 or alternate) out.push('.');
    const first_fraction: isize = if (decimal.len == 0) std.math.minInt(i32) else @as(isize, decimal.exponent) + 1;
    for (0..precision) |offset| out.push(decimal.digitAt(first_fraction + @as(isize, @intCast(offset))));
}

fn appendGeneralStyle(out: *Out, decimal: *Decimal, requested_precision: ?usize, alternate: bool) void {
    const precision = @max(requested_precision orelse 6, 1);
    roundDecimal(decimal, @intCast(precision));
    const exponent: isize = if (decimal.len == 0) 0 else decimal.exponent;
    const start = out.len;
    if (@as(isize, @intCast(precision)) > exponent and exponent >= -4) {
        appendFixedStyle(out, decimal, @intCast(@as(isize, @intCast(precision)) - 1 - exponent), alternate);
    } else {
        appendExponentStyle(out, decimal, precision - 1, alternate);
    }
    if (alternate) return;

    const text = out.buf[start..out.len];
    const point = std.mem.indexOfScalar(u8, text, '.') orelse return;
    const mantissa_end = std.mem.indexOfScalar(u8, text, 'e') orelse text.len;
    var keep = mantissa_end;
    while (keep > point + 1 and text[keep - 1] == '0') keep -= 1;
    if (keep == point + 1) keep = point;
    const removed = mantissa_end - keep;
    if (removed == 0) return;
    std.mem.copyForwards(u8, text[keep..], text[mantissa_end..]);
    out.len -= removed;
}

fn appendHex(out: *Out, magnitude: f64, precision: ?usize, alternate: bool) void {
    const bits: u64 = @bitCast(magnitude);
    const exponent_bits: u32 = @intCast((bits >> 52) & 0x7ff);
    const fraction_mask = (@as(u64, 1) << 52) - 1;
    var lead: u8 = 1;
    var fraction: u64 = bits & fraction_mask;
    var exponent: i32 = @as(i32, @intCast(exponent_bits)) - 1023;
    if (magnitude == 0) {
        lead = 0;
        exponent = 0;
    } else if (exponent_bits == 0) {
        if (darwin_printf) {
            var mantissa = fraction;
            exponent = -1022;
            while (mantissa & (@as(u64, 1) << 52) == 0) {
                mantissa <<= 1;
                exponent -= 1;
            }
            fraction = mantissa & fraction_mask;
        } else {
            lead = 0;
            exponent = -1022;
        }
    }

    var digits: [13]u8 = undefined;
    for (&digits, 0..) |*digit, index| digit.* = @intCast((fraction >> @intCast(48 - 4 * index)) & 0xf);

    var count: usize = 13;
    if (precision) |wanted| {
        count = wanted;
        if (wanted < 13) {
            const next = digits[wanted];
            const round_up = if (darwin_printf) blk: {
                const after: u8 = if (wanted + 1 < 13) digits[wanted + 1] else 0;
                break :blk next > 8 or (next == 8 and after & 1 == 1);
            } else blk: {
                var rest_nonzero = false;
                for (digits[wanted + 1 ..]) |digit| rest_nonzero = rest_nonzero or digit != 0;
                const last = if (wanted > 0) digits[wanted - 1] else lead;
                break :blk next > 8 or (next == 8 and (rest_nonzero or last & 1 == 1));
            };
            if (round_up) {
                var index = wanted;
                var carry = true;
                while (index > 0 and carry) {
                    index -= 1;
                    if (digits[index] == 0xf) {
                        digits[index] = 0;
                    } else {
                        digits[index] += 1;
                        carry = false;
                    }
                }
                if (carry) lead += 1;
            }
        }
    } else {
        while (count > 0 and digits[count - 1] == 0) count -= 1;
    }

    const hex = "0123456789abcdef";
    out.pushSlice("0x");
    out.push(hex[lead]);
    if (count > 0 or alternate) out.push('.');
    for (0..count) |index| out.push(if (index < 13) hex[digits[index]] else '0');
    out.push('p');
    out.push(if (exponent < 0) '-' else '+');
    var scratch: [8]u8 = undefined;
    out.pushSlice(std.fmt.bufPrint(&scratch, "{d}", .{@abs(exponent)}) catch unreachable);
}

fn expectFormat(expected: []const u8, spec: Spec, value: f64) !void {
    var buffer: [max_formatted_len]u8 = undefined;
    try std.testing.expectEqualStrings(expected, formatFloat(&buffer, spec, value));
}

fn expectLua(expected: []const u8, value: f64) !void {
    var buffer: [max_lua_float_len]u8 = undefined;
    try std.testing.expectEqualStrings(expected, formatLuaFloat(&buffer, value));
}

test "Lua float strings use %.15g, then %.17g when needed" {
    try expectLua("1e+15", 1e15);
    try expectLua("9.2233720368547758e+18", 0x1p63);
    try expectLua("-9.2233720368547758e+18", -0x1p63);
    try expectLua("0.1", 0.1);
    try expectLua("0.33333333333333331", 1.0 / 3.0);
    try expectLua("9007199254740992.0", 0x1p53);
    try expectLua("123456789012345.0", 123456789012345.0);
    try expectLua("3.1415926535897931", std.math.pi);
    try expectLua("4.94065645841247e-324", 5e-324);
    try expectLua("1.7976931348623157e+308", std.math.floatMax(f64));
    try expectLua("-0.0", -0.0);
    try expectLua("0.0", 0.0);
    try expectLua("1e-05", 1e-5);
    try expectLua("1e+100", 1e100);
    try expectLua("inf", std.math.inf(f64));
    try expectLua("-inf", -std.math.inf(f64));
    try expectLua("0.30000000000000004", 0.30000000000000004);
    try expectLua("1e+16", 1e16);
    try expectLua("2.5", 2.5);
    try expectLua("100.0", 100.0);
    try expectLua("2.2250738585072014e-308", std.math.floatMin(f64));
}

test "Lua float strings agree with the exact %.15g/%.17g rule" {
    var prng = std.Random.DefaultPrng.init(0x5eed);
    const random = prng.random();
    var buffer: [max_lua_float_len]u8 = undefined;
    var scratch: [max_formatted_len]u8 = undefined;
    for (0..20000) |_| {
        const value: f64 = @bitCast(random.int(u64));
        if (!std.math.isFinite(value)) continue;
        var expected = formatFloat(&scratch, .{ .conversion = 'g', .precision = 15 }, value);
        if ((std.fmt.parseFloat(f64, expected) catch unreachable) != value) expected = formatFloat(&scratch, .{ .conversion = 'g', .precision = 17 }, value);
        const actual = formatLuaFloat(&buffer, value);
        try std.testing.expectEqualStrings(expected, actual[0 .. actual.len - @as(usize, if (looksLikeInteger(expected)) 2 else 0)]);
    }
}

test "printf conversions match C" {
    try expectFormat("0.10000000000000001", .{ .conversion = 'g', .precision = 17 }, 0.1);
    try expectFormat("1.000000e+00", .{ .conversion = 'e' }, 1.0);
    try expectFormat("2e+01", .{ .conversion = 'e', .precision = 0 }, 25.0);
    try expectFormat("2", .{ .conversion = 'f', .precision = 0 }, 2.5);
    try expectFormat("2", .{ .conversion = 'f', .precision = 0 }, 1.5);
    try expectFormat("0", .{ .conversion = 'f', .precision = 0 }, 0.5);
    try expectFormat("1.00", .{ .conversion = 'f', .precision = 2 }, 1.005);
    try expectFormat("10.0", .{ .conversion = 'f', .precision = 1 }, 9.96);
    try expectFormat("123.", .{ .conversion = 'g', .precision = 3, .alternate = true }, 123.456);
    try expectFormat("1e+02", .{ .conversion = 'g', .precision = 0 }, 123.456);
    try expectFormat("0.0001234", .{ .conversion = 'g' }, 0.0001234);
    try expectFormat("1e-05", .{ .conversion = 'g' }, 1e-5);
    try expectFormat("+001.000e+00", .{ .conversion = 'e', .precision = 3, .force_sign = true, .zero_pad = true, .width = 12 }, 1.0);
    try expectFormat("-00003.142", .{ .conversion = 'f', .precision = 3, .zero_pad = true, .width = 10 }, -std.math.pi);
    try expectFormat("  inf", .{ .conversion = 'g', .width = 5, .zero_pad = true }, std.math.inf(f64));
    try expectFormat("-INF", .{ .conversion = 'E' }, -std.math.inf(f64));
    try expectFormat("0x1p+0", .{ .conversion = 'a' }, 1.0);
    try expectFormat("-0x1.80p+0", .{ .conversion = 'a', .precision = 2, .zero_pad = true, .width = 10 }, -1.5);
    try expectFormat("0x00001.8p+0", .{ .conversion = 'a', .zero_pad = true, .width = 12 }, 1.5);
    try expectFormat("0x1.999999999999ap-4", .{ .conversion = 'a' }, 0.1);
    try expectFormat("0X1.99AP-4", .{ .conversion = 'A', .precision = 3 }, 0.1);
    try expectFormat("0x2.000p+1023", .{ .conversion = 'a', .precision = 3 }, std.math.floatMax(f64));
    try expectFormat("0x0p+0", .{ .conversion = 'a' }, 0.0);
    try expectFormat("-0x0p+0", .{ .conversion = 'a' }, -0.0);
}
