#!/bin/bash

# Re-source guard: the class only needs to be built once per process
# (kcl/README.md §1.4 — the guard reads the flag with `:-` so `set -u` is happy).
if [[ -n "${_TTAIL_SOURCED:-}" ]]; then
    return
fi
declare -g _TTAIL_SOURCED=1

# Locale self-heal (kcl/README.md §1.6). A path and the bytes tail emits are
# data and pass through verbatim, so character semantics are part of this unit's
# contract: an empty environment means the C locale, where a multi-byte file
# name stops being characters.
if [[ -z "${LC_ALL:-}${LC_CTYPE:-}${LANG:-}" ]]; then
    export LC_CTYPE=C.UTF-8
fi

# The base class. `tutil.sh` transitively brings kklass's Pascal front-end and
# `tpipe.sh`; both carry re-source guards, so a caller that already loaded them
# pays nothing. This is the tobjectlist -> tlist pattern: a descendant in
# another file sources its parent by the parent's own path, resolved from
# `${BASH_SOURCE[0]}`. This is the ONLY `source` line in the unit — the sibling
# `head` wrapper is never sourced from here and `TTail : THead` would be wrong,
# because `+N` means "the first N" there and "from line N" here. The two units
# share their plan text and nothing else.
TTAIL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$TTAIL_DIR/../tutil/tutil.sh"

# Monotonic sequence for `TTail.take`'s throw-away instance name. A FIXED name is
# deleted out from under an outer `take` by a nested one, so the name is
# `__tt_t_${BASHPID}_${__TT_SEQ}`: BASHPID separates processes (a `$( )` or
# `<( )` producer is a different one), the counter separates calls inside a
# process. Same idiom as TGrep's `__TG_SEQ`.
declare -g __TT_SEQ=0

