const std = @import("std");
const zlua = @import("zlua");

const Budget = struct {
    remaining: i64,

    pub fn init(ctx: *zlua.Context, amount: i64) !Budget {
        if (amount < 0) return ctx.raise("a budget can't start negative");
        return .{ .remaining = amount };
    }

    pub fn spend(self: *Budget, amount: i64) i64 {
        self.remaining = @max(self.remaining - amount, 0);
        return self.remaining;
    }
};

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;

    const lua = try zlua.State.init(allocator, .{});
    defer lua.deinit();

    var new_budget = try lua.newConstructor(Budget, "new_budget", Budget.init, .{});
    defer new_budget.deinit();
    try lua.setGlobal("new_budget", new_budget);

    var chunk = try lua.loadString(
        \\local budget = new_budget(25)
        \\assert(budget:spend(7) == 18)
        \\assert(budget:spend(20) == 0)
        \\assert(not pcall(new_budget, -1))
        \\return budget
    , .{ .name = "=userdata_constructor" });
    defer chunk.deinit();

    var budget = try chunk.call(.{}, zlua.Userdata(Budget));
    defer budget.deinit();

    std.debug.print("remaining={d}\n", .{(try budget.ptr()).remaining});
}
