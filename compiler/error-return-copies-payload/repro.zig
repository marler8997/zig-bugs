const std = @import("std");

const Big = struct {
    data: [64 * 1024]u8,
    len: usize,
};
const Error = error{ Zero, TooBig };

noinline fn fill(n: usize) Error!Big {
    if (n == 0) return error.Zero;
    if (n > 64 * 1024) return error.TooBig;
    var big: Big = undefined;
    @memset(big.data[0..n], 'a');
    big.len = n;
    return big;
}

pub fn main() u8 {
    // not known at compile time
    var zero: usize = 0;
    const n = @as(*volatile usize, &zero).*;

    var result: Error!Big = undefined;
    const bytes = std.mem.asBytes(&result);
    @memset(bytes, 0x55);
    result = fill(n);
    if (result) |_| return 2 else |err| if (err != error.Zero) return 2;

    // the payload of an error is undefined, there's no reason to write it
    var written: usize = 0;
    for (bytes) |byte| written += @intFromBool(byte != 0x55);
    std.debug.print("returning an error wrote {} of the {} bytes of the error union\n", .{ written, bytes.len });
    return if (written > 1024) 1 else 0;
}