# ---------------------------------------------------------------------------
# TTail — the GNU coreutils 8.32 `tail` wrapper over TUtil.
#
#     source kcl/ttail/ttail.sh
#
#     TTail.take 20 build.log              # the one-liner: `tail -n 20`, streamed
#     TTail.take +2 data.csv               # skip the header row
#
#     TTail.new t 20 a.log b.log           # or an instance, for options
#     t.quiet = 1                          # no `==> NAME <==` headers
#     t.each r.onLine                      # one call per record, THIS shell
#     t.toArray last20                     # RESULT = ${#last20[@]}
#     t.count                              # RESULT = how many
#
#     t.follow = 1                         # -f: run / each / first only (§2.1)
#     t.first                              # "wait for the next line"
#     t.delete
#
# ---- The pinned argv (PLAN §1.2) ------------------------------------------
#   tail [-q|-v] [-z] [-f] [-n N | -c N] [EXTRA ARGS from addArg] [-- PATH...]
#
# The order is this builder's, not the caller's. `--` appears only when there is
# at least one path (with none, tail reads stdin, the documented stdin form).
# Booleans are the exact string `1`; anything else is off. Extras come LAST, and
# because tail is last-flag-wins an `addArg -n`/`-c` REPLACES `lines`/`bytes` —
# the documented escape hatch for the suffix forms (`-n 1K`).
#
# `t.argv V` with `follow = 1` still yields `-f`: the refusal below is a SINK
# rule, not an argv rule.
#
# ---- The count (PLAN §2.2, the sibling plan's §2.2) -----------------------
# `lines` and `bytes` are validated with ONE regex, `^[+-]?[0-9]+$`, plus a
# magnitude guard of at most 19 digits, and passed to tail VERBATIM. `kk.isInt`
# is deliberately NOT used: it normalises, and tail reads the normalised value as
# a different request —
#
#   value | tail -n           | the `head` wrapper's -n
#   ------+-------------------+--------------------------
#   N     | the last N        | the first N
#   +N    | FROM line N       | the first N
#   -N    | the last N        | all but the last N
#   0/-0  | nothing           | 0/+0 nothing, -0 everything
#   +0    | EVERYTHING        | nothing
#
# so `kk.isInt` turning `+2` into `2` would swap "from line 2" for "the last
# two lines". `08` reaches tail as `08` and tail reads it as decimal 8.
#
# ---- rc 2 at buildArgv: nothing runs, one kk.debug line --------------------
#   * `cmd` empty (the instance was disarmed by hand);
#   * `lines` AND `bytes` (tail would silently take the last one);
#   * `quiet` AND `verbose` (tail accepts both, last flag wins — the answer
#     would depend on this builder's fixed order rather than on the caller);
#   * `zeroTerminated` with two or more paths, or with `verbose`: the
#     `==> NAME <==` headers stay `\n`-terminated under `-z`, so a derived `-0`
#     would frame header + data into ONE record;
#   * a count that fails the regex or the 19-digit guard.
#
# ---- `follow` and the sinks (PLAN §2.1) -----------------------------------
# `tail -f` never ends on its own, and `buildArgv` cannot refuse per sink — it
# does not know its caller. The split is therefore three OVERRIDDEN sinks:
#
#   run           streams until the caller kills it (Ctrl-C, `timeout`, a kill)
#   each          streams until the callback calls `TPipe.stop`; the tpipe stop
#                 path (close -> kill -TERM -> wait) then ends tail with raw rc
#                 143 -> member rc 0, `lastRc` 143. BLOCKS FOREVER with a
#                 callback that never stops: there is no timeout and no
#                 cancellation from outside
#   first         one record, then the same stop path — the "wait for the next
#                 line" idiom; blocks until a record arrives
#   toArray       rc 2 IN THE OVERRIDE, nothing runs: they can only finish at
#   count         EOF, which never comes
#   toList        rc 2 too: it could only finish if `.Add` called `TPipe.stop`,
#                 and no kcl list does (TStringList / TList / THashSet.Add never
#                 stop)
#
# `addArg --pid=PID` is the ONE shape in which `-f` terminates on its own (once
# PID dies); the refusal is not lifted by inspecting `${inst}_args` — a caller
# who needs that uses `run`.
#
# ---- mapRc ----------------------------------------------------------------
# tail has no "answer" rc: `0` is success and `1` is every failure — a missing
# file, a bad count, an unknown option. So `0 -> 0`, anything else `-> 1` with
# one `kk.debug` line (127 keeps the base wording). Two named deviations this
# family already carries:
#   (a) a PARTIAL failure (`tail -n 1 a missing`) prints a's records and exits 1;
#       the sinks keep every record that arrived and RESULT is the REAL count;
#   (b) tail's own stderr is unconditional and its quoting follows the locale —
#       it is the TOOL's stream and passes through untouched.
#
# ---- Headers are records --------------------------------------------------
# With two or more operands and neither `-q` nor `-v`, tail writes
# `\n==> NAME <==\n` before every operand after the first. Through the sinks
# those are ordinary records, and the leading `\n` is an EMPTY record only when
# the previous file's last line was terminated: two terminated 3-line files under
# `-n 5` are 9 records, the same pair with the first unterminated is 8.
#
# ---- Text mode and the CR -------------------------------------------------
# tail is a BYTE tool: it keeps the CR. This is one of the two wrappers where
# TUtil's `crlf = 1` finally does something — it strips exactly one trailing CR
# per record, in bytes mode too.
#
# ---- Traps this unit is written around ------------------------------------
#  * The constructor calls `parent.constructor tail` EXPLICITLY. `inherited` in
#    a constructor body is rewritten to `parent.constructor "$@"` and would hand
#    TUtil `cmd=N` plus every path as an extra argument — every path would then
#    appear twice in the argv.
#  * EVERY declared var is assigned in `Create`.
#  * An overridden `func` may NOT simply end on `inherited NAME "$@"`: `build`
#    compiles a `kk._return "$RESULT"` trailer onto a `func`, and that trailer
#    replaces the rc — the override would answer 0 where the base answered 1.
#    The three sink overrides therefore capture the rc, save RESULT, and re-raise
#    both: `inherited X "$@" || rc=$?; n="$RESULT"; kk._return "$n"; return "$rc"`.
#  * No `var` here may be named like a TUtil member (`cmd crlf nul _lastRc
#    subshellOk buildArgv addArg clearArgs argv run each toArray toList first
#    count lastRc mapRc`) or a kklass one (`property call parent delete`).
#  * Booleans are compared as strings (`[[ "$x" == 1 ]]`).
#  * The count regex lives in a VARIABLE and is applied with `[[ =~ $re ]]`.
#  * `${inst}_argv` is rebuilt through a nameref, never with `unset "…[…]"`.
#  * `__tt_` is registered in `tutil._badOut`: bash scopes locals DYNAMICALLY, so
#    a caller array named `__tt_v` would bind this unit's own scratch nameref.
# ---------------------------------------------------------------------------
class TTail : TUtil
    public
        var lines           # -n N   ('' = off -> tail's own default of 10)
        var bytes           # -c N   ('' = off); with `lines` -> rc 2
        var quiet           # -q     never print the file-name headers
        var verbose         # -v     always print them; with `quiet` -> rc 2
        var zeroTerminated  # -z     NUL INPUT records; derives the sinks' -0
        var follow          # -f     see §2.1 — three sinks refuse it
        var _nulDerived     # private bookkeeping for the -z derivation
        constructor Create  # [N [PATH...]] — N becomes `lines`
        destructor  Destroy # frees ${inst}_paths, then inherited
        proc paths          # PATH... — REPLACES the operand list
        override func buildArgv
        override func mapRc
        override func toArray
        override func toList
        override func count
        static proc take    # N PATH... — `tail -n N -- PATH...`, streamed
