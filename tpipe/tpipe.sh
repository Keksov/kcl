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

# __TPIPE_QUIET — the CALLER's opt-out from the `$( )` echo (README §7).
#
# `tpipe._ret` prints RESULT whenever `BASH_SUBSHELL > 0`, which is right for a
# caller that IS the answer (`n=$(TPipe.count -- cmd)`). It is wrong for a
# COMPOSING caller: a kklass member that runs a sink and then answers through
# its own return channel gets the value printed TWICE — measured while tutil P1
# was written, `$(u.count)` read back as `22`. A caller in that position
# declares `local __TPIPE_QUIET=1` in its own frame; bash's DYNAMIC scoping
# makes the setting reach this unit's members and end with the frame, exactly as
# `local __TPIPE_STOP` does for `TPipe.stop`.
#
# kklass's `__kk_return_silent` cannot be borrowed: the THIN static dispatcher
# sets it to 1 for EVERY static body (kklass.sh:~990), so a static member could
# never tell "quiet" from "loud".
#
# It silences `tpipe._ret` and nothing else — a callback's own stdout, a
# `toList` target's `.Add`, and the producer's stderr all pass through
# untouched. The load-time global exists so that a read under `set -u` outside
# any sink is safe.
declare -g __TPIPE_QUIET=0

# TPIPE_INDEX is the 1-based ordinal of the record the callback is looking at.
# Every sink shadows it with a `local` too, for the same reason: a nested sink
# gets its own counter. The load-time global exists so that a shared callback
# which reads the ordinal is usable OUTSIDE a sink as well — without it the
# very first read aborts a `set -u` caller.
declare -g TPIPE_INDEX=0

# The `-c` strip pattern, as a VALUE — never as a literal `$'\r'` in a member
# body.
#
# P1 finding, measured on 5.2.37 and 5.3.9: `build` extracts every member body
# with `declare -f` and re-creates it with `eval`. `declare -f` prints
# `${x%$'\r'}` as `${x%'<CR>'}` with a RAW carriage return inside the quotes, and
# the re-parse of that text DROPS the CR — the rebuilt body reads `${x%''}`,
# which strips nothing at all and is silent about it. So the pattern lives in a
# variable, whose value survives because it is never re-parsed:
#
#     __tpi_line="${__tpi_line%"$__TPIPE_CR"}"
#
# The double quotes around the expansion keep it a LITERAL match, not a glob.
# It strips EXACTLY one trailing CR (`x\r\r` -> `x\r`); `tr` would be a fork per
# call and would also eat CRs inside the record.
declare -g __TPIPE_CR
printf -v __TPIPE_CR '\r'

