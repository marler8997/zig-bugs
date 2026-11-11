//! Compile for spirv64-opencl with -fno-llvm. Lowering `table` takes a slice of the
//! backend's id scratch list for the 60 rows, and lowering each 100-element row grows
//! that list, so the outer loop writes through a slice into the freed buffer.
const N = 60;
const M = 100;
const table: [N][M]u32 = blk: {
    @setEvalBranchQuota(100_000_000);
    var t: [N][M]u32 = undefined;
    for (&t, 0..) |*row, i| {
        for (row, 0..) |*x, j| x.* = @intCast(i * M + j);
    }
    break :blk t;
};

export fn k(out: *addrspace(.global) [N][M]u32) callconv(.kernel) void {
    out.* = table;
}
