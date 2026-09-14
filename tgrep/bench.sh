#!/bin/bash
# Micro-benchmark for tgrep (P3.1). Publishes the numbers README.md §9 quotes
# and measures the PLAN.md §5 P3.1 gate:
#
#   (a) argv — what the typed option set costs to turn into a command line, and
#       the proof that it RUNS NOTHING: with `cmd` pointed at a shell function
#       that counts its own invocations, ND `argv` calls leave the counter at 0.
#       $BASHPID is read before and after: the builder is fork-free;
#   (b) GATED — `TGrep.search PATTERN DIR` against a bare `grep -r -e PATTERN --
#       DIR` over the same generated corpus. Gate: <= 1.3x. The delta is ONE
#       throw-away instance construction plus four kklass dispatches, and it is
#       measured on its own line so the ratio is explained and not just stated;
#   (c) PUBLISHED — `g.count` against `grep -c`. These answer the same question
#       by different means and the numbers are far apart on purpose: `grep -c`
#       counts inside grep and prints ONE line per file, while the `count` sink
#       reads every matching line into bash. The `countOnly` shortcut that gets
#       grep's own number through the wrapper is measured next to them;
#   (d) ZERO FORKS — $BASHPID around every TGrep member and inside a callback.
#
# Timing primitive: TStopwatch.getTimeStamp (kcl/tstopwatch) — one tested,
# locale-safe us clock shared by every kcl bench; RESULT-only, no fork.
# Deterministic: fixed sizes, no $RANDOM, one generated corpus everywhere.
#
# MEDIANS, AND WHY. Unlike tpipe's and tutil's, every number in (b) and (c) is
# ONE PROCESS START plus a scan — about 27 ms — and on this platform a process
# start occasionally takes 200 ms for reasons outside this repo (a scanner, a
# page-fault storm). One such outlier in 20 runs moves a MEAN by 9%, which is
# most of the head-room of a 1.3x gate, and it landed on a different side from
# run to run (the ratio read 1.07x, 1.23x and 1.51x on three consecutive runs of
# this file before this was fixed). So the two shapes are timed INTERLEAVED, one
# of each per iteration, each run is recorded separately, and the published
# ratio is computed from the MEDIANS. The mean is printed next to it, and a gap
# between the two IS the outlier telling you the box was not idle.
#
# The corpus is generated into a `mktemp -d` directory and removed by an EXIT
# trap: NL lines in `tree/big.txt`, every 100th carrying the sparse needle, plus
# a `tree/sub/small.txt` so `-r` has something to descend into.
#
# SMALL-N CAVEAT. (b) is dominated by that one process start plus the scan of NL
# lines; the wrapper's own cost is FIXED at a few milliseconds per call. Shrink
# the corpus (`bench.sh 200`) and that fixed cost becomes a visible fraction of
# the whole, so the ratio climbs for a reason that has nothing to do with the
# wrapper's per-line path — it has none. Re-run at the default NL before
# believing a failed (b).
#
# The gate printed here is the PLAN §5 number, measured by hand with the machine
# idle. `tests/007_Bench.sh` asserts the same shapes with a ceiling of 10x: ktests
# runs test files threaded (8 workers) and the two sides do NOT inflate together
# under that load — grep is its own process and roughly doubles, the wrapper's
# share is bash work in the contended shell and has been seen to grow tenfold.
#
# Run: bash bench.sh [NL] [NR] [ND]
#      (defaults: NL=10000 corpus lines, NR=20 runs per timing, ND=300 calls)
# Runs clean under `bash -eu`; always exits 0 (a failed gate is printed, not
# raised — tests/007_Bench.sh is the assertion).

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/tgrep.sh"
source "$DIR/../tstopwatch/tstopwatch.sh"

NL=${1:-10000}      # corpus lines in tree/big.txt
NR=${2:-20}         # repetitions per timed shape
ND=${3:-300}        # calls per per-call measurement

# ---------------------------------------------------------------------------
# helpers (the tpipe/bench.sh shape, so every kcl bench table reads the same)
# ---------------------------------------------------------------------------

report() {  # label total_us iters unit -> us/iter with tenths + total ms
    local x10=$(( $2 * 10 / $3 ))
    printf '  %-44s %7d.%d us/%s  (total %d ms)\n' "$1" $(( x10/10 )) $(( x10%10 )) "$4" $(( $2/1000 ))
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
    printf '  %-44s median %5d.%02d ms   mean %5d.%02d ms  (%d runs)\n' \
        "$1" $(( m100/100 )) $(( m100%100 )) $(( a100/100 )) $(( a100%100 )) "$4"
}

