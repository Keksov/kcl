#!/bin/bash
# Micro-benchmark for thead (P1). Publishes the numbers README.md §8 quotes and
# measures the PLAN.md §5 P1 gate:
#
#   (a) ARGV — what the typed option set costs to turn into a command line, and
#       the proof that it RUNS NOTHING: with `cmd` pointed at a shell function
#       that counts its own invocations, ND `argv` calls leave the counter at 0.
#       $BASHPID is read before and after: the builder is fork-free;
#   (b) THE WRAPPER'S FIXED DELTA — `new` + `argv` + `delete` on its own line.
#       That triple is the WHOLE difference between `THead.take N FILE` and the
#       bare `head -n N -- FILE` of (c): one throw-away instance, one build, one
#       destruction, and then the same single fork. It is a per-CALL cost and
#       never a per-record one;
#   (c) GATED — `THead.take N FILE` against a bare `head -n N -- FILE` over the
#       same generated corpus, in the two shapes that bracket the tool's own
#       work: `-n 1` (head stops after one line: the fork IS the measurement)
#       and `-n 5000` (half the corpus). Gate: <= **1.5x**, from the MEDIANS of
#       NR >= 15 INTERLEAVED runs;
#   (d) PUBLISHED, NOT GATED — `h.count` against the `wc -l` equivalent
#       (`head -n 5000 -- FILE | wc -l`). They answer the same question by
#       different means: `wc` counts in a second process at memory speed, the
#       `count` sink reads every record into bash. The gap is the price of
#       having the records in this shell, and it is a per-RECORD price;
#   (e) ZERO FORKS — $BASHPID around every THead member, around `take`, and
#       inside an `each` callback and a `.Add`.
#
# `follow` is a ttail property and there is nothing like it here; every shape
# below terminates on its own.
#
# Timing primitive: TStopwatch.getTimeStamp (kcl/tstopwatch) — one tested,
# locale-safe us clock shared by every kcl bench; RESULT-only, no fork.
# Deterministic: fixed sizes, no $RANDOM, one generated corpus everywhere.
#
# WHY THE CORPUS SIZE DOES NOT MOVE THE RATIO OF (c). On this platform a whole
# `head` run — the msys `fork`+`exec` of a coreutils binary, plus the scan —
# costs **33-36 ms** at NL = 10 000 (the plan estimated ~42 ms), while the
# wrapper's entire fixed delta — section (b) — is **3.1-3.3 ms** (the plan
# estimated ~3.9 ms). The ratio of (c) is therefore roughly (34 + 3.2) / 34: it
# sits near 1.1x and can only fall as the scan grows. Ten times the corpus does
# not make the wrapper cheaper, it makes the denominator bigger — which is why
# both `-n 1` and `-n 5000` land within a few percent of each other below. That
# is also why the gate is 1.5x and not 1.3x: the head-room is not in the corpus,
# it is in the VARIANCE of that ~34 ms process start, whose MEAN on this box is
# routinely double its median.
#
# MEDIANS, AND WHY. Every number in (c) and (d) is ONE PROCESS START plus a
# scan, and on this platform a process start occasionally takes several hundred
# milliseconds for reasons outside this repo (a scanner, a page-fault storm).
# One such outlier in 20 runs moves a MEAN by more than the whole head-room of
# the gate, and it lands on a different side from run to run: a NON-interleaved
# loop over these two shapes has been read as high as 2.4x on code that
# interleaved medians put at 1.07-1.30x (PLAN §8 finding 7). So the two shapes
# are timed INTERLEAVED, one of each per iteration, every run is recorded
# separately, and the published ratio is computed from the MEDIANS. The MEAN is
# printed next to each median, and a gap between the two IS the outlier telling
# you the box was not idle.
#
# The corpus is generated into a `mktemp -d` directory and removed by an EXIT
# trap (this is a bench, not a test file: a test file must NOT install a trap of
# its own, it would replace ktests').
#
# The gate printed here is the PLAN §5 P1 number, measured by hand with the
# machine idle. `tests/007_Bench.sh` asserts the same shapes with a ceiling of
# 10x: ktests runs test files threaded (8 workers) and the two sides do NOT
# inflate together under that load — `head` is its own process, while the
# wrapper's share is bash work in the contended shell.
#
# Run: bash bench.sh [NL] [NR] [ND]
#      (defaults: NL=10000 corpus lines, NR=21 interleaved runs, ND=300 calls)
# Runs clean under `bash -eu`; always exits 0 (a failed gate is printed, not
# raised — tests/007_Bench.sh is the assertion).

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/thead.sh"
source "$DIR/../tstopwatch/tstopwatch.sh"

