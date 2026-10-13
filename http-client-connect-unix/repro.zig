const std = @import("std");

pub fn main(init: std.process.Init) !u8 {
    const io = init.io;
    const path = "zig-bugs-connect-unix.sock";
    std.Io.Dir.cwd().deleteFile(io, path) catch |err| switch (err) {
        error.FileNotFound => {},
        else => |e| return e,
    };
    const address: std.Io.net.UnixAddress = try .init(path);
    var server = try address.listen(io, .{});
    defer server.deinit(io);
    defer std.Io.Dir.cwd().deleteFile(io, path) catch |err| std.debug.panic("delete '{s}' failed with {t}", .{ path, err });

    var client: std.http.Client = .{ .allocator = init.gpa, .io = io };
    defer client.deinit();
    const connection = try client.connectUnix(path);
    client.connection_pool.release(connection, io);
    std.debug.print("connectUnix connected to '{s}'\n", .{path});
    return 0;
}
