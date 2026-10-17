# Resolving a host name segfaults under Wine

This is most likely a Wine bug rather than a zig bug: Wine doesn't populate `PEB.ReadOnlyStaticServerData`, which Windows always sets for normal processes. It's here because std could cheaply tolerate it (see Fix).

## Zig Version

```
0.17.0
```

Tested with x86_64-windows binaries running under Wine 9.0 (`wine-9.0 (Ubuntu 9.0~repack-4build3)`) on x86_64-linux.

## Steps to Reproduce, Observed Behavior, and Expected Behavior

Save [repro.zig](repro.zig) and run:

```
zig build-exe repro.zig -target x86_64-windows
wine repro.exe
```

It resolves `localhost` with `std.Io.net.HostName.lookup`.

Observed: the lookup segfaults while building the path to the hosts file:

```
Segmentation fault at address 0x8
lib/std/os/windows.zig:6025:39: 0x1400bbf2c in getSystemDirectoryWtf16Le
        peb().ReadOnlyStaticServerData.base_static_server_data_addr,
                                      ^
```

Expected: `localhost` resolves:

```
localhost resolved to [::1]:80
localhost resolved to 127.0.0.1:80
```

## Cause

`getSystemDirectoryWtf16Le` in `lib/std/os/windows.zig` reads the system directory from the CSRSS static server data that the PEB points at. `PEB.ReadOnlyStaticServerData` is declared non-optional, but Wine leaves it null, so the read faults at offset 8 of the unknown indirection struct. On Windows the hosts file lookup in `lib/std/Io/Threaded.zig` calls it for every host name, so any program that resolves a name crashes under Wine.

On Windows, the field is set when kernel32 connects the process to CSRSS during startup (`CsrClientConnectToServer`), and kernel32 terminates the process if that fails. kernel32's own `GetSystemDirectoryW` reads the same data, so std's assumption matches Windows (based on ReactOS's [kernel32 DllMain](https://doxygen.reactos.org/d3/d9e/dll_2win32_2kernel32_2client_2dllmain_8c_source.html) and [csrlib](https://doxygen.reactos.org/d1/dad/subsystems_2csr_2csrlib_2connect_8c.html), there's no official documentation for this field). Wine's `CsrClientConnectToServer` is a [stub](https://source.winehq.org/WineAPI/ntdll.html), so the field stays null.

The one case where it's likely null on real Windows is a native subsystem process (`IMAGE_SUBSYSTEM_NATIVE`, e.g. built with `--subsystem native`), which doesn't load kernel32 or connect to CSRSS. That's untested.

## Workaround

Connect to IP addresses instead of host names. Note this doesn't make networking work under Wine 9.0 though: after the lookup, std creates sockets by opening `\Device\Afd` with an AFD open packet extended attribute, which Wine doesn't appear to support, so the socket ioctls that follow fail (`SO_REUSE_UNICASTPORT` with `INVALID_DEVICE_REQUEST`, then the bind with `BAD_DEVICE_TYPE`).

## Fix

The proper fix is likely in Wine (populating `PEB.ReadOnlyStaticServerData`). Alternatively std can tolerate it being null, which would also cover native subsystem processes. `fix.patch` (relative to `lib/std`): declares `PEB.ReadOnlyStaticServerData` optional and makes `getSystemDirectoryWtf16Le` return null when it's missing. The hosts file lookup then skips the hosts file and falls through to the rest of the resolution (`localhost` is resolved by the RFC 6761 special case). The other caller, `cmdExePath` (used to run batch scripts), panics with a message instead of segfaulting.

The repro only reproduces under Wine, so run the steps for a windows target with `-fwine`:

```
zig build repro-wine-host-name-lookup-segfault -Dtarget=x86_64-windows -fwine   # succeeds if stock std has the bug
zig build fixed-wine-host-name-lookup-segfault -Dtarget=x86_64-windows -fwine   # succeeds if fix.patch fixes it
```
