# std.http.Client accepts a body shorter than its Content-Length

## Zig Version

```
0.18.0-dev.146+35accc06e
```

Also reproduced on `0.17.0`. Tested on x86_64-linux; the bug isn't platform-specific.

## Steps to Reproduce, Observed Behavior, and Expected Behavior

Save [repro.zig](repro.zig) and run:

```
zig run repro.zig
```

It serves `Content-Length: 1000000` followed by 10 bytes and a close, from a thread in the same program, then fetches it with `std.http.Client.fetch`.

Observed: `fetch` succeeds with the truncated body, and the program exits 1.

```
fetch succeeded: status ok, 10 of 1000000 bytes
bug: a body shorter than its Content-Length was accepted
```

Expected: `fetch` returns an error because the body ended before `Content-Length` bytes. The same applies to reading a response body with `streamRemaining`.

Over TLS this matters more: `Connection.Tls` sets `allow_truncation_attacks = true`, relying on the HTTP content length to detect truncation, which this path doesn't do.

## Cause

`http.Reader.contentLengthStream` passes the underlying reader's `error.EndOfStream` through, and `Io.Reader.streamRemaining` treats `EndOfStream` as normal completion.

## Workaround

Use the lower-level API (`client.request`, `sendBodiless`, `receiveHead`, then `response.reader(...).streamRemaining(...)`) and compare the byte count `streamRemaining` returns with `response.head.content_length` (read it before calling `response.reader`). `fetch` doesn't expose either.

## Fix

`fix.patch` (relative to `lib/std`): adds `error.HttpContentLengthTruncated`, returned when the connection ends before `Content-Length` bytes were read (in both `contentLengthStream` and `contentLengthDiscard`). With it, the reproducer prints this and exits 0:

```
fetch failed with HttpContentLengthTruncated (expected)
```

```
zig build repro-http-client-truncated-body   # succeeds if stock std has the bug
zig build fixed-http-client-truncated-body   # succeeds if fix.patch fixes it
```
