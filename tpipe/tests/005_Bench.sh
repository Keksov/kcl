#!/bin/bash
# 005_Bench.sh — tpipe P2: the PLAN.md §2.6 performance gates, as assertions.
#
# TWO SETS OF NUMBERS, on purpose.
#
#   `../bench.sh`, run BY HAND on an idle machine, measures and prints the real
#   PLAN §2.6 gates: `each` + a no-op FUNCTION <= 2.0x a bare `while IFS= read -r`
#   loop, `toArray` <= 1.5x a bare `mapfile`, `TPipe.first -- yes` <= 250 ms.
#   Those are the numbers README.md §6 publishes.
#
#   THIS FILE asserts the same three shapes with ceilings 3x looser — 6.0x,
#   4.5x and 750 ms — because ktests runs test files THREADED, 8 workers by
#   default (PLAN §4): seven other test files are competing for the same cores
#   while these loops run, and a gate set at the measured value would flake for
#   reasons that have nothing to do with tpipe. A 3x-loose ceiling still catches
#   every regression the gates exist for — a fork per record, a subshell per
#   record, an accidental `$( )` in the reader, a lost `kill -TERM` on the stop
#   path — each of which costs an order of magnitude, not 20%.
#
# N is 2000 here, not bench.sh's 10 000, so the file stays under a few seconds.
# Ratios are measured against a baseline taken in THIS process, a few
# milliseconds before the measured call, so a slow machine moves both numbers.
#
# Sections:
#   A  the two streaming gates (each vs a bare read loop, toArray vs mapfile)
#   B  the latency gate (first on an infinite producer) — measured inside a
#      CHILD under `timeout`, so a regression that hangs `wait` FAILS the case
#      instead of hanging the suite, and bash's own startup is not counted
#   C  zero forks per record, for every sink
#
# Timing primitive: TStopwatch.getTimeStamp — the shared fork-free us clock.
# Every test sets its own stdin explicitly (PLAN §4).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

TP_DIR="$SCRIPT_DIR/.."
source "$TP_DIR/tpipe.sh"
source "$TP_DIR/../tstopwatch/tstopwatch.sh"

TEST_NAME="$(basename "$0" .sh)"
kt_test_init "$TEST_NAME" "$SCRIPT_DIR" "$@"

TMP="$(cd "$(kt_fixture_tmpdir)" && pwd)"

kt_test_section "005: the PLAN §2.6 performance gates (P2)"

N=2000

# One builtin printf emits the whole stream, so the producer side is identical
# for TPipe and for the bare-bash baseline and adds no per-record cost of its own.
declare -a RECS=()
for (( i = 0; i < N; i++ )); do RECS+=( "record-$i" ); done
bench_producer() { printf '%s\n' "${RECS[@]}"; }

bench_noop() { return 0; }

# ===========================================================================
kt_test_section "A. the streaming gates"
# ===========================================================================

kt_test_start "each + a no-op FUNCTION costs at most 6x a bare \`while read\` loop (PLAN gate 2x)"
line=''
TStopwatch.getTimeStamp; t0=$RESULT
while IFS= read -r line; do :; done < <( bench_producer )
TStopwatch.getTimeStamp; t1=$RESULT
bare=$(( t1 - t0 )); (( bare > 0 )) || bare=1

TStopwatch.getTimeStamp; t0=$RESULT
TPipe.each bench_noop -- bench_producer; rc=$?
n_each="$RESULT"
TStopwatch.getTimeStamp; t1=$RESULT
eachfn=$(( t1 - t0 ))
lim=$(( bare * 6 ))
r100=$(( eachfn * 100 / bare ))
if [[ "$n_each" == "$N" && $rc -eq 0 ]] && (( eachfn <= lim )); then
    kt_test_pass "bare ${bare}us, each ${eachfn}us — ${r100}% of the baseline (ceiling ${lim}us), $N records"
else
    kt_test_fail "RESULT='$n_each' rc=$rc bare=${bare}us each=${eachfn}us (${r100}%) ceiling=${lim}us"
fi

kt_test_start "toArray costs at most 4.5x a bare \`mapfile\` (PLAN gate 1.5x)"
declare -a BARR=() TARR=()
TStopwatch.getTimeStamp; t0=$RESULT
mapfile -t BARR < <( bench_producer )
TStopwatch.getTimeStamp; t1=$RESULT
baremap=$(( t1 - t0 )); (( baremap > 0 )) || baremap=1

TStopwatch.getTimeStamp; t0=$RESULT
TPipe.toArray TARR -- bench_producer; rc=$?
n_arr="$RESULT"
TStopwatch.getTimeStamp; t1=$RESULT
toarr=$(( t1 - t0 ))
lim=$(( baremap * 45 / 10 ))
r100=$(( toarr * 100 / baremap ))
if [[ "$n_arr" == "$N" && $rc -eq 0 && "${#TARR[@]}" == "$N" && "${TARR[0]}" == "${BARR[0]}" \
      && "${TARR[$(( N - 1 ))]}" == "${BARR[$(( N - 1 ))]}" ]] && (( toarr <= lim )); then
    kt_test_pass "bare ${baremap}us, toArray ${toarr}us — ${r100}% of the baseline (ceiling ${lim}us), $N records"