# ---------------------------------------------------------------------------
# TPipe: run a producer and hand every record to a callback IN THIS SHELL.
#
# The bash fact this unit exists for: the right-hand side of `|` is a subshell,
# so `producer | obj.method` throws away every mutation `obj.method` makes
# (measured: n=0 after three lines, PLAN §1.1). `TPipe.each obj.method -- producer`
# reads the producer through `exec {fd}< <(...)` in the CALLING shell, so the
# callback keeps its state; the stdin form is allowed everywhere too, including
# the RHS of a pipe without `lastpipe` (D6 final Q1 — NOTHING is refused because
# of a subshell; when the loss is certain, ONE `kk.warn` line says so).
#
#     TPipe.each    [-0] [-c] [-s] CB   [-- CMD ARG...]  # cb RECORD per record
#     TPipe.toArray [-0] [-c] [-s] NAME [-- CMD ARG...]  # REPLACE a caller array
#     TPipe.toList  [-0] [-c] [-s] INST [-- CMD ARG...]  # INST.Add RECORD per record
#     TPipe.first   [-0] [-c] [-s]      [-- CMD ARG...]  # RESULT = first record
#     TPipe.count   [-0] [-c] [-s]      [-- CMD ARG...]  # RESULT = number of records
#     TPipe.stop                                         # from inside a callback
#     TPipe.lastRc                                       # raw rc of the last `--` producer
#
# `-0` = NUL-terminated records (find -print0), `-c` = strip ONE trailing CR,
# `-s` = "the subshell scope is intended", which silences the D6 warning for
# THIS call (inert on `first`/`count`, which never warn). `KK_SUBSHELL_OK=1` is
# the same switch as a dynamically scoped variable, for a whole block or through
# a wrapper. Flags come first; after the sink's operand the ONLY legal word is
# `--`. `first` and `count` take no operand, so for them the first non-flag word
# must already be `--`.
#
# ---- Return contract (kcl/README.md §1.1) ---------------------------------
# A DIRECT call prints NOTHING and leaves the value in RESULT; inside `$( )` the
# value is printed exactly once. Members are `static proc`, not `static func`,
# and the value goes out through tpipe._ret: kklass's THIN static dispatcher
# re-prints kk._return's value UNCONDITIONALLY, i.e. on a direct call too, so a
# `static func` would echo on every call (the same measurement tpath, tfile and
# tregex record in their headers).
#
# `each` is the ONE member that never prints (D6 final Q7): its stdout belongs
# to the CALLBACK, so `x=$(TPipe.each fmt -- cmd)` is exactly what `fmt` wrote
# and `TPipe.each fmt -- cmd | sort` sorts exactly that. It answers `RESULT=N;
# return RC` directly and never goes through tpipe._ret; a DIRECT call still
# reads the count from RESULT. (Before Q7 the count was appended to the
# callback's bytes in both positions.)
#
# `each`, `toArray`, `toList` and `count` answer RESULT = the number of records
# delivered / stored / offered / counted, rc 0 when the producer exited 0 or the
# consumer stopped the stream, rc 1 (silent) when the producer exited non-zero —
# and RESULT KEEPS the count in that case, with `toArray`'s array and `toList`'s
# list holding everything read before the failure. That last part is a named
# deviation from kcl/README.md §1.2, spelled out in README.md §4. `first` is the
# odd one out: RESULT is the record itself, rc 0 when a record was read (the
# producer's rc is irrelevant then — the consumer stopped it on purpose) and
# rc 1 with RESULT='' when the producer had nothing.
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
#
# RESULT is set unconditionally; the ECHO is what `__TPIPE_QUIET` turns off, so
# a composing caller still reads the value the normal way (see the note at the
# declaration of `__TPIPE_QUIET`). The `:-0` keeps `set -u` happy even if the
# load-time global was unset by hand.
tpipe._ret() {
    RESULT="$1"
    if (( BASH_SUBSHELL > 0 )) && [[ "${__TPIPE_QUIET:-0}" != 1 ]]; then
        printf '%s' "$1"
    fi
    return "${2:-0}"
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

# List validator (the operand check of `toList`). $1 = member, $2 = instance.
#
# DUCK-TYPED on purpose: anything with an `.Add` wrapper qualifies — a
# TStringList, a TList, a THashSet, a user class — and this unit sources none of
# them. `.Add`'s own exit status is IGNORED by the sink (THashSet.Add answers 1
# for a duplicate, TStringList.Add under `dupError` too), so the ONLY thing that
# can be checked up front is that the member exists at all.
#
# `declare -F --` for the same reason as above.
tpipe._isAddable() {
    if declare -F -- "$2.Add" >/dev/null 2>&1; then
        return 0
    fi
    kk.debug "Error: TPipe.$1: '$2' has no .Add member"
    return 2
}

# Is the named variable one that `mapfile` cannot fill CORRECTLY? Three
# attributes are refused up front (PLAN §2.4 toArray, F15):
#
#   A  an ASSOCIATIVE array — "mapfile: NAME: not an indexed array", rc 1;
#   r  a READONLY variable of any shape — "NAME: readonly variable", rc 1;
#   i  an INTEGER-attributed variable — this one is worse than a diagnostic:
#      mapfile SUCCEEDS (rc 0, silent) and every record is evaluated
#      arithmetically on the way in, so `declare -i v=0` + two records `abc`,
#      `def` yields `declare -ai v=([0]="0" [1]="0")`. Records are DATA; a
#      target that silently rewrites them is a malformed call, not a value the
#      caller may legitimately try (measured on 5.2.37 and 5.3.9).
#
# The first two make bash print a diagnostic, which a kcl unit must never emit;
# the third corrupts in silence. An existing SCALAR is fine: mapfile converts it
# to an indexed array (measured on both bashes), as does an unset name and a
# declared-but-never-assigned `declare -a`.
#
# `${ref@a}` aborts under `set -u` whenever the target has no value yet, and
# `declare -a out=()` — the normal way to prepare a receiving array — is exactly
# that shape; `local -` makes `$-` local to THIS function so the option can be
# switched off without a fork and without leaking to the caller (the thashset
# TSet._isAssoc shape, thashset.sh:242).
#
# rc 0 = unusable target, rc 1 = fine.
tpipe._isBadTarget() {
    local -
    set +u
    local -n __tpi_probe="$1" 2>/dev/null || return 0
    case "${__tpi_probe@a}" in
        *A*|*i*|*r*) return 0 ;;
    esac
    return 1
}

