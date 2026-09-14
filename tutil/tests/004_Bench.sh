#!/bin/bash
# 004_Bench.sh — tutil P3: the PLAN.md §5 P3.1 performance gates, as assertions.
#
# TWO SETS OF NUMBERS, on purpose.
#
#   `../bench.sh`, run BY HAND on an idle machine, measures and prints the real
#   PLAN §5 gate: `u.each` + a no-op FUNCTION over 10 000 records <= **1.1x**
#   `TPipe.each` called DIRECTLY on the very same argv. Measured 2026-09-11:
#   **0.97x** on bash 5.2.37 and **1.00x** on bash 5.3.9, with `u.toArray` at
#   1.05x / 0.95x of `TPipe.toArray` direct. Those are the numbers README.md §6
#   publishes.
#
#   THIS FILE asserts the same shapes with a ceiling of **5x** on both — five
#   times the measured ratios — because ktests runs test files THREADED, 8
#   workers by default: seven other test files are competing for the same cores
#   while these loops run, and a gate set at the measured value would flake for
#   reasons that have nothing to do with this unit. Under that runner the same
#   two cases have been seen at 0.94x and 1.87x, so 5x is not decoration. A
#   ceiling that loose still catches every regression the gate exists for — a
#   fork per record, a subshell per record, an accidental `$( )` in a sink, a
#   `buildArgv` called once per RECORD instead of once per CALL — each of which
#   costs an order of magnitude, not 20%.
#
# N is 2000 here, not bench.sh's 10 000, so the file stays under a few seconds.
# Ratios are measured against a baseline taken in THIS process a few
# milliseconds before the measured call, so a slow machine moves both numbers.
# Both shapes are warmed once before either is timed: the FIRST sink call in a
# process pays for binding the member wrappers and the `mapfile` target
# attributes, and whichever ran first would otherwise carry that one-off cost.
#
# Sections:
#   A  the two delegation gates (each, toArray) against TPipe called directly
#   B  the argv model: `buildArgv` and `argv` RUN NOTHING and fork nothing
#   C  zero forks, for every member of the surface — the callback, `.Add` and
#      the `cmd` that `run` executes all report THIS process's $BASHPID, and the
#      only extra pid in a sink call is the one producer
#
# Timing primitive: TStopwatch.getTimeStamp — the shared fork-free us clock.
# Every case sets its own stdin explicitly; this file installs no EXIT trap of
# its own (it would replace ktests' trap and swallow the `__COUNTS__` line).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

TU_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$TU_DIR/tutil.sh"
source "$TU_DIR/../tstopwatch/tstopwatch.sh"

TEST_NAME="$(basename "$0" .sh)"
kt_test_init "$TEST_NAME" "$SCRIPT_DIR" "$@"

kt_test_section "004: the PLAN §5 P3.1 performance gates (P3)"

N=2000

# One builtin printf emits the whole stream, so the producer side is identical
# for the wrapper and for the direct TPipe call and adds no per-record cost of
# its own. It is a FUNCTION, which is a perfectly good `cmd`.
declare -a RECS=()
for (( i = 0; i < N; i++ )); do RECS+=( "record-$i" ); done
bench_producer() { printf '%s\n' "${RECS[@]}"; }
bench_noop() { return 0; }

warm5() { printf 'a\nb\nc\nd\ne\n'; }

# ===========================================================================
kt_test_section "A. the delegation gates — a sink is ONE TPipe call"
# ===========================================================================

TUtil.new BU bench_producer
declare -a BARGV=()
BU.argv BARGV

# warm all four measured paths on a 5-record producer
TUtil.new BWARM warm5
declare -a WARMARR=()
TPipe.each bench_noop -- warm5   >/dev/null 2>&1 || :
BWARM.each bench_noop            >/dev/null 2>&1 || :
TPipe.toArray WARMARR -- warm5   >/dev/null 2>&1 || :
BWARM.toArray WARMARR            >/dev/null 2>&1 || :
BWARM.delete

kt_test_start "u.each costs at most 5x TPipe.each on the same argv (PLAN gate 1.1x)"
TStopwatch.getTimeStamp; t0=$RESULT
TPipe.each bench_noop -- "${BARGV[@]}"; drc=$?
n_direct="$RESULT"
TStopwatch.getTimeStamp; t1=$RESULT
d_each=$(( t1 - t0 )); (( d_each > 0 )) || d_each=1

