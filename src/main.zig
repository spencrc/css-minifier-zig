const std = @import("std");
const builtin = @import("builtin");
const lexer = @import("lexer.zig");

pub fn main() !void {
    var debug_allocator: std.heap.DebugAllocator(.{}) = .init;
    const allocator: std.mem.Allocator = allocator: {
        break :allocator switch (builtin.mode) {
            .Debug, .ReleaseSafe => debug_allocator.allocator(),
            .ReleaseFast, .ReleaseSmall => std.heap.smp_allocator,
        };
    };
    const is_debug: bool = allocator: {
        break :allocator switch (builtin.mode) {
            .Debug, .ReleaseSafe => true,
            .ReleaseFast, .ReleaseSmall => false,
        };
    };
    defer if (is_debug) {
        _ = debug_allocator.deinit();
    };

    const input = @embedFile("input/main.css");

    try std.fs.cwd().makePath("output");
    var file = try std.fs.cwd().createFile("output/main.css", .{});
    defer file.close();

    var writer = file.writer(&.{});
    var writer_interface = &writer.interface;

    var scanner = lexer.Scanner.init(allocator, input);
    defer scanner.deinit();

    const tokens = try scanner.scan_tokens();
    var prev: lexer.Token = undefined;
    for (tokens.items) |current| {
        if (current.type == .EOF)
            break;
        if ((prev.type == .NUMBER or prev.type == .IDENT) and (current.type == .NUMBER or current.type == .IDENT))
            try writer_interface.writeByte(' ');
        try writer_interface.writeAll(current.lexeme);
        prev = current;
    }
}
