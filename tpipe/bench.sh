#!/bin/bash
# Micro-benchmark for tpipe (P2.1). Publishes the numbers README.md §6 quotes
# and measures the PLAN.md §2.6 gates:
#   (a) DISPATCH COST — a plain function call vs a kklass STATIC member vs a
#       kklass INSTANCE member (`r.onLine`). This section is not about TPipe at
#       all: it is the price of the callback the caller chooses, and it is what
#       makes section (c) three times section (b);
#   (b) GATED — `TPipe.each` + a no-op FUNCTION over N records against a bare
#       `while IFS= read -r` loop over the SAME producer. Gate: <= 2.0x;
#   (c) PUBLISHED, NOT GATED — `TPipe.each r.onLine` over the same producer.
#       A full kklass instance dispatch per record; kklass's price, not TPipe's;
#   (d) GATED — `TPipe.toArray` against a bare `mapfile` over the same producer.
#       Gate: <= 1.5x;
#   (e) GATED — `TPipe.first -- yes` latency: the close -> kill -TERM -> wait
#       path on an INFINITE producer must return promptly. Gate: <= 250 ms;
#   (f) ZERO FORKS PER RECORD — $BASHPID inside the callback, inside `.Add`,
#       and around every sink call.
# Timing primitive: TStopwatch.getTimeStamp (kcl/tstopwatch) — one tested,
# locale-safe us clock shared by every kcl bench; RESULT-only, no fork.
# Deterministic: fixed sizes, no $RANDOM, one producer shape everywhere.
#
# The gates printed here are the PLAN §2.6 numbers, measured by hand with the
# machine idle. `tests/005_Bench.sh` asserts the same three gates with ceilings
# 3x looser, because ktests runs test files threaded (8 workers) by default.
#
# Run: bash bench.sh [N] [ND]      (defaults: N=10000 records, ND=2000 calls)
# Runs clean under `bash -eu`; always exits 0 (a failed gate is printed, not
# raised — tests/005_Bench.sh is the assertion).

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/tpipe.sh"
source "$DIR/../tstopwatch/tstopwatch.sh"

N=${1:-10000}       # records per stream measurement
ND=${2:-2000}       # calls per dispatch measurement (instance dispatch is ~200us)

# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------

report() {  # label total_us iters unit -> us/iter with tenths + total ms
    local x10=$(( $2 * 10 / $3 ))
    printf '  %-46s %7d.%d us/%s  (total %d ms)\n' "$1" $(( x10/10 )) $(( x10%10 )) "$4" $(( $2/1000 ))
}

ratio() {   # label value_us base_us -> the ratio, no verdict (published numbers)
    local r100=$(( $2 * 100 / $3 ))
    printf '  %-46s %7d ms   ratio %d.%02dx of the bare loop\n' \
        "$1" $(( $2/1000 )) $(( r100/100 )) $(( r100%100 ))
}

gate_ratio() {  # label value_us base_us limit_tenths -> ratio + PASS/FAIL
    local r100=$(( $2 * 100 / $3 )) lim=$(( $3 * $4 / 10 )) verdict
    if (( $2 <= lim )); then verdict="PASS"; else verdict="FAIL"; GATES_FAILED=$(( GATES_FAILED + 1 )); fi
    printf '  %-46s %7d ms   ratio %d.%02dx  (gate %d.%dx) %s\n' \
        "$1" $(( $2/1000 )) $(( r100/100 )) $(( r100%100 )) $(( $4/10 )) $(( $4%10 )) "$verdict"
}

gate_abs() {    # label value_us limit_us -> ms + PASS/FAIL
    local verdict
    if (( $2 <= $3 )); then verdict="PASS"; else verdict="FAIL"; GATES_FAILED=$(( GATES_FAILED + 1 )); fi
    printf '  %-46s %7d ms   (gate %d ms) %s\n' "$1" $(( $2/1000 )) $(( $3/1000 )) "$verdict"
}

GATES_FAILED=0

# The one producer shape used by (b), (c) and (d): ONE builtin printf emits the
# whole stream, so the producer side of the comparison is identical for TPipe
# and for the bare loop and contributes no per-record cost of its own.
declare -a RECS=()
for (( _i = 0; _i < N; _i++ )); do RECS+=( "record-$_i" ); done
bench_producer() { printf '%s\n' "${RECS[@]}"; }

