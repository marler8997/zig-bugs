# `Io.operateTimeout` times out up to 1ms early on posix

## Zig Version

```
0.17.0
```

Also reproduced on `0.18.0-dev.246+05671ced9`, and the code is unchanged on master as of 2026-10-18. Tested on x86_64-linux; the bug is in the posix `poll` path so it should affect the other posix targets too, windows is not affected.

## Steps to Reproduce, Observed Behavior, and Expected Behavior

Save [repro.zig](repro.zig) and run:

```
zig run repro.zig
```

It reads from a connected unix socket that never receives data with `io.operateTimeout` and 1, 2, 5 and 15ms timeouts, and prints the shortest time it waited before `error.Timeout`.

Observed: every timeout returns up to 1ms early, a 1ms timeout doesn't wait at all, and the program exits 1:

```
1ms timeout: shortest wait 0us
2ms timeout: shortest wait 1044us
5ms timeout: shortest wait 4056us
15ms timeout: shortest wait 14056us
bug: operateTimeout returned error.Timeout before the timeout elapsed
```

Expected: `error.Timeout` isn't returned before the timeout has elapsed:

```
1ms timeout: shortest wait 1030us
2ms timeout: shortest wait 2055us
5ms timeout: shortest wait 5055us
15ms timeout: shortest wait 15059us
```

In practice this turned a frame loop that waited for socket input with a 1ms timeout into a busy loop rendering ~56000 frames per second instead of 1000 (zigx's dbe example, [marler8997/zigx#69](https://github.com/marler8997/zigx/pull/69)).

## Cause

`batchAwaitConcurrent` in `lib/std/Io/Threaded.zig` computes the `poll` timeout from the time left until the deadline with `Duration.toMilliseconds`, which truncates. Unless the time left is an exact number of milliseconds, `poll` wakes up before the deadline, and when it returns 0 the function returns `error.Timeout` without checking the deadline. With less than 1ms left (always the case for a 1ms timeout, since some time passes between computing the deadline and calling `poll`) it calls `poll` with 0 and returns immediately.

There's a comment there saying "spurious timeouts are OK", but the docs for `Io.operateTimeout` and `Batch.awaitConcurrent` don't mention it, and the windows path waits with 100ns precision.

## Workaround

Ask for just under 1ms more than you need (e.g. `timeout_ms * std.time.ns_per_ms + std.time.ns_per_ms - 1` nanoseconds), and after `error.Timeout` check whether the time has actually elapsed.

## Fix

`fix.patch` (relative to `lib/std`): rounds the time left up to whole milliseconds instead of down when computing the `poll` timeout, so `poll` doesn't wake up before the deadline.

```
zig build repro-operate-timeout-returns-early   # succeeds if stock std has the bug
zig build fixed-operate-timeout-returns-early   # succeeds if fix.patch fixes it
```
