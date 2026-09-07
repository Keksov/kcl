#!/bin/bash
# Shared symlink helpers for the tdirectory suite (review 2026-09-06, phase P3).
#
# The old probe was `ln -s <NONEXISTENT> link`. On MSYS/cygwin, `ln -s` runs in
# COPY mode by default: a link to a missing target fails outright, so the probe
# said "symlinks not supported" and 12 tests reported `PASS (skipped)` on a box
# where symlinks work perfectly well — which is exactly why createSymLink could
# stay broken (G6-05) and why `delete` on a directory link could wipe the
# target's contents unnoticed (G6-04).
#
# `MSYS=winsymlinks:native` (and `CYGWIN=` for the cygwin build) asks for a real
# NTFS symlink; the `[[ -L ]]` check afterwards is what actually proves it,
# because copy mode SUCCEEDS while producing a copy.
#
# This file is deliberately not named NNN_*.sh: the ktests runner collects
# `[0-9][0-9][0-9]_*.sh` only, so it is a library, not a test file.

# kt_make_symlink LINK TARGET -> rc 0 and LINK is a real symlink
kt_make_symlink() {
    local link="$1" target="$2"
    rm -rf -- "$link" 2>/dev/null || :
    MSYS=winsymlinks:native CYGWIN=winsymlinks:native ln -s -- "$target" "$link" 2>/dev/null || return 1
    if [[ -L "$link" ]]; then
        return 0
    fi
    # copy mode: it "succeeded" and made a copy — undo it and report failure
    rm -rf -- "$link" 2>/dev/null || :
    return 1
}

# kt_symlinks_supported DIR -> rc 0 when real symlinks can be created in DIR
kt_symlinks_supported() {
    local probe="$1/.kt_symlink_probe.$$"
    if kt_make_symlink "$probe" "$1"; then
        rm -f -- "$probe" 2>/dev/null || :
        return 0
    fi
    return 1
}
