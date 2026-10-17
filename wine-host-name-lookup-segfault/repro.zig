const std = @import("std");

pub fn main(init: std.process.Init) !u8 {
    const io = init.io;
    const host_name: std.Io.net.HostName = try .init("localhost");
    var queue_buf: [16]std.Io.net.HostName.LookupResult = undefined;
    var queue: std.Io.Queue(std.Io.net.HostName.LookupResult) = .init(&queue_buf);
    // segfaults under wine while reading the hosts file path from the PEB
    try host_name.lookup(io, &queue, .{ .port = 80 });
    var address_count: usize = 0;
    while (queue.getOne(io)) |result| switch (result) {
        .address => |address| {
            std.debug.print("localhost resolved to {f}\n", .{address});
            address_count += 1;
        },
        .canonical_name => {},
    } else |err| switch (err) {
        error.Closed => {},
        error.Canceled => |e| return e,
    }
    if (address_count == 0) {
        std.debug.print("bug: localhost resolved to no addresses\n", .{});
        return 1;
    }
    return 0;
}
