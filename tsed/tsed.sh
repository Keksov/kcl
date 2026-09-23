#!/bin/bash

# Re-source guard: the class only needs to be built once per process
# (kcl/README.md §1.4 — the guard reads the flag with `:-` so `set -u` is happy).
if [[ -n "${_TSED_SOURCED:-}" ]]; then
    return
fi
declare -g _TSED_SOURCED=1

# Locale self-heal (kcl/README.md §1.6). A path, an expression and the bytes sed
# emits are data and pass through verbatim, so character semantics are part of
# this unit's contract: an empty environment means the C locale.
if [[ -z "${LC_ALL:-}${LC_CTYPE:-}${LANG:-}" ]]; then
    export LC_CTYPE=C.UTF-8
fi

# The base class. `tutil.sh` transitively brings kklass's Pascal front-end and
# `tpipe.sh`; both carry re-source guards. This is the ONLY `source` line in
# the unit.
TSED_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$TSED_DIR/../tutil/tutil.sh"

# Register this unit in TUtil's two out-name registries (PLAN §2.1):
#   * the local prefix `__tsd_` — bash scopes locals DYNAMICALLY, so a caller
#     array named `__tsd_v` would bind the scratch nameref a member body holds;
#   * the suffix `_exprs` — `${inst}_exprs` is this unit's own storage, and
#     measured, `s.toArray s_exprs` turned the records into the NEXT run's
#     script (with `sandbox = 0` a data line `e …` became a command).
# Each append is idempotent (only if absent), and the scratch globals are
# released right after, so the unit leaves exactly `_TSED_SOURCED`, `TSED_DIR`
# and `__TSD_SEQ` behind.
declare -g __tsd_seen=0
declare -g __tsd_p=''
for __tsd_p in "${TUTIL_OUT_PREFIXES[@]}"; do
    if [[ "$__tsd_p" == "__tsd_" ]]; then
        __tsd_seen=1
    fi
done
if [[ "$__tsd_seen" != "1" ]]; then
    TUTIL_OUT_PREFIXES+=( __tsd_ )
fi
__tsd_seen=0
for __tsd_p in "${TUTIL_OUT_SUFFIXES[@]}"; do
    if [[ "$__tsd_p" == "_exprs" ]]; then
        __tsd_seen=1
    fi
done
if [[ "$__tsd_seen" != "1" ]]; then
    TUTIL_OUT_SUFFIXES+=( _exprs )
fi
unset -v __tsd_seen __tsd_p

# Monotonic sequence for `TSed.edit`'s throw-away instance name (PLAN §2.7): a
# FIXED name is deleted out from under an outer `edit` by a nested one, so the
# name is `__tsd_e_${BASHPID}_${__TSD_SEQ}`. Same idiom as TGrep's `__TG_SEQ`.
declare -g __TSD_SEQ=0

