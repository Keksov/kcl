#!/bin/bash

# Re-source guard: the class only needs to be built once per process
# (kcl/README.md §1.4 — the guard reads the flag with `:-` so `set -u` is happy).
if [[ -n "${_TFIND_SOURCED:-}" ]]; then
    return
fi
declare -g _TFIND_SOURCED=1

# Locale self-heal (kcl/README.md §1.6). A path and the bytes find emits are
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
# `${BASH_SOURCE[0]}`. It is the ONLY `source` line in the unit.
TFIND_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$TFIND_DIR/../tutil/tutil.sh"

# Register this unit's local prefix in TUtil's out-name registry (PLAN §2.6).
# Bash scopes locals DYNAMICALLY, so a caller array named `__tfd_v` or `__tfd_p`
# would bind the scratch nameref a member body below holds. The append is
# idempotent — `+=` on every load would grow the registry without bound if the
# guard above were ever lifted — and the two scratch globals are released right
# after, so the unit leaves exactly `_TFIND_SOURCED`, `TFIND_DIR` and
# `__TFD_SEQ` behind.
declare -g __tfd_seen=0
declare -g __tfd_p=''
for __tfd_p in "${TUTIL_OUT_PREFIXES[@]}"; do
    if [[ "$__tfd_p" == "__tfd_" ]]; then
        __tfd_seen=1
    fi
done
if [[ "$__tfd_seen" != "1" ]]; then
    TUTIL_OUT_PREFIXES+=( __tfd_ )
fi
unset -v __tfd_seen __tfd_p

# Monotonic sequence for `TFind.byName`'s throw-away instance name (PLAN §2.5).
# A FIXED name is deleted out from under an outer `byName` by a nested one, so
# the name is `__tfd_b_${BASHPID}_${__TFD_SEQ}`: BASHPID separates processes (a
# `$( )` or `<( )` producer is a different one), the counter separates calls
# inside a process. Same idiom as TGrep's `__TG_SEQ`.
declare -g __TFD_SEQ=0

