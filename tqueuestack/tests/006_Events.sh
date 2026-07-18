#!/bin/bash
# 006_Events.sh - tqueuestack P3: the OnNotify event seam. Pins: S1 (write
# then added), S2 (Notify is the removal TAIL with the value), S4 (Clear =
# per-item removed in FIFO/LIFO order), S6 (Destroy -> Clear -> events fire
# during delete), the extracted-vs-removed action split, the hot-path gate
# (no callback -> no dispatch), dangling-callback safety, RESULT preservation
# through the dispatcher, exotic values through events. FPC-traceable cases
# cite tests.generics.queue.pas/stack.pas TestValueNotification[Delete] and
# stdcollections Test_TQueue/TStack_Notification.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

TQS_DIR="$SCRIPT_DIR/.."
source "$TQS_DIR/tqueuestack.sh"

TEST_NAME="$(basename "$0" .sh)"
kt_test_init "$TEST_NAME" "$SCRIPT_DIR" "$@"

kt_test_section "006: OnNotify events (P3)"

REC=()
rec() { REC+=("$2:$3"); }               # cb: <inst> <item> <action>
recsender() { REC+=("$1|$2:$3"); }      # variant capturing the sender

kt_test_start "FPC TestValueNotification (queue :368): add 3 -> added x3 in order"
TQueue.new Q
Q.on_notify = "rec"
REC=()
Q.Enqueue 1; Q.Enqueue 2; Q.Enqueue 3
[[ "${REC[*]}" == "1:added 2:added 3:added" ]] && kt_test_pass "S1 order" \
    || kt_test_fail "${REC[*]}"

kt_test_start "stdcollections :639-647: Dequeue -> removed, Extract -> extracted"
REC=()
Q.Dequeue >/dev/null
Q.Extract >/dev/null
[[ "${REC[*]}" == "1:removed 2:extracted" ]] && kt_test_pass "action split" \
    || kt_test_fail "${REC[*]}"

kt_test_start "FPC TestValueNotificationDelete (queue :376): Clear -> removed FIFO"
Q.Enqueue 4; REC=()
Q.Clear
[[ "${REC[*]}" == "3:removed 4:removed" ]] && kt_test_pass "S4 FIFO" \
    || kt_test_fail "${REC[*]}"

kt_test_start "sender is the instance handle"
REC=()
Q.on_notify = "recsender"
Q.Enqueue s1
[[ "${REC[0]}" == "Q|s1:added" ]] && kt_test_pass "sender Q" || kt_test_fail "${REC[0]}"
Q.on_notify = "rec"

kt_test_start "TryDequeue fires removed; empty Try fires NOTHING"
Q.Clear; Q.Enqueue T; REC=()
Q.TryDequeue >/dev/null
Q.TryDequeue >/dev/null
[[ "${REC[*]}" == "T:removed" ]] && kt_test_pass "one event only" || kt_test_fail "${REC[*]}"

kt_test_start "S6: queue Destroy fires FIFO removed events"
Q.Enqueue d1; Q.Enqueue d2; REC=()
Q.delete
[[ "${REC[*]}" == "d1:removed d2:removed" ]] && kt_test_pass "events during delete" \
    || kt_test_fail "${REC[*]}"

kt_test_start "stack: added order + Pop removed + Extract extracted"
TStack.new S
S.on_notify = "rec"
REC=()
S.Push a; S.Push b; S.Push c; S.Push d
S.Pop >/dev/null
S.Extract >/dev/null
[[ "${REC[*]}" == "a:added b:added c:added d:added d:removed c:extracted" ]] \
    && kt_test_pass "stack action stream" || kt_test_fail "${REC[*]}"

kt_test_start "FPC TestValueNotificationDelete (stack): Clear -> removed LIFO"
REC=()
S.Clear
[[ "${REC[*]}" == "b:removed a:removed" ]] && kt_test_pass "S4 LIFO" || kt_test_fail "${REC[*]}"

kt_test_start "S6: stack Destroy fires LIFO removed events"
S.Push z1; S.Push z2; REC=()
S.delete
[[ "${REC[*]}" == "z2:removed z1:removed" ]] && kt_test_pass "events during delete" \
    || kt_test_fail "${REC[*]}"

kt_test_start "hot-path gate: no callback -> ops work, nothing dispatched"
TQueue.new G
G.Enqueue x
G.Dequeue
[[ "$RESULT" == "x" ]] && kt_test_pass "gate off, ops fine" || kt_test_fail "r=$RESULT"
G.delete

kt_test_start "dangling callback: silent no-op, operations unaffected"
TQueue.new DG
DG.on_notify = "no_such_fn_xyz"
DG.Enqueue ok 2>/dev/null; rc=$?
DG.Dequeue 2>/dev/null; r="$RESULT"
[[ $rc -eq 0 && "$r" == "ok" ]] && kt_test_pass "rc 0, value intact" || kt_test_fail "rc=$rc r=$r"
DG.delete

kt_test_start "RESULT survives a clobbering callback (dispatcher isolation)"
clobber() { RESULT="CLOBBERED"; }
TStack.new RP
RP.on_notify = "clobber"
RP.Push v
RP.Pop
[[ "$RESULT" == "v" ]] && kt_test_pass "Pop's RESULT wins" || kt_test_fail "got '$RESULT'"
RP.delete

kt_test_start "exotic values pass through events byte-exact"
REC=()
TQueue.new EX
EX.on_notify = "rec"
EX.Enqueue $'a\nb'
EX.Enqueue 'two words'
EX.Clear
want="$(printf 'a\nb'):added two words:added $(printf 'a\nb'):removed two words:removed"
[[ "${REC[*]}" == "$want" ]] && kt_test_pass "newline/space items intact" \
    || kt_test_fail "${REC[*]}"
EX.delete

kt_test_start "callback detach mid-life: events stop"
TQueue.new DT
DT.on_notify = "rec"
DT.Enqueue e1
DT.on_notify = ""
REC=()
DT.Enqueue e2; DT.Clear
[[ "${REC[*]}" == "" ]] && kt_test_pass "no events after detach" || kt_test_fail "${REC[*]}"
DT.delete

kt_test_start "PATH='' : events fork-free"
zf="$(
    PATH=''
    source "$TQS_DIR/tqueuestack.sh" 2>/dev/null
    Z_REC=()
    zrec() { Z_REC+=("$2:$3"); }
    TQueue.new Z
    Z.on_notify = "zrec"
    Z.Enqueue x
    Z.Dequeue >/dev/null
    Z.delete
    printf '%s' "${Z_REC[*]}"
)"
[[ "$zf" == "x:added x:removed" ]] && kt_test_pass "$zf" || kt_test_fail "PATH='' got '$zf'"

kt_test_log "006_Events.sh completed"
