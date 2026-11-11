const std = @import("std");

// ntdll.dll and kernel32.dll both export RtlFillMemory, so this program should import it from both
const ntdll = struct {
    extern "ntdll" fn RtlFillMemory(dest: [*]u8, len: usize, fill: u8) callconv(.winapi) void;
};
const kernel32 = struct {
    extern "kernel32" fn RtlFillMemory(dest: [*]u8, len: usize, fill: u8) callconv(.winapi) void;
    extern "kernel32" fn GetModuleHandleA(name: ?[*:0]const u8) callconv(.winapi) ?[*]const u8;
};

fn read(comptime T: type, base: [*]const u8, offset: usize) T {
    return std.mem.readInt(T, base[offset..][0..@sizeOf(T)], .little);
}

fn cstr(base: [*]const u8, rva: usize) []const u8 {
    const ptr: [*:0]const u8 = @ptrCast(base + rva);
    return std.mem.sliceTo(ptr, 0);
}

/// Whether this exe's own import table lists `func` under `dll`.
fn imports(base: [*]const u8, dll: []const u8, func: []const u8) bool {
    const optional_header = read(u32, base, 0x3c) + 24;
    const pe32_plus = 0x20b;
    if (read(u16, base, optional_header) != pe32_plus) @panic("repro only supports 64-bit targets");
    var descriptor: usize = read(u32, base, optional_header + 120);
    while (read(u32, base, descriptor + 12) != 0) : (descriptor += 20) {
        const name_rva = read(u32, base, descriptor + 12);
        if (!std.ascii.eqlIgnoreCase(cstr(base, name_rva), dll)) continue;
        var thunk: usize = read(u32, base, descriptor);
        if (thunk == 0) @panic("import lookup table is missing");
        while (read(u64, base, thunk) != 0) : (thunk += 8) {
            const entry = read(u64, base, thunk);
            const by_ordinal = entry >> 63 != 0;
            if (by_ordinal) continue;
            const hint_size = 2;
            if (std.mem.eql(u8, cstr(base, @as(usize, @intCast(entry)) + hint_size), func)) return true;
        }
    }
    return false;
}

pub fn main() u8 {
    // call both so that neither import can be dropped
    var buf: [1]u8 = undefined;
    ntdll.RtlFillMemory(&buf, buf.len, 1);
    kernel32.RtlFillMemory(&buf, buf.len, 2);

    const base = kernel32.GetModuleHandleA(null) orelse @panic("GetModuleHandleA failed");
    const from_ntdll = imports(base, "ntdll.dll", "RtlFillMemory");
    const from_kernel32 = imports(base, "kernel32.dll", "RtlFillMemory");
    std.debug.print("RtlFillMemory imported from ntdll.dll: {}, kernel32.dll: {}\n", .{ from_ntdll, from_kernel32 });
    if (from_ntdll and from_kernel32) return 0;
    std.debug.print("bug: one of the extern declarations isn't imported from the DLL it names\n", .{});
    return 1;
}