# ---------------------------------------------------------------------------
# TFind — the GNU findutils 4.10.0 `find` wrapper over TUtil.
#
#     source kcl/tfind/tfind.sh
#
#     TFind.byName '*.log' /var/log        # the one-liner, streamed
#
#     TFind.new f src                      # or an instance, for options
#     f.name = '*.c'                       # ALWAYS quote the pattern (§2.2)
#     f.type = f
#     f.maxDepth = 3
#     f.print0 = 1                         # -print0 + the sinks' -0
#     f.each r.onPath                      # one call per record, THIS shell
#     f.toArray sources                    # RESULT = ${#sources[@]}
#     f.count                              # RESULT = how many
#     f.delete
#
# ---- The pinned argv (PLAN §1.2) ------------------------------------------
#   find [-L] [START...] [-maxdepth N] [-mindepth N] [-name P] [-iname P]
#        [-type T] [-newer F] [EXTRA ARGS from addArg] [-print0]
#
# find's grammar is the REVERSE of grep's and head's: the start points come
# FIRST and the expression after them. Consequences this unit is built around:
#
#  * `-L` is accepted only BEFORE the start points (`find tree -L` is "unknown
#    predicate"), which is why `followSymlinks` is a typed property and an
#    `addArg -L` would land in the wrong place;
#  * `--` is NOT emitted, ever. It ends the OPTION list (`-H/-L/-P`,
#    `--version`) and does nothing for a start point: `find -- -weird` is still
#    "unknown predicate", rc 1. A start point that is empty or begins with `-`,
#    `!` or `(` is therefore this wrapper's rc 2 (§2.1); `./-weird` works, and
#    `)` and `,` are fine;
#  * extras land in the expression, AFTER the typed tests and BEFORE the action:
#    `addArg -size +1M`, `addArg -mtime -1`, `addArg '!' -name x`,
#    `addArg '(' -name a -o -name b ')'`.
#
# ---- The typed values (PLAN §2.2) -----------------------------------------
# `name` / `iname` / `newer` are ONE argv element each and are never expanded by
# the wrapper. The trap is on the CALLER's side: `f.name = *.txt` unquoted
# expands at the call site and the property setter silently keeps the first
# word. Always `f.name = '*.txt'`.
#
# `type` is validated with `^[bcdflps](,[bcdflps])*$`. A duplicate list like
# `f,f` passes that regex and is the TOOL's rc 1 — parity, documented.
#
# `maxDepth` / `minDepth` go through `kk.isInt` + `>= 0` and are emitted from
# `$__KK_INT`, the NORMALISED value: `08` -> 8 and `+1` -> 1, because a verbatim
# `+1` is find's own rc 1 ("Expected a positive decimal integer … got '+1'").
# This is the opposite decision from thead/ttail, where the sign is meaning and
# `kk.isInt` is forbidden. A depth above INT_MAX passes the guard and is the
# tool's rc 1 (parity). `minDepth > maxDepth` is not refused — find answers
# nothing, rc 0.
#
# ---- rc 2 at buildArgv: nothing runs, one kk.debug line --------------------
#   * `cmd` empty (the instance was disarmed by hand);
#   * a start point that is EMPTY or begins with `-`, `!` or `(`;
#   * `type` outside the regex;
#   * `maxDepth`/`minDepth` that is not an integer, or is negative;
#   * `print0 = 1` together with an ACTION word among the extras (§2.3).
#
# ---- `print0` derives `-0` and excludes every other action (PLAN §2.3) -----
# `print0 = 1` makes `-print0` THE action and derives `nul = 1` for the sinks
# (with the P3-F1 guard below). With it, an extra from `addArg` that is an
# action — `-print -print0 -printf -fprint -fprint0 -fprintf -ls -fls -exec
# -execdir -ok -okdir -delete -quit` — is rc 2: measured, two actions interleave
# into ONE corrupted NUL record (`X:./a.txt\n./a.txt\0`), and an `-exec` that
# exits non-zero short-circuits the AND chain so `-print0` never fires — rc 0,
# zero records, no diagnostic. A caller who wants a hand-built action keeps
# `print0 = 0` and sets `nul` itself if the framing calls for it.
#
# ---- mapRc (PLAN §2.4) ----------------------------------------------------
# find has no "answer" rc: `0` is success and `1` is every failure. So `0 -> 0`,
# anything else `-> 1` with one `kk.debug` line (127 keeps the base wording).
# THREE named deviations:
#   (a) a missing start point among good ones still prints the good ones — the
#       records are delivered, RESULT is the REAL count, rc 1;
#   (b) find's own stderr is unconditional and locale-quoted — it is the TOOL's
#       stream and passes through untouched (tests match a PREFIX);
#   (c) `-exec CMD {} \;` whose command fails or is missing leaves find at rc 0
#       (stderr only); the `{} +` form propagates the failure as rc 1. A caller
#       who needs the child's status in `lastRc` uses `{} +`.
# `-newer MISSING` is a FATAL rc 1 with no records at all — not (a).
#
# ---- Traps this unit is written around ------------------------------------
#  * The constructor calls `parent.constructor find` EXPLICITLY. `inherited` in
#    a constructor body is rewritten to `parent.constructor "$@"`
#    (kklass_pascal.sh:166) and would hand TUtil `cmd=START` plus every other
#    start point as an extra argument — each would then appear twice.
#  * EVERY declared var is assigned in `Create`: kklass binds a property as a
#    nameref onto `${inst}_data[NAME]`, an unassigned one is an unbound variable
#    under `set -u`, and `.new` over a still-live instance does not clear
#    `_data`.
#  * No `var` here may be named like a TUtil member (`cmd crlf nul _lastRc
#    subshellOk buildArgv addArg clearArgs argv run each toArray toList first
#    count lastRc mapRc`) or a kklass one (`property call parent delete`): the
#    method wrapper is generated after the property wrapper and wins silently.
#    `type` is safe — it is a VARIABLE name and the `type` builtin lives in a
#    different namespace (verified on both bashes).
#  * The start-point class is `[-!\(]*`. `[!-(]*` is a NEGATED class and would
#    silently stop refusing `-x`; the `-` must stay first.
#  * Booleans are compared as strings (`[[ "$x" == 1 ]]`); `(( x ))` on a
#    non-numeric property is 0 in silence, or an arithmetic injection.
#  * The `type` regex lives in a VARIABLE and is applied with `[[ =~ $re ]]`;
#    an inline pattern does not survive `build`'s `declare -f` round trip.
#  * A `func` that answers both a value and a non-zero rc ends with
#    `kk._return V; return N`.
#  * `${inst}_argv` is rebuilt through a nameref (`local -n a=…; a=()`), never
#    with `unset "${inst}_argv[…]"`.
#  * `__tfd_` is in `TUTIL_OUT_PREFIXES` (PLAN §2.6).
# ---------------------------------------------------------------------------
class TFind : TUtil
    public
        var name            # -name PATTERN   ('' = off; ONE argv element)
        var iname           # -iname PATTERN  ('' = off)
        var type            # -type T, T = [bcdflps](,[bcdflps])*  ('' = off)
        var maxDepth        # -maxdepth N  (kk.isInt, >= 0, emitted as $__KK_INT)
        var minDepth        # -mindepth N  (same)
        var newer           # -newer FILE ('' = off; a missing FILE is FATAL rc 1)
        var followSymlinks  # 1 -> -L, emitted BEFORE the start points
        var print0          # 1 -> -print0 as THE action; derives the sinks' -0
        var _nulDerived     # private bookkeeping for the §2.3 derivation
        constructor Create  # [START...] — every argument is a start point
        destructor  Destroy # frees ${inst}_paths, then inherited
        proc paths          # START... — REPLACES the start-point list
        override func buildArgv
        override func mapRc
        static proc byName  # PATTERN START... — `find START... -name PATTERN`
