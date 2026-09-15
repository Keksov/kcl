#!/bin/bash

# Re-source guard: the class only needs to be built once per process
# (kcl/README.md §1.4 — the guard reads the flag with `:-` so `set -u` is happy).
if [[ -n "${_THEAD_SOURCED:-}" ]]; then
    return
fi
declare -g _THEAD_SOURCED=1

# Locale self-heal (kcl/README.md §1.6). A path and the bytes head emits are
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
# `${BASH_SOURCE[0]}`. Nothing else is sourced — in particular NOT `ttail.sh`:
# the two units share their plan text and nothing else (PLAN header).
THEAD_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$THEAD_DIR/../tutil/tutil.sh"

# Monotonic sequence for `THead.take`'s throw-away instance name (PLAN §2.7). A
# FIXED name is deleted out from under an outer `take` by a nested one, so the
# name is `__th_t_${BASHPID}_${__TH_SEQ}`: BASHPID separates processes (a `$( )`
# or `<( )` producer is a different one), the counter separates calls inside a
# process. Same idiom as TGrep's `__TG_SEQ`.
declare -g __TH_SEQ=0

# ---------------------------------------------------------------------------
# THead — the GNU coreutils 8.32 `head` wrapper over TUtil.
#
#     source kcl/thead/thead.sh
#
#     THead.take 20 build.log              # the one-liner: `head -n 20`, streamed
#
#     THead.new h 20 a.log b.log           # or an instance, for options
#     h.quiet = 1                          # no `==> NAME <==` headers
#     h.each r.onLine                      # one call per record, THIS shell
#     h.toArray first20                    # RESULT = ${#first20[@]}
#     h.count                              # RESULT = how many
#     h.delete
#
# ---- The pinned argv (PLAN §1.2) ------------------------------------------
#   head [-q|-v] [-z] [-n N | -c N] [EXTRA ARGS from addArg] [-- PATH...]
#
# The order is this builder's, not the caller's. `--` appears only when there is
# at least one path (with none, head reads stdin, the documented stdin form).
# Booleans are the exact string `1`; anything else is off. Extras come LAST, and
# because head is last-flag-wins an `addArg -n`/`-c` REPLACES `lines`/`bytes` —
# the documented escape hatch for the suffix forms (`-n 1K`), PLAN §1.3.
#
# ---- The count (PLAN §2.2) ------------------------------------------------
# `lines` and `bytes` are validated with ONE regex, `^[+-]?[0-9]+$`, plus a
# magnitude guard of at most 19 digits, and passed to head VERBATIM. `kk.isInt`
# is deliberately NOT used: it normalises, and head reads the normalised value as
# a different request —
#
#   value | head -n            | tail -n (ttail)
#   ------+--------------------+---------------------------
#   N     | the first N        | the last N
#   +N    | the first N        | FROM line N
#   -N    | all but the last N | the last N
#   0/+0  | nothing            | 0/-0 nothing, +0 everything
#   -0    | EVERYTHING         | nothing
#
# so `kk.isInt` turning `-0` into `0` would swap "everything" for "nothing".
# `08` reaches head as `08` and head reads it as decimal 8.
#
# ---- rc 2 at buildArgv: nothing runs, one kk.debug line --------------------
#   * `cmd` empty (the instance was disarmed by hand);
#   * `lines` AND `bytes` (head would silently take the last one);
#   * `quiet` AND `verbose` (head accepts both, last flag wins — the answer
#     would depend on this builder's fixed order rather than on the caller);
#   * `zeroTerminated` with two or more paths, or with `verbose` (PLAN §2.3:
#     the `==> NAME <==` headers stay `\n`-terminated under `-z`, so a derived
#     `-0` would frame header + data into ONE record);
#   * a count that fails the regex or the 19-digit guard.
#
# ---- mapRc (PLAN §2.5) ----------------------------------------------------
# head has no "answer" rc: `0` is success and `1` is every failure — a missing
# file, a directory operand, an overflowing count, an unknown option. So
# `0 -> 0`, anything else `-> 1` with one `kk.debug` line (127 keeps the base
# wording). Two named deviations this family already carries:
#   (a) a PARTIAL failure (`head -n 1 a missing`) prints a's records and exits 1;
#       the sinks keep every record that arrived and RESULT is the REAL count;
#   (b) head's own stderr is unconditional and its quoting follows the locale —
#       it is the TOOL's stream and passes through untouched.
#
# ---- Headers are records (PLAN §2.4) --------------------------------------
# With two or more operands and neither `-q` nor `-v`, head writes
# `\n==> NAME <==\n` before every operand after the first. Through the sinks
# those are ordinary records, and the leading `\n` is an EMPTY record only when
# the previous file's last line was terminated: two terminated 3-line files under
# `-n 5` are 9 records, the same pair with the first unterminated is 8.
#
# ---- Text mode and the CR (PLAN §2.6) -------------------------------------
# head is a BYTE tool: it keeps the CR (unlike grep/sed/gawk, which open input in
# text mode on this platform). This is the wrapper where TUtil's `crlf = 1`
# finally does something — it strips exactly one trailing CR per record, in bytes
# mode too.
#
# ---- Traps this unit is written around ------------------------------------
#  * The constructor calls `parent.constructor head` EXPLICITLY. `inherited` in
#    a constructor body is rewritten to `parent.constructor "$@"`
#    (kklass_pascal.sh:166) and would hand TUtil `cmd=N` plus every path as an
#    extra argument — every path would then appear twice in the argv.
#  * EVERY declared var is assigned in `Create`: kklass binds a property as a
#    nameref onto `${inst}_data[NAME]`, an unassigned one is an unbound variable
#    under `set -u`, and `.new` over a still-live instance does not clear
#    `_data`.
#  * No `var` here may be named like a TUtil member (`cmd crlf nul _lastRc
#    subshellOk buildArgv addArg clearArgs argv run each toArray toList first
#    count lastRc mapRc`) or a kklass one (`property call parent delete`): the
#    method wrapper is generated after the property wrapper and wins silently.
#    That is why the count properties are `lines`/`bytes` and never
#    `count`/`first`.
#  * Booleans are compared as strings (`[[ "$x" == 1 ]]`); `(( x ))` on a
#    non-numeric property is 0 in silence, or an arithmetic injection.
#  * The count regex lives in a VARIABLE and is applied with `[[ =~ $re ]]`;
#    an inline `$'…'` in a member body does not survive `build`'s `declare -f`
#    round trip.
#  * A `func` that answers both a value and a non-zero rc ends with
#    `kk._return V; return N`.
#  * `${inst}_argv` is rebuilt through a nameref (`local -n a=…; a=()`), never
#    with `unset "${inst}_argv[…]"`.
#  * `__th_` is registered in `tutil._badOut` (PLAN §2.8): bash scopes locals
#    DYNAMICALLY, so a caller array named `__th_v` would bind this unit's own
#    scratch nameref.
# ---------------------------------------------------------------------------
class THead : TUtil
    public
        var lines           # -n N   ('' = off -> head's own default of 10)
        var bytes           # -c N   ('' = off); with `lines` -> rc 2
        var quiet           # -q     never print the file-name headers
        var verbose         # -v     always print them; with `quiet` -> rc 2
        var zeroTerminated  # -z     NUL INPUT records; derives the sinks' -0
        var _nulDerived     # private bookkeeping for the §2.3 derivation
        constructor Create  # [N [PATH...]] — N becomes `lines`
        destructor  Destroy # frees ${inst}_paths, then inherited
        proc paths          # PATH... — REPLACES the operand list
        override func buildArgv
        override func mapRc
        static proc take    # N PATH... — `head -n N -- PATH...`, streamed