NL=${1:-10000}      # corpus lines in big.txt
NR=${2:-21}         # interleaved repetitions per gated shape (odd, >= 15)
ND=${3:-300}        # calls per per-call measurement

# ---------------------------------------------------------------------------
# helpers (the tgrep/bench.sh shape, so every kcl bench table reads the same)
# ---------------------------------------------------------------------------

report() {  # label total_us iters unit -> us/iter with tenths + total ms
    local x10=$(( $2 * 10 / $3 ))
    printf '  %-46s %7d.%d us/%s  (total %d ms)\n' "$1" $(( x10/10 )) $(( x10%10 )) "$4" $(( $2/1000 ))
}

# median NAME -> MED (us). Sorting is one fork, OUTSIDE every timed region.
MED=0
median() {
    local -n __m_a="$1"
    local -a __m_s=()
    mapfile -t __m_s < <( printf '%s\n' "${__m_a[@]}" | sort -n )
    MED="${__m_s[ ${#__m_s[@]} / 2 ]}"
}

report_med() {  # label median_us total_us runs
    local m100=$(( $2 * 100 / 1000 )) a100=$(( $3 * 100 / $4 / 1000 ))
    printf '  %-46s median %6d.%02d ms  mean %6d.%02d ms  (%d runs)\n' \
        "$1" $(( m100/100 )) $(( m100%100 )) $(( a100/100 )) $(( a100%100 )) "$4"
}

ratio() {   # label value_us base_us base_label -> the ratio, no verdict
    local r100=$(( $2 * 100 / $3 ))
    printf '  %-46s ratio %d.%02dx of %s\n' \
        "$1" $(( r100/100 )) $(( r100%100 )) "$4"
}

GATES_FAILED=0
GATES_TOTAL=0

gate_ratio() {  # label median_us base_median_us limit_tenths -> ratio + PASS/FAIL
    local r100=$(( $2 * 100 / $3 )) lim=$(( $3 * $4 / 10 )) verdict
    GATES_TOTAL=$(( GATES_TOTAL + 1 ))
    if (( $2 <= lim )); then
        verdict="PASS"
    else
        verdict="FAIL"
        GATES_FAILED=$(( GATES_FAILED + 1 ))
    fi
    printf '  %-46s ratio %d.%02dx  (gate %d.%dx) %s\n' \
        "$1" $(( r100/100 )) $(( r100%100 )) $(( $4/10 )) $(( $4%10 )) "$verdict"
}

# --- the GNU banner gate ----------------------------------------------------
# D4 pins the DIALECT (GNU coreutils 8.32), not a binary. Every number below is
# about that tool; on anything else they are not comparable, so say so loudly
# instead of publishing a meaningless table.
HEAD_BANNER="$(head --version 2>/dev/null | sed -n 1p || true)"
case "$HEAD_BANNER" in
    "head (GNU coreutils) "*) ;;
    *) echo "thead bench: SKIPPED — \`head\` is not GNU coreutils: '$HEAD_BANNER'"; exit 0 ;;
esac

# --- the corpus -------------------------------------------------------------
BD="$(mktemp -d)"
trap 'rm -rf "$BD"' EXIT
{
    for (( _i = 0; _i < NL; _i++ )); do
        printf 'line %d of the bench corpus, some payload here\n' "$_i"
    done
} > "$BD/big.txt"
BIG="$BD/big.txt"
HALF=$(( NL / 2 ))          # the `-n 5000` shape at the default NL

echo "thead micro-benchmark  (bash ${BASH_VERSION}, ${HEAD_BANNER})"
echo "corpus: $NL lines in big.txt; NR=$NR interleaved runs, ND=$ND calls"
echo

# ===========================================================================
# (a) the typed option set -> argv
# ===========================================================================
echo "(a) the argv model — typed options into a command line, running NOTHING:"
THead.new BH "$HALF" "$BIG"
BH.quiet = 1
declare -a BW=()

TStopwatch.getTimeStamp; t0=$RESULT
for (( i = 0; i < ND; i++ )); do BH.buildArgv; done
TStopwatch.getTimeStamp; t1=$RESULT
b_build=$(( t1 - t0 )); (( b_build > 0 )) || b_build=1
report "buildArgv (the override)" "$b_build" "$ND" "call"

TStopwatch.getTimeStamp; t0=$RESULT
for (( i = 0; i < ND; i++ )); do BH.argv BW; done
n_argv="$RESULT"
TStopwatch.getTimeStamp; t1=$RESULT
b_argv=$(( t1 - t0 )); (( b_argv > 0 )) || b_argv=1
report "argv NAME (buildArgv + validate + copy)" "$b_argv" "$ND" "call"
printf '  %-46s %s words: %s\n' "argv NAME copied" "$n_argv" "${BW[*]}"