# ---------------------------------------------------------------------------
# TSed — the GNU sed 4.9 wrapper over TUtil.
#
#     source kcl/tsed/tsed.sh
#
#     TSed.edit 's/foo/bar/' notes.txt      # the one-liner, streamed, sandboxed
#
#     TSed.new s 's/a/A/' in.txt            # or an instance, for options
#     s.addExpr '/^#/d'                     # more expressions, in order
#     s.extended = 1                        # -E (always before the first -e)
#     s.toArray lines                       # RESULT = ${#lines[@]}
#     s.inPlace = 1; s.backupSuffix = .bak  # in-place: `run` only
#     s.run
#     s.delete
#
# ---- The pinned argv (PLAN §1.2) ------------------------------------------
#   sed [--sandbox] [-E] [-n] [-s] [-z] [-b] [-i[SUFFIX]] [EXTRA OPTIONS]
#       [-e EXPR] [-e X ...] [-f FILE] [-- PATH...]
#
#  * sed compiles each `-e` WHEN IT READS IT, with the flags known so far:
#    `sed -e 's/(/X/' -E` silently runs the expression as BRE. So EVERY option
#    — typed or extra — precedes the first `-e`;
#  * `expr` is emitted first, then the `addExpr` list in call order, then
#    `-f scriptFile`; `--` appears only with at least one path;
#  * `-b` is emitted when `binary == 1` OR `inPlace == 1` OR `nullData == 1`
#    (owner Q5): in text mode sed rewrites CRLF to LF ON DISK under `-i` (even
#    the identity) and strips a CR inside a NUL record under `-z`. The derivation
#    lives here only; the `binary` property is never written;
#  * `-i` takes its suffix ATTACHED (`-i.bak`); `*` in the suffix is replaced
#    by the OPERAND AS GIVEN, directory part included (`bak_*` on `d/f` is
#    `bak_d/f`), `/` makes it a directory (`bk/*`); a missing directory is the
#    tool's rc 4 with the file untouched (measured at P0).
#  * `--sandbox` is emitted unless `sandbox` is EXACTLY `0` — it fails closed,
#    the one deliberate exception to the family boolean rule (owner Q1).
#
# ---- rc 2 at buildArgv: nothing runs, one kk.debug line (PLAN §2.2) --------
#   * `cmd` empty;
#   * NO script at all (`expr` '', the list empty, `scriptFile` '') — sed would
#     take the first path AS the script. The identity is `addExpr ''`;
#   * `inPlace = 1` with no path, or with the path `-`;
#   * `backupSuffix` non-empty with `inPlace = 0`, or equal to `*`;
#   * an extra on the Q6 deny-list: any spelling sed's getopt reads as `-i`,
#     `-z`, `-e`, `-f`, `-n`, `-s`, `-E`/`-r`, `-b` or `--sandbox` — see
#     `tsed._denied`. `--posix`, `-u`, `-l N`, `--follow-symlinks`, `--debug`
#     pass;
#   * `--` among the extras: it ends sed's options, and every expression after
#     it would become an operand (the wrapper emits its own `--`).
#
# ---- The five sinks (PLAN §2.4) --------------------------------------------
# `inPlace = 1`, or `--debug` among the extras, makes every sink answer rc 2
# with nothing run (`_lastRc` untouched): in-place writes nothing to stdout,
# `--debug` writes its trace INTO it. `run` is the member for both. Otherwise
# the base sink runs, through the rc-PRESERVING spelling (thead §6).
#
# ---- mapRc (owner Q3) ------------------------------------------------------
#   0 -> 0;  1, 2, 4 -> 1 + one kk.debug line ("sed exited N (a sed error, or
#   the script's q/Q N)");  127 -> the base wording;  anything else — a
#   script's `q N`/`Q N` — -> 1 SILENT, the raw value in `lastRc`.
#
# ---- Traps this unit is written around ------------------------------------
#  * The constructor calls `parent.constructor sed` EXPLICITLY (`inherited` in
#    a constructor forwards "$@" and would make EXPR the command).
#  * EVERY declared var is assigned in `Create`; `sandbox` to 1.
#  * No `var` is named like a TUtil or kklass member.
#  * Booleans are compared as strings (`[[ "$x" == 1 ]]`) — except `sandbox`,
#    which fails closed (`[[ "$sandbox" != "0" ]]`).
#  * A `func` answering a value and a non-zero rc ends `kk._return V; return N`.
#  * `${inst}_argv` is rebuilt through a nameref.
#  * A CALLBACK that assigns a bare `expr=`, `quiet=`, `sandbox=0` or `inPlace=`
#    writes the INSTANCE's property (dynamic scoping) — callbacks declare
#    `local`.
# ---------------------------------------------------------------------------
class TSed : TUtil
    public
        var expr            # the FIRST expression (-e); '' = none
        var scriptFile      # -f FILE ('' = off), after the expressions
        var extended        # -E
        var quiet           # -n
        var separate        # -s   (implied by -i)
        var nullData        # -z  -> derives the sinks' -0 AND -b
        var binary          # -b  (keep the CR; also derived)
        var sandbox         # --sandbox, DEFAULT 1 (owner Q1); off ONLY for exactly '0'
        var inPlace         # -i  (derives -b; the sinks refuse it)
        var backupSuffix    # -iSUFFIX (only with inPlace = 1)
        var _nulDerived     # private bookkeeping for the -z -> -0 derivation
        constructor Create  # [EXPR [PATH...]]
        destructor  Destroy # frees ${inst}_paths and ${inst}_exprs, then inherited
        proc paths          # PATH... — REPLACES the operand list
        proc addExpr        # EXPR... — appended after `expr`; '' is a real element
        proc clearExprs     # empties the list (not `expr`)
        override func buildArgv
        override func mapRc
        override proc each
        override func toArray
        override func toList
        override func first
        override func count
        static proc edit    # EXPR PATH... — `sed --sandbox -e EXPR -- PATH...`
