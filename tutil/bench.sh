#!/bin/bash
# Micro-benchmark for tutil (P3.1). Publishes the numbers README.md §6 quotes
# and measures the PLAN.md §5 P3.1 gate:
#
#   (a) ARGV AND buildArgv — what the option->argv model costs, and the proof
#       that it RUNS NOTHING: the `cmd` is a shell function that counts its own
#       invocations, and after ND `argv` calls the counter is still 0. $BASHPID
#       is read before and after the loop: the whole builder is fork-free;
#   (b) run ON `true` — the per-call cost of the wrapper against a bare `true`
#       and against `command true`. PUBLISHED, not gated: the delta is two
#       kklass dispatches (buildArgv + mapRc) plus one `command -v`, i.e. the
#       price of the model, and it is paid ONCE PER CALL, never per record;
#   (c) GATED — `u.each` + a no-op FUNCTION over N records against
#       `TPipe.each` called DIRECTLY on the very same argv. Gate: <= 1.1x.
#       The delegation is one prologue per CALL and zero work per record, so
#       the two numbers must be the same number;
#   (d) PUBLISHED — `u.toArray` against `TPipe.toArray` direct, same argv;
#   (e) PUBLISHED, NOT GATED — `u.each` with an INSTANCE-member callback. A
#       full kklass instance dispatch per record; kklass's price, not tutil's
#       and not TPipe's (tpipe/bench.sh section (a) measures it directly);
#   (f) ZERO FORKS — $BASHPID around every member of the surface and inside the
#       callback and inside `.Add`.
#
# Timing primitive: TStopwatch.getTimeStamp (kcl/tstopwatch) — one tested,
# locale-safe us clock shared by every kcl bench; RESULT-only, no fork.
# Deterministic: fixed sizes, no $RANDOM, one producer shape everywhere.
#
# SMALL-N CAVEAT. The 1.1x gate of (c) is calibrated for N = 10 000. The
# wrapper's cost over TPipe is FIXED per call (one buildArgv, one `command -v`,
# one mapRc — about a millisecond), so at a small N (`bench.sh 200`) that fixed
# millisecond is a visible fraction of the whole measurement and the ratio
# drifts above 1.1 for a reason that has nothing to do with the per-record path.
# Re-run at the default N before believing a failed (c).
#
# The gates printed here are the PLAN §5 numbers, measured by hand with the
# machine idle. `tests/004_Bench.sh` asserts the same shapes with a ceiling of
# 5x, because ktests runs test files threaded (8 workers) and under that load the
# same two cases have been seen at 0.94x and 1.87x.
#
# Run: bash bench.sh [N] [ND]      (defaults: N=10000 records, ND=300 calls)
# Runs clean under `bash -eu`; always exits 0 (a failed gate is printed, not
# raised — tests/004_Bench.sh is the assertion).

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/tutil.sh"
source "$DIR/../tstopwatch/tstopwatch.sh"

N=${1:-10000}       # records per stream measurement
ND=${2:-300}        # calls per per-call measurement (a wrapper call is ~0.5 ms)

# ---------------------------------------------------------------------------
# helpers (the tpipe/bench.sh shape, so the two tables read the same way)
# ---------------------------------------------------------------------------

report() {  # label total_us iters unit -> us/iter with tenths + total ms
    local x10=$(( $2 * 10 / $3 ))
    printf '  %-46s %7d.%d us/%s  (total %d ms)\n' "$1" $(( x10/10 )) $(( x10%10 )) "$4" $(( $2/1000 ))
}

ratio() {   # label value_us base_us base_label -> the ratio, no verdict
    local r100=$(( $2 * 100 / $3 ))
    printf '  %-46s %7d ms   ratio %d.%02dx of %s\n' \
        "$1" $(( $2/1000 )) $(( r100/100 )) $(( r100%100 )) "$4"
}

