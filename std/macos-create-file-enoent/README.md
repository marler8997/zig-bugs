# macOS: concurrent Dir.createFile of the same new file fails with FileNotFound

## Zig Version

```
0.18.0-dev.146+35accc06e
```

Also reproduced on `0.17.0`. macOS only, tested on macOS 26.7 (25G229) arm64. The same reproducer never fails on Linux.

## Steps to Reproduce, Observed Behavior, and Expected Behavior

Save [repro.zig](repro.zig) and run:

```
zig run repro.zig
```

8 threads repeatedly call `createFile(name, .{ .truncate = false })` on the same new file at the same time, 500 different files in all.

Observed: most calls fail with `error.FileNotFound`, even though the directory exists and the file either exists or is being created. The program exits 1. The failure count varies from run to run, it was between 3063 and 3350 in six runs:

```
first failure: createFile '0' failed with FileNotFound
3102 of 4000 createFile calls failed
bug: createFile on a file that exists or is being created failed with FileNotFound
```

Expected: every call creates or opens the file:

```
0 of 4000 createFile calls failed
```

The same happens across processes; anyzig hit it in CI when two processes created the same install lock file at once.

## Cause

The macOS kernel: when several threads or processes `open` the same nonexistent file with `O_CREAT` (and not `O_EXCL`) at once, some get `ENOENT`, which std maps to `error.FileNotFound`. The parent directory was confirmed to still be linked, with the same inode, when it happened.

## Workaround

Create with `.exclusive = true` (`O_EXCL`). Exactly one caller creates the file and the others get `error.PathAlreadyExists`, then open it with `openFile` (no `O_CREAT`). This only holds if the file is never deleted, otherwise that `openFile` can fail with `FileNotFound` too.

## Fix

None. The bug is in macOS; whether std should work around it in `createFile` is an open question.

```
zig build repro-macos-create-file-enoent   # succeeds if the bug reproduces (macOS only)
```