end

# ===========================================================================
# Members
# ===========================================================================

# Create [START...] — PLAN §1.2.
#
# `parent.constructor find` is spelled out: `inherited` would forward THIS
# constructor's arguments to TUtil and make `cmd` the first start point while
# the rest became TUtil extras — every one would then appear twice. After it,
# EVERY declared var is assigned (booleans `0`, strings `''`), and the
# start-point list becomes a real global array next to `${inst}_data`, released
# by the destructor (kcl/README.md §1.9).
TFind.Create() {
    parent.constructor find
    name=''
    iname=''
    type=''
    maxDepth=''
    minDepth=''
    newer=''
    followSymlinks=0
    print0=0
    _nulDerived=0
    declare -ga "${__inst__}_paths=()"
    local -n __tfd_p="${__inst__}_paths"
    __tfd_p=( "$@" )
    return 0
}

# Destroy — release this class's own array, then chain. `inherited` in a
# DESTRUCTOR is the ordinary parent call (the rewrite that bites constructors
# does not apply), and TUtil.Destroy releases `${inst}_args` and `${inst}_argv`.
# `unset -v` on a name that does not exist is rc 0, so a half-built instance
# tears down cleanly too.
TFind.Destroy() {
    unset -v "${__inst__}_paths"
    inherited
    return 0
}

# paths START... — REPLACE the start-point list. With NO argument the list
# becomes empty and the built argv carries no start point at all, which is
# find's own `.`: the records then read `./…` and are relative to the CALLER's
# working directory (`f.paths; f.toArray recs`).
TFind.paths() {
    local -n __tfd_p="${__inst__}_paths"
    __tfd_p=( "$@" )
    return 0
}

