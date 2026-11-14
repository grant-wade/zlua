const std = @import("std");
const zlua = @import("zlua");

const Budget = struct {
    remaining: i64,
    spent: i64,
};

const BudgetMethods = struct {
    pub fn spend(self: *Budget, amount: i64) i64 {
        self.remaining = @max(self.remaining - amount, 0);
        self.spent += amount;
        return self.remaining;
    }

    pub fn refund(self: *Budget, amount: i64) i64 {
        self.remaining += amount;
        self.spent = @max(self.spent - amount, 0);
        return self.remaining;
    }

    pub fn spent(self: *Budget) i64 {
        return self.spent;
    }

    pub fn available(self: *Budget) i64 {
        return self.remaining;
    }
};

fn newBudget(ctx: *zlua.Context, amount: i64) !zlua.Userdata(Budget) {
    return ctx.state().newUserdata(Budget, .{ .remaining = amount, .spent = 0 }, .{});
}

fn percent(part: f64, whole: f64) f64 {
    if (whole == 0) return 0;
    return part / whole * 100;
}

fn hostAudit(ctx: *zlua.Context) !void {
    const label = try ctx.arg(0, []const u8);
    const amount = try ctx.arg(1, i64);
    if (amount < 0) return ctx.raise("audit amounts must be non-negative");

    std.debug.print("audit: {s}={d}\n", .{ label, amount });
    try ctx.returnValues(.{ true, "recorded" });
}

pub fn main() !void {
    const allocator = std.heap.smp_allocator;

    const lua = try zlua.State.init(allocator, .{});
    defer lua.deinit();

    try lua.setGlobal("settings", .{
        .name = "zlua-test integration",
        .features = &.{ "globals", "modules", "callbacks", "userdata" },
    });

    try lua.defineUserdata(Budget, .{ .methods = BudgetMethods });

    var rules = try lua.newTable(.{});
    defer rules.deinit();
    try rules.set("starting_budget", 150);
    try rules.set("warning_at", 40);
    try lua.setLoadedModule("rules", rules);

    try lua.addMemoryFile("plugins/planner.lua",
        \\local M = {}
        \\function M.plan(items)
        \\  local total = 0
        \\  for i = 1, #items do
        \\    total = total + items[i].cost
        \\  end
        \\  return { name = 'weekend trip', items = items, total = total }
        \\end
        \\return M
    );
    try lua.setPackagePath("plugins/?.lua");

    var new_budget = try lua.newTypedFunction("new_budget", newBudget);
    defer new_budget.deinit();
    try lua.setGlobal("new_budget", new_budget);

    var percent_fn = try lua.newTypedFunction("percent", percent);
    defer percent_fn.deinit();
    try lua.setGlobal("percent", percent_fn);

    var audit = try lua.newFunction("host_audit", hostAudit);
    defer audit.deinit();
    try lua.setGlobal("host_audit", audit);

    var chunk = try lua.loadString(
        \\local rules = require('rules')
        \\local planner = require('planner')
        \\assert(settings.features[4] == 'userdata')
        \\
        \\local budget = new_budget(rules.starting_budget)
        \\budget:spend(37)
        \\budget:refund(5)
        \\
        \\local plan = planner.plan({
        \\  { name = 'train', cost = 41 },
        \\  { name = 'lunch', cost = 18 },
        \\  { name = 'museum', cost = 24 },
        \\})
        \\
        \\for i = 1, #plan.items do
        \\  budget:spend(plan.items[i].cost)
        \\end
        \\
        \\local ok, audit_label = host_audit('spent', budget:spent())
        \\assert(ok == true and audit_label == 'recorded')
        \\
        \\return {
        \\  title = settings.name,
        \\  plan = plan.name,
        \\  planned = plan.total,
        \\  spent = budget:spent(),
        \\  remaining = budget:available(),
        \\  used_percent = percent(budget:spent(), rules.starting_budget),
        \\  warned = budget:available() <= rules.warning_at,
        \\}, function(extra)
        \\  return budget:spend(extra)
        \\end, budget
    , .{ .name = "=zlua_test_integration" });
    defer chunk.deinit();

    var result = try chunk.call(.{}, struct { zlua.Table, zlua.Function, zlua.Userdata(Budget) });
    defer zlua.deinit(&result);

    try lua.collect();

    const report, const spend_more, const budget = result;

    const after_extra = try spend_more.call(.{6}, i64);
    var title = try report.get("title", zlua.String);
    defer title.deinit();
    var plan = try report.get("plan", zlua.String);
    defer plan.deinit();

    std.debug.print(
        "{f}: {f}, planned={d}, spent={d}, remaining={d}, used={d:.1}%, warned={}, after_extra={d}, userdata_remaining={d}\n",
        .{
            title,
            plan,
            try report.get("planned", i64),
            try report.get("spent", i64),
            try report.get("remaining", i64),
            try report.get("used_percent", f64),
            try report.get("warned", bool),
            after_extra,
            (try budget.ptr()).remaining,
        },
    );

    var failing = try lua.loadString("return host_audit('refund', -1)", .{ .name = "=zlua_test_protected_error" });
    defer failing.deinit();

    if (failing.call(.{}, void)) |_| return error.ExpectedLuaError else |err| {
        if (err != error.LuaError) return err;
        var failure = lua.takeError().?;
        defer failure.deinit();
        std.debug.print("lua error: {f}\n", .{failure});
    }
}
