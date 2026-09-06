#!/bin/bash
# 021_ReviewP2.sh — regressions for the 2026-09-06 review, phase P2 (containers).
# Findings pinned here (each was RED on the pre-fix code):
#
#   G1-01  `${inst}_items` survives `.delete` — TList declares no destructor, so
#          every deleted list leaks a global array with its full contents and a
#          later instance reusing the name starts out pre-populated.
#   G1-06  TList.Add returned the new COUNT; FPC (and docs/TList.md, and
#          TStringList.Add) return the INDEX of the added item (decision R1).
#   G1-09  the capacity setter accepted negatives and values < count: silent
#          truncation / corrupt state (FPC raises EListError) — decision R2:
#          rc 1 and the list is left exactly as it was.
#   G1-18  Clear did O(n) work twice; it must still leave an empty, dense list.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

TLIST_DIR="$SCRIPT_DIR/.."
source "$TLIST_DIR/tlist.sh"

TEST_NAME="$(basename "$0" .sh)"
kt_test_init "$TEST_NAME" "$SCRIPT_DIR" "$@"

kt_test_section "021: review 2026-09-06 P2 — destructor, Add index, capacity guard"

# --- G1-01: the destructor frees ${inst}_items -----------------------------
kt_test_start "delete frees \${inst}_items [G1-01]"
TList.new L
L.Add x; L.Add y
L.delete
if declare -p L_items >/dev/null 2>&1; then
    kt_test_fail "L_items survived .delete: $(declare -p L_items)"
else
    kt_test_pass "L_items is gone"
fi

kt_test_start "a new instance reusing the name starts empty [G1-01]"
TList.new L
L.Add a; L.Add b; L.Add c
L.delete
TList.new L
n="$(L.count)"
len="${#L_items[@]}"
L.delete
[[ "$n" == "0" && "$len" == "0" ]] && kt_test_pass "count 0, storage empty" \
    || kt_test_fail "count=$n storage=$len (stale contents inherited)"

# --- G1-06 / R1: Add returns the INDEX ------------------------------------
kt_test_start "Add returns the index of the added item, not the new count [G1-06, R1]"
TList.new L
RESULT="sentinel"
L.Add first;  i0="$RESULT"
L.Add second; i1="$RESULT"
L.Add third;  i2="$RESULT"
[[ "$i0" == "0" && "$i1" == "1" && "$i2" == "2" ]] \
    && kt_test_pass "0 1 2" || kt_test_fail "got $i0 $i1 $i2 (expected 0 1 2)"

kt_test_start "the same index comes back through \$( ) [G1-06, R1]"
c="$(L.Add fourth)"
[[ "$c" == "3" ]] && kt_test_pass "3" || kt_test_fail "\$(L.Add fourth) = '$c' (expected 3)"

kt_test_start "the returned index addresses the item that was just added [G1-06]"
L.Clear
L.Add alpha; idx="$RESULT"
L.Get "$idx"
[[ "$RESULT" == "alpha" ]] && kt_test_pass "Get $idx -> alpha" \
    || kt_test_fail "Get $idx -> '$RESULT'"
L.delete

# --- G1-09 / R2: the capacity setter ---------------------------------------
kt_test_start "capacity < count is refused and changes nothing [G1-09, R2]"
TList.new L
for v in a b c d e; do L.Add "$v"; done
cap_before="$(L.capacity)"
L.capacity = 2 2>/dev/null; rc=$?
items="${L_items[*]}"
[[ $rc -eq 1 && "$(L.count)" == "5" && "$(L.capacity)" == "$cap_before" && "$items" == "a b c d e" ]] \
    && kt_test_pass "rc=1, count 5, capacity $cap_before, items intact" \
    || kt_test_fail "rc=$rc count=$(L.count) capacity=$(L.capacity) items='$items'"

kt_test_start "a negative capacity is refused and changes nothing [G1-09, R2]"
L.capacity = -3 2>/dev/null; rc=$?
items="${L_items[*]}"
[[ $rc -eq 1 && "$(L.count)" == "5" && "$(L.capacity)" == "$cap_before" && "$items" == "a b c d e" ]] \
    && kt_test_pass "rc=1, state unchanged" \
    || kt_test_fail "rc=$rc count=$(L.count) capacity=$(L.capacity) items='$items'"

kt_test_start "capacity == count and capacity > count are accepted [G1-09, R2]"
L.capacity = 5; rc1=$?; c1="$(L.capacity)"
L.capacity = 40; rc2=$?; c2="$(L.capacity)"
[[ $rc1 -eq 0 && "$c1" == "5" && $rc2 -eq 0 && "$c2" == "40" && "$(L.count)" == "5" ]] \
    && kt_test_pass "5 then 40, count still 5" \
    || kt_test_fail "rc1=$rc1 c1=$c1 rc2=$rc2 c2=$c2 count=$(L.count)"

kt_test_start "capacity = 0 on an empty list is still accepted [G1-09, R2]"
L.Clear
L.capacity = 0; rc=$?
[[ $rc -eq 0 && "$(L.capacity)" == "0" ]] && kt_test_pass "rc=0 capacity=0" \
    || kt_test_fail "rc=$rc capacity=$(L.capacity)"
L.delete

# --- G1-18: Clear ----------------------------------------------------------
kt_test_start "Clear empties the storage array itself, not only the counters [G1-18]"
TList.new L
for v in a b c d; do L.Add "$v"; done
L.Clear
n="$(L.count)"; cap="$(L.capacity)"; len="${#L_items[@]}"
[[ "$n" == "0" && "$cap" == "0" && "$len" == "0" ]] \
    && kt_test_pass "count 0, capacity 0, 0 stored elements" \
    || kt_test_fail "count=$n capacity=$cap stored=$len"

kt_test_start "a list stays usable after Clear [G1-18]"
L.Add again; idx="$RESULT"
L.Get 0
[[ "$idx" == "0" && "$RESULT" == "again" && "$(L.count)" == "1" ]] \
    && kt_test_pass "Add after Clear -> index 0" \
    || kt_test_fail "idx=$idx RESULT='$RESULT' count=$(L.count)"
L.delete

kt_test_log "021_ReviewP2.sh completed"