# Output-array validator (the operand check of `toArray`). $1 = member, $2 = name.
#
# The §1.7 rule first (identifier shape, the kklass reserved set, the
# `__kk_`/`__KK_` space and this unit's own `__tpi_` / `__TPIPE_` locals — bash
# scopes locals DYNAMICALLY, so a name equal to one of them would bind the
# caller's array to our scratch), then the mapfile-can-fill-it check.
#
# `TPIPE_INDEX` is passed as a third reserved prefix even though PLAN §2.5 spells
# the call as `kk._outName NAME __tpi_ __TPIPE_`: every sink shadows
# `TPIPE_INDEX` with a `local` of its own frame (PLAN §6), so a nameref bound to
# that name would fill the SINK's local and the caller would see nothing at all
# while RESULT still reported the count — the silent-loss class `kk._outName`
# exists to prevent (measured on both bashes). README.md §7 already lists the
# name as reserved.
tpipe._isOutArr() {
    if ! kk._outName "$2" __tpi_ __TPIPE_ TPIPE_INDEX; then
        kk.debug "Error: TPipe.$1: bad output array name '$2'"
        return 2
    fi
    if tpipe._isBadTarget "$2"; then
        kk.debug "Error: TPipe.$1: '$2' is an associative array, integer-attributed or readonly and cannot receive the records"
        return 2
    fi
    return 0
}

