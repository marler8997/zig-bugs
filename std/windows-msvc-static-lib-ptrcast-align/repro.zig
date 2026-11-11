const std = @import("std");

// a static library for an msvc target, so SelfInfo loads ntdll procs at runtime
export fn dumpStack() void {
    std.debug.dumpCurrentStackTrace(.{});
}
