//! Run: zig build run-example -- coroutine_story
//! Drive a loaded script and a terminal host callback from Zig.
const std = @import("std");
const zlua = @import("zlua");

fn askUser(ctx: *zlua.Context) !void {
    const prompt = try ctx.arg(0, []const u8);
    return ctx.yield(.{prompt});
}

pub fn main() !void {
    var lua = try zlua.State.init(std.heap.smp_allocator, .{});
    defer lua.deinit();

    var chunk = try lua.loadString(
        \\coroutine.yield("show dialogue")
        \\return "story finished"
    , .{ .name = "=story.lua" });
    defer chunk.deinit();
    var story = try lua.newCoroutine(chunk);
    defer story.deinit();

    while (try story.status() == .suspended) {
        var step = try story.resumeCoroutine(.{}, []const u8, []const u8);
        defer step.deinit();
        switch (step) {
            .yielded => |text| std.debug.print("yielded: {s}\n", .{text}),
            .returned => |text| std.debug.print("returned: {s}\n", .{text}),
        }
    }

    var ask = try lua.register("ask_user", askUser);
    defer ask.deinit();
    try lua.setGlobal("ask_user", ask);
    var dialogue = try lua.loadString(
        \\local answer = ask_user("Open the door?")
        \\return "You chose: " .. answer
    , .{ .name = "=dialogue.lua" });
    defer dialogue.deinit();
    var exchange = try lua.newCoroutine(dialogue);
    defer exchange.deinit();
    var prompt = try exchange.resumeCoroutine(.{}, []const u8, []const u8);
    defer prompt.deinit();
    const question = switch (prompt) {
        .yielded => |text| text,
        .returned => return error.ExpectedPrompt,
    };
    std.debug.print("{s}\n", .{question});
    var answer = try exchange.resumeCoroutine(.{"yes"}, []const u8, []const u8);
    defer answer.deinit();
    switch (answer) {
        .returned => |text| std.debug.print("{s}\n", .{text}),
        .yielded => return error.ExpectedReturn,
    }
}
