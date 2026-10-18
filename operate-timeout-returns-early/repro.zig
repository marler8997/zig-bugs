const std = @import("std");

pub fn main(init: std.process.Init) !u8 {
    const io = init.io;

    // a connected socket with no data to read, so the read can only time out
    const path = "zig-bugs-operate-timeout.sock";
    std.Io.Dir.cwd().deleteFile(io, path) catch {};
    defer std.Io.Dir.cwd().deleteFile(io, path) catch {};
    const address: std.Io.net.UnixAddress = try .init(path);
    var server = try address.listen(io, .{});
    defer server.deinit(io);
    const client = try address.connect(io);
    defer client.close(io);
    const conn = try server.accept(io);
    defer conn.close(io);

    var buffer: [64]u8 = undefined;
    var data: [1][]u8 = .{&buffer};
    var early = false;
    for ([_]i64{ 1, 2, 5, 15 }) |timeout_ms| {
        var shortest: std.Io.Duration = .fromSeconds(1000);
        for (0..20) |_| {
            const start = std.Io.Timestamp.now(io, .awake);
            if (io.operateTimeout(.{ .net_read = .{
                .socket_handle = client.socket.handle,
                .data = &data,
            } }, .{ .duration = .{ .raw = .fromMilliseconds(timeout_ms), .clock = .awake } })) |_| {
                std.debug.print("read unexpectedly completed\n", .{});
                return 2;
            } else |err| switch (err) {
                error.Timeout => {},
                else => |e| return e,
            }
            const waited = start.untilNow(io, .awake);
            if (waited.nanoseconds < shortest.nanoseconds) shortest = waited;
        }
        const waited_us = shortest.toMicroseconds();
        std.debug.print("{}ms timeout: shortest wait {}us\n", .{ timeout_ms, waited_us });
        if (waited_us < timeout_ms * std.time.us_per_ms) early = true;
    }
    if (early) {
        std.debug.print("bug: operateTimeout returned error.Timeout before the timeout elapsed\n", .{});
        return 1;
    }
    return 0;
}
