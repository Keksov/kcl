#!/bin/bash
# 006_FpcParity.sh - FPC-TRACEABLE cross-checks. Mined from the FPC seed
#   packages/rtl-generics/tests/tests.generics.arrayhelper.pas
# (the dedicated TArrayHelper fpcunit). Each case cites its FPC procedure and
# uses FPC's own fixtures. NOTE: unlike tregex (whose Delphi TMatch.Index is
# 1-based), FPC's TArray<Integer> is a 0-BASED dynamic array, so IndexOf /
# CandidateIndex / FoundIndex map to our indices with NO adjustment. Integer
# comparisons use TComparer<Integer>.Default -> our `-n` numeric mode. Reverse
# (Test_Reverse) is exercised in the P3 FpcParity extension.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"
source "$SCRIPT_DIR/../tarray.sh"

TEST_NAME="$(basename "$0" .sh)"
kt_test_init "$TEST_NAME" "$SCRIPT_DIR" "$@"

kt_test_section "006: FPC TArrayHelper parity (tests.generics.arrayhelper.pas)"

# FPC fixture: a := TArray<Integer>.Create(1,3,5,7,9,11,13,15,20);
a=(1 3 5 7 9 11 13 15 20)

# --- Test_BinarySearch_Integers ---
# CheckBinarySearch(a,10,False); CheckSearchResult(...,10, 5, -1, CompareResult>0)
kt_test_start "FPC Test_BinarySearch_Integers: 10 -> false, candidate 5, found -1, compare>0"
TArray.binarySearch a 10 -n; rc=$?
if [[ $rc -eq 1 && "$RESULT_CANDIDATE" == "5" && "$RESULT" == "-1" && $RESULT_COMPARE -gt 0 ]]; then
    kt_test_pass "cand 5 / found -1 / cmp>0"
else
    kt_test_fail "rc=$rc cand=$RESULT_CANDIDATE found=$RESULT cmp=$RESULT_COMPARE"
fi

# CheckBinarySearch(a,20,True); CheckSearchResult(...,20, 8, 8, CompareResult=0)
kt_test_start "FPC Test_BinarySearch_Integers: 20 -> true, candidate 8, found 8, compare 0"
TArray.binarySearch a 20 -n; rc=$?
if [[ $rc -eq 0 && "$RESULT_CANDIDATE" == "8" && "$RESULT" == "8" && "$RESULT_COMPARE" == "0" ]]; then
    kt_test_pass "cand 8 / found 8 / cmp 0"
else
    kt_test_fail "rc=$rc cand=$RESULT_CANDIDATE found=$RESULT cmp=$RESULT_COMPARE"
fi

# --- Test_BinarySearch_EmptyArray: nil, 1 -> false, candidate -1, found -1, compare 0
kt_test_start "FPC Test_BinarySearch_EmptyArray: candidate -1, found -1, compare 0"
empty=()
TArray.binarySearch empty 1 -n; rc=$?
if [[ $rc -eq 1 && "$RESULT_CANDIDATE" == "-1" && "$RESULT" == "-1" && "$RESULT_COMPARE" == "0" ]]; then
    kt_test_pass "empty -> -1/-1/0"
else
    kt_test_fail "rc=$rc cand=$RESULT_CANDIDATE found=$RESULT cmp=$RESULT_COMPARE"
fi

# --- Test_IndexOf: IndexOf(a,9)=4 ; IndexOf(a,33)=-1 ---
kt_test_start "FPC Test_IndexOf: 9 -> 4, 33 -> -1"
TArray.indexOf a 9 -n; i1=$RESULT
TArray.indexOf a 33 -n; i2=$RESULT
[[ "$i1" == "4" && "$i2" == "-1" ]] && kt_test_pass "4 / -1" || kt_test_fail "$i1 / $i2"

# --- Test_FirstIndexOf / Test_LastIndexOf on (1,3,5,7,9,11,13,9,20) ---
d=(1 3 5 7 9 11 13 9 20)
kt_test_start "FPC Test_FirstIndexOf: 9 -> 4"
TArray.firstIndexOf d 9 -n; [[ "$RESULT" == "4" ]] && kt_test_pass "4" || kt_test_fail "got $RESULT"
kt_test_start "FPC Test_LastIndexOf: 9 -> 7"
TArray.lastIndexOf d 9 -n; [[ "$RESULT" == "7" ]] && kt_test_pass "7" || kt_test_fail "got $RESULT"

# --- Test_Min / Test_Max: 1 / 20 ; empty -> default -1 ---
kt_test_start "FPC Test_Min: 1 ; empty -> -1"
TArray.min a -n -1; m1=$RESULT
TArray.min empty -n -1; m2=$RESULT
[[ "$m1" == "1" && "$m2" == "-1" ]] && kt_test_pass "1 / -1" || kt_test_fail "$m1 / $m2"

kt_test_start "FPC Test_Max: 20 ; empty -> -1"
TArray.max a -n -1; m1=$RESULT
TArray.max empty -n -1; m2=$RESULT
[[ "$m1" == "20" && "$m2" == "-1" ]] && kt_test_pass "20 / -1" || kt_test_fail "$m1 / $m2"

# --- Test_Contains: 15 -> true, 14 -> false, empty -> false ---
kt_test_start "FPC Test_Contains: 15 true, 14 false, empty false"
TArray.contains a 15 -n; c1=$?
TArray.contains a 14 -n; c2=$?
TArray.contains empty 15 -n; c3=$?
[[ $c1 -eq 0 && $c2 -eq 1 && $c3 -eq 1 ]] && kt_test_pass "true/false/false" || kt_test_fail "$c1/$c2/$c3"

# --- Test_Reverse: Reverse(a,b) -> b[i]=a[len-i-1]; Reverse(a,a) in-place ---
kt_test_start "FPC Test_Reverse: into target + in-place, source-safe"
fa=(1 3 5 7 9 11 13 15 20); fb=()
TArray.reverse fa fb
ok=1; len=${#fa[@]}
for (( i = 0; i < len; i++ )); do [[ "${fb[i]}" == "${fa[len-i-1]}" ]] || ok=0; done
# in-place: reverse a into itself, compare against a saved copy of the original
orig=("${fa[@]}")
TArray.reverse fa fa
for (( i = 0; i < len; i++ )); do [[ "${fa[len-i-1]}" == "${orig[i]}" ]] || ok=0; done
[[ $ok -eq 1 ]] && kt_test_pass "reverse(a,b) + reverse(a,a)" || kt_test_fail "reverse mismatch"

kt_test_log "006_FpcParity.sh completed"
