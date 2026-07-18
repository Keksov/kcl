#!/bin/bash
# 003_FpcQueueParity.sh - FPC-TRACEABLE cross-checks: the TTestSimpleQueue core
# procedures of packages/rtl-generics/tests/tests.generics.queue.pas, adapted
# verbatim (DoAdd enqueues IntToStr(offset+1..offset+count); exceptions ->
# rc 1). The notification procedures (TestValueNotification/-Delete) land at
# P3 with the events; the TTestSingleObjectQueue ownership pair lands at P4.
# Each case cites its seed procedure/line.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

TQS_DIR="$SCRIPT_DIR/.."
source "$TQS_DIR/tqueuestack.sh"

TEST_NAME="$(basename "$0" .sh)"
kt_test_init "$TEST_NAME" "$SCRIPT_DIR" "$@"

kt_test_section "003: FPC TTestSimpleQueue parity (tests.generics.queue.pas)"

do_add() {  # aCount [aOffset] — seed DoAdd :186 (enqueue IntToStr(i))
    local count="$1" offset="${2:-0}" i
    for (( i = offset + 1; i <= offset + count; i++ )); do
        Q.Enqueue "$i"
    done
}

kt_test_start "TestEmpty :180 — fresh queue has Count 0"
TQueue.new Q
Q.Count
[[ "$RESULT" == "0" ]] && kt_test_pass "0" || kt_test_fail "got $RESULT"

kt_test_start "TestAdd :198 — DoAdd(1) count 1; DoAdd(1,1) count 2"
do_add 1
Q.Count; a=$RESULT
do_add 1 1
Q.Count; b=$RESULT
[[ "$a" == "1" && "$b" == "2" ]] && kt_test_pass "1 / 2" || kt_test_fail "$a / $b"
Q.Clear

kt_test_start "TestClear :207 — add 3, count 3, clear, count 0"
do_add 3
Q.Count; a=$RESULT
Q.Clear
Q.Count; b=$RESULT
[[ "$a" == "3" && "$b" == "0" ]] && kt_test_pass "3 -> 0" || kt_test_fail "$a -> $b"

kt_test_start "TestGetValue :285 — dequeue '1','2','3', 4th raises (rc 1)"
do_add 3
Q.Dequeue; a=$RESULT
Q.Dequeue; b=$RESULT
Q.Dequeue; c=$RESULT
Q.Dequeue 2>/dev/null; rc=$?
[[ "$a/$b/$c" == "1/2/3" && $rc -eq 1 ]] \
    && kt_test_pass "1 2 3 then EArgumentOutOfRange analog" || kt_test_fail "$a/$b/$c rc=$rc"

kt_test_start "TestPeek :297 — Peek==i then Dequeue==i, for 1..3"
do_add 3
ok=1
for i in 1 2 3; do
    Q.Peek;    [[ "$RESULT" == "$i" ]] || ok=0
    Q.Dequeue; [[ "$RESULT" == "$i" ]] || ok=0
done
[[ $ok -eq 1 ]] && kt_test_pass "peek/dequeue pairs match" || kt_test_fail "mismatch"

kt_test_start "TestDequeue :322 — add 3, Dequeue '1', Count 2"
do_add 3
Q.Dequeue; a=$RESULT
Q.Count; b=$RESULT
[[ "$a" == "1" && "$b" == "2" ]] && kt_test_pass "'1', count 2" || kt_test_fail "a=$a b=$b"
Q.Clear

kt_test_start "TestToArray :330 — add 3, ToArray len 3, elements '1','2','3'"
do_add 3
A=(); Q.ToArray A
[[ "${#A[@]}" == "3" && "${A[0]}" == "1" && "${A[1]}" == "2" && "${A[2]}" == "3" ]] \
    && kt_test_pass "len 3: 1 2 3" || kt_test_fail "len=${#A[@]} [${A[*]}]"
Q.delete

kt_test_log "003_FpcQueueParity.sh completed"
