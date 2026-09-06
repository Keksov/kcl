#!/bin/bash
# 005_ReviewP2.sh — regressions for the 2026-09-06 review, phase P2.
#
#   G1-01  TObjectList.Destroy freed the elements but not `${inst}_items`, and
#          did not chain to the parent destructor at all.
#   G1-07a `L.count = N` shrinking an OWNING list dropped the handles without
#          freeing them (FPC SetCount -> Delete -> Notify(lnDeleted) -> Free).
#   G1-07b `L.capacity = N` below count dropped elements alive (now rc 1 and
#          unchanged, decision R2 — no element can be lost this way any more).
#   G1-07c the inherited TList.Assign stub called the virtual Clear FIRST, so on
#          an owning list it freed every element and then returned "not
#          implemented": rc 1 with the data destroyed.
#   G1-16  boolean tokens were loose: `owns_objects = yes` silently produced a
#          NON-owning list, and `FindInstanceOf TList no` silently meant exact.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

TOL_DIR="$SCRIPT_DIR/.."
source "$TOL_DIR/tobjectlist.sh"

TEST_NAME="$(basename "$0" .sh)"
kt_test_init "$TEST_NAME" "$SCRIPT_DIR" "$@"

kt_test_section "005: review 2026-09-06 P2 — destructor chain, shrink paths, boolean tokens"

alive() { declare -F "$1.delete" >/dev/null 2>&1; }
state() { alive "$1" && printf alive || printf freed; }

# --- G1-01: the destructor chain -------------------------------------------
kt_test_start "delete frees \${inst}_items on an owning list [G1-01]"
TList.new e1; TList.new e2
TObjectList.new L
L.Add e1; L.Add e2
L.delete
if declare -p L_items >/dev/null 2>&1; then
    kt_test_fail "L_items survived .delete: $(declare -p L_items)"
else
    kt_test_pass "L_items is gone"
fi

kt_test_start "the elements are still freed once Destroy chains to the parent [G1-01]"
[[ "$(state e1) $(state e2)" == "freed freed" ]] && kt_test_pass "both freed" \
    || kt_test_fail "e1=$(state e1) e2=$(state e2)"

kt_test_start "delete frees \${inst}_items on a NON-owning list too [G1-01]"
TList.new k1
TObjectList.new N false
N.Add k1
N.delete
if declare -p N_items >/dev/null 2>&1; then
    kt_test_fail "N_items survived .delete"
else
    alive k1 && kt_test_pass "storage gone, element left alive (non-owning)" \
              || kt_test_fail "non-owning list freed its element"
fi
alive k1 && k1.delete

# --- G1-07a: count shrink frees the dropped elements ------------------------
kt_test_start "count = N shrinking an owning list frees the dropped elements [G1-07a]"
TList.new o1; TList.new o2; TList.new o3
TObjectList.new L
L.Add o1; L.Add o2; L.Add o3
L.count = 1; rc=$?
[[ $rc -eq 0 && "$(L.count)" == "1" && "$(state o1)" == "alive" \
   && "$(state o2)" == "freed" && "$(state o3)" == "freed" ]] \
    && kt_test_pass "o1 alive, o2/o3 freed, count 1" \
    || kt_test_fail "rc=$rc count=$(L.count) o1=$(state o1) o2=$(state o2) o3=$(state o3)"
L.delete

kt_test_start "count = N on a NON-owning list drops without freeing [G1-07a]"
TList.new p1; TList.new p2
TObjectList.new N false
N.Add p1; N.Add p2
N.count = 1
[[ "$(N.count)" == "1" && "$(state p1)" == "alive" && "$(state p2)" == "alive" ]] \
    && kt_test_pass "both alive, count 1" \
    || kt_test_fail "count=$(N.count) p1=$(state p1) p2=$(state p2)"
N.delete
alive p2 && p2.delete

