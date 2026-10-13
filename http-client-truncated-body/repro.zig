const std = @import("std");

pub fn main(init: std.process.Init) !u8 {
    const io = init.io;
    const address: std.Io.net.IpAddress = try .parse("127.0.0.1", 0);
    var server = try address.listen(io, .{});
    defer server.deinit(io);
    const port = server.socket.address.getPort();

    const thread = try std.Thread.spawn(.{}, serve, .{ io, &server });
    defer thread.join();

    var url_buf: [64]u8 = undefined;
    const url = try std.fmt.bufPrint(&url_buf, "http://127.0.0.1:{d}/", .{port});
    var client: std.http.Client = .{ .allocator = init.gpa, .io = io };
    defer client.deinit();
    var body: std.Io.Writer.Allocating = .init(init.gpa);
    defer body.deinit();
    const result = client.fetch(.{
        .location = .{ .url = url },
        .keep_alive = false,
        .response_writer = &body.writer,
    }) catch |err| {
        std.debug.print("fetch failed with {t} (expected)\n", .{err});
        return 0;
    };
    std.debug.print("fetch succeeded: status {t}, {d} of 1000000 bytes\n", .{ result.status, body.written().len });
    std.debug.print("bug: a body shorter than its Content-Length was accepted\n", .{});
    return 1;
}

fn serve(io: std.Io, server: *std.Io.net.Server) void {
    const stream = server.accept(io) catch |err| std.debug.panic("accept failed with {t}", .{err});
    defer stream.close(io);
    var buf: [256]u8 = undefined;
    var reader = stream.reader(io, &buf);
    while (true) {
        const line = reader.interface.takeDelimiterInclusive('\n') catch |err| std.debug.panic("read failed with {t}", .{err});
        if (std.mem.eql(u8, line, "\r\n")) break;
    }
    var writer = stream.writer(io, &.{});
    writer.interface.writeAll("HTTP/1.1 200 OK\r\nContent-Length: 1000000\r\nConnection: close\r\n\r\n0123456789") catch |err|
        std.debug.panic("write failed with {t}", .{err});
}
