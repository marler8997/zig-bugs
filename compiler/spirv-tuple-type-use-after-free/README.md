# SPIR-V backend writes through a stale slice when lowering a tuple type with a tuple field

## Zig Version

```
0.17.0
```

Also present on master (0.18.0-dev, `a7a26284b5`): the same code is at `src/codegen/spirv/CodeGen.zig:2111`/`2117`, compared with 2060/2066 in 0.17.0.

## Steps to Reproduce, Observed Behavior, and Expected Behavior

[repro.zig](repro.zig) uses a 60-field tuple whose last field is a 200-field tuple:

```zig
const Inner = @Tuple(&@as([200]type, @splat(u32)));
const Outer = @Tuple(&(@as([59]type, @splat(u32)) ++ [1]type{Inner}));

export fn k(out: *addrspace(.global) Outer, v: u32) callconv(.kernel) void {
    out.@"0" = v;
}
```

The bug shows reliably in a Debug compiler built with `debug_gpa`. `zig build` builds one from the 0.17.0 source tarball (the lazy `zig` dependency, about a minute and 5 GB of RAM) and runs:

```
zig build repro-spirv-tuple-type-use-after-free
# runs: zig-debug build-obj -fno-llvm -target spirv64-opencl -ofmt=spirv repro.zig
```

Observed: the compiler panics:

```
Compiler crash context:
Generating function 'repro.k'
thread 58976 panic: write after free at *1f4add605b4
original alloc of [addr: 1f4add604c8, len: 488 (0x1e8) align: 4]:
```

Expected: it compiles. With 3 + 1 outer fields and a 4-field `Inner`, it does.

The shipped compiler compiled this repro in 20 of 20 runs. A generated variant of the same shape (a 60-field tuple whose last field alternates `u32`/`u16` fields) made it segfault in 2 of 23 runs with fresh caches, leaving an empty output file.

## Cause

`resolveType` lowers a tuple type like this (`src/codegen/spirv/CodeGen.zig:2060`):

```zig
const member_types = try cg.id_scratch.addManyAsSlice(gpa, tuple.values.len);

var member_index: usize = 0;
for (tuple.types.get(ip), tuple.values.get(ip)) |field_ty, field_val| {
    ...
    member_types[member_index] = try cg.resolveType(.fromInterned(field_ty), .indirect);
    member_index += 1;
}
```

When a field type is itself a tuple that hasn't been lowered yet, the recursive `resolveType` takes its own `addManyAsSlice` from `id_scratch`. Once that exceeds the capacity, the list reallocates. `member_types` then points into the freed buffer, the assignment writes the field type's id through it, and `structType` reads all of them back from it.

This is the same pattern as [spirv-nested-array-constant-use-after-free](../spirv-nested-array-constant-use-after-free), in a different function.

## Workaround

Keep big tuple types out of SPIR-V code. A `struct` type takes a different path, which doesn't use `id_scratch`.

## Fix

No `fix.patch`, because the bug is in the compiler rather than std. Index `id_scratch` instead of holding a slice across the recursive calls. A Debug compiler with this change (plus the fixes for the other two SPIR-V bugs) compiles the repro:

```diff
--- a/src/codegen/spirv/CodeGen.zig
+++ b/src/codegen/spirv/CodeGen.zig
@@ -2057,18 +2057,21 @@
                 .tuple_type => |tuple| {
                     const scratch_top = cg.id_scratch.items.len;
                     defer cg.id_scratch.shrinkRetainingCapacity(scratch_top);
-                    const member_types = try cg.id_scratch.addManyAsSlice(gpa, tuple.values.len);
+                    // `resolveType` below can grow `id_scratch` (for an aggregate field
+                    // type), so index it instead of holding a slice across those calls.
+                    _ = try cg.id_scratch.addManyAsSlice(gpa, tuple.values.len);
 
                     var member_index: usize = 0;
                     for (tuple.types.get(ip), tuple.values.get(ip)) |field_ty, field_val| {
                         if (field_val != .none or !Type.fromInterned(field_ty).hasRuntimeBits(zcu)) continue;
 
-                        member_types[member_index] = try cg.resolveType(.fromInterned(field_ty), .indirect);
+                        const member_type = try cg.resolveType(.fromInterned(field_ty), .indirect);
+                        cg.id_scratch.items[scratch_top + member_index] = member_type;
                         member_index += 1;
                     }
 
                     const result_id = try cg.structType(
-                        member_types[0..member_index],
+                        cg.id_scratch.items[scratch_top..][0..member_index],
                         null,
                         .none,
                     );
```

## Provenance

Found by the `invalidation` check in zint, a static analyzer written with an LLM (Claude), and the reproducer and this write-up were also written with Claude. Zig's contribution rules forbid LLM-found bugs and LLM-written prose, so this can't be filed upstream as it is.