bench_noop() { return 0; }                      # the no-op FUNCTION callback

BENCH_PLAIN_N=0
bench_plain() { BENCH_PLAIN_N=$(( BENCH_PLAIN_N + 1 )); return 0; }

# a kklass STATIC member callback
BENCH_STATIC_N=0
class TBenchStatic
    public
        static proc onLine
end
TBenchStatic.onLine() { BENCH_STATIC_N=$(( BENCH_STATIC_N + 1 )); return 0; }
build TBenchStatic

# a kklass INSTANCE member callback — the `r.onLine` of the README
class TBenchSink
    public
        var         N
        constructor Create
        proc        onLine
end
TBenchSink.Create() { N=0; return 0; }
TBenchSink.onLine() { N=$(( N + 1 )); return 0; }
build TBenchSink

echo "tpipe micro-benchmark  (bash ${BASH_VERSION}, N=$N records / ND=$ND dispatched calls)"
echo

# --- (a) what a callback costs before TPipe touches it ----------------------
echo "callback dispatch cost (NOT TPipe — the price of the callback you choose):"
TBenchSink.new BR

TStopwatch.getTimeStamp; t0=$RESULT
for (( i = 0; i < ND; i++ )); do bench_plain "x"; done
TStopwatch.getTimeStamp; t1=$RESULT
plain=$(( t1 - t0 )); (( plain > 0 )) || plain=1
report "plain function call" "$plain" "$ND" "call"

TStopwatch.getTimeStamp; t0=$RESULT
for (( i = 0; i < ND; i++ )); do TBenchStatic.onLine "x"; done
TStopwatch.getTimeStamp; t1=$RESULT
stat=$(( t1 - t0 ))
report "kklass STATIC member (TBenchStatic.onLine)" "$stat" "$ND" "call"

TStopwatch.getTimeStamp; t0=$RESULT
for (( i = 0; i < ND; i++ )); do BR.onLine "x"; done
TStopwatch.getTimeStamp; t1=$RESULT
inst=$(( t1 - t0 ))
report "kklass INSTANCE member (r.onLine)" "$inst" "$ND" "call"
printf '  static/plain %d.%dx, instance/plain %d.%dx — that factor IS section (c) below\n' \
    $(( stat * 10 / plain / 10 )) $(( stat * 10 / plain % 10 )) \
    $(( inst * 10 / plain / 10 )) $(( inst * 10 / plain % 10 ))

# --- (b) the gated stream comparison ----------------------------------------
echo
echo "streaming $N records — TPipe.each vs a bare \`while IFS= read -r\` loop:"
line=''
TStopwatch.getTimeStamp; t0=$RESULT
while IFS= read -r line; do :; done < <( bench_producer )
TStopwatch.getTimeStamp; t1=$RESULT
bare=$(( t1 - t0 )); (( bare > 0 )) || bare=1
report "bare while IFS= read -r loop (baseline)" "$bare" "$N" "rec"

TStopwatch.getTimeStamp; t0=$RESULT
TPipe.each bench_noop -- bench_producer || :
n_eachfn="$RESULT"                      # read RESULT FIRST: the clock uses it too
TStopwatch.getTimeStamp; t1=$RESULT
eachfn=$(( t1 - t0 ))
report "TPipe.each + a no-op FUNCTION" "$eachfn" "$N" "rec"
gate_ratio "  gate: each + function vs the bare loop" "$eachfn" "$bare" 20

# --- (c) published, not gated ------------------------------------------------
BR.onLine ""            # warm the instance dispatcher
TStopwatch.getTimeStamp; t0=$RESULT
TPipe.each BR.onLine -- bench_producer || :
n_eachinst="$RESULT"
TStopwatch.getTimeStamp; t1=$RESULT
eachinst=$(( t1 - t0 ))
report "TPipe.each + an INSTANCE member (r.onLine)" "$eachinst" "$N" "rec"
ratio "  published, NOT gated: instance-member callback" "$eachinst" "$bare"
echo "  (that ratio is the kklass instance dispatch of section (a), not TPipe's reader)"

# --- (d) toArray vs a bare mapfile ------------------------------------------
echo
echo "collecting $N records — TPipe.toArray vs a bare \`mapfile\`:"
declare -a BARR=() TARR=()
TStopwatch.getTimeStamp; t0=$RESULT
mapfile -t BARR < <( bench_producer )
TStopwatch.getTimeStamp; t1=$RESULT
baremap=$(( t1 - t0 )); (( baremap > 0 )) || baremap=1
report "bare mapfile -t (baseline)" "$baremap" "$N" "rec"

