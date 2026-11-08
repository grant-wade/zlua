const convert = @import("convert.zig");
const AnyUserdata = @import("userdata.zig").AnyUserdata;
const Coroutine = @import("coroutine.zig").Coroutine;
const Function = @import("function.zig").Function;
const String = @import("string.zig").String;
const Table = @import("table.zig").Table;

/// Dynamic Lua value; handle variants are rooted and released by `deinit`.
pub const Value = union(enum) {
    nil,
    boolean: bool,
    integer: i64,
    number: f64,
    string: String,
    table: Table,
    function: Function,
    coroutine: Coroutine,
    userdata: AnyUserdata,

    pub fn deinit(self: *Value) void {
        switch (self.*) {
            .string => |*string| string.deinit(),
            .table => |*table| table.deinit(),
            .function => |*function| function.deinit(),
            .userdata => |*userdata| userdata.deinit(),
            .coroutine => |*coroutine| coroutine.deinit(),
            else => {},
        }
        self.* = undefined;
    }

    /// The name Lua's `type` gives this value.
    pub fn typeName(self: Value) []const u8 {
        return switch (self) {
            .nil => "nil",
            .boolean => "boolean",
            .integer, .number => "number",
            .string => "string",
            .table => "table",
            .function => "function",
            .coroutine => "thread",
            .userdata => "userdata",
        };
    }
};

/// Converts multiple Lua return values.
pub fn Tuple(comptime types: []const type) type {
    return struct {
        /// Marker for zlua's compile-time conversions.
        pub const is_zlua_tuple = true;
        pub const field_types = types;

        values: @Tuple(types),

        pub fn deinit(self: *@This()) void {
            inline for (types, 0..) |Field, index| convert.deinitIfOwned(Field, &self.values[index]);
            self.* = undefined;
        }

        pub fn get(self: *const @This(), comptime index: usize) types[index] {
            return self.values[index];
        }
    };
}
