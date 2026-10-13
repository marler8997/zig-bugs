# zig-bugs

This repo houses bugs for zig.  The purpose is to have a place to both find and report bugs without bothering the Zig core team. It can be a temporary staging area to house bugs that might be real, but, might not make sense to report upstream yet, or, that I just don't have time to make into a proper report yet.

## Layout

Each bug is a directory with:

- `README.md`: follows zig's [bug report template](https://codeberg.org/ziglang/zig/src/branch/master/.forgejo/ISSUE_TEMPLATE/bug.yml) (Zig Version; Steps to Reproduce, Observed Behavior, and Expected Behavior), so it converts directly to an upstream issue, followed by Cause, Workaround and Fix
- `repro.zig`: a program that fails (exit code or compile error) while the bug is present
- `fix.patch` (optional): a diff against `lib/std`, applied with [zig-patch](https://github.com/marler8997/zig-patch)

`zig build test` checks that every bug still reproduces with stock std and that its `fix.patch`, if it has one, fixes it. Each bug also has its own `repro-<name>` step, plus `fixed-<name>` if it has a patch (see `zig build --help`). To add a bug, add an entry to `bugs` in `build.zig` (set `has_fix_patch` to say whether it has a `fix.patch`).