kt_test_start "count = N growing an owning list pads and frees nothing [G1-07a]"
TList.new g1
TObjectList.new L
L.Add g1
L.count = 3; rc=$?
[[ $rc -eq 0 && "$(L.count)" == "3" && "$(state g1)" == "alive" ]] \
    && kt_test_pass "count 3, element alive" \
    || kt_test_fail "rc=$rc count=$(L.count) g1=$(state g1)"
L.count = 1
L.delete

# --- G1-07b: capacity below count is refused (R2), so nothing leaks ---------
kt_test_start "capacity < count is refused; no element is dropped or leaked [G1-07b, R2]"
TList.new c1; TList.new c2
TObjectList.new L
L.Add c1; L.Add c2
L.capacity = 1 2>/dev/null; rc=$?
[[ $rc -eq 1 && "$(L.count)" == "2" && "$(state c1)" == "alive" && "$(state c2)" == "alive" ]] \
    && kt_test_pass "rc=1, count 2, both alive" \
    || kt_test_fail "rc=$rc count=$(L.count) c1=$(state c1) c2=$(state c2)"
L.delete

# --- G1-07c: the Assign stub must not destroy the list ----------------------
kt_test_start "the unimplemented Assign leaves an owning list untouched [G1-07c]"
TList.new a1; TList.new a2
TObjectList.new L
L.Add a1; L.Add a2
TList.new src
L.Assign src 2>/dev/null; rc=$?
[[ $rc -eq 1 && "$(L.count)" == "2" && "$(state a1)" == "alive" && "$(state a2)" == "alive" ]] \
    && kt_test_pass "rc=1, count 2, elements alive" \
    || kt_test_fail "rc=$rc count=$(L.count) a1=$(state a1) a2=$(state a2)"
L.delete; src.delete

# --- G1-16: boolean tokens --------------------------------------------------
kt_test_start "owns_objects rejects a non-boolean token and keeps its value [G1-16]"
TObjectList.new L
L.owns_objects = "yes" 2>/dev/null; rc=$?
[[ $rc -eq 2 && "$(L.owns_objects)" == "true" ]] \
    && kt_test_pass "rc=2, still true" || kt_test_fail "rc=$rc owns=$(L.owns_objects)"

kt_test_start "owns_objects still accepts true and false [G1-16]"
L.owns_objects = "false"; r1=$?; v1="$(L.owns_objects)"
L.owns_objects = "true";  r2=$?; v2="$(L.owns_objects)"
[[ $r1 -eq 0 && "$v1" == "false" && $r2 -eq 0 && "$v2" == "true" ]] \
    && kt_test_pass "false then true" || kt_test_fail "r1=$r1 v1=$v1 r2=$r2 v2=$v2"

kt_test_start "a rejected owns_objects token does not silently disown the elements [G1-16]"
TList.new y1
L.Add y1
L.owns_objects = "yes" 2>/dev/null
L.delete
[[ "$(state y1)" == "freed" ]] && kt_test_pass "element freed (list stayed owning)" \
    || { kt_test_fail "y1=$(state y1) — the bad token disowned the list"; alive y1 && y1.delete; }

kt_test_start "FindInstanceOf rejects a non-boolean exact token [G1-16]"
TList.new z1
TObjectList.new L
L.Add z1
RESULT="sentinel"
L.FindInstanceOf TList no 2>/dev/null; rc=$?
[[ $rc -eq 2 ]] && kt_test_pass "rc=2" || kt_test_fail "rc=$rc RESULT='$RESULT' (a bad token was read as exact=true)"

kt_test_start "FindInstanceOf still accepts true/false/omitted [G1-16]"
L.FindInstanceOf TList;       r0=$?; f0="$RESULT"
L.FindInstanceOf TList true;  r1=$?; f1="$RESULT"
L.FindInstanceOf TList false; r2=$?; f2="$RESULT"
[[ $r0 -eq 0 && $r1 -eq 0 && $r2 -eq 0 && "$f0$f1$f2" == "000" ]] \
    && kt_test_pass "0/0/0" || kt_test_fail "r=$r0/$r1/$r2 f=$f0/$f1/$f2"
L.delete

kt_test_log "005_ReviewP2.sh completed"
