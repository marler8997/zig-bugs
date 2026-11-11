const std = @import("std");

const Bug = struct {
    name: []const u8,
    /// the reproducer fails like this with stock std
    reproduces: union(enum) {
        exit_code: u8,
        compile_error: []const u8,
        /// A bug in the compiler itself that only shows up as a panic in a Debug compiler
        /// with the checking allocator. Builds the 0.17.0 compiler from source (the lazy
        /// `zig` dependency) that way, then compiles repro.zig with it.
        debug_compiler_panic: struct {
            args: []const []const u8,
            /// a substring of the Debug compiler's stderr
            stderr: []const u8,
        },
    },
    /// repro.zig imports `aro` (lib/compiler/aro from the zig running the build), with
    /// `aro_build_options.zig` and `aro_system_defaults.zig` from the bug's directory
    uses_aro: bool = false,
    only_os: ?std.Target.Os.Tag = null,
    /// builds for this target instead of -Dtarget, for bugs that are compile errors on one target
    target: ?std.Target.Query = null,
    /// repro.zig is a static library's root, and fix.patch fixes it if it compiles
    static_lib: bool = false,
    optimize: std.builtin.Optimize = .debug,
    has_fix_patch: bool,
};

const bugs = [_]Bug{
    .{ .name = "http-client-connect-unix", .reproduces = .{ .compile_error = "has no member named 'SocketError'" }, .has_fix_patch = true },
    .{ .name = "http-client-truncated-body", .reproduces = .{ .exit_code = 1 }, .has_fix_patch = true },
    .{ .name = "macos-create-file-enoent", .reproduces = .{ .exit_code = 1 }, .only_os = .macos, .has_fix_patch = false },
    .{ .name = "unix-abstract-socket-name", .reproduces = .{ .exit_code = 1 }, .only_os = .linux, .has_fix_patch = true },
    // the bug is in the posix poll path, tested on linux
    .{ .name = "operate-timeout-returns-early", .reproduces = .{ .exit_code = 1 }, .only_os = .linux, .has_fix_patch = true },
    // only reproduces under wine: zig build test -Dtarget=x86_64-windows -fwine
    .{ .name = "wine-host-name-lookup-segfault", .reproduces = .{ .exit_code = 3 }, .only_os = .windows, .has_fix_patch = true },
    .{ .name = "windows-extern-same-name-different-dll", .reproduces = .{ .exit_code = 1 }, .only_os = .windows, .has_fix_patch = false },
    .{
        .name = "windows-msvc-static-lib-ptrcast-align",
        .reproduces = .{ .compile_error = "@ptrCast increases pointer alignment" },
        .target = .{ .cpu_arch = .aarch64, .os_tag = .windows, .abi = .msvc },
        .static_lib = true,
        .has_fix_patch = true,
    },
    .{ .name = "aro-knr-param-use-after-free", .reproduces = .{ .exit_code = 1 }, .uses_aro = true, .has_fix_patch = false },
    .{
        .name = "spirv-nested-array-constant-use-after-free",
        .reproduces = .{ .debug_compiler_panic = .{
            .args = &.{ "-target", "spirv64-opencl", "-ofmt=spirv" },
            .stderr = "panic: write after free",
        } },
        .has_fix_patch = false,
    },
    .{
        .name = "sparc64-else-if-chain-use-after-free",
        .reproduces = .{ .debug_compiler_panic = .{
            .args = &.{ "-target", "sparc64-linux" },
            .stderr = "in airCondBr",
        } },
        .has_fix_patch = false,
    },
    .{ .name = "threaded-init-failing-allocator", .reproduces = .{ .exit_code = 1 }, .has_fix_patch = false },
    // in debug the payload is written on purpose, undefined memory is set to 0xaa
    .{ .name = "error-return-copies-payload", .reproduces = .{ .exit_code = 1 }, .optimize = .small, .has_fix_patch = false },
};

