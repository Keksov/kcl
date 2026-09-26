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
#   4.5x and (for `first`, since 2026-09-25) 3x a bare stop path + 300 ms
#   instead of an absolute 750 ms, see section B — because ktests runs test files THREADED, 8 workers by
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

# FIVE INTERLEAVED SAMPLES, BEST OF EACH SIDE (2026-09-24). Each side's window
# holds one fork by design — the producer's process substitution — and under
# the threaded runner (8 files forking side by side) ~2-9 % of forks stall
# ~280 ms, seconds on 5.3.9. With ONE sample per side a single stall on the
# measured side broke the ceiling on code that is fine; contention only ever
# makes a sample slower, so the minimum is the cost of the code itself.
NS=5

kt_test_start "each + a no-op FUNCTION costs at most 6x a bare \`while read\` loop (PLAN gate 2x)"
line=''
bare=0; eachfn=0; rc=0; n_each=''
for (( s = 0; s < NS; s++ )); do
    TStopwatch.getTimeStamp; t0=$RESULT
    while IFS= read -r line; do :; done < <( bench_producer )
    TStopwatch.getTimeStamp; t1=$RESULT
    if (( bare == 0 || t1 - t0 < bare )); then bare=$(( t1 - t0 )); fi

    TStopwatch.getTimeStamp; t0=$RESULT
    TPipe.each bench_noop -- bench_producer || rc=$?
    n=$RESULT
    TStopwatch.getTimeStamp; t1=$RESULT
    if (( eachfn == 0 || t1 - t0 < eachfn )); then eachfn=$(( t1 - t0 )); fi
    # every sample must deliver every record, not just the last one
    if [[ -z "$n_each" || "$n_each" == "$N" ]]; then n_each="$n"; fi
done
(( bare > 0 )) || bare=1
lim=$(( bare * 6 ))
r100=$(( eachfn * 100 / bare ))
if [[ "$n_each" == "$N" && $rc -eq 0 ]] && (( eachfn <= lim )); then
    kt_test_pass "best of $NS: bare ${bare}us, each ${eachfn}us — ${r100}% of the baseline (ceiling ${lim}us), $N records"
else
    kt_test_fail "best of $NS: RESULT='$n_each' rc=$rc bare=${bare}us each=${eachfn}us (${r100}%) ceiling=${lim}us"
fi

kt_test_start "toArray costs at most 4.5x a bare \`mapfile\` (PLAN gate 1.5x)"
declare -a BARR=() TARR=()
baremap=0; toarr=0; rc=0; n_arr=''; arr_ok=1
for (( s = 0; s < NS; s++ )); do
    TStopwatch.getTimeStamp; t0=$RESULT
    mapfile -t BARR < <( bench_producer )
    TStopwatch.getTimeStamp; t1=$RESULT
    if (( baremap == 0 || t1 - t0 < baremap )); then baremap=$(( t1 - t0 )); fi

    TStopwatch.getTimeStamp; t0=$RESULT
    TPipe.toArray TARR -- bench_producer || rc=$?
    n=$RESULT
    TStopwatch.getTimeStamp; t1=$RESULT
    if (( toarr == 0 || t1 - t0 < toarr )); then toarr=$(( t1 - t0 )); fi
    if [[ -z "$n_arr" || "$n_arr" == "$N" ]]; then n_arr="$n"; fi
    if [[ "${#TARR[@]}" != "$N" || "${TARR[0]}" != "${BARR[0]}" \
          || "${TARR[$(( N - 1 ))]}" != "${BARR[$(( N - 1 ))]}" ]]; then arr_ok=0; fi
done
(( baremap > 0 )) || baremap=1
lim=$(( baremap * 45 / 10 ))
r100=$(( toarr * 100 / baremap ))
if [[ "$n_arr" == "$N" && $rc -eq 0 && "$arr_ok" == 1 ]] && (( toarr <= lim )); then
    kt_test_pass "best of $NS: bare ${baremap}us, toArray ${toarr}us — ${r100}% of the baseline (ceiling ${lim}us), $N records"
