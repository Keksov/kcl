#!/bin/bash
# 018_CustomSort.sh - TList.CustomSort (roadmap follow-up): the previously-stub
# method now delegates the in-place [0,count) sort to TArray.sort with a
# caller-supplied comparator (TArray cmpFn protocol: rc 0=a<b / 1=a==b / 2=a>b),
# exactly as FPC generics TList<T>.Sort delegates to TArrayHelper.Sort.
# Raw TList has no public indexed Get (subclass stub), so results are read from
# the instance's ${inst}_items array + First/Last/IndexOf.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"
source "$SCRIPT_DIR/../tlist.sh"

TEST_NAME="$(basename "$0" .sh)"
kt_test_init "$TEST_NAME" "$SCRIPT_DIR" "$@"

kt_test_section "018: TList.Sort / CustomSort (delegate to TArray.sort)"

bylen(){ (( ${#1} < ${#2} )) && return 0; (( ${#1} == ${#2} )) && return 1; return 2; }
bybyte(){ local a="$1" b="$2"; local LC_ALL=C; [[ "$a" < "$b" ]] && return 0; [[ "$a" == "$b" ]] && return 1; return 2; }
items_of(){ local -n __a="${1}_items"; echo "${__a[*]}"; }
item_at(){ local -n __a="${1}_items"; echo "${__a[$2]}"; }

# --- TList.Sort (no-arg) = default BYTE-order sort (bash convenience; NOT in
#     FPC Classes.TList — a raw TList holds strings, so byte order is natural,
#     symmetric with TArray.sort's no-arg default). TStringList overrides it.
kt_test_start "TList.Sort (no-arg) sorts byte-order (upper<lower)"
TList.new L; for x in banana Apple cherry Banana; do L.Add "$x"; done
L.Sort
[[ "$(items_of L)" == "Apple Banana banana cherry" ]] && kt_test_pass "$(items_of L)" || kt_test_fail "got $(items_of L)"
L.delete

kt_test_start "TList.Sort (no-arg): empty rc0, single intact"
TList.new E; E.Sort; re=$?
TList.new S; S.Add "only"; S.Sort
[[ $re -eq 0 && "$(E.count)" == "0" && "$(items_of S)" == "only" ]] \
    && kt_test_pass "empty rc0, single intact" || kt_test_fail "re=$re E=$(E.count) S=[$(items_of S)]"
E.delete; S.delete

# --- sort by a custom comparator (length) ---
kt_test_start "CustomSort by length"
TList.new L; for x in ccc a dddd bb; do L.Add "$x"; done
L.CustomSort bylen
[[ "$(items_of L)" == "a bb ccc dddd" ]] && kt_test_pass "$(items_of L)" || kt_test_fail "got $(items_of L)"
L.delete

# --- sort by byte comparator + First/Last/IndexOf reflect the new order ---
kt_test_start "CustomSort byte-order; First/Last/IndexOf agree"
TList.new L; for x in banana apple cherry; do L.Add "$x"; done
L.CustomSort bybyte
L.First; f=$RESULT; L.Last; l=$RESULT; L.IndexOf "banana"; ib=$RESULT
[[ "$(items_of L)" == "apple banana cherry" && "$f" == "apple" && "$l" == "cherry" && "$ib" == "1" ]] \
    && kt_test_pass "sorted; First=apple Last=cherry banana@1" \
    || kt_test_fail "items=[$(items_of L)] First=$f Last=$l banana@$ib"
L.delete

# --- count preserved; empty comparator rejected ---
kt_test_start "count preserved; missing comparator -> rc 1, unchanged"
TList.new L; for x in 3 1 2; do L.Add "$x"; done
before="$(items_of L)"
L.CustomSort ""; rc=$?
[[ $rc -eq 1 && "$(items_of L)" == "$before" && "$(L.count)" == "3" ]] \
    && kt_test_pass "rc 1, unchanged, count 3" || kt_test_fail "rc=$rc items=[$(items_of L)]"
L.delete

# --- stability: equal-key elements keep input order ---
kt_test_start "stable: equal comparator keys keep input order"
byfirst(){ local x="${1:0:1}" y="${2:0:1}"; [[ "$x" < "$y" ]] && return 0; [[ "$x" == "$y" ]] && return 1; return 2; }
TList.new L; for x in b1 a1 b2 a2 c1 a3; do L.Add "$x"; done
L.CustomSort byfirst
[[ "$(items_of L)" == "a1 a2 a3 b1 b2 c1" ]] && kt_test_pass "$(items_of L)" || kt_test_fail "got $(items_of L)"
L.delete

# --- edges: empty / single (no crash, no-op) ---
kt_test_start "edges: empty and single-element lists"
TList.new E; E.CustomSort bylen; re=$?
TList.new S; S.Add "only"; S.CustomSort bylen
[[ $re -eq 0 && "$(E.count)" == "0" && "$(items_of S)" == "only" ]] \
    && kt_test_pass "empty rc0/count0, single intact" || kt_test_fail "re=$re Ecount=$(E.count) S=[$(items_of S)]"
E.delete; S.delete

# --- torture: exotic elements sort losslessly ---
kt_test_start "torture: newline/glob/space elements lossless"
TList.new L; L.Add $'z\nz'; L.Add '* x'; L.Add 'a'
L.CustomSort bybyte
if [[ "$(item_at L 0)" == '* x' && "$(item_at L 1)" == 'a' && "$(item_at L 2)" == $'z\nz' ]]; then
    kt_test_pass "lossless byte-order"
else
    kt_test_fail "got [$(item_at L 0)][$(item_at L 1)][$(item_at L 2)]"
fi
L.delete

kt_test_log "018_CustomSort.sh completed"