# ---------------------------------------------------------------------------
# tpipe._subshellWarn MEMBER OPERAND FORM   — the D6-final warning rule.
#
# FORM is `stdin` (no `--`) or `cmd` (`--` present); the caller has already
# established that `BASH_SUBSHELL > 0` and that neither `-s` nor
# `KK_SUBSHELL_OK=1` was given. Always rc 0: a warning never changes the
# member's answer.
#
# ---- WHEN (D6 final Q2: only when the loss is CERTAIN) --------------------
#   toArray  the nameref fill cannot reach the caller           -> always
#   toList   `INST.Add` mutates a list the caller will not see  -> always
#   each     depends on the CALLBACK:
#              * an INSTANCE member (`r.onLine`) mutates an object that dies
#                with the subshell                              -> warn
#              * a plain function or a STATIC member may print, count into a
#                file, or answer through the producer's own stdout — all of
#                which work perfectly well in a subshell        -> silent
#   first    RESULT is the answer and the caller reads it       -> never
#   count    likewise                                           -> never
#
# The callback kind is decided by `[[ $cb == *.* ]] && declare -p "${cb%%.*}_data"`
# — a kklass instance wrapper is `inst.member` with a live `${inst}_data` array,
# while a static member (`Class.member`) has no `_data` (measured on both
# bashes: `TPipe.count` as a callback name is NOT reported). `declare -p` is a
# builtin, so the probe costs no fork, and it runs ONLY on the warning path.
#
# ---- WHICH LINE (two templates, keyed on the FORM) -----------------------
# The stdin form is almost always the RHS of a pipe, where `lastpipe` or the
# `--` form is the fix; the `--` form in a subshell is almost always an explicit
# `$( )`, where the only fix is to move the call out. Both templates are pinned
# byte-exact by PLAN §2.4 and by tests/004_Contract.sh §4.
# ---------------------------------------------------------------------------
tpipe._subshellWarn() {
    local __tpi_wm="$1" __tpi_wo="$2" __tpi_wf="$3" __tpi_wt='' __tpi_wl=''
    case "$__tpi_wm" in
        each)
            if [[ "$__tpi_wo" != *.* ]]; then
                return 0
            fi
            if ! declare -p "${__tpi_wo%%.*}_data" >/dev/null 2>&1; then
                return 0
            fi
            __tpi_wt="the instance member $__tpi_wo runs"
            __tpi_wl=' CB'
            ;;
        toArray)
            __tpi_wt="the array $__tpi_wo is filled"
            __tpi_wl=' NAME'
            ;;
        toList)
            __tpi_wt="$__tpi_wo.Add runs"
            __tpi_wl=' INST'
            ;;
        *)  return 0 ;;
    esac
    if [[ "$__tpi_wf" == "stdin" ]]; then
        kk.warn "Warning: TPipe.$__tpi_wm: $__tpi_wt inside a subshell (BASH_SUBSHELL=$BASH_SUBSHELL) — the calling shell will not see it; in a pipeline use \`shopt -s lastpipe\` (non-interactive scripts) or the \`TPipe.$__tpi_wm$__tpi_wl -- CMD ...\` form at top level; if the subshell scope is intended, pass -s or set KK_SUBSHELL_OK=1"
    else
        kk.warn "Warning: TPipe.$__tpi_wm: $__tpi_wt inside a subshell (BASH_SUBSHELL=$BASH_SUBSHELL) — the calling shell will not see it; move the call out of \$( ) / ( ); if the subshell scope is intended, pass -s or set KK_SUBSHELL_OK=1"
    fi
    return 0
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
#   1. flags: -0, -c, -s; anything else starting with `-` that is not `--` is rc 2
#   2. the sink's own operand
#   3. the word after the operand must be `--` or absent  (this is what catches
#      a flag written after the operand)
#   4. `--` present with an EMPTY argv after it is rc 2, not "read stdin"
#   5. BASH_SUBSHELL > 0 -> the D6-final warning rule (tpipe._subshellWarn), in
#      BOTH forms, unless `-s` or `KK_SUBSHELL_OK=1`. Nothing is refused and
#      neither rc nor RESULT changes; an rc 2 path never gets this far, so a
#      malformed call never warns.
#   6. only now open
# ---------------------------------------------------------------------------
tpipe._open() {
    local __tpi_m="$1" __tpi_v="$2" __tpi_sok=0 __tpi_form=''
    shift 2

    # 1. flags
    while (( $# > 0 )); do
        case "$1" in
            -0)  __tpi_d=''; shift ;;
            -c)  __tpi_crlf=1; shift ;;
            -s)  __tpi_sok=1; shift ;;
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
        __tpi_form=cmd
    else
        __tpi_form=stdin
    fi

    # 5. D6 final (owner ruling 2026-09-15). NOTHING is refused because of a
    #    subshell any more — the old D1 rc 2 for the stdin form is gone, and so
    #    is the D6 debug-only line for the `--` form. Both forms now take the
    #    same rule: when the sink runs with BASH_SUBSHELL > 0 and the loss is
    #    CERTAIN, one `kk.warn` line goes to stderr and the call proceeds with
    #    exactly the rc and RESULT of the contract table.
    #
    #    Two ways to say "the subshell scope is intended", both per call and
    #    neither changing anything but the warning: the `-s` flag (sugar) and
    #    the dynamically scoped `KK_SUBSHELL_OK=1` (the primitive — it survives
    #    a wrapper, so `KK_SUBSHELL_OK=1 g.each r.onLine` reaches here through
    #    TGrep and TUtil without a line of their code). The `KK_` prefix is
    #    kcl-wide on purpose: any other callback-taking member may honour it.
    #
    #    This is the LAST thing before the producer starts, so an rc 2 path can
    #    never warn, and it is done once per call — there is no de-duplication
    #    across calls (D6 final Q5).
    if (( BASH_SUBSHELL > 0 )) && [[ "$__tpi_sok" != "1" && "${KK_SUBSHELL_OK:-}" != "1" ]]; then
        tpipe._subshellWarn "$__tpi_m" "$__tpi_op" "$__tpi_form"
    fi

    # 6. open. The producer argv is run as "$@" — no eval, no word splitting of
    #    a command string, ever. The process substitution inherits the CALLER's
    #    stdin, so `-- grep needle` reads whatever the caller reads. With no
    #    `--` the producer IS the caller's stdin and there is nothing of ours to
    #    open or to close.
    if [[ "$__tpi_form" == "cmd" ]]; then
        exec {__tpi_fd}< <( "$@" )
        __tpi_pid=$!
        return 0
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
                __tpi_line="${__tpi_line%"$__TPIPE_CR"}"
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
        # D6 final Q7: `each` NEVER prints. Its stdout belongs to the callback,
        # so `x=$(TPipe.each fmt -- cmd)` must be exactly what `fmt` wrote and
        # `TPipe.each fmt -- cmd | sort` must sort exactly that — while
        # tpipe._ret would have appended the record count in both positions.
        # RESULT is still set for the direct call, which is how the count is
        # read; this is the one member of the unit that answers `RESULT=V;
        # return N` instead of going through the unit's return helper, and the
        # reason is spelled out in the header note and in README §4.
        RESULT="$__tpi_n"
        return "$__tpi_rc"
    else
        RESULT=""
        return 2
    fi
}