else
    kt_test_fail "best of $NS: RESULT='$n_arr' rc=$rc n=${#TARR[@]} arrays-equal=$arr_ok bare=${baremap}us toArray=${toarr}us (${r100}%) ceiling=${lim}us"
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
# A RELATIVE GATE (2026-09-25, on the reviewer's decision). Every call holds the
# fork of `yes` by design, and under a 16-sibling fork storm every fork costs
# ~1 s (all 5 calls of a best-of-5 measured at 1.0-3.5 s, answers correct), so
# no absolute ceiling survives while an idle call is ~28 ms. The child
# therefore times, INTERLEAVED, a BARE baseline and TPipe.first, and the gate
# is  best(first) <= K x best(bare) + SLACK.
#
# The baseline is TPipe.first's own mechanism written out in the test —
#     exec {fd}< <( yes ); pid=$!; read -r -u fd; exec {fd}<&-; kill -TERM pid; wait pid
# — the same process substitution (one fork, `yes` exec'd in it), the same one
# record read, the same close -> kill -TERM -> wait stop path (tpipe.sh
# tpipe._open / tpipe._close). `IFS= read -r x < <(yes)` would NOT do: it
# neither kills nor waits, so it would leave out exactly the stop path this
# case exists for. The ratio is thus "TPipe's own overhead around one stop".
#
# K = 3, SLACK = 300 ms, from measured pairs (min bare / min first, 5 pairs,
# 4 rounds per cell, both bashes): idle 26-36 / 26-37 ms (ratio 0.9-1.04);
# storm 8 up to 44 / 128 ms (2.9x — the two minima are independent draws from
# a fast ~50 ms / slow ~300 ms fork distribution); storm 16 up to 79 / 196 ms
# (2.5x) and 613 / 621 ms. SLACK covers one ~300 ms fork quantum landing on
# every `first` sample; K covers the rest. Idle this is a ~380 ms ceiling,
# tighter than the old 750 ms one (a stop path grown by a fixed 0.5 s fails
# here and passed there); the PLAN gate (250 ms, idle, absolute) stays in
# bench.sh.
# HANG BOUND: a lost stop on `yes` never returns at all, so any single call
# over 10 s fails whatever the ratio (the slowest correct call measured under
# storm 16 was 3.5 s), and a call still running when the guard fires is a HANG.
#
# PER-PAIR LOG, NOT A SUMMARY LINE. The child appends `start K +MS` (ms since
# it started) before each pair and `pair K bare=US first=US <answer>` after it
# to $3 AS IT GOES, so a `timeout` tells a HANG from a slow start: under a
# 16-sibling storm the child's cold `source` alone took 19-68 s (measured,
# both bashes). The guard is 180 s; the child stops starting pairs once 20 s
# have gone into them, so a slow child exits by itself.
LATCHILD="$TMP/lat_child.sh"
LATLOG="$TMP/lat_calls.log"
LAT_GUARD=180
LAT_K=3
LAT_SLACK_US=300000
LAT_HANG_US=10000000
LAT_PAIRS=7
cat > "$LATCHILD" <<'LAT_EOF'
#!/bin/bash
T0=${EPOCHREALTIME/[.,]/}
source "$1/tpipe.sh"
source "$1/../tstopwatch/tstopwatch.sh"
spent=0
for (( k = 0; k < $2; k++ )); do
    (( k > 0 && spent > 20000000 )) && break
    printf 'start %s +%s\n' "$k" $(( (${EPOCHREALTIME/[.,]/} - T0) / 1000 )) >> "$3"
    # (a) the bare baseline: TPipe.first's mechanism, written out
    TStopwatch.getTimeStamp; t0=$RESULT
    exec {bfd}< <( yes 2>/dev/null ); bpid=$!
    IFS= read -r -u "$bfd" bline
    exec {bfd}<&-
    kill -TERM "$bpid" 2>/dev/null || :
    wait "$bpid" 2>/dev/null || :
    TStopwatch.getTimeStamp; t1=$RESULT
    # (b) the member
    rc=0
    TPipe.first -- yes 2>/dev/null || rc=$?
    res="$RESULT"
    TStopwatch.getTimeStamp; t2=$RESULT
    TPipe.lastRc
    printf 'pair %s bare=%s first=%s rc=%s res=%s lastrc=%s\n' "$k" $(( t1 - t0 )) $(( t2 - t1 )) \
        "$rc" "$res" "$RESULT" >> "$3"
    spent=$(( spent + t2 - t0 ))
