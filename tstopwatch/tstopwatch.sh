#!/bin/bash

# Re-source guard (kcl review 2026-09-06, X-SETU / decision D7): every unit is
# sourceable — and re-sourceable — from a script running `set -eu`, and building
# the class a second time is pure waste.
if [[ -n "${_TSTOPWATCH_SOURCED:-}" ]]; then
    return
fi
declare -g _TSTOPWATCH_SOURCED=1

# Character semantics are part of this unit's contract (kcl/README.md 1.6,
# decision D6); an empty environment means the C locale, where ${#s} counts
# bytes and ${s,,} corrupts UTF-8.
if [[ -z "${LC_ALL:-}${LC_CTYPE:-}${LANG:-}" ]]; then
    export LC_CTYPE=C.UTF-8
fi

# Source the kklass Pascal-style DSL front-end (don't override SCRIPT_DIR)
TSTOPWATCH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$TSTOPWATCH_DIR/../../kklass/kklass_pascal.sh"

# ---------------------------------------------------------------------------
# TStopwatch: elapsed-time measurement, an INSTANTIABLE class.
# Port of Delphi System.Diagnostics.TStopwatch (no FPC RTL equivalent — the
# spec is the Delphi DocWiki API; .NET Stopwatch semantics break ties; same
# Delphi-spec situation as tfile/tpath/tdirectory/tstringhelper).
#
# CLOCK: the EPOCHREALTIME builtin (microseconds since the epoch, bash >= 5.0,
# zero forks). 1 tick := 1 microsecond, frequency := 1000000 — the honest bash
# mapping (no 10 MHz QPC emulation; code that divides ticks by frequency keeps
# working unchanged). WALL clock: NTP steps / manual clock changes CAN affect
# a running measurement — bash has no monotonic builtin (documented wontfix).
#
# EPOCHREALTIME parsing (probed 2026-07-12 on 5.2.37 AND 5.3.9): the decimal
# separator is locale-dependent on 5.2 (de_DE/ru_RU -> comma; 5.3 always emits
# '.'), hence the ${er%[.,]*} parse; the fraction is 6 digits and 10# guards
# the leading-zero octal trap; the variable is read ONCE per stamp (two reads
# = two different times).
#
# STATE (three per-instance kklass vars, all integer µs unless noted):
#   _accum   accumulated over COMPLETED run segments
#   _t0      stamp when the current segment started; 0 while stopped
#            (meaningful only while _running=1)
#   _running 0/1
# Elapsed while running = _accum + (now - _t0); reads are pure (no state
# writes on read, S7). Epoch µs (~1.8e15) needs 64-bit arithmetic — bash
# $((...)) is 64-bit; never route stamps through 32-bit tools.
#
# GETTERS are `func`s surfaced as read-only properties. kklass call
# contract (kk._return): a DIRECT call sets RESULT and prints NOTHING; the
# value is echoed only in a subshell context, i.e. under $() capture. So
# `sw.elapsedMicroseconds; use $RESULT` is the fork-free path and
# `$(sw.elapsedMicroseconds)` is the convenience path. TStopwatch.getTimeStamp
# is a PLAIN file-level function with the same RESULT-only shape in ALL
# contexts: it is the tight-loop escape hatch (no dispatch, no echo ever).
#
# OVERHEAD POSITIONING: a kklass method call costs ~0.5 ms on MSYS2, dwarfing
# the µs clock — the object API structures measurements of MULTI-MILLISECOND
# work. For tight loops use TStopwatch.getTimeStamp deltas or raw
# $EPOCHREALTIME. bench.sh publishes self-overhead numbers (P2).
# ---------------------------------------------------------------------------
class TStopwatch
    public
        constructor Create
        destructor  Destroy
        proc Start
        proc Stop
        proc Reset
        proc Restart
        property isRunning read GetIsRunning
        func GetIsRunning
        property elapsedTicks read GetElapsedTicks
        func GetElapsedTicks
        property elapsedMicroseconds read GetElapsedMicroseconds
        func GetElapsedMicroseconds
        property elapsedMilliseconds read GetElapsedMilliseconds
        func GetElapsedMilliseconds
        property elapsedSeconds read GetElapsedSeconds
        func GetElapsedSeconds
        property frequency read GetFrequency
        func GetFrequency
        property isHighResolution read GetIsHighResolution
        func GetIsHighResolution
        var _accum
        var _t0
        var _running
end

# ---- file-level helpers (plain functions, no kklass dispatch) ---------------

# Boolean answer (finding G3-12, default R8, kcl/README.md 1.3): the exit
# status carries the answer AND true|false lands in RESULT, so both
# `if sw.isRunning; then` and `$(sw.isRunning)` read correctly.
#
# $1 = 0 for true, anything else for false. The CALLER must end on an explicit
# `return`: kklass appends `kk._return "$RESULT"` to every `func` body, which
# would otherwise flatten the status to 0 and print a second time under `$( )`.
TStopwatch._retBool() {
    if [[ "$1" == "0" ]]; then
        kk._return "true"
    else
        kk._return "false"
    fi
    return "${1:-0}"
}

