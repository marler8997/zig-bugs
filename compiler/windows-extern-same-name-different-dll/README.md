# Two extern functions with the same name in different DLLs import from only one

## Zig Version

```
0.17.0
```

Also present on 0.15.2, 0.16.0 and master (0.18.0-dev.861+1a0778dc2). `-fno-llvm` worked on 0.16.0, so that path is a regression in 0.17.0.

## Steps to Reproduce, Observed Behavior, and Expected Behavior

`ntdll.dll` and `kernel32.dll` both export `RtlFillMemory`, and these are separate exports at different addresses. [repro.zig](repro.zig) declares both, calls both, then checks its own import table:

```zig
const ntdll = struct {
    extern "ntdll" fn RtlFillMemory(dest: [*]u8, len: usize, fill: u8) callconv(.winapi) void;
};
const kernel32 = struct {
    extern "kernel32" fn RtlFillMemory(dest: [*]u8, len: usize, fill: u8) callconv(.winapi) void;
};
```

On x86_64 Windows, run:

```
zig run repro.zig
```

Observed: it compiles and links without a warning, but the program imports `RtlFillMemory` from only one DLL, so `kernel32.RtlFillMemory` calls the function in `ntdll.dll`:

```
RtlFillMemory imported from ntdll.dll: true, kernel32.dll: false
bug: one of the extern declarations isn't imported from the DLL it names
```

Which DLL wins isn't reliable. 0.15.2 built this repro with the `kernel32.dll` import instead.

Expected: each function is imported from the DLL it names, as the PE import table allows and as this repro gets from 0.16.0 with `-fno-llvm`:

```
RtlFillMemory imported from ntdll.dll: true, kernel32.dll: true
```

If that isn't possible, a compile or link error would be better than calling the wrong function.

| Version | Default | `-fno-llvm` |
| --- | --- | --- |
| 0.15.2 | one DLL | one DLL, and the exe won't load without a `compiler_rt.dll` the build doesn't produce |
| 0.16.0 | one DLL | both DLLs (correct) |
| 0.17.0 | one DLL | one DLL |
| master | one DLL | one DLL |

## Cause

I haven't traced this through the compiler. The import table shows the DLL name is lost somewhere before the imports are written. The likely reason on the default path is that the function resolves through one flat symbol, `__imp_RtlFillMemory`, and the linker stops at the first import library that defines it. That doesn't explain the 0.17.0 `-fno-llvm` regression, since 0.16.0 got it right on that path.

## Workaround

- Look the function up at runtime with `LoadLibrary` and `GetProcAddress`.
- With the default backend, give each import a unique local name using a `.def` file with `EXPORTAS` (`a_GetName EXPORTAS GetName`), build an import library from it, and declare `extern fn a_GetName`. `-fno-llvm` can't use these libraries: 0.17.0 and master stop with `TODO handle name_type NAME_EXPORTAS`, and on 0.16.0 the exe crashes.

## Fix

No patch, since the bug is in the compiler rather than std. `zig build repro-windows-extern-same-name-different-dll` succeeds while the bug is present.
