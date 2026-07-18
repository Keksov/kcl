#!/bin/bash
# 004_StackCore.sh - tqueuestack P2: the TStack core. Pins: LIFO order incl.
# interleaved push/pop, Pop/Extract/Peek empty -> rc 1 vs TryPop's SILENT
# rc 1, Clear = Pop-loop shape (LIFO events from P3), ToArray bottom->top
# (S9, seed-confirmed), density invariant (top == count-1 survives any op
# sequence), exotic values, ''-item vs empty distinction, instance isolation
# (incl. queue-vs-stack on the same names), zero-fork. FPC-traceable cases
# live in 005_FpcStackParity.sh.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

TQS_DIR="$SCRIPT_DIR/.."
source "$TQS_DIR/tqueuestack.sh"

TEST_NAME="$(basename "$0" .sh)"
kt_test_init "$TEST_NAME" "$SCRIPT_DIR" "$@"

kt_test_section "004: TStack core (P2)"

kt_test_start "LIFO: push 3, pop in reverse, then empty rc 1"
TStack.new S
S.Push one; S.Push two; S.Push three
S.Pop; a=$RESULT
S.Pop; b=$RESULT
S.Pop; c=$RESULT
S.Pop 2>/dev/null; rc=$?
[[ "$a/$b/$c" == "three/two/one" && $rc -eq 1 && "$RESULT" == "" ]] \
    && kt_test_pass "three two one, then rc 1 ''" || kt_test_fail "$a/$b/$c rc=$rc"

kt_test_start "interleave: push/pop mixed keeps LIFO + density"
S.Push A; S.Push B
S.Pop >/dev/null            # removes B
S.Push C; S.Push D
S.Peek; p=$RESULT
S.Count; n=$RESULT
T=(); S.ToArray T
[[ "$p" == "D" && "$n" == "3" && "${T[0]}${T[1]}${T[2]}" == "ACD" ]] \
    && kt_test_pass "peek D, count 3, ToArray ACD (bottom->top)" \
    || kt_test_fail "p=$p n=$n arr=${T[*]}"

kt_test_start "density invariant: indices stay 0..count-1 after mixed ops"
iv="S_items"
idx="$(eval "echo \${!${iv}[@]}")"
[[ "$idx" == "0 1 2" ]] && kt_test_pass "dense: $idx" || kt_test_fail "indices: $idx"

kt_test_start "Extract removes the top like Pop (action differs from P3 on)"
S.Extract; x=$RESULT
S.Count; n=$RESULT
[[ "$x" == "D" && "$n" == "2" ]] && kt_test_pass "extracted D" || kt_test_fail "x=$x n=$n"

kt_test_start "Clear: drain + reusable; TryPop/Peek empty semantics"
S.Clear
S.Count; n=$RESULT
S.TryPop; rc1=$?; r1="$RESULT"
S.Peek 2>/dev/null; rc2=$?
S.Push again; S.Pop; r2=$RESULT
[[ "$n" == "0" && $rc1 -eq 1 && "$r1" == "" && $rc2 -eq 1 && "$r2" == "again" ]] \
    && kt_test_pass "count 0; Try rc1 silent; Peek rc1; reusable" \
    || kt_test_fail "n=$n rc1=$rc1 r1='$r1' rc2=$rc2 r2=$r2"

kt_test_start "''-item pops with rc 0 — distinguishable from empty-stack rc 1"
S.Push ""
S.Pop; rc=$?
[[ $rc -eq 0 && "$RESULT" == "" ]] && kt_test_pass "rc 0, RESULT ''" || kt_test_fail "rc=$rc"

kt_test_start "exotic values byte-exact through the stack"
S.Push "two words"; S.Push $'a\nb'; S.Push '*.txt'; S.Push '$(boom)'; S.Push 'café'
S.Pop; e5=$RESULT; S.Pop; e4=$RESULT; S.Pop; e3=$RESULT
S.Pop; e2=$RESULT; S.Pop; e1=$RESULT
[[ "$e1" == "two words" && "$e2" == $'a\nb' && "$e3" == '*.txt' \
   && "$e4" == '$(boom)' && "$e5" == 'café' ]] \
    && kt_test_pass "spaces/newline/glob/\$()/unicode lossless (LIFO)" \
    || kt_test_fail "[$e1][$e2][$e3][$e4][$e5]"
S.delete

kt_test_start "queue and stack instances are independent"
TQueue.new IQ; TStack.new IS
IQ.Enqueue qv; IS.Push sv
IQ.Dequeue; a=$RESULT
IS.Pop; b=$RESULT
[[ "$a" == "qv" && "$b" == "sv" ]] && kt_test_pass "isolated" || kt_test_fail "a=$a b=$b"
IQ.delete; IS.delete

kt_test_start "deep stack: 200 pushes, 200 pops, order + final emptiness"
TStack.new DS
for ((i=0; i<200; i++)); do DS.Push "s$i"; done
DS.Count; n1=$RESULT
ok=1
for ((i=199; i>=0; i--)); do
    DS.Pop
    [[ "$RESULT" == "s$i" ]] || { ok=0; break; }
done
DS.Count; n2=$RESULT
[[ $ok -eq 1 && "$n1" == "200" && "$n2" == "0" ]] \
    && kt_test_pass "200 LIFO-exact, drained" || kt_test_fail "ok=$ok n1=$n1 n2=$n2 (i=$i r=$RESULT)"
DS.delete

kt_test_start "PATH='' : full stack lifecycle fork-free"
zf="$(
    PATH=''
    source "$TQS_DIR/tqueuestack.sh" 2>/dev/null
    TStack.new Z
    Z.Push x; Z.Push y; Z.Push z
    Z.Pop >/dev/null; a="$RESULT"
    Z.Extract >/dev/null; b="$RESULT"
    Z.Peek >/dev/null; c="$RESULT"
    O=(); Z.ToArray O >/dev/null
    Z.Clear; Z.Count >/dev/null; d="$RESULT"
    Z.delete
    printf '%s|%s|%s|%s|%s' "$a" "$b" "$c" "${#O[@]}" "$d"
)"
[[ "$zf" == "z|y|x|1|0" ]] && kt_test_pass "$zf" || kt_test_fail "PATH='' got '$zf'"

kt_test_log "004_StackCore.sh completed"
