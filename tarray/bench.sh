#!/bin/bash
# Micro-benchmark for tarray (P4.2). Publishes the honest-positioning numbers
# README.md quotes:
#   - sort scaling n=100/1000/5000 (per-element cost, byte mode);
#   - comparator-mode deltas at n=1000 (byte vs -n vs cmpFn);
#   - binarySearch per-probe cost vs a LINEAR indexOf scan (the payoff row);
#   - reverse/concat single-pass throughput;
#   - INFORMATIONAL: one /usr/bin/sort fork+pipe on the same data (the thing
#     TArray exists to avoid: fork cost, line-based corruption on newline
#     elements, and no binary search);
#   - the zero-fork check on every entry point.
# Timing primitive: TStopwatch.getTimeStamp (kcl/tstopwatch) — one tested,
# locale-safe µs clock shared by every kcl bench; RESULT-only, no fork.
# Run: bash bench.sh   (sizes fixed; deterministic LCG data, no $RANDOM)

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/tarray.sh"
source "$DIR/../tstopwatch/tstopwatch.sh"

report() {  # label total_us iters -> us/iter with tenths + total ms
    local x10=$(( $2 * 10 / $3 ))
    printf '  %-42s %6d.%d us/%s  (total %d ms)\n' "$1" $(( x10/10 )) $(( x10%10 )) "$4" $(( $2/1000 ))
}

# deterministic pseudo-random ints via LCG
mkdata() {  # n -> fills global data[]
    data=(); local x=12345 i
    for (( i=0; i<$1; i++ )); do
        x=$(( (x*1103515245 + 12345) & 0x7fffffff ))
        data+=( $(( x % 100000 )) )
    done
}

echo "tarray micro-benchmark  (bash ${BASH_VERSION})"
echo

# --- sort scaling, byte mode -------------------------------------------------
echo "sort scaling (default byte mode):"
for n in 100 1000 5000; do
    mkdata "$n"; a=( "${data[@]}" )
    TStopwatch.getTimeStamp; t0=$RESULT
    TArray.sort a
    TStopwatch.getTimeStamp; t1=$RESULT
    report "sort n=$n" $(( t1-t0 )) "$n" "elem"
done

# --- comparator-mode deltas at n=1000 ----------------------------------------
echo
echo "comparator modes at n=1000:"
mkdata 1000
b=( "${data[@]}" )
TStopwatch.getTimeStamp; t0=$RESULT; TArray.sort b;    TStopwatch.getTimeStamp; t1=$RESULT
report "byte mode (inlined [[ < ]])" $(( t1-t0 )) 1000 "elem"
b=( "${data[@]}" )
TStopwatch.getTimeStamp; t0=$RESULT; TArray.sort b -n; TStopwatch.getTimeStamp; t1=$RESULT
report "-n numeric (inlined (( )), 10# keys)" $(( t1-t0 )) 1000 "elem"
cmpnum(){ (( $1 < $2 )) && return 0; (( $1 == $2 )) && return 1; return 2; }
b=( "${data[@]}" )
TStopwatch.getTimeStamp; t0=$RESULT; TArray.sort b cmpnum; TStopwatch.getTimeStamp; t1=$RESULT
report "cmpFn (plain-fn call per compare)" $(( t1-t0 )) 1000 "elem"

# --- binarySearch vs linear indexOf on n=5000 ---------------------------------
echo
echo "search on n=5000 (sorted numeric):"
mkdata 5000; s=( "${data[@]}" ); TArray.sort s -n
NSRCH=500
TStopwatch.getTimeStamp; t0=$RESULT
for (( i=0; i<NSRCH; i++ )); do TArray.binarySearch s "${s[i]}" -n; done
TStopwatch.getTimeStamp; t1=$RESULT
report "binarySearch ($NSRCH hits)" $(( t1-t0 )) "$NSRCH" "search"

NLIN=10
TStopwatch.getTimeStamp; t0=$RESULT
for (( i=0; i<NLIN; i++ )); do TArray.indexOf s "-1" -n; done   # miss = full scan
TStopwatch.getTimeStamp; t1=$RESULT
report "indexOf full-scan miss ($NLIN)" $(( t1-t0 )) "$NLIN" "search"

# --- single-pass helpers at n=5000 --------------------------------------------
echo
echo "single-pass helpers at n=5000:"
TStopwatch.getTimeStamp; t0=$RESULT; TArray.reverse s s;   TStopwatch.getTimeStamp; t1=$RESULT
report "reverse in-place" $(( t1-t0 )) 5000 "elem"
TStopwatch.getTimeStamp; t0=$RESULT; TArray.concat cc s s; TStopwatch.getTimeStamp; t1=$RESULT
report "concat 5k+5k" $(( t1-t0 )) 10000 "elem"

# --- informational: the external-sort alternative ------------------------------
echo
echo "informational — /usr/bin/sort on the same n=1000 (fork+pipe, line-based):"
mkdata 1000; e=( "${data[@]}" )
TStopwatch.getTimeStamp; t0=$RESULT
printf '%s\n' "${e[@]}" | sort -n >/dev/null
TStopwatch.getTimeStamp; t1=$RESULT
printf '  one fork+pipe round trip                    total %d ms\n' $(( (t1-t0)/1000 ))
echo "  (faster per element at scale — but forks, corrupts newline-containing"
echo "   elements, and cannot binary-search; see README positioning)"

# --- zero-fork check ------------------------------------------------------------
echo
echo "zero-fork check (every entry point with empty PATH):"
if ( PATH=''
     z=(3 1 2);        TArray.sort z                  || exit 1
     TArray.sort z -n                                 || exit 1
     cf(){ (( $1 < $2 )) && return 0; (( $1 == $2 )) && return 1; return 2; }
     TArray.sort z cf                                 || exit 1
     TArray.binarySearch z 2 -n                       || exit 1
     TArray.indexOf z 2 -n                            || exit 1
     TArray.lastIndexOf z 2 -n                        || exit 1
     TArray.contains z 2 -n                           || exit 1
     TArray.min z -n                                  || exit 1
     TArray.max z -n                                  || exit 1
     d=(_ _ _);        TArray.copy z d 3              || exit 1
     TArray.reverse z z                               || exit 1
     TArray.reverseInPlace z                          || exit 1
     TArray.concat cc z d                             || exit 1
     declare -a sp=([3]=x); TArray.compact sp         || exit 1
   ); then
    echo "  OK — all 13 members spawned no external process"
else
    echo "  FAIL — an operation forked or failed under PATH=''"
fi