TStopwatch.getTimeStamp; t0=$RESULT
TPipe.toArray TARR -- bench_producer || :
n_toarr="$RESULT"
TStopwatch.getTimeStamp; t1=$RESULT
toarr=$(( t1 - t0 ))
report "TPipe.toArray" "$toarr" "$N" "rec"
gate_ratio "  gate: toArray vs bare mapfile" "$toarr" "$baremap" 15

# --- (e) first on an infinite producer --------------------------------------
echo
echo "latency — TPipe.first on an INFINITE producer (close -> kill -TERM -> wait):"
TStopwatch.getTimeStamp; t0=$RESULT
TPipe.first -- yes 2>/dev/null || :
firstrec="$RESULT"
TStopwatch.getTimeStamp; t1=$RESULT
firstus=$(( t1 - t0 ))
TPipe.lastRc; firstlrc="$RESULT"
gate_abs "  gate: TPipe.first -- yes" "$firstus" 250000
echo "  first record '$firstrec', lastRc $firstlrc (141 SIGPIPE or 143 SIGTERM — a race, both correct)"

# --- (f) zero forks per record ----------------------------------------------
echo
echo "zero-fork check (\$BASHPID inside the callback and around every sink):"
FORKPIDS=()
fork_cb() { FORKPIDS+=( "$BASHPID" ); return 0; }
class TForkList
    public
        constructor Create
        proc        Add
end
TForkList.Create() { return 0; }
TForkList.Add()    { FORKPIDS+=( "$BASHPID" ); return 0; }
build TForkList
TForkList.new FL

p5() { printf 'r1\nr2\nr3\nr4\nr5\n'; }
declare -a FARR=()
p0=$BASHPID; forked=0
TPipe.each fork_cb -- p5    || :; [[ $BASHPID == "$p0" ]] || forked=1
TPipe.toList FL     -- p5   || :; [[ $BASHPID == "$p0" ]] || forked=1
TPipe.toArray FARR  -- p5   || :; [[ $BASHPID == "$p0" ]] || forked=1
TPipe.count         -- p5   || :; [[ $BASHPID == "$p0" ]] || forked=1
TPipe.first         -- p5 2>/dev/null || :; [[ $BASHPID == "$p0" ]] || forked=1
TPipe.lastRc                   ;  [[ $BASHPID == "$p0" ]] || forked=1
TPipe.stop                     ;  [[ $BASHPID == "$p0" ]] || forked=1
FL.delete
for pid in "${FORKPIDS[@]}"; do
    [[ "$pid" == "$p0" ]] || forked=1
done
if (( forked == 0 )) && (( ${#FORKPIDS[@]} == 10 )); then
    echo "  BASHPID $p0 unchanged across all seven members and all 10 callback/.Add invocations"
else
    echo "  ZERO-FORK VIOLATION: p0=$p0 forked=$forked callback pids=(${FORKPIDS[*]})"
fi

# The producer IS the one fork per call: every record carries the producer's own
# pid, and all of them are the same, different-from-ours pid.
ppid5() { local i; for i in 1 2 3 4 5; do printf '%s\n' "$BASHPID"; done; }
declare -a PPIDS=()
TPipe.toArray PPIDS -- ppid5 || :
same=1
for pid in "${PPIDS[@]}"; do
    [[ "$pid" == "${PPIDS[0]}" ]] || same=0
done
if (( same == 1 )) && [[ "${PPIDS[0]}" != "$p0" ]] && (( ${#PPIDS[@]} == 5 )); then
    echo "  the only fork per call is the producer: 5 records, one producer pid ${PPIDS[0]}"
else
    echo "  PRODUCER-FORK ANOMALY: ours $p0, record pids=(${PPIDS[*]})"
fi

# --- summary -----------------------------------------------------------------
echo
echo "records delivered: each+fn $n_eachfn, each+r.onLine $n_eachinst, toArray $n_toarr (want $N each)"
if (( GATES_FAILED == 0 )); then
    echo "gates: 3/3 PASS (each <= 2.0x, toArray <= 1.5x, first <= 250 ms)"
else
    echo "gates: $GATES_FAILED of 3 FAILED — see the lines above"
fi
BR.delete

exit 0
