#!/usr/bin/env bash
[[ ${__KK_UNITS[@]@a} == A* ]] || source "${BASH_SOURCE%tpipe.sh}../../kbool.sh" || return
kk.unit tpipe || return $__kk_unit_rc

# Locale self-heal (kcl/README.md §1.6). Records are data and are handed to the
# callback verbatim, so character semantics are part of this unit's contract:
# an empty environment means the C locale, where ${#s} counts bytes and ${s,,}
# corrupts multi-byte text.
if [[ -z "${LC_ALL:-}${LC_CTYPE:-}${LANG:-}" ]]; then
    export LC_CTYPE=C.UTF-8
fi

# A unit (kklass/USES_PLAN.md §7.4, phase U4): the two header lines at the
# top load kbool.sh when needed and make a repeated `source` a no-op, also
# under `set -eu` (they replaced the D7 re-source guard). Dependencies come
# through kk.uses.
kk.uses kklass_pascal || return

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

# __TPIPE_PT — the process-table source of the tree stop (tpipe._ptScan), probed
# once per process on the FIRST stop and never at load time, so a run that never
# stops pays nothing for it:
#
#   cygwin  Git-bash, MSYS2: /proc/PID/ppid           — no fork
#   linuxc  Linux with /proc/PID/task/TID/children (CONFIG_PROC_CHILDREN, the
#           distribution kernels): no table at all — the tree is walked from
#           the producer down, a couple of reads per member, and a parent is
#           one /proc/PID/stat read. No fork
#   linux   any other Linux (glibc, musl, busybox): every /proc/PID/stat —
#           no fork, but ~150 reads for a full table (measured on kb-ubuntu:
#           two full scans made `TPipe.first -- yes` 2 -> 39 ms)
#   ps      FreeBSD, macOS, a Linux without /proc: ONE `ps -A -o pid= -o ppid=`
#   none    nothing works: the stop path falls back to TERMing the producer
#           alone, which is what it did before launch L2.7-P
#
# This is the unit's OWN table (kcl must not depend on ktests' ktest_proc.sh).
# A value assigned after `source` is honoured when it is one of the five words —
# a test knob (tests/006_TreeStop.sh drives `linux`, `ps` and `none` wherever
# they work); anything else is probed again.
declare -g __TPIPE_PT=''

# __TPIPE_TREETOK — 1 on cygwin (Git-bash, MSYS2): every `--` producer is started
# with `__TPIPE_TREE=...:<shell pid>.<producer pid>` exported, a token
# that the stop path uses to find the producer's descendants that the ppid walk
# cannot (see "The tree stop" below: cygwin delivers a TERM only after a fork in
# flight completes, and the new child is re-parented at once). The assignment
# rides on the existing fork: `<( export VAR=v; cmd )` still execs `cmd`
# directly (no extra process, measured), and costs nothing measurable per call
# for a builtin, a function or an external producer. The prefix form
# `<( VAR=v "$@" )` is NOT used: called from a function, a temporary
# assignment in front of a BUILTIN producer cost ~2 ms per call on Windows
# (`TPipe.count -- printf ...`: 9.3 -> 10.8 ms, measured; nothing for a
# function or an external one). The value accumulates (`a:b`), so a TPipe
# nested inside a producer keeps the outer token. Elsewhere the producer is started exactly as before: Linux does not
# need it, and a forked (not exec'd) Linux subshell would not even show it in
# /proc/PID/environ.
if [[ "$OSTYPE" == cygwin* || "$OSTYPE" == msys* ]]; then
    declare -g __TPIPE_TREETOK=1
else
    declare -g __TPIPE_TREETOK=0
fi

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
    #    On cygwin the producer also gets the tree token (__TPIPE_TREETOK): the
    #    substitution expands it in the CHILD, where $BASHPID is the producer's
    #    own pid and `__tpi_pid` still holds this shell's, so the token is
    #    "<this shell>.<producer>" without a second local.
    if [[ "$__tpi_form" == "cmd" ]]; then
        if (( __TPIPE_TREETOK )); then
            __tpi_pid="$BASHPID"
            exec {__tpi_fd}< <( export __TPIPE_TREE="${__TPIPE_TREE:+$__TPIPE_TREE:}$__tpi_pid.$BASHPID"; "$@" )
        else
            exec {__tpi_fd}< <( "$@" )
        fi
        __tpi_pid=$!
        return 0
    fi
    __tpi_fd=0
    __tpi_pid=''
    return 0
}