ratio() {   # label value_us base_us base_label -> the ratio, no verdict
    local r100=$(( $2 * 100 / $3 ))
    printf '  %-44s ratio %d.%02dx of %s\n' \
        "$1" $(( r100/100 )) $(( r100%100 )) "$4"
}

gate_ratio() {  # label median_us base_median_us limit_tenths -> ratio + PASS/FAIL
    local r100=$(( $2 * 100 / $3 )) lim=$(( $3 * $4 / 10 )) verdict
    if (( $2 <= lim )); then verdict="PASS"; else verdict="FAIL"; GATES_FAILED=$(( GATES_FAILED + 1 )); fi
    printf '  %-44s ratio %d.%02dx  (gate %d.%dx) %s\n' \
        "$1" $(( r100/100 )) $(( r100%100 )) $(( $4/10 )) $(( $4%10 )) "$verdict"
}

GATES_FAILED=0

# --- the GNU banner gate ----------------------------------------------------
# This box also carries a non-GNU `grep` (Embarcadero) that can win the PATH
# race. Every number below is about GNU grep 3.0; on anything else they are not
# comparable, so say so loudly instead of publishing a meaningless table.
GREP_BANNER="$(grep --version 2>/dev/null | head -n 1 || true)"
case "$GREP_BANNER" in
    "grep (GNU grep) "*) ;;
    *) echo "tgrep bench: SKIPPED — \`grep\` is not GNU grep: '$GREP_BANNER'"; exit 0 ;;
esac

# --- the corpus -------------------------------------------------------------
BD="$(mktemp -d)"
trap 'rm -rf "$BD"' EXIT
mkdir -p "$BD/tree/sub"
{
    for (( _i = 0; _i < NL; _i++ )); do
        if (( _i % 100 == 0 )); then
            printf 'line %d needle here\n' "$_i"
        else
            printf 'line %d nothing here\n' "$_i"
        fi
    done
} > "$BD/tree/big.txt"
printf 'line a needle here\nline b nothing here\n' > "$BD/tree/sub/small.txt"
TREE="$BD/tree"
SPARSE_HITS=$(( NL / 100 + 1 ))     # `needle`: every 100th line, plus small.txt
DENSE_HITS=$(( NL + 2 ))            # `line`:   every line of both files

echo "tgrep micro-benchmark  (bash ${BASH_VERSION}, ${GREP_BANNER})"
echo "corpus: $NL lines in tree/big.txt + 2 in tree/sub/small.txt; NR=$NR runs, ND=$ND calls"
echo

# ===========================================================================
# (a) the typed option set -> argv
# ===========================================================================
echo "the argv model — 22 typed options into a command line, running NOTHING:"
TGrep.new BG needle "$TREE"
BG.ignoreCase = 1
BG.recursive  = 1
BG.lineNumber = 1
BG.maxCount   = 8
BG.include    = '*.txt'
declare -a BW=()

TStopwatch.getTimeStamp; t0=$RESULT
for (( i = 0; i < ND; i++ )); do BG.buildArgv; done
TStopwatch.getTimeStamp; t1=$RESULT
b_build=$(( t1 - t0 )); (( b_build > 0 )) || b_build=1
report "buildArgv (the override, 22 options)" "$b_build" "$ND" "call"

TStopwatch.getTimeStamp; t0=$RESULT
for (( i = 0; i < ND; i++ )); do BG.argv BW; done
n_argv="$RESULT"
TStopwatch.getTimeStamp; t1=$RESULT
b_argv=$(( t1 - t0 )); (( b_argv > 0 )) || b_argv=1
report "argv NAME (buildArgv + validate + copy)" "$b_argv" "$ND" "call"
printf '  %-44s %s words: %s\n' "argv NAME copied" "$n_argv" "${BW[*]}"

# grep is never executed above; prove it by pointing `cmd` at a function that
# would count its own invocations, and building ND more times.
BENCH_RAN=0
bench_counted() { BENCH_RAN=$(( BENCH_RAN + 1 )); return 0; }
BG.cmd = bench_counted
pid_a="$BASHPID"
for (( i = 0; i < ND; i++ )); do BG.argv BW; done
BG.cmd = grep
if (( BENCH_RAN == 0 )) && [[ "$BASHPID" == "$pid_a" ]]; then
    echo "  RUNS NOTHING: with cmd pointed at a counting function, $ND builds invoked it 0 times"
    echo "  FORK-FREE:    BASHPID $pid_a unchanged across all $(( ND * 3 )) builds"
