# aro writes through a stale slice when a K&R parameter is a function pointer

## Zig Version

```
0.17.0
```

Also present on master (0.18.0-dev, `a7a26284b5`): the code is unchanged at the same lines. aro is the C frontend behind `translate-c` and `@cImport`.

## Steps to Reproduce, Observed Behavior, and Expected Behavior

[repro.zig](repro.zig) parses this C with aro. The function definition is old style (K&R), and its first parameter is a function pointer with 64 parameters of its own:

```c
int f(p0, p1, p2, p3, p4, p5, p6, p7)
int (*p0)(int, int, ... 64 total);
int p1, p2, p3, p4, p5, p6, p7;
{ return p1; }
```

It parses with an allocator that never returns memory: it fills each freed buffer with `0xaa` and checks the buffers again after parsing.

```
zig build repro-aro-knr-param-use-after-free
```

Observed: aro writes into a buffer it already freed:

```
bug: aro wrote to a freed 144-byte buffer (byte 0 is 0x40, expected 0xaa)
```

Expected: no writes to freed memory. With `inner_param_count = 1` in repro.zig, the same program prints `ok: no writes to freed memory`.

The shipped compiler gives no error on this input, because the freed memory still holds the written values when aro reads them back. With the Debug `DebugAllocator`, the 64-parameter input panics with `write after free`. A version with 2000 parameters and a 20000-parameter function pointer segfaults at `Parser.zig:1556` (`if (new_param.name == .empty) try p.addMaybeUnusued(param_node);`).

## Cause

In `Parser.zig` (the old-style parameter path in `decl`, line 1499), `new_params` is a slice of `p.param_buf`:

```zig
const new_params = try p.param_buf.addManyAsSlice(gpa, params_len);
...
param_loop: while (true) {
    ...
    var param_d = (try p.declarator(param_decl_spec.qt, .param)) orelse { ... };
    ...
    for (func_qt.get(p.comp, .func).?.params, new_params) |param, *new_param| {
        ...
            new_param.* = .{ ... };
```

`p.declarator` parses `p0`'s own parameter list, which appends to the same `param_buf`. Once that list is big enough to make `param_buf` reallocate, `new_params` points into the freed buffer. The loop then writes each declared parameter through it. After the loop, `type_store.put` reads the parameter types back out of the freed buffer.

## Workaround

Use a prototype-style definition (`int f(int (*p0)(int, ...), int p1, ...)`) instead of a K&R one.

## Fix

No `fix.patch`, because the bug is in `lib/compiler/aro`, not `lib/std`. Keep the start index and re-slice `param_buf` after each `declarator` call. With this change applied to a copy of aro, repro.zig prints `ok`:

```diff
--- a/lib/compiler/aro/aro/Parser.zig
+++ b/lib/compiler/aro/aro/Parser.zig
@@ -1496,8 +1496,11 @@
             const func_qt = init_d.d.qt.base(p.comp).qt;
             const params_len = func_qt.get(p.comp, .func).?.params.len;
 
-            const new_params = try p.param_buf.addManyAsSlice(gpa, params_len);
-            for (new_params) |*new_param| {
+            // `declarator` below can append to `param_buf` (for a function pointer
+            // parameter's own parameters), so re-slice instead of holding a slice.
+            const new_params_start = p.param_buf.items.len;
+            _ = try p.param_buf.addManyAsSlice(gpa, params_len);
+            for (p.param_buf.items[new_params_start..][0..params_len]) |*new_param| {
                 new_param.name = .empty;
             }
 
@@ -1551,7 +1554,7 @@
                     try p.syms.defineParam(p, interned_name, param_d.qt, param_d.name, param_node);
 
                     // find and correct parameter types
-                    for (func_qt.get(p.comp, .func).?.params, new_params) |param, *new_param| {
+                    for (func_qt.get(p.comp, .func).?.params, p.param_buf.items[new_params_start..][0..params_len]) |param, *new_param| {
                         if (param.name == interned_name) {
                             if (new_param.name == .empty) try p.addMaybeUnusued(param_node);
                             new_param.* = .{
@@ -1572,6 +1575,7 @@
                 _ = try p.expectToken(.semicolon);
             }
 
+            const new_params = p.param_buf.items[new_params_start..][0..params_len];
             const func_ty = func_qt.get(p.comp, .func).?;
             for (func_ty.params, new_params) |param, *new_param| {
                 if (new_param.name == .empty) {
```

## Provenance

Found by the `invalidation` check in zint, a static analyzer written with an LLM (Claude), and the reproducer and this write-up were also written with Claude. Zig's contribution rules forbid LLM-found bugs and LLM-written prose, so this can't be filed upstream as it is.