TPipe.toArray() {
    # The §6 frame invariant: every sink owns its stop slot and record ordinal.
    # No callback runs in THIS frame (mapfile is a builtin), so nothing can set
    # them — they are declared so that a nested sink started from a NEIGHBOURING
    # frame can never see ours, and so that the reserved-name rule of
    # tpipe._isOutArr is true by construction.
    local __TPIPE_STOP=0 TPIPE_INDEX=0
    local __tpi_d=$'\n' __tpi_crlf='' __tpi_op='' __tpi_fd='' __tpi_pid='' \
          __tpi_rc=0 __tpi_i=0 __tpi_n=0
    if tpipe._open toArray tpipe._isOutArr "$@"; then
        # The nameref is bound only AFTER the name passed kk._outName AND the
        # assoc/readonly check inside tpipe._open (PLAN §2.4): `local -n` on a
        # bad name prints a bash diagnostic and still returns 0.
        local -n __tpi_out="$__tpi_op"
        # mapfile CLEARS the array first, so the caller's array is REPLACED, not
        # appended to. The delimiter is passed as a VALUE for the same reason the
        # reader loop does it (an expansion-built `-d ''` is split by the
        # CALLER's IFS); `-d $'\n'` is identical to the default (measured).
        # Zero per-record overhead: one builtin call for the whole stream.
        mapfile -t -d "$__tpi_d" -u "$__tpi_fd" __tpi_out
        __tpi_n=${#__tpi_out[@]}
        # -c is one extra pass over the array: the strip takes EXACTLY one
        # trailing CR (verified `x\r\r` -> `x\r`), and never forks. The pattern
        # comes from __TPIPE_CR, not from an inline `$'\r'` — see the note at
        # its declaration.
        if [[ -n "$__tpi_crlf" ]]; then
            for (( __tpi_i = 0; __tpi_i < __tpi_n; __tpi_i++ )); do
                __tpi_out[__tpi_i]="${__tpi_out[__tpi_i]%"$__TPIPE_CR"}"
            done
        fi
        tpipe._close 0
        tpipe._ret "$__tpi_n" "$__tpi_rc"
    else
        tpipe._ret "" 2
    fi
}

TPipe.toList() {
    local __TPIPE_STOP=0 TPIPE_INDEX=0
    local __tpi_d=$'\n' __tpi_crlf='' __tpi_op='' __tpi_fd='' __tpi_pid='' \
          __tpi_rc=0 __tpi_add='' __tpi_line='' __tpi_n=0
    if tpipe._open toList tpipe._isAddable "$@"; then
        __tpi_add="$__tpi_op.Add"
        # The `each` loop with `INST.Add` in the callback's place (PLAN §2.2).
        while IFS= read -r -d "$__tpi_d" -u "$__tpi_fd" __tpi_line || [[ -n "$__tpi_line" ]]; do
            if [[ -n "$__tpi_crlf" ]]; then
                __tpi_line="${__tpi_line%"$__TPIPE_CR"}"
            fi
            __tpi_n=$(( __tpi_n + 1 ))
            TPIPE_INDEX=$__tpi_n
            # `.Add`'s exit status is IGNORED: THashSet.Add answers 1 for a
            # duplicate and TStringList.Add under `dupError` does too, and
            # neither is a stream error. RESULT therefore counts the records
            # OFFERED, not the ones the list chose to keep. Without the `|| :`
            # a rejecting Add would abort a `set -e` caller.
            "$__tpi_add" "$__tpi_line" || :
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

TPipe.first() {
    local __TPIPE_STOP=0 TPIPE_INDEX=0
    local __tpi_d=$'\n' __tpi_crlf='' __tpi_op='' __tpi_fd='' __tpi_pid='' \
          __tpi_rc=0 __tpi_line='' __tpi_got=0
    if tpipe._open first '' "$@"; then
        # One record, then stop. `read`'s own rc is not the test: the `|| [[ -n ]]`
        # tail is what delivers an unterminated last record, and a record that is
        # legitimately EMPTY arrives with read rc 0 — which is exactly what
        # separates "an empty record" (rc 0, RESULT='') from "no record at all"
        # (rc 1, RESULT='').
        if IFS= read -r -d "$__tpi_d" -u "$__tpi_fd" __tpi_line || [[ -n "$__tpi_line" ]]; then
            __tpi_got=1
        fi
        if [[ -n "$__tpi_crlf" ]]; then
            __tpi_line="${__tpi_line%"$__TPIPE_CR"}"
        fi
        # With a record in hand this is the CONSUMER-initiated stop path
        # (close -> kill -TERM -> guarded wait, PLAN §2.3), so an infinite
        # producer dies instead of blocking. With no record the producer already
        # hit EOF, so the plain close/wait gives its real rc through lastRc.
        tpipe._close "$__tpi_got"
        if (( __tpi_got )); then
            # rc 0 whatever the producer's rc turned out to be: WE ended it.
            tpipe._ret "$__tpi_line" 0
        else
            tpipe._ret "" 1
        fi
    else
        tpipe._ret "" 2
    fi
}

TPipe.count() {
    local __TPIPE_STOP=0 TPIPE_INDEX=0
    local __tpi_d=$'\n' __tpi_crlf='' __tpi_op='' __tpi_fd='' __tpi_pid='' \
          __tpi_rc=0 __tpi_line='' __tpi_n=0
    if tpipe._open count '' "$@"; then
        # No callback, so nothing can request a stop and nothing reads the record
        # but the counter. `-c` is accepted for surface symmetry and is a no-op
        # here: stripping a CR cannot change how many records there are.
        while IFS= read -r -d "$__tpi_d" -u "$__tpi_fd" __tpi_line || [[ -n "$__tpi_line" ]]; do
            __tpi_n=$(( __tpi_n + 1 ))
        done
        tpipe._close 0
        tpipe._ret "$__tpi_n" "$__tpi_rc"
    else
        tpipe._ret "" 2
    fi
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
