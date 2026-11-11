//! The `build_options` module for the Zig 0.17.0 compiler that `build.zig` builds from
//! source for `debug_compiler_panic` bugs: no LLVM, and `debug_gpa` so the compiler uses
//! the checking allocator that reports use-after-free.
pub const mem_leak_frames: u32 = 4;
pub const have_llvm: bool = false;
pub const llvm_has_m68k: bool = false;
pub const llvm_has_csky: bool = false;
pub const llvm_has_arc: bool = false;
pub const llvm_has_xtensa: bool = false;
pub const debug_gpa: bool = true;
pub const @"src.dev.Env" = enum(u5) {
    bootstrap = 0,
    core = 1,
    full = 2,
    c_source = 3,
    ast_gen = 4,
    sema = 5,
    @"aarch64-linux" = 6,
    cbe = 7,
    llvm = 8,
    @"loongarch-linux" = 9,
    @"powerpc-linux" = 10,
    @"riscv64-linux" = 11,
    spirv = 12,
    spork8 = 13,
    wasm = 14,
    @"x86_64-linux" = 15,
    @"x86_64-windows" = 16,
};
pub const dev: @"src.dev.Env" = .full;
pub const @"build.IoMode" = enum(u1) {
    threaded = 0,
    evented = 1,
};
pub const io_mode: @"build.IoMode" = .threaded;
pub const @"build.ValueInterpretMode" = enum(u1) {
    direct = 0,
    by_name = 1,
};
pub const value_interpret_mode: @"build.ValueInterpretMode" = .direct;
pub const version: [:0]const u8 = "0.17.0";
pub const semver: @import("std").SemanticVersion = .{
    .major = 0,
    .minor = 17,
    .patch = 0,
    .pre = null,
    .build = null,
};
pub const enable_debug_extensions: bool = true;
pub const @"log.Level" = enum(u2) {
    err = 0,
    warn = 1,
    info = 2,
    debug = 3,
};
pub const log_level: @"log.Level" = .debug;
pub const enable_tracy: bool = false;
pub const enable_tracy_callstack: bool = false;
pub const enable_tracy_allocation: bool = false;
pub const tracy_callstack_depth: u32 = 6;
pub const value_tracing: bool = false;
pub const enable_logging: bool = false;
