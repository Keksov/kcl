#!/bin/bash
# 007_ObjectOwnership.sh - tqueuestack P4: TObjectQueue/TObjectStack. Pins:
# S7 (Notify = inherited FIRST — the user callback observes the instance
# ALIVE — then free on 'removed' ONLY when owning; 'extracted' hands
# ownership back), S8 (the two FPC quirks VERBATIM: TObjectQueue.Dequeue is a
# procedure — no value; TObjectStack.Pop returns the just-freed handle), S10
# (owns_objects writable mid-life — the FPC seed itself flips it), the
# ownership matrix across every removal path (Dequeue/Pop/Try*/Extract/Clear/
# Destroy), duplicate handles, non-instance items, zero-fork. FPC-traceable:
# TTestSingleObjectQueue TestEmpty/TestFreeOnDeQueue/TestNoFreeOnDeQueue
# (tests.generics.queue.pas :99-141) + the stack mirror.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

TQS_DIR="$SCRIPT_DIR/.."
source "$TQS_DIR/../tlist/tlist.sh"          # element instances for ownership
source "$TQS_DIR/tqueuestack.sh"

TEST_NAME="$(basename "$0" .sh)"
kt_test_init "$TEST_NAME" "$SCRIPT_DIR" "$@"

kt_test_section "007: TObjectQueue/TObjectStack ownership (P4)"

alive() { declare -F "$1.delete" >/dev/null 2>&1; }

kt_test_start "FPC TestEmpty :99 — fresh owning queue, Count 0, owns true"
TObjectQueue.new OQ
OQ.Count
[[ "$RESULT" == "0" && "$(OQ.owns_objects)" == "true" ]] \
    && kt_test_pass "0 / true (FPC default)" || kt_test_fail "n=$RESULT owns=$(OQ.owns_objects)"

kt_test_start "FPC TestFreeOnDeQueue :127 — owning Dequeue frees the object"
TList.new o1
OQ.Enqueue o1
OQ.Dequeue 2>/dev/null
if alive o1; then kt_test_fail "o1 survived an owning Dequeue"; o1.delete
else kt_test_pass "freed"; fi

kt_test_start "S8 quirk: TObjectQueue.Dequeue returns NOTHING (RESULT untouched)"
TList.new o2
OQ.Enqueue o2
RESULT="SENTINEL"
OQ.Dequeue
[[ "$RESULT" == "SENTINEL" ]] && kt_test_pass "procedure semantics (proc rollback)" \
    || kt_test_fail "RESULT='$RESULT'"

kt_test_start "FPC TestNoFreeOnDeQueue :136 — S10 mid-life flip: owns=false, not freed"
OQ.owns_objects = "false"
TList.new o3
OQ.Enqueue o3
OQ.Dequeue
if alive o3; then kt_test_pass "alive (flip honored at event time)"; o3.delete
else kt_test_fail "freed despite owns=false"; fi
OQ.owns_objects = "true"

kt_test_start "Extract hands ownership back — never frees"
TList.new o4
OQ.Enqueue o4
OQ.Extract; x="$RESULT"
if [[ "$x" == "o4" ]] && alive o4; then kt_test_pass "handle returned, alive"; o4.delete
else kt_test_fail "x=$x alive=$(alive o4 && echo y || echo n)"; fi

kt_test_start "TryDequeue frees like Dequeue (owning)"
TList.new o5
OQ.Enqueue o5
OQ.TryDequeue >/dev/null
alive o5 && { kt_test_fail "o5 alive"; o5.delete; } || kt_test_pass "freed"

kt_test_start "Clear frees all queued objects; Destroy frees the rest"
TList.new c1; TList.new c2; TList.new c3
OQ.Enqueue c1; OQ.Enqueue c2
OQ.Clear
a=$(alive c1 && echo y || echo n); b=$(alive c2 && echo y || echo n)
OQ.Enqueue c3
OQ.delete
c=$(alive c3 && echo y || echo n)
[[ "$a$b$c" == "nnn" ]] && kt_test_pass "Clear + Destroy free everything" \
    || kt_test_fail "$a$b$c"

