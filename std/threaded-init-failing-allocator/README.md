# `Io.Threaded.init` says its allocator is only used for async and concurrent, but spawning a process uses it too

## Zig Version

```
0.17.1
```

Also reproduced on `0.17.0` and `0.18.0-dev.1005+75d48dfff`. Tested on x86_64-windows and x86_64-linux.

## Steps to Reproduce, Observed Behavior, and Expected Behavior

Save [repro.zig](repro.zig) and run:

```
zig run repro.zig
```

It initializes an `Io.Threaded` with `Allocator.failing` and spawns itself as a child process. It doesn't use `async`, `concurrent`, `groupAsync` or `groupConcurrent`, which the doc comment on `init` says are the only users of the allocator:

```zig
pub fn init(
    /// Must be threadsafe. Only used for the following functions:
    /// * `Io.VTable.async`
    /// * `Io.VTable.concurrent`
    /// * `Io.VTable.groupAsync`
    /// * `Io.VTable.groupConcurrent`
    /// If these functions are avoided, then `Allocator.failing` may be passed
    /// here.
    gpa: Allocator,
    options: InitOptions,
) Threaded {
```

Observed: the spawn fails and the program exits 1:

```
bug: spawn failed with OutOfMemory
```

Expected: the child process is spawned and the program exits 0, or the docs say which other operations need the allocator.

The same goes for `Io.Threaded.init_single_threaded` and `global_single_threaded`, their allocator is `.failing`, so they can't spawn a process.

## Cause

In `lib/std/Io/Threaded.zig` these also allocate with `t.allocator`:

- `scanEnviron`, which the spawn and replace functions call to look up `PATH`
- `processReplace`, `spawnPosix`, `processSpawnDarwin` and `processSpawnWindows`, for an arena that holds the argv, environment and paths of the child
- `batchAwaitConcurrent`, for its poll storage when a batch outgrows the buffer it was given
- `fileMemoryMapCreate`, `fileMemoryMapDestroy` and `fileMemoryMapSetLength`, when a memory map falls back to a heap buffer

## Workaround

Give `Io.Threaded.init` an allocator that works if the program spawns processes, uses `Batch.awaitConcurrent` or memory maps files, even if it never uses async or concurrent. An arena backed by the page allocator is enough for spawning.

## Fix

Either list these operations in the doc comment of `init` (and on `init_single_threaded`), or have them take their memory from somewhere else. There's no `fix.patch`.

```
zig build repro-threaded-init-failing-allocator   # succeeds if stock std has the bug
```
