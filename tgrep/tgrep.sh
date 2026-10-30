#!/usr/bin/env bash
[[ ${__KK_UNITS[@]@a} == A* ]] || source "${BASH_SOURCE%tgrep.sh}../../kbool.sh" || return
kk.unit tgrep || return $__kk_unit_rc

# Locale self-heal (kcl/README.md §1.6). A pattern, a path and the bytes grep
# emits are all data and pass through verbatim, so character semantics are part
# of this unit's contract: an empty environment means the C locale, where a
# multi-byte pattern and a multi-byte file name stop being characters.
if [[ -z "${LC_ALL:-}${LC_CTYPE:-}${LANG:-}" ]]; then
    export LC_CTYPE=C.UTF-8
fi

# A unit (kklass/USES_PLAN.md §7.4, phase U4): the two header lines at the
# top load kbool.sh when needed and make a repeated `source` a no-op, also
# under `set -eu` (they replaced the D7 re-source guard). Dependencies come
# through kk.uses.
# The base class. `tutil` transitively brings kklass's Pascal front-end and
# `tpipe`; both are units (loaded once per process), so a caller that already
# loaded them pays nothing. This is the tobjectlist -> tlist pattern: a
# descendant in another file loads its parent's unit by name.
kk.uses tutil || return

# Monotonic sequence for `TGrep.search`'s throw-away instance name (§2.5). A
# FIXED name is deleted out from under an outer `search` by a nested one, so the
# name is `__tg_s_${BASHPID}_${__TG_SEQ}`: BASHPID separates processes (a `$( )`
# or `<( )` producer is a different one), the counter separates calls inside a
# process. Same idiom as ktests' `_KT_BACKUP_SEQ`.
declare -g __TG_SEQ=0