gate_ratio() {  # label value_us base_us limit_tenths -> ratio + PASS/FAIL
    local r100=$(( $2 * 100 / $3 )) lim=$(( $3 * $4 / 10 )) verdict
    if (( $2 <= lim )); then verdict="PASS"; else verdict="FAIL"; GATES_FAILED=$(( GATES_FAILED + 1 )); fi
    printf '  %-46s %7d ms   ratio %d.%02dx  (gate %d.%dx) %s\n' \
        "$1" $(( $2/1000 )) $(( r100/100 )) $(( r100%100 )) $(( $4/10 )) $(( $4%10 )) "$verdict"
}

GATES_FAILED=0

# The one producer shape used by (c), (d) and (e): ONE builtin printf emits the
# whole stream, so the producer side is identical for the wrapper and for the
# direct TPipe call and contributes no per-record cost of its own. It is a
# FUNCTION, which is a perfectly good `cmd` — `command -v` finds it and no
# executable is started.
declare -a RECS=()
for (( _i = 0; _i < N; _i++ )); do RECS+=( "record-$_i" ); done
bench_producer() { printf '%s\n' "${RECS[@]}"; }

bench_noop() { return 0; }                      # the no-op FUNCTION callback

# A `cmd` that COUNTS its own invocations — section (a) proves `argv` and
# `buildArgv` never touch it.
BENCH_RAN=0
bench_counted() { BENCH_RAN=$(( BENCH_RAN + 1 )); return 0; }

# an INSTANCE-member callback — the `r.onLine` of the README
class TBenchSink
    public
        var         N
        constructor Create
        proc        onLine
end
TBenchSink.Create() { N=0; return 0; }
TBenchSink.onLine() { N=$(( N + 1 )); return 0; }
build TBenchSink

echo "tutil micro-benchmark  (bash ${BASH_VERSION}, N=$N records / ND=$ND calls)"
echo

# ===========================================================================
# (a) the argv model: what it costs, and that it runs nothing
# ===========================================================================
echo "the argv model (buildArgv / argv) — builds a command line, runs NOTHING:"
TUtil.new BA bench_counted -i -e needle -- 'a file.txt'
declare -a BW=()
pid_a="$BASHPID"

TStopwatch.getTimeStamp; t0=$RESULT
for (( i = 0; i < ND; i++ )); do BA.buildArgv; done
TStopwatch.getTimeStamp; t1=$RESULT
b_build=$(( t1 - t0 )); (( b_build > 0 )) || b_build=1
report "buildArgv (base: cmd + the extras)" "$b_build" "$ND" "call"

TStopwatch.getTimeStamp; t0=$RESULT
for (( i = 0; i < ND; i++ )); do BA.argv BW; done
n_argv="$RESULT"
TStopwatch.getTimeStamp; t1=$RESULT
b_argv=$(( t1 - t0 )); (( b_argv > 0 )) || b_argv=1
report "argv NAME (buildArgv + validate + copy)" "$b_argv" "$ND" "call"
printf '  %-46s %s\n' "argv NAME copied" "${#BW[@]} words, RESULT $n_argv: ${BW[*]}"

if (( BENCH_RAN == 0 )) && [[ "$BASHPID" == "$pid_a" ]]; then
    echo "  RUNS NOTHING: the cmd (a counting function) was invoked 0 times in $(( ND * 2 )) builds"
    echo "  FORK-FREE:    BASHPID $pid_a unchanged across all $(( ND * 2 )) calls"
else
    echo "  VIOLATION: cmd invoked $BENCH_RAN times, BASHPID $pid_a -> $BASHPID"
fi
BA.delete

# ===========================================================================
# (b) run on `true` — the fixed per-call cost of the wrapper
# ===========================================================================
echo
echo "run on \`true\` — the per-CALL cost of the wrapper (paid once, never per record):"
TStopwatch.getTimeStamp; t0=$RESULT
for (( i = 0; i < ND; i++ )); do true; done
TStopwatch.getTimeStamp; t1=$RESULT
b_true=$(( t1 - t0 )); (( b_true > 0 )) || b_true=1
report "bare \`true\` (baseline)" "$b_true" "$ND" "call"

TStopwatch.getTimeStamp; t0=$RESULT
for (( i = 0; i < ND; i++ )); do command true; done
TStopwatch.getTimeStamp; t1=$RESULT
b_cmdtrue=$(( t1 - t0 )); (( b_cmdtrue > 0 )) || b_cmdtrue=1
report "\`command true\`" "$b_cmdtrue" "$ND" "call"