end

# ===========================================================================
# Members
# ===========================================================================

# Create [N [PATH...]] — PLAN §2.1.
#
# `parent.constructor head` is spelled out: `inherited` would forward THIS
# constructor's arguments to TUtil and make `cmd` the count while every path
# became a TUtil extra arg — each path would then appear twice. After it, EVERY
# declared var is assigned (booleans `0`, strings `''`), and the operand list
# becomes a real global array next to `${inst}_data`, released by the destructor
# (kcl/README.md §1.9).
THead.Create() {
    parent.constructor head
    lines="${1:-}"
    bytes=''
    quiet=0
    verbose=0
    zeroTerminated=0
    _nulDerived=0
    declare -ga "${__inst__}_paths=()"
    local -n __th_p="${__inst__}_paths"
    __th_p=( "${@:2}" )
    return 0
}

# Destroy — release this class's own array, then chain. `inherited` in a
# DESTRUCTOR is the ordinary parent call (the rewrite that bites constructors
# does not apply), and TUtil.Destroy releases `${inst}_args` and `${inst}_argv`.
# `unset -v` on a name that does not exist is rc 0, so a half-built instance
# tears down cleanly too.
THead.Destroy() {
    unset -v "${__inst__}_paths"
    inherited
    return 0
}

# paths PATH... — REPLACE the operand list. With no arguments the list becomes
# empty and the built argv carries no `--` at all, which is head's stdin form:
# `h.paths; printf 'a\nb\n' | h.run`.
THead.paths() {
    local -n __th_p="${__inst__}_paths"
    __th_p=( "$@" )
    return 0
}

