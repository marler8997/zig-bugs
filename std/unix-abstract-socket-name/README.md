# Linux abstract unix socket names get an extra NUL byte

## Zig Version

```
0.18.0-dev.146+35accc06e
```

Also reproduced on `0.17.0`. Tested on x86_64-linux; abstract socket names are Linux-only.

## Steps to Reproduce, Observed Behavior, and Expected Behavior

Save [repro.zig](repro.zig) and run:

```
zig run repro.zig
```

It listens on an abstract name with `std.Io.net.UnixAddress`, then connects with raw syscalls using the exact name and the name plus a NUL.

Observed: only the name plus a NUL connects, and the program exits 1. So other programs can't reach a zig server by its abstract name; zig programs reach each other only because both sides add the NUL.

```
connect to the abstract name: CONNREFUSED
connect to the abstract name + NUL: SUCCESS
bug: std bound the abstract name with an extra NUL byte
```

Expected: the exact name connects and the name plus a NUL doesn't:

```
connect to the abstract name: SUCCESS
connect to the abstract name + NUL: CONNREFUSED
```

## Cause

`addressUnixToPosix` in `lib/std/Io/Threaded.zig` always appends a NUL terminator and includes it in the address length. That's fine for filesystem paths, but abstract names are delimited by the length, not a terminator, so the NUL becomes part of the name.

## Workaround

Use raw syscalls (`socket`/`bind`/`connect` from `std.os.linux`) with the exact name length for abstract sockets that need to interoperate with non-zig programs.

## Fix

`fix.patch` (relative to `lib/std`): skips the NUL terminator for abstract names in `addressUnixToPosix`.

```
zig build repro-unix-abstract-socket-name   # succeeds if stock std has the bug
zig build fixed-unix-abstract-socket-name   # succeeds if fix.patch fixes it
```
