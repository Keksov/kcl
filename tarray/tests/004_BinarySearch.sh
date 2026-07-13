#!/bin/bash
# 004_BinarySearch.sh - TArray.binarySearch: the TBinarySearchResult contract
# (RESULT=FoundIndex, RESULT_CANDIDATE, RESULT_COMPARE sign) across hit/miss/
# empty, the three comparator modes, the range form, and a sort+search closure
# cross-check. The exact FPC-oracle values live in 006_FpcParity.sh; here we
# probe the surface + the sign/candidate semantics (S2). Basis: FPC impl
# (generics.collections.pas :1225-1292) + a linear-scan oracle.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"
source "$SCRIPT_DIR/../tarray.sh"

TEST_NAME="$(basename "$0" .sh)"
kt_test_init "$TEST_NAME" "$SCRIPT_DIR" "$@"

kt_test_section "004: TArray.binarySearch"

# --- hit: RESULT=index, candidate=index, compare=0, rc 0 ---
kt_test_start "hit: found index + candidate + compare 0"
a=(1 3 5 7 9 11 13 15 20)
TArray.binarySearch a 9 -n; rc=$?
[[ $rc -eq 0 && "$RESULT" == "4" && "$RESULT_CANDIDATE" == "4" && "$RESULT_COMPARE" == "0" ]] \
    && kt_test_pass "found 9 @4" || kt_test_fail "rc=$rc R=$RESULT C=$RESULT_CANDIDATE cmp=$RESULT_COMPARE"

# --- miss: found=-1, candidate=insertion point, compare sign, rc 1 ---
kt_test_start "miss below: candidate 0, compare>0 (array[0]>item)"
TArray.binarySearch a 0 -n; rc=$?
[[ $rc -eq 1 && "$RESULT" == "-1" && "$RESULT_CANDIDATE" == "0" && $RESULT_COMPARE -gt 0 ]] \
    && kt_test_pass "miss 0 -> cand 0" || kt_test_fail "rc=$rc R=$RESULT C=$RESULT_CANDIDATE cmp=$RESULT_COMPARE"

kt_test_start "miss above: candidate last, compare<0 (array[last]<item)"
TArray.binarySearch a 99 -n; rc=$?
[[ $rc -eq 1 && "$RESULT" == "-1" && "$RESULT_CANDIDATE" == "8" && $RESULT_COMPARE -lt 0 ]] \
    && kt_test_pass "miss 99 -> cand 8, cmp<0" || kt_test_fail "rc=$rc C=$RESULT_CANDIDATE cmp=$RESULT_COMPARE"

# --- empty / single ---
kt_test_start "empty: found -1, candidate -1, compare 0, rc 1"
e=(); TArray.binarySearch e 5 -n; rc=$?
[[ $rc -eq 1 && "$RESULT" == "-1" && "$RESULT_CANDIDATE" == "-1" && "$RESULT_COMPARE" == "0" ]] \
    && kt_test_pass "empty result" || kt_test_fail "rc=$rc R=$RESULT C=$RESULT_CANDIDATE cmp=$RESULT_COMPARE"

kt_test_start "single-element hit and miss"
one=(42)
TArray.binarySearch one 42 -n; h=$?; hr=$RESULT
TArray.binarySearch one 7 -n;  m=$?; mr=$RESULT
[[ $h -eq 0 && "$hr" == "0" && $m -eq 1 && "$mr" == "-1" ]] && kt_test_pass "hit@0 / miss -1" \
    || kt_test_fail "hit=$h/$hr miss=$m/$mr"

# --- byte mode (default) + cmpFn mode ---
kt_test_start "byte-mode search on sorted strings"
s=(Apple Banana apple banana cherry)
TArray.binarySearch s banana; r1=$RESULT
TArray.binarySearch s Apple;  r2=$RESULT
TArray.binarySearch s zzz;    r3=$RESULT
[[ "$r1" == "3" && "$r2" == "0" && "$r3" == "-1" ]] && kt_test_pass "banana@3 Apple@0 miss" \
    || kt_test_fail "$r1 $r2 $r3"

kt_test_start "cmpFn-mode search (by length)"
bylen(){ (( ${#1} < ${#2} )) && return 0; (( ${#1} == ${#2} )) && return 1; return 2; }
L=(a bb ccc dddd eeeee)
TArray.binarySearch L xxx bylen; r=$RESULT   # length 3 -> index 2
[[ "$r" == "2" ]] && kt_test_pass "len-3 @2" || kt_test_fail "got $r"

# --- range form: search only within [start,count) ---
kt_test_start "range: search restricted to [3,4)"
# array 9 8 7 | 1 3 5 7 | 99  -> sort-agnostic; search 5 in the sorted middle
r=(0 0 0 1 3 5 7 0)
TArray.binarySearch r 5 -n 3 4; f=$RESULT   # subrange (1 3 5 7) at indices 3..6, 5 is at 5
[[ "$f" == "5" ]] && kt_test_pass "found 5 @5 in range" || kt_test_fail "got $f"

# --- closure: sort then every element is findable at a correct index ---
kt_test_start "closure: sort + binarySearch finds every element"
c=(37 12 99 1 50 3 88 0 -1 7 12 5)
TArray.sort c -n
ok=1; for v in "${c[@]}"; do
    TArray.binarySearch c "$v" -n || { ok=0; break; }
    [[ "${c[$RESULT]}" == "$v" ]] || { ok=0; break; }
done
[[ $ok -eq 1 ]] && kt_test_pass "all elements findable" || kt_test_fail "failed for '$v'"

# --- torture: newline/glob elements, byte order ---
kt_test_start "torture: search string with newline (sorted byte-order)"
t=($'a\na' 'b' 'c')          # already byte-sorted
TArray.binarySearch t $'a\na'; r1=$RESULT
TArray.binarySearch t 'c';     r2=$RESULT
[[ "$r1" == "0" && "$r2" == "2" ]] && kt_test_pass "newline elem @0, c @2" || kt_test_fail "$r1 $r2"

# --- missing array name -> rc 2 ---
kt_test_start "missing array name -> rc 2"
TArray.binarySearch "" 5; [[ $? -eq 2 ]] && kt_test_pass "rc 2" || kt_test_fail "rc=$?"

kt_test_log "004_BinarySearch.sh completed"
