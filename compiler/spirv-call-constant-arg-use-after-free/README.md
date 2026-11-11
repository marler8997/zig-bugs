# SPIR-V backend writes through a stale slice when a call has a constant aggregate argument

## Zig Version

```
0.17.0
```

Also present on master (0.18.0-dev, `a7a26284b5`): the same code is at `src/codegen/spirv/CodeGen.zig:5504`/`5525`, compared with 8683/8704 in 0.17.0.

## Steps to Reproduce, Observed Behavior, and Expected Behavior

[repro.zig](repro.zig) passes a comptime-known `[200]u32` to a function that isn't inlined:

```zig
const row: [200]u32 = blk: { ... };

fn f(r: [200]u32) u32 {
    return r[3];
}

export fn k(out: *addrspace(.global) u32) callconv(.kernel) void {
    out.* = @call(.never_inline, f, .{row});
}
```

The bug shows reliably in a Debug compiler built with `debug_gpa`. `zig build` builds one from the 0.17.0 source tarball (the lazy `zig` dependency, about a minute and 5 GB of RAM) and runs:

```
zig build repro-spirv-call-constant-arg-use-after-free
# runs: zig-debug build-obj -fno-llvm -target spirv64-opencl -ofmt=spirv repro.zig
```

Observed: the compiler panics:

```
Compiler crash context:
(no context)
thread 53032 panic: write after free at *1e7ddaf1878
original alloc of [addr: 1e7ddaf1878, len: 132 (0x84) align: 4]:
```

Expected: it compiles. With a `[4]u32` argument, it does.

The shipped compiler compiled this repro in 20 of 20 runs. A generated variant (a 200-argument call whose last argument is a constant `[1000]u32`) made it segfault in 1 of 12 runs with fresh caches.

## Cause

`airCall` collects the argument ids like this (`src/codegen/spirv/CodeGen.zig:8683`):

```zig
const params = try cg.id_scratch.addManyAsSlice(gpa, args.len);

var n_params: usize = 0;
for (args) |arg| {
    ...
        params[n_params] = try cg.resolve(arg);
    ...
}

try cg.body.emit(gpa, .OpFunctionCall, .{
    ...
    .id_ref_3 = params[0..n_params],
});
```

`resolve` of a comptime-known array lowers it through `constant()`, which takes its own `addManyAsSlice` from `id_scratch` for the 200 elements. Once that exceeds the capacity, the list reallocates. `params` then points into the freed buffer, the assignment writes the argument's id through it, and `OpFunctionCall` is emitted from it.

This is the same pattern as [spirv-nested-array-constant-use-after-free](../spirv-nested-array-constant-use-after-free), in a different function. With only that bug's fix applied, this repro still panics.

## Workaround

Copy the constant into a `var` first, so the argument isn't comptime-known:

```zig
var copy = row;
_ = &copy;
out.* = @call(.never_inline, f, .{copy});
```

Passing `&row` instead stops with `TODO (SPIR-V): pointer to constant 'repro.row'`.

## Fix

No `fix.patch`, because the bug is in the compiler rather than std. Index `id_scratch` instead of holding a slice across the `resolve` calls. A Debug compiler with this change (plus the fixes for the other two SPIR-V bugs) compiles the repro:

```diff
--- a/src/codegen/spirv/CodeGen.zig
+++ b/src/codegen/spirv/CodeGen.zig
@@ -8680,7 +8680,9 @@
 
     const scratch_top = cg.id_scratch.items.len;
     defer cg.id_scratch.shrinkRetainingCapacity(scratch_top);
-    const params = try cg.id_scratch.addManyAsSlice(gpa, args.len);
+    // `resolve` below can grow `id_scratch` (for a constant aggregate argument), so
+    // index it instead of holding a slice across those calls.
+    _ = try cg.id_scratch.addManyAsSlice(gpa, args.len);
 
     var n_params: usize = 0;
     for (args) |arg| {
@@ -8699,9 +8701,11 @@
             // zero-sized types, the source value may not be a variable, so just
             // allocate a dummy one.
             const child_ty_id = try cg.resolveType(arg_ty.childType(zcu), .indirect);
-            params[n_params] = try cg.alloc(child_ty_id, null);
+            const param = try cg.alloc(child_ty_id, null);
+            cg.id_scratch.items[scratch_top + n_params] = param;
         } else {
-            params[n_params] = try cg.resolve(arg);
+            const param = try cg.resolve(arg);
+            cg.id_scratch.items[scratch_top + n_params] = param;
         }
         n_params += 1;
     }
@@ -8710,7 +8714,7 @@
         .id_result_type = result_type_id,
         .id_result = result_id,
         .function = callee_id,
-        .id_ref_3 = params[0..n_params],
+        .id_ref_3 = cg.id_scratch.items[scratch_top..][0..n_params],
     });
 
     if (cg.liveness.isUnused(inst) or !Type.fromInterned(return_type).hasRuntimeBits(zcu)) {
```

## Provenance

Found by the `invalidation` check in zint, a static analyzer written with an LLM (Claude), and the reproducer and this write-up were also written with Claude. Zig's contribution rules forbid LLM-found bugs and LLM-written prose, so this can't be filed upstream as it is.