end

# ===========================================================================
# Members
# ===========================================================================

# Create [N [PATH...]].
#
# `parent.constructor tail` is spelled out: `inherited` would forward THIS
# constructor's arguments to TUtil and make `cmd` the count while every path
# became a TUtil extra arg — each path would then appear twice. After it, EVERY
# declared var is assigned (booleans `0`, strings `''`), and the operand list
# becomes a real global array next to `${inst}_data`, released by the destructor
# (kcl/README.md §1.9).
TTail.Create() {
    parent.constructor tail
    lines="${1:-}"
    bytes=''
    quiet=0
    verbose=0
    zeroTerminated=0
    follow=0
    _nulDerived=0
    declare -ga "${__inst__}_paths=()"
    local -n __tt_p="${__inst__}_paths"
    __tt_p=( "${@:2}" )
    return 0
}

# Destroy — release this class's own array, then chain. `inherited` in a
# DESTRUCTOR is the ordinary parent call, and TUtil.Destroy releases
# `${inst}_args` and `${inst}_argv`. `unset -v` on a name that does not exist is
# rc 0, so a half-built instance tears down cleanly too.
TTail.Destroy() {
    unset -v "${__inst__}_paths"
    inherited
    return 0
}

# paths PATH... — REPLACE the operand list. With no arguments the list becomes
# empty and the built argv carries no `--` at all, which is tail's stdin form.
TTail.paths() {
    local -n __tt_p="${__inst__}_paths"
    __tt_p=( "$@" )
    return 0
}