# ===========================================================================
# The tree stop (launch L2.7-P, owner decision DL13)
#
# `TPipe.stop` (and `TPipe.first` after its record) stops the producer's WHOLE
# process tree, not only the process substitution. Before DL13 only `$!` got
# the TERM; a function producer runs IN that subshell, so its own children (the
# `sleep 8` of tests/002_Stop.sh's `trap '' PIPE; printf 'a\n'; sleep 8; ...`)
# were re-parented and lived on — the gate's STRAY on Linux, 6-9 per run.
#
# ---- Why a ppid walk on the stop path and not a process group -------------
# A process group would be the textbook tool, but bash cannot give a process
# substitution one: `<( )` joins the caller's group even under `set -m`
# (process_substitute() sets pipeline_pgrp = shell_pgrp; measured on 5.2.37 and
# 5.3.9). The producer would have to be an extra `set -m; "$@" & wait` job
# INSIDE the substitution — one more fork on EVERY call, stopped or not, and a
# fork of a kklass-sized bash costs ~14 ms on Windows (10.4 -> 24.4 ms per
# `<( printf )`, 23.4 -> 37.8 ms per `<( /usr/bin/printf )`, measured). It
# would also move the producer out of the terminal's foreground group, so a
# `-- cat` that reads the caller's terminal would get SIGTTIN, and `setsid`
# would take it out of the session the ktests stray guard watches. The walk
# costs nothing until a stop happens; the normal EOF path is untouched.
#
# ---- The sequence (tpipe._close STOPPED=1) ---------------------------------
#   1. one snapshot of the process table (tpipe._ptScan; on linuxc only the
#      producer's own /proc entries) WHILE the read end is still open — a
#      SIGPIPE-honouring producer cannot die and orphan its children before
#      they are seen;
#   2. the producer is accepted only while the table says it is still OUR
#      child (ppid == $BASHPID): a pid that was reaped and reused belongs to
#      someone else, and neither it nor anything below it is touched. With no
#      usable table, or with the producer missing from it (already reaped; or
#      cygwin's /proc listing missing a live process for a moment), the
#      producer alone gets the TERM, exactly as before DL13;
#   3. its descendants by the ppid chain (tpipe._ptDesc) — collected FROZEN on
#      linux/ps (tpipe._ptFreeze: SIGSTOP the producer, wait until the table
#      shows it stopped, scan, stop what is new, scan again, until a scan finds
#      nothing new), as one snapshot on cygwin (see below);
#   4. close the read end, then ONE `kill -TERM producer descendant...`, and on
#      linux/ps ONE `kill -CONT` of the same list (a stopped process keeps a
#      trapped TERM pending until it runs);
#   5. `wait` for the producer (the one child of ours);
#   6. tpipe._ptReap: the descendants are not our children and cannot be
#      waited for, so they are polled (tpipe._ptAlive: `kill -0`, and on Linux
#      not a zombie; fork-free naps between rounds), every
#      round re-scanning for NEW children of any member (a member that traps
#      TERM may fork on) and TERMing those too; a survivor gets its TERM once
#      more __TPIPE_RETERM_US (0.1 s) after its first and SIGKILL from
#      __TPIPE_GRACE_US (1 s) on, re-sent every round until it is gone (at
#      most __TPIPE_HARDCAP_US, 3 s). On cygwin a ppid-1 process carrying the
#      producer's tree token is a member too (tpipe._ptOrphans,
#      __TPIPE_TREETOK), and the reap ends only when no member is alive for two
#      rounds a nap apart.
#
# ---- Why the freeze (linux, ps) ---------------------------------------------
# Without it the walk loses a race it meets all the time: the producer prints
# the record that makes the consumer stop and forks right after it. A child
# born between the snapshot and the TERM is not in the list, its parent dies
# of the TERM, and it is re-parented — 006 §C left a `sleep` alive in nearly
# every one of ten stops on Linux (measured on kb-ubuntu). A stopped process
# cannot fork, the state the table shows is the real one (Linux sets T when the
# task has stopped), and a fork that completed before the STOP left a child the
# next scan lists; a fork still in flight when a FATAL signal arrives is
# aborted by the kernel.
#
# ---- Why no freeze, and a token instead, on cygwin --------------------------
#   * a STOP is reported as state T before the main thread really stops: a
#     fork in flight still completes and its child appears ~12 ms later
#     (measured), so "frozen" cannot be observed;
#   * a STOP that lands while a process is in its exec hand-over left `sleep`s
#     stuck in T that neither CONT nor KILL ended (Git runtime, measured — only
#     TerminateProcess did);
#   * a STOP to a native Win32 producer (git.exe) makes cygwin print
#     "Suppressing signal 17 to win32 process" on the producer's stderr.
# The race is real there too, and worse: cygwin delivers a TERM only after a
# fork in flight completes, and the new child is re-parented to 1 at once (30
# of 30 survivors in 006 §C before the token, both bashes). What survives is
# the environment: cygwin's /proc/PID/environ of a FORKED bash shows the
# variables it exported (unlike Linux, where it is the env of the last exec),
# so the producer's token reaches every descendant, and a ppid-1 process that
# carries it is the producer's, whatever its ppid says now. Each one found is
# TERMed, and the reap ends only when no member is alive for two rounds a nap
# apart.
#
# ---- Job control, the terminal, the stray guard ----------------------------
# Neither the freeze nor the token changes the producer's process group or
# session, so job control, the terminal and the ktests stray guard (which
# watches the session) see the same processes as before DL13. The freeze
# stops processes of the caller's own group for a few milliseconds; a caller
# with job control on is not told — the stop path turns `set -m` off for that
# time, or bash would record the producer's STOP as its status (tpipe._close;
# 006 §F runs the stop under `set -m`, an interactive bash was checked by hand
# on kb-ubuntu under script(1)).
#
# ---- What is NOT done, and why --------------------------------------------
#   * the producer itself gets no KILL: it is our child, `wait` is the only
#     honest way to learn its rc, and a producer that ignores TERM blocks the
#     stop exactly as it did before (README §5).
#   * no tree stop on the EOF path: a producer that finished on its own and
#     left a background job behind is not stopped by TPipe (README §5).
#
# ---- Limits (README §5) -----------------------------------------------------
#   * a descendant that already left the tree before the stop — a daemon that
#     double-forked, a child whose parent exited — has no ppid chain to the
#     producer any more and is not found (on cygwin the token still finds it
#     while it is re-parented to 1 and kept its environment);
#   * a descendant that clears its environment (`env -i`) AND is born in the
#     race above escapes the cygwin token;
#   * the `ps` backend costs one `ps` per scan and per freeze check (FreeBSD,
#     macOS) — a stop there forks a few times; the EOF path still never does.
#
# All helpers write the CALLER's `__tpi_*` locals through dynamic scoping, like
# the rest of this unit, and are `set -eu` safe: every test is an `if`, every
# signal `|| :`.
# ===========================================================================

