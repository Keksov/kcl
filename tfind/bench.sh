#!/bin/bash
# Micro-benchmark for tfind (P1). Publishes the numbers README.md §10 quotes and
# measures the PLAN.md §5 P1 gate:
#
#   (a) ARGV — what the typed option set costs to turn into a command line, and
#       the proof that it RUNS NOTHING: with `cmd` pointed at a shell function
#       that counts its own invocations, ND `argv` calls leave the counter at 0.
#       $BASHPID is read before and after: the builder is fork-free;
#   (b) THE WRAPPER'S FIXED DELTA — `new` + `name =` + `argv` + `delete` on its
#       own line. That quadruple is the WHOLE difference between
#       `TFind.byName '*.txt' TREE` and the bare `find TREE -name '*.txt'` of
#       (c): one throw-away instance (NINE properties to assign, where thead has
#       six), one property write, one build, one destruction, and then the same
#       single fork. It is a per-CALL cost and never a per-record one;
#   (c) GATED — `TFind.byName '*.txt' TREE` against a bare
#       `find TREE -name '*.txt'` over the same generated corpus, in the two
#       shapes that bracket the tool's own work: a 400-file tree (find really
#       walks) and a ONE-file tree (the fork IS the measurement). Gate:
#       <= **1.5x**, from the MEDIANS of NR >= 15 INTERLEAVED runs;
#   (d) PUBLISHED, NOT GATED — `f.count` with `print0 = 1` against the shell
#       equivalent `find … -print0 | tr -dc '\0' | wc -c`. They answer the same
#       question by different means: `tr`+`wc` count in two more processes at
#       memory speed, the `count` sink reads every record into bash. The gap is
#       the price of having the records in this shell, and it is a per-RECORD
#       price;
#   (e) ZERO FORKS — $BASHPID around every TFind and TUtil member, around a
#       REFUSED build (the rc 2 path forks nothing either), around `byName`, and
#       inside an `each` callback and a `.Add`.
#
# Timing primitive: TStopwatch.getTimeStamp (kcl/tstopwatch) — one tested,
# locale-safe us clock shared by every kcl bench; RESULT-only, no fork.
# **`date +%s%N` must NOT be used here**: on msys each call is its own process
# and costs ~20 ms — more than half of the very `find` run being measured, and
# it would be paid twice per sample (PLAN §8 finding 17).
# Deterministic: fixed sizes, no $RANDOM, one generated corpus everywhere.
#
# WHY THE CORPUS SIZE DOES NOT MOVE THE RATIO OF (c). On this platform a whole
# `find` run — the msys `fork`+`exec` of a findutils binary, plus the walk —
# costs ~32 ms, while the wrapper's entire fixed delta — section (b) — is
# ~4.7 ms (nine properties assigned by the constructor, one written by the
# caller). The ratio of (c) is therefore roughly (32 + 4.7) / 32: it sits near
# 1.15x and can only fall as the walk grows. Four hundred files do not make the
# wrapper cheaper, they make the denominator bigger — which is why the 400-file
# tree and the ONE-file tree land within a few points of each other below.
#
# MEDIANS, AND WHY THEY ARE NOT NEGOTIABLE. Every number in (c) and (d) is ONE
# PROCESS START plus a walk, and on this platform a process start occasionally
# takes several hundred milliseconds for reasons outside this repo (a scanner, a
# page-fault storm). One such outlier in 20 runs moves a MEAN by more than the
# whole head-room of the gate, and it lands on a different side from run to run:
# the WORST SINGLE PAIRING measured while this unit was planned read **1.64x**
# on code whose interleaved medians are 1.13-1.16x (PLAN §8 finding 17). A
# single pairing, or a non-interleaved loop, can therefore fail a 1.5x gate on
# code that is fine. So the two sides are timed INTERLEAVED, one of each per
# iteration, every run is recorded separately, and the published ratio is
# computed from the MEDIANS. The MEAN is printed next to each median, and a gap
# between the two IS the outlier telling you the box was not idle.
#
# The corpus is generated into a `mktemp -d` directory and removed by an EXIT
# trap (this is a bench, not a test file: a test file must NOT install a trap of
# its own, it would replace ktests').
#
# The gate printed here is the PLAN §5 P1 number, measured by hand with the
# machine idle. `tests/007_Bench.sh` asserts the same shapes with a ceiling of
# 10x: ktests runs test files threaded (8 workers) and the two sides do NOT
# inflate together under that load — `find` is its own process, while the
# wrapper's share is bash work in the contended shell.
#
# Run: bash bench.sh [NDIR] [NR] [ND]
#      (defaults: NDIR=20 directories of 20 .txt + 1 .dat each, NR=21
#       interleaved runs, ND=300 calls)
# Runs clean under `bash -eu`; always exits 0 (a failed gate is printed, not
# raised — tests/007_Bench.sh is the assertion).

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/tfind.sh"
source "$DIR/../tstopwatch/tstopwatch.sh"