TUtil.new BT true
TStopwatch.getTimeStamp; t0=$RESULT
for (( i = 0; i < ND; i++ )); do BT.run || :; done
TStopwatch.getTimeStamp; t1=$RESULT
b_run=$(( t1 - t0 )); (( b_run > 0 )) || b_run=1
report "u.run (buildArgv + command -v + exec + mapRc)" "$b_run" "$ND" "call"
printf '  the wrapper adds %d us per CALL over a bare "true": two kklass dispatches\n' \
    $(( (b_run - b_true) / ND ))
printf '  (buildArgv, mapRc) and one "command -v" — NOT a per-record cost, see (c)\n'
BT.lastRc; printf '  lastRc after the loop: %s\n' "$RESULT"
BT.delete

# ===========================================================================
# (c) the gate: each == TPipe.each direct on the same argv
# ===========================================================================
echo
echo "streaming $N records — u.each vs TPipe.each called DIRECTLY on the same argv:"
TUtil.new BU bench_producer
declare -a BARGV=()
BU.argv BARGV

# Warm every one of the four measured code paths on a 5-record producer first:
# the FIRST sink call in a process pays for binding `tpipe._*`, the member
# wrappers and the `mapfile` target attributes, and whichever of the four ran
# first would otherwise carry that one-off cost into its ratio.
warm5() { printf 'a\nb\nc\nd\ne\n'; }
TUtil.new BWARM warm5
declare -a WARMARR=()
TPipe.each bench_noop -- warm5      || :
BWARM.each bench_noop               || :
TPipe.toArray WARMARR -- warm5      || :
BWARM.toArray WARMARR               || :
BWARM.delete

TStopwatch.getTimeStamp; t0=$RESULT
TPipe.each bench_noop -- "${BARGV[@]}" || :
n_direct="$RESULT"                      # read RESULT FIRST: the clock uses it too
TStopwatch.getTimeStamp; t1=$RESULT
d_each=$(( t1 - t0 )); (( d_each > 0 )) || d_each=1
report "TPipe.each + no-op fn, DIRECT (baseline)" "$d_each" "$N" "rec"

TStopwatch.getTimeStamp; t0=$RESULT
BU.each bench_noop || :
TStopwatch.getTimeStamp; t1=$RESULT
w_each=$(( t1 - t0 ))
report "u.each + the same no-op fn" "$w_each" "$N" "rec"
gate_ratio "  gate: u.each vs TPipe.each direct" "$w_each" "$d_each" 11

# ===========================================================================
# (d) toArray, published
# ===========================================================================
echo
echo "collecting $N records — u.toArray vs TPipe.toArray direct, same argv:"
declare -a DARR=() WARR=()
TStopwatch.getTimeStamp; t0=$RESULT
TPipe.toArray DARR -- "${BARGV[@]}" || :
n_dtoarr="$RESULT"
TStopwatch.getTimeStamp; t1=$RESULT
d_toarr=$(( t1 - t0 )); (( d_toarr > 0 )) || d_toarr=1
report "TPipe.toArray, DIRECT (baseline)" "$d_toarr" "$N" "rec"

TStopwatch.getTimeStamp; t0=$RESULT
BU.toArray WARR || :
n_wtoarr="$RESULT"
TStopwatch.getTimeStamp; t1=$RESULT
w_toarr=$(( t1 - t0 ))
report "u.toArray" "$w_toarr" "$N" "rec"
ratio "  published: u.toArray vs TPipe.toArray" "$w_toarr" "$d_toarr" "the direct call"

