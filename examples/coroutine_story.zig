//! Drive a loaded script, a terminal host callback, and a continuation from Zig.
const std = @import("std");
const zlua = @import("zlua");

fn askUser(ctx: *zlua.Context) !void {
    const prompt = try ctx.arg(0, []const u8);
    return ctx.yield(.{prompt});
}

fn confirm(ctx: *zlua.Context, prompt: []const u8) !void {
    return ctx.yieldThen(.{prompt}, answered, .{prompt});
}

fn answered(ctx: *zlua.Context, answer: []const u8) ![]const u8 {
    const prompt = try ctx.upvalue(0, []const u8);
    return if (std.mem.eql(u8, answer, "yes")) prompt else "declined";
}

pub fn main() !void {
    const lua = try zlua.State.init(std.heap.smp_allocator, .{});
    defer lua.deinit();

    var chunk = try lua.loadString(
        \\coroutine.yield("show dialogue")
        \\return "story finished"
    , .{ .name = "=story.lua" });
    defer chunk.deinit();
    var story = try lua.newCoroutine(chunk);
    defer story.deinit();

    while (try story.status() == .suspended) {
        var step = try story.resumeCoroutine(.{}, zlua.String, zlua.String);
        defer step.deinit();
        switch (step) {
            .yielded => |text| std.debug.print("yielded: {s}\n", .{try text.bytes()}),
            .returned => |text| std.debug.print("returned: {s}\n", .{try text.bytes()}),
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
    var prompt = try exchange.resumeCoroutine(.{}, zlua.String, zlua.String);
    defer prompt.deinit();
    const question = switch (prompt) {
        .yielded => |text| try text.bytes(),
        .returned => return error.ExpectedPrompt,
    };
    std.debug.print("{s}\n", .{question});
    var answer = try exchange.resumeCoroutine(.{"yes"}, zlua.String, zlua.String);
    defer answer.deinit();
    switch (answer) {
        .returned => |text| std.debug.print("{s}\n", .{try text.bytes()}),
        .yielded => return error.ExpectedReturn,
    }

    try lua.setGlobal("confirm", confirm);
    var confirmation = try lua.loadString(
        \\return "Confirmed: " .. confirm("Take the key?")
    , .{ .name = "=confirm.lua" });
    defer confirmation.deinit();
    var flow = try lua.newCoroutine(confirmation);
    defer flow.deinit();
    var asked = try flow.resumeCoroutine(.{}, zlua.String, void);
    defer asked.deinit();
    std.debug.print("{s}\n", .{try asked.yielded.bytes()});
    var confirmed = try flow.resumeCoroutine(.{"yes"}, void, zlua.String);
    defer confirmed.deinit();
    std.debug.print("{s}\n", .{try confirmed.returned.bytes()});
}
