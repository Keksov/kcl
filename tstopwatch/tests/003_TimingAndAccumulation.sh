#!/bin/bash
# 003_TimingAndAccumulation.sh - TStopwatch real-time behavior: S3
# (accumulation across Start/Stop cycles), S2 (startnew measures at once),
# S8 (getTimeStamp deltas + RESULT-only contract).
# Waits are ARITHMETIC BUSY-LOOPS on the same EPOCHREALTIME clock the unit
# uses (P0 pin): lower bounds are guaranteed BY CONSTRUCTION (never flaky);
# upper bounds are deliberately wide (+10 s) and only catch unit confusions
# (µs-vs-ms-vs-ns), not scheduler noise. No external `sleep` (fork).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

TSW_DIR="$SCRIPT_DIR/.."
source "$TSW_DIR/tstopwatch.sh"

TEST_NAME="$(basename "$0" .sh)"
kt_test_init "$TEST_NAME" "$SCRIPT_DIR" "$@"

kt_test_section "003: TStopwatch timing and accumulation"

WIDE=10000000   # +10 s upper margin: catches unit confusion, immune to CI noise

# fork-free wait: spin on the SAME clock until >= target µs elapsed
_t_busy_us() {
    local __t_target=$1 __t_er __t_t0 __t_now
    __t_er=$EPOCHREALTIME; __t_t0=$(( ${__t_er%[.,]*} * 1000000 + 10#${__t_er##*[.,]} ))
    while :; do
        __t_er=$EPOCHREALTIME; __t_now=$(( ${__t_er%[.,]*} * 1000000 + 10#${__t_er##*[.,]} ))
        (( __t_now - __t_t0 >= __t_target )) && break
    done
}

# Test: a single running segment covers the busy window (S3, single segment)
kt_test_start "Running segment: elapsed >= 15 ms busy window, < wide upper"
TStopwatch.new sw
sw.Start
_t_busy_us 15000
sw.Stop
sw.elapsedMicroseconds >/dev/null; e1=$RESULT
if (( e1 >= 15000 && e1 < 15000 + WIDE )); then
    kt_test_pass "elapsed $e1 µs in [15000, 15000+10s)"
else
    kt_test_fail "elapsed $e1 µs outside [15000, 15000+WIDE)"
fi

# Test: stopped gap does NOT count (exact freeze during the gap)
kt_test_start "Stopped gap between segments adds nothing (exact)"
sw.elapsedMicroseconds >/dev/null; g1=$RESULT
_t_busy_us 10000
sw.elapsedMicroseconds >/dev/null; g2=$RESULT
if [[ "$g1" == "$g2" ]]; then
    kt_test_pass "still $g1 µs after a 10 ms stopped gap"
else
    kt_test_fail "grew while stopped: $g1 -> $g2"
fi

# Test: second segment ACCUMULATES on top of the first (S3)
kt_test_start "Accumulation: two 15 ms segments -> elapsed >= 30 ms (S3)"
sw.Start
_t_busy_us 15000
sw.Stop
sw.elapsedMicroseconds >/dev/null; e2=$RESULT
if (( e2 >= 30000 && e2 < 30000 + WIDE && e2 > e1 )); then
    kt_test_pass "total $e2 µs >= 30000 and > segment1 ($e1)"
else
    kt_test_fail "total $e2 µs (segment1 $e1)"
fi
sw.delete

# Test: startnew watch measures immediately (S2)
kt_test_start "startnew: created running, covers a 10 ms window at once (S2)"
TStopwatch.new swn startnew
_t_busy_us 10000
swn.elapsedMicroseconds >/dev/null; en=$RESULT
if [[ "$(swn.isRunning)" == "1" ]] && (( en >= 10000 && en < 10000 + WIDE )); then
    kt_test_pass "running, elapsed $en µs >= 10000"
else
    kt_test_fail "run=$(swn.isRunning) elapsed=$en"
fi
swn.delete

# Test: getTimeStamp deltas bound a busy window from below (S8)
kt_test_start "getTimeStamp: delta across 10 ms busy window >= 10000 µs (S8)"
TStopwatch.getTimeStamp; ts1=$RESULT
_t_busy_us 10000
TStopwatch.getTimeStamp; ts2=$RESULT
if (( ts2 - ts1 >= 10000 && ts2 - ts1 < 10000 + WIDE )); then
    kt_test_pass "delta $(( ts2 - ts1 )) µs in [10000, 10000+10s)"
else
    kt_test_fail "ts1=$ts1 ts2=$ts2 delta=$(( ts2 - ts1 ))"
fi

# Test: getTimeStamp is monotone-nondecreasing across immediate calls (S8;
# wall-clock steps aside — documented wontfix)
kt_test_start "getTimeStamp: nondecreasing across 3 immediate calls"
TStopwatch.getTimeStamp; m1=$RESULT
TStopwatch.getTimeStamp; m2=$RESULT
TStopwatch.getTimeStamp; m3=$RESULT
if (( m2 >= m1 && m3 >= m2 )); then
    kt_test_pass "$m1 <= $m2 <= $m3"
else
    kt_test_fail "$m1, $m2, $m3"
fi

# Test: getTimeStamp is RESULT-only — NO stdout (tight-loop contract)
kt_test_start "getTimeStamp: sets RESULT, prints NOTHING"
outf="${TMPDIR:-/tmp}/tsw003_out.$$"
RESULT=""
TStopwatch.getTimeStamp >"$outf"
bytes=$(wc -c <"$outf")
rm -f "$outf"
if [[ "$bytes" -eq 0 && "$RESULT" =~ ^[0-9]+$ ]] && (( RESULT > 1000000000000000 )); then
    kt_test_pass "0 bytes on stdout; RESULT=$RESULT (epoch-µs magnitude)"
else
    kt_test_fail "stdout-bytes=$bytes RESULT='$RESULT'"
fi

kt_test_log "003_TimingAndAccumulation.sh completed"