# ---------------------------------------------------------------------------
# TGrep — the first TUtil wrapper: GNU grep 3.0 with typed options.
# The tool is the GNU grep ktool resolves (`cmd` = its absolute path: `grep`,
# or `ggrep` on FreeBSD); with none, `.new` still works and the first
# run/sink/argv answers rc 2 with ktool's reason.
#
#     source kcl/tgrep/tgrep.sh
#
#     TGrep.search "needle" src/            # the one-liner: `grep -r`, streamed
#
#     TGrep.new g "needle" src/ doc/        # or an instance, for options
#     g.ignoreCase = 1
#     g.recursive  = 1
#     g.include    = '*.sh'
#     g.each r.onLine                       # one call per matching line
#     g.toArray hits                        # RESULT = ${#hits[@]}
#     g.count                               # RESULT = how many
#     g.delete
#
# ---- The pinned argv (PLAN §1.3) ------------------------------------------
#   grep [-i] [-v] [-w] [-x] [-F|-E] [-r] [-n] [-l|-L] [-c] [-o] [-h|-H]
#        [-m N] [--include=G] [--exclude=G] [--exclude-dir=G] [-U] [-z] [-Z] [-q]
#        -e PATTERN [EXTRA ARGS from addArg] [-- PATH...]
#
# The pattern ALWAYS travels as `-e PATTERN`, so a pattern that starts with `-`
# is data and not a flag; `--` appears only when there is at least one path (with
# none, grep reads stdin, which is the documented stdin form). Booleans are the
# exact string `1`; anything else is off. No `-P` (PCRE is optional in a GNU
# build and absent from the house ERE line, tregex) and no `--color`, ever — the
# output is data.
#
# ---- rc 2 at buildArgv: nothing runs, one kk.debug line --------------------
#   * `cmd` empty: no GNU grep was found when the instance was created
#     (`_toolErr` holds ktool's reason and is the line printed), or the
#     instance was disarmed by hand;
#   * `pattern` empty — `-e ''` matches every line, which no caller means;
#   * `fixed` + `extended` (-F and -E): grep itself answers 2;
#   * `filesOnly` + `filesWithoutMatch` (-l and -L) and `noFilename` +
#     `withFilename` (-h and -H): grep ACCEPTS both pairs with last-flag-wins /
#     empty-output semantics, so the answer would depend on the fixed order of
#     this builder rather than on anything the caller wrote;
#   * `maxCount` that is not an integer, or negative — grep 3.0 reads `-m -1` as
#     "no limit", silently.
#
# ---- mapRc (PLAN §2.4) ----------------------------------------------------
# `0 -> 0`; `1 -> 1` SILENT (no match is an answer, not a failure);
# `>= 2 -> 1` with one `kk.debug` line quoting the raw status. grep answers 2
# while still delivering matches when one operand of many is unreadable — the
# sinks then keep every record that arrived and RESULT is the REAL count, the one
# place in this family where rc 1 does not imply an empty RESULT (§2.4, README).
#
# ---- Text mode and the CR (PLAN §2.6; tutil README §3, owner DL11) --------
# In text mode (`binary = 0`, `nullData = 0`) a line record NEVER carries the
# line-end CR, on every platform: cygwin/msys grep strips it itself; on
# Linux/BSD/macOS grep reading STDIN gets a filtered stdin (`tutil._crStdin`,
# so `$`, `-x`, `^$` behave as on Windows), and grep reading FILES has its
# output cleaned (`_textMode = 1`: the sinks add `-c`, `run` filters) — its
# matching still sees the CR there (README §5). `-l`/`-L` output is names and
# is never touched. So `crlf` has nothing left to do in text mode; `binary`
# (-U) is the way to see the CR, and `binary = 1` with `crlf = 1` is the
# byte-faithful pass over a CRLF corpus.
#
# ---- Binary files (PLAN §1.4) ---------------------------------------------
# `Binary file X matches` goes to grep's STDOUT, so it arrives as a RECORD
# through every sink. `addArg -a` (or `--binary-files=text`) is the documented
# escape hatch; `-a`/`-I` are not modelled yet. grep 3.5 and later write the note
# to stderr instead (no record). `TGrep.countMatching` passes `-I`, so a binary
# file adds nothing on every grep version (HELPERS_PLAN H2).
#
# ---- Traps this unit is written around ------------------------------------
#  * The constructor calls `parent.constructor grep` EXPLICITLY. `inherited` in
#    a constructor body is rewritten to `parent.constructor "$@"`
#    (kklass_pascal.sh:166) and would hand TUtil `cmd=PATTERN` plus every path
#    as an extra argument — the hit list doubled (PLAN §2.1). It then calls
#    `tutil._gnu grep` (`cmd` = the GNU grep ktool resolved, or '' with the
#    reason in `_toolErr`).
#  * EVERY declared var is assigned in `Create`: kklass binds a property as a
#    nameref onto `${inst}_data[NAME]`, an unassigned one is an unbound variable
#    under `set -u`, and `.new` over a still-live instance does not clear
#    `_data`.
#  * No `var` here may be named like a TUtil member (`cmd crlf nul _lastRc
#    _toolErr buildArgv addArg clearArgs argv run each toArray toList first count lastRc
#    mapRc`) or a kklass one (`property call parent delete`): the method wrapper
#    is generated after the property wrapper and wins silently.
#  * Booleans are compared as strings (`[[ "$x" == 1 ]]`); `(( x ))` on a
#    non-numeric property is 0 in silence, or an arithmetic injection.
#  * `maxCount` goes through `kk.isInt` and the NORMALISED value is read back
#    from `$__KK_INT` — never through the OUTVAR form, which writes through the
#    property nameref and would rewrite the caller's `08` into `8` on the
#    instance.
#  * A `func` that answers both a value and a non-zero rc ends with
#    `kk._return V; return N`.
#  * `${inst}_argv` is rebuilt through a nameref (`local -n a=…; a=()`), never
#    with `unset "${inst}_argv[…]"`.
# ---------------------------------------------------------------------------
class TGrep : TUtil
    public
        var pattern                    # -e PATTERN (always via -e); '' -> rc 2
        var ignoreCase                 # -i
        var invert                     # -v
        var wordRegexp                 # -w
        var lineRegexp                 # -x
        var fixed                      # -F   ┐ both set -> rc 2
        var extended                   # -E   ┘
        var recursive                  # -r   (never -R, see §2.5 / G12)
        var lineNumber                 # -n
        var filesOnly                  # -l   ┐ both set -> rc 2
        var filesWithoutMatch          # -L   ┘
        var countOnly                  # -c
        var onlyMatching               # -o
        var noFilename                 # -h   ┐ both set -> rc 2
        var withFilename               # -H   ┘
        var maxCount                   # -m N (kk.isInt AND >= 0; '' = off)
        var include                    # --include=GLOB      ('' = off)
        var exclude                    # --exclude=GLOB
        var excludeDir                 # --exclude-dir=GLOB
        var binary                     # -U (--binary): see §2.6
        var nullData                   # -z  (NUL-terminated INPUT records)
        var nullOut                    # -Z  (see §2.7)
        var quiet                      # -q  (HELPERS_PLAN H2): no output, the rc is the answer
        var _nulDerived                # private bookkeeping for §2.7 (below)
        constructor Create             # [PATTERN [PATH...]]
        destructor  Destroy            # frees ${inst}_paths, then inherited
        proc paths                     # PATH... — REPLACES the operand list
        override func buildArgv
        override func mapRc
        static proc search             # PATTERN PATH... — `grep -r`, streamed
        static proc contains           # TEXT PATH... — rc only: `grep -r -F -q`
        static proc countMatching      # TEXT PATH... — RESULT = matching lines: `grep -r -h -F` + `count`
