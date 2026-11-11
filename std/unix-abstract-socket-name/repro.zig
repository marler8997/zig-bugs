const std = @import("std");
const linux = std.os.linux;

pub fn main(init: std.process.Init) !u8 {
    const io = init.io;
    const name = "\x00zig-bugs-abstract-socket-name";
    const address: std.Io.net.UnixAddress = try .init(name);
    var server = try address.listen(io, .{});
    defer server.deinit(io);

    const exact = connectRaw(name);
    const with_nul = connectRaw(name ++ "\x00");
    std.debug.print("connect to the abstract name: {t}\n", .{exact});
    std.debug.print("connect to the abstract name + NUL: {t}\n", .{with_nul});
    if (exact != .SUCCESS) {
        std.debug.print("bug: std bound the abstract name with an extra NUL byte\n", .{});
        return 1;
    }
    return 0;
}

fn connectRaw(name: []const u8) linux.E {
    const rc = linux.socket(linux.AF.UNIX, linux.SOCK.STREAM | linux.SOCK.CLOEXEC, 0);
    switch (linux.errno(rc)) {
        .SUCCESS => {},
        else => |e| std.debug.panic("socket failed with {t}", .{e}),
    }
    const fd: linux.fd_t = @intCast(rc);
    defer _ = linux.close(fd);
    var addr: linux.sockaddr.un = .{ .path = undefined };
    @memcpy(addr.path[0..name.len], name);
    const len = @offsetOf(linux.sockaddr.un, "path") + name.len;
    return linux.errno(linux.connect(fd, @ptrCast(&addr), @intCast(len)));
}
