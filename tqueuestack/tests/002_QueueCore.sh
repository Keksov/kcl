#!/bin/bash
# 002_QueueCore.sh - tqueuestack P1: the TQueue core. Pins: FIFO order incl.
# interleaved enqueue/dequeue over head holes, Dequeue/Extract/Peek empty ->
# rc 1 (the EArgumentOutOfRange analog) vs TryDequeue's SILENT rc 1, Clear =
# drain loop + head reset (S4), ToArray front->back snapshot (S9), the
# amortized compaction (fires at qhead>=64 AND qhead>=live; order/values
# byte-exact across it — probes Q3/Q4 live), the drain-to-empty qhead reset
# (FPC FLow reset :2457, probe Q7), exotic values, ''-item vs empty-queue
# distinction, zero-fork. FPC-traceable cases live in 003_FpcQueueParity.sh.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

TQS_DIR="$SCRIPT_DIR/.."
source "$TQS_DIR/tqueuestack.sh"

TEST_NAME="$(basename "$0" .sh)"
kt_test_init "$TEST_NAME" "$SCRIPT_DIR" "$@"

kt_test_section "002: TQueue core (P1)"

kt_test_start "FIFO: enqueue 3, dequeue in order, then empty rc 1"
TQueue.new Q
Q.Enqueue one; Q.Enqueue two; Q.Enqueue three
Q.Dequeue; a=$RESULT
Q.Dequeue; b=$RESULT
Q.Dequeue; c=$RESULT
Q.Dequeue 2>/dev/null; rc=$?
[[ "$a/$b/$c" == "one/two/three" && $rc -eq 1 && "$RESULT" == "" ]] \
    && kt_test_pass "one two three, then rc 1 ''" || kt_test_fail "$a/$b/$c rc=$rc r='$RESULT'"

kt_test_start "interleave over head holes: dequeue then enqueue keeps FIFO"
Q.Enqueue A; Q.Enqueue B
Q.Dequeue >/dev/null                      # consume A -> hole at the head
Q.Enqueue C
Q.Peek; p=$RESULT
Q.Count; n=$RESULT
T=(); Q.ToArray T
[[ "$p" == "B" && "$n" == "2" && "${T[0]}${T[1]}" == "BC" ]] \
    && kt_test_pass "peek B, count 2, ToArray BC" || kt_test_fail "p=$p n=$n arr=${T[*]}"

kt_test_start "Extract removes the front like Dequeue (action differs from P3 on)"
Q.Extract; x=$RESULT
Q.Count; n=$RESULT
[[ "$x" == "B" && "$n" == "1" ]] && kt_test_pass "extracted B" || kt_test_fail "x=$x n=$n"

kt_test_start "Clear: drain + reusable; TryDequeue/Peek empty semantics"
Q.Clear
Q.Count; n=$RESULT
Q.TryDequeue; rc1=$?; r1="$RESULT"
Q.Peek 2>/dev/null; rc2=$?
Q.Enqueue again; Q.Dequeue; r2=$RESULT
[[ "$n" == "0" && $rc1 -eq 1 && "$r1" == "" && $rc2 -eq 1 && "$r2" == "again" ]] \
    && kt_test_pass "count 0; Try rc1 silent; Peek rc1; reusable" \
    || kt_test_fail "n=$n rc1=$rc1 r1='$r1' rc2=$rc2 r2=$r2"

kt_test_start "''-item dequeues with rc 0 — distinguishable from empty-queue rc 1"
Q.Enqueue ""
Q.Dequeue; rc=$?
[[ $rc -eq 0 && "$RESULT" == "" ]] && kt_test_pass "rc 0, RESULT ''" || kt_test_fail "rc=$rc"

kt_test_start "exotic values byte-exact through the queue"
Q.Enqueue "two words"; Q.Enqueue $'a\nb'; Q.Enqueue '*.txt'; Q.Enqueue '$(boom)'; Q.Enqueue 'café'
Q.Dequeue; e1=$RESULT; Q.Dequeue; e2=$RESULT; Q.Dequeue; e3=$RESULT
Q.Dequeue; e4=$RESULT; Q.Dequeue; e5=$RESULT
[[ "$e1" == "two words" && "$e2" == $'a\nb' && "$e3" == '*.txt' \
   && "$e4" == '$(boom)' && "$e5" == 'café' ]] \
    && kt_test_pass "spaces/newline/glob/\$()/unicode lossless" \
    || kt_test_fail "[$e1][$e2][$e3][$e4][$e5]"

kt_test_start "compaction fires at the frozen threshold; order/values intact"
for ((i=0; i<100; i++)); do Q.Enqueue "v$i"; done
for ((i=0; i<70; i++)); do Q.Dequeue >/dev/null; done
hv=Q_qhead; h="${!hv}"
Q.Count; n=$RESULT
Q.Peek; p=$RESULT
T2=(); Q.ToArray T2
# reindex fired at the 64th dequeue (qhead 64 >= live 36) -> qhead reset, then
# 6 more removals: qhead 6, live 30, front v70, back v99
if [[ "$h" == "6" && "$n" == "30" && "$p" == "v70" \
      && "${T2[0]}" == "v70" && "${T2[29]}" == "v99" && "${#T2[@]}" == "30" ]]; then
    kt_test_pass "fired at 64th; qhead 6, live 30, v70..v99 intact"
else
    kt_test_fail "h=$h n=$n p=$p t0=${T2[0]} t29=${T2[29]} len=${#T2[@]}"
fi

kt_test_start "drain-to-empty resets qhead to 0 (FPC FLow reset)"
for ((i=0; i<30; i++)); do Q.Dequeue >/dev/null; done
h="${!hv}"
Q.Count; n=$RESULT
[[ "$h" == "0" && "$n" == "0" ]] && kt_test_pass "qhead 0, count 0" || kt_test_fail "h=$h n=$n"
Q.delete

kt_test_start "two queues are independent (per-instance storage)"
TQueue.new Q1; TQueue.new Q2
Q1.Enqueue only1; Q2.Enqueue only2
Q1.Dequeue; a=$RESULT
Q2.Dequeue; b=$RESULT
[[ "$a" == "only1" && "$b" == "only2" ]] && kt_test_pass "isolated" || kt_test_fail "a=$a b=$b"
Q1.delete; Q2.delete

kt_test_start "PATH='' : full queue lifecycle fork-free"
zf="$(
    PATH=''
    source "$TQS_DIR/tqueuestack.sh" 2>/dev/null
    TQueue.new Z
    Z.Enqueue x; Z.Enqueue y; Z.Enqueue z
    Z.Dequeue >/dev/null; a="$RESULT"
    Z.Extract >/dev/null; b="$RESULT"
    Z.Peek >/dev/null; c="$RESULT"
    O=(); Z.ToArray O >/dev/null
    Z.Clear; Z.Count >/dev/null; d="$RESULT"
    Z.delete
    printf '%s|%s|%s|%s|%s' "$a" "$b" "$c" "${#O[@]}" "$d"
)"
[[ "$zf" == "x|y|z|1|0" ]] && kt_test_pass "$zf" || kt_test_fail "PATH='' got '$zf'"

kt_test_log "002_QueueCore.sh completed"
