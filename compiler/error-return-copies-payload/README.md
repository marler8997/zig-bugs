# Returning an error from a function that returns `E!T` writes all of `T`, from a constant the size of `T`

## Zig Version

```
0.17.1
```

Also reproduced on `0.17.0` and `0.18.0-dev.1005+75d48dfff`. Tested on x86_64-windows and x86_64-linux, in every optimize mode.

## Steps to Reproduce, Observed Behavior, and Expected Behavior

Save [repro.zig](repro.zig) and run:

```
zig run -OReleaseSmall repro.zig
```

It has a function that returns `error{ Zero, TooBig }!Big`, where `Big` is 64KiB, and isn't inlined. The program fills the result location with `0x55`, makes the function return `error.Zero`, and counts the bytes that changed.

Observed: every byte of the error union was written, and the program exits 1:

```
returning an error wrote 65552 of the 65552 bytes of the error union
```

Expected: only the error code is written. The payload of an error is undefined, there's nothing to copy.

The bytes come from a constant: each `return error.X` in the function puts a constant the size of the whole error union in the executable. With the function above and nothing else, built with `-OReleaseSmall`:

| target         | returns `Error!Big` | writes to a `*Big`, returns `Error!void` |
|----------------|---------------------|------------------------------------------|
| x86_64-linux   | 135984 bytes        | 4840 bytes                               |
| x86_64-windows | 182272 bytes        | 51200 bytes                              |

The difference is 131072 bytes on both, two errors of 64KiB each.

This is what std's `wToPrefixedFileW` and `sliceToPrefixedFileW` do in `lib/std/Io/Threaded.zig`. They return `Wtf16ToPrefixedFileWError!WindowsPathSpace`, a 64KiB path buffer, and between them have three `return error.X` that survive optimization. A windows executable that opens a file has 192KiB of zeroes for them, and copies 64KiB when a path conversion fails. Taking them out made [marler8997/msi](https://github.com/marler8997/msi)'s ReleaseSmall exe go from 420352 to 223744 bytes.

In Debug the payload being written is expected, undefined memory is set to `0xaa`. The constants are there in Debug too.

## Cause

Not tracked down in the compiler. From the object file, each `return error.X` is a copy of the whole error union from an anonymous read-only constant, whose payload is all zeroes in release modes. It only happens when the function isn't inlined into its caller.

## Workaround

Have the function write to a pointer and return `E!void`:

```zig
fn fill(n: usize, big: *Big) Error!void
```

For std, [std-windows-pathspace.patch](https://github.com/marler8997/msi/blob/master/cli/std-windows-pathspace.patch) does that to `wToPrefixedFileW` and `sliceToPrefixedFileW`.

## Fix

None yet. Returning an error should only store the error code.

```
zig build repro-error-return-copies-payload   # succeeds if the compiler has the bug
```
