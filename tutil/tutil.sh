#!/bin/bash

# Re-source guard: the class only needs to be built once per process
# (kcl/README.md §1.4 — the guard reads the flag with `:-` so `set -u` is happy).
if [[ -n "${_TUTIL_SOURCED:-}" ]]; then
    return
fi
declare -g _TUTIL_SOURCED=1

# Locale self-heal (kcl/README.md §1.6). The words of an argv and the bytes a
# tool emits are data and pass through verbatim, so character semantics are part
# of this unit's contract: an empty environment means the C locale, where
# ${#s} counts bytes and ${s,,} corrupts multi-byte text.
if [[ -z "${LC_ALL:-}${LC_CTYPE:-}${LANG:-}" ]]; then
    export LC_CTYPE=C.UTF-8
fi

# Source the kklass Pascal-style DSL front-end (don't override SCRIPT_DIR).
TUTIL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$TUTIL_DIR/../../kklass/kklass_pascal.sh"

# ---------------------------------------------------------------------------
# TUtil — the CLI-tool wrapper base, and a usable generic runner on its own.
#
# Kinship: FPC `fcl-process` TProcess (`Executable`, `Parameters`, `Execute`,
# `ExitStatus`) in spirit — no class is ported line by line (PLAN.md header).
# What a wrapper buys over calling the tool by hand: typed options built into an
# argv ARRAY (no string building, no `eval`, no word splitting — a path with a
# space or a pattern starting with `-` is safe by construction), ONE rc
# convention across tools whose own conventions differ, and one place for the
# platform notes.
#
#     TUtil.new u git log --format=%H     # cmd = git, args = (log --format=%H)
#     u.run                               # runs it, stdout inherited
#     u.lastRc                            # RESULT = the tool's RAW exit status
#
#     TUtil.new g grep; g.addArg -i -e needle -- file
#     declare -a words; g.argv words      # RESULT = 4 — built, NOT run
#
# ---- Surface (PLAN §1.2) ---------------------------------------------------
#   var  cmd        executable / function / builtin name; '' = not runnable
#   var  crlf       1 -> the P1 sinks strip one trailing CR per record (TPipe -c)
#   var  nul        1 -> records are NUL-terminated (TPipe -0)
#   var  _lastRc    raw rc of the last run/sink; -1 until one ran
#   Create [CMD [ARG...]]   assigns EVERY var; ARGs become ${inst}_args
#   Destroy                 frees ${inst}_args and ${inst}_argv (§1.9)
#   buildArgv               virtual; fills ${inst}_argv; RESULT = count
#   addArg ARG...           append to ${inst}_args (the un-modelled-option hatch)
#   clearArgs               empty ${inst}_args
#   argv NAME               buildArgv, then COPY into the caller's array;
#                           RESULT = count; runs NOTHING
#   run                     execute in the FOREGROUND, stdout inherited
#   each/toArray/toList/first/count      P1: delegate to TPipe (stubs here)
#   lastRc                  RESULT = _lastRc
#   mapRc RAW               virtual; RESULT = the normalised rc
#
# ---- Reserved member names (PLAN §1.2) -------------------------------------
# TUtil owns `cmd crlf nul _lastRc buildArgv addArg clearArgs argv run each
# toArray toList first count lastRc mapRc`; kklass owns `property call parent
# delete` on every instance. A DESCENDANT must never declare a `var` with any of
# those names: the method wrapper is generated after the property wrapper and
# wins silently (kklass.sh:911), so `obj.count = 5` would be accepted and
# discarded. The §7 wrappers use `lines`/`bytes`, never `count`/`first`.
#
# ---- Three per-instance arrays (PLAN §2.1) ---------------------------------
# `${inst}_args` (the caller's extras, persistent) and `${inst}_argv` (built,
# REBUILT on every run/sink) live next to kklass's `${inst}_data`, are created
# with `declare -g -a` in the constructor and are released by the destructor —
# kcl/README.md §1.9: an extra per-instance array is the unit's own
# responsibility. (`${inst}_paths` is TGrep's, from P2; its name is already
# refused as an output name here so the rule never changes under a caller.)
#
# ---- Return contract (kcl/README.md §1.1, §1.2) ----------------------------
# A direct call prints nothing and answers in RESULT; `$( )` prints the value
# once. `run` is the ONE deliberate deviation in this family: a stream member
# prints by definition, so `run`'s stdout is the TOOL's stdout, inherited
# untouched. rc 0 = the tool succeeded; rc 1 = it did not (silent, the raw
# status stays readable through `lastRc`); rc 2 = a malformed CALL (empty `cmd`,
# a bad output-array name) — one `kk.debug` line and NOTHING runs.
#
# Under `$( )` every mutation is lost with the subshell: `$(u.run)` captures the
# bytes but the instance's `_lastRc` is NOT updated — the line every kcl
# instance unit carries.
#
# ---- Traps this unit is written around (PLAN §2.2, §2.3, §6) ---------------
#  * An internal call to another member is `kk.call_silent "$__inst__" NAME …`,
#    NEVER `$this.NAME`. `$this.NAME` compiles to `$__inst__.call NAME`, which
#    does not set `__kk_return_silent`; the callee's `kk._return` then PRINTS
#    whenever the outer member runs under `$( )`, on the LHS of a pipe or inside
#    `<( )` — exactly the three positions `run` exists for (measured: `od -c <
#    <(v.run)` showed buildArgv's count and mapRc's value wrapped around the
#    tool's own output). `kk.call_silent` sets and restores the flag, keeps
#    RESULT, and still dispatches VIRTUALLY (kklass test 112).
#  * A `func` that must answer both RESULT and a non-zero rc ends with
#    `kk._return V; return N`: an explicit `return` skips the compiled
#    `kk._return "$RESULT"` trailer and `kk._invoke` then restores the CALLER's
#    RESULT (kklass.sh:399), so a bare `RESULT=V; return N` loses V.
#  * The constructor assigns EVERY declared var. kklass binds a property as a
#    nameref onto `${inst}_data[NAME]`; an unassigned one is an UNBOUND variable
#    under `set -u` (kklass.sh:363), and `.new` over a still-live instance does
#    not clear `_data`, so an unassigned var can also inherit the previous
#    instance's value.
#  * `"${argv[@]}" || rc=$?` in `run`, never bare: under `set -e` a failing
#    external command inside a member aborts the caller before `_lastRc` is
#    stored.
#  * `run` pre-checks `command -v -- "$cmd"` (a builtin, no fork). Without it
#    bash prints its own UNCONDITIONAL `command not found` line on stderr,
#    attributed to kklass.sh, which breaks §1.2's "stderr only under the
#    switch". Deliberately stricter than TPipe, which takes an arbitrary argv
#    and cannot know the command (tpipe PLAN §2.5); TUtil owns `cmd`.
#  * A boolean var is tested as `[[ "$x" == 1 ]]`, never `(( x ))`.
#  * `${inst}_argv` is rebuilt through a nameref (`local -n a=…; a=()`), never
#    with `unset "${inst}_argv[…]"`.
#  * No `$'…'` holding a control character inside a member body: `build`
#    re-creates every body from `declare -f` through `eval`, and a literal CR
#    does not survive that round trip (tpipe README §7 — a kklass-wide trap).
# ---------------------------------------------------------------------------
class TUtil
    public
        var  cmd
        var  crlf
        var  nul
        var  _lastRc
        constructor Create
        destructor  Destroy
        func buildArgv
        proc addArg
        proc clearArgs
        func argv
        proc run
        proc each
        func toArray
        func toList
        func first
        func count
        func lastRc
        func mapRc
