//! Run: zig build run-example -- snapshot_adventure
//! Try several futures from one suspended coroutine, then replay the best one.
const std = @import("std");
const zlua = @import("zlua");

pub fn main() !void {
    const allocator = std.heap.smp_allocator;
    var lua = try zlua.State.init(allocator, .{ .stdlib = .full });
    defer lua.deinit();

    try lua.doString(
        \\world = { dragon_awake = false, treasure = 120, journal = {} }
        \\local attempts = 0
        \\adventure = coroutine.create(function()
        \\    local hp, gold = 100, 0
        \\    table.insert(world.journal, "Reached the dragon's lair")
        \\    local choice = coroutine.yield()
        \\    if choice == "fight" then
        \\        world.dragon_awake = true
        \\        hp = hp - 80
        \\        gold = world.treasure
        \\    elseif choice == "sneak" then
        \\        gold = world.treasure - 30
        \\    elseif choice == "bargain" then
        \\        world.dragon_awake = true
        \\        gold = world.treasure // 2
        \\    else
        \\        error("unknown choice: " .. choice)
        \\    end
        \\    world.treasure = world.treasure - gold
        \\    table.insert(world.journal, choice)
        \\    return hp, gold
        \\end)
        \\assert(coroutine.resume(adventure))
        \\function explore(choice)
        \\    -- Every branch must start with the same table, closure and stack.
        \\    assert(attempts == 0)
        \\    assert(not world.dragon_awake and world.treasure == 120)
        \\    assert(#world.journal == 1 and report == nil)
        \\    assert(coroutine.status(adventure) == "suspended")
        \\    attempts = attempts + 1
        \\    local ok, hp, gold = coroutine.resume(adventure, choice)
        \\    assert(ok, hp)
        \\    assert(coroutine.status(adventure) == "dead")
        \\    report = string.format("%s: %d HP, %d gold, dragon %s",
        \\        choice, hp, gold, world.dragon_awake and "awake" or "asleep")
        \\    return hp + gold
        \\end
    , .{ .name = "=adventure" });

    // Capture after initialization, with the adventure paused at its choice.
    var snapshot = try lua.snapshot(allocator);
    defer snapshot.deinit();

    // These Zig values survive resets: keep only the winning choice and score.
    var best_choice: []const u8 = "";
    var best_score: i64 = -1;
    for ([_][]const u8{ "fight", "sneak", "bargain" }) |choice| {
        try lua.reset();
        const score = try explore(&lua, choice);
        if (score > best_score) {
            best_choice = choice;
            best_score = score;
        }
    }

    // Discard the last trial and leave the VM in the winning future.
    std.debug.print("\nReplay winner (HP + gold = {d}):\n", .{best_score});
    try lua.reset();
    if (try explore(&lua, best_choice) != best_score) return error.ReplayMismatch;
}

fn explore(lua: *zlua.State, choice: []const u8) !i64 {
    // Reset invalidates earlier handles; acquire a fresh one for each future.
    var function = try lua.getGlobal("explore", zlua.Function);
    defer function.deinit();
    const score = try function.call(.{choice}, i64);
    const report = try lua.getGlobal("report", []const u8);
    std.debug.print("  {s} (score {d})\n", .{ report, score });
    return score;
}
