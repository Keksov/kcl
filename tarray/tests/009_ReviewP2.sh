#!/bin/bash
# 009_ReviewP2.sh — regressions for the 2026-09-06 review, phase P2.
#
#   G1-12  a comparator name that is not a defined function fell through to the
#          RANGE parser: `TArray.sort a myUndefinedCmp` sorted by byte order and
#          reported success, and `TArray.binarySearch a 3 noSuchFn` searched
#          from start="noSuchFn" (= 0) — a typo silently produced a wrong
#          answer instead of an argument error.
#   G1-15  binarySearch never clamped start/count to the array, so a range that
#          overruns it compared against nonexistent elements and returned a
#          candidate index past the end (sort has clamped since P1).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

TARRAY_DIR="$SCRIPT_DIR/.."
source "$TARRAY_DIR/tarray.sh"

TEST_NAME="$(basename "$0" .sh)"
kt_test_init "$TEST_NAME" "$SCRIPT_DIR" "$@"

kt_test_section "009: review 2026-09-06 P2 — comparator validation, binarySearch clamping"

bylen() { (( ${#1} < ${#2} )) && return 0; (( ${#1} == ${#2} )) && return 1; return 2; }

# --- G1-12: an undefined comparator name is an argument error --------------
kt_test_start "sort rejects an undefined comparator name [G1-12]"
declare -a a=(10 9 100)
TArray.sort a myUndefinedCmp 2>/dev/null; rc=$?
[[ $rc -eq 2 && "${a[*]}" == "10 9 100" ]] \
    && kt_test_pass "rc 2, array untouched" || kt_test_fail "rc=$rc array='${a[*]}'"

kt_test_start "sort still accepts -n, a real comparator and a plain range [G1-12]"
declare -a n1=(10 9 100); TArray.sort n1 -n;        r1=$?
declare -a n2=(ccc a dddd bb); TArray.sort n2 bylen; r2=$?
declare -a n3=(d c b a); TArray.sort n3 1 3;         r3=$?
[[ $r1 -eq 0 && "${n1[*]}" == "9 10 100" \
   && $r2 -eq 0 && "${n2[*]}" == "a bb ccc dddd" \
   && $r3 -eq 0 && "${n3[*]}" == "d a b c" ]] \
    && kt_test_pass "-n, cmpFn and range all still work" \
    || kt_test_fail "r=$r1/$r2/$r3 n1='${n1[*]}' n2='${n2[*]}' n3='${n3[*]}'"

kt_test_start "binarySearch rejects an undefined comparator name [G1-12]"
declare -a b=(1 3 5)
RESULT="sentinel"
TArray.binarySearch b 3 noSuchFn 2>/dev/null; rc=$?
[[ $rc -eq 2 ]] && kt_test_pass "rc 2" || kt_test_fail "rc=$rc RESULT='$RESULT' (start='noSuchFn' was read as 0)"

kt_test_start "the scan family rejects an undefined comparator name [G1-12]"
declare -a s=(x y z)
bad=""
TArray.indexOf      s y noSuchFn 2>/dev/null; [[ $? -eq 2 ]] || bad+="indexOf "
TArray.firstIndexOf s y noSuchFn 2>/dev/null; [[ $? -eq 2 ]] || bad+="firstIndexOf "
TArray.lastIndexOf  s y noSuchFn 2>/dev/null; [[ $? -eq 2 ]] || bad+="lastIndexOf "
TArray.contains     s y noSuchFn 2>/dev/null; [[ $? -eq 2 ]] || bad+="contains "
[[ -z "$bad" ]] && kt_test_pass "all four rc 2" || kt_test_fail "accepted by: $bad"

kt_test_start "the scan family still answers with -n and with a real comparator [G1-12]"
declare -a nums=(1 20 3)
TArray.indexOf nums 20 -n; i1=$RESULT
declare -a words=(aa b cccc)
TArray.indexOf words zz bylen; i2=$RESULT     # length 2 == "aa" -> index 0
TArray.contains words b bylen; c1=$?
[[ "$i1" == "1" && "$i2" == "0" && $c1 -eq 0 ]] \
    && kt_test_pass "1 / 0 / present" || kt_test_fail "i1=$i1 i2=$i2 contains=$c1"

kt_test_start "min/max keep their documented [cmp] [default] ambiguity [G1-12]"
# `min arr [cmp] [default]`: the slot after the array is a comparator only when
# it NAMES a function — otherwise it is the default value, which is free-form
# data and can never be rejected. Documented in tarray/README.md.
declare -a e=()
TArray.min e notAFunction; r1=$?; d1=$RESULT
TArray.max e -1; d2=$RESULT
declare -a L=(ccc a dddd)
TArray.min L bylen; m1=$RESULT
[[ "$d1" == "notAFunction" && $r1 -eq 1 && "$d2" == "-1" && "$m1" == "a" ]] \
    && kt_test_pass "default honoured, cmpFn honoured" \
    || kt_test_fail "d1='$d1' rc=$r1 d2='$d2' m1='$m1'"

# --- G1-15: binarySearch clamps its range ----------------------------------
kt_test_start "binarySearch clamps a count that overruns the array [G1-15]"
declare -a c=(1 3 5 7)
TArray.binarySearch c 9 2 10; rc=$?
[[ $rc -eq 1 && "$RESULT" == "-1" && "$RESULT_CANDIDATE" == "3" ]] \
    && kt_test_pass "rc 1, candidate 3 (inside the array)" \
    || kt_test_fail "rc=$rc RESULT=$RESULT candidate=$RESULT_CANDIDATE (must be < 4)"

kt_test_start "binarySearch clamps a negative start [G1-15]"
TArray.binarySearch c 3 -5; rc=$?
[[ $rc -eq 0 && "$RESULT" == "1" ]] \
    && kt_test_pass "rc 0, index 1" || kt_test_fail "rc=$rc RESULT=$RESULT"

kt_test_start "binarySearch on a start beyond the end is a plain miss [G1-15]"
TArray.binarySearch c 3 9; rc=$?
[[ $rc -eq 1 && "$RESULT" == "-1" && "$RESULT_CANDIDATE" == "-1" ]] \
    && kt_test_pass "rc 1, -1/-1" || kt_test_fail "rc=$rc RESULT=$RESULT candidate=$RESULT_CANDIDATE"

kt_test_start "an in-range subrange search is unchanged [G1-15, S2]"
declare -a r=(9 9 9 1 3 5 7)
TArray.binarySearch r 5 -n 3 4; rc=$?
[[ $rc -eq 0 && "$RESULT" == "5" ]] \
    && kt_test_pass "found at 5" || kt_test_fail "rc=$rc RESULT=$RESULT"

kt_test_log "009_ReviewP2.sh completed"
