# std.http.Client.connectUnix doesn't compile

## Zig Version

```
0.18.0-dev.146+35accc06e
```

Also reproduced on `0.17.0`. Tested on x86_64-linux; the bug isn't platform-specific.

## Steps to Reproduce, Observed Behavior, and Expected Behavior

Save [repro.zig](repro.zig) and run:

```
zig build-exe repro.zig
```

Observed: it fails to compile.

```
lib/std/http/Client.zig:1485:58: error: root source file struct 'posix' has no member named 'SocketError'
pub const ConnectUnixError = Allocator.Error || std.posix.SocketError || error{NameTooLong} || std.posix.ConnectError || Io.Cancelable;
                                                ~~~~~~~~~^~~~~~~~~~~~
```

Expected: it compiles, and running it connects to the unix socket server it starts and prints:

```
connectUnix connected to 'zig-bugs-connect-unix.sock'
```

## Cause

`connectUnix` wasn't updated for the `std.Io` changes:

- `ConnectUnixError` references `std.posix.SocketError`, which no longer exists.
- It calls `Io.net.connectUnixSocket`, which no longer exists.
- It initializes `Connection` fields from an older layout (`.stream`, `.tls_client`).

## Workaround

None in `std.http.Client`; HTTP over a unix socket isn't usable.

## Fix

`fix.patch` (relative to `lib/std`): rewrites `connectUnix` against the current `Io.net.UnixAddress` and `Connection.Plain` APIs.

```
zig build repro-http-client-connect-unix   # succeeds if stock std has the bug
zig build fixed-http-client-connect-unix   # succeeds if fix.patch fixes it
```