# buildArgv — the override, and the single truth about what will run. `run` and
# all five sinks reach it through `kk.call_silent`, which dispatches VIRTUALLY,
# so this body is what they get.
#
# RESULT = the number of words, rc 0. On any refusal: `kk._return ""`, rc 2, one
# `kk.debug` line naming the reason, `${inst}_argv` left EMPTY so no stale
# command line can be executed afterwards, and the caller runs nothing.
TFind.buildArgv() {
    local -n __tfd_v="${__inst__}_argv"
    local -n __tfd_p="${__inst__}_paths"
    local -n __tfd_a="${__inst__}_args"
    __tfd_v=()

    # ---- the rc 2 list, checked before a single word is built -------------
    if [[ -z "$cmd" ]]; then
        kk.debug "Error: TFind.buildArgv: cmd is empty; there is nothing to run"
        kk._return ""
        return 2
    fi

    # Start points are POSITIONAL and `--` cannot rescue one (§1.1): find reads
    # a leading `-`, `!` or `(` as the start of the EXPRESSION and answers
    # "unknown predicate", and an empty one is "'': No such file or directory".
    # The class is `[-!\(]*` — `[!-(]*` would be a NEGATED class and would
    # silently stop refusing anything.
    local __tfd_s
    for __tfd_s in "${__tfd_p[@]}"; do
        if [[ -z "$__tfd_s" ]]; then
            kk.debug "Error: TFind.buildArgv: an EMPTY start point; find reads it as \`'': No such file or directory\` — call \`paths\` with NO arguments for find's own \`.\`"
            kk._return ""
            return 2
        fi
        if [[ "$__tfd_s" == [-!\(]* ]]; then
            kk.debug "Error: TFind.buildArgv: the start point '$__tfd_s' begins with \`-\`, \`!\` or \`(\`; find reads it as the expression (\`--\` does NOT protect a start point) — spell it \`./$__tfd_s\`"
            kk._return ""
            return 2
        fi
    done

    # The `type` regex (PLAN §2.2). It is held in a VARIABLE and applied with
    # `[[ =~ $re ]]`: an inline pattern would not survive the `declare -f` round
    # trip `build` performs, and a quoted right-hand side would be matched
    # literally. A duplicate list (`f,f`) passes on purpose — that one is the
    # tool's own rc 1, and parity beats a second opinion.
    local __tfd_re='^[bcdflps](,[bcdflps])*$'
    if [[ -n "$type" ]]; then
        if [[ ! "$type" =~ $__tfd_re ]]; then
            kk.debug "Error: TFind.buildArgv: type '$type' is not a find type list; it must match ^[bcdflps](,[bcdflps])*$ (b c d f l p s, comma separated)"
            kk._return ""
            return 2
        fi
    fi

    # `kk.isInt` accepts a negative, and a negative depth is find's own rc 1, so
    # `>= 0` is a separate check. The NORMALISED value is read from `$__KK_INT`
    # (so `08` reaches find as `8` and `+1` as `1`); the OUTVAR form would write
    # through the property nameref and rewrite the caller's own value.
    local __tfd_max='' __tfd_min=''
    if [[ -n "$maxDepth" ]]; then
        if ! kk.isInt "$maxDepth"; then
            kk.debug "Error: TFind.buildArgv: maxDepth '$maxDepth' is not an integer"
            kk._return ""
            return 2
        fi
        __tfd_max="$__KK_INT"
        if [[ "${__tfd_max:0:1}" == "-" ]]; then
            kk.debug "Error: TFind.buildArgv: maxDepth '$maxDepth' is negative; find takes a positive decimal integer"
            kk._return ""
            return 2
        fi
    fi
    if [[ -n "$minDepth" ]]; then
        if ! kk.isInt "$minDepth"; then
            kk.debug "Error: TFind.buildArgv: minDepth '$minDepth' is not an integer"
            kk._return ""
            return 2
        fi
        __tfd_min="$__KK_INT"
        if [[ "${__tfd_min:0:1}" == "-" ]]; then
            kk.debug "Error: TFind.buildArgv: minDepth '$minDepth' is negative; find takes a positive decimal integer"
            kk._return ""
            return 2
        fi
    fi

    # §2.3. With `print0 = 1` the action is `-print0` and NOTHING else may be an
    # action: two of them both run and interleave into one corrupted NUL record,
    # and an `-exec` that exits non-zero short-circuits the AND chain so
    # `-print0` never fires (rc 0, zero records, no diagnostic). The whole
    # extras list is scanned, and the match is on the WHOLE word.
    if [[ "$print0" == 1 ]] && (( ${#__tfd_a[@]} > 0 )); then
        local __tfd_w
        for __tfd_w in "${__tfd_a[@]}"; do
            case "$__tfd_w" in
                -print|-print0|-printf|-fprint|-fprint0|-fprintf|-ls|-fls|-exec|-execdir|-ok|-okdir|-delete|-quit)
                    kk.debug "Error: TFind.buildArgv: print0 = 1 together with the action '$__tfd_w' in the extras; find runs BOTH actions and their output interleaves into one corrupted NUL record (and a failing -exec short-circuits -print0 away) — set print0 = 0 and let the extra's output be the record stream, or drop the extra"
                    kk._return ""
                    return 2
                    ;;
            esac
        done
    fi

    # ---- the §2.3 derivation ---------------------------------------------
    # `-print0` NUL-terminates every record, so the sinks must read NUL-framed
    # records. find has no headers, so there is no exception to make.
    #
    # `_nulDerived` records that WE set `nul`, which is what makes the
    # derivation idempotent: turning `print0` back off takes the `-0` off again,
    # while a `nul = 1` the CALLER set (for a framing this wrapper does not
    # model, e.g. a hand-built `addArg -print0 -quit`) is never touched.
    # buildArgv mutates no other state.
    #
    # The inner guard is tgrep's P3-F1: claiming ownership whenever the
    # CONDITION held — even when `nul` was already 1 because the caller set it —
    # made the undo one condition too coarse, and a later build that stopped
    # deriving cleared the caller's own `nul`. We claim it only when we really
    # set it, so the three states stay distinct: derived (ours, undo it),
    # caller-set (never touch), and off.
    if [[ "$print0" == 1 ]]; then
        if [[ "$nul" != 1 ]]; then
            nul=1
            _nulDerived=1
        fi
    elif [[ "$_nulDerived" == 1 ]]; then
        nul=0
        _nulDerived=0
    fi

    # ---- the argv, in the pinned order ------------------------------------
    # `-L` first (it is only accepted before the start points), then the start
    # points verbatim, then the global options, the typed tests, the extras and
    # the action. No `--` anywhere.
    __tfd_v=( "$cmd" )
    if [[ "$followSymlinks" == 1 ]]; then __tfd_v+=( -L ); fi
    if (( ${#__tfd_p[@]} > 0 )); then __tfd_v+=( "${__tfd_p[@]}" ); fi
    if [[ -n "$__tfd_max" ]]; then __tfd_v+=( -maxdepth "$__tfd_max" ); fi
    if [[ -n "$__tfd_min" ]]; then __tfd_v+=( -mindepth "$__tfd_min" ); fi
    if [[ -n "$name"  ]]; then __tfd_v+=( -name  "$name"  ); fi
    if [[ -n "$iname" ]]; then __tfd_v+=( -iname "$iname" ); fi
    if [[ -n "$type"  ]]; then __tfd_v+=( -type  "$type"  ); fi
    if [[ -n "$newer" ]]; then __tfd_v+=( -newer "$newer" ); fi
    if (( ${#__tfd_a[@]} > 0 )); then __tfd_v+=( "${__tfd_a[@]}" ); fi
    if [[ "$print0" == 1 ]]; then __tfd_v+=( -print0 ); fi

    kk._return "${#__tfd_v[@]}"
    return 0
}

# mapRc RAW — the override (PLAN §2.4). find's own table is two-valued:
#
#   0  everything asked for was traversed and printed        -> 0
#   1  ANY failure: a missing or unreadable start point, a predicate the tool
#      refused (a bad depth, a duplicate `-type` list), a `-newer` reference
#      that does not exist, an `-exec … {} +` whose command failed —
#      INCLUDING a partial failure that still printed the good start points'
#      records                                               -> 1, one debug line
#
# `-exec CMD {} \;` is the documented exception in the other direction: a
# failing or missing CMD leaves find at rc 0 (deviation (c)).
#
# 127 cannot normally reach here (`run` and every sink pre-check the command),
# but it keeps the base class's wording if it ever does.
TFind.mapRc() {
    local __tfd_raw="${1:-}"
    if [[ "$__tfd_raw" == "0" ]]; then
        kk._return "0"
        return 0
    fi
    if [[ "$__tfd_raw" == "127" ]]; then
        kk.debug "Error: TFind.mapRc: command not found (raw rc 127)"
        kk._return "1"
        return 0
    fi
    kk.debug "Error: TFind.mapRc: find exited $__tfd_raw (a missing or unreadable start point, a predicate the tool refused, or a failing -exec … {} +); records that did arrive are kept"
    kk._return "1"
    return 0
}

# byName PATTERN START... — the one-liner (PLAN §2.5):
# `find START... -name PATTERN` as a STREAM, with the rc mapped. A
# `static proc`: it prints the tool's stdout, has no return channel, and never
# calls `kk._return`.
#
#     TFind.byName '*.log' /var/log                  # straight to the terminal
#     TFind.byName '*.log' /var/log | TPipe.each cb  # lastpipe
#     TPipe.each cb -- TFind.byName '*.log' /var/log # the safe `--` form
#
# At least ONE start point is required: with none find would search the CALLER's
# working directory, which no caller means by accident in a one-liner — that is
# rc 2 and nothing runs. A caller who wants the cwd form, or any option at all,
# builds an instance. The implied `-print` is what streams, so a record is
# newline framed; quote the pattern at the call site (§2.2).
#
# The throw-away instance is named `__tfd_b_${BASHPID}_${__TFD_SEQ}`: a fixed
# name is deleted out from under an outer `byName` by a nested one (one started
# from inside the callback of an outer sink). Cost: one construction per call.
# A start point this wrapper refuses comes back as rc 2 through `run`.
TFind.byName() {
    if (( $# < 2 )); then
        kk.debug "Error: TFind.byName: usage: TFind.byName PATTERN START... — at least one start point is required (with none find would search the caller's working directory); build an instance for that form"
        return 2
    fi
    __TFD_SEQ=$(( __TFD_SEQ + 1 ))
    local __tfd_i="__tfd_b_${BASHPID}_${__TFD_SEQ}"
    TFind.new "$__tfd_i" "${@:2}"
    "$__tfd_i".name = "$1"
    local __tfd_rc=0
    "$__tfd_i".run || __tfd_rc=$?
    "$__tfd_i".delete
    return "$__tfd_rc"
}

# Finalize: extract the bodies above into the `TFind` class and generate the
# per-instance wrappers.
build TFind