else
    kt_test_fail "RESULT='$n_arr' rc=$rc n=${#TARR[@]} bare=${baremap}us toArray=${toarr}us (${r100}%) ceiling=${lim}us"
fi

# ===========================================================================
kt_test_section "B. the latency gate — first on an infinite producer"
# ===========================================================================

# In a CHILD under `timeout`: the close -> kill -TERM -> wait path is the one
# that can HANG (a producer that ignores SIGPIPE and stops writing blocks `wait`
# for its whole life — PLAN §2.3), and a hang here would take the whole suite
# with it. The child times the call itself, so bash's startup is not counted.
# `yes` gets 2>/dev/null: a closed pipe makes it print "write error: Broken
# pipe", which is the PRODUCER's stderr (PLAN §4).
LATCHILD="$TMP/lat_child.sh"
cat > "$LATCHILD" <<'LAT_EOF'
#!/bin/bash
source "$1/tpipe.sh"
source "$1/../tstopwatch/tstopwatch.sh"
TStopwatch.getTimeStamp; t0=$RESULT
rc=0
TPipe.first -- yes 2>/dev/null || rc=$?
res="$RESULT"
TStopwatch.getTimeStamp; t1=$RESULT
TPipe.lastRc
printf 'rc=%s res=%s lastrc=%s us=%s\n' "$rc" "$res" "$RESULT" "$(( t1 - t0 ))"
LAT_EOF

kt_test_start "TPipe.first -- yes answers in at most 750 ms (PLAN gate 250 ms)"
out="$(timeout 20 "$BASH" "$LATCHILD" "$TP_DIR" </dev/null 2>/dev/null)"; crc=$?
us="${out##*us=}"
if [[ $crc -eq 0 && "$out" == "rc=0 res=y lastrc=14"[13]" us="* && "$us" =~ ^[0-9]+$ ]] \
   && (( us <= 750000 )); then
    kt_test_pass "$out (ceiling 750000 us)"
else
    kt_test_fail "timeout rc=$crc out='$out' (ceiling 750000 us)"
fi

# ===========================================================================
kt_test_section "C. zero forks per record, for every sink"
# ===========================================================================

p5() { printf 'r1\nr2\nr3\nr4\nr5\n'; }
# one line per record carrying the PRODUCER's own pid
ppid5() { local i; for i in 1 2 3 4 5; do printf '%s\n' "$BASHPID"; done; }

CBPIDS=()
pid_cb() { CBPIDS+=( "$BASHPID" ); return 0; }

ADDPIDS=()
class TFork005
    public
        constructor Create
        proc        Add
end
TFork005.Create() { return 0; }
TFork005.Add()    { ADDPIDS+=( "$BASHPID" ); return 0; }
build TFork005
TFork005.new F5

kt_test_start "each: the callback runs in THIS process for every record"
p0=$BASHPID
CBPIDS=()
TPipe.each pid_cb -- p5; rc=$?
ok=1
for pid in "${CBPIDS[@]}"; do
    [[ "$pid" == "$p0" ]] || ok=0
done
if [[ "$RESULT" == "5" && $rc -eq 0 && "$BASHPID" == "$p0" ]] && (( ok == 1 && ${#CBPIDS[@]} == 5 )); then
    kt_test_pass "5 records, all in pid $p0"
else
    kt_test_fail "RESULT='$RESULT' rc=$rc ours=$p0 now=$BASHPID pids=(${CBPIDS[*]})"
fi

kt_test_start "toList: \`.Add\` runs in THIS process for every record"
p0=$BASHPID
ADDPIDS=()
TPipe.toList F5 -- p5; rc=$?
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
TPipe.toArray PPIDS -- ppid5; rc=$?
same=1
for pid in "${PPIDS[@]}"; do
    [[ "$pid" == "${PPIDS[0]}" ]] || same=0
done
prod_arr="${PPIDS[0]:-}"
TPipe.count -- ppid5;  rc2=$?; n_count="$RESULT"
TPipe.first -- ppid5 2>/dev/null; rc3=$?; prod_first="$RESULT"
if [[ "$BASHPID" == "$p0" && $rc -eq 0 && $rc2 -eq 0 && $rc3 -eq 0 && "$n_count" == "5" ]] \
   && (( same == 1 && ${#PPIDS[@]} == 5 )) \
   && [[ -n "$prod_arr" && "$prod_arr" != "$p0" && "$prod_first" != "$p0" ]]; then
    kt_test_pass "5 records, one producer pid $prod_arr (ours $p0); count 5; first saw pid $prod_first"
else
    kt_test_fail "ours=$p0 now=$BASHPID rc=$rc/$rc2/$rc3 count='$n_count' first='$prod_first' pids=(${PPIDS[*]})"
fi

F5.delete

kt_test_log "005_Bench.sh completed"
