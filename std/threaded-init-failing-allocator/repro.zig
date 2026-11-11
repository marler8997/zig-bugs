const std = @import("std");

pub fn main(init: std.process.Init.Minimal) !u8 {
    var args_buffer: [4096]u8 = undefined;
    var args_allocator: std.heap.FixedBufferAllocator = .init(&args_buffer);
    var args = try init.args.iterateAllocator(args_allocator.allocator());
    const exe = args.next().?;
    // the child process, see below
    if (args.next() != null) return 0;

    // nothing in this program uses async, concurrent, groupAsync or groupConcurrent, so
    // according to the docs of `init` this allocator is never used
    var threaded: std.Io.Threaded = .init(.failing, .{
        .environ = init.environ,
        .argv0 = .init(init.args),
    });
    const io = threaded.io();

    var child = std.process.spawn(io, .{ .argv = &.{ exe, "child" } }) catch |err| {
        std.debug.print("bug: spawn failed with {t}\n", .{err});
        return 1;
    };
    switch (try child.wait(io)) {
        .exited => |code| if (code == 0) return 0,
        else => {},
    }
    std.debug.print("the child process failed\n", .{});
    return 2;
}
