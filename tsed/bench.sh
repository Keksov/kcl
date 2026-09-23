#!/bin/bash
# Micro-benchmark for tsed (P1). Publishes the numbers README.md §10 quotes and
# measures the PLAN.md §5 P1 gate:
#
#   (a) ARGV — what the typed option set costs to turn into a command line, and
#       the proof that it RUNS NOTHING: with `cmd` pointed at a shell function
#       that counts its own invocations, 2 x ND builds leave the counter at 0.
#       $BASHPID is read before and after: the builder is fork-free. The cost of
#       a REFUSED build is timed too — a deny-list hit (owner Q6), because the
#       deny-list scan is this unit's own addition to the build and the refusal
#       is the path a caller reaches by accident;
#   (b) THE WRAPPER'S FIXED DELTA — exactly what `TSed.edit` does around the one
#       fork, on its own line: `new` (ELEVEN properties assigned, two arrays
#       declared, where tfind's constructor assigns nine and declares one),
#       `addExpr`, `sandbox = 1`, the build (with the deny-list scan over the
#       empty extras) and `delete`. It is a per-CALL cost and never a per-record
#       one;
#   (c) GATED — `TSed.edit 's/a/A/' FILE` against a bare
#       `sed --sandbox -e 's/a/A/' -- FILE` over the same generated corpus, in the
#       two shapes that bracket the tool's own work: a 10 000-line file (sed
#       really edits) and a ONE-line file (the fork IS the measurement). Gate:
#       <= **1.5x**, from the MEDIANS of NR >= 15 INTERLEAVED runs;
#   (d) PUBLISHED, NOT GATED — `s.count` against the shell equivalent
#       `sed … | wc -l`. They answer the same question by different means: `wc`
#       counts in one more process at memory speed, the `count` sink reads every
#       record into bash. The gap is the price of having the records in this
#       shell, and it is a per-RECORD price — derived here by DIFFERENCE, from the
#       same sink over the 10 000-line file and over the one-line file;
#   (e) ZERO FORKS — $BASHPID around every TSed and TUtil member, around a
#       REFUSED build (a deny-list hit), a refused in-place sink and a refused
#       `edit` (the rc 2 paths fork nothing either), around `edit`, and inside an
#       `each` callback and a `.Add`.
#
# Timing primitive: TStopwatch.getTimeStamp (kcl/tstopwatch) — one tested,
# locale-safe us clock shared by every kcl bench; RESULT-only, no fork.
# **`date +%s%N` must NOT be used here**: on msys each call is its own process
# and costs ~20 ms — more than half of the very `sed` run being measured, and it
# would be paid twice per sample (tfind PLAN §8 finding 17).
# Deterministic: fixed sizes, no $RANDOM, one generated corpus everywhere.
#
# WHY THE CORPUS SIZE DOES NOT MOVE THE RATIO OF (c). On this platform a whole
# `sed` run — the msys `fork`+`exec` of a sed binary, plus the edit — costs
# tens of milliseconds, while the wrapper's entire fixed delta — section (b) — is
# ~5 ms. The ratio of (c) is therefore roughly (sed + 5) / sed: it can only FALL
# as the file grows. Ten thousand lines do not make the wrapper cheaper, they
# make the denominator bigger — which is why the big file and the ONE-line file
# land within a few points of each other below, and why the one-line row (where
# the fork is the whole measurement) is the pessimistic one.
#
# MEDIANS, AND WHY THEY ARE NOT NEGOTIABLE. Every number in (c) and (d) is ONE
# PROCESS START plus an edit, and on this platform a process start occasionally
# takes several hundred milliseconds for reasons outside this repo (a scanner, a
# page-fault storm). One such outlier in 21 runs moves a MEAN by more than the
# whole head-room of the gate, and it lands on a different side from run to run:
# while tfind was planned, the WORST SINGLE PAIRING read **1.64x** on code whose
# interleaved medians are 1.13-1.16x, and inside tfind's own published samples it
# read 7.8x-10.6x. A single pairing, or a non-interleaved loop, can therefore
# fail a 1.5x gate on code that is fine. So the two sides are timed INTERLEAVED,
# one of each per iteration, every run is recorded separately, and the published
# ratio is computed from the MEDIANS. The MEAN is printed next to each median and
# the worst single pairing under each gate: a gap between median and mean IS the
# outlier telling you the box was not idle.
#
# The corpus is generated into a `mktemp -d` directory and removed by an EXIT
# trap (this is a bench, not a test file: a test file must NOT install a trap of
# its own, it would replace ktests').
#
# The gate printed here is the PLAN §5 P1 number, measured by hand with the
# machine idle. `tests/007_Bench.sh` asserts the same shapes with a ceiling of
# 10x: ktests runs test files threaded (8 workers) and the two sides do NOT
# inflate together under that load — `sed` is its own process, while the
# wrapper's share is bash work in the contended shell.
#
# Run: bash bench.sh [NL] [NR] [ND]
#      (defaults: NL=10000 lines in the big file, NR=21 interleaved runs,
#       ND=300 calls per per-call measurement)
# Runs clean under `bash -eu`; always exits 0 (a failed gate is printed, not
# raised — tests/007_Bench.sh is the assertion).

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/tsed.sh"
source "$DIR/../tstopwatch/tstopwatch.sh"