end

# ===========================================================================
# Members
# ===========================================================================

# Create [PATTERN [PATH...]] — PLAN §2.1.
#
# `parent.constructor grep` is spelled out: `inherited` would forward THIS
# constructor's arguments to TUtil and make `cmd` the pattern while every path
# became a TUtil extra arg — each path would then appear twice in the argv.
# `tutil._gnu grep` then resolves the tool into `cmd` (L3.4: no GNU grep =
# `cmd` '' and `_toolErr`, `.new` still succeeds; the first buildArgv answers
# rc 2). EVERY declared var is assigned (booleans `0`, strings `''`), and the
# operand list becomes a real global array next to `${inst}_data`, released by
# the destructor (kcl/README.md §1.9).
TGrep.Create() {
    parent.constructor grep
    tutil._gnu grep
    pattern="${1:-}"
    ignoreCase=0
    invert=0
    wordRegexp=0
    lineRegexp=0
    fixed=0
    extended=0
    recursive=0
    lineNumber=0
    filesOnly=0
    filesWithoutMatch=0
    countOnly=0
    onlyMatching=0
    noFilename=0
    withFilename=0
    maxCount=''
    include=''
    exclude=''
    excludeDir=''
    binary=0
    nullData=0
    nullOut=0
    quiet=0
    _nulDerived=0
    declare -ga "${__inst__}_paths=()"
    local -n __tg_p="${__inst__}_paths"
    __tg_p=( "${@:2}" )
    return 0
}

# Destroy — release this class's own array, then chain. `inherited` in a
# DESTRUCTOR is the ordinary parent call (the rewrite that bites constructors
# does not apply), and TUtil.Destroy releases `${inst}_args` and `${inst}_argv`.
# `unset -v` on a name that does not exist is rc 0, so a half-built instance
# tears down cleanly too.
TGrep.Destroy() {
    unset -v "${__inst__}_paths"
    inherited
    return 0
}

# paths PATH... — REPLACE the operand list. With no arguments the list becomes
# empty and the built argv carries no `--` at all, which is grep's stdin form:
# `g.paths; printf 'a\nb\n' | g.run`.
TGrep.paths() {
    local -n __tg_p="${__inst__}_paths"
    __tg_p=( "$@" )
    return 0
}

