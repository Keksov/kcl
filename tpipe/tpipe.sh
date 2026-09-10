#!/bin/bash

# Re-source guard: the class only needs to be built once per process
# (kcl/README.md §1.4 — the guard reads the flag with `:-` so `set -u` is happy).
if [[ -n "${_TPIPE_SOURCED:-}" ]]; then
    return
fi
declare -g _TPIPE_SOURCED=1

# Locale self-heal (kcl/README.md §1.6). Records are data and are handed to the
# callback verbatim, so character semantics are part of this unit's contract:
# an empty environment means the C locale, where ${#s} counts bytes and ${s,,}
# corrupts multi-byte text.
if [[ -z "${LC_ALL:-}${LC_CTYPE:-}${LANG:-}" ]]; then
    export LC_CTYPE=C.UTF-8
fi

# Source the kklass Pascal-style DSL front-end (don't override SCRIPT_DIR).
TPIPE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$TPIPE_DIR/../../kklass/kklass_pascal.sh"

# ---------------------------------------------------------------------------
# Process-wide slots.
#
# Every sink shadows __TPIPE_STOP with a `local` of its own frame (PLAN §2.3):
# bash scopes locals DYNAMICALLY, so `TPipe.stop` called from inside a callback
# lands in the innermost sink on the call stack, whatever depth of callbacks and
# nested sinks lies between, and an inner sink can never clear an outer sink's
# pending stop. The global below exists only so that a STRAY `TPipe.stop`
# (called outside any sink) has somewhere to write and `set -u` never trips; no
# sink ever reads it.
#
# __TPIPE_RC is the raw exit status of the last `--` producer, published by
# `TPipe.lastRc`. -1 means "there was no producer of ours": before any sink has
# run, and after a sink that read stdin (read `${PIPESTATUS[0]}` right after the
# pipeline for that case).
#
# These are deliberately top-level variables, NOT `static var`s: a class with
# static variables gets the capturing static dispatcher (a funsub on 5.3, a
# scratch file on 5.2); a class WITHOUT them keeps the thin, fork-free one.
# ---------------------------------------------------------------------------
declare -g __TPIPE_STOP=0
declare -g __TPIPE_RC=-1

# TPIPE_INDEX is the 1-based ordinal of the record the callback is looking at.
# Every sink shadows it with a `local` too, for the same reason: a nested sink
# gets its own counter. The load-time global exists so that a shared callback
# which reads the ordinal is usable OUTSIDE a sink as well — without it the
# very first read aborts a `set -u` caller.
declare -g TPIPE_INDEX=0

# ---------------------------------------------------------------------------
# TPipe: run a producer and hand every record to a callback IN THIS SHELL.
#
# The bash fact this unit exists for: the right-hand side of `|` is a subshell,
# so `producer | obj.method` throws away every mutation `obj.method` makes
# (measured: n=0 after three lines, PLAN §1.1). `TPipe.each obj.method -- producer`
# reads the producer through `exec {fd}< <(...)` in the CALLING shell, so the
# callback keeps its state; the stdin form is allowed too, and refused with rc 2
# when it would run in a subshell (decision D1).
#
#     TPipe.each  [-0] [-c] CB [-- CMD ARG...]   # cb RECORD per record
#     TPipe.stop                                 # from inside a callback
#     TPipe.lastRc                               # raw rc of the last `--` producer
#
# `-0` = NUL-terminated records (find -print0), `-c` = strip ONE trailing CR.
# Flags come first; after the callback the ONLY legal word is `--`.
#
# ---- Return contract (kcl/README.md §1.1) ---------------------------------
# A DIRECT call prints NOTHING and leaves the value in RESULT; inside `$( )` the
# value is printed exactly once. Members are `static proc`, not `static func`,
# and the value goes out through tpipe._ret: kklass's THIN static dispatcher
# re-prints kk._return's value UNCONDITIONALLY, i.e. on a direct call too, so a
# `static func` would echo on every call (the same measurement tpath, tfile and
# tregex record in their headers).
#
# `each` answers RESULT = the number of records DELIVERED, rc 0 when the producer
# exited 0 or the consumer stopped the stream, rc 1 (silent) when the producer
# exited non-zero — and RESULT KEEPS the count in that case. That last part is a
# named deviation from kcl/README.md §1.2, spelled out in README.md §4.
# A malformed CALL is rc 2 + RESULT='' and runs nothing at all.
#
# ---- Internal helpers ------------------------------------------------------
# The tpipe._* helpers are NOT class members: they are plain functions, so the
# sinks share the flag parser, the guards, the pid capture and the rc bookkeeping
# WITHOUT a nested `$( )` and without double-printing under `$( )`. They read and
# write the CALLER's locals through bash's dynamic scoping — `__tpi_d`,
# `__tpi_crlf`, `__tpi_op`, `__tpi_fd`, `__tpi_pid`, `__tpi_rc` — so a sink that
# calls one MUST declare all of them first. The `__tpi_*` and `__TPIPE_*` names
# and `TPIPE_INDEX` are reserved for this unit and must never be used as an
# output-variable name (kcl/README.md §1.7).
# ---------------------------------------------------------------------------
class TPipe
    public
        # sinks
        static proc each
        static proc toArray
        static proc toList
        static proc first
        static proc count
        # control
        static proc stop
        static proc lastRc