# Internal: current time as integer microseconds -> __tsw_now (dynamic scope:
# callers do `local __tsw_now; TStopwatch._nowUs`). Zero forks, no echo.
TStopwatch._nowUs() {
    local __tsw_er=$EPOCHREALTIME
    __tsw_now=$(( ${__tsw_er%[.,]*} * 1000000 + 10#${__tsw_er##*[.,]} ))
}

# Internal: elapsed µs of the CURRENT instance -> __tsw_us. Must be called
# from a method body: bash dynamic scoping supplies the caller's injected
# _accum/_t0/_running namerefs. Callers do `local __tsw_us; TStopwatch._elapsedUs`.
TStopwatch._elapsedUs() {
    if [[ "$_running" == "1" ]]; then
        local __tsw_er=$EPOCHREALTIME
        __tsw_us=$(( _accum + ( ${__tsw_er%[.,]*} * 1000000 + 10#${__tsw_er##*[.,]} ) - _t0 ))
    else
        __tsw_us=$_accum
    fi
}

# Public: the Delphi class function TStopwatch.GetTimeStamp (S8) — the raw
# current stamp in integer µs. PLAIN function and RESULT-ONLY by design (see
# header): `TStopwatch.getTimeStamp; t0=$RESULT` is the fork-free tight-loop
# idiom. Monotone-nondecreasing between calls modulo wall-clock steps.
TStopwatch.getTimeStamp() {
    local __tsw_er=$EPOCHREALTIME
    RESULT=$(( ${__tsw_er%[.,]*} * 1000000 + 10#${__tsw_er##*[.,]} ))
}

# ---- method bodies (real bash functions; extracted by `build`) --------------

TStopwatch.Create() {
    # Delphi TStopwatch.Create yields a STOPPED watch with elapsed 0 (S1).
    # Optional token 'startnew' (exact lowercase) = the TStopwatch.StartNew
    # form (S2): created already running (token-argument style per
    # TObjectDictionary). Fields are initialized BEFORE token validation, so
    # even on rc=1 the instance is a valid stopped watch.
    _accum=0
    _t0=0
    _running=0
    if [[ -n "${1:-}" ]]; then
        if [[ "$1" == "startnew" ]]; then
            local __tsw_now
            TStopwatch._nowUs
            _t0=$__tsw_now
            _running=1
        else
            # printf, not echo: a diagnostic that starts with -e/-n would be
            # swallowed as an option (X-ECHO, finding G1-13).
            kk.debug "Error: TStopwatch.Create: unknown token '$1' (expected 'startnew')"
            return 1
        fi
    fi
}

TStopwatch.Destroy() {
    # No external storage: all state lives in the three kklass instance vars,
    # torn down by kklass on delete.
    :
}

TStopwatch.Start() {
    # Begins a segment; RESUMES after Stop — _accum keeps prior segments (S3).
    # S4: Start while already running is a no-op (NOT a reset, NOT an error).
    [[ "$_running" == "1" ]] && return 0
    local __tsw_now
    TStopwatch._nowUs
    _t0=$__tsw_now
    _running=1
}

TStopwatch.Stop() {
    # Pauses: the finished segment folds into _accum (S3).
    # S4: Stop while already stopped is a no-op.
    [[ "$_running" != "1" ]] && return 0
    local __tsw_now
    TStopwatch._nowUs
    _accum=$(( _accum + __tsw_now - _t0 ))
    _running=0
    _t0=0
}

TStopwatch.Reset() {
    # S5: stops AND zeroes the accumulated time (running or not).
    _accum=0
    _t0=0
    _running=0
}

TStopwatch.Restart() {
    # S5: Reset + Start as ONE atomic call — always leaves the watch running
    # with elapsed ~ 0.
    local __tsw_now
    TStopwatch._nowUs
    _accum=0
    _t0=$__tsw_now
    _running=1
}

TStopwatch.GetIsRunning() {
    # G3-12 / R8: rc IS the answer, and RESULT carries true|false. Until P6 this
    # returned the numbers 0/1 — the fifth boolean convention in kcl. DOCUMENTED
    # API CHANGE: `[[ "$RESULT" == 1 ]]` becomes `if sw.isRunning; then`.
    if [[ "$_running" == "1" ]]; then
        TStopwatch._retBool 0
        return 0
    fi
    TStopwatch._retBool 1
    return 1
}

TStopwatch.GetElapsedMicroseconds() {
    # The native unit — lossless (bash-convenience extra; documented in
    # TEST_COVERAGE_NOTES). Pure read, valid in every state (S7).
    local __tsw_us
    TStopwatch._elapsedUs
    RESULT=$__tsw_us
}

TStopwatch.GetElapsedTicks() {
    # 1 tick := 1 µs (§2.2 of PLAN.md) — numerically identical to
    # elapsedMicroseconds; kept as its own member for Delphi-shaped call sites.
    local __tsw_us
    TStopwatch._elapsedUs
    RESULT=$__tsw_us
}

TStopwatch.GetElapsedMilliseconds() {
    # S6: Delphi Int64 division — TRUNCATES (1999 µs -> 1 ms), not rounds.
    local __tsw_us
    TStopwatch._elapsedUs
    RESULT=$(( __tsw_us / 1000 ))
}

TStopwatch.GetElapsedSeconds() {
    # Bash-convenience extra (Delphi exposes seconds only via TTimeSpan,
    # which is not ported). Truncating, like the ms getter.
    local __tsw_us
    TStopwatch._elapsedUs
    RESULT=$(( __tsw_us / 1000000 ))
}

TStopwatch.GetFrequency() {
    # Class constant: ticks per second = 1e6 (1 tick = 1 µs, §2.2). Code that
    # divides elapsedTicks by frequency keeps working unchanged.
    RESULT=1000000
}

TStopwatch.GetIsHighResolution() {
    # Constant true: EPOCHREALTIME is the µs builtin clock. G3-12 / R8 — rc 0
    # and RESULT='true' (it used to be the number 1).
    TStopwatch._retBool 0
    return 0
}

# Finalize the class.
build TStopwatch