TStopwatch.getTimeStamp; t0=$RESULT
BU.each bench_noop; wrc=$?
TStopwatch.getTimeStamp; t1=$RESULT
w_each=$(( t1 - t0 ))
lim=$(( d_each * 5 ))
r100=$(( w_each * 100 / d_each ))
if [[ "$n_direct" == "$N" && $drc -eq 0 && $wrc -eq 0 ]] && (( w_each <= lim )); then
    kt_test_pass "TPipe direct ${d_each}us, u.each ${w_each}us — ${r100}% of it (ceiling ${lim}us), $N records"
else
    kt_test_fail "direct RESULT='$n_direct' rc=$drc; u.each rc=$wrc; direct=${d_each}us each=${w_each}us (${r100}%) ceiling=${lim}us"
fi

kt_test_start "u.toArray costs at most 5x TPipe.toArray on the same argv (measured 1.05x)"
declare -a DARR=() WARR=()
TStopwatch.getTimeStamp; t0=$RESULT
TPipe.toArray DARR -- "${BARGV[@]}"; drc=$?
n_dtoarr="$RESULT"
TStopwatch.getTimeStamp; t1=$RESULT
d_toarr=$(( t1 - t0 )); (( d_toarr > 0 )) || d_toarr=1

TStopwatch.getTimeStamp; t0=$RESULT
BU.toArray WARR; wrc=$?
n_wtoarr="$RESULT"
TStopwatch.getTimeStamp; t1=$RESULT
w_toarr=$(( t1 - t0 ))
lim=$(( d_toarr * 5 ))
r100=$(( w_toarr * 100 / d_toarr ))
if [[ "$n_dtoarr" == "$N" && "$n_wtoarr" == "$N" && $drc -eq 0 && $wrc -eq 0 \
      && "${#WARR[@]}" == "$N" && "${WARR[0]}" == "${DARR[0]}" \
      && "${WARR[$(( N - 1 ))]}" == "${DARR[$(( N - 1 ))]}" ]] && (( w_toarr <= lim )); then
    kt_test_pass "TPipe direct ${d_toarr}us, u.toArray ${w_toarr}us — ${r100}% of it (ceiling ${lim}us), $N records"
else
    kt_test_fail "direct='$n_dtoarr' rc=$drc; wrapper='$n_wtoarr' rc=$wrc n=${#WARR[@]}; direct=${d_toarr}us wrapper=${w_toarr}us (${r100}%) ceiling=${lim}us"
fi

BU.delete

# ===========================================================================
kt_test_section "B. the argv model runs NOTHING and forks nothing"
# ===========================================================================

ND=100
BENCH_RAN=0
BENCH_CMD_PID=''
bench_counted() { BENCH_RAN=$(( BENCH_RAN + 1 )); BENCH_CMD_PID="$BASHPID"; return 0; }

kt_test_start "$(( ND * 2 )) buildArgv/argv calls never invoke the cmd and never fork"
TUtil.new BA bench_counted -i -e needle -- 'a file.txt'
declare -a BW=()
p0="$BASHPID"
for (( i = 0; i < ND; i++ )); do BA.buildArgv; done
n_build="$RESULT"
for (( i = 0; i < ND; i++ )); do BA.argv BW; done
n_argv="$RESULT"
want="bench_counted -i -e needle -- a file.txt"
if (( BENCH_RAN == 0 )) && [[ "$BASHPID" == "$p0" && "$n_build" == "6" && "$n_argv" == "6" \
      && "${BW[*]}" == "$want" && "${#BW[@]}" == "6" ]]; then
    kt_test_pass "cmd invoked 0 times in $(( ND * 2 )) builds, BASHPID $p0 unchanged, argv = ($want)"
else
    kt_test_fail "ran=$BENCH_RAN pid $p0 -> $BASHPID buildArgv='$n_build' argv='$n_argv' words=(${BW[*]})"
fi

kt_test_start "the argv build stays constant-cost: 100 rebuilds do not accumulate words"
declare -a BW2=()
BA.argv BW2
if [[ "${#BW2[@]}" == "6" && "${BW2[*]}" == "$want" && "$RESULT" == "6" ]]; then
    kt_test_pass "still 6 words after ${ND} rebuilds: (${BW2[*]})"
else
    kt_test_fail "n=${#BW2[@]} RESULT='$RESULT' words=(${BW2[*]})"
fi
BA.delete

# ===========================================================================
kt_test_section "C. zero forks — every member, the callback, .Add and the cmd"
# ===========================================================================

p5() { printf 'r1\nr2\nr3\nr4\nr5\n'; }
# one line per record carrying the PRODUCER's own pid
ppid5() { local i; for i in 1 2 3 4 5; do printf '%s\n' "$BASHPID"; done; }

