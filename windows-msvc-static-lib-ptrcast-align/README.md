# Stack traces don't compile in an aarch64-windows-msvc static library

## Zig Version

```
0.17.0
```

Also present on master (`lib/std/debug/SelfInfo/Windows.zig` as of 2026-11-02). Found cross-compiling Tuple's Windows static library for arm64 from x86_64-windows.

## Steps to Reproduce, Observed Behavior, and Expected Behavior

Save [repro.zig](repro.zig) and run:

```
zig build-lib -static repro.zig -target aarch64-windows-msvc
```

It exports a function that calls `std.debug.dumpCurrentStackTrace`. The default panic handler reaches the same code, so in practice any static library for this target hits it.

Observed:

```
lib/std/debug/SelfInfo/Windows.zig:668:9: error: @ptrCast increases pointer alignment
        @ptrCast(try si.loadNtdllProc(@tagName(proc)))
        ^~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
```

Expected: the library compiles, as it does for `x86_64-windows-msvc`, and as an executable or DLL for `aarch64-windows-msvc`.

## Cause

`load_dll_notification_procs` is true for msvc static libraries (and the C backend), so `getNtdllProc` looks up `LdrRegisterDllNotification` and friends with `loadNtdllProc`, which returns `*anyopaque`, and `@ptrCast`s it to a function pointer. `*anyopaque` has alignment 1. Function pointers are align 1 on x86_64 but 4 on aarch64, so the cast increases alignment, which `@ptrCast` alone doesn't allow.

## Workaround

Patch std with `fix.patch` (zig-patch), or don't cross-compile static libraries for aarch64-windows-msvc.

## Fix

`fix.patch` (relative to `lib/std`) adds `@alignCast`. The pointer comes from `LdrGetProcedureAddress`, so it is a real function address and the safety check can't fail.

```
zig build repro-windows-msvc-static-lib-ptrcast-align   # succeeds if stock std has the bug
zig build fixed-windows-msvc-static-lib-ptrcast-align   # succeeds if fix.patch fixes it
```