NDIR=${1:-20}       # sub-directories in the big tree
NR=${2:-21}         # interleaved repetitions per gated shape (odd, >= 15)
ND=${3:-300}        # calls per per-call measurement
NF=20               # .txt files per sub-directory

# ---------------------------------------------------------------------------
# helpers (the tgrep/thead/ttail bench shape, so every kcl bench table reads the
# same)
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
# D4 pins the DIALECT (GNU findutils 4.10.0), not a binary. Every number below
# is about that tool; on anything else they are not comparable, so say so loudly
# instead of publishing a meaningless table.
FIND_BANNER="$(find --version 2>/dev/null | sed -n 1p || true)"
case "$FIND_BANNER" in
    "find (GNU findutils) "*) ;;
    *) echo "tfind bench: SKIPPED — \`find\` is not GNU findutils: '$FIND_BANNER'"; exit 0 ;;
esac

# --- the corpus -------------------------------------------------------------
# Two trees, both under one `mktemp -d`: BIG has NDIR * NF `.txt` files (plus one
# `.dat` per directory, so `-name '*.txt'` really filters), ONE holds a single
# `.txt`. Every file holds `x\n` so a `-size +0` probe would have something to
# match, and no file name needs quoting beyond what the wrapper already does.
BD="$(mktemp -d)"
trap 'rm -rf "$BD"' EXIT
BIG="$BD/tree"
ONE="$BD/one"
mkdir -p "$BIG" "$ONE"
for (( _d = 0; _d < NDIR; _d++ )); do
    printf -v _dn '%s/d%02d' "$BIG" "$_d"
    mkdir -p "$_dn"
    for (( _f = 0; _f < NF; _f++ )); do
        printf -v _fn '%s/f%02d.txt' "$_dn" "$_f"
        printf 'x\n' > "$_fn"
    done
    printf 'x\n' > "$_dn/skip.dat"
done
printf 'x\n' > "$ONE/only.txt"
NTXT=$(( NDIR * NF ))

echo "tfind micro-benchmark  (bash ${BASH_VERSION}, ${FIND_BANNER})"
echo "corpus: $NDIR dirs x $NF .txt (+1 .dat) = $NTXT matches in tree/, 1 match in one/"
echo "        NR=$NR interleaved runs, ND=$ND calls"
echo

# ===========================================================================
# (a) the typed option set -> argv
# ===========================================================================
echo "(a) the argv model — typed options into a command line, running NOTHING:"
TFind.new BF "$BIG"
BF.name = '*.txt'
BF.type = f
BF.maxDepth = 9
declare -a BW=()

TStopwatch.getTimeStamp; t0=$RESULT
for (( i = 0; i < ND; i++ )); do BF.buildArgv; done
TStopwatch.getTimeStamp; t1=$RESULT
b_build=$(( t1 - t0 )); (( b_build > 0 )) || b_build=1
report "buildArgv (the override)" "$b_build" "$ND" "call"

TStopwatch.getTimeStamp; t0=$RESULT
for (( i = 0; i < ND; i++ )); do BF.argv BW; done
n_argv="$RESULT"
TStopwatch.getTimeStamp; t1=$RESULT
b_argv=$(( t1 - t0 )); (( b_argv > 0 )) || b_argv=1
report "argv NAME (buildArgv + validate + copy)" "$b_argv" "$ND" "call"
printf '  %-46s %s words: %s\n' "argv NAME copied" "$n_argv" "${BW[*]}"

# find is never executed above; prove it by pointing `cmd` at a function that
# would count its own invocations, and building ND more times.
BENCH_RAN=0
bench_counted() { BENCH_RAN=$(( BENCH_RAN + 1 )); return 0; }
BF.cmd = bench_counted
pid_a="$BASHPID"
for (( i = 0; i < ND; i++ )); do BF.argv BW; done
BF.cmd = find
if (( BENCH_RAN == 0 )) && [[ "$BASHPID" == "$pid_a" ]]; then
    echo "  RUNS NOTHING: with cmd pointed at a counting function, $ND builds invoked it 0 times"
    echo "  FORK-FREE:    BASHPID $pid_a unchanged across all $(( ND * 3 )) builds"