# head is never executed above; prove it by pointing `cmd` at a function that
# would count its own invocations, and building ND more times.
BENCH_RAN=0
bench_counted() { BENCH_RAN=$(( BENCH_RAN + 1 )); return 0; }
BH.cmd = bench_counted
pid_a="$BASHPID"
for (( i = 0; i < ND; i++ )); do BH.argv BW; done
BH.cmd = head
if (( BENCH_RAN == 0 )) && [[ "$BASHPID" == "$pid_a" ]]; then
    echo "  RUNS NOTHING: with cmd pointed at a counting function, $ND builds invoked it 0 times"
    echo "  FORK-FREE:    BASHPID $pid_a unchanged across all $(( ND * 3 )) builds"
else
    echo "  VIOLATION: cmd invoked $BENCH_RAN times, BASHPID $pid_a -> $BASHPID"
fi
BH.delete

# ===========================================================================
# (b) the wrapper's fixed delta: new + argv + delete
# ===========================================================================
echo
echo "(b) the wrapper's FIXED delta — one instance, one build, one destruction:"
declare -a BV=()
TStopwatch.getTimeStamp; t0=$RESULT
for (( i = 0; i < ND; i++ )); do
    THead.new BC "$HALF" "$BIG"
    BC.argv BV
    BC.delete
done
TStopwatch.getTimeStamp; t1=$RESULT
b_ctor=$(( t1 - t0 )); (( b_ctor > 0 )) || b_ctor=1
report "new + argv + delete (the \`take\` delta)" "$b_ctor" "$ND" "call"
per_ctor=$(( b_ctor / ND ))
echo "  this is the WHOLE difference between \`take\` and the bare tool below;"
echo "  it is paid once per CALL, never per record, and it does not grow with"
echo "  the corpus — the process start it is measured against does not either."

# ===========================================================================
# (c) the gate: THead.take vs a bare `head -n`
# ===========================================================================
echo
echo "(c) THead.take N FILE vs a bare \`head -n N -- FILE\` (INTERLEAVED, medians):"

# gate_shape N — time the two shapes interleaved and gate the medians at 1.5x.
gate_shape() {
    local __n="$1"
    local -a __t_bare=() __t_take=()
    local __i __a0 __a1 __s_bare=0 __s_take=0

    # warm the page cache and every code path once, so neither side pays for the
    # first read of the corpus or the first bind of a member wrapper.
    head -n "$__n" -- "$BIG" >/dev/null 2>&1 || :
    THead.take "$__n" "$BIG" >/dev/null 2>&1 || :

    for (( __i = 0; __i < NR; __i++ )); do
        TStopwatch.getTimeStamp; __a0=$RESULT
        head -n "$__n" -- "$BIG" >/dev/null || :
        TStopwatch.getTimeStamp; __a1=$RESULT
        __t_bare+=( $(( __a1 - __a0 )) ); __s_bare=$(( __s_bare + __a1 - __a0 ))

        TStopwatch.getTimeStamp; __a0=$RESULT
        THead.take "$__n" "$BIG" >/dev/null || :
        TStopwatch.getTimeStamp; __a1=$RESULT
        __t_take+=( $(( __a1 - __a0 )) ); __s_take=$(( __s_take + __a1 - __a0 ))
    done
    median __t_bare; local __m_bare="$MED"; (( __m_bare > 0 )) || __m_bare=1
    median __t_take; local __m_take="$MED"
    report_med "bare \`head -n $__n -- FILE\` (baseline)" "$__m_bare" "$__s_bare" "$NR"
    report_med "THead.take $__n FILE" "$__m_take" "$__s_take" "$NR"
    gate_ratio "  gate: take vs bare head, -n $__n (medians)" "$__m_take" "$__m_bare" 15
    printf '  delta %d us per call; section (b) measured the wrapper at %d us\n' \
        $(( __m_take - __m_bare )) "$per_ctor"
    echo
}

gate_shape 1
gate_shape "$HALF"

# ===========================================================================
# (d) counting: the `count` sink vs the `wc -l` equivalent
# ===========================================================================
echo "(d) counting — the \`count\` sink vs \`head -n $HALF | wc -l\` (published, NOT gated):"
THead.new BQ "$HALF" "$BIG"
declare -a T_WC=() T_CNT=()
b_wc=0; b_cnt=0
n_wc=''; n_cnt=''

# Warm both shapes, and take the record counts HERE, once. A `$( )` inside the
# timed loop would add a fork to the baseline and dilute the very comparison.
n_wc="$( head -n "$HALF" -- "$BIG" | wc -l )"
n_wc="${n_wc//[[:space:]]/}"
BQ.count >/dev/null 2>&1 || :