done
LAT_EOF

kt_test_start "TPipe.first -- yes costs at most ${LAT_K}x a bare stop path + $(( LAT_SLACK_US / 1000 )) ms (PLAN gate 250 ms idle)"
: > "$LATLOG"
timeout "$LAT_GUARD" "$BASH" "$LATCHILD" "$TP_DIR" "$LAT_PAIRS" "$LATLOG" </dev/null >/dev/null 2>&1; crc=$?
mapfile -t LCALLS < "$LATLOG"
n=0; bbest=0; fbest=0; fmax=0; bad=''; open=''; summary=''
for l in "${LCALLS[@]}"; do
    if [[ "$l" =~ ^start\ ([0-9]+)\ \+([0-9]+)$ ]]; then
        open="${BASH_REMATCH[1]} ${BASH_REMATCH[2]}"
    elif [[ "$l" =~ ^pair\ ([0-9]+)\ bare=([0-9]+)\ first=([0-9]+)\ (.*)$ ]]; then
        open=''; n=$(( n + 1 ))
        b="${BASH_REMATCH[2]}"; u="${BASH_REMATCH[3]}"; a="${BASH_REMATCH[4]}"
        summary+="$(( b / 1000 ))/$(( u / 1000 )) "
        if [[ -z "$bad" && "$a" != "rc=0 res=y lastrc=14"[13] ]]; then bad="pair ${BASH_REMATCH[1]}: $a"; fi
        if (( bbest == 0 || b < bbest )); then bbest=$b; fi
        if (( fbest == 0 || u < fbest )); then fbest=$u; fi
        if (( u > fmax )); then fmax=$u; fi
    fi
done
lim=$(( LAT_K * bbest + LAT_SLACK_US ))
# an open pair had run for (guard - its start) when the guard fired; a correct
# pair takes a few seconds at worst under a fork storm, so 30 s of it is a hang
if [[ -n "$open" ]] && (( LAT_GUARD * 1000 - ${open#* } >= 30000 )); then
    kt_test_fail "HANG: pair ${open% *} started at +${open#* } ms and had not returned when the ${LAT_GUARD} s guard fired (rc=$crc); done bare/first ms: ${summary:-none}"
elif (( n == 0 )); then
    kt_test_fail "no pair finished: ${open:+pair ${open% *} started only at +${open#* } ms, }the child's start did not complete in time (${LAT_GUARD} s guard, rc=$crc)"
elif [[ -n "$bad" ]]; then
    kt_test_fail "wrong answer on $bad (bare/first ms: $summary)"
elif (( fmax > LAT_HANG_US )); then
    kt_test_fail "a call took ${fmax} us > the ${LAT_HANG_US} us hang bound (bare/first ms: ${summary% })"
elif (( fbest <= lim )); then
    kt_test_pass "best of $n: first ${fbest} us <= ${LAT_K} x bare ${bbest} us + ${LAT_SLACK_US} = ${lim} us (bare/first ms: ${summary% }; child rc=$crc)"
else
    kt_test_fail "best of $n: first ${fbest} us > ${LAT_K} x bare ${bbest} us + ${LAT_SLACK_US} = ${lim} us (bare/first ms: ${summary% }; child rc=$crc)"
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