end

# ===========================================================================
# Internal helpers (plain functions, never class members)
# ===========================================================================

# tsed._denied WORD — rc 0 when WORD is, to sed's getopt, one of the options
# this wrapper models as a typed property (the owner's Q6 deny-list). On rc 0 it
# sets the CALLER's `__tsd_dopt` (the option as sed reads it) and `__tsd_dprop`
# (the property to use instead); the caller declares both.
#
# The scan follows getopt, because that is what decides what sed does:
#   * a long word `--NAME[=VALUE]` is refused when NAME is a (possibly
#     abbreviated) prefix of a denied long option — measured on sed 4.9,
#     `--in=.bak` edits the file in place with rc 0, `--expr=p`, `--null` and
#     `--d` all work, and `--zero-terminated` is an undocumented alias of `-z`;
#   * a short word `-XYZ` is a bundle: each letter is an option until one that
#     takes an argument, so `-ni` is `-n -i`, `-i.bak` is `-i` with the suffix
#     attached, `-es/a/b/` is `-e` with its script attached. `l` (`-l N`) is the
#     one ALLOWED option that takes an argument: the scan stops there, so
#     `-ul40` passes;
#   * `-` alone and a word that is not an option pass here; `--` alone is
#     refused by `buildArgv` itself, with its own message.
tsed._denied() {
    local __tsd_w="${1:-}" __tsd_nm='' __tsd_l='' __tsd_c='' __tsd_k=0
    case "$__tsd_w" in
        --|-|'')
            return 1
            ;;
        --*)
            __tsd_nm="${__tsd_w#--}"
            __tsd_nm="${__tsd_nm%%=*}"
            if [[ -z "$__tsd_nm" ]]; then
                return 1
            fi
            for __tsd_l in in-place:inPlace null-data:nullData zero-terminated:nullData \
                           expression:expr file:scriptFile quiet:quiet silent:quiet \
                           separate:separate regexp-extended:extended binary:binary \
                           sandbox:sandbox; do
                if [[ "${__tsd_l%%:*}" == "$__tsd_nm"* ]]; then
                    __tsd_dopt="--${__tsd_l%%:*}"
                    __tsd_dprop="${__tsd_l#*:}"
                    return 0
                fi
            done
            return 1
            ;;
        -*)
            for (( __tsd_k = 1; __tsd_k < ${#__tsd_w}; __tsd_k++ )); do
                __tsd_c="${__tsd_w:__tsd_k:1}"
                case "$__tsd_c" in
                    i)   __tsd_dprop=inPlace ;;
                    z)   __tsd_dprop=nullData ;;
                    e)   __tsd_dprop=expr ;;
                    f)   __tsd_dprop=scriptFile ;;
                    n)   __tsd_dprop=quiet ;;
                    s)   __tsd_dprop=separate ;;
                    E|r) __tsd_dprop=extended ;;
                    b)   __tsd_dprop=binary ;;
                    l)   return 1 ;;
                    *)   continue ;;
                esac
                __tsd_dopt="-$__tsd_c"
                return 0
            done
            return 1
            ;;
    esac
    return 1
}

# tsed._isDebug WORD — rc 0 when sed's getopt reads WORD as `--debug` (any
# unambiguous prefix down to `--d`, with or without `=VALUE`).
tsed._isDebug() {
    local __tsd_nm=''
    case "${1:-}" in
        --?*)
            __tsd_nm="${1#--}"
            __tsd_nm="${__tsd_nm%%=*}"
            if [[ -n "$__tsd_nm" && "debug" == "$__tsd_nm"* ]]; then
                return 0
            fi
            ;;
    esac
    return 1
}

