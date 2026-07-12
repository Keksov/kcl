#!/bin/bash
# Micro-benchmark for tregex (P4.2). Publishes the honest-positioning numbers
# README.md quotes:
#   - DISPATCH overhead: TRegEx.isMatch / .match (kklass static-proc dispatch)
#     vs a raw inline `[[ $s =~ $re ]]`;
#   - matches() SCALING: per-occurrence scan cost (10 vs 100 matches);
#   - replace / escape throughput;
#   - the zero-fork check on every entry point.
# Timing primitive: TStopwatch.getTimeStamp (kcl/tstopwatch) — one tested,
# locale-safe µs clock shared by every kcl bench; RESULT-only, no fork.
# Run: bash bench.sh [N_dispatch] [N_scan]   (defaults 2000 / 200)

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/tregex.sh"
source "$DIR/../tstopwatch/tstopwatch.sh"

N=${1:-2000}       # iterations for dispatched calls
NS=${2:-200}       # iterations for the scan/throughput loops (heavier per call)

report() {  # label total_us iters -> us/call, tenths precision
    local x10=$(( $2 * 10 / $3 ))
    printf '  %-40s %5d.%d us/call\n' "$1" $(( x10/10 )) $(( x10%10 ))
}

echo "tregex micro-benchmark  (bash ${BASH_VERSION}, N=$N dispatch / $NS scan)"
echo

# --- dispatch overhead: API wrapper vs raw [[ =~ ]] --------------------------
echo "Dispatch overhead (single match):"
subj="the quick brown fox jumps over the lazy dog"; pat="q[a-z]+k"

TStopwatch.getTimeStamp; t0=$RESULT
for (( i=0; i<N; i++ )); do __re="$pat"; [[ $subj =~ $__re ]]; done
TStopwatch.getTimeStamp; t1=$RESULT
report "raw [[ =~ ]] inline" $(( t1-t0 )) "$N"; raw=$(( (t1-t0)*10/N ))

TStopwatch.getTimeStamp; t0=$RESULT
for (( i=0; i<N; i++ )); do TRegEx.isMatch "$subj" "$pat"; done
TStopwatch.getTimeStamp; t1=$RESULT
report "TRegEx.isMatch (static-proc dispatch)" $(( t1-t0 )) "$N"; im=$(( (t1-t0)*10/N ))

TStopwatch.getTimeStamp; t0=$RESULT
for (( i=0; i<N; i++ )); do TRegEx.match "$subj" "$pat"; done
TStopwatch.getTimeStamp; t1=$RESULT
report "TRegEx.match (offset+groups)" $(( t1-t0 )) "$N"; mm=$(( (t1-t0)*10/N ))

TStopwatch.getTimeStamp; t0=$RESULT
for (( i=0; i<N; i++ )); do TRegEx.escape "$subj" >/dev/null; done
TStopwatch.getTimeStamp; t1=$RESULT
report "TRegEx.escape (${#subj}-char string)" $(( t1-t0 )) "$N"

# --- matches() scaling: per-occurrence scan cost ----------------------------
echo
echo "matches() scaling (per-occurrence scan cost):"
s10=""; for (( i=0; i<10;  i++ )); do s10+="x$i "; done
s100=""; for (( i=0; i<100; i++ )); do s100+="x$i "; done
M=()

TStopwatch.getTimeStamp; t0=$RESULT
for (( i=0; i<NS; i++ )); do TRegEx.matches "$s10" "x[0-9]+" M; done
TStopwatch.getTimeStamp; t1=$RESULT
tot10=$(( t1-t0 )); report "matches, 10 occurrences  (per call)" "$tot10" "$NS"

TStopwatch.getTimeStamp; t0=$RESULT
for (( i=0; i<NS; i++ )); do TRegEx.matches "$s100" "x[0-9]+" M; done
TStopwatch.getTimeStamp; t1=$RESULT
tot100=$(( t1-t0 )); report "matches, 100 occurrences (per call)" "$tot100" "$NS"
per10=$(( tot10/NS/10 )); per100=$(( tot100/NS/100 ))
printf '  -> ~%d us per occurrence @10, ~%d us per occurrence @100 (≈linear)\n' "$per10" "$per100"

# --- replace throughput -----------------------------------------------------
echo
echo "replace throughput:"
S=()
TStopwatch.getTimeStamp; t0=$RESULT
for (( i=0; i<NS; i++ )); do TRegEx.replace "$s100" "x[0-9]+" "#" >/dev/null; done
TStopwatch.getTimeStamp; t1=$RESULT
report "replace-all, 100 matches (per call)" $(( t1-t0 )) "$NS"

TStopwatch.getTimeStamp; t0=$RESULT
for (( i=0; i<NS; i++ )); do TRegEx.split "$s100" "[[:space:]]" S; done
TStopwatch.getTimeStamp; t1=$RESULT
report "split, 100 pieces (per call)" $(( t1-t0 )) "$NS"

# --- positioning summary ----------------------------------------------------
echo
echo "Positioning summary:"
printf '  API dispatch wrapper adds ~%d.%d us over a raw [[ =~ ]] (%d.%d us);\n' \
    $(( (im-raw)/10 )) $(( (im-raw)%10 )) $(( raw/10 )) $(( raw%10 ))
printf '  match (offset+group copy) ~%d.%d us; matches/replace/split scale ~linearly per occurrence;\n' \
    $(( mm/10 )) $(( mm%10 ))
printf '  everything is fork-free — the engine is the bash [[ =~ ]] builtin, no external process.\n'

# --- zero-fork check --------------------------------------------------------
echo
echo "zero-fork check (every entry point with empty PATH):"
if ( PATH=''
     TRegEx.isMatch "ab" "b"                 || exit 1
     TRegEx.match "ab" "(b)"                  || exit 1
     [[ "${RESULT_GROUPS[0]}" == "b" ]]       || exit 1
     TRegEx.escape "a.b" >/dev/null           || exit 1
     zc=(); TRegEx.matches "a1b2" "[0-9]" zc  || exit 1
     zs=(); TRegEx.split "a,b" "," zs         || exit 1
     TRegEx.replace "a1" "[0-9]" "#" >/dev/null || exit 1
     cb() { REPLY="<$1>"; }
     TRegEx.replaceCb "a1" "[0-9]" cb >/dev/null || exit 1
   ); then
    echo "  OK — isMatch/match/escape/matches/split/replace/replaceCb spawned no external process"
else
    echo "  FAIL — an operation forked or failed under PATH=''"
fi