# buildArgv — the override, and the single truth about what will run. `run` and
# all five sinks reach it through `kk.call_silent`, which dispatches VIRTUALLY,
# so this body is what they get.
#
# RESULT = the number of words, rc 0. On any refusal: `kk._return ""`, rc 2, one
# `kk.debug` line naming the reason, `${inst}_argv` left EMPTY so no stale
# command line can be executed afterwards, and the caller runs nothing.
THead.buildArgv() {
    local -n __th_v="${__inst__}_argv"
    local -n __th_p="${__inst__}_paths"
    __th_v=()

    # ---- the rc 2 list, checked before a single word is built -------------
    if [[ -z "$cmd" ]]; then
        kk.debug "Error: THead.buildArgv: cmd is empty; there is nothing to run"
        kk._return ""
        return 2
    fi
    if [[ -n "$lines" && -n "$bytes" ]]; then
        kk.debug "Error: THead.buildArgv: lines (-n) and bytes (-c) are mutually exclusive; head takes both and the last one silently wins"
        kk._return ""
        return 2
    fi
    if [[ "$quiet" == 1 && "$verbose" == 1 ]]; then
        kk.debug "Error: THead.buildArgv: quiet (-q) and verbose (-v) are mutually exclusive; head takes both and the answer would depend on this builder's order"
        kk._return ""
        return 2
    fi
    if [[ "$zeroTerminated" == 1 ]] && (( ${#__th_p[@]} > 1 )); then
        kk.debug "Error: THead.buildArgv: zeroTerminated (-z) with ${#__th_p[@]} paths; the \`==> NAME <==\` headers stay newline-terminated under -z, so the derived -0 would frame a header and its file into ONE record — use one path, or set quiet and run the files separately"
        kk._return ""
        return 2
    fi
    if [[ "$zeroTerminated" == 1 && "$verbose" == 1 ]]; then
        kk.debug "Error: THead.buildArgv: zeroTerminated (-z) with verbose (-v); a forced \`==> NAME <==\` header is newline-terminated and would be framed into the file's own NUL record"
        kk._return ""
        return 2
    fi

    # The count regex (PLAN §2.2). It is held in a VARIABLE and applied with
    # `[[ =~ $re ]]`: an inline pattern with a `$'…'` would not survive the
    # `declare -f` round trip `build` performs, and a quoted right-hand side
    # would be matched literally. `kk.isInt` is NOT used — it strips the sign
    # and folds `+0`/`-0` into `0`, and head reads those as opposite requests.
    local __th_re='^[+-]?[0-9]+$'
    local __th_d=''
    if [[ -n "$lines" ]]; then
        __th_d="${lines#[+-]}"
        if [[ ! "$lines" =~ $__th_re ]] || (( ${#__th_d} > 19 )); then
            kk.debug "Error: THead.buildArgv: lines '$lines' is not a count; head takes [+-]?DIGITS of at most 19 digits (a suffix like 1K goes through addArg -n 1K)"
            kk._return ""
            return 2
        fi
    fi
    if [[ -n "$bytes" ]]; then
        __th_d="${bytes#[+-]}"
        if [[ ! "$bytes" =~ $__th_re ]] || (( ${#__th_d} > 19 )); then
            kk.debug "Error: THead.buildArgv: bytes '$bytes' is not a count; head takes [+-]?DIGITS of at most 19 digits (a suffix like 2M goes through addArg -c 2M)"
            kk._return ""
            return 2
        fi
    fi

    # ---- the §2.3 derivation ---------------------------------------------
    # `-z` re-delimits the INPUT by NUL and NUL-terminates the output records,
    # so the sinks must read NUL-framed records — but only the single-operand
    # shape reaches this line, because the headers of a multi-operand run stay
    # `\n`-terminated (refused above).
    #
    # `_nulDerived` records that WE set `nul`, which is what makes the
    # derivation idempotent: turning `zeroTerminated` back off takes the `-0`
    # off again, while a `nul = 1` the CALLER set (for a framing this wrapper
    # does not model) is never touched. buildArgv mutates no other state.
    #
    # The inner guard is tgrep's P3-F1: claiming ownership whenever the
    # CONDITION held — even when `nul` was already 1 because the caller set it —
    # made the undo one condition too coarse, and a later build that stopped
    # deriving cleared the caller's own `nul`. We claim it only when we really
    # set it, so the three states stay distinct: derived (ours, undo it),
    # caller-set (never touch), and off.
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
    __th_v=( "$cmd" )
    if [[ "$quiet"          == 1 ]]; then __th_v+=( -q ); fi
    if [[ "$verbose"        == 1 ]]; then __th_v+=( -v ); fi
    if [[ "$zeroTerminated" == 1 ]]; then __th_v+=( -z ); fi
    if   [[ -n "$lines" ]]; then __th_v+=( -n "$lines" )
    elif [[ -n "$bytes" ]]; then __th_v+=( -c "$bytes" )
    fi

    # The un-modelled-option hatch, verbatim, after the options and before the
    # operands (`--` is what closes the option list). head is last-flag-wins, so
    # an `addArg -n 5` here REPLACES `lines` — documented, PLAN §1.3.
    local -n __th_a="${__inst__}_args"
    if (( ${#__th_a[@]} > 0 )); then
        __th_v+=( "${__th_a[@]}" )
    fi

    # `--` only when there IS an operand: with none, head reads stdin, and a
    # trailing `--` alone would make head read stdin anyway but says something
    # the caller did not.
    if (( ${#__th_p[@]} > 0 )); then
        __th_v+=( -- "${__th_p[@]}" )
    fi

    kk._return "${#__th_v[@]}"
    return 0
}

# mapRc RAW — the override (PLAN §2.5). head's own table is two-valued:
#
#   0  everything asked for was delivered          -> 0
#   1  ANY failure: a missing or unreadable file, a directory operand, a bad or
#      overflowing count, an unknown option — INCLUDING a partial failure that
#      still printed the good operands' records -> 1, one kk.debug line
#
# 127 cannot normally reach here (`run` and every sink pre-check the command),
# but it keeps the base class's wording if it ever does.
#
# rc 1 STILL delivers records when one operand of many failed; the sinks keep
# every record that arrived and their RESULT is the real count. This member only
# decides the member's exit status and writes the diagnostic.
THead.mapRc() {
    local __th_raw="${1:-}"
    if [[ "$__th_raw" == "0" ]]; then
        kk._return "0"
        return 0
    fi
    if [[ "$__th_raw" == "127" ]]; then
        kk.debug "Error: THead.mapRc: command not found (raw rc 127)"
        kk._return "1"
        return 0
    fi
    kk.debug "Error: THead.mapRc: head exited $__th_raw (a missing or unreadable operand, a directory operand, or a count the tool refused); records that did arrive are kept"
    kk._return "1"
    return 0
}

# take N PATH... — the one-liner (PLAN §2.7): `head -n N -- PATH...` as a
# STREAM, with the rc mapped. A `static proc`: it prints the tool's stdout, has
# no return channel, and never calls `kk._return`.
#
#     THead.take 20 build.log                   # straight to the terminal
#     THead.take 20 build.log | TPipe.each cb   # lastpipe
#     TPipe.each cb -- THead.take 20 build.log  # the safe `--` form
#
# At least ONE path is required: with none head would read the CALLER's stdin
# (tpipe PLAN §1.3), which no caller means by accident — that is rc 2 and
# nothing runs. A caller who wants stdin, or any option at all, builds an
# instance. Tool parity is kept: with two or more paths the `==> NAME <==`
# headers are in the stream.
#
# The throw-away instance is named `__th_t_${BASHPID}_${__TH_SEQ}`: a fixed name
# is deleted out from under an outer `take` by a nested one (one started from
# inside the callback of an outer sink). Cost: one construction per call.
THead.take() {
    if (( $# < 2 )); then
        kk.debug "Error: THead.take: usage: THead.take N PATH... — at least one path is required (with none head would read the caller's stdin); build an instance for the stdin form"
        return 2
    fi
    local __th_re='^[+-]?[0-9]+$'
    local __th_d="${1#[+-]}"
    if [[ ! "$1" =~ $__th_re ]] || (( ${#__th_d} > 19 )); then
        kk.debug "Error: THead.take: N '$1' is not a count; head takes [+-]?DIGITS of at most 19 digits"
        return 2
    fi
    __TH_SEQ=$(( __TH_SEQ + 1 ))
    local __th_i="__th_t_${BASHPID}_${__TH_SEQ}"
    THead.new "$__th_i" "$@"
    local __th_rc=0
    "$__th_i".run || __th_rc=$?
    "$__th_i".delete
    return "$__th_rc"
}

# Finalize: extract the bodies above into the `THead` class and generate the
# per-instance wrappers.
build THead