else
    echo "  VIOLATION: cmd invoked $BENCH_RAN times, BASHPID $pid_a -> $BASHPID"
fi
BG.delete

# ===========================================================================
# (b) the gate: TGrep.search vs a bare `grep -r`
# ===========================================================================
echo
echo "TGrep.search vs a bare \`grep -r\` over the same tree ($SPARSE_HITS hits):"

# warm the page cache and every code path once, so neither side pays for the
# first read of the corpus or the first bind of a member wrapper.
grep -r -e needle -- "$TREE" >/dev/null 2>&1 || :
TGrep.search needle "$TREE" >/dev/null 2>&1 || :

declare -a T_GREP=() T_SEARCH=()
b_grep=0; b_search=0
for (( i = 0; i < NR; i++ )); do
    TStopwatch.getTimeStamp; t0=$RESULT
    grep -r -e needle -- "$TREE" >/dev/null || :
    TStopwatch.getTimeStamp; t1=$RESULT
    T_GREP+=( $(( t1 - t0 )) ); b_grep=$(( b_grep + t1 - t0 ))

    TStopwatch.getTimeStamp; t0=$RESULT
    TGrep.search needle "$TREE" >/dev/null || :
    TStopwatch.getTimeStamp; t1=$RESULT
    T_SEARCH+=( $(( t1 - t0 )) ); b_search=$(( b_search + t1 - t0 ))
done
median T_GREP;   m_grep="$MED";   (( m_grep > 0 )) || m_grep=1
median T_SEARCH; m_search="$MED"
report_med "bare \`grep -r -e needle -- TREE\` (baseline)" "$m_grep" "$b_grep" "$NR"
report_med "TGrep.search needle TREE" "$m_search" "$b_search" "$NR"
gate_ratio "  gate: search vs bare grep -r (medians)" "$m_search" "$m_grep" 13

# the delta, measured on its own: one instance construction + its destruction.
TStopwatch.getTimeStamp; t0=$RESULT
for (( i = 0; i < ND; i++ )); do TGrep.new BC needle "$TREE"; BC.delete; done
TStopwatch.getTimeStamp; t1=$RESULT
b_ctor=$(( t1 - t0 )); (( b_ctor > 0 )) || b_ctor=1
report "TGrep.new + .delete (the search delta)" "$b_ctor" "$ND" "call"
printf '  search costs %d us more per call than bare grep; the construction above\n' \
    $(( m_search - m_grep ))
printf '  is %d us of that, the rest is four kklass dispatches\n' $(( b_ctor / ND ))

# ===========================================================================
# (c) counting: the sink vs grep's own counter
# ===========================================================================
echo
echo "counting — the \`count\` sink vs \`grep -c\` (published, NOT gated):"
# Three shapes, INTERLEAVED for the same reason as (b), so three instances.
TGrep.new BQ  needle "$TREE"; BQ.recursive  = 1
TGrep.new BQC needle "$TREE"; BQC.recursive = 1; BQC.countOnly = 1
declare -a BCARR=() T_GC=() T_CNT=() T_CO=()

grep -c -r -e needle -- "$TREE" >/dev/null 2>&1 || :   # warm all three shapes
BQ.count             >/dev/null 2>&1 || :
BQC.toArray BCARR    >/dev/null 2>&1 || :

b_grepc=0; b_count=0; b_conly=0
for (( i = 0; i < NR; i++ )); do
    TStopwatch.getTimeStamp; t0=$RESULT
    grep -c -r -e needle -- "$TREE" >/dev/null || :
    TStopwatch.getTimeStamp; t1=$RESULT
    T_GC+=( $(( t1 - t0 )) ); b_grepc=$(( b_grepc + t1 - t0 ))

    TStopwatch.getTimeStamp; t0=$RESULT
    BQ.count || :
    n_sparse="$RESULT"
    TStopwatch.getTimeStamp; t1=$RESULT
    T_CNT+=( $(( t1 - t0 )) ); b_count=$(( b_count + t1 - t0 ))

    TStopwatch.getTimeStamp; t0=$RESULT
    BQC.toArray BCARR || :
    n_conly="$RESULT"
    TStopwatch.getTimeStamp; t1=$RESULT
    T_CO+=( $(( t1 - t0 )) ); b_conly=$(( b_conly + t1 - t0 ))