end

# ===========================================================================
# Internal helpers (plain functions, never class members — `build` does not
# touch them, and they can be shared by a descendant in another file).
# ===========================================================================

# tutil._badOut NAME — rc 0 when NAME must NOT be used as an output array,
# rc 1 when it is usable. The shape is `TQueueStack._outName`
# (tqueuestack.sh:189) with the polarity the name states and with one
# difference: the CALLER converts the refusal to rc 2 (kcl/README.md §1.2
# reserves rc 2 for a malformed call; that helper answers rc 1 and its caller
# does the same conversion).
#
# Two checks, in this order:
#   1. `kk._outName NAME __tu_ __tg_` — the §1.7 core: identifier shape, the
#      kklass reserved set (`this __inst__ __class__ RESULT REPLY IFS state`),
#      the `__kk_`/`__KK_` space, the receiving instance's own
#      `_data`/`_class`/`_items`, and this family's local prefixes. Both
#      prefixes are passed from P0 on: bash scopes locals DYNAMICALLY, so a
#      caller array named `__tu_v` or `__tg_p` would bind our own scratch, and
#      tgrep (P2) shares these member bodies by inheritance.
#   2. the extra per-instance arrays this family keeps beyond the kklass three:
#      `${inst}_args`, `${inst}_argv` and TGrep's `${inst}_paths`. Filling one
#      of those would hand the caller the instance's own storage and then let
#      the next `buildArgv` overwrite it.
tutil._badOut() {
    local __tu_n="${1:-}" __tu_i="${__inst__:-}"
    if ! kk._outName "$__tu_n" __tu_ __tg_; then
        return 0
    fi
    if [[ -n "$__tu_i" ]]; then
        case "$__tu_n" in
            "${__tu_i}_args"|"${__tu_i}_argv"|"${__tu_i}_paths") return 0 ;;
        esac
    fi
    return 1
}

