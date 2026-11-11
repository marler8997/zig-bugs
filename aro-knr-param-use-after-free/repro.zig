//! Parses a K&R-style C function definition with aro (Zig's C frontend) and checks
//! that nothing writes to memory aro has already freed.
//!
//! `PoisonAllocator` never returns memory to the OS. It fills each freed buffer with
//! `poison` and checks the buffers again after parsing, so a write through a stale
//! pointer shows up as an exit code instead of depending on allocator timing.
const std = @import("std");
const aro = @import("aro");

/// `int (*p0)(int, ... 64 times)` grows aro's `param_buf` past its initial capacity
/// while the outer function's parameter slice is still live.
const source =
    "int f(p0, p1, p2, p3, p4, p5, p6, p7)\n" ++
    "int (*p0)(" ++ inner_params ++ ");\n" ++
    "int p1, p2, p3, p4, p5, p6, p7;\n" ++
    "{ return p1; }\n";

/// The number of parameters in p0's own list. 1 doesn't grow `param_buf` and passes.
const inner_param_count = 64;
const inner_params = blk: {
    var list: []const u8 = "int";
    for (1..inner_param_count) |_| list = list ++ ",int";
    break :blk list;
};

pub fn main(init: std.process.Init) !u8 {
    var poison_state: PoisonAllocator = .{ .backing = std.heap.page_allocator };
    const gpa = poison_state.allocator();
    const io = init.io;

    var diagnostics: aro.Diagnostics = .{ .output = .ignore };
    defer diagnostics.deinit();
    var comp = try aro.Compilation.init(.{
        .gpa = gpa,
        .arena = init.arena.allocator(),
        .io = io,
        .diagnostics = &diagnostics,
        .environ_map = init.environ_map,
    });
    defer comp.deinit();
    const main_source = try comp.addSourceFromBuffer("knr.c", source);
    const builtin_macros = try comp.generateBuiltinMacros(.no_system_defines);
    var pp = try aro.Preprocessor.init(&comp, .{ .base_file = main_source.id });
    defer pp.deinit();
    try pp.preprocessSources(.{ .main = main_source, .builtin = builtin_macros });
    var tree = try pp.parse();
    defer tree.deinit();

    if (poison_state.findWriteAfterFree()) |hit| {
        std.debug.print(
            "bug: aro wrote to a freed {d}-byte buffer (byte {d} is 0x{x:0>2}, expected 0x{x:0>2})\n",
            .{ hit.buffer_len, hit.offset, hit.value, PoisonAllocator.poison },
        );
        return 1;
    }
    std.debug.print("ok: no writes to freed memory ({d} freed buffers checked)\n", .{poison_state.freed.items.len});
    return 0;
}

const PoisonAllocator = struct {
    backing: std.mem.Allocator,
    /// Freed buffers, kept mapped and filled with `poison`.
    freed: std.ArrayList([]u8) = .empty,

    const poison = 0xaa;

    fn allocator(self: *PoisonAllocator) std.mem.Allocator {
        return .{ .ptr = self, .vtable = &.{
            .alloc = alloc,
            .resize = resize,
            .remap = std.mem.Allocator.noRemap,
            .free = free,
        } };
    }

    fn alloc(ctx: *anyopaque, len: usize, alignment: std.mem.Alignment, ret_addr: usize) ?[*]u8 {
        const self: *PoisonAllocator = @ptrCast(@alignCast(ctx));
        return self.backing.rawAlloc(len, alignment, ret_addr);
    }

    /// Only shrinking is done in place, so growing always moves the buffer and frees
    /// the old one, which is what the bug needs.
    fn resize(ctx: *anyopaque, memory: []u8, alignment: std.mem.Alignment, new_len: usize, ret_addr: usize) bool {
        _ = ctx;
        _ = alignment;
        _ = ret_addr;
        return new_len <= memory.len;
    }

    fn free(ctx: *anyopaque, memory: []u8, alignment: std.mem.Alignment, ret_addr: usize) void {
        _ = alignment;
        _ = ret_addr;
        const self: *PoisonAllocator = @ptrCast(@alignCast(ctx));
        @memset(memory, poison);
        self.freed.append(self.backing, memory) catch @panic("OOM");
    }

    const Hit = struct { buffer_len: usize, offset: usize, value: u8 };

    fn findWriteAfterFree(self: *const PoisonAllocator) ?Hit {
        for (self.freed.items) |buffer| {
            for (buffer, 0..) |byte, offset| {
                if (byte != poison) return .{ .buffer_len = buffer.len, .offset = offset, .value = byte };
            }
        }
        return null;
    }
};
