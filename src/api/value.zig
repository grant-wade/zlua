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
