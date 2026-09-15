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

# TPipe is the engine behind all five sinks (PLAN §2.3): `each`, `toArray`,
# `toList`, `first` and `count` are one `TPipe.<sink> … -- "${argv[@]}"` call
# each. It is sourced ONCE here, at load time and after kklass, because the
# sinks are member bodies and a member body may not source anything; `tpipe.sh`
# carries its own re-source guard, so a caller that already loaded it pays
# nothing.
source "$TUTIL_DIR/../tpipe/tpipe.sh"

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
#   var  crlf       1 -> the sinks strip one trailing CR per record (TPipe -c)
#   var  nul        1 -> records are NUL-terminated (TPipe -0)
#   var  _lastRc    raw rc of the last run/sink; -1 until one ran
#   var  subshellOk 1 -> every sink passes `-s` to TPipe, i.e. "the subshell
#                   scope is intended", which silences TPipe's D6 subshell
#                   warning for this instance's calls (D6 final Q9); default 0
#   Create [CMD [ARG...]]   assigns EVERY var; ARGs become ${inst}_args
#   Destroy                 frees ${inst}_args and ${inst}_argv (§1.9)
#   buildArgv               virtual; fills ${inst}_argv; RESULT = count
#   addArg ARG...           append to ${inst}_args (the un-modelled-option hatch)
#   clearArgs               empty ${inst}_args
#   argv NAME               buildArgv, then COPY into the caller's array;
#                           RESULT = count; runs NOTHING
#   run                     execute in the FOREGROUND, stdout inherited
#   each CB                 TPipe.each    [-0] [-c] CB   -- "${argv[@]}"
#   toArray NAME            TPipe.toArray [-0] [-c] NAME -- "${argv[@]}"
#   toList INST             TPipe.toList  [-0] [-c] INST -- "${argv[@]}"
#   first                   TPipe.first   [-0] [-c]      -- "${argv[@]}"
#   count                   TPipe.count   [-0] [-c]      -- "${argv[@]}"
#   lastRc                  RESULT = _lastRc
#   mapRc RAW               virtual; RESULT = the normalised rc
#
# ---- Reserved member names (PLAN §1.2) -------------------------------------
# TUtil owns `cmd crlf nul _lastRc subshellOk buildArgv addArg clearArgs argv
# run each toArray toList first count lastRc mapRc`; kklass owns `property call parent
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
        var  subshellOk
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