# ===========================================================================
# Members
# ===========================================================================

# Create [CMD [ARG...]] — PLAN §2.1.
#
# EVERY declared var is assigned here, no exception (see the header trap list).
# The two per-instance arrays are created with `declare -g -a` so they are real
# globals next to `${inst}_data`, and filled through a nameref: the constructor
# arguments reach this body verbatim, `--format=%H` and a word with a space
# included, because kklass forwards `.new`'s tail unchanged.
TUtil.Create() {
    cmd="${1:-}"
    crlf=0
    nul=0
    _lastRc=-1
    declare -ga "${__inst__}_args=()"
    declare -ga "${__inst__}_argv=()"
    local -n __tu_a="${__inst__}_args"
    __tu_a=( "${@:2}" )
    return 0
}

# Destroy — release the two arrays this unit created (kcl/README.md §1.9).
# WHOLE-array unset through the plain names: `unset "${inst}_argv[…]"` (the
# indexed form in double quotes) is the G2-01 trap and is never used here.
# `unset -v` on a name that does not exist is rc 0, so a half-built instance
# tears down cleanly too.
TUtil.Destroy() {
    unset -v "${__inst__}_args" "${__inst__}_argv"
    return 0
}

# buildArgv — VIRTUAL by kklass default, and the single truth about what will
# run: `run` and every P1 sink call it first, and it is the DESCENDANT's
# override that runs. The base builds `cmd` + the caller's extras.
#
# RESULT = the number of words; rc 2 with RESULT='' when `cmd` is empty, and
# then the caller runs NOTHING.
TUtil.buildArgv() {
    local -n __tu_v="${__inst__}_argv"
    __tu_v=()
    if [[ -z "$cmd" ]]; then
        kk.debug "Error: TUtil.buildArgv: cmd is empty; there is nothing to run"
        kk._return ""
        return 2
    fi
    local -n __tu_a="${__inst__}_args"
    __tu_v=( "$cmd" "${__tu_a[@]}" )
    kk._return "${#__tu_v[@]}"
    return 0
}

# addArg ARG... — append to the persistent extras. This is the documented
# escape hatch for options a wrapper does not model; the words are passed to the
# tool VERBATIM, never re-split and never expanded. No arguments is a no-op.
TUtil.addArg() {
    local -n __tu_a="${__inst__}_args"
    __tu_a+=( "$@" )
    return 0
}

# clearArgs — empty the extras (the built argv is rebuilt on the next call).
TUtil.clearArgs() {
    local -n __tu_a="${__inst__}_args"
    __tu_a=()
    return 0
}

# argv NAME — build the argv and COPY it into the caller's array; RESULT = the
# count. This member RUNS NOTHING: it is how a wrapper's option set is pinned by
# comparing an array instead of executing the tool.
#
# Order (kcl/README.md §1.7): the name is validated BEFORE any nameref is bound
# — `local -n out="$1"` on a bad name prints a bash diagnostic and still returns
# 0 — and `buildArgv` is reached through `kk.call_silent`, which dispatches
# virtually without letting the callee's `kk._return` print under `$( )`.
TUtil.argv() {
    if tutil._badOut "${1:-}"; then
        kk.debug "Error: TUtil.argv: bad output array name '${1:-}'"
        kk._return ""
        return 2
    fi
    local __tu_rc=0
    kk.call_silent "$__inst__" buildArgv || __tu_rc=$?
    if [[ "$__tu_rc" != "0" ]]; then
        kk._return ""
        return "$__tu_rc"
    fi
    local -n __tu_out="$1"
    local -n __tu_v="${__inst__}_argv"
    __tu_out=( "${__tu_v[@]}" )
    kk._return "${#__tu_out[@]}"
    return 0
}