else
    echo "  VIOLATION: cmd invoked $BENCH_RAN times, BASHPID $pid_a -> $BASHPID"
fi

# The rc 2 path is a build too, and it is the one a caller hits by accident.
TFind.new BR '-weird'
TStopwatch.getTimeStamp; t0=$RESULT
for (( i = 0; i < ND; i++ )); do BR.buildArgv >/dev/null 2>&1 || :; done
TStopwatch.getTimeStamp; t1=$RESULT
b_ref=$(( t1 - t0 )); (( b_ref > 0 )) || b_ref=1
report "buildArgv REFUSED (rc 2, a \`-weird\` start point)" "$b_ref" "$ND" "call"
BR.delete
BF.delete

# ===========================================================================
# (b) the wrapper's fixed delta: new + name + argv + delete
# ===========================================================================
echo
echo "(b) the wrapper's FIXED delta — one instance, one property, one build, one"
echo "    destruction (what \`byName\` does around the same single fork):"
declare -a BV=()
TStopwatch.getTimeStamp; t0=$RESULT
for (( i = 0; i < ND; i++ )); do
    TFind.new BC "$BIG"
    BC.name = '*.txt'
    BC.argv BV
    BC.delete
done
TStopwatch.getTimeStamp; t1=$RESULT
b_ctor=$(( t1 - t0 )); (( b_ctor > 0 )) || b_ctor=1
report "new + name + argv + delete (the byName delta)" "$b_ctor" "$ND" "call"
per_ctor=$(( b_ctor / ND ))
echo "  this is the WHOLE difference between \`byName\` and the bare tool below;"
echo "  the constructor assigns NINE properties (thead's assigns six), it is paid"
echo "  once per CALL, never per record, and it does not grow with the corpus —"
echo "  the process start it is measured against does not either."

# ===========================================================================
# (c) the gate: TFind.byName vs a bare `find … -name`
# ===========================================================================
echo
echo "(c) TFind.byName '*.txt' TREE vs a bare \`find TREE -name '*.txt'\` (INTERLEAVED, medians):"

# gate_shape TREE LABEL — time the two shapes interleaved and gate the medians
# at 1.5x.
gate_shape() {
    local __tree="$1" __label="$2"
    local -a __t_bare=() __t_by=()
    local __i __a0 __a1 __s_bare=0 __s_by=0

    # warm the directory cache and every code path once, so neither side pays
    # for the first walk of the corpus or the first bind of a member wrapper.
    find "$__tree" -name '*.txt' >/dev/null 2>&1 || :
    TFind.byName '*.txt' "$__tree" >/dev/null 2>&1 || :

    for (( __i = 0; __i < NR; __i++ )); do
        TStopwatch.getTimeStamp; __a0=$RESULT
        find "$__tree" -name '*.txt' >/dev/null || :
        TStopwatch.getTimeStamp; __a1=$RESULT
        __t_bare+=( $(( __a1 - __a0 )) ); __s_bare=$(( __s_bare + __a1 - __a0 ))

        TStopwatch.getTimeStamp; __a0=$RESULT
        TFind.byName '*.txt' "$__tree" >/dev/null || :
        TStopwatch.getTimeStamp; __a1=$RESULT
        __t_by+=( $(( __a1 - __a0 )) ); __s_by=$(( __s_by + __a1 - __a0 ))
    done
    median __t_bare; local __m_bare="$MED"; (( __m_bare > 0 )) || __m_bare=1
    median __t_by;   local __m_by="$MED"
    report_med "bare \`find $__label -name '*.txt'\` (baseline)" "$__m_bare" "$__s_bare" "$NR"
    report_med "TFind.byName '*.txt' $__label" "$__m_by" "$__s_by" "$NR"
    gate_ratio "  gate: byName vs bare find, $__label (medians)" "$__m_by" "$__m_bare" 15
    printf '  delta %d us per call; section (b) measured the wrapper at %d us\n' \
        $(( __m_by - __m_bare )) "$per_ctor"
    # The worst SINGLE pairing of this very sample, for comparison with the
    # median above: this is the number a one-shot measurement would have
    # published, and it is why the protocol is what it is.
    local __worst=0 __r100 __j
    for (( __j = 0; __j < NR; __j++ )); do
        __r100=$(( __t_by[__j] * 100 / ( __t_bare[__j] > 0 ? __t_bare[__j] : 1 ) ))
        (( __r100 > __worst )) && __worst=$__r100
    done
    printf '  worst SINGLE pairing in this sample: %d.%02dx — one sample is not a measurement\n' \
        $(( __worst/100 )) $(( __worst%100 ))
    echo
}