# buildArgv — the override, and the single truth about what will run. `run` and
# all five sinks reach it through `kk.call_silent`, which dispatches VIRTUALLY,
# so this body is what they get.
#
# RESULT = the number of words, rc 0. On any refusal: `kk._return ""`, rc 2, one
# `kk.debug` line naming the reason, `${inst}_argv` left EMPTY so no stale
# command line can be executed afterwards, and the caller runs nothing.
TGrep.buildArgv() {
    local -n __tg_v="${__inst__}_argv"
    __tg_v=()

    # ---- the rc 2 list, checked before a single word is built -------------
    if [[ -z "$cmd" ]]; then
        kk.debug "Error: TGrep.buildArgv: ${_toolErr:-cmd is empty; there is nothing to run}"
        kk._return ""
        return 2
    fi
    if [[ -z "$pattern" ]]; then
        kk.debug "Error: TGrep.buildArgv: pattern is empty; \`grep -e ''\` matches every line — set \`pattern\` or use a different tool"
        kk._return ""
        return 2
    fi
    if [[ "$fixed" == 1 && "$extended" == 1 ]]; then
        kk.debug "Error: TGrep.buildArgv: fixed (-F) and extended (-E) are mutually exclusive; grep itself answers 2"
        kk._return ""
        return 2
    fi
    if [[ "$filesOnly" == 1 && "$filesWithoutMatch" == 1 ]]; then
        kk.debug "Error: TGrep.buildArgv: filesOnly (-l) and filesWithoutMatch (-L) are mutually exclusive; grep takes both and the answer would depend on this builder's order"
        kk._return ""
        return 2
    fi
    if [[ "$noFilename" == 1 && "$withFilename" == 1 ]]; then
        kk.debug "Error: TGrep.buildArgv: noFilename (-h) and withFilename (-H) are mutually exclusive; grep takes both and the answer would depend on this builder's order"
        kk._return ""
        return 2
    fi
    # `kk.isInt` accepts a negative, and grep 3.0 reads `-m -1` as "no limit"
    # SILENTLY, so `>= 0` is a separate check. The normalised value is read from
    # `$__KK_INT` (so `08` reaches grep as `8`); the OUTVAR form would write
    # through the property nameref and rewrite the caller's own value.
    local __tg_m=''
    if [[ -n "$maxCount" ]]; then
        if ! kk.isInt "$maxCount"; then
            kk.debug "Error: TGrep.buildArgv: maxCount '$maxCount' is not an integer"
            kk._return ""
            return 2
        fi
        __tg_m="$__KK_INT"
        if [[ "${__tg_m:0:1}" == "-" ]]; then
            kk.debug "Error: TGrep.buildArgv: maxCount '$maxCount' is negative; grep 3.0 reads \`-m -1\` as 'no limit' in silence"
            kk._return ""
            return 2
        fi
    fi

    # ---- the §2.7 derivation ---------------------------------------------
    # `-Z` is NUL TERMINATION only together with `-l`/`-L`. With `-c` (and with
    # normal output) it merely replaces the separator after the file name and the
    # record still ends in `\n` — measured on grep 3.0: `a.txt\0 2\n`. Handing
    # those to the sinks' `-0` would mis-frame every record, so the sinks' `-0`
    # is DERIVED here instead of being a second meaning of `nullOut`:
    #
    #   nullOut == 1 AND (filesOnly == 1 OR filesWithoutMatch == 1)  ->  nul = 1
    #
    # `_nulDerived` records that WE set it, which is what makes the derivation
    # idempotent: turning `filesOnly` back off takes the `-0` off again, while a
    # `nul = 1` the CALLER set (for `-z`, or for a shape this wrapper does not
    # model) is never touched. Besides `nul`/`_nulDerived` buildArgv writes only
    # TUtil's `_textMode` (the CR contract, below).
    #
    # The inner guard is P3-F1: claiming ownership whenever the CONDITION held —
    # even when `nul` was already 1 because the caller set it — made the undo one
    # condition too coarse, and a later build that stopped deriving cleared the
    # caller's own `nul`. We claim it only when we really set it, so the three
    # states stay distinct: derived (ours, undo it), caller-set (never touch),
    # and off.
    if [[ "$nullOut" == 1 ]] && [[ "$filesOnly" == 1 || "$filesWithoutMatch" == 1 ]]; then
        if [[ "$nul" != 1 ]]; then
            nul=1
            _nulDerived=1
        fi
    elif [[ "$_nulDerived" == 1 ]]; then
        nul=0
        _nulDerived=0
    fi

    # ---- the CR contract (tutil README §3, owner DL11) ---------------------
    # Text mode = neither `-U` nor `-z`: grep then reads lines, and the
    # line-end CR of a CRLF input must not reach the caller on any platform.
    # cygwin/msys grep has already dropped it; elsewhere (`tutil._keepsCr`):
    #   * no path operand and no `-r` (grep reads STDIN): stdin goes through
    #     `tutil._crStdin` first, so `$`, `-x` and `^$` see no CR either — the
    #     argv starts with that helper, and the output needs nothing more;
    #   * file operands (grep has no input-side switch): `_textMode = 1`, so
    #     TUtil cleans the OUTPUT (the sinks' `-c`, `run`'s filter); grep's
    #     matching still sees the CR there — the documented residual.
    # `-z` counts as binary because grep -z keeps the CR on Windows too, and
    # `-l`/`-L` print NAMES, not lines, so they get no strip at all.
    # `_textMode` is derived the same way on every platform; TUtil reads it
    # only where the tool keeps the CR.
    local __tg_in=0
    local -n __tg_p="${__inst__}_paths"
    if [[ "$binary" == 1 || "$nullData" == 1 || "$filesOnly" == 1 || "$filesWithoutMatch" == 1 ]]; then
        _textMode=0
    elif (( ${#__tg_p[@]} == 0 )) && [[ "$recursive" != 1 ]]; then
        _textMode=0
        if tutil._keepsCr; then
            __tg_in=1
        fi
    else
        _textMode=1
    fi

    # ---- the argv, in the pinned order ------------------------------------
    __tg_v=( "$cmd" )
    if [[ "$ignoreCase"        == 1 ]]; then __tg_v+=( -i ); fi
    if [[ "$invert"            == 1 ]]; then __tg_v+=( -v ); fi
    if [[ "$wordRegexp"        == 1 ]]; then __tg_v+=( -w ); fi
    if [[ "$lineRegexp"        == 1 ]]; then __tg_v+=( -x ); fi
    if [[ "$fixed"             == 1 ]]; then __tg_v+=( -F ); fi
    if [[ "$extended"          == 1 ]]; then __tg_v+=( -E ); fi
    if [[ "$recursive"         == 1 ]]; then __tg_v+=( -r ); fi
    if [[ "$lineNumber"        == 1 ]]; then __tg_v+=( -n ); fi
    if [[ "$filesOnly"         == 1 ]]; then __tg_v+=( -l ); fi
    if [[ "$filesWithoutMatch" == 1 ]]; then __tg_v+=( -L ); fi
    if [[ "$countOnly"         == 1 ]]; then __tg_v+=( -c ); fi
    if [[ "$onlyMatching"      == 1 ]]; then __tg_v+=( -o ); fi
    if [[ "$noFilename"        == 1 ]]; then __tg_v+=( -h ); fi
    if [[ "$withFilename"      == 1 ]]; then __tg_v+=( -H ); fi
    if [[ -n "$__tg_m"              ]]; then __tg_v+=( -m "$__tg_m" ); fi
    if [[ -n "$include"             ]]; then __tg_v+=( "--include=$include" ); fi
    if [[ -n "$exclude"             ]]; then __tg_v+=( "--exclude=$exclude" ); fi
    if [[ -n "$excludeDir"          ]]; then __tg_v+=( "--exclude-dir=$excludeDir" ); fi
    if [[ "$binary"            == 1 ]]; then __tg_v+=( -U ); fi
    if [[ "$nullData"          == 1 ]]; then __tg_v+=( -z ); fi
    if [[ "$nullOut"           == 1 ]]; then __tg_v+=( -Z ); fi
    if [[ "$quiet"             == 1 ]]; then __tg_v+=( -q ); fi

    # The pattern is ALWAYS `-e PATTERN`: a pattern of `-v` is then searched for,
    # not parsed as a flag.
    __tg_v+=( -e "$pattern" )

    # The un-modelled-option hatch, verbatim, after the pattern and before the
    # operands (`--` is what closes the option list).
    local -n __tg_a="${__inst__}_args"
    if (( ${#__tg_a[@]} > 0 )); then
        __tg_v+=( "${__tg_a[@]}" )
    fi

    # `--` only when there IS an operand: with none, grep reads stdin, and a
    # trailing `--` alone would make grep read stdin anyway but says something
    # the caller did not.
    if (( ${#__tg_p[@]} > 0 )); then
        __tg_v+=( -- "${__tg_p[@]}" )
    fi

    # The stdin CR filter (above) goes IN FRONT of the whole command line:
    # `tutil._crStdin grep …` is what `run` and every sink execute.
    if [[ "$__tg_in" == 1 ]]; then
        __tg_v=( tutil._crStdin "${__tg_v[@]}" )
    fi

    kk._return "${#__tg_v[@]}"
    return 0
}

# mapRc RAW — the override (PLAN §2.4). grep's own table:
#
#   0  a line was selected                     -> 0
#   1  no line was selected                    -> 1, SILENT (that is an answer)
#   2  an error: a bad regex, an unreadable or missing operand, a directory
#      without -r                              -> 1, one kk.debug line
#
# 127 cannot normally reach here (`run` and every sink pre-check the command),
# but it keeps the base class's wording if it ever does.
#
# rc 2 STILL delivers matches when one operand of many failed; the sinks keep
# every record that arrived and their RESULT is the real count. This member only
# decides the member's exit status and writes the diagnostic.
TGrep.mapRc() {
    local __tg_raw="${1:-}"
    if [[ "$__tg_raw" == "0" ]]; then
        kk._return "0"
        return 0
    fi
    if [[ "$__tg_raw" == "1" ]]; then
        # No match. An answer, not a failure: silent by contract.
        kk._return "1"
        return 0
    fi
    if [[ "$__tg_raw" == "127" ]]; then
        kk.debug "Error: TGrep.mapRc: command not found (raw rc 127)"
        kk._return "1"
        return 0
    fi
    kk.debug "Error: TGrep.mapRc: grep exited $__tg_raw (a bad regex, an unreadable or missing operand, or a directory operand without \`recursive\`); records that did arrive are kept"
    kk._return "1"
    return 0
}

# search PATTERN PATH... — the one-liner (PLAN §2.5): `grep -r -e PATTERN --
# PATH...` as a STREAM, with the rc mapped. A `static proc`: it prints the
# tool's stdout, has no return channel, and never calls `kk._return`.
#
#     TGrep.search "needle" src/                      # straight to the terminal
#     TGrep.search "needle" src/ | TPipe.each cb      # lastpipe
#     TPipe.each cb -- TGrep.search "needle" src/     # the safe `--` form
#
# `-r` is implied BY DEFINITION: the flagship call names a directory, and GNU
# grep 3.0 without `-r` answers `Is a directory`, rc 2, zero records. At least
# ONE path is required, because `grep -r` with none searches the CURRENT
# DIRECTORY, which no caller means by accident — that is rc 2 and nothing runs.
# A caller who wants stdin, or any option at all, builds an instance; an
# instance NEVER implies `-r`.
#
# The throw-away instance is named `__tg_s_${BASHPID}_${__TG_SEQ}`: a fixed name
# is deleted out from under an outer `search` by a nested one (one started from
# inside the callback of an outer sink). Cost: one construction per call.
TGrep.search() {
    if (( $# < 2 )); then
        kk.debug "Error: TGrep.search: usage: TGrep.search PATTERN PATH... — at least one path is required (\`grep -r\` with none would search the current directory); build an instance for the stdin form"
        return 2
    fi
    __TG_SEQ=$(( __TG_SEQ + 1 ))
    local __tg_i="__tg_s_${BASHPID}_${__TG_SEQ}"
    TGrep.new "$__tg_i" "$@"
    "$__tg_i".recursive = 1
    local __tg_rc=0
    "$__tg_i".run || __tg_rc=$?
    "$__tg_i".delete
    return "$__tg_rc"
}

# tgrep._ret VALUE [RC] — kcl README §1.1's static-unit helper (the `tpath._ret`
# shape, as `tsed._ret`): RESULT = VALUE, printed only inside a subshell, so a
# direct call is silent and `$( )` prints the value exactly once.
tgrep._ret() {
    RESULT="$1"
    if (( BASH_SUBSHELL > 0 )); then
        printf '%s' "$1"
    fi
    return "${2:-0}"
}

# contains TEXT PATH... — the predicate (HELPERS_PLAN §3, H2): is the LITERAL
# TEXT in any file under PATH...? `grep -r -F -q -e TEXT -- PATH...`, built on a
# throw-away instance exactly like `search` (`fixed = 1`, `recursive = 1`,
# `quiet = 1`, `run`, `delete`). It answers by its rc ALONE and prints nothing:
#
#     rc 0   a line matched
#     rc 1   no line matched — OR a tool error (a missing or unreadable operand;
#            one `kk.debug` line from `mapRc`). The family mapping, no new
#            meaning: who must tell the two apart builds an instance and reads
#            `lastRc` (1 = no match, 2 = error)
#     rc 2   a malformed call, nothing ran: fewer than two arguments (one usage
#            line), or an empty TEXT (`buildArgv`'s line) — never a tool error
#
# GNU grep with `-q` exits 0 as soon as one match is found EVEN IF another
# operand failed (measured on 3.0: `-q -e needle -- a.txt missing.txt` is rc 0,
# so is `missing.txt a.txt`), while a miss plus a failed operand is its 2 -> rc 1
# here. At least ONE path is required: `grep -r` with none searches the CURRENT
# DIRECTORY, which no caller means by accident.
TGrep.contains() {
    if (( $# < 2 )); then
        kk.debug "Error: TGrep.contains: usage: TGrep.contains TEXT PATH... — at least one path is required (\`grep -r\` with none would search the current directory); build an instance for the stdin form"
        return 2
    fi
    __TG_SEQ=$(( __TG_SEQ + 1 ))
    local __tg_i="__tg_s_${BASHPID}_${__TG_SEQ}"
    TGrep.new "$__tg_i" "$@"
    "$__tg_i".fixed = 1
    "$__tg_i".recursive = 1
    "$__tg_i".quiet = 1
    local __tg_rc=0
    "$__tg_i".run || __tg_rc=$?
    "$__tg_i".delete
    return "$__tg_rc"
}

# countMatching TEXT PATH... — how many LINES contain the LITERAL TEXT, over all
# TEXT files under PATH... (HELPERS_PLAN §3, H2): `grep -F -r -h -e TEXT -I --
# PATH...` through the existing `count` sink — no parsing of `file:count`, no `-c`. Same
# throw-away instance and the same rc 2 usage rule as `search`; an empty TEXT is
# `buildArgv`'s rc 2 with RESULT ''.
#
# RESULT and rc are what the `count` sink answers, the family's named deviation
# included (README §3): 0 matches is `0` with rc 1, and an operand that failed
# among good ones is the REAL count with rc 1. BINARY files are skipped (`-I`,
# added through `addArg`): without it grep < 3.5 would add ONE `Binary file X
# matches` record per binary hit while grep >= 3.5 adds none and writes the note
# to stderr — the same tree would count differently per platform (CI, L6.0).
# `contains` keeps binary files: the match alone is its answer. A `static proc`
# answering in RESULT (kcl README §1.1): a direct call prints nothing, `$( )`
# prints the value exactly once.
TGrep.countMatching() {
    if (( $# < 2 )); then
        kk.debug "Error: TGrep.countMatching: usage: TGrep.countMatching TEXT PATH... — at least one path is required (\`grep -r\` with none would search the current directory); build an instance for the stdin form"
        tgrep._ret '' 2
        return 2
    fi
    __TG_SEQ=$(( __TG_SEQ + 1 ))
    local __tg_i="__tg_s_${BASHPID}_${__TG_SEQ}"
    TGrep.new "$__tg_i" "$@"
    "$__tg_i".fixed = 1
    "$__tg_i".recursive = 1
    "$__tg_i".noFilename = 1
    "$__tg_i".addArg -I
    local __tg_rc=0
    "$__tg_i".count || __tg_rc=$?
    local __tg_n="$RESULT"
    "$__tg_i".delete
    tgrep._ret "$__tg_n" "$__tg_rc"
}

# Finalize: extract the bodies above into the `TGrep` class and generate the
# per-instance wrappers.
build TGrep