# run — execute the built argv in the FOREGROUND with stdout INHERITED.
#
# PLAN §2.3, in order:
#   1. `buildArgv` (virtual, silent). rc 2 -> return 2, nothing runs.
#   2. `command -v -- "$cmd"`, a builtin with no fork: a missing command is
#      rc 1 + `_lastRc=127` + ONE `kk.debug` line, and nothing runs — otherwise
#      bash prints its own unconditional `command not found` on stderr.
#   3. `"${argv[@]}" || rc=$?` — NEVER bare, or a `set -e` caller dies before
#      `_lastRc` is stored.
#   4. the raw status into the PER-INSTANCE `_lastRc` (two wrappers may
#      interleave), then `mapRc` (virtual, silent) decides the member's own rc.
#
# `run` is a `proc`: it has no return channel, and its stdout is the tool's.
TUtil.run() {
    local __tu_rc=0
    kk.call_silent "$__inst__" buildArgv || __tu_rc=$?
    if [[ "$__tu_rc" != "0" ]]; then
        return "$__tu_rc"
    fi
    if ! command -v -- "$cmd" >/dev/null 2>&1; then
        _lastRc=127
        kk.debug "Error: TUtil.run: command not found: '$cmd'"
        return 1
    fi
    local -n __tu_v="${__inst__}_argv"
    __tu_rc=0
    "${__tu_v[@]}" || __tu_rc=$?
    _lastRc="$__tu_rc"
    kk.call_silent "$__inst__" mapRc "$_lastRc"
    return "$RESULT"
}

# lastRc — the RAW exit status of the last run/sink; -1 until one ran. The raw
# status is what tells `no match` (grep 1) from `bad regex` (grep 2) apart after
# `mapRc` has flattened both to the kcl rc 1.
TUtil.lastRc() {
    kk._return "$_lastRc"
    return 0
}

# mapRc RAW — VIRTUAL. The one policy, and the one override point: a descendant
# that knows its tool's rc table replaces this body (TGrep: 1 = "no match", an
# answer, silent; >= 2 = a real error with a diagnostic).
#
# Base table: 0 -> 0; 127 -> 1 with one `kk.debug` line; anything else -> 1,
# silent. It is a MAPPER, not a sink: it answers through RESULT with rc 0, and
# the caller uses that value as its own exit status.
TUtil.mapRc() {
    local __tu_raw="${1:-}"
    if [[ "$__tu_raw" == "0" ]]; then
        kk._return "0"
        return 0
    fi
    if [[ "$__tu_raw" == "127" ]]; then
        kk.debug "Error: TUtil.mapRc: command not found (raw rc 127)"
    fi
    kk._return "1"
    return 0
}

# ---------------------------------------------------------------------------
# P0 STUBS — the five sinks land in P1, delegating to TPipe with
# `-- "${argv[@]}"` (PLAN §2.3, §5 P1.1).
#
# The four `func`s answer the `__TUTIL_PENDING__` sentinel through `kk._return`
# rather than just returning: a func stub that does not call `kk._return` leaves
# the CALLER's RESULT in place (kk._invoke restores it), which no test can tell
# from a member that answered correctly. `each` is a `proc` and has no return
# channel, so it is rc 2 plus the diagnostic and nothing else.
# ---------------------------------------------------------------------------
TUtil.each() {
    kk.debug "Error: TUtil.each: not implemented before P1 (the TPipe sinks)"
    return 2
}

TUtil.toArray() {
    kk.debug "Error: TUtil.toArray: not implemented before P1 (the TPipe sinks)"
    kk._return "__TUTIL_PENDING__"
    return 2
}

TUtil.toList() {
    kk.debug "Error: TUtil.toList: not implemented before P1 (the TPipe sinks)"
    kk._return "__TUTIL_PENDING__"
    return 2
}

TUtil.first() {
    kk.debug "Error: TUtil.first: not implemented before P1 (the TPipe sinks)"
    kk._return "__TUTIL_PENDING__"
    return 2
}

TUtil.count() {
    kk.debug "Error: TUtil.count: not implemented before P1 (the TPipe sinks)"
    kk._return "__TUTIL_PENDING__"
    return 2
}

# Finalize: extract the bodies above into the `TUtil` class and generate the
# per-instance wrappers.
build TUtil
