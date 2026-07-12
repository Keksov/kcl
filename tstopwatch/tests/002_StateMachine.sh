#!/bin/bash
# 002_StateMachine.sh - TStopwatch state machine: EXACT, timing-free tests.
# S1 (fresh stopped/zero), S4 (double-transition no-ops), S5 (Reset/Restart),
# S6 (truncating ms — proven by white-box seeding _accum, no real time
# involved), S7 (reads are pure), constants, instance independence.
# Spec basis: Delphi DocWiki TStopwatch + .NET Stopwatch (tiebreaker); no FPC
# tests exist — every case has a TEST_COVERAGE_NOTES.md row.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

TSW_DIR="$SCRIPT_DIR/.."
source "$TSW_DIR/tstopwatch.sh"

TEST_NAME="$(basename "$0" .sh)"
kt_test_init "$TEST_NAME" "$SCRIPT_DIR" "$@"

kt_test_section "002: TStopwatch state machine (exact, timing-free)"

_t_now_us() { local er=$EPOCHREALTIME; echo $(( ${er%[.,]*} * 1000000 + 10#${er##*[.,]} )); }

# Test: fresh watch — every getter reads 0, not running (S1)
kt_test_start "Fresh watch: stopped, every elapsed getter 0 (S1)"
TStopwatch.new sw
if [[ "$(sw.isRunning)" == "0" && "$(sw.elapsedMicroseconds)" == "0" \
      && "$(sw.elapsedTicks)" == "0" && "$(sw.elapsedMilliseconds)" == "0" \
      && "$(sw.elapsedSeconds)" == "0" ]]; then
    kt_test_pass "isRunning 0; us/ticks/ms/s all 0"
else
    kt_test_fail "run=$(sw.isRunning) us=$(sw.elapsedMicroseconds) ticks=$(sw.elapsedTicks) ms=$(sw.elapsedMilliseconds) s=$(sw.elapsedSeconds)"
fi

# Test: Start switches to running; reads work while running (S7)
kt_test_start "Start: isRunning 1; reads valid and nondecreasing while running (S7)"
sw.Start
sw.elapsedMicroseconds >/dev/null; r1=$RESULT
sw.elapsedMicroseconds >/dev/null; r2=$RESULT
if [[ "$(sw.isRunning)" == "1" ]] && (( r1 >= 0 && r2 >= r1 )); then
    kt_test_pass "running; successive reads $r1 <= $r2"
else
    kt_test_fail "run=$(sw.isRunning) r1=$r1 r2=$r2"
fi

# Test: reads have NO side effects (S7) — state triple unchanged by getters
kt_test_start "Reads are pure: _accum/_t0/_running untouched by getters (S7)"
b_accum=${sw_data[_accum]}; b_t0=${sw_data[_t0]}; b_run=${sw_data[_running]}
sw.elapsedMicroseconds >/dev/null
sw.elapsedTicks        >/dev/null
sw.elapsedMilliseconds >/dev/null
sw.elapsedSeconds      >/dev/null
sw.isRunning           >/dev/null
if [[ "${sw_data[_accum]}" == "$b_accum" && "${sw_data[_t0]}" == "$b_t0" && "${sw_data[_running]}" == "$b_run" ]]; then
    kt_test_pass "state triple identical after 5 getter calls"
else
    kt_test_fail "before=($b_accum,$b_t0,$b_run) after=(${sw_data[_accum]},${sw_data[_t0]},${sw_data[_running]})"
fi

# Test: Start while running = no-op (S4) — the segment start is NOT restarted
kt_test_start "Double Start: no-op, _t0 unchanged, still running (S4)"
t0a=${sw_data[_t0]}
sw.Start
t0b=${sw_data[_t0]}
if [[ "$t0a" == "$t0b" && "$(sw.isRunning)" == "1" ]]; then
    kt_test_pass "second Start left _t0=$t0a and the run flag intact"
else
    kt_test_fail "t0: $t0a -> $t0b run=$(sw.isRunning)"
fi

# Test: Stop folds the segment; second Stop is a no-op (S3+S4)
kt_test_start "Stop then double Stop: accumulates once, second is no-op (S4)"
sw.Stop
aa=${sw_data[_accum]}
sw.Stop
ab=${sw_data[_accum]}
if [[ "$(sw.isRunning)" == "0" && "$aa" == "$ab" ]] && (( aa >= 0 )); then
    kt_test_pass "stopped; _accum stable at $aa across double Stop"
else
    kt_test_fail "run=$(sw.isRunning) accum: $aa -> $ab"
fi

# Test: elapsed is FROZEN while stopped — two reads EXACTLY equal
kt_test_start "Stopped watch is frozen: two elapsed reads exactly equal"
sw.elapsedMicroseconds >/dev/null; f1=$RESULT
sw.elapsedMicroseconds >/dev/null; f2=$RESULT
if [[ "$f1" == "$f2" ]]; then
    kt_test_pass "frozen at $f1 µs (exact equality)"
else
    kt_test_fail "drift while stopped: $f1 != $f2"
fi

# Test: Reset on a RUNNING watch stops it and zeroes (S5)
kt_test_start "Reset on running watch: stops AND zeroes (S5)"
sw.Start
sw.Reset
if [[ "$(sw.isRunning)" == "0" && "${sw_data[_accum]}" == "0" && "${sw_data[_t0]}" == "0" \
      && "$(sw.elapsedMicroseconds)" == "0" ]]; then
    kt_test_pass "stopped, _accum=0, _t0=0, elapsed 0"
else
    kt_test_fail "run=$(sw.isRunning) accum=${sw_data[_accum]} t0=${sw_data[_t0]}"
fi

# Test: Restart = zero + start atomically; _t0 inside the call window (S5)
kt_test_start "Restart: running with elapsed ~0, _t0 in call window (S5)"
sw_data[_accum]=999999   # pre-load garbage that Restart must discard
before=$(_t_now_us)
sw.Restart
after=$(_t_now_us)
t0=${sw_data[_t0]}
if [[ "$(sw.isRunning)" == "1" && "${sw_data[_accum]}" == "0" ]] \
   && (( t0 >= before && t0 <= after )); then
    kt_test_pass "running, accum zeroed, $before <= t0 <= $after"
else
    kt_test_fail "run=$(sw.isRunning) accum=${sw_data[_accum]} t0=$t0 window=[$before,$after]"
fi
sw.Reset

# Test: ms getter TRUNCATES (S6) — white-box _accum seeding, no real time
kt_test_start "ElapsedMilliseconds truncates: 999us->0, 1999us->1 (S6)"
sw_data[_accum]=999
ms1=$(sw.elapsedMilliseconds)
sw_data[_accum]=1999
ms2=$(sw.elapsedMilliseconds)
if [[ "$ms1" == "0" && "$ms2" == "1" ]]; then
    kt_test_pass "999->0, 1999->1 (Int64-div semantics)"
else
    kt_test_fail "999->$ms1 (want 0), 1999->$ms2 (want 1)"
fi

# Test: seconds getter truncates the same way
kt_test_start "elapsedSeconds truncates: 1999999us->1, 2000000us->2"
sw_data[_accum]=1999999
s1=$(sw.elapsedSeconds)
sw_data[_accum]=2000000
s2=$(sw.elapsedSeconds)
if [[ "$s1" == "1" && "$s2" == "2" ]]; then
    kt_test_pass "1999999->1, 2000000->2"
else
    kt_test_fail "1999999->$s1 (want 1), 2000000->$s2 (want 2)"
fi

# Test: ticks are µs — identical values while stopped (exact)
kt_test_start "elapsedTicks == elapsedMicroseconds (1 tick = 1 µs)"
sw_data[_accum]=123456
if [[ "$(sw.elapsedTicks)" == "123456" && "$(sw.elapsedMicroseconds)" == "123456" ]]; then
    kt_test_pass "both read 123456"
else
    kt_test_fail "ticks=$(sw.elapsedTicks) us=$(sw.elapsedMicroseconds)"
fi

# Test: ticks/frequency ratio gives whole seconds (Delphi-shaped division)
kt_test_start "ticks / frequency == seconds (ratio contract)"
sw_data[_accum]=2500000
sw.elapsedTicks >/dev/null; t=$RESULT
sw.frequency    >/dev/null; f=$RESULT
if (( t / f == 2 )) && [[ "$(sw.elapsedSeconds)" == "2" ]]; then
    kt_test_pass "2500000 / 1000000 == 2 == elapsedSeconds"
else
    kt_test_fail "t=$t f=$f t/f=$(( t / f )) s=$(sw.elapsedSeconds)"
fi
sw.Reset

# Test: constants hold in every state
kt_test_start "frequency/isHighResolution constant across states"
c1="$(sw.frequency)/$(sw.isHighResolution)"
sw.Start
c2="$(sw.frequency)/$(sw.isHighResolution)"
sw.Stop
c3="$(sw.frequency)/$(sw.isHighResolution)"
if [[ "$c1" == "1000000/1" && "$c2" == "1000000/1" && "$c3" == "1000000/1" ]]; then
    kt_test_pass "1000000/1 fresh, running and stopped"
else
    kt_test_fail "fresh=$c1 running=$c2 stopped=$c3"
fi
sw.Reset

# Test: two watches are fully independent
kt_test_start "Independence: ops on one watch never touch the other"
TStopwatch.new wA
TStopwatch.new wB startnew
wA_before=("${wA_data[_accum]}" "${wA_data[_t0]}" "${wA_data[_running]}")
wB.Stop; wB.Start; wB.Reset; wB.Restart
if [[ "${wA_data[_accum]}" == "${wA_before[0]}" && "${wA_data[_t0]}" == "${wA_before[1]}" \
      && "${wA_data[_running]}" == "${wA_before[2]}" && "$(wB.isRunning)" == "1" ]]; then
    kt_test_pass "wA untouched by wB's full op cycle"
else
    kt_test_fail "wA=(${wA_data[_accum]},${wA_data[_t0]},${wA_data[_running]}) expected (${wA_before[*]})"
fi
wA.delete; wB.delete

# cleanup
sw.delete

kt_test_log "002_StateMachine.sh completed"