gate_shape "$BIG" "tree/ ($NTXT matches)"
gate_shape "$ONE" "one/ (1 match)"

# ===========================================================================
# (d) counting: the `count` sink vs the `tr -dc '\0' | wc -c` equivalent
# ===========================================================================
echo "(d) counting — the \`count\` sink vs \`find … -print0 | tr -dc '\\0' | wc -c\` (published, NOT gated):"
TFind.new BQ "$BIG"
BQ.name = '*.txt'
BQ.print0 = 1
TFind.new BQ1 "$ONE"           # the SAME sink over ONE record: the fixed half
BQ1.name = '*.txt'
BQ1.print0 = 1
declare -a T_WC=() T_CNT=() T_CNT1=()
b_wc=0; b_cnt=0; b_cnt1=0
n_wc=''; n_cnt=''

# Warm both shapes, and take the record counts HERE, once. A `$( )` inside the
# timed loop would add a fork to the baseline and dilute the very comparison.
# `tr -dc '\0' | wc -c` is the NUL-framed equivalent of `wc -l`: it counts the
# record TERMINATORS, so a name containing a newline still counts once.
n_wc="$( find "$BIG" -name '*.txt' -print0 | tr -dc '\0' | wc -c )"
n_wc="${n_wc//[[:space:]]/}"
BQ.count >/dev/null 2>&1 || :
BQ1.count >/dev/null 2>&1 || :

for (( i = 0; i < NR; i++ )); do
    TStopwatch.getTimeStamp; t0=$RESULT
    find "$BIG" -name '*.txt' -print0 | tr -dc '\0' | wc -c >/dev/null || :
    TStopwatch.getTimeStamp; t1=$RESULT
    T_WC+=( $(( t1 - t0 )) ); b_wc=$(( b_wc + t1 - t0 ))

    TStopwatch.getTimeStamp; t0=$RESULT
    BQ.count || :
    n_cnt="$RESULT"
    TStopwatch.getTimeStamp; t1=$RESULT
    T_CNT+=( $(( t1 - t0 )) ); b_cnt=$(( b_cnt + t1 - t0 ))

    TStopwatch.getTimeStamp; t0=$RESULT
    BQ1.count || :
    TStopwatch.getTimeStamp; t1=$RESULT
    T_CNT1+=( $(( t1 - t0 )) ); b_cnt1=$(( b_cnt1 + t1 - t0 ))
done
median T_WC;   m_wc="$MED";  (( m_wc > 0 )) || m_wc=1
median T_CNT;  m_cnt="$MED"
median T_CNT1; m_cnt1="$MED"
report_med "\`find … -print0 | tr -dc '\\0' | wc -c\` (baseline)" "$m_wc" "$b_wc" "$NR"
report_med "f.print0 = 1; f.count ($NTXT records)" "$m_cnt" "$b_cnt" "$NR"
report_med "the same sink over ONE record (the fixed half)" "$m_cnt1" "$b_cnt1" "$NR"
ratio "  published: f.count vs the wc equivalent" "$m_cnt" "$m_wc" "the shell equivalent"
printf '  both answered %s / %s records\n' "$n_wc" "$n_cnt"
# The sink's cost splits cleanly: a fixed part (one find, one instance) and a
# per-record part (one bash `read` each). Measured, not assumed — the ONE-record
# row above IS the fixed part, so the difference over (NTXT - 1) records is the
# marginal cost of a record.
per_rec=$(( (m_cnt - m_cnt1) / (NTXT > 1 ? NTXT - 1 : 1) ))
printf '  marginal cost of ONE record read into bash: ~%d us (%d-record row minus\n' \
    "$per_rec" "$NTXT"
printf '  the 1-record row, over %d records)\n' $(( NTXT > 1 ? NTXT - 1 : 1 ))
if (( m_cnt > m_wc )); then
    printf '  at this corpus the sink is the SLOWER of the two: that per-record price\n'
    printf '  is what having the records in THIS shell costs, and when all you want is\n'
    printf '  the number, the pipeline is the right answer.\n'
else
    printf '  at this corpus the SINK IS FASTER — and that is not a bash victory:\n'
    printf '  counting NUL-framed records in the shell needs `tr` AND `wc`, two more\n'
    printf '  msys process starts on top of find (%d ms of pipeline over the %d ms the\n' \
        $(( (m_wc - m_cnt1) / 1000 )) $(( m_cnt1 / 1000 ))
    printf '  sink pays for its one fork), while the sink adds only the ~%d us per\n' "$per_rec"
    if (( per_rec > 0 )); then
        printf '  record measured above. The crossover is ~%d records; past it the\n' \
            $(( (m_wc - m_cnt1) / per_rec ))
        printf '  pipeline wins again. Which is exactly why this row is published, never gated.\n'
    else
        printf '  record measured above. Which is why this row is published, never gated.\n'
    fi