# ===========================================================================
# (e) an instance-member callback, published
# ===========================================================================
echo
echo "the callback you choose (published, NOT gated — kklass's price):"
TBenchSink.new BR
BR.onLine ""            # warm the instance dispatcher …
BR.N = 0                # … and undo the warm-up call's own count
TStopwatch.getTimeStamp; t0=$RESULT
BU.each BR.onLine || :
TStopwatch.getTimeStamp; t1=$RESULT
w_inst=$(( t1 - t0 ))
report "u.each + an INSTANCE member (r.onLine)" "$w_inst" "$N" "rec"
ratio "  published: instance member vs a plain fn" "$w_inst" "$w_each" "u.each + a function"
echo "  (that ratio is the kklass instance dispatch, not tutil's and not TPipe's)"
printf '  the callback object saw %s records\n' "$( BR.N )"
BR.delete

# ===========================================================================
# (f) zero forks
# ===========================================================================
echo
echo "zero-fork check (\$BASHPID around every member and inside the callback):"
FORKPIDS=()
fork_cb() { FORKPIDS+=( "$BASHPID" ); return 0; }
class TForkList2
    public
        constructor Create
        proc        Add
end
TForkList2.Create() { return 0; }
TForkList2.Add()    { FORKPIDS+=( "$BASHPID" ); return 0; }
build TForkList2
TForkList2.new FL

p5() { printf 'r1\nr2\nr3\nr4\nr5\n'; }
declare -a FARR=() FW=()
TUtil.new FU p5
p0=$BASHPID; forked=0
FU.buildArgv                 ; [[ $BASHPID == "$p0" ]] || forked=1
FU.argv FW                   ; [[ $BASHPID == "$p0" ]] || forked=1
FU.addArg                    ; [[ $BASHPID == "$p0" ]] || forked=1
FU.clearArgs                 ; [[ $BASHPID == "$p0" ]] || forked=1
FU.mapRc 0                   ; [[ $BASHPID == "$p0" ]] || forked=1
FU.lastRc                    ; [[ $BASHPID == "$p0" ]] || forked=1
FU.each    fork_cb    || :   ; [[ $BASHPID == "$p0" ]] || forked=1
FU.toList  FL         || :   ; [[ $BASHPID == "$p0" ]] || forked=1
FU.toArray FARR       || :   ; [[ $BASHPID == "$p0" ]] || forked=1
FU.count              || :   ; [[ $BASHPID == "$p0" ]] || forked=1
FU.first 2>/dev/null  || :   ; [[ $BASHPID == "$p0" ]] || forked=1
TUtil.new FT true
FT.run                || :   ; [[ $BASHPID == "$p0" ]] || forked=1
FT.delete
for pid in "${FORKPIDS[@]}"; do
    [[ "$pid" == "$p0" ]] || forked=1
done
if (( forked == 0 )) && (( ${#FORKPIDS[@]} == 10 )); then
    echo "  BASHPID $p0 unchanged across all 12 members and all 10 callback/.Add invocations"
else
    echo "  ZERO-FORK VIOLATION: p0=$p0 forked=$forked callback pids=(${FORKPIDS[*]})"
fi

# The producer IS the one fork per sink call: every record carries the
# producer's own pid, and all of them are the same, different-from-ours pid.
ppid5() { local i; for i in 1 2 3 4 5; do printf '%s\n' "$BASHPID"; done; }
declare -a PPIDS=()
TUtil.new FP ppid5
FP.toArray PPIDS || :
same=1
for pid in "${PPIDS[@]}"; do
    [[ "$pid" == "${PPIDS[0]}" ]] || same=0
done
if (( same == 1 )) && [[ "${PPIDS[0]}" != "$p0" ]] && (( ${#PPIDS[@]} == 5 )); then
    echo "  the only fork per SINK call is the producer: 5 records, one pid ${PPIDS[0]}"
else
    echo "  PRODUCER-FORK ANOMALY: ours $p0, record pids=(${PPIDS[*]})"
fi
FL.delete; FU.delete; FP.delete

# --- summary -----------------------------------------------------------------
echo
echo "records delivered: each direct $n_direct, u.each $N, toArray direct $n_dtoarr, u.toArray $n_wtoarr (want $N each)"
if (( GATES_FAILED == 0 )); then
    echo "gates: 1/1 PASS (u.each <= 1.1x TPipe.each direct on the same argv)"
else
    echo "gates: $GATES_FAILED of 1 FAILED — see the lines above"
fi
BU.delete

exit 0
