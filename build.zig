const std = @import("std");

const Bug = struct {
    name: []const u8,
    /// the reproducer fails like this with stock std
    reproduces: union(enum) {
        exit_code: u8,
        compile_error: []const u8,
    },
    only_os: ?std.Target.Os.Tag = null,
    has_fix_patch: bool,
};

const bugs = [_]Bug{
    .{ .name = "http-client-connect-unix", .reproduces = .{ .compile_error = "has no member named 'SocketError'" }, .has_fix_patch = true },
    .{ .name = "http-client-truncated-body", .reproduces = .{ .exit_code = 1 }, .has_fix_patch = true },
    .{ .name = "macos-create-file-enoent", .reproduces = .{ .exit_code = 1 }, .only_os = .macos, .has_fix_patch = false },
    .{ .name = "unix-abstract-socket-name", .reproduces = .{ .exit_code = 1 }, .only_os = .linux, .has_fix_patch = true },
    // only reproduces under wine: zig build test -Dtarget=x86_64-windows -fwine
    .{ .name = "wine-host-name-lookup-segfault", .reproduces = .{ .exit_code = 3 }, .only_os = .windows, .has_fix_patch = true },
};

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const test_step = b.step("test", "Check every bug reproduces with stock std and is fixed by its fix.patch, if it has one");
    for (bugs) |bug| {
        if (bug.only_os) |os| if (target.result.os.tag != os) continue;
        const repro_step = b.step(b.fmt("repro-{s}", .{bug.name}), "Check the bug reproduces with stock std");
        test_step.dependOn(repro_step);

        const repro_path = b.path(b.fmt("{s}/repro.zig", .{bug.name}));
        const stock = b.addExecutable(.{
            .name = bug.name,
            .root_module = b.createModule(.{ .root_source_file = repro_path, .target = target }),
        });
        switch (bug.reproduces) {
            .exit_code => |code| {
                const run = b.addRunArtifact(stock);
                run.expectExitCode(code);
                repro_step.dependOn(&run.step);
            },
            .compile_error => |message| {
                stock.expect_errors = .{ .contains = message };
                repro_step.dependOn(&stock.step);
            },
        }

        if (!bug.has_fix_patch) continue;
        const fixed_step = b.step(b.fmt("fixed-{s}", .{bug.name}), "Check fix.patch fixes the bug");
        test_step.dependOn(fixed_step);
        const patched_std = b.dependency("patch", .{
            .std_patches = &[_]std.Build.LazyPath{b.path(b.fmt("{s}/fix.patch", .{bug.name}))},
        }).module("std");
        const fixed = b.addExecutable(.{
            .name = b.fmt("{s}-fixed", .{bug.name}),
            .root_module = b.createModule(.{
                .root_source_file = repro_path,
                .target = target,
                .imports = &.{.{ .name = "std", .module = patched_std }},
            }),
        });
        const run = b.addRunArtifact(fixed);
        run.expectExitCode(0);
        fixed_step.dependOn(&run.step);
    }
}
