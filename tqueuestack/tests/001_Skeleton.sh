#!/bin/bash
# 001_Skeleton.sh - tqueuestack P0 skeleton gate. Pins the ctor core: storage
# init (items + qhead), computed Count == ${#items[@]} (probes Q1/Q7),
# TObjectQueue/TObjectStack ctor token with the FPC OWNS-DEFAULT-TRUE (:483/
# :498 — kept verbatim), inheritance wiring for both pairs, pending sentinels,
# teardown, re-source guard, zero-fork. Core ops arrive P1 (queue) / P2 (stack).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

TQS_DIR="$SCRIPT_DIR/.."
source "$TQS_DIR/tqueuestack.sh"

TEST_NAME="$(basename "$0" .sh)"
kt_test_init "$TEST_NAME" "$SCRIPT_DIR" "$@"

kt_test_section "001: TQueue/TStack skeleton (P0 ctor core)"

kt_test_start "TQueue: storage init (items empty, qhead 0), Count 0"
TQueue.new Q
q_ok=1
declare -p Q_items >/dev/null 2>&1 || q_ok=0
hv="Q_qhead"
Q.Count
[[ $q_ok -eq 1 && "${!hv}" == "0" && "$RESULT" == "0" ]] \
    && kt_test_pass "items+qhead present, Count 0" \
    || kt_test_fail "ok=$q_ok qhead=${!hv} count=$RESULT"

kt_test_start "TStack: storage init, Count 0, on_notify empty"
TStack.new S
S.Count
[[ "$RESULT" == "0" && "$(S.on_notify)" == "" ]] && kt_test_pass "clean stack" \
    || kt_test_fail "count=$RESULT cb='$(S.on_notify)'"

kt_test_start "Count is computed from set elements (probe Q1 live)"
Q_items=(a b c); unset 'Q_items[0]'
Q.Count
[[ "$RESULT" == "2" ]] && kt_test_pass "holes don't count" || kt_test_fail "got $RESULT"
Q_items=(); Q_qhead=0

kt_test_start "TObjectQueue: FPC owns-default TRUE; explicit false honored"
TObjectQueue.new OQ
a="$(OQ.owns_objects)"
TObjectQueue.new OQF false
b="$(OQF.owns_objects)"
[[ "$a" == "true" && "$b" == "false" ]] && kt_test_pass "true / false" || kt_test_fail "a=$a b=$b"
OQF.delete

kt_test_start "TObjectStack: owns default TRUE; bogus token rc 1, still valid+owning"
TObjectStack.new OS
a="$(OS.owns_objects)"
TObjectStack.new OSB maybe 2>/dev/null
rc=$?
b="$(OSB.owns_objects)"
OSB.Count
c="$RESULT"
[[ "$a" == "true" && $rc -ne 0 && "$b" == "true" && "$c" == "0" ]] \
    && kt_test_pass "default true; bogus rc=$rc, usable owning instance" \
    || kt_test_fail "a=$a rc=$rc b=$b c=$c"
OSB.delete

kt_test_start "inheritance wiring: both pairs chain to their base"
pq="TObjectQueue_parent_class"; ps="TObjectStack_parent_class"
[[ "${!pq}" == "TQueue" && "${!ps}" == "TStack" ]] \
    && kt_test_pass "TObjectQueue:TQueue, TObjectStack:TStack" \
    || kt_test_fail "q=${!pq} s=${!ps}"

kt_test_start "TObject* inherit storage via inherited ctor (items exist)"
declare -p OQ_items >/dev/null 2>&1 && declare -p OS_items >/dev/null 2>&1 \
    && kt_test_pass "both storages present" || kt_test_fail "missing storage"

kt_test_start "all members real (post-P4): empty-collection overrides behave"
OQ.Dequeue 2>/dev/null
r1=$?
OS.Pop 2>/dev/null
r2=$?
[[ $r1 -eq 1 && $r2 -eq 1 ]] \
    && kt_test_pass "empty ObjectQueue.Dequeue/ObjectStack.Pop rc 1" \
    || kt_test_fail "r1=$r1 r2=$r2"

kt_test_start "delete tears the storage down"
Q.delete
declare -p Q_items >/dev/null 2>&1 && kt_test_fail "Q_items survived" || kt_test_pass "storage gone"
S.delete; OQ.delete; OS.delete

kt_test_start "re-source is a clean no-op"
source "$TQS_DIR/tqueuestack.sh"
[[ $? -eq 0 ]] && kt_test_pass "second source rc 0" || kt_test_fail "rc=$?"

kt_test_start "PATH='' : ctors/Count/teardown fork-free"
zf="$(
    PATH=''
    source "$TQS_DIR/tqueuestack.sh" 2>/dev/null
    TQueue.new Z; TObjectStack.new ZS false
    Z.Count >/dev/null; a="$RESULT"
    b="$(ZS.owns_objects)"
    Z.delete; ZS.delete
    printf '%s|%s' "$a" "$b"
)"
[[ "$zf" == "0|false" ]] && kt_test_pass "$zf" || kt_test_fail "PATH='' got '$zf'"

kt_test_log "001_Skeleton.sh completed"
