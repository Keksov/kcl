#!/bin/bash
# 002_FpcParity.sh - FPC-TRACEABLE cross-checks: the 9 fpcunit tests of
#   packages/fcl-base/tests/utcobjectlist.pp
# adapted to bash: TObject instances -> kklass instances (TList handles),
# the TMyObject(:TObject) subclass -> TStringList(:TList) for FindInstanceOf,
# TMyObject.IsFreed destructor flag -> dispatcher-liveness (declare -F
# "$h.delete"), L.Items[i] -> L.Get i. Each case cites its FPC procedure.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

TOL_DIR="$SCRIPT_DIR/.."
source "$TOL_DIR/../tstringlist/tstringlist.sh"   # TStringList for FindInstanceOf's subclass role
source "$TOL_DIR/tobjectlist.sh"

TEST_NAME="$(basename "$0" .sh)"
kt_test_init "$TEST_NAME" "$SCRIPT_DIR" "$@"

kt_test_section "002: FPC TObjectList parity (utcobjectlist.pp)"

alive() { declare -F "$1.delete" >/dev/null 2>&1; }

# --- TObjectList_TestCreate: count 0, OwnsObjects true by default ---
kt_test_start "FPC TestCreate: count 0, OwnsObjects default true"
TObjectList.new L
[[ "$(L.count)" == "0" && "$(L.owns_objects)" == "true" ]] && kt_test_pass "0 / true" \
    || kt_test_fail "count=$(L.count) owns=$(L.owns_objects)"
L.delete

# --- TObjectList_TestAdd (Create(False)): count + Items[i] identity ---
kt_test_start "FPC TestAdd: count 1 then 2; Items[0]=O1, Items[1]=O2"
TList.new O1; TList.new O2
TObjectList.new L false
L.Add O1 >/dev/null; c1="$(L.count)"
L.Add O2 >/dev/null; c2="$(L.count)"
L.Get 0; g0=$RESULT; L.Get 1; g1=$RESULT
[[ "$c1" == "1" && "$c2" == "2" && "$g0" == "O1" && "$g1" == "O2" ]] \
    && kt_test_pass "1/2, O1/O2" || kt_test_fail "c=$c1/$c2 items=$g0/$g1"
L.delete; O1.delete; O2.delete

# --- TObjectList_TestExtract: extracted==O1, count 1, Items[0]==O2 ---
kt_test_start "FPC TestExtract: returns O1; count 1; first is O2; O1 alive"
TList.new O1; TList.new O2
TObjectList.new L false
L.Add O1 >/dev/null; L.Add O2 >/dev/null
L.Extract O1; ex=$RESULT
L.Get 0; g0=$RESULT
if [[ "$ex" == "O1" && "$(L.count)" == "1" && "$g0" == "O2" ]] && alive O1; then
    kt_test_pass "extracted O1 (alive), list=[O2]"
else
    kt_test_fail "ex=$ex count=$(L.count) g0=$g0 alive=$(alive O1 && echo y || echo n)"
fi
L.delete; O1.delete; O2.delete

# --- TObjectList_TestRemove: count 1, Items[0]==O2 ---
kt_test_start "FPC TestRemove: count 1 after remove; first is O2"
TList.new O1; TList.new O2
TObjectList.new L false
L.Add O1 >/dev/null; L.Add O2 >/dev/null
L.Remove O1
L.Get 0; g0=$RESULT
if [[ "$(L.count)" == "1" && "$g0" == "O2" ]] && alive O1; then
    kt_test_pass "removed, O1 alive (non-owning), list=[O2]"
else
    kt_test_fail "count=$(L.count) g0=$g0 alive=$(alive O1 && echo y || echo n)"
fi
L.delete; O1.delete; O2.delete

# --- TObjectList_TestIndexOf: 0 / 1 / -1 ---
kt_test_start "FPC TestIndexOf: O1->0, O2->1, non-added O3->-1"
TList.new O1; TList.new O2; TList.new O3
TObjectList.new L false
L.Add O1 >/dev/null; L.Add O2 >/dev/null
L.IndexOf O1; i1=$RESULT
L.IndexOf O2; i2=$RESULT
L.IndexOf O3; i3=$RESULT
[[ "$i1" == "0" && "$i2" == "1" && "$i3" == "-1" ]] && kt_test_pass "0/1/-1" \
    || kt_test_fail "$i1/$i2/$i3"
L.delete; O1.delete; O2.delete; O3.delete

# --- TObjectList_TestFindInstanceOf: exact + inexact over a subclass pair ---
# FPC pair: O1:TObject, C1:TMyObject(:TObject). Bash pair: O1:TList,
# C1:TStringList(:TList) — same shape.
kt_test_start "FPC TestFindInstanceOf: exact/inexact over TList+TStringList"
TList.new O1; TStringList.new C1
TObjectList.new L false
L.Add O1 >/dev/null; L.Add C1 >/dev/null
L.FindInstanceOf TList;              f1=$RESULT   # exact TObject -> 0
L.FindInstanceOf TStringList;        f2=$RESULT   # exact TMyObject -> 1
L.FindInstanceOf TList false;        f3=$RESULT   # inexact TObject -> 0
L.FindInstanceOf TStringList false;  f4=$RESULT   # inexact TMyObject -> 1
L.FindInstanceOf TList false 1;      f5=$RESULT   # is-a beyond exact: C1 is-a TList -> 1
[[ "$f1$f2$f3$f4$f5" == "01011" ]] && kt_test_pass "0/1/0/1 + is-a from 1 -> 1" \
    || kt_test_fail "$f1/$f2/$f3/$f4/$f5"
L.delete; O1.delete; C1.delete

# --- TObjectList_TestInsert: count 3, Items[1]=O3, Items[2]=O2 ---
kt_test_start "FPC TestInsert: insert at 1; count 3; [1]=O3 [2]=O2"
TList.new O1; TList.new O2; TList.new O3
TObjectList.new L false
L.Add O1 >/dev/null; L.Add O2 >/dev/null
L.Insert 1 O3
L.Get 1; g1=$RESULT; L.Get 2; g2=$RESULT
[[ "$(L.count)" == "3" && "$g1" == "O3" && "$g2" == "O2" ]] && kt_test_pass "3, O3@1, O2@2" \
    || kt_test_fail "count=$(L.count) g1=$g1 g2=$g2"
L.delete; O1.delete; O2.delete; O3.delete

# --- TObjectList_TestFirstLast ---
kt_test_start "FPC TestFirstLast: First=O1, Last=O2"
TList.new O1; TList.new O2
TObjectList.new L false
L.Add O1 >/dev/null; L.Add O2 >/dev/null
L.First; f=$RESULT; L.Last; l=$RESULT
[[ "$f" == "O1" && "$l" == "O2" ]] && kt_test_pass "O1 / O2" || kt_test_fail "$f / $l"
L.delete; O1.delete; O2.delete

# --- TObjectList_TestOwnsObjects: Create(True) + Free frees the element ---
kt_test_start "FPC TestOwnsObjects: owning list.delete frees the element"
TList.new O1
TObjectList.new L true
L.Add O1 >/dev/null
L.delete
if alive O1; then kt_test_fail "O1 survived an owning delete"; O1.delete
else kt_test_pass "O1 freed by the owning list's delete"; fi

kt_test_log "002_FpcParity.sh completed"