NL=${1:-10000}      # lines in the big file
NR=${2:-21}         # interleaved repetitions per gated shape (odd, >= 15)
ND=${3:-300}        # calls per per-call measurement

# ---------------------------------------------------------------------------
# helpers (the tgrep/thead/ttail/tfind bench shape, so every kcl bench table
# reads the same)
# ---------------------------------------------------------------------------

report() {  # label total_us iters unit -> us/iter with tenths + total ms
    local x10=$(( $2 * 10 / $3 ))
    printf '  %-50s %7d.%d us/%s  (total %d ms)\n' "$1" $(( x10/10 )) $(( x10%10 )) "$4" $(( $2/1000 ))
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
    printf '  %-50s median %6d.%02d ms  mean %6d.%02d ms  (%d runs)\n' \
        "$1" $(( m100/100 )) $(( m100%100 )) $(( a100/100 )) $(( a100%100 )) "$4"
}

ratio() {   # label value_us base_us base_label -> the ratio, no verdict
    local r100=$(( $2 * 100 / $3 ))
    printf '  %-50s ratio %d.%02dx of %s\n' \
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
    printf '  %-50s ratio %d.%02dx  (gate %d.%dx) %s\n' \
        "$1" $(( r100/100 )) $(( r100%100 )) $(( $4/10 )) $(( $4%10 )) "$verdict"
}

# --- the GNU banner gate ----------------------------------------------------
# D4 pins the DIALECT (GNU sed 4.9 — 5.2.37 resolves Git for Windows' sed.exe,
# 5.3.9 msys64's), not a binary. Every number below is about that tool; on
# anything else they are not comparable, so say so loudly instead of publishing
# a meaningless table.
SED_BANNER="$(sed --version 2>/dev/null | sed -n 1p || true)"
case "$SED_BANNER" in
    "sed (GNU sed) "*) ;;
    *) echo "tsed bench: SKIPPED — \`sed\` is not GNU sed: '$SED_BANNER'"; exit 0 ;;
esac
SED_BIN="$(command -v sed 2>/dev/null || printf '(none)')"

# --- the corpus -------------------------------------------------------------
# Two files, both under one `mktemp -d`: BIG holds NL lines `aNNNNN xyz` (every
# line has an `a`, so `s/a/A/` really substitutes on every record), ONE holds a
# single such line. The lines are built into an array and written by ONE
# `printf` — no fork per line, and NL stays overridable.
BD="$(mktemp -d)"
trap 'rm -rf "$BD"' EXIT
BIG="$BD/big.txt"
ONE="$BD/one.txt"
declare -a _lines=()
for (( _i = 1; _i <= NL; _i++ )); do
    _lines+=( "$_i" )
done
printf 'a%05d xyz\n' "${_lines[@]}" > "$BIG"
printf 'a%05d xyz\n' 1 > "$ONE"
unset -v _lines

echo "tsed micro-benchmark  (bash ${BASH_VERSION}, ${SED_BANNER} at ${SED_BIN})"
echo "corpus: big.txt = $NL lines, one.txt = 1 line (every line has an \`a\`)"
echo "        NR=$NR interleaved runs, ND=$ND calls"
echo

# ===========================================================================
# (a) the typed option set -> argv
# ===========================================================================
echo "(a) the argv model — typed options into a command line, running NOTHING:"
TSed.new BF 's/a/A/' "$BIG"
BF.addExpr '/^$/d'
BF.extended = 1
BF.addArg --posix
declare -a BW=()