end

# ===========================================================================
# Internal helpers (plain functions, never class members)
# ===========================================================================

# The return contract of every member (see the header note).
# $1 = value, $2 = exit status (default 0).
tpipe._ret() {
    RESULT="$1"
    if (( BASH_SUBSHELL > 0 )); then
        printf '%s' "$1"
    fi
    return "${2:-0}"
}

# P0 placeholder for the four sinks that land at P1. rc 2 + one kk.debug line,
# and RESULT is never touched, so a test can prove a member is still a stub.
# $1 = member name.
tpipe._pending() {
    kk.debug "Error: TPipe.$1: not implemented yet (kcl/tpipe/PLAN.md P1)"
    return 2
}

# Callback validator (the operand check of `each`). $1 = member, $2 = name.
# `declare -F` is the same up-front check THashSet.onNotify uses (thashset.sh:638);
# THashSet.ForEach (:409) answers rc 1 for this condition and is NOT the model —
# a callback that is not a function is a malformed CALL, not a value the caller
# may legitimately try.
#
# The `--` in `declare -F -- "$2"` is load-bearing: `declare -F "--"` treats the
# argument as the end-of-options marker and reports SUCCESS with no output
# (measured on 5.2.37 and 5.3.9), so a bare form would accept `--` as a callback.
tpipe._isFunc() {
    if declare -F -- "$2" >/dev/null 2>&1; then
        return 0
    fi
    kk.debug "Error: TPipe.$1: '$2' is not a function"
    return 2
}