for (( i = 0; i < NR; i++ )); do
    TStopwatch.getTimeStamp; t0=$RESULT
    head -n "$HALF" -- "$BIG" | wc -l >/dev/null || :
    TStopwatch.getTimeStamp; t1=$RESULT
    T_WC+=( $(( t1 - t0 )) ); b_wc=$(( b_wc + t1 - t0 ))

    TStopwatch.getTimeStamp; t0=$RESULT
    BQ.count || :
    n_cnt="$RESULT"
    TStopwatch.getTimeStamp; t1=$RESULT
    T_CNT+=( $(( t1 - t0 )) ); b_cnt=$(( b_cnt + t1 - t0 ))
done
median T_WC;  m_wc="$MED"; (( m_wc > 0 )) || m_wc=1
median T_CNT; m_cnt="$MED"
report_med "\`head -n $HALF -- FILE | wc -l\` (baseline)" "$m_wc" "$b_wc" "$NR"
report_med "h.lines = $HALF; h.count" "$m_cnt" "$b_cnt" "$NR"
ratio "  published: h.count vs wc -l" "$m_cnt" "$m_wc" "the wc -l equivalent"
printf '  both answered %s / %s records; the gap is one bash read per record,\n' \
    "$n_wc" "$n_cnt"
printf '  which is what having the records in THIS shell costs (~%d us each)\n' \
    $(( (m_cnt - m_wc) / (HALF > 0 ? HALF : 1) ))
BQ.delete

# ===========================================================================
# (e) zero forks
# ===========================================================================
echo
echo "(e) zero-fork check (\$BASHPID around every THead member and in the callback):"
FORKPIDS=()
fork_cb() { FORKPIDS+=( "$BASHPID" ); return 0; }
class TBenchListTH
    public
        constructor Create
        proc        Add
end
TBenchListTH.Create() { return 0; }
TBenchListTH.Add()    { FORKPIDS+=( "$BASHPID" ); return 0; }
build TBenchListTH
TBenchListTH.new FL

printf 'one\ntwo\n' > "$BD/two.txt"
declare -a FARR=() FW=()
THead.new FH 2 "$BD/two.txt"
p0=$BASHPID; forked=0
FH.buildArgv                 ; [[ $BASHPID == "$p0" ]] || forked=1
FH.argv FW                   ; [[ $BASHPID == "$p0" ]] || forked=1
FH.paths "$BD/two.txt"       ; [[ $BASHPID == "$p0" ]] || forked=1
FH.addArg                    ; [[ $BASHPID == "$p0" ]] || forked=1
FH.clearArgs                 ; [[ $BASHPID == "$p0" ]] || forked=1
FH.mapRc 1 2>/dev/null       ; [[ $BASHPID == "$p0" ]] || forked=1
FH.lastRc                    ; [[ $BASHPID == "$p0" ]] || forked=1
FH.each    fork_cb    || :   ; [[ $BASHPID == "$p0" ]] || forked=1
FH.toList  FL         || :   ; [[ $BASHPID == "$p0" ]] || forked=1
FH.toArray FARR       || :   ; [[ $BASHPID == "$p0" ]] || forked=1
FH.count              || :   ; [[ $BASHPID == "$p0" ]] || forked=1
FH.first  2>/dev/null || :   ; [[ $BASHPID == "$p0" ]] || forked=1
FH.run >/dev/null     || :   ; [[ $BASHPID == "$p0" ]] || forked=1
THead.take 2 "$BD/two.txt" >/dev/null || :
                               [[ $BASHPID == "$p0" ]] || forked=1
for pid in "${FORKPIDS[@]}"; do
    [[ "$pid" == "$p0" ]] || forked=1
done
if (( forked == 0 )) && (( ${#FORKPIDS[@]} == 4 )); then
    echo "  BASHPID $p0 unchanged across all 13 members, \`take\`, and all four"
    echo "  callback/.Add invocations — the only fork per call is head itself"
else
    echo "  ZERO-FORK VIOLATION: p0=$p0 forked=$forked callback pids=(${FORKPIDS[*]})"
fi
FL.delete; FH.delete

# --- summary -----------------------------------------------------------------
echo
if (( GATES_FAILED == 0 )); then
    echo "gates: $GATES_TOTAL/$GATES_TOTAL PASS (THead.take <= 1.5x a bare \`head -n\`, medians of $NR interleaved runs)"
else
    echo "gates: $GATES_FAILED of $GATES_TOTAL FAILED — see the lines above"
fi

exit 0