TStopwatch.getTimeStamp; t0=$RESULT
for (( i = 0; i < ND; i++ )); do BF.buildArgv; done
TStopwatch.getTimeStamp; t1=$RESULT
b_build=$(( t1 - t0 )); (( b_build > 0 )) || b_build=1
report "buildArgv (the override, one extra scanned)" "$b_build" "$ND" "call"

TStopwatch.getTimeStamp; t0=$RESULT
for (( i = 0; i < ND; i++ )); do BF.argv BW; done
n_argv="$RESULT"
TStopwatch.getTimeStamp; t1=$RESULT
b_argv=$(( t1 - t0 )); (( b_argv > 0 )) || b_argv=1
report "argv NAME (buildArgv + validate + copy)" "$b_argv" "$ND" "call"
printf '  %-50s %s words: %s\n' "argv NAME copied" "$n_argv" "${BW[*]}"

# sed is never executed above; prove it by pointing `cmd` at a function that
# would count its own invocations, and building 2 x ND more times.
BENCH_RAN=0
bench_counted() { BENCH_RAN=$(( BENCH_RAN + 1 )); return 0; }
BF.cmd = bench_counted
pid_a="$BASHPID"
for (( i = 0; i < ND; i++ )); do BF.buildArgv; done
for (( i = 0; i < ND; i++ )); do BF.argv BW; done
BF.cmd = sed
if (( BENCH_RAN == 0 )) && [[ "$BASHPID" == "$pid_a" && "${BW[0]}" == "bench_counted" ]]; then
    echo "  RUNS NOTHING: with cmd pointed at a counting function, $(( ND * 2 )) builds invoked it 0 times"
    echo "  FORK-FREE:    BASHPID $pid_a unchanged across all $(( ND * 4 )) builds"
else
    echo "  VIOLATION: cmd invoked $BENCH_RAN times, BASHPID $pid_a -> $BASHPID, argv[0]='${BW[0]}'"
fi

# The rc 2 path is a build too. The refusal timed here is a deny-list hit (owner
# Q6) at the END of three extras, so the whole scan — two passing words and the
# getopt-style bundle split of the third — is inside the number.
TSed.new BR 's/a/A/' "$BIG"
BR.addArg -u --posix -ni
TStopwatch.getTimeStamp; t0=$RESULT
for (( i = 0; i < ND; i++ )); do BR.buildArgv >/dev/null 2>&1 || :; done
TStopwatch.getTimeStamp; t1=$RESULT
b_ref=$(( t1 - t0 )); (( b_ref > 0 )) || b_ref=1
report "buildArgv REFUSED (rc 2, -ni after -u --posix)" "$b_ref" "$ND" "call"
BR.delete
BF.delete

# ===========================================================================
# (b) the wrapper's fixed delta: what TSed.edit does around the fork
# ===========================================================================
echo
echo "(b) the wrapper's FIXED delta — exactly what \`TSed.edit\` does around the"
echo "    one fork (a fresh instance name per call, as edit uses):"
declare -a BV=()
TStopwatch.getTimeStamp; t0=$RESULT
for (( i = 0; i < ND; i++ )); do
    TSed.new "BC_$i" '' "$ONE"
    "BC_$i".addExpr 's/a/A/'
    "BC_$i".sandbox = 1
    "BC_$i".argv BV
    "BC_$i".delete
done
TStopwatch.getTimeStamp; t1=$RESULT
b_ctor=$(( t1 - t0 )); (( b_ctor > 0 )) || b_ctor=1
report "new+addExpr+sandbox+argv+delete (edit delta)" "$b_ctor" "$ND" "call"
per_ctor=$(( b_ctor / ND ))
echo "  this is the WHOLE difference between \`TSed.edit\` and the bare tool below;"
echo "  the constructor assigns ELEVEN properties and declares two arrays (tfind:"
echo "  nine and one), the build scans the extras against the deny-list; it is paid"
echo "  once per CALL, never per record, and it does not grow with the corpus —"
echo "  the process start it is measured against does not either."

# ===========================================================================
# (c) the gate: TSed.edit vs a bare `sed --sandbox -e … -- FILE`
# ===========================================================================
echo
echo "(c) TSed.edit 's/a/A/' FILE vs a bare \`sed --sandbox -e 's/a/A/' -- FILE\` (INTERLEAVED, medians):"