CBPIDS=()
pid_cb() { CBPIDS+=( "$BASHPID" ); return 0; }

ADDPIDS=()
class TFork004
    public
        constructor Create
        proc        Add
end
TFork004.Create() { return 0; }
TFork004.Add()    { ADDPIDS+=( "$BASHPID" ); return 0; }
build TFork004
TFork004.new F4

TUtil.new FU p5

kt_test_start "each: the callback runs in THIS process for every record"
p0=$BASHPID
CBPIDS=()
FU.each pid_cb; rc=$?
ok=1
for pid in "${CBPIDS[@]}"; do
    [[ "$pid" == "$p0" ]] || ok=0
done
if [[ $rc -eq 0 && "$BASHPID" == "$p0" ]] && (( ok == 1 && ${#CBPIDS[@]} == 5 )); then
    kt_test_pass "5 records, all in pid $p0"
else
    kt_test_fail "rc=$rc ours=$p0 now=$BASHPID pids=(${CBPIDS[*]})"
fi

kt_test_start "toList: \`.Add\` runs in THIS process for every record"
p0=$BASHPID
ADDPIDS=()
FU.toList F4; rc=$?
ok=1
for pid in "${ADDPIDS[@]}"; do
    [[ "$pid" == "$p0" ]] || ok=0
done
if [[ "$RESULT" == "5" && $rc -eq 0 && "$BASHPID" == "$p0" ]] && (( ok == 1 && ${#ADDPIDS[@]} == 5 )); then
    kt_test_pass "5 records offered, all in pid $p0"
else
    kt_test_fail "RESULT='$RESULT' rc=$rc ours=$p0 now=$BASHPID pids=(${ADDPIDS[*]})"
fi

kt_test_start "toArray / count / first: the ONLY fork per call is the producer"
p0=$BASHPID
declare -a PPIDS=()
TUtil.new FP ppid5
FP.toArray PPIDS; rc=$?
same=1
for pid in "${PPIDS[@]}"; do
    [[ "$pid" == "${PPIDS[0]}" ]] || same=0
done
prod_arr="${PPIDS[0]:-}"
FP.count; rc2=$?; n_count="$RESULT"
FP.first 2>/dev/null; rc3=$?; prod_first="$RESULT"
if [[ "$BASHPID" == "$p0" && $rc -eq 0 && $rc2 -eq 0 && $rc3 -eq 0 && "$n_count" == "5" ]] \
   && (( same == 1 && ${#PPIDS[@]} == 5 )) \
   && [[ -n "$prod_arr" && "$prod_arr" != "$p0" && "$prod_first" != "$p0" ]]; then
    kt_test_pass "5 records, one producer pid $prod_arr (ours $p0); count 5; first saw pid $prod_first"
else
    kt_test_fail "ours=$p0 now=$BASHPID rc=$rc/$rc2/$rc3 count='$n_count' first='$prod_first' pids=(${PPIDS[*]})"
fi
FP.delete

kt_test_start "run executes the cmd in THIS process, and the six non-running members fork nothing"
p0=$BASHPID
BENCH_RAN=0
BENCH_CMD_PID=''
TUtil.new FR bench_counted
declare -a FW=()
ok=1
FR.buildArgv ; [[ "$BASHPID" == "$p0" ]] || ok=0
FR.argv FW   ; [[ "$BASHPID" == "$p0" ]] || ok=0
FR.addArg    ; [[ "$BASHPID" == "$p0" ]] || ok=0
FR.clearArgs ; [[ "$BASHPID" == "$p0" ]] || ok=0
FR.mapRc 0   ; [[ "$BASHPID" == "$p0" ]] || ok=0
FR.lastRc    ; [[ "$BASHPID" == "$p0" ]] || ok=0
FR.run; rc=$?
FR.lastRc; lrc="$RESULT"
if (( ok == 1 && BENCH_RAN == 1 )) && [[ "$BENCH_CMD_PID" == "$p0" && "$BASHPID" == "$p0" \
      && $rc -eq 0 && "$lrc" == "0" ]]; then
    kt_test_pass "the cmd ran once, in pid $p0; rc 0, lastRc 0; six builder members left BASHPID at $p0"
else
    kt_test_fail "ok=$ok ran=$BENCH_RAN cmdpid='$BENCH_CMD_PID' ours=$p0 now=$BASHPID rc=$rc lastRc='$lrc'"
fi
FR.delete

F4.delete
FU.delete

kt_test_log "004_Bench.sh completed"