pub fn build(b: *std.Build) void {
    const default_target = b.standardTargetOptions(.{});
    const test_step = b.step("test", "Check every bug reproduces with stock std and is fixed by its fix.patch, if it has one");
    var debug_compiler: ?DebugCompiler = null;
    for (bugs) |bug| {
        const target = if (bug.target) |query| b.resolveTargetQuery(query) else default_target;
        if (bug.only_os) |os| if (target.result.os.tag != os) continue;
        const repro_step = b.step(b.fmt("repro-{s}", .{bug.name}), "Check the bug reproduces with stock std");
        test_step.dependOn(repro_step);

        const repro_path = b.path(b.fmt("{s}/repro.zig", .{bug.name}));
        if (bug.reproduces == .debug_compiler_panic) {
            const expect = bug.reproduces.debug_compiler_panic;
            if (debug_compiler == null) debug_compiler = addDebugCompiler(b) orelse continue;
            const compiler = debug_compiler.?;
            const run = b.addRunArtifact(compiler.exe);
            run.setName(b.fmt("compile {s}/repro.zig with the Debug compiler", .{bug.name}));
            run.addArgs(&.{ "build-obj", "-fno-llvm" });
            run.addArgs(expect.args);
            run.addFileArg(repro_path);
            run.addArg("--zig-lib-dir");
            run.addDirectoryArg(compiler.lib);
            _ = run.addPrefixedOutputFileArg("-femit-bin=", "repro.o");
            // fresh caches, so the Debug compiler never shares a cache with a release one
            run.addArg("--cache-dir");
            _ = run.addOutputDirectoryArg("cache");
            run.addArg("--global-cache-dir");
            _ = run.addOutputDirectoryArg("global-cache");
            run.addCheck(.{ .expect_stderr_match = expect.stderr });
            repro_step.dependOn(&run.step);
            continue;
        }
        const stock = addRepro(b, bug, bug.name, b.createModule(.{ .root_source_file = repro_path, .target = target, .optimize = bug.optimize }));
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
            .debug_compiler_panic => unreachable,
        }

        if (!bug.has_fix_patch) continue;
        const fixed_step = b.step(b.fmt("fixed-{s}", .{bug.name}), "Check fix.patch fixes the bug");
        test_step.dependOn(fixed_step);
        const patched_std = b.dependency("patch", .{
            .std_patches = &[_]std.Build.LazyPath{b.path(b.fmt("{s}/fix.patch", .{bug.name}))},
        }).module("std");
        const fixed = addRepro(b, bug, b.fmt("{s}-fixed", .{bug.name}), b.createModule(.{
            .root_source_file = repro_path,
            .target = target,
            .optimize = bug.optimize,
            .imports = &.{.{ .name = "std", .module = patched_std }},
        }));
        if (bug.static_lib) {
            fixed_step.dependOn(&fixed.step);
        } else {
            const run = b.addRunArtifact(fixed);
            run.expectExitCode(0);
            fixed_step.dependOn(&run.step);
        }
    }
}

fn addRepro(b: *std.Build, bug: Bug, name: []const u8, module: *std.Build.Module) *std.Build.Step.Compile {
    if (bug.uses_aro) addAro(b, bug, module);
    if (bug.static_lib) return b.addLibrary(.{ .linkage = .static, .name = name, .root_module = module });
    return b.addExecutable(.{ .name = name, .root_module = module });
}

fn addAro(b: *std.Build, bug: Bug, module: *std.Build.Module) void {
    const target = module.resolved_target.?;
    const aro = b.createModule(.{
        .root_source_file = std.Build.LazyPath.zig_lib.path(b, "compiler/aro/aro.zig"),
        .target = target,
    });
    const assembly_backend = b.createModule(.{
        .root_source_file = std.Build.LazyPath.zig_lib.path(b, "compiler/aro/assembly_backend.zig"),
        .target = target,
        .imports = &.{.{ .name = "aro", .module = aro }},
    });
    aro.addImport("aro", aro);
    aro.addImport("assembly_backend", assembly_backend);
    aro.addImport("build_options", b.createModule(.{ .root_source_file = b.path(b.fmt("{s}/aro_build_options.zig", .{bug.name})) }));
    aro.addImport("system_defaults", b.createModule(.{ .root_source_file = b.path(b.fmt("{s}/aro_system_defaults.zig", .{bug.name})) }));
    module.addImport("aro", aro);
}

const DebugCompiler = struct {
    exe: *std.Build.Step.Compile,
    /// the lib directory from the same source, which the compiler must be paired with
    lib: std.Build.LazyPath,
};

/// The 0.17.0 compiler built from source for the host in Debug, without LLVM and with
/// `debug_gpa`, so use-after-free in the compiler panics. null until the lazy `zig`
/// dependency has been fetched.
fn addDebugCompiler(b: *std.Build) ?DebugCompiler {
    const src = b.lazyDependency("zig", .{}) orelse return null;
    const exe = b.addExecutable(.{
        .name = "zig-debug",
        .root_module = b.createModule(.{
            .root_source_file = src.path("zig-0.17.0/src/main.zig"),
            .target = b.graph.host,
            .optimize = .Debug,
            .imports = &.{.{
                .name = "build_options",
                .module = b.createModule(.{ .root_source_file = b.path("compiler_build_options.zig") }),
            }},
        }),
    });
    exe.stack_size = 64 * 1024 * 1024;
    return .{ .exe = exe, .lib = src.path("zig-0.17.0/lib") };
}