# gate_shape FILE LABEL — time the two shapes interleaved and gate the medians
# at 1.5x.
gate_shape() {
    local __file="$1" __label="$2"
    local -a __t_bare=() __t_ed=()
    local __i __a0 __a1 __s_bare=0 __s_ed=0

    # warm the file cache and every code path once, so neither side pays for
    # the first read of the corpus or the first bind of a member wrapper.
    sed --sandbox -e 's/a/A/' -- "$__file" >/dev/null 2>&1 || :
    TSed.edit 's/a/A/' "$__file" >/dev/null 2>&1 || :

    for (( __i = 0; __i < NR; __i++ )); do
        TStopwatch.getTimeStamp; __a0=$RESULT
        sed --sandbox -e 's/a/A/' -- "$__file" >/dev/null || :
        TStopwatch.getTimeStamp; __a1=$RESULT
        __t_bare+=( $(( __a1 - __a0 )) ); __s_bare=$(( __s_bare + __a1 - __a0 ))

        TStopwatch.getTimeStamp; __a0=$RESULT
        TSed.edit 's/a/A/' "$__file" >/dev/null || :
        TStopwatch.getTimeStamp; __a1=$RESULT
        __t_ed+=( $(( __a1 - __a0 )) ); __s_ed=$(( __s_ed + __a1 - __a0 ))
    done
    median __t_bare; local __m_bare="$MED"; (( __m_bare > 0 )) || __m_bare=1
    median __t_ed;   local __m_ed="$MED"
    report_med "bare \`sed --sandbox -e\` $__label (baseline)" "$__m_bare" "$__s_bare" "$NR"
    report_med "TSed.edit $__label" "$__m_ed" "$__s_ed" "$NR"
    gate_ratio "  gate: edit vs bare sed, $__label" "$__m_ed" "$__m_bare" 15
    printf '  delta %d us per call; section (b) measured the wrapper at %d us\n' \
        $(( __m_ed - __m_bare )) "$per_ctor"
    # The worst SINGLE pairing of this very sample, for comparison with the
    # median above: this is the number a one-shot measurement would have
    # published, and it is why the protocol is what it is.
    local __worst=0 __r100 __j __den
    for (( __j = 0; __j < NR; __j++ )); do
        __den="${__t_bare[__j]}"
        if (( __den <= 0 )); then
            __den=1
        fi
        __r100=$(( __t_ed[__j] * 100 / __den ))
        if (( __r100 > __worst )); then
            __worst=$__r100
        fi
    done
    printf '  worst SINGLE pairing in this sample: %d.%02dx — one sample is not a measurement\n' \
        $(( __worst/100 )) $(( __worst%100 ))
    echo
}

gate_shape "$BIG" "big.txt, $NL lines"
gate_shape "$ONE" "one.txt, 1 line"

# ===========================================================================
# (d) counting: the `count` sink vs `sed … | wc -l`
# ===========================================================================
echo "(d) counting — the \`count\` sink vs \`sed --sandbox -e … -- FILE | wc -l\` (published, NOT gated):"
TSed.new BQ 's/a/A/' "$BIG"
TSed.new BQ1 's/a/A/' "$ONE"     # the SAME sink over ONE record: the fixed half
declare -a T_WC=() T_CNT=() T_CNT1=()
b_wc=0; b_cnt=0; b_cnt1=0
n_wc=''; n_cnt=''

# Warm both shapes, and take the record counts HERE, once. A `$( )` inside the
# timed loop would add a fork to the baseline and dilute the very comparison.
n_wc="$( sed --sandbox -e 's/a/A/' -- "$BIG" | wc -l )"
n_wc="${n_wc//[[:space:]]/}"
BQ.count >/dev/null 2>&1 || :
BQ1.count >/dev/null 2>&1 || :

for (( i = 0; i < NR; i++ )); do
    TStopwatch.getTimeStamp; t0=$RESULT
    sed --sandbox -e 's/a/A/' -- "$BIG" | wc -l >/dev/null || :
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
report_med "\`sed … | wc -l\` (baseline)" "$m_wc" "$b_wc" "$NR"
report_med "s.count ($NL records)" "$m_cnt" "$b_cnt" "$NR"
report_med "the same sink over ONE record (the fixed half)" "$m_cnt1" "$b_cnt1" "$NR"
ratio "  published: s.count vs the wc equivalent" "$m_cnt" "$m_wc" "the shell equivalent"
printf '  both answered %s / %s records\n' "$n_wc" "$n_cnt"
# The sink's cost splits cleanly: a fixed part (one sed, one TPipe setup) and a
# per-record part (one bash `read` each). Measured, not assumed — the ONE-record
# row above IS the fixed part, so the difference over (NL - 1) records is the
# marginal cost of a record.
per_rec=$(( (m_cnt - m_cnt1) / (NL > 1 ? NL - 1 : 1) ))
printf '  marginal cost of ONE record read into bash: ~%d us (%d-record row minus\n' \
    "$per_rec" "$NL"