# tutil._prep MEMBER — the prologue every sink runs before it hands the argv to
# TPipe. It is the `run` prologue (PLAN §2.3) with the flag words added, in one
# place instead of five copies, so `each` and the four `func` sinks cannot drift
# apart and a descendant inherits ONE order.
#
#   1. `buildArgv` through `kk.call_silent` — VIRTUAL (a TGrep override runs),
#      and silent, so the callee's `kk._return` cannot print when the sink is
#      under `$( )` / `|` / `<( )`. Its rc is passed straight back: the base
#      answers 2 for an empty `cmd`, and nothing may run after it.
#   2. `command -v -- "$cmd"` (a builtin, no fork). A missing command is
#      `_lastRc=127` + ONE `kk.debug` line + rc 1, and NOTHING runs — without it
#      bash prints its own unconditional `command not found`, attributed to
#      kklass.sh. TPipe deliberately does not pre-check (it takes an arbitrary
#      argv); TUtil owns `cmd`, so it can. `_lastRc` IS updated here: the call
#      was well formed, it simply could not be executed.
#   3. the TPipe flag words, from the three properties: `nul == 1` -> `-0`,
#      `crlf == 1` -> `-c`, `subshellOk == 1` -> `-s`. They go into the caller's
#      `__tu_fl` ARRAY, never into an expansion-built option word (`${nul:+-0}`
#      is re-split by the caller's IFS — the bug tpipe PLAN §2.3 records).
#      Booleans are compared as strings: `(( nul ))` on a non-numeric property
#      is 0 in silence, or an arithmetic injection.
#
#      `subshellOk` is the object-style spelling of TPipe's `-s` (D6 final Q9)
#      and does nothing but silence TPipe's subshell warning for this
#      instance's sinks. The dynamically scoped `KK_SUBSHELL_OK=1` is the same
#      switch for one call or one block and needs no code here at all: it
#      reaches TPipe straight through this frame.
#
# `$cmd`, `$nul`, `$crlf`, `$_lastRc` and `$__inst__` are the member frame's
# namerefs/locals, reached through bash's DYNAMIC scoping exactly as the
# `tpipe._*` helpers reach their caller's `__tpi_*` — the assignment to
# `_lastRc` therefore writes through the property nameref into
# `${inst}_data[_lastRc]`. The single OUT parameter is `__tu_fl`, which the
# caller must have declared.
#
# rc 0 = ready to delegate; rc 1 = the command does not exist (diagnostic and
# `_lastRc` already done); anything else = buildArgv's own rc (2 for the base).
tutil._prep() {
    local __tu_m="$1" __tu_rc=0
    kk.call_silent "$__inst__" buildArgv || __tu_rc=$?
    if [[ "$__tu_rc" != "0" ]]; then
        return "$__tu_rc"
    fi
    if ! command -v -- "$cmd" >/dev/null 2>&1; then
        _lastRc=127
        kk.debug "Error: TUtil.$__tu_m: command not found: '$cmd'"
        return 1
    fi
    __tu_fl=()
    if [[ "$nul" == 1 ]]; then
        __tu_fl+=( -0 )
    fi
    if [[ "$crlf" == 1 ]]; then
        __tu_fl+=( -c )
    fi
    if [[ "$subshellOk" == 1 ]]; then
        __tu_fl+=( -s )
    fi
    return 0
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
    subshellOk=0
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

# ===========================================================================
# The five sinks (PLAN §2.3, §2.4)
#
# A sink is the wrapper AS A PRODUCER: it builds the argv, then hands it to
# TPipe's `--` form, which reads the records in THIS shell (never in the
# subshell a real `|` would create) so a callback keeps its object's state. The
# whole body of each of the five is
#
#     tutil._prep NAME                     # buildArgv + pre-check + flag words
#     TPipe.<sink> "${__tu_fl[@]}" [OP] -- "${argv[@]}"
#     <the ordered tail>
#
# and TPipe owns the OPERAND rules — `CB` must be a function, `NAME` must be a
# fillable output array, `INST` must have an `.Add` — so they are not repeated
# here (the one thing TPipe cannot know is this family's own local prefixes and
# extra arrays; `toArray` adds that check, see its body).
#
# ---- The ordered tail, and why the order is not negotiable ----------------
# An explicit `return` SKIPS the `kk._return "$RESULT"` trailer `build` compiles
# onto a `func`, and `kk._invoke` then restores the CALLER's RESULT
# (kklass.sh:399). A `func` that must answer both a value and a non-zero rc has
# exactly one spelling: `kk._return V; return N`, with V captured BEFORE
# anything else can overwrite RESULT. Hence:
#
#     TPipe.<sink> …          || __tu_prc=$?   # never bare: a non-zero rc here
#     local __tu_n="$RESULT"                   #   is normal, and `set -e` would
#     [[ rc == 2 ]] && kk._return ""; return 2 #   abort the caller
#     TPipe.lastRc; _lastRc="$RESULT"
#     [[ rc == 0 ]] && kk._return "$__tu_n"; return 0      # the consumer-stop
#     kk.call_silent … mapRc "$_lastRc"                    # case: NO mapRc
#     kk._return "$__tu_n"; return "$__tu_m"
#
#   * RESULT is saved IMMEDIATELY after the TPipe call — `TPipe.lastRc` and
#     `mapRc` both overwrite it.
#   * rc 2 from TPipe is a malformed CALL: nothing ran, so `_lastRc` is left
#     exactly as it was (a fresh instance still reads -1) and RESULT is ''.
#   * rc 0 from TPipe ALSO covers "the callback called TPipe.stop": the producer
#     was killed, so its raw rc is 141/143 and mapping it would turn the
#     consumer's success into rc 1. `mapRc` is applied only when TPipe itself
#     answered non-zero (PLAN §2.4).
#   * `first` is the exception to the last line: TPipe answering 1 means "there
#     was no record", which is `first`'s OWN answer and does not depend on what
#     the producer's status turned out to be. `mapRc` is still called there, for
#     its diagnostic side effect, but its value is discarded — see that body.
#
# ---- RESULT under `$( )`: `local __TPIPE_QUIET=1` -------------------------
# `tpipe._ret` prints TPipe's RESULT whenever `BASH_SUBSHELL > 0`, which is
# right for a caller that IS the answer and wrong for one that COMPOSES: the
# sink's own `kk._return` would print the same value a second time, and
# `$(u.count)` measured as `22`. `kk.call_silent` cannot help — `tpipe._ret`
# does not know `__kk_return_silent`, and kklass's thin static dispatcher sets
# that flag to 1 for every static body anyway, so it could not be reused.
#
# TPipe therefore carries a dedicated, DYNAMICALLY SCOPED opt-out (tpipe
# README §7): a composing caller declares `local __TPIPE_QUIET=1` in its own
# frame and the setting reaches the sink and ends with the frame, exactly as
# `local __TPIPE_STOP` does. ALL FIVE sinks declare it, `each` included, and no
# TPipe call here is redirected:
#
#   * `$(u.count)` prints `2` once — the member's own value, not TPipe's;
#   * `u.each cb | cat` carries ONLY what `cb` printed (a `>/dev/null` here
#     would have swallowed that, and a redirect on `each` was never possible);
#   * `$(u.toList l)` still shows whatever a printing `.Add` writes;
#   * `TPipe.lastRc`, our own bookkeeping, never reaches the stream either.
#
# The one consequence of dynamic scoping: a CALLBACK invoked by one of these
# sinks also sees the 1, so a callback that itself captures a sink
# (`x=$(TPipe.count -- …)`) must declare `local __TPIPE_QUIET=0` first.
# ===========================================================================

# each CB — call `CB RECORD` once per record, IN THIS SHELL.
#
# A `proc`: the record count is TPipe's RESULT, but `kk._invoke` restores the
# CALLER's RESULT when a body never calls `kk._return`, so `each` answers with
# its rc ALONE. Use `count` (or `toArray` and `${#arr[@]}`) when the number
# matters.
TUtil.each() {
    local -a __tu_fl=()
    local __TPIPE_QUIET=1
    local __tu_rc=0
    tutil._prep each || __tu_rc=$?
    if [[ "$__tu_rc" != "0" ]]; then
        return "$__tu_rc"
    fi
    local -n __tu_v="${__inst__}_argv"
    local __tu_prc=0
    TPipe.each "${__tu_fl[@]}" "${1:-}" -- "${__tu_v[@]}" || __tu_prc=$?
    if [[ "$__tu_prc" == "2" ]]; then
        return 2
    fi
    TPipe.lastRc
    _lastRc="$RESULT"
    if [[ "$__tu_prc" == "0" ]]; then
        return 0
    fi
    kk.call_silent "$__inst__" mapRc "$_lastRc"
    return "$RESULT"
}

# toArray NAME — REPLACE the caller's array with the records; RESULT = how many.
#
# The out-name is checked HERE as well as in TPipe, and the two checks do not
# overlap: `tpipe._isOutArr` knows kklass's reserved set and its own
# `__tpi_`/`__TPIPE_` space, but it cannot know that `__tu_v` is the nameref
# this very body holds on `${inst}_argv`, or that `${inst}_args`/`_argv` are the
# instance's own storage. Without this line `u.toArray __tu_v -- cmd` mapfiles
# the records straight into the instance's argv and the caller's array stays
# empty while RESULT reports a healthy count — the silent-loss class kcl
# README §1.7 exists to prevent. It runs FIRST, before `buildArgv`, so a refused
# call has still run nothing at all.
TUtil.toArray() {
    if tutil._badOut "${1:-}"; then
        kk.debug "Error: TUtil.toArray: bad output array name '${1:-}'"
        kk._return ""
        return 2
    fi
    local -a __tu_fl=()
    local __TPIPE_QUIET=1
    local __tu_rc=0
    tutil._prep toArray || __tu_rc=$?
    if [[ "$__tu_rc" != "0" ]]; then
        kk._return ""
        return "$__tu_rc"
    fi
    local -n __tu_v="${__inst__}_argv"
    local __tu_prc=0
    TPipe.toArray "${__tu_fl[@]}" "$1" -- "${__tu_v[@]}" || __tu_prc=$?
    local __tu_n="$RESULT"
    if [[ "$__tu_prc" == "2" ]]; then
        kk._return ""
        return 2
    fi
    TPipe.lastRc
    _lastRc="$RESULT"
    if [[ "$__tu_prc" == "0" ]]; then
        kk._return "$__tu_n"
        return 0
    fi
    kk.call_silent "$__inst__" mapRc "$_lastRc"
    local __tu_m="$RESULT"
    kk._return "$__tu_n"
    return "$__tu_m"
}

# toList INST — call `INST.Add RECORD` per record; RESULT = records OFFERED.
#
# Duck-typed by TPipe: anything with an `.Add` qualifies, and `.Add`'s own exit
# status is ignored (THashSet.Add answers 1 for a duplicate, TStringList.Add
# does under `dupError`), so RESULT counts what was offered, not what the list
# chose to keep.
TUtil.toList() {
    local -a __tu_fl=()
    local __TPIPE_QUIET=1
    local __tu_rc=0
    tutil._prep toList || __tu_rc=$?
    if [[ "$__tu_rc" != "0" ]]; then
        kk._return ""
        return "$__tu_rc"
    fi
    local -n __tu_v="${__inst__}_argv"
    local __tu_prc=0
    TPipe.toList "${__tu_fl[@]}" "${1:-}" -- "${__tu_v[@]}" || __tu_prc=$?
    local __tu_n="$RESULT"
    if [[ "$__tu_prc" == "2" ]]; then
        kk._return ""
        return 2
    fi
    TPipe.lastRc
    _lastRc="$RESULT"
    if [[ "$__tu_prc" == "0" ]]; then
        kk._return "$__tu_n"
        return 0
    fi
    kk.call_silent "$__inst__" mapRc "$_lastRc"
    local __tu_m="$RESULT"
    kk._return "$__tu_n"
    return "$__tu_m"
}

# first — RESULT = the FIRST record, then the producer is stopped.
#
# The one sink whose RESULT is a record and not a count, and the one whose rc is
# not `mapRc`'s. A record that was read puts TPipe on its consumer-stop path, so
# TPipe answers rc 0 and the producer's 141/143 never reaches `mapRc`. TPipe
# answering rc 1 means "there was NO record", and that is this member's answer
# too — rc 1 with RESULT='' — whatever the producer's status turned out to be: a
# `grep` that matched nothing (raw 1) and a tool that succeeded silently (raw 0)
# are the same question answered the same way, and `count` is the member to ask
# when the question is "how many". `mapRc` is still CALLED on that path, because
# a descendant's override is where a real tool error gets its `kk.debug` line
# (TGrep: raw >= 2), but its value is discarded.
TUtil.first() {
    local -a __tu_fl=()
    local __TPIPE_QUIET=1
    local __tu_rc=0
    tutil._prep first || __tu_rc=$?
    if [[ "$__tu_rc" != "0" ]]; then
        kk._return ""
        return "$__tu_rc"
    fi
    local -n __tu_v="${__inst__}_argv"
    local __tu_prc=0
    TPipe.first "${__tu_fl[@]}" -- "${__tu_v[@]}" || __tu_prc=$?
    local __tu_n="$RESULT"
    if [[ "$__tu_prc" == "2" ]]; then
        kk._return ""
        return 2
    fi
    TPipe.lastRc
    _lastRc="$RESULT"
    if [[ "$__tu_prc" == "0" ]]; then
        kk._return "$__tu_n"
        return 0
    fi
    # No record. `mapRc` runs for its diagnostic only — the rc below is 1
    # because `first` has no answer, not because the tool failed.
    kk.call_silent "$__inst__" mapRc "$_lastRc"
    kk._return ""
    return 1
}

# count — RESULT = the number of records. No callback, nothing to stop.
TUtil.count() {
    local -a __tu_fl=()
    local __TPIPE_QUIET=1
    local __tu_rc=0
    tutil._prep count || __tu_rc=$?
    if [[ "$__tu_rc" != "0" ]]; then
        kk._return ""
        return "$__tu_rc"
    fi
    local -n __tu_v="${__inst__}_argv"
    local __tu_prc=0
    TPipe.count "${__tu_fl[@]}" -- "${__tu_v[@]}" || __tu_prc=$?
    local __tu_n="$RESULT"
    if [[ "$__tu_prc" == "2" ]]; then
        kk._return ""
        return 2
    fi
    TPipe.lastRc
    _lastRc="$RESULT"
    if [[ "$__tu_prc" == "0" ]]; then
        kk._return "$__tu_n"
        return 0
    fi
    kk.call_silent "$__inst__" mapRc "$_lastRc"
    local __tu_m="$RESULT"
    kk._return "$__tu_n"
    return "$__tu_m"
}

# Finalize: extract the bodies above into the `TUtil` class and generate the
# per-instance wrappers.
build TUtil