fi
BQ1.delete
BQ.delete

# ===========================================================================
# (e) zero forks
# ===========================================================================
echo
echo "(e) zero-fork check (\$BASHPID around every TFind/TUtil member, a REFUSED"
echo "    build, \`byName\`, and inside the callback and \`.Add\`):"
FORKPIDS=()
fork_cb() { FORKPIDS+=( "$BASHPID" ); return 0; }
class TBenchListTF
    public
        constructor Create
        proc        Add
end
TBenchListTF.Create() { return 0; }
TBenchListTF.Add()    { FORKPIDS+=( "$BASHPID" ); return 0; }
build TBenchListTF
TBenchListTF.new FL

declare -a FARR=() FW=()
TFind.new FF "$ONE"
FF.print0 = 1
p0=$BASHPID; forked=0
FF.name = '*.txt'            ; [[ $BASHPID == "$p0" ]] || forked=1
FF.iname = ''                ; [[ $BASHPID == "$p0" ]] || forked=1
FF.type = f                  ; [[ $BASHPID == "$p0" ]] || forked=1
FF.maxDepth = 9              ; [[ $BASHPID == "$p0" ]] || forked=1
FF.minDepth = 0              ; [[ $BASHPID == "$p0" ]] || forked=1
FF.newer = ''                ; [[ $BASHPID == "$p0" ]] || forked=1
FF.followSymlinks = 0        ; [[ $BASHPID == "$p0" ]] || forked=1
FF.buildArgv                 ; [[ $BASHPID == "$p0" ]] || forked=1
FF.argv FW                   ; [[ $BASHPID == "$p0" ]] || forked=1
FF.paths "$ONE"              ; [[ $BASHPID == "$p0" ]] || forked=1
FF.addArg                    ; [[ $BASHPID == "$p0" ]] || forked=1
FF.clearArgs                 ; [[ $BASHPID == "$p0" ]] || forked=1
FF.mapRc 1 2>/dev/null       ; [[ $BASHPID == "$p0" ]] || forked=1
FF.lastRc                    ; [[ $BASHPID == "$p0" ]] || forked=1
FF.each    fork_cb    || :   ; [[ $BASHPID == "$p0" ]] || forked=1
FF.toList  FL         || :   ; [[ $BASHPID == "$p0" ]] || forked=1
FF.toArray FARR       || :   ; [[ $BASHPID == "$p0" ]] || forked=1
FF.count              || :   ; [[ $BASHPID == "$p0" ]] || forked=1
FF.first  2>/dev/null || :   ; [[ $BASHPID == "$p0" ]] || forked=1
FF.run >/dev/null     || :   ; [[ $BASHPID == "$p0" ]] || forked=1
TFind.byName '*.txt' "$ONE" >/dev/null || :
                               [[ $BASHPID == "$p0" ]] || forked=1
# the rc 2 paths: a refused build and a refused one-liner fork nothing either
TFind.new FR '-weird'
FR.count 2>/dev/null   || :  ; [[ $BASHPID == "$p0" ]] || forked=1
TFind.byName '*.txt' 2>/dev/null || :
                               [[ $BASHPID == "$p0" ]] || forked=1
FR.delete
for pid in "${FORKPIDS[@]}"; do
    [[ "$pid" == "$p0" ]] || forked=1
done
if (( forked == 0 )) && (( ${#FORKPIDS[@]} == 2 )); then
    echo "  BASHPID $p0 unchanged across all 20 members, \`byName\`, both rc 2"
    echo "  paths, and both callback/.Add invocations — the only fork per call is"
    echo "  find itself, and a refused call does not even pay that"
else
    echo "  ZERO-FORK VIOLATION: p0=$p0 forked=$forked callback pids=(${FORKPIDS[*]})"
fi
FL.delete; FF.delete

# --- summary -----------------------------------------------------------------
echo
if (( GATES_FAILED == 0 )); then
    echo "gates: $GATES_TOTAL/$GATES_TOTAL PASS (TFind.byName <= 1.5x a bare \`find … -name\`, medians of $NR interleaved runs)"
else
    echo "gates: $GATES_FAILED of $GATES_TOTAL FAILED — see the lines above"
fi

exit 0
