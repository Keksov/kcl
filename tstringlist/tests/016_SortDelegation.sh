#!/bin/bash
# 016_SortDelegation.sh - pins the TStringList.Sort -> TArray.sort delegation
# (roadmap follow-up). The existing 001-015 suites already prove byte-identical
# Sort/CompareStrings output; this file adds what they lacked: STABILITY on
# fold-equal-but-textually-different elements (the parity-critical property of
# swapping the stable bubble sort for a stable mergesort), the inherited
# TList.CustomSort on a TStringList (read via the real Get), and a larger-list
# correctness check (the case that was O(n^2) before).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"
source "$SCRIPT_DIR/../tstringlist.sh"

TEST_NAME="$(basename "$0" .sh)"
kt_test_init "$TEST_NAME" "$SCRIPT_DIR" "$@"

kt_test_section "016: TStringList.Sort delegation (stability + inherited CustomSort)"

joinget(){ local L="$1" n i out=""; n=$($L.count); for (( i=0; i<n; i++ )); do out+="$($L.Get $i)|"; done; echo "$out"; }

# --- STABILITY: case-insensitive Sort of fold-equal, textually-different items
# keeps INPUT order (all fold to "apple" -> stable sort must not reorder them).
kt_test_start "stable: fold-equal items keep input order (insensitive)"
TStringList.new L
for x in apple Apple APPLE aPPle; do L.Add "$x"; done   # all == under fold
L.Sort
[[ "$(joinget L)" == "apple|Apple|APPLE|aPPle|" ]] && kt_test_pass "input order preserved" \
    || kt_test_fail "got $(joinget L)"
L.delete

# --- STABILITY within groups: mixed keys, equal-fold neighbours keep order ---
kt_test_start "stable: within-key order kept across distinct keys"
TStringList.new L
for x in Bravo bravo Alpha alpha Bravo2 ; do L.Add "$x"; done
# fold keys: bravo,bravo,alpha,alpha,bravo2 -> sorted keys: alpha,alpha,bravo,bravo,bravo2
# stable -> Alpha,alpha (input order), Bravo,bravo (input order), Bravo2
L.Sort
[[ "$(joinget L)" == "Alpha|alpha|Bravo|bravo|Bravo2|" ]] && kt_test_pass "$(joinget L)" \
    || kt_test_fail "got $(joinget L)"
L.delete

# --- inherited TList.CustomSort works on a TStringList (read via real Get) ---
kt_test_start "inherited CustomSort by length (real Get reads result)"
bylen(){ (( ${#1} < ${#2} )) && return 0; (( ${#1} == ${#2} )) && return 1; return 2; }
TStringList.new L
for x in ccc a dddd bb; do L.Add "$x"; done
L.CustomSort bylen
[[ "$(joinget L)" == "a|bb|ccc|dddd|" ]] && kt_test_pass "$(joinget L)" || kt_test_fail "got $(joinget L)"
L.delete

# --- larger-list correctness (was O(n^2) bubble; now O(n log n) merge) ---
kt_test_start "50-element sort is fully ordered (case-insensitive)"
TStringList.new L
# deterministic pseudo-shuffle of item_00..item_49 via an LCG index scramble
x=7
for (( k=0; k<50; k++ )); do
    x=$(( (x*1103515245 + 12345) & 0x7fffffff ))
    printf -v tag 'item_%02d' "$(( x % 100 ))"
    L.Add "$tag"
done
L.Sort
ok=1; prev=""
n=$(L.count)
for (( i=0; i<n; i++ )); do
    cur="$(L.Get $i)"
    [[ -n "$prev" && "$prev" > "$cur" ]] && { ok=0; break; }
    prev="$cur"
done
[[ $ok -eq 1 && "$n" == "50" ]] && kt_test_pass "50 items non-decreasing" || kt_test_fail "not ordered at $i (n=$n)"
L.delete

# --- Sort still sets sorted=true and Find still works over the delegated sort ---
kt_test_start "post-delegation: sorted flag + Find hit/miss intact"
TStringList.new L
for x in cherry apple banana; do L.Add "$x"; done
L.Sort
sf=$(L.sorted)
L.Find "banana" >/dev/null; hit=$RESULT
L.Find "aardvark" >/dev/null; miss=$RESULT
[[ "$sf" == "true" && "$hit" == "1" && "$miss" == "-1" ]] \
    && kt_test_pass "sorted=true, Find banana@1, miss -1" || kt_test_fail "sf=$sf hit=$hit miss=$miss"
L.delete

kt_test_log "016_SortDelegation.sh completed"
