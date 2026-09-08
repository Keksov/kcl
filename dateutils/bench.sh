#!/bin/bash
# Micro-benchmark for dateutils hot paths (P7.3; caller section added in P6).
#
# Two different costs live here and the README used to quote only the first:
#
#   CALLEE  dispatch + body, read through $RESULT. Target ~0.3 ms/call on bash
#           5.2 thin dispatch. Since P6 every public member also validates its
#           numeric arguments (findings G3-01/G3-04), which costs one kk.isInt
#           (~52 us) per argument — dayOfTheWeek, which validated nothing at
#           all before, roughly doubled.
#   CALLER  what a call site actually pays. Before P6 every member printed its
#           answer, so `$(dateutils.yearOf $k)` — a fork — was the ONLY way to
#           read one, at ~19 ms on MSYS2. Decision D3 made the direct call the
#           supported path; that is the >100x line at the bottom.
#
# Run: bash bench.sh [iterations]

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

echo
echo "caller cost — the D3 return contract (N=300):"
NC=300
TStopwatch.getTimeStamp; c0=$RESULT
for (( i=0; i<NC; i++ )); do dateutils.yearOf "$K"; done
TStopwatch.getTimeStamp; c1=$RESULT
for (( i=0; i<NC; i++ )); do v="$(dateutils.yearOf "$K")"; done
TStopwatch.getTimeStamp; c2=$RESULT
direct_us=$(( (c1 - c0) / NC ))
forked_us=$(( (c2 - c1) / NC ))
printf '  %-26s %6d us/call\n' "direct (RESULT)" "$direct_us"
printf '  %-26s %6d us/call\n' "\$( ) capture" "$forked_us"
if (( direct_us > 0 )); then
    printf '  %-26s %6dx\n' "direct is faster by" "$(( forked_us / direct_us ))"
fi

echo
echo "zero-fork check (empty PATH):"
if ( PATH=""; dateutils.yearOf "$K" >/dev/null; [[ "$RESULT" == 2011 ]] ); then
    echo "  OK — hot path spawned no external process"
else
    echo "  FAIL — a fork happened or RESULT was wrong"
fi