# The reap's deadlines, in µs. Constants, not knobs.
#   RETERM  a descendant still alive this long after ITS TERM gets the TERM
#           once more (once per member). The Git runtime
#           (5.2.37) LOSES a signal sent while the target is still in its exec
#           hand-over — 2 of 30 `sleep`s TERMed right after the fork survived
#           (measured; 0 of 30 on MSYS2's 5.3.9), and in the 006 shapes every
#           stop then waited the whole grace. A second TERM to a process that
#           did get the first one only re-queues its trap.
#   GRACE   whatever is still alive this long after its first TERM gets
#           SIGKILL, re-sent every round until it is gone: a member that traps
#           TERM and takes longer, or ignores it, or (Git runtime) one whose
#           signals are still being lost in its exec hand-over.
#   HARDCAP the reap gives up: a process that neither TERM nor repeated KILLs
#           end within this is left (none was seen; it bounds the stop).
declare -gr __TPIPE_RETERM_US=100000
declare -gr __TPIPE_GRACE_US=1000000
declare -gr __TPIPE_HARDCAP_US=3000000

# tpipe._ptScan — fill the caller's assoc `__tpi_pp` (pid -> ppid) from the
# process table. rc 0 when the table is usable, i.e. it lists this shell
# itself; rc 1 when there is none (`__TPIPE_PT=none`) or it came back empty.
tpipe._ptScan() {
    local __tpi_f='' __tpi_q='' __tpi_l='' __tpi_a='' __tpi_b=''
    local IFS=$' \t\n'
    __tpi_pp=()
    case "$__TPIPE_PT" in
        cygwin|linuxc|linux|ps|none) ;;
        *)  if [[ -r "/proc/$BASHPID/ppid" ]]; then
                __TPIPE_PT=cygwin
            elif (( ! __TPIPE_TREETOK )) \
                 && [[ -r "/proc/$BASHPID/task/$BASHPID/children" ]]; then
                __TPIPE_PT=linuxc
            elif (( ! __TPIPE_TREETOK )) && [[ -r "/proc/$BASHPID/stat" ]]; then
                __TPIPE_PT=linux
            elif type -P ps >/dev/null 2>&1; then
                __TPIPE_PT=ps
            else
                __TPIPE_PT=none
            fi ;;
    esac
    case "$__TPIPE_PT" in
        linuxc)
            # no table: tpipe._ptDesc and tpipe._ptParent read /proc per pid
            [[ -r "/proc/$BASHPID/task/$BASHPID/children" ]]
            return ;;
        cygwin)
            # /proc/PID/ppid is cygwin's own file (~30 µs a read); its
            # /proc/PID/stat is far more expensive there.
            for __tpi_f in /proc/[0-9]*/ppid; do
                if { read -r __tpi_l < "$__tpi_f"; } 2>/dev/null; then
                    __tpi_q="${__tpi_f#/proc/}"
                    __tpi_pp[${__tpi_q%/ppid}]="$__tpi_l"
                fi
            done ;;
        linux)
            # Fields counted from the LAST ") ": a comm may hold spaces and
            # parentheses. After it: state, ppid, ...
            for __tpi_f in /proc/[0-9]*/stat; do
                if { IFS= read -r __tpi_l < "$__tpi_f"; } 2>/dev/null; then
                    __tpi_l="${__tpi_l##*) }"
                    __tpi_l="${__tpi_l#* }"
                    __tpi_q="${__tpi_f#/proc/}"
                    __tpi_pp[${__tpi_q%/stat}]="${__tpi_l%% *}"
                fi
            done ;;
        ps)
            # POSIX keywords, one `-o` each (BSD ps reads the rest of
            # `-o a=,b=` as a's header).
            while read -r __tpi_a __tpi_b; do
                if [[ -n "$__tpi_a" && "$__tpi_a" != *[!0-9]* \
                      && -n "$__tpi_b" && "$__tpi_b" != *[!0-9]* ]]; then
                    __tpi_pp[$__tpi_a]="$__tpi_b"
                fi
            done < <(ps -A -o pid= -o ppid= 2>/dev/null)
            ;;
    esac
    [[ -n "${__tpi_pp[$BASHPID]+x}" ]]
}

