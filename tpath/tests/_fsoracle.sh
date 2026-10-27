#!/usr/bin/env bash
# _fsoracle.sh — a portable test oracle for stored file times and modes
# (launch L3.5-1 R6): the tfile/tdirectory/tpath tests read back what a setter
# stored without the GNU-only `stat -c`, `date -d @E` and `date -d STRING`,
# so they run on GNU, busybox and BSD userlands alike.
#
# This is NOT a test file: the runner's "/[0-9][0-9][0-9]_" filter skips it
# (no NNN_ prefix). Source it after the unit:
#     source "$SCRIPT_DIR/../../tpath/tests/_fsoracle.sh"

# fso_stat LETTER PATH -> the GNU `stat -c %LETTER` value of PATH on stdout.
# LETTER: X (access epoch), Y (write epoch), W (birth epoch), a (octal mode).
# `stat -c` (GNU, busybox), else `stat -f` with the BSD letters (FreeBSD,
# macOS). rc != 0 when neither answers.
fso_stat() {
    local f
    if stat -c "%$1" -- "$2" 2>/dev/null; then
        return 0
    fi
    case "$1" in
        X) f=%a ;;
        Y) f=%m ;;
        W) f=%B ;;
        a) f=%Lp ;;
        *) return 1 ;;
    esac
    stat -f "$f" -- "$2" 2>/dev/null
}

# fso_fmt EPOCH [utc] -> "YYYY-MM-DD HH:MM:SS" (local time; utc: in UTC).
fso_fmt() {
    if [[ "${2:-}" == "utc" ]]; then
        TZ=UTC0 printf '%(%Y-%m-%d %H:%M:%S)T\n' "$1"
    else
        printf '%(%Y-%m-%d %H:%M:%S)T\n' "$1"
    fi
}

# fso_epoch STRING [utc] -> epoch seconds of a date string (local time; utc:
# read as UTC). `date -d` (GNU, busybox), else BSD `date -j -f`, which takes
# the canonical `YYYY-MM-DD HH:MM:SS` form only.
fso_epoch() {
    local u=()
    if [[ "${2:-}" == "utc" ]]; then
        u=(-u)
    fi
    date "${u[@]}" -d "$1" +%s 2>/dev/null \
        || date "${u[@]}" -j -f '%Y-%m-%d %H:%M:%S' "$1" +%s
}