# buildArgv — the override, and the single truth about what will run. `run` and
# all five sinks reach it through `kk.call_silent`, which dispatches VIRTUALLY,
# so this body is what they get.
#
# RESULT = the number of words, rc 0. On any refusal: `kk._return ""`, rc 2, one
# `kk.debug` line naming the reason, `${inst}_argv` left EMPTY so no stale
# command line can be executed afterwards, and the caller runs nothing.
TTail.buildArgv() {
    local -n __tt_v="${__inst__}_argv"
    local -n __tt_p="${__inst__}_paths"
    __tt_v=()

    # ---- the rc 2 list, checked before a single word is built -------------
    if [[ -z "$cmd" ]]; then
        kk.debug "Error: TTail.buildArgv: cmd is empty; there is nothing to run"
        kk._return ""
        return 2
    fi
    if [[ -n "$lines" && -n "$bytes" ]]; then
        kk.debug "Error: TTail.buildArgv: lines (-n) and bytes (-c) are mutually exclusive; tail takes both and the last one silently wins"
        kk._return ""
        return 2
    fi
    if [[ "$quiet" == 1 && "$verbose" == 1 ]]; then
        kk.debug "Error: TTail.buildArgv: quiet (-q) and verbose (-v) are mutually exclusive; tail takes both and the answer would depend on this builder's order"
        kk._return ""
        return 2
    fi
    if [[ "$zeroTerminated" == 1 ]] && (( ${#__tt_p[@]} > 1 )); then
        kk.debug "Error: TTail.buildArgv: zeroTerminated (-z) with ${#__tt_p[@]} paths; the \`==> NAME <==\` headers stay newline-terminated under -z, so the derived -0 would frame a header and its file into ONE record — use one path, or set quiet and run the files separately"
        kk._return ""
        return 2
    fi
    if [[ "$zeroTerminated" == 1 && "$verbose" == 1 ]]; then
        kk.debug "Error: TTail.buildArgv: zeroTerminated (-z) with verbose (-v); a forced \`==> NAME <==\` header is newline-terminated and would be framed into the file's own NUL record"
        kk._return ""
        return 2
    fi

    # The count regex. It is held in a VARIABLE and applied with `[[ =~ $re ]]`:
    # an inline pattern with a `$'…'` would not survive the `declare -f` round
    # trip `build` performs, and a quoted right-hand side would be matched
    # literally. `kk.isInt` is NOT used — it strips the sign and folds `+0`/`-0`
    # into `0`, and `+N` is a different request from `N` for tail.
    local __tt_re='^[+-]?[0-9]+$'
    local __tt_d=''
    if [[ -n "$lines" ]]; then
        __tt_d="${lines#[+-]}"
        if [[ ! "$lines" =~ $__tt_re ]] || (( ${#__tt_d} > 19 )); then
            kk.debug "Error: TTail.buildArgv: lines '$lines' is not a count; tail takes [+-]?DIGITS of at most 19 digits (a suffix like 1K goes through addArg -n 1K)"
            kk._return ""
            return 2
        fi
    fi
    if [[ -n "$bytes" ]]; then
        __tt_d="${bytes#[+-]}"
        if [[ ! "$bytes" =~ $__tt_re ]] || (( ${#__tt_d} > 19 )); then
            kk.debug "Error: TTail.buildArgv: bytes '$bytes' is not a count; tail takes [+-]?DIGITS of at most 19 digits (a suffix like 2M goes through addArg -c 2M)"
            kk._return ""
            return 2
        fi
    fi

    # ---- the -z derivation -----------------------------------------------
    # `-z` re-delimits the INPUT by NUL and NUL-terminates the output records,
    # so the sinks must read NUL-framed records — but only the single-operand
    # shape reaches this line, because the headers of a multi-operand run stay
    # `\n`-terminated (refused above).
    #
    # `_nulDerived` records that WE set `nul`, which is what makes the
    # derivation idempotent: turning `zeroTerminated` back off takes the `-0`
    # off again, while a `nul = 1` the CALLER set is never touched. The inner
    # guard is tgrep's P3-F1: claim ownership only when we really set it, so the
    # three states stay distinct — derived (ours, undo it), caller-set (never
    # touch), and off. buildArgv mutates no other state.
    if [[ "$zeroTerminated" == 1 ]]; then
        if [[ "$nul" != 1 ]]; then
            nul=1
            _nulDerived=1
        fi
    elif [[ "$_nulDerived" == 1 ]]; then
        nul=0
        _nulDerived=0
    fi

    # ---- the argv, in the pinned order ------------------------------------
    __tt_v=( "$cmd" )
    if [[ "$quiet"          == 1 ]]; then __tt_v+=( -q ); fi
    if [[ "$verbose"        == 1 ]]; then __tt_v+=( -v ); fi
    if [[ "$zeroTerminated" == 1 ]]; then __tt_v+=( -z ); fi
    if [[ "$follow"         == 1 ]]; then __tt_v+=( -f ); fi
    if   [[ -n "$lines" ]]; then __tt_v+=( -n "$lines" )
    elif [[ -n "$bytes" ]]; then __tt_v+=( -c "$bytes" )
    fi

    # The un-modelled-option hatch, verbatim, after the options and before the
    # operands (`--` is what closes the option list). tail is last-flag-wins, so
    # an `addArg -n 5` here REPLACES `lines`.
    local -n __tt_a="${__inst__}_args"
    if (( ${#__tt_a[@]} > 0 )); then
        __tt_v+=( "${__tt_a[@]}" )
    fi

    # `--` only when there IS an operand: with none, tail reads stdin, and a
    # trailing `--` alone would make tail read stdin anyway but says something
    # the caller did not.
    if (( ${#__tt_p[@]} > 0 )); then
        __tt_v+=( -- "${__tt_p[@]}" )
    fi

    kk._return "${#__tt_v[@]}"
    return 0
}

# mapRc RAW — the override. tail's own table is two-valued:
#
#   0  everything asked for was delivered          -> 0
#   1  ANY failure: a missing or unreadable file, a bad or overflowing count, an
#      unknown option — INCLUDING a partial failure that still printed the good
#      operands' records                           -> 1, one kk.debug line
#
# 127 cannot normally reach here (`run` and every sink pre-check the command),
# but it keeps the base class's wording if it ever does.
TTail.mapRc() {
    local __tt_raw="${1:-}"
    if [[ "$__tt_raw" == "0" ]]; then
        kk._return "0"
        return 0
    fi
    if [[ "$__tt_raw" == "127" ]]; then
        kk.debug "Error: TTail.mapRc: command not found (raw rc 127)"
        kk._return "1"
        return 0
    fi
    kk.debug "Error: TTail.mapRc: tail exited $__tt_raw (a missing or unreadable operand, or a count the tool refused); records that did arrive are kept"
    kk._return "1"
    return 0
}

# ---------------------------------------------------------------------------
# The three sinks `follow` makes impossible (PLAN §2.1)
#
# `toArray` and `count` can only finish at EOF, and `tail -f` never reaches one.
# `toList` could in principle finish if the target's `.Add` called `TPipe.stop`,
# but no kcl list does, so it joins them. The refusal lives HERE, not in
# `buildArgv`: `buildArgv` does not know which member called it (the critic
# measured `tutil._prep`'s `__tu_m` unset on the `argv`/`run` paths), and
# `t.argv V` must still be able to show the `-f`.
#
# The spelling is not negotiable. `build` compiles a `kk._return "$RESULT"`
# trailer onto every `func`, and an explicit `return` is the only way past it —
# a body that merely ENDS on `inherited toArray "$@"` answers rc 0 where the
# base answered 1, and the caller's own RESULT comes back. So each override
# captures the rc, saves RESULT immediately (`inherited` leaves it, but anything
# after would overwrite it), and re-raises both.
# ---------------------------------------------------------------------------

TTail.toArray() {
    if [[ "$follow" == 1 ]]; then
        kk.debug "Error: TTail.toArray: cannot finish with follow = 1 (tail -f never reaches EOF); use each with a stopping callback, first, or run"
        kk._return ""
        return 2
    fi
    local __tt_rc=0
    inherited toArray "$@" || __tt_rc=$?
    local __tt_n="$RESULT"
    kk._return "$__tt_n"
    return "$__tt_rc"
}

TTail.toList() {
    if [[ "$follow" == 1 ]]; then
        kk.debug "Error: TTail.toList: cannot finish with follow = 1 (tail -f never reaches EOF, and no kcl list's .Add calls TPipe.stop); use each with a stopping callback, first, or run"
        kk._return ""
        return 2
    fi
    local __tt_rc=0
    inherited toList "$@" || __tt_rc=$?
    local __tt_n="$RESULT"
    kk._return "$__tt_n"
    return "$__tt_rc"
}

TTail.count() {
    if [[ "$follow" == 1 ]]; then
        kk.debug "Error: TTail.count: cannot finish with follow = 1 (tail -f never reaches EOF); use each with a stopping callback, first, or run"
        kk._return ""
        return 2
    fi
    local __tt_rc=0
    inherited count "$@" || __tt_rc=$?
    local __tt_n="$RESULT"
    kk._return "$__tt_n"
    return "$__tt_rc"
}

# take N PATH... — the one-liner: `tail -n N -- PATH...` as a STREAM, with the rc
# mapped. A `static proc`: it prints the tool's stdout, has no return channel,
# and never calls `kk._return`.
#
#     TTail.take 20 build.log                   # straight to the terminal
#     TTail.take +2 data.csv                    # skip the header row
#     TTail.take 20 build.log | TPipe.each cb   # lastpipe
#     TPipe.each cb -- TTail.take 20 build.log  # the safe `--` form
#
# At least ONE path is required: with none tail would read the CALLER's stdin,
# which no caller means by accident — that is rc 2 and nothing runs. A caller who
# wants stdin, or any option at all (`follow` included), builds an instance. Tool
# parity is kept: with two or more paths the `==> NAME <==` headers are in the
# stream.
#
# The throw-away instance is named `__tt_t_${BASHPID}_${__TT_SEQ}`: a fixed name
# is deleted out from under an outer `take` by a nested one.
TTail.take() {
    if (( $# < 2 )); then
        kk.debug "Error: TTail.take: usage: TTail.take N PATH... — at least one path is required (with none tail would read the caller's stdin); build an instance for the stdin form"
        return 2
    fi
    local __tt_re='^[+-]?[0-9]+$'
    local __tt_d="${1#[+-]}"
    if [[ ! "$1" =~ $__tt_re ]] || (( ${#__tt_d} > 19 )); then
        kk.debug "Error: TTail.take: N '$1' is not a count; tail takes [+-]?DIGITS of at most 19 digits"
        return 2
    fi
    __TT_SEQ=$(( __TT_SEQ + 1 ))
    local __tt_i="__tt_t_${BASHPID}_${__TT_SEQ}"
    TTail.new "$__tt_i" "$@"
    local __tt_rc=0
    "$__tt_i".run || __tt_rc=$?
    "$__tt_i".delete
    return "$__tt_rc"
}

# Finalize: extract the bodies above into the `TTail` class and generate the
# per-instance wrappers.
build TTail