printf '  the 1-record row, over %d records)\n' $(( NL > 1 ? NL - 1 : 1 ))
if (( m_cnt > m_wc )); then
    printf '  the sink is the SLOWER of the two: that per-record price is what having\n'
    printf '  the records in THIS shell costs, and when all you want is the number,\n'
    printf '  the pipeline is the right answer.\n'
else
    printf '  at this corpus the SINK IS FASTER — the pipeline pays one more process\n'
    printf '  start, and the corpus is small enough for that to dominate.\n'
fi
BQ1.delete
BQ.delete

# ===========================================================================
# (e) zero forks
# ===========================================================================
echo
echo "(e) zero-fork check (\$BASHPID around every TSed/TUtil member, three REFUSED"
echo "    paths, \`edit\`, and inside the callback and \`.Add\`):"
FORKPIDS=()
fork_cb() { FORKPIDS+=( "$BASHPID" ); return 0; }
class TBenchListTS
    public
        constructor Create
        proc        Add
end
TBenchListTS.Create() { return 0; }
TBenchListTS.Add()    { FORKPIDS+=( "$BASHPID" ); return 0; }
build TBenchListTS
TBenchListTS.new FL

p0=$BASHPID
forked=0
nzf=0
# zf COMMAND... — run one member call (output discarded, rc ignored), then check
# that this shell's PID did not change. A function call and a redirection on it
# do not fork, so the helper itself adds none.
zf() {
    "$@" >/dev/null 2>&1 || :
    nzf=$(( nzf + 1 ))
    if [[ "$BASHPID" != "$p0" ]]; then
        forked=1
    fi
}

declare -a FARR=() FW=()
TSed.new FF 's/a/A/' "$ONE"
zf FF.expr = 's/a/A/'
zf FF.scriptFile = ''
zf FF.extended = 0
zf FF.quiet = 0
zf FF.separate = 0
zf FF.nullData = 0
zf FF.binary = 0
zf FF.sandbox = 1
zf FF.inPlace = 0
zf FF.backupSuffix = ''
zf FF.crlf = 0
zf FF.subshellOk = 0
zf FF.paths "$ONE"
zf FF.addExpr 'p'
zf FF.clearExprs
zf FF.addArg --posix
zf FF.clearArgs
zf FF.buildArgv
zf FF.argv FW
zf FF.mapRc 1
zf FF.lastRc
zf FF.each    fork_cb
zf FF.toList  FL
zf FF.toArray FARR
zf FF.count
zf FF.first
zf FF.run
zf TSed.edit 's/a/A/' "$ONE"
# the rc 2 paths: a deny-list hit, an in-place sink and a path-less edit fork
# nothing either
TSed.new FR 's/a/A/' "$ONE"
FR.addArg -ni
zf FR.count
FR.clearArgs
FR.inPlace = 1
zf FR.count
zf TSed.edit 's/a/A/'
FR.delete
for pid in "${FORKPIDS[@]}"; do
    [[ "$pid" == "$p0" ]] || forked=1
done
if (( forked == 0 && nzf == 31 )) && (( ${#FORKPIDS[@]} == 2 )); then
    echo "  BASHPID $p0 unchanged across all $nzf member calls — twenty-seven members"
    echo "  and \`edit\`, plus the three rc 2 paths (a deny-list hit, an in-place"
    echo "  sink, a path-less \`edit\`) — and both callback/.Add invocations: the"
    echo "  only fork per call is sed itself, and a refused call does not even pay that"
else
    echo "  ZERO-FORK VIOLATION: p0=$p0 forked=$forked calls=$nzf callback pids=(${FORKPIDS[*]})"
fi
FL.delete; FF.delete

# --- summary -----------------------------------------------------------------
echo
if (( GATES_FAILED == 0 )); then
    echo "gates: $GATES_TOTAL/$GATES_TOTAL PASS (TSed.edit <= 1.5x a bare \`sed --sandbox -e\`, medians of $NR interleaved runs)"
else
    echo "gates: $GATES_FAILED of $GATES_TOTAL FAILED — see the lines above"
fi

exit 0