# tpipe._ptParent PID — the caller's `__tpi_par` = the ppid of PID, '' when it
# is not listed (gone, or not in the last scan). linuxc reads /proc/PID/stat;
# the other backends look it up in the caller's `__tpi_pp` from the last
# tpipe._ptScan. rc 0. (Not REPLY: the caller's REPLY is the caller's.)
tpipe._ptParent() {
    local __tpi_l=''
    __tpi_par=''
    if [[ "$__TPIPE_PT" == linuxc ]]; then
        if { IFS= read -r __tpi_l < "/proc/$1/stat"; } 2>/dev/null; then
            __tpi_l="${__tpi_l##*) }"
            __tpi_l="${__tpi_l#* }"
            __tpi_par="${__tpi_l%% *}"
        fi
    elif [[ -n "${__tpi_pp[$1]+x}" ]]; then
        __tpi_par="${__tpi_pp[$1]}"
    fi
    return 0
}

# tpipe._ptDesc PID... — append to the caller's `__tpi_new` every descendant of
# the PIDs that is not yet in the caller's assoc `__tpi_seen`, and mark it seen:
# linuxc walks /proc/PID/task/*/children from the PIDs down (every thread's
# file: a child belongs to the thread that forked it); the other backends
# follow the ppid chain in `__tpi_pp`. Always rc 0.
tpipe._ptDesc() {
    local -A __tpi_kids=()
    local -a __tpi_q=( "$@" )
    local __tpi_p='' __tpi_c='' __tpi_f='' __tpi_l=''
    local IFS=$' \t\n'
    __tpi_new=()
    if [[ "$__TPIPE_PT" == linuxc ]]; then
        while (( ${#__tpi_q[@]} > 0 )); do
            __tpi_p="${__tpi_q[0]}"
            __tpi_q=( "${__tpi_q[@]:1}" )
            for __tpi_f in "/proc/$__tpi_p/task/"*/children; do
                __tpi_l=''
                { IFS= read -r __tpi_l < "$__tpi_f"; } 2>/dev/null || :
                for __tpi_c in $__tpi_l; do
                    if [[ -z "${__tpi_seen[$__tpi_c]+x}" ]]; then
                        __tpi_seen[$__tpi_c]=1
                        __tpi_new+=( "$__tpi_c" )
                        __tpi_q+=( "$__tpi_c" )
                    fi
                done
            done
        done
        return 0
    fi
    for __tpi_p in "${!__tpi_pp[@]}"; do
        __tpi_kids[${__tpi_pp[$__tpi_p]}]+=" $__tpi_p"
    done
    while (( ${#__tpi_q[@]} > 0 )); do
        __tpi_p="${__tpi_q[0]}"
        __tpi_q=( "${__tpi_q[@]:1}" )
        for __tpi_c in ${__tpi_kids[$__tpi_p]:-}; do
            if [[ -z "${__tpi_seen[$__tpi_c]+x}" ]]; then
                __tpi_seen[$__tpi_c]=1
                __tpi_new+=( "$__tpi_c" )
                __tpi_q+=( "$__tpi_c" )
            fi
        done
    done
    return 0
}

# tpipe._ptOrphans TOKEN — cygwin only: append to the caller's `__tpi_new` every
# process the last scan shows re-parented to 1 that is not yet in `__tpi_seen`
# and whose environment carries TOKEN in __TPIPE_TREE (see __TPIPE_TREETOK), and
# mark it seen. The token is unique to one producer, so a hit is that producer's
# descendant whatever its ppid says now. Only ppid-1 processes are read: on
# cygwin that is where an orphan lands. Always rc 0.
tpipe._ptOrphans() {
    local __tpi_p='' __tpi_v=''
    local -a __tpi_env=()
    __tpi_new=()
    for __tpi_p in "${!__tpi_pp[@]}"; do
        if [[ "${__tpi_pp[$__tpi_p]}" != 1 || -n "${__tpi_seen[$__tpi_p]+x}" ]]; then
            continue
        fi
        __tpi_env=()
        { mapfile -d '' -t __tpi_env < "/proc/$__tpi_p/environ"; } 2>/dev/null || continue
        for __tpi_v in "${__tpi_env[@]}"; do
            if [[ "$__tpi_v" == __TPIPE_TREE=* && ":${__tpi_v#__TPIPE_TREE=}:" == *":$1:"* ]]; then
                __tpi_seen[$__tpi_p]=1
                __tpi_new+=( "$__tpi_p" )
                break
            fi
        done
    done
    return 0
}

# tpipe._nap — about 10 ms without a fork: `read -t` on a pty master that never
# has data (the caller's `__tpi_nfd`, opened on first use and closed by
# tpipe._close); `sleep` where /dev/ptmx cannot be opened or the read does not
# time out (FreeBSD without the pty compat device).
#
# The open is `{ exec {fd}<>/dev/ptmx; } 2>/dev/null`, never `exec {fd}<>...
# 2>/dev/null`: on `exec` EVERY redirection is permanent, so the second form
# sends the caller's stderr to /dev/null for the rest of its life (measured —
# 006 pins that stderr still works after a stop). The `-c` test first: a failed
# redirection on `exec` ends a shell in POSIX mode.
tpipe._nap() {
    local __tpi_x='' __tpi_r=0
    if [[ -z "$__tpi_nfd" ]]; then
        __tpi_nfd=-
        if [[ -c /dev/ptmx ]]; then
            { exec {__tpi_nfd}<>/dev/ptmx; } 2>/dev/null || __tpi_nfd=-
        fi
    fi
    if [[ "$__tpi_nfd" != - ]]; then
        read -r -t 0.01 -u "$__tpi_nfd" __tpi_x 2>/dev/null || __tpi_r=$?
        if (( __tpi_r > 128 )); then
            return 0
        fi
    fi
    sleep 0.01 2>/dev/null || :
    return 0
}

# tpipe._ptFrozen PID... — rc 0 when every PID given is stopped (T/t), dead
# (Z/X) or gone. linux: /proc/PID/stat (no fork); ps: ONE `ps -o pid= -o
# state= -p LIST`. Never called on cygwin (see "Why no freeze ... on cygwin").
tpipe._ptFrozen() {
    local __tpi_p='' __tpi_l='' __tpi_s=''
    local IFS=$' \t\n'
    if [[ "$__TPIPE_PT" == ps ]]; then
        printf -v __tpi_l '%s,' "$@"
        while read -r __tpi_p __tpi_s; do
            case "$__tpi_s" in
                T*|t*|Z*|X*|'') ;;
                *) return 1 ;;
            esac
        done < <(ps -o pid= -o state= -p "${__tpi_l%,}" 2>/dev/null)
        return 0
    fi
    for __tpi_p in "$@"; do
        if { IFS= read -r __tpi_l < "/proc/$__tpi_p/stat"; } 2>/dev/null; then
            __tpi_s="${__tpi_l##*) }"
            case "${__tpi_s%% *}" in
                T|t|Z|X) ;;
                *) return 1 ;;
            esac
        fi
    done
    return 0
}

# tpipe._ptStop PID... — SIGSTOP each PID (one that refuses it — EPERM, already
# gone — is not waited for) and wait until all are frozen: a few tight
# re-checks, then fork-free naps, the STOP re-sent every 4th round, at most
# __TPIPE_GRACE_US. Always rc 0; a process that never freezes (stuck in
# uninterruptible sleep) is simply TERMed with the rest after the bound.
tpipe._ptStop() {
    local __tpi_t0="${EPOCHREALTIME/[.,]/}" __tpi_i=0 __tpi_p=''
    local -a __tpi_w=()
    for __tpi_p in "$@"; do
        if kill -STOP "$__tpi_p" 2>/dev/null; then
            __tpi_w+=( "$__tpi_p" )
        fi
    done
    if (( ${#__tpi_w[@]} == 0 )); then
        return 0
    fi
    while ! tpipe._ptFrozen "${__tpi_w[@]}"; do
        __tpi_i=$(( __tpi_i + 1 ))
        if (( ${EPOCHREALTIME/[.,]/} - __tpi_t0 >= __TPIPE_GRACE_US )); then
            return 0
        fi
        if (( __tpi_i % 4 == 0 )); then
            kill -STOP "${__tpi_w[@]}" 2>/dev/null || :
        fi
        if (( __tpi_i > 3 )); then
            tpipe._nap
        fi
    done
    return 0
}

# tpipe._ptFreeze ROOT — linux and ps backends: freeze the producer and its
# tree before anything is signalled to die. ROOT first, then, scan after scan,
# every descendant not yet frozen, until a scan taken with all of them stopped
# finds nothing new: a stopped process cannot fork, and a fork that completed
# before the STOP left a child the next scan lists. The caller's `__tpi_tree`
# receives the descendants (the caller's `__tpi_pp`, `__tpi_seen`, `__tpi_new`
# are used). At most 16 rounds. Always rc 0.
tpipe._ptFreeze() {
    local __tpi_i=0
    tpipe._ptStop "$1"
    for (( __tpi_i = 0; __tpi_i < 16; __tpi_i++ )); do
        if ! tpipe._ptScan; then
            break
        fi
        tpipe._ptDesc "$1" "${__tpi_tree[@]}"
        if (( ${#__tpi_new[@]} == 0 )); then
            break
        fi
        tpipe._ptStop "${__tpi_new[@]}"
        __tpi_tree+=( "${__tpi_new[@]}" )
    done
    return 0
}

# tpipe._ptAlive PID — rc 0 while PID is a live process: `kill -0` sees it and,
# on linux, /proc/PID/stat does not say Z. A killed descendant is re-parented
# and stays a ZOMBIE until its new parent reaps it — busybox init (Alpine) does
# that about once a second, and `kill -0` answers yes all that time (measured:
# every stop on kb-alpine took the whole 1 s grace before this check).
tpipe._ptAlive() {
    local __tpi_l=''
    if ! kill -0 "$1" 2>/dev/null; then
        return 1
    fi
    if [[ "$__TPIPE_PT" == linux* ]] \
       && { IFS= read -r __tpi_l < "/proc/$1/stat"; } 2>/dev/null; then
        __tpi_l="${__tpi_l##*) }"
        if [[ "${__tpi_l%% *}" == Z ]]; then
            return 1
        fi
    fi
    return 0
}

# tpipe._ptReap [TOKEN] — step 6 of the sequence. Round after round, until the
# tree is gone or __TPIPE_HARDCAP_US:
#   * one scan: every NEW descendant of any member ever seen gets its TERM (a
#     member that traps TERM may fork on); with TOKEN (cygwin) every ppid-1
#     process carrying the token is a member too (tpipe._ptOrphans);
#   * every member is checked (tpipe._ptAlive) — ALL of them, every round, not
#     only the ones alive last time: under load the Git runtime can report a
#     process in its exec hand-over as gone for a moment;
#   * per member, counted from ITS first TERM: one more TERM after
#     __TPIPE_RETERM_US, SIGKILL after __TPIPE_GRACE_US and again every round
#     after that (the Git runtime loses a KILL sent during the hand-over too —
#     measured under the threaded runner).
# Done when no member is alive — on cygwin only when that holds for two rounds a
# nap apart (a child whose parent's fork just returned is not always listed
# yet: one survivor in ten 006 §C stops with a single look). Uses the caller's
# `__tpi_tree`, `__tpi_pp`, `__tpi_seen`, `__tpi_new`. Always rc 0.
tpipe._ptReap() {
    local __tpi_t0="${EPOCHREALTIME/[.,]/}" __tpi_now=0 __tpi_p='' __tpi_age=0
    local __tpi_quiet=0 __tpi_need=1
    local -A __tpi_tt=() __tpi_rt=()
    local -a __tpi_live=() __tpi_re=() __tpi_kl=()
    if [[ -n "$1" && "$__TPIPE_PT" == cygwin ]]; then
        __tpi_need=2
    fi
    for __tpi_p in "${__tpi_tree[@]}"; do
        __tpi_tt[$__tpi_p]="$__tpi_t0"
    done
    while :; do
        if tpipe._ptScan; then
            tpipe._ptDesc "${!__tpi_seen[@]}"
            if [[ -n "$1" && "$__TPIPE_PT" == cygwin ]]; then
                __tpi_re=( "${__tpi_new[@]}" )
                tpipe._ptOrphans "$1"
                __tpi_new+=( "${__tpi_re[@]}" )
            fi
            if (( ${#__tpi_new[@]} > 0 )); then
                kill -TERM "${__tpi_new[@]}" 2>/dev/null || :
                __tpi_now="${EPOCHREALTIME/[.,]/}"
                for __tpi_p in "${__tpi_new[@]}"; do
                    __tpi_tt[$__tpi_p]="$__tpi_now"
                done
                __tpi_tree+=( "${__tpi_new[@]}" )
            fi
        fi
        __tpi_live=()
        for __tpi_p in "${__tpi_tree[@]}"; do
            if tpipe._ptAlive "$__tpi_p"; then
                __tpi_live+=( "$__tpi_p" )
            fi
        done
        if (( ${#__tpi_live[@]} == 0 )); then
            __tpi_quiet=$(( __tpi_quiet + 1 ))
            if (( __tpi_quiet >= __tpi_need )); then
                return 0
            fi
            tpipe._nap
            continue
        fi
        __tpi_quiet=0
        __tpi_now="${EPOCHREALTIME/[.,]/}"
        if (( __tpi_now - __tpi_t0 >= __TPIPE_HARDCAP_US )); then
            return 0
        fi
        __tpi_re=(); __tpi_kl=()
        for __tpi_p in "${__tpi_live[@]}"; do
            __tpi_age=$(( __tpi_now - ${__tpi_tt[$__tpi_p]:-$__tpi_t0} ))
            if (( __tpi_age >= __TPIPE_GRACE_US )); then
                __tpi_kl+=( "$__tpi_p" )
            elif (( __tpi_age >= __TPIPE_RETERM_US )) && [[ -z "${__tpi_rt[$__tpi_p]+x}" ]]; then
                __tpi_rt[$__tpi_p]=1
                __tpi_re+=( "$__tpi_p" )
            fi
        done
        if (( ${#__tpi_re[@]} > 0 )); then
            kill -TERM "${__tpi_re[@]}" 2>/dev/null || :
        fi
        if (( ${#__tpi_kl[@]} > 0 )); then
            kill -KILL "${__tpi_kl[@]}" 2>/dev/null || :
        fi
        tpipe._nap
    done
}

# ---------------------------------------------------------------------------
# tpipe._close [STOPPED]
#
# STOPPED is 1 when the CONSUMER ended the stream (TPipe.stop). Sets the caller's
# `__tpi_rc` (the member's exit status) and the process-wide `__TPIPE_RC` (the
# producer's raw rc, published by TPipe.lastRc). Always rc 0.
#
#   * `exec {fd}<&-` comes before the wait, always: a producer blocked on a full
#     pipe only gets its SIGPIPE once the read end is gone, and `wait` would
#     hang. On the stop path the table snapshot comes before the close (step 1
#     of the tree stop above), the TERM right after it.
#   * on the stop path the close is followed by `kill -TERM` of the producer
#     and its whole tree (the block above): a producer that ignores SIGPIPE and
#     then stops writing (`trap '' PIPE; echo a; sleep 8`) otherwise blocks
#     `wait` for its whole remaining life — 8.1 s measured, ~50 ms with the
#     kill — and its `sleep 8` would outlive it.
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
    if [[ "${1:-0}" == "0" ]]; then         # EOF path: unchanged by DL13
        exec {__tpi_fd}<&-
        __TPIPE_RC=0
        wait "$__tpi_pid" || __TPIPE_RC=$?
        if [[ "$__TPIPE_RC" == "0" ]]; then
            __tpi_rc=0
        else
            __tpi_rc=1
        fi
        return 0
    fi
    # The stop path. `local -` restores the caller's options when we return:
    #   set +f  the table is read through a glob, and a caller under `set -f`
    #           must not turn the walk into a no-op;
    #   set +m  with job control on, bash reaps its children with WUNTRACED, so
    #           the freeze's SIGSTOP of the producer (our child) is RECORDED as
    #           its status and the `wait` below answers 147 or 0 instead of 143
    #           (measured on kb-ubuntu, 5.2.21, non-interactive `set -m`). Off
    #           for these few milliseconds, the stop and the CONT are invisible
    #           to bash and `wait` gets the real exit status.
    local -
    set +f +m
    local -A __tpi_pp=() __tpi_seen=()
    local -a __tpi_new=() __tpi_tree=()
    local __tpi_nfd='' __tpi_kill=1 __tpi_tok='' __tpi_frz=0 __tpi_par=''
    if (( __TPIPE_TREETOK )); then
        __tpi_tok="$BASHPID.$__tpi_pid"
    fi
    if tpipe._ptScan && tpipe._ptParent "$__tpi_pid" && [[ -n "$__tpi_par" ]]; then
        if [[ "$__tpi_par" == "$BASHPID" ]]; then
            __tpi_seen[$__tpi_pid]=1
            if (( __TPIPE_TREETOK )); then  # cygwin: never a SIGSTOP (above)
                tpipe._ptDesc "$__tpi_pid"
                __tpi_tree=( "${__tpi_new[@]}" )
            else
                __tpi_frz=1
                tpipe._ptFreeze "$__tpi_pid"
            fi
        else
            __tpi_kill=0                    # a reused pid: not ours any more
            __tpi_tok=''
        fi
    fi
    exec {__tpi_fd}<&-
    if (( __tpi_kill )); then
        kill -TERM "$__tpi_pid" "${__tpi_tree[@]}" 2>/dev/null || :
    fi
    if (( __tpi_frz )); then
        kill -CONT "$__tpi_pid" "${__tpi_tree[@]}" 2>/dev/null || :
    fi
    __TPIPE_RC=0
    wait "$__tpi_pid" || __TPIPE_RC=$?
    if (( ${#__tpi_tree[@]} > 0 )) || [[ -n "$__tpi_tok" && "$__TPIPE_PT" == cygwin ]]; then
        tpipe._ptReap "$__tpi_tok"
    fi
    if [[ -n "$__tpi_nfd" && "$__tpi_nfd" != - ]]; then
        exec {__tpi_nfd}>&-
    fi
    __tpi_rc=0
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
