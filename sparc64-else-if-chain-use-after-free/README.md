# sparc64 backend reads a freed branch-stack entry after a long else-if chain

## Zig Version

```
0.17.0
```

Also present on master (0.18.0-dev, `a7a26284b5`): the same code is at `src/codegen/sparc64/CodeGen.zig:1501`/`1519`, compared with 1499/1517 in 0.17.0.

## Steps to Reproduce, Observed Behavior, and Expected Behavior

[repro.zig](repro.zig) is a single function with a 40-deep `else if` chain:

```zig
export fn f(a: u32) u32 {
    if (a == 0) {
        return 0;
    } else if (a == 1) {
        return 3;
    // ... up to a == 39
    } else {
        return 999;
    }
}
```

The shipped compiler compiles this without complaint, so the bug only shows in a Debug compiler built with `debug_gpa`. `zig build` builds one from the 0.17.0 source tarball (the lazy `zig` dependency, about a minute and 5 GB of RAM) and runs:

```
zig build repro-sparc64-else-if-chain-use-after-free
# runs: zig-debug build-obj -fno-llvm -target sparc64-linux repro.zig
```

Observed: the compiler panics, because it uses a garbage count from freed memory:

```
Compiler crash context:
Generating function 'repro.f'
thread 39948 panic: integer overflow
lib\std\multi_array_list.zig:659:31: in capacityInBytes
            return elem_bytes * capacity;
...
src\codegen\sparc64\CodeGen.zig:1517:54: in airCondBr
    try parent_branch.inst_table.ensureUnusedCapacity(self.gpa, else_branch.inst_table.count());
src\codegen\sparc64\CodeGen.zig:560:51: in genBody
            .cond_br         => try self.airCondBr(inst),
src\codegen\sparc64\CodeGen.zig:1506:21: in airCondBr
    try self.genBody(else_body);
...
```

Expected: it compiles. A 2-deep chain does.

## Cause

`airCondBr` takes a pointer to the else branch's entry before generating the else body (`src/codegen/sparc64/CodeGen.zig:1499`):

```zig
const else_branch = self.branch_stack.addOneAssumeCapacity();
else_branch.* = .{};
...
try self.genBody(else_body);
...
try parent_branch.inst_table.ensureUnusedCapacity(self.gpa, else_branch.inst_table.count());
```

An `else if` is a nested `cond_br` in the else body, so `genBody` calls back into `airCondBr`. That call does `self.branch_stack.append(.{})`. Once the chain is deep enough for `branch_stack` to grow, the list reallocates and `else_branch` points into the freed buffer. Everything after `genBody` reads the else branch's `inst_table` through it.

## Workaround

The self-hosted sparc64 backend only runs with `-fno-llvm` or in a compiler built without LLVM. The default LLVM backend doesn't use this code. With the self-hosted backend, keep `else if` chains short.

## Fix

No `fix.patch`, because the bug is in the compiler rather than std. Take the pointer after `genBody`. Nested calls push and pop in balanced pairs, so the else branch is the last entry again. A Debug compiler with this change compiles the repro:

```diff
--- a/src/codegen/sparc64/CodeGen.zig
+++ b/src/codegen/sparc64/CodeGen.zig
@@ -1496,14 +1496,16 @@
     self.register_manager.free_registers = parent_free_registers;
 
     try self.performReloc(reloc);
-    const else_branch = self.branch_stack.addOneAssumeCapacity();
-    else_branch.* = .{};
+    self.branch_stack.addOneAssumeCapacity().* = .{};
 
     try self.ensureProcessDeathCapacity(liveness_condbr.else_deaths.len);
     for (liveness_condbr.else_deaths) |operand| {
         self.processDeath(operand);
     }
     try self.genBody(else_body);
+    // `genBody` can grow `branch_stack` (for nested conditions), so only take a pointer
+    // to the else branch now.
+    const else_branch = &self.branch_stack.items[self.branch_stack.items.len - 1];
 
     // At this point, each branch will possibly have conflicting values for where
     // each instruction is stored. They agree, however, on which instructions are alive/dead.
```

## Provenance

Found by the `invalidation` check in zint, a static analyzer written with an LLM (Claude), and the reproducer and this write-up were also written with Claude. Zig's contribution rules forbid LLM-found bugs and LLM-written prose, so this can't be filed upstream as it is.
