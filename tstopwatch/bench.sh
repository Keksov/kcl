#!/bin/bash
# Micro-benchmark for tstopwatch (P2.2). Publishes the honest-positioning
# numbers README.md quotes:
#   - clock primitive costs (raw EPOCHREALTIME parse vs TStopwatch.getTimeStamp);
#   - object-API costs (kklass dispatch included) per getter / per Start+Stop;
#   - INSTRUMENT SELF-TIME: what an EMPTY Start;Stop bracket measures — the
#     systematic bias added to any interval measured through the object API;
#   - dispatch-vs-raw delta and the zero-fork check.
# Dog-fooding: the benchmark times itself with TStopwatch.getTimeStamp.
# Run: bash bench.sh [N_dispatch] [N_fast]   (defaults 300 / 10000)

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/tstopwatch.sh"

N=${1:-300}          # iterations for dispatched (kklass) calls, ~0.5 ms each
NFAST=${2:-10000}    # iterations for plain-function / inline paths, ~µs each

report() {  # label total_us iters  -> integer us/call
    local us_per=$(( $2 / $3 ))
    printf '  %-34s %6d us/call  (%d.%03d ms)\n' "$1" "$us_per" $(( us_per/1000 )) $(( us_per%1000 ))
}
report_frac() {  # label total_us iters  -> tenths precision for µs-scale paths
    local x10=$(( $2 * 10 / $3 ))
    printf '  %-34s %4d.%d us/call\n' "$1" $(( x10/10 )) $(( x10%10 ))
}

echo "tstopwatch micro-benchmark  (bash ${BASH_VERSION}, N=$N dispatched / $NFAST fast)"
echo

echo "Clock primitives (plain functions, no kklass dispatch):"
TStopwatch.getTimeStamp; t0=$RESULT
for (( i=0; i<NFAST; i++ )); do
    er=$EPOCHREALTIME; us=$(( ${er%[.,]*} * 1000000 + 10#${er##*[.,]} ))
done
TStopwatch.getTimeStamp; t1=$RESULT
report_frac "raw EPOCHREALTIME parse (inline)" $(( t1-t0 )) "$NFAST"
raw_x10=$(( (t1-t0) * 10 / NFAST ))

TStopwatch.getTimeStamp; t0=$RESULT
for (( i=0; i<NFAST; i++ )); do
    TStopwatch.getTimeStamp
done
TStopwatch.getTimeStamp; t1=$RESULT
report_frac "TStopwatch.getTimeStamp" $(( t1-t0 )) "$NFAST"
gts_x10=$(( (t1-t0) * 10 / NFAST ))

echo
echo "Object API — FUNC forms (kklass dispatch, fork-free; use \$RESULT):"
TStopwatch.new sw

TStopwatch.getTimeStamp; t0=$RESULT
for (( i=0; i<N; i++ )); do sw.Start; sw.Stop; done
TStopwatch.getTimeStamp; t1=$RESULT
report "Start+Stop pair" $(( t1-t0 )) "$N"
pair_us=$(( (t1-t0) / N ))

sw.Reset
TStopwatch.getTimeStamp; t0=$RESULT
for (( i=0; i<N; i++ )); do sw.GetElapsedMicroseconds >/dev/null; done
TStopwatch.getTimeStamp; t1=$RESULT
report "GetElapsedMicroseconds (stopped)" $(( t1-t0 )) "$N"
getter_us=$(( (t1-t0) / N ))

sw.Start
TStopwatch.getTimeStamp; t0=$RESULT
for (( i=0; i<N; i++ )); do sw.GetElapsedMicroseconds >/dev/null; done
TStopwatch.getTimeStamp; t1=$RESULT
report "GetElapsedMicroseconds (running)" $(( t1-t0 )) "$N"
sw.Stop

TStopwatch.getTimeStamp; t0=$RESULT
for (( i=0; i<N; i++ )); do sw.GetIsRunning >/dev/null; done
TStopwatch.getTimeStamp; t1=$RESULT
report "GetIsRunning" $(( t1-t0 )) "$N"

echo
echo "Object API — PROPERTY forms (kklass method-backed property read forks"
echo "a subshell per read — kklass_decl.sh:261 'RESULT=\"\$(\$__inst__.call …)\"';"
echo "house-wide: tdictionary d.count pays the same):"
TStopwatch.getTimeStamp; t0=$RESULT
for (( i=0; i<N; i++ )); do sw.elapsedMicroseconds >/dev/null; done
TStopwatch.getTimeStamp; t1=$RESULT
report "elapsedMicroseconds (property)" $(( t1-t0 )) "$N"
prop_us=$(( (t1-t0) / N ))

TStopwatch.getTimeStamp; t0=$RESULT
for (( i=0; i<N; i++ )); do sw.isRunning >/dev/null; done
TStopwatch.getTimeStamp; t1=$RESULT
report "isRunning (property)" $(( t1-t0 )) "$N"

echo
echo "  informational — \$() capture adds a subshell fork per call:"
TStopwatch.getTimeStamp; t0=$RESULT
for (( i=0; i<N; i++ )); do v=$(sw.elapsedMicroseconds); done
TStopwatch.getTimeStamp; t1=$RESULT
report "elapsedMicroseconds via \$()" $(( t1-t0 )) "$N"

echo
echo "Instrument self-time — what an EMPTY Start;Stop bracket measures"
echo "(the systematic bias the object API adds to a measured interval):"
sw.Reset
total=0
for (( i=0; i<N; i++ )); do
    sw.Restart
    sw.Stop
    sw.elapsedMicroseconds >/dev/null
    total=$(( total + RESULT ))
done
bias_us=$(( total / N ))
printf '  empty-bracket reading (avg of %d)  %6d us\n' "$N" "$bias_us"
sw.delete

echo
echo "Positioning summary:"
if (( raw_x10 > 0 )); then
    printf '  dispatch-vs-raw delta: func getter %d us vs raw %d.%d us (~x%d); property read %d us (~x%d)\n' \
        "$getter_us" $(( raw_x10/10 )) $(( raw_x10%10 )) $(( getter_us * 10 / raw_x10 )) \
        "$prop_us" $(( prop_us * 10 / raw_x10 ))
fi
printf '  object API is for intervals  >> %d us (empty-bracket bias);\n' "$bias_us"
printf '  Start+Stop instrumentation costs the CALLER ~%d us per bracket;\n' "$pair_us"
printf '  read results via FUNC forms + $RESULT (~%d us) — property forms fork (~%d us);\n' \
    "$getter_us" "$prop_us"
printf '  tight loops: TStopwatch.getTimeStamp deltas (%d.%d us/call, RESULT-only).\n' \
    $(( gts_x10/10 )) $(( gts_x10%10 ))

echo
echo "zero-fork check (direct-call API with empty PATH):"
TStopwatch.new zf
if ( PATH=''
     zf.Start                          || exit 1
     zf.Stop                           || exit 1
     zf.elapsedMicroseconds >/dev/null || exit 1
     [[ "$RESULT" =~ ^[0-9]+$ ]]       || exit 1
     zf.Restart                        || exit 1
     zf.Reset                          || exit 1
     TStopwatch.getTimeStamp           || exit 1
   ); then
    echo "  OK — Start/Stop/getters/Restart/Reset/getTimeStamp spawned no external process"
else
    echo "  FAIL — an operation forked or failed under PATH=''"
fi
zf.delete
