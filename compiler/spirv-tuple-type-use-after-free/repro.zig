//! Compile for spirv64-opencl with -fno-llvm. Lowering the type `Outer` takes a slice of
//! the backend's id scratch list for its 60 field types. Lowering its last field type,
//! the 200-field tuple `Inner`, grows that list, so the field type id is written through
//! a slice into the freed buffer.
const Inner = @Tuple(&@as([200]type, @splat(u32)));
const Outer = @Tuple(&(@as([59]type, @splat(u32)) ++ [1]type{Inner}));

export fn k(out: *addrspace(.global) Outer, v: u32) callconv(.kernel) void {
    out.@"0" = v;
}