kt_test_start "S8 quirk: TObjectStack.Pop returns the DEAD handle (owning)"
TList.new s1; TObjectStack.new OS
OS.Push s1
OS.Pop
p="$RESULT"
if [[ "$p" == "s1" ]] && ! alive s1; then kt_test_pass "s1 returned, already freed"
else kt_test_fail "p=$p alive=$(alive s1 && echo y || echo n)"; fi

kt_test_start "non-owning stack: Pop returns a LIVE handle"
TObjectStack.new OSN false
TList.new s2
OSN.Push s2
OSN.Pop
p="$RESULT"
if [[ "$p" == "s2" ]] && alive s2; then kt_test_pass "alive"; s2.delete
else kt_test_fail "p=$p"; fi
OSN.delete

kt_test_start "stack Extract never frees"
TList.new s3
OS.Push s3
OS.Extract; x="$RESULT"
if [[ "$x" == "s3" ]] && alive s3; then kt_test_pass "alive"; s3.delete
else kt_test_fail "x=$x"; fi

kt_test_start "S7: user callback observes the instance ALIVE; freed after"
CBSEEN=""
cb() { [[ "$3" == "removed" ]] && CBSEEN="$2:$(alive "$2" && echo y || echo n)"; }
TList.new v1
OS.on_notify = "cb"
OS.Push v1
OS.Pop >/dev/null
OS.on_notify = ""
[[ "$CBSEEN" == "v1:y" ]] && ! alive v1 \
    && kt_test_pass "cb saw it alive; dead after" || kt_test_fail "seen=$CBSEEN alive=$(alive v1 && echo y || echo n)"

kt_test_start "duplicate handle twice: freed once, second free is a no-op"
TList.new d1
OS.Push d1; OS.Push d1
OS.Clear; rc=$?
[[ $rc -eq 0 ]] && ! alive d1 && kt_test_pass "rc 0, freed once" || kt_test_fail "rc=$rc"

kt_test_start "non-instance items (plain strings, '') are silently safe"
OS.Push "plain string"; OS.Push ""
OS.Clear; rc=$?
OS.Count; n=$RESULT
[[ $rc -eq 0 && "$n" == "0" ]] && kt_test_pass "no-ops, cleared" || kt_test_fail "rc=$rc n=$n"
OS.delete

kt_test_start "empty TObjectQueue.Dequeue -> rc 1 (quirk keeps the error)"
TObjectQueue.new EQ
EQ.Dequeue 2>/dev/null; rc=$?
[[ $rc -eq 1 ]] && kt_test_pass "rc 1" || kt_test_fail "rc=$rc"
EQ.delete

kt_test_start "owning queue: FIFO free order visible through events"
SEQ=()
ecb() { [[ "$3" == "removed" ]] && SEQ+=("$2"); }
TList.new f1; TList.new f2
TObjectQueue.new FQ
FQ.on_notify = "ecb"
FQ.Enqueue f1; FQ.Enqueue f2
FQ.delete
[[ "${SEQ[*]}" == "f1 f2" ]] && ! alive f1 && ! alive f2 \
    && kt_test_pass "f1 f2 removed+freed in FIFO" || kt_test_fail "${SEQ[*]}"

kt_test_start "PATH='' : ownership cycle fork-free"
zf="$(
    PATH=''
    source "$TQS_DIR/../tlist/tlist.sh" 2>/dev/null
    source "$TQS_DIR/tqueuestack.sh" 2>/dev/null
    TList.new z1; TList.new z2
    TObjectQueue.new ZQ
    ZQ.Enqueue z1; ZQ.Enqueue z2
    ZQ.Dequeue
    a=$(declare -F z1.delete >/dev/null 2>&1 && echo y || echo n)
    ZQ.Extract >/dev/null
    b=$(declare -F z2.delete >/dev/null 2>&1 && echo y || echo n)
    ZQ.delete; z2.delete 2>/dev/null
    printf '%s%s' "$a" "$b"
)"
[[ "$zf" == "ny" ]] && kt_test_pass "dequeued-freed / extracted-alive" \
    || kt_test_fail "PATH='' got '$zf'"

kt_test_log "007_ObjectOwnership.sh completed"
