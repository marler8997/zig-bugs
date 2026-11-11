//! Compile for spirv64-opencl with -fno-llvm. Lowering the call takes a slice of the
//! backend's id scratch list for the arguments. Lowering the constant argument `row`
//! grows that list by 200 ids, so its id is written through a slice into the freed
//! buffer.
const row: [200]u32 = blk: {
    var r: [200]u32 = undefined;
    for (&r, 0..) |*x, i| x.* = @intCast(i * 7);
    break :blk r;
};

fn f(r: [200]u32) u32 {
    return r[3];
}

export fn k(out: *addrspace(.global) u32) callconv(.kernel) void {
    out.* = @call(.never_inline, f, .{row});
}