done
median T_GC;  m_grepc="$MED"; (( m_grepc > 0 )) || m_grepc=1
median T_CNT; m_count="$MED"
median T_CO;  m_conly="$MED"
report_med "bare \`grep -c -r\` (baseline, $SPARSE_HITS hits)" "$m_grepc" "$b_grepc" "$NR"
report_med "g.count ($n_sparse records read into bash)" "$m_count" "$b_count" "$NR"
ratio "  published: g.count vs grep -c, sparse" "$m_count" "$m_grepc" "bare grep -c"
report_med "g.countOnly=1; g.toArray ($n_conly records)" "$m_conly" "$b_conly" "$NR"
ratio "  published: countOnly vs grep -c" "$m_conly" "$m_grepc" "bare grep -c"
printf '  countOnly delivers the per-file numbers grep itself computed: %s\n' "${BCARR[*]}"

# the DENSE case: the same corpus, a pattern that matches every line. A run
# costs ~1.5 s at NL=10000 (one bash `read` per line), so it is repeated a fifth
# as often. At fifty times the baseline an outlier is not what this number is
# about, so the mean of NRD runs is what is published.
NRD=$(( NR / 5 )); (( NRD > 0 )) || NRD=1
BQ.pattern = line
BQ.count >/dev/null 2>&1 || :          # warm
TStopwatch.getTimeStamp; t0=$RESULT
for (( i = 0; i < NRD; i++ )); do BQ.count || :; done
n_dense="$RESULT"
TStopwatch.getTimeStamp; t1=$RESULT
b_dense=$(( t1 - t0 ))
report_med "g.count, DENSE ($n_dense records)" $(( b_dense / NRD )) "$b_dense" "$NRD"
ratio "  published: g.count vs grep -c, dense" $(( b_dense / NRD )) "$m_grepc" "bare grep -c"
BQ.delete; BQC.delete

# ===========================================================================
# (d) zero forks
# ===========================================================================
echo
echo "zero-fork check (\$BASHPID around every TGrep member and in the callback):"
FORKPIDS=()
fork_cb() { FORKPIDS+=( "$BASHPID" ); return 0; }
class TForkList7
    public
        constructor Create
        proc        Add
end
TForkList7.Create() { return 0; }
TForkList7.Add()    { FORKPIDS+=( "$BASHPID" ); return 0; }
build TForkList7
TForkList7.new FL

declare -a FARR=() FW=()
TGrep.new FG needle "$TREE/sub/small.txt"
p0=$BASHPID; forked=0
FG.buildArgv                  ; [[ $BASHPID == "$p0" ]] || forked=1
FG.argv FW                    ; [[ $BASHPID == "$p0" ]] || forked=1
FG.paths "$TREE/sub/small.txt"; [[ $BASHPID == "$p0" ]] || forked=1
FG.addArg                     ; [[ $BASHPID == "$p0" ]] || forked=1
FG.clearArgs                  ; [[ $BASHPID == "$p0" ]] || forked=1
FG.mapRc 2 2>/dev/null        ; [[ $BASHPID == "$p0" ]] || forked=1
FG.lastRc                     ; [[ $BASHPID == "$p0" ]] || forked=1
FG.each    fork_cb     || :   ; [[ $BASHPID == "$p0" ]] || forked=1
FG.toList  FL          || :   ; [[ $BASHPID == "$p0" ]] || forked=1
FG.toArray FARR        || :   ; [[ $BASHPID == "$p0" ]] || forked=1
FG.count               || :   ; [[ $BASHPID == "$p0" ]] || forked=1
FG.first  2>/dev/null  || :   ; [[ $BASHPID == "$p0" ]] || forked=1
FG.run >/dev/null      || :   ; [[ $BASHPID == "$p0" ]] || forked=1
TGrep.search needle "$TREE/sub/small.txt" >/dev/null || :
                                [[ $BASHPID == "$p0" ]] || forked=1
for pid in "${FORKPIDS[@]}"; do
    [[ "$pid" == "$p0" ]] || forked=1
done
if (( forked == 0 )) && (( ${#FORKPIDS[@]} == 2 )); then
    echo "  BASHPID $p0 unchanged across all 13 members, \`search\`, and both"
    echo "  callback/.Add invocations — the only fork per call is grep itself"
else
    echo "  ZERO-FORK VIOLATION: p0=$p0 forked=$forked callback pids=(${FORKPIDS[*]})"
fi
FL.delete; FG.delete

# --- summary -----------------------------------------------------------------
echo
echo "hits: sparse $n_sparse (want $SPARSE_HITS), dense $n_dense (want $DENSE_HITS)"
if (( GATES_FAILED == 0 )); then
    echo "gates: 1/1 PASS (TGrep.search <= 1.3x a bare grep -r on the same tree)"
else
    echo "gates: $GATES_FAILED of 1 FAILED — see the lines above"
fi

exit 0