# tsed._sinkRefused SINK — the refusal every overridden sink runs FIRST (PLAN
# §2.4). rc 0 = refused (one kk.debug line already written; the caller answers
# rc 2 and runs nothing); rc 1 = go ahead. It reads the member frame's
# `$inPlace` and `$__inst__` through dynamic scoping, as `tutil._prep` does.
tsed._sinkRefused() {
    local __tsd_m="${1:-}"
    if [[ "$inPlace" == 1 ]]; then
        kk.debug "Error: TSed.$__tsd_m: in-place editing writes nothing to stdout; use run"
        return 0
    fi
    local -n __tsd_ea="${__inst__}_args"
    local __tsd_w
    for __tsd_w in "${__tsd_ea[@]}"; do
        if tsed._isDebug "$__tsd_w"; then
            kk.debug "Error: TSed.$__tsd_m: sed --debug writes to stdout; use run"
            return 0
        fi
    done
    return 1
}

# ===========================================================================
# Members
# ===========================================================================

# Create [EXPR [PATH...]] — PLAN §1.2, §2.1. EXPR becomes `expr`, every further
# argument a path. `parent.constructor sed` is spelled out, EVERY declared var
# is assigned (`sandbox` = 1, the owner's Q1 default), and the two per-instance
# arrays are real globals next to `${inst}_data`, released by the destructor.
TSed.Create() {
    parent.constructor sed
    expr="${1:-}"
    scriptFile=''
    extended=0
    quiet=0
    separate=0
    nullData=0
    binary=0
    sandbox=1
    inPlace=0
    backupSuffix=''
    _nulDerived=0
    declare -ga "${__inst__}_paths=()"
    declare -ga "${__inst__}_exprs=()"
    local -n __tsd_p="${__inst__}_paths"
    __tsd_p=( "${@:2}" )
    return 0
}

# Destroy — release this class's two arrays, then chain to TUtil.Destroy.
TSed.Destroy() {
    unset -v "${__inst__}_paths" "${__inst__}_exprs"
    inherited
    return 0
}

# paths PATH... — REPLACE the operand list. No argument = the stdin form.
TSed.paths() {
    local -n __tsd_p="${__inst__}_paths"
    __tsd_p=( "$@" )
    return 0
}

# addExpr EXPR... — append to the expression list, emitted after `expr` in call
# order. An EMPTY argument is a real element: `-e ''` is sed's identity.
TSed.addExpr() {
    local -n __tsd_x="${__inst__}_exprs"
    __tsd_x+=( "$@" )
    return 0
}

# clearExprs — empty the list. `expr` is a property and is left alone.
TSed.clearExprs() {
    local -n __tsd_x="${__inst__}_exprs"
    __tsd_x=()
    return 0
}

