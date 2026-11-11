const std = @import("std");

const thread_count = 8;
const iterations = 500;
const dir_name = "zig-bugs-create-file-enoent";

pub fn main(init: std.process.Init) !u8 {
    const io = init.io;
    const cwd = std.Io.Dir.cwd();
    try cwd.deleteTree(io, dir_name);
    const dir = try cwd.createDirPathOpen(io, dir_name, .{});
    defer {
        dir.close(io);
        cwd.deleteTree(io, dir_name) catch |err| std.debug.panic("delete '{s}' failed with {t}", .{ dir_name, err });
    }

    var shared: Shared = .{ .io = io, .dir = dir };
    var threads: [thread_count]std.Thread = undefined;
    for (&threads) |*thread| thread.* = try std.Thread.spawn(.{}, Shared.run, .{&shared});
    for (threads) |thread| thread.join();

    const failures = shared.failures.load(.monotonic);
    std.debug.print("{d} of {d} createFile calls failed\n", .{ failures, thread_count * iterations });
    if (failures == 0) return 0;
    std.debug.print("bug: createFile on a file that exists or is being created failed with FileNotFound\n", .{});
    return 1;
}

const Shared = struct {
    io: std.Io,
    dir: std.Io.Dir,
    arrived: std.atomic.Value(u32) = .init(0),
    failures: std.atomic.Value(u32) = .init(0),

    fn run(shared: *Shared) void {
        for (0..iterations) |i| {
            _ = shared.arrived.fetchAdd(1, .acq_rel);
            while (shared.arrived.load(.acquire) < (i + 1) * thread_count) std.atomic.spinLoopHint();
            var name_buf: [16]u8 = undefined;
            const name = std.fmt.bufPrint(&name_buf, "{d}", .{i}) catch unreachable;
            if (shared.dir.createFile(shared.io, name, .{ .truncate = false })) |file| {
                file.close(shared.io);
            } else |err| {
                if (shared.failures.fetchAdd(1, .monotonic) == 0)
                    std.debug.print("first failure: createFile '{s}' failed with {t}\n", .{ name, err });
            }
        }
    }
};
