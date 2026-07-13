#!/bin/bash
# 002_Sort.sh - TArray.sort: the three comparator modes (default byte-order,
# numeric -n, custom cmpFn), the range form (S8), edge inputs (empty/single/
# all-equal/already-sorted/reversed), and the rejections (associative array,
# non-integer under -n). Sort has NO FPC seed test (the arrayhelper fpcunit has
# none), so basis = the sorted-invariant + hand matrices. Byte order is proven
# via case ordering (LC_ALL=C: 'A'(65) < 'a'(97)).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"
source "$SCRIPT_DIR/../tarray.sh"

TEST_NAME="$(basename "$0" .sh)"
kt_test_init "$TEST_NAME" "$SCRIPT_DIR" "$@"

kt_test_section "002: TArray.sort — modes, range, edges, rejects"

# --- default byte-order (LC_ALL=C: uppercase sorts before lowercase) ---
kt_test_start "byte-order: case-sensitive, upper before lower"
a=(banana Apple cherry Banana apple)
TArray.sort a
[[ "${a[*]}" == "Apple Banana apple banana cherry" ]] && kt_test_pass "${a[*]}" || kt_test_fail "got ${a[*]}"

kt_test_start "byte-order: digits < upper < lower"
a=(z A 9 a Z 0)
TArray.sort a
[[ "${a[*]}" == "0 9 A Z a z" ]] && kt_test_pass "${a[*]}" || kt_test_fail "got ${a[*]}"

# --- numeric -n ---
kt_test_start "numeric: negatives, zero, leading zeros preserved"
b=(10 9 100 -5 007 20 0)
TArray.sort b -n
[[ "${b[*]}" == "-5 0 007 9 10 20 100" ]] && kt_test_pass "${b[*]}" || kt_test_fail "got ${b[*]}"

kt_test_start "numeric: original strings preserved (007 not 7)"
b=(007 7 07)
TArray.sort b -n            # all equal numerically (7) -> stable: input order
[[ "${b[*]}" == "007 7 07" ]] && kt_test_pass "${b[*]}" || kt_test_fail "got ${b[*]}"

kt_test_start "numeric: large 64-bit values"
b=(4611686018427387904 -4611686018427387904 0 1)
TArray.sort b -n
[[ "${b[*]}" == "-4611686018427387904 0 1 4611686018427387904" ]] && kt_test_pass "ok" || kt_test_fail "got ${b[*]}"

# --- custom cmpFn (rc 0/1/2 protocol) ---
kt_test_start "cmpFn: sort by string length"
bylen(){ (( ${#1} < ${#2} )) && return 0; (( ${#1} == ${#2} )) && return 1; return 2; }
c=(ccc a bb dddd e)
TArray.sort c bylen
[[ "${c[*]}" == "a e bb ccc dddd" ]] && kt_test_pass "${c[*]}" || kt_test_fail "got ${c[*]}"

kt_test_start "cmpFn: reverse numeric via comparator"
revnum(){ (( $1 > $2 )) && return 0; (( $1 == $2 )) && return 1; return 2; }
c=(3 1 2 5 4)
TArray.sort c revnum
[[ "${c[*]}" == "5 4 3 2 1" ]] && kt_test_pass "${c[*]}" || kt_test_fail "got ${c[*]}"

# --- range form (S8): only [start, start+count-1] sorted, rest untouched ---
kt_test_start "range: sort [2,4), outside untouched"
r=(9 8 7 3 2 1 5 4)
TArray.sort r -n 2 4
[[ "${r[*]}" == "9 8 1 2 3 7 5 4" ]] && kt_test_pass "${r[*]}" || kt_test_fail "got ${r[*]}"

kt_test_start "range: count<=1 is a no-op"
r=(3 1 2)
TArray.sort r -n 0 1
[[ "${r[*]}" == "3 1 2" ]] && kt_test_pass "no-op" || kt_test_fail "got ${r[*]}"

kt_test_start "range: count clamped to array length"
r=(3 1 2)
TArray.sort r -n 1 99        # count beyond end -> clamp to [1,2]
[[ "${r[*]}" == "3 1 2" ]] && kt_test_pass "clamped" || kt_test_fail "got ${r[*]}"

# --- edge inputs ---
kt_test_start "edges: empty / single / all-equal / sorted / reversed"
e=(); TArray.sort e; r0=$?
s=(z); TArray.sort s
q=(x x x); TArray.sort q
srt=(a b c d); TArray.sort srt
rev=(d c b a); TArray.sort rev
if [[ $r0 -eq 0 && "${#e[@]}" == "0" && "${s[*]}" == "z" && "${q[*]}" == "x x x" \
      && "${srt[*]}" == "a b c d" && "${rev[*]}" == "a b c d" ]]; then
    kt_test_pass "all edge shapes correct"
else
    kt_test_fail "empty=$r0/${#e[@]} single=${s[*]} equal=${q[*]} sorted=${srt[*]} rev=${rev[*]}"
fi

# --- rejections ---
kt_test_start "reject: associative array -> rc 1, no change"
declare -A m=([b]=2 [a]=1)
TArray.sort m
[[ $? -eq 1 ]] && kt_test_pass "assoc rejected rc 1" || kt_test_fail "assoc not rejected"

kt_test_start "reject: non-integer under -n -> rc 1, array unchanged"
bad=(3 1 abc 2)
TArray.sort bad -n
[[ $? -eq 1 && "${bad[*]}" == "3 1 abc 2" ]] && kt_test_pass "rejected, unchanged" \
    || kt_test_fail "rc=$? arr=${bad[*]}"

kt_test_start "reject: missing array name -> rc 2"
TArray.sort ""
[[ $? -eq 2 ]] && kt_test_pass "rc 2" || kt_test_fail "rc=$?"

kt_test_log "002_Sort.sh completed"