# buildArgv — the override, and the single truth about what will run. RESULT =
# the number of words, rc 0; on a refusal `kk._return ""`, rc 2, one kk.debug
# line, `${inst}_argv` left EMPTY.
TSed.buildArgv() {
    local -n __tsd_v="${__inst__}_argv"
    local -n __tsd_p="${__inst__}_paths"
    local -n __tsd_x="${__inst__}_exprs"
    local -n __tsd_a="${__inst__}_args"
    __tsd_v=()

    # ---- the rc 2 list, checked before a single word is built -------------
    if [[ -z "$cmd" ]]; then
        kk.debug "Error: TSed.buildArgv: cmd is empty; there is nothing to run"
        kk._return ""
        return 2
    fi
    if [[ -z "$expr" && -z "$scriptFile" ]] && (( ${#__tsd_x[@]} == 0 )); then
        kk.debug "Error: TSed.buildArgv: no script — expr is '', the addExpr list is empty and scriptFile is ''; sed would read the first path AS the script (the identity is addExpr '')"
        kk._return ""
        return 2
    fi
    local __tsd_s
    if [[ "$inPlace" == 1 ]]; then
        if (( ${#__tsd_p[@]} == 0 )); then
            kk.debug "Error: TSed.buildArgv: inPlace = 1 with no path; sed -i has no stdin form — give the file(s) to edit"
            kk._return ""
            return 2
        fi
        for __tsd_s in "${__tsd_p[@]}"; do
            if [[ "$__tsd_s" == "-" ]]; then
                kk.debug "Error: TSed.buildArgv: inPlace = 1 with the path '-'; sed cannot edit stdin in place"
                kk._return ""
                return 2
            fi
        done
    fi
    if [[ -n "$backupSuffix" && "$inPlace" != 1 ]]; then
        kk.debug "Error: TSed.buildArgv: backupSuffix '$backupSuffix' with inPlace = 0; the suffix only means something to -i — set inPlace = 1 or clear backupSuffix"
        kk._return ""
        return 2
    fi
    if [[ "$backupSuffix" == "*" ]]; then
        kk.debug "Error: TSed.buildArgv: backupSuffix '*' names the backup exactly like the file, so sed makes NO backup, silently — use e.g. '.bak' or 'bak_*'"
        kk._return ""
        return 2
    fi
    local __tsd_dopt='' __tsd_dprop='' __tsd_w
    for __tsd_w in "${__tsd_a[@]}"; do
        # `--` among the extras ends sed's options before the first `-e`:
        # measured, `addArg --` built `sed --sandbox -- -e s/a/A/ -- f`, and
        # every expression became an OPERAND (sed then read `-e` as its script).
        if [[ "$__tsd_w" == "--" ]]; then
            kk.debug "Error: TSed.buildArgv: the extra '--' ends sed's options, so every expression after it would become an operand; the wrapper emits its own '--' before the paths"
            kk._return ""
            return 2
        fi
        if tsed._denied "$__tsd_w"; then
            if [[ "$__tsd_dprop" == "expr" ]]; then
                __tsd_dprop="expr / addExpr"
            fi
            kk.debug "Error: TSed.buildArgv: the extra '$__tsd_w' is sed's $__tsd_dopt, which this wrapper models as the property '$__tsd_dprop' — use the property, not addArg (an extra would break the pinned argv order or the sinks' refusals)"
            kk._return ""
            return 2
        fi
    done

    # ---- the -z -> -0 derivation (PLAN §2.3, tgrep's P3-F1 guard) ----------
    # `_nulDerived` records that WE set `nul`: turning `nullData` back off takes
    # the `-0` off again, while a `nul = 1` the CALLER set is never touched.
    if [[ "$nullData" == 1 ]]; then
        if [[ "$nul" != 1 ]]; then
            nul=1
            _nulDerived=1
        fi
    elif [[ "$_nulDerived" == 1 ]]; then
        nul=0
        _nulDerived=0
    fi

    # ---- the argv, in the pinned order: every option before the first -e --
    __tsd_v=( "$cmd" )
    # `sandbox` FAILS CLOSED — the one deliberate exception to the family
    # boolean rule (every other flag is on only for the exact string `1`).
    # Owner Q1 made the sandbox a security default, so `--sandbox` is dropped
    # ONLY for the exact string `0`; '', `yes`, `2`, ` 0`, `00` all keep it.
    if [[ "$sandbox" != "0" ]]; then __tsd_v+=( --sandbox ); fi
    if [[ "$extended" == 1 ]]; then __tsd_v+=( -E ); fi
    if [[ "$quiet"    == 1 ]]; then __tsd_v+=( -n ); fi
    if [[ "$separate" == 1 ]]; then __tsd_v+=( -s ); fi
    if [[ "$nullData" == 1 ]]; then __tsd_v+=( -z ); fi
    # Owner Q5: the derived -b. Nothing is written back to `binary`.
    if [[ "$binary" == 1 || "$inPlace" == 1 || "$nullData" == 1 ]]; then
        __tsd_v+=( -b )
    fi
    if [[ "$inPlace" == 1 ]]; then __tsd_v+=( "-i$backupSuffix" ); fi
    if (( ${#__tsd_a[@]} > 0 )); then __tsd_v+=( "${__tsd_a[@]}" ); fi
    if [[ -n "$expr" ]]; then __tsd_v+=( -e "$expr" ); fi
    for __tsd_s in "${__tsd_x[@]}"; do
        __tsd_v+=( -e "$__tsd_s" )
    done
    if [[ -n "$scriptFile" ]]; then __tsd_v+=( -f "$scriptFile" ); fi
    if (( ${#__tsd_p[@]} > 0 )); then __tsd_v+=( -- "${__tsd_p[@]}" ); fi

    kk._return "${#__tsd_v[@]}"
    return 0
}

# mapRc RAW — owner Q3. sed's own statuses are 1 (a bad script), 2 (a missing
# input file; the other files are still processed) and 4 (an I/O error;
# processing STOPS at that operand). A script's `q N`/`Q N` exits with N mod
# 256, so `q1`/`q2`/`q4` are indistinguishable from those — the line says so.
# Any other non-zero status can only be the script's and is NOT an error: rc 1,
# silent, the raw value in `lastRc`.
TSed.mapRc() {
    local __tsd_raw="${1:-}"
    case "$__tsd_raw" in
        0)
            kk._return "0"
            return 0
            ;;
        127)
            kk.debug "Error: TSed.mapRc: command not found (raw rc 127)"
            ;;
        1|2|4)
            kk.debug "Error: TSed.mapRc: sed exited $__tsd_raw (a sed error, or the script's q/Q $__tsd_raw)"
            ;;
    esac
    kk._return "1"
    return 0
}

# ---------------------------------------------------------------------------
# The five sinks (PLAN §2.4). Each runs `tsed._sinkRefused` FIRST, then the base
# sink through the rc-PRESERVING spelling: `build` compiles a
# `kk._return "$RESULT"` trailer onto a `func`, so a body that merely ENDS on
# `inherited X "$@"` would answer rc 0 where the base answered 1. The funcs
# capture the rc, save RESULT at once and re-raise both; the proc `each` has no
# return channel and re-raises the rc alone.
# ---------------------------------------------------------------------------

TSed.each() {
    if tsed._sinkRefused each; then
        return 2
    fi
    local __tsd_rc=0
    inherited each "$@" || __tsd_rc=$?
    return "$__tsd_rc"
}

TSed.toArray() {
    if tsed._sinkRefused toArray; then
        kk._return ""
        return 2
    fi
    local __tsd_rc=0
    inherited toArray "$@" || __tsd_rc=$?
    local __tsd_n="$RESULT"
    kk._return "$__tsd_n"
    return "$__tsd_rc"
}

TSed.toList() {
    if tsed._sinkRefused toList; then
        kk._return ""
        return 2
    fi
    local __tsd_rc=0
    inherited toList "$@" || __tsd_rc=$?
    local __tsd_n="$RESULT"
    kk._return "$__tsd_n"
    return "$__tsd_rc"
}

TSed.first() {
    if tsed._sinkRefused first; then
        kk._return ""
        return 2
    fi
    local __tsd_rc=0
    inherited first "$@" || __tsd_rc=$?
    local __tsd_n="$RESULT"
    kk._return "$__tsd_n"
    return "$__tsd_rc"
}

TSed.count() {
    if tsed._sinkRefused count; then
        kk._return ""
        return 2
    fi
    local __tsd_rc=0
    inherited count "$@" || __tsd_rc=$?
    local __tsd_n="$RESULT"
    kk._return "$__tsd_n"
    return "$__tsd_rc"
}

# edit EXPR PATH... — the one-liner (PLAN §2.7): `sed --sandbox -e EXPR --
# PATH...` as a STREAM, with the rc mapped. A `static proc`: it prints sed's
# stdout and never calls `kk._return`.
#
# The throw-away instance is built with an EMPTY `expr` and then
# `addExpr "$EXPR"`, so an empty EXPR is a real `-e ''` — the identity — and not
# "no script". The sandbox is forced on (the default, and there is no way to
# turn it off from here). At least ONE path is required: with none sed would
# read the caller's stdin — rc 2, nothing runs.
TSed.edit() {
    if (( $# < 2 )); then
        kk.debug "Error: TSed.edit: usage: TSed.edit EXPR PATH... — at least one path is required (with none sed would read the caller's stdin); build an instance for the stdin form"
        return 2
    fi
    __TSD_SEQ=$(( __TSD_SEQ + 1 ))
    local __tsd_i="__tsd_e_${BASHPID}_${__TSD_SEQ}"
    TSed.new "$__tsd_i" '' "${@:2}"
    "$__tsd_i".addExpr "$1"
    "$__tsd_i".sandbox = 1
    local __tsd_rc=0
    "$__tsd_i".run || __tsd_rc=$?
    "$__tsd_i".delete
    return "$__tsd_rc"
}

# Finalize: extract the bodies above into the `TSed` class and generate the
# per-instance wrappers.
build TSed
