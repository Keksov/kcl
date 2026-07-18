#!/bin/bash
# 005_FpcStackParity.sh - FPC-TRACEABLE cross-checks: the TTestSimpleStack core
# procedures of packages/rtl-generics/tests/tests.generics.stack.pas, adapted
# verbatim (DoAdd pushes IntToStr(1..count); exceptions -> rc 1). Notification
# procedures land at P3; the TTestSingleObjectStack ownership pair at P4.
# Each case cites its seed procedure.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

TQS_DIR="$SCRIPT_DIR/.."
source "$TQS_DIR/tqueuestack.sh"

TEST_NAME="$(basename "$0" .sh)"
kt_test_init "$TEST_NAME" "$SCRIPT_DIR" "$@"

kt_test_section "005: FPC TTestSimpleStack parity (tests.generics.stack.pas)"

do_add() {  # aCount — seed DoAdd :196 (push IntToStr(1..count))
    local count="$1" i
    for (( i = 1; i <= count; i++ )); do
        S.Push "$i"
    done
}

kt_test_start "TestEmpty :190 — fresh stack has Count 0"
TStack.new S
S.Count
[[ "$RESULT" == "0" ]] && kt_test_pass "0" || kt_test_fail "got $RESULT"

kt_test_start "TestAdd :206 — DoAdd(1) count 1; DoAdd(1) count 2"
do_add 1
S.Count; a=$RESULT
do_add 1
S.Count; b=$RESULT
[[ "$a" == "1" && "$b" == "2" ]] && kt_test_pass "1 / 2" || kt_test_fail "$a / $b"
S.Clear

kt_test_start "TestClear :215 — add 3, count 3, clear, count 0"
do_add 3
S.Count; a=$RESULT
S.Clear
S.Count; b=$RESULT
[[ "$a" == "3" && "$b" == "0" ]] && kt_test_pass "3 -> 0" || kt_test_fail "$a -> $b"

kt_test_start "TestGetValue :293 — pop '3','2','1', 4th raises (rc 1)"
do_add 3
S.Pop; a=$RESULT
S.Pop; b=$RESULT
S.Pop; c=$RESULT
S.Pop 2>/dev/null; rc=$?
[[ "$a/$b/$c" == "3/2/1" && $rc -eq 1 ]] \
    && kt_test_pass "3 2 1 then EArgumentOutOfRange analog" || kt_test_fail "$a/$b/$c rc=$rc"

kt_test_start "TestPeek :305 — Peek==i then Pop==i, for 3 downto 1"
do_add 3
ok=1
for i in 3 2 1; do
    S.Peek; [[ "$RESULT" == "$i" ]] || ok=0
    S.Pop;  [[ "$RESULT" == "$i" ]] || ok=0
done
[[ $ok -eq 1 ]] && kt_test_pass "peek/pop pairs match (LIFO)" || kt_test_fail "mismatch"

kt_test_start "TestPop :330 — pop 3..1 asserted, then Count 0"
do_add 3
ok=1
for i in 3 2 1; do
    S.Pop; [[ "$RESULT" == "$i" ]] || ok=0
done
S.Count; n=$RESULT
[[ $ok -eq 1 && "$n" == "0" ]] && kt_test_pass "3 2 1, count 0" || kt_test_fail "ok=$ok n=$n"

kt_test_start "TestToArray :345 — add 3, len 3, A[i-1]==i (bottom->top)"
do_add 3
A=(); S.ToArray A
[[ "${#A[@]}" == "3" && "${A[0]}" == "1" && "${A[1]}" == "2" && "${A[2]}" == "3" ]] \
    && kt_test_pass "len 3: 1 2 3 bottom->top" || kt_test_fail "len=${#A[@]} [${A[*]}]"
S.delete

kt_test_log "005_FpcStackParity.sh completed"
