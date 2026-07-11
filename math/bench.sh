#!/bin/bash
# Micro-benchmark for math hot paths (P8.3).
#   Tier A (pure-bash core): target <= 0.3 ms/call, zero forks.
#   Tier B (float engine):   report the pipe round-trip latency (cold path,
#                            NOT held to the 0.3 ms target).
# Uses the EPOCHREALTIME builtin (itself fork-free). Run: bash bench.sh [iters]

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/math.sh"

N=${1:-3000}
_now_us() { local er=$EPOCHREALTIME; echo $(( ${er%[.,]*} * 1000000 + 10#${er##*[.,]} )); }

bench() {  # label  command...
    local label=$1; shift
    local t0 t1 i
    t0=$(_now_us)
    for (( i=0; i<N; i++ )); do "$@" >/dev/null; done
    t1=$(_now_us)
    local us_per=$(( (t1 - t0) / N ))
    printf '  %-22s %6d us/call  (%d.%03d ms)\n' "$label" "$us_per" "$(( us_per/1000 ))" "$(( us_per%1000 ))"
    (( us_per <= 300 )) || echo "    WARNING: above the 0.3 ms/call target"
}

benchE() {  # label  op args...   (Tier-B engine, no $() capture)
    local label=$1; shift
    local t0 t1 i
    t0=$(_now_us)
    for (( i=0; i<N; i++ )); do math._fe "$@" >/dev/null; done
    t1=$(_now_us)
    local us_per=$(( (t1 - t0) / N ))
    printf '  %-22s %6d us/call  (%d.%03d ms)\n' "$label" "$us_per" "$(( us_per/1000 ))" "$(( us_per%1000 ))"
}

echo "math micro-benchmark  (bash ${BASH_VERSION}, N=$N)"
echo
benchI() {  # informational (no 0.3 ms warning)
    local label=$1; shift
    local t0 t1 i
    t0=$(_now_us)
    for (( i=0; i<N; i++ )); do "$@" >/dev/null; done
    t1=$(_now_us)
    local us_per=$(( (t1 - t0) / N ))
    printf '  %-22s %6d us/call  (%d.%03d ms)\n' "$label" "$us_per" "$(( us_per/1000 ))" "$(( us_per%1000 ))"
}

echo "Tier A — pure-bash integer core (target <= 0.3 ms/call):"
bench "min"          math.min 3 7
bench "max"          math.max 3 7
bench "sign"         math.sign -5
bench "inRange"      math.inRange 5 1 10
bench "ensureRange"  math.ensureRange 99 1 10
bench "compareValue" math.compareValue 3 5
bench "ifThen"       math.ifThen true 9 4
bench "ceil"         math.ceil -2.1
bench "floor"        math.floor -2.1
bench "divMod"       math.divMod 17 5
bench "intPower"     math.intPower 2 10
bench "sumInt"       math.sumInt 1 2 3 4 5
bench "randomRange"  math.randomRange 1 100
bench "isNan"        math.isNan 1.0

echo
echo "  decimal-operand comparison (pure-bash decimal split; ~0.4 ms, fork-free):"
benchI "max (decimal)"   math.max -2.5 -2.4
benchI "sign (decimal)"  math.sign -3.14

echo
echo "Tier B — float engine (pipe round-trip; cold path):"
math.feStart
benchE "sin"     sin 1
benchE "sqrt"    sqrt 2
benchE "roundTo" roundto 2.5 0
benchE "power"   power 2 10
benchE "mean(8)" amean 2 4 4 4 5 5 7 9
math._fe_stop

echo
echo "zero-fork check (Tier-A core with empty PATH):"
if o1=$( PATH=''; math.sign -5 ) && [[ "$o1" == -1 ]] \
   && o2=$( PATH=''; math.ceil 2.1 ) && [[ "$o2" == 3 ]] \
   && o3=$( PATH=''; math.divMod 10 3 ) && [[ "$o3" == "3 1" ]] \
   && o4=$( PATH=''; math.sumInt 1 2 3 ) && [[ "$o4" == 6 ]]; then
    echo "  OK — Tier-A hot paths spawned no external process"
else
    echo "  FAIL — a Tier-A path forked ([$o1] [$o2] [$o3] [$o4])"
fi

echo
echo "single-engine-process check:"
math.feStart
p=$__MATH_FE_PID
for (( i=0; i<100; i++ )); do math._fe sin "$i" >/dev/null; done
if [[ "$__MATH_FE_PID" == "$p" ]] && kill -0 "$p" 2>/dev/null; then
    echo "  OK — one awk co-process reused across 100 calls (pid $p)"
else
    echo "  FAIL — engine pid changed or died"
fi
math._fe_stop