# ---------------------------------------------------------------------------
# tpipe._open MEMBER VALIDATOR ARG...
#
# Parses the flags and the operand, applies the §2.5 validation order, and opens
# the producer. Writes the caller's `__tpi_d` / `__tpi_crlf` / `__tpi_op` /
# `__tpi_fd` / `__tpi_pid`. rc 0 = ready to read, rc 2 = malformed call.
#
# VALIDATOR is '' for a sink with no operand, else the name of a checker called
# as `VALIDATOR MEMBER OPERAND` that answers rc 0 or rc 2 (and prints its own
# kk.debug line).
#
# Validation order (PLAN §2.5) — every rc 2 path runs NOTHING: the producer is
# not started and stdin is not touched, which is why all of it precedes the
# `exec` below.
#   1. flags: -0, -c; anything else starting with `-` that is not `--` is rc 2
#   2. the sink's own operand
#   3. the word after the operand must be `--` or absent  (this is what catches
#      a flag written after the operand)
#   4. `--` present with an EMPTY argv after it is rc 2, not "read stdin"
#   5. `--` absent -> the D1 subshell refusal; `--` present in a subshell -> one
#      kk.debug line and carry on (D6)
#   6. only now open
# ---------------------------------------------------------------------------
tpipe._open() {
    local __tpi_m="$1" __tpi_v="$2"
    shift 2

    # 1. flags
    while (( $# > 0 )); do
        case "$1" in
            -0)  __tpi_d=''; shift ;;
            -c)  __tpi_crlf=1; shift ;;
            --)  break ;;
            -*)  kk.debug "Error: TPipe.$__tpi_m: unknown flag '$1'"
                 return 2 ;;
            *)   break ;;
        esac
    done

    # 2. the operand
    if [[ -n "$__tpi_v" ]]; then
        if (( $# == 0 )); then
            kk.debug "Error: TPipe.$__tpi_m: missing argument"
            return 2
        fi
        if [[ "$1" == "--" ]]; then
            kk.debug "Error: TPipe.$__tpi_m: missing argument before '--'"
            return 2
        fi
        if ! "$__tpi_v" "$__tpi_m" "$1"; then
            return 2
        fi
        __tpi_op="$1"
        shift
    fi

    # 3. the only word allowed after the operand is `--`
    if (( $# > 0 )) && [[ "$1" != "--" ]]; then
        kk.debug "Error: TPipe.$__tpi_m: unexpected argument '$1'; the only word allowed after the operand is '--'"
        return 2
    fi

    if (( $# > 0 )); then
        shift                                   # drop the `--`
        # 4. `--` with nothing after it is a mistake, not the stdin form
        if (( $# == 0 )); then
            kk.debug "Error: TPipe.$__tpi_m: '--' with no producer command"
            return 2
        fi
        # 5b. D6: the `--` form READS correctly in a subshell, but a callback
        #     that mutates an object (or a nameref fill) is thrown away with the
        #     subshell. That is the caller's own explicit `$( )` / `( )`, so it
        #     is allowed with one diagnostic line.
        if (( BASH_SUBSHELL > 0 )); then
            kk.debug "Warning: TPipe.$__tpi_m: running in a subshell (BASH_SUBSHELL=$BASH_SUBSHELL); records are delivered, but every mutation the callback makes is lost when the subshell exits"
        fi
        # 6. open. The producer argv is run as "$@" — no eval, no word splitting
        #    of a command string, ever. The process substitution inherits the
        #    CALLER's stdin, so `-- grep needle` reads whatever the caller reads.
        exec {__tpi_fd}< <( "$@" )
        __tpi_pid=$!
        return 0
    fi

    # 5a. D1: the stdin form only works when the member runs in the calling
    #     shell. In a subshell (the RHS of a pipe without lastpipe, `$( )`,
    #     `( )`) every mutation the callback makes is lost, so refuse instead of
    #     losing state silently.
    if (( BASH_SUBSHELL > 0 )); then
        kk.debug "Error: TPipe.$__tpi_m: stdin form ran in a subshell (BASH_SUBSHELL=$BASH_SUBSHELL); use \`TPipe.$__tpi_m CB -- CMD ...\`, or \`shopt -s lastpipe\` at the top of a NON-interactive script (lastpipe is inert while job control is on)"
        return 2
    fi
    __tpi_fd=0
    __tpi_pid=''
    return 0
}

# ---------------------------------------------------------------------------
# tpipe._close [STOPPED]
#
# STOPPED is 1 when the CONSUMER ended the stream (TPipe.stop). Sets the caller's
# `__tpi_rc` (the member's exit status) and the process-wide `__TPIPE_RC` (the
# producer's raw rc, published by TPipe.lastRc). Always rc 0.
#
#   * `exec {fd}<&-` comes FIRST and never after the wait: a producer blocked on
#     a full pipe only gets its SIGPIPE once the read end is gone, and `wait`
#     would hang.
#   * on the stop path the close is followed by `kill -TERM`: a producer that
#     ignores SIGPIPE and then stops writing (`trap '' PIPE; echo a; sleep 8`)
#     otherwise blocks `wait` for its whole remaining life — 8.1 s measured,
#     ~50 ms with the kill. `kill -- -"$pid"` is wrong: a process substitution
#     is not a process-group leader.
#   * `wait` is the one statement here that is EXPECTED to be non-zero, so it is
#     always `__TPIPE_RC=0; wait "$pid" || __TPIPE_RC=$?` — a bare `wait` aborts
#     a `set -e` caller.
#   * the member's rc is 0 whenever the consumer stopped the stream: that is the
#     consumer's success, not the producer's failure (the producer's own 141/143
#     stays visible through TPipe.lastRc).
# ---------------------------------------------------------------------------
tpipe._close() {
    if [[ -z "$__tpi_pid" ]]; then          # stdin: nothing of ours to close
        __TPIPE_RC=-1
        __tpi_rc=0
        return 0
    fi
    exec {__tpi_fd}<&-
    if [[ "${1:-0}" != "0" ]]; then
        kill -TERM "$__tpi_pid" 2>/dev/null || :
    fi
    __TPIPE_RC=0
    wait "$__tpi_pid" || __TPIPE_RC=$?
    if [[ "${1:-0}" != "0" || "$__TPIPE_RC" == "0" ]]; then
        __tpi_rc=0
    else
        __tpi_rc=1
    fi
    return 0
}

# ===========================================================================
# Members
# ===========================================================================

TPipe.each() {
    # The frame-local stop slot and record ordinal (PLAN §2.3, §1.3). Both are
    # `local` HERE so that a nested sink started from inside the callback gets
    # its own pair and neither disturbs ours.
    local __TPIPE_STOP=0 TPIPE_INDEX=0
    local __tpi_d=$'\n' __tpi_crlf='' __tpi_op='' __tpi_fd='' __tpi_pid='' \
          __tpi_rc=0 __tpi_cb='' __tpi_line='' __tpi_n=0
    if tpipe._open each tpipe._isFunc "$@"; then
        __tpi_cb="$__tpi_op"
        # `IFS= read -r` and the `|| [[ -n ]]` tail: leading/trailing blanks and
        # backslashes survive verbatim, a last record without a terminator is
        # delivered, and the tail cannot run away because `read` clears the
        # variable at EOF. The delimiter is passed as a VALUE: an expansion-built
        # option word (`${d:+-d ''}`) is split by the CALLER's IFS, which with
        # IFS=':' silently turned the NUL delimiter into a space (measured).
        # Zero forks per record; the only fork per call is the producer.
        while IFS= read -r -d "$__tpi_d" -u "$__tpi_fd" __tpi_line || [[ -n "$__tpi_line" ]]; do
            if [[ -n "$__tpi_crlf" ]]; then
                __tpi_line="${__tpi_line%$'\r'}"
            fi
            __tpi_n=$(( __tpi_n + 1 ))
            TPIPE_INDEX=$__tpi_n
            # The callback runs in THIS frame: it sees and may mutate its own
            # object, globals and the caller's arrays. Its exit status is
            # DISCARDED (D2) — a predicate callback legitimately answers 1 and
            # must not tear the stream down.
            "$__tpi_cb" "$__tpi_line" || :
            if (( __TPIPE_STOP )); then
                break
            fi
        done
        tpipe._close "$__TPIPE_STOP"
        tpipe._ret "$__tpi_n" "$__tpi_rc"
    else
        tpipe._ret "" 2
    fi
}

TPipe.toArray() {
    tpipe._pending toArray
}

TPipe.toList() {
    tpipe._pending toList
}

TPipe.first() {
    tpipe._pending first
}

TPipe.count() {
    tpipe._pending count
}

TPipe.stop() {
    # Called from inside a callback: end this sink after the current record.
    # RESULT is deliberately left untouched — the callback may be mid-computation
    # — so this member does NOT go through tpipe._ret.
    __TPIPE_STOP=1
    return 0
}

TPipe.lastRc() {
    tpipe._ret "$__TPIPE_RC" 0
}

# Finalize: extract the bodies above into the `TPipe` class and generate the
# thin static dispatchers (see the header note).
build TPipe
