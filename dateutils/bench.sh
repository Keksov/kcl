#!/bin/bash
# Micro-benchmark for dateutils hot paths (P7.3).
# Measures pure dispatch+body cost (no $() capture) using the EPOCHREALTIME
# builtin — itself fork-free. Target: extraction/arithmetic <= ~0.3 ms/call on
# bash 5.2 thin dispatch. Run: bash bench.sh [iterations]

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/dateutils.sh"
source "$DIR/../tstopwatch/tstopwatch.sh"   # shared, tested µs clock (fork-free)

N=${1:-3000}
K=$(dateutils.encodeDateTime 2011 3 26 19 15 30 555)
K2=$(dateutils.encodeDate 2000 1 1)

# Timing primitive: TStopwatch.getTimeStamp (kcl/tstopwatch) — one tested,
# locale-safe µs clock shared by every kcl bench; RESULT-only, no fork.

bench() {  # label  command...
    local label=$1; shift
    local t0 t1 i
    TStopwatch.getTimeStamp; t0=$RESULT
    for (( i=0; i<N; i++ )); do "$@" "$K" "$K2" >/dev/null; done
    TStopwatch.getTimeStamp; t1=$RESULT
    local us_per=$(( (t1 - t0) / N ))
    printf '  %-26s %6d us/call  (%d.%03d ms)\n' "$label" "$us_per" "$(( us_per/1000 ))" "$(( us_per%1000 ))"
    (( us_per <= 300 )) || echo "    WARNING: above the 0.3 ms/call target"
}

echo "dateutils micro-benchmark  (bash ${BASH_VERSION}, N=$N, pure dispatch, no \$() capture)"
bench "yearOf"        dateutils.yearOf
bench "monthOf"       dateutils.monthOf
bench "dayOfTheWeek"  dateutils.dayOfTheWeek
bench "incDay"        dateutils.incDay
bench "incMonth"      dateutils.incMonth
bench "daysBetween"   dateutils.daysBetween
bench "compareDateTime" dateutils.compareDateTime
bench "weekOfTheYear" dateutils.weekOfTheYear

echo "zero-fork check (empty PATH):"
if out=$( PATH=''; dateutils.yearOf "$K" ) && [[ "$out" == 2011 ]]; then
    echo "  OK — hot path spawned no external process"
else
    echo "  FAIL — a fork happened (out=$out)"
fi
