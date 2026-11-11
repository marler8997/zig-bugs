# SPIR-V backend writes through a stale slice when lowering a nested array constant

## Zig Version

```
0.17.0
```

Also present on master (0.18.0-dev, `a7a26284b5`): the same code is at `src/codegen/spirv/CodeGen.zig:1429`/`1447`, compared with 1482/1500 in 0.17.0.

## Steps to Reproduce, Observed Behavior, and Expected Behavior

[repro.zig](repro.zig) stores a comptime `[60][100]u32` constant from a kernel:

```zig
const table: [N][M]u32 = blk: { ... };

export fn k(out: *addrspace(.global) [N][M]u32) callconv(.kernel) void {
    out.* = table;
}
```

The shipped compiler compiles this without complaint, so the bug only shows in a Debug compiler built with `debug_gpa`. `zig build` builds one from the 0.17.0 source tarball (the lazy `zig` dependency, about a minute and 5 GB of RAM) and runs:

```
zig build repro-spirv-nested-array-constant-use-after-free
# runs: zig-debug build-obj -fno-llvm -target spirv64-opencl -ofmt=spirv repro.zig
```

Observed: the compiler panics:

```
Compiler crash context:
Generating function 'repro.k'
thread 16220 panic: write after free at *1cf390a0ec8
original alloc of [addr: 1cf390a0ec8, len: 488 (0x1e8) align: 4]:
lib\std\array_list.zig:1469:28: in addManyAsSlice
free:
lib\std\array_list.zig:1377:25: in ensureTotalCapacityPrecise
                gpa.free(old_memory);
lib\std\array_list.zig:1469:28: in addManyAsSlice
```

The allocator notices the write later, when it checks the freed slot. That's why the stack trace at the panic shows an unrelated `Liveness.deinit`. The 488-byte buffer is `id_scratch` at its capacity of 122 ids.

Expected: it compiles. With `N = 2` and `M = 3` it does. A splatted constant hits the same bug through the `.repeated_elem` branch:

```zig
const table: [60][M]u32 = @splat(row); // row is a non-uniform [100]u32
```

## Cause

`constant()` lowers an array value like this (`src/codegen/spirv/CodeGen.zig:1482`):

```zig
const constituents = try cg.id_scratch.addManyAsSlice(gpa, @intCast(ty.arrayLenIncludingSentinel(zcu)));
...
.elems => |elems| {
    for (constituents, elems) |*constituent, elem| {
        constituent.* = try cg.constant(elem_ty, .fromInterned(elem), child_repr);
    }
},
.repeated_elem => |elem| {
    @memset(constituents, try cg.constant(elem_ty, .fromInterned(elem), child_repr));
},
```

When the element type is itself an array, the recursive `cg.constant` takes its own `addManyAsSlice` from `id_scratch`. Once 60 + 100 ids exceed the capacity, the list reallocates. The outer `constituents` then points into the freed buffer. The outer loop writes each row's id through it, and `constantComposite` reads all of them back from it. The `.bytes` branch holds the same slice, but `constInt` never grows `id_scratch` for integer elements, so it isn't affected today.

## Workaround

Keep large nested array constants out of SPIR-V code, for example by passing them in a buffer.

## Fix

No `fix.patch`, because the bug is in the compiler rather than std. Index `id_scratch` instead of holding a slice across the recursive calls. A Debug compiler with this change compiles both repros, and its output matches the shipped compiler's byte for byte:

```diff
--- a/src/codegen/spirv/CodeGen.zig
+++ b/src/codegen/spirv/CodeGen.zig
@@ -1479,7 +1479,10 @@
 
                 const scratch_top = cg.id_scratch.items.len;
                 defer cg.id_scratch.shrinkRetainingCapacity(scratch_top);
-                const constituents = try cg.id_scratch.addManyAsSlice(gpa, @intCast(ty.arrayLenIncludingSentinel(zcu)));
+                // `cg.constant` below can grow `id_scratch` (when the element is itself
+                // an aggregate), so index it instead of holding a slice across those calls.
+                const len: usize = @intCast(ty.arrayLenIncludingSentinel(zcu));
+                _ = try cg.id_scratch.addManyAsSlice(gpa, len);
 
                 const child_repr: Repr = switch (tag) {
                     .array_type => .indirect,
@@ -1491,22 +1494,25 @@
                     .bytes => |bytes| {
                         // TODO: This is really space inefficient, perhaps there is a better
                         // way to do it?
-                        for (constituents, bytes.toSlice(constituents.len, ip)) |*constituent, byte| {
-                            constituent.* = try cg.constInt(elem_ty, byte);
+                        for (bytes.toSlice(len, ip), scratch_top..) |byte, i| {
+                            const id = try cg.constInt(elem_ty, byte);
+                            cg.id_scratch.items[i] = id;
                         }
                     },
                     .elems => |elems| {
-                        for (constituents, elems) |*constituent, elem| {
-                            constituent.* = try cg.constant(elem_ty, .fromInterned(elem), child_repr);
+                        for (elems, scratch_top..) |elem, i| {
+                            const id = try cg.constant(elem_ty, .fromInterned(elem), child_repr);
+                            cg.id_scratch.items[i] = id;
                         }
                     },
                     .repeated_elem => |elem| {
-                        @memset(constituents, try cg.constant(elem_ty, .fromInterned(elem), child_repr));
+                        const id = try cg.constant(elem_ty, .fromInterned(elem), child_repr);
+                        @memset(cg.id_scratch.items[scratch_top..][0..len], id);
                     },
                 }
 
                 const comp_ty_id = try cg.resolveType(ty, .direct);
-                return cg.constantComposite(comp_ty_id, constituents);
+                return cg.constantComposite(comp_ty_id, cg.id_scratch.items[scratch_top..][0..len]);
             },
             .struct_type => {
                 const struct_type = zcu.typeToStruct(ty).?;
```

## Provenance

Found by the `invalidation` check in zint, a static analyzer written with an LLM (Claude), and the reproducer and this write-up were also written with Claude. Zig's contribution rules forbid LLM-found bugs and LLM-written prose, so this can't be filed upstream as it is.
