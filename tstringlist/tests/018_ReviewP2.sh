#!/bin/bash
# 018_ReviewP2.sh — regressions for the 2026-09-06 review, phase P2.
#
#   G1-01  `${inst}_items` survived `.delete` (TList had no destructor).
#   G1-03  the Duplicates policy was enforced on UNSORTED lists (FPC applies it
#          only when Sorted) and every Add ran a full kklass-dispatched IndexOf:
#          300 Adds took 16.6 s against 0.12 s for TList (136x).
#   G1-04  `sorted = true` on a populated list did not sort it, so Find/Add then
#          searched unsorted data (FPC SetSorted(True) sorts).
#   G1-05  a dupIgnore Add returned the CALLER's stale RESULT instead of the
#          existing index (the explicit-`return` trailer trap).
#   G1-10  Assign copied items only: a sorted destination silently received
#          unsorted data and kept claiming to be sorted.
#   G1-11  Assign/AddStrings forked once per call (`$($source.count)`) and
#          accepted a nonexistent source with rc 0.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

TSTRINGLIST_DIR="$SCRIPT_DIR/.."
source "$TSTRINGLIST_DIR/tstringlist.sh"

TEST_NAME="$(basename "$0" .sh)"
kt_test_init "$TEST_NAME" "$SCRIPT_DIR" "$@"

kt_test_section "018: review 2026-09-06 P2 — duplicates, sorted setter, Assign, perf"

items_of() { local -n __a="${1}_items"; local IFS='|'; printf '%s' "${__a[*]}"; }
ms() { printf '%s' $(( ${EPOCHREALTIME/./} / 1000 )); }

# --- G1-01 -----------------------------------------------------------------
kt_test_start "delete frees \${inst}_items [G1-01]"
TStringList.new L
L.Add x
L.delete
if declare -p L_items >/dev/null 2>&1; then
    kt_test_fail "L_items survived .delete: $(declare -p L_items)"
else
    kt_test_pass "L_items is gone"
fi

# --- G1-03: Duplicates applies only to SORTED lists (FPC) ------------------
kt_test_start "dupIgnore on an UNSORTED list accepts the duplicate [G1-03, FPC]"
TStringList.new L
L.duplicates = dupIgnore
L.Add a; L.Add a
[[ "$(L.count)" == "2" && "$(items_of L)" == "a|a" ]] \
    && kt_test_pass "count 2" || kt_test_fail "count=$(L.count) items=$(items_of L)"
L.delete

kt_test_start "dupError on an UNSORTED list accepts the duplicate [G1-03, FPC]"
TStringList.new L
L.duplicates = dupError
L.Add a; rc1=$?
L.Add a 2>/dev/null; rc2=$?
[[ $rc1 -eq 0 && $rc2 -eq 0 && "$(L.count)" == "2" ]] \
    && kt_test_pass "rc 0/0, count 2" || kt_test_fail "rc1=$rc1 rc2=$rc2 count=$(L.count)"
L.delete

kt_test_start "dupIgnore on a SORTED list still drops the duplicate [G1-03, FPC]"
TStringList.new L
L.sorted = true
L.duplicates = dupIgnore
L.Add b; L.Add a; L.Add b
[[ "$(L.count)" == "2" && "$(items_of L)" == "a|b" ]] \
    && kt_test_pass "count 2, a|b" || kt_test_fail "count=$(L.count) items=$(items_of L)"
L.delete

kt_test_start "dupError on a SORTED list still refuses the duplicate [G1-03, FPC]"
TStringList.new L
L.sorted = true
L.duplicates = dupError
L.Add b; L.Add a
L.Add b 2>/dev/null; rc=$?
[[ $rc -ne 0 && "$(L.count)" == "2" ]] \
    && kt_test_pass "rc=$rc, count 2" || kt_test_fail "rc=$rc count=$(L.count)"
L.delete

# --- G1-04: the sorted setter sorts ----------------------------------------
kt_test_start "sorted = true sorts a populated list [G1-04, FPC SetSorted]"
TStringList.new L
L.Add banana; L.Add apple; L.Add cherry
L.sorted = true
[[ "$(items_of L)" == "apple|banana|cherry" ]] \
    && kt_test_pass "apple|banana|cherry" || kt_test_fail "items=$(items_of L)"

kt_test_start "Find works right after sorted = true [G1-04]"
L.Find apple; f="$RESULT"
[[ "$f" == "0" ]] && kt_test_pass "Find apple -> 0" || kt_test_fail "Find apple -> $f"

kt_test_start "a sorted Add after sorted = true lands in order [G1-04]"
L.Add aardvark
[[ "$(items_of L)" == "aardvark|apple|banana|cherry" ]] \
    && kt_test_pass "aardvark|apple|banana|cherry" || kt_test_fail "items=$(items_of L)"
L.delete

kt_test_start "sorted = false does not reorder anything [G1-04]"
TStringList.new L
L.Add pear; L.Add fig
L.sorted = false
[[ "$(items_of L)" == "pear|fig" && "$(L.sorted)" == "false" ]] \
    && kt_test_pass "order kept" || kt_test_fail "items=$(items_of L) sorted=$(L.sorted)"
L.delete

kt_test_start "sorted = true on an already sorted list is a no-op [G1-04]"
TStringList.new L
L.sorted = true
L.Add a; L.Add b
L.sorted = true
[[ "$(items_of L)" == "a|b" && "$(L.sorted)" == "true" ]] \
    && kt_test_pass "a|b" || kt_test_fail "items=$(items_of L)"
L.delete

# --- G1-05: dupIgnore Add returns the existing index ------------------------
kt_test_start "a dupIgnore Add returns the EXISTING index, not the caller's RESULT [G1-05]"
TStringList.new L
L.sorted = true
L.duplicates = dupIgnore
L.Add a; L.Add b
RESULT="SENTINEL"
L.Add b
[[ "$RESULT" == "1" ]] && kt_test_pass "RESULT=1" \
    || kt_test_fail "RESULT='$RESULT' (expected 1, the index of the existing b)"

kt_test_start "the same index comes back through \$( ) [G1-05]"
c="$(L.Add b)"
[[ "$c" == "1" ]] && kt_test_pass "1" || kt_test_fail "captured '$c'"
L.delete

# --- G1-10: Assign copies the flags ----------------------------------------
kt_test_start "Assign copies sorted/case_sensitive/duplicates from the source [G1-10, FPC]"
TStringList.new S
S.case_sensitive = true
S.duplicates = dupError
S.Add b; S.Add a
TStringList.new D
D.sorted = true
D.Assign S
[[ "$(D.sorted)" == "false" && "$(D.case_sensitive)" == "true" && "$(D.duplicates)" == "dupError" ]] \
    && kt_test_pass "flags copied (sorted false, cs true, dupError)" \
    || kt_test_fail "sorted=$(D.sorted) cs=$(D.case_sensitive) dup=$(D.duplicates)"

kt_test_start "a destination is never left claiming sorted over unsorted data [G1-10]"
[[ "$(items_of D)" == "b|a" ]] && kt_test_pass "items b|a, sorted flag false" \
    || kt_test_fail "items=$(items_of D)"
S.delete; D.delete

kt_test_start "Assign from a SORTED source leaves the destination searchable [G1-10]"
TStringList.new S
S.sorted = true
S.Add pear; S.Add apple; S.Add fig
TStringList.new D
D.Assign S
D.Find apple; f="$RESULT"
[[ "$(D.sorted)" == "true" && "$(items_of D)" == "apple|fig|pear" && "$f" == "0" ]] \
    && kt_test_pass "sorted copy, Find apple -> 0" \
    || kt_test_fail "sorted=$(D.sorted) items=$(items_of D) find=$f"
S.delete; D.delete

# --- G1-11: no forks, and the operand is validated -------------------------
kt_test_start "Assign and AddStrings read the source count without calling it [G1-11]"
# The old bodies read the source count as `$($source.count)` — one FORK per
# call. A marker inside the parent shell cannot see that (the subshell keeps
# it), so the probe is a FILE: the source's `count` wrapper is replaced by one
# that leaves a trace, and a trace surviving the call means the fork path ran.
# The fixed bodies read `${source}_data[count]` by nameref and never touch the
# wrapper at all.
TMPD="$(cd "$(kt_fixture_tmpdir)" && pwd)"
TStringList.new S; S.Add one; S.Add two
TStringList.new D
probe="$TMPD/count_wrapper_called"
rm -f "$probe"
orig_count_wrapper="$(declare -f S.count)"
eval "S.count() { : > '$probe'; printf '2\n'; }"
D.Assign S
called_assign=no; [[ -e "$probe" ]] && called_assign=yes
rm -f "$probe"
D.Clear
D.AddStrings S
called_addstrings=no; [[ -e "$probe" ]] && called_addstrings=yes
rm -f "$probe"
eval "$orig_count_wrapper"          # restore the real wrapper
if [[ "$called_assign" == "no" && "$called_addstrings" == "no" && "$(D.count)" == "2" ]]; then
    kt_test_pass "no wrapper call, no fork, 2 items copied"
else
    kt_test_fail "Assign called the wrapper: $called_assign; AddStrings: $called_addstrings; count=$(D.count)"
fi

kt_test_start "Assign rejects a source that is not a TStringList [G1-11, R5]"
TStringList.new K; K.Add keep
K.Assign no_such_list 2>/dev/null; rc1=$?
TList.new PLAIN; PLAIN.Add x
K.Assign PLAIN 2>/dev/null; rc2=$?
[[ $rc1 -eq 1 && $rc2 -eq 1 && "$(K.count)" == "1" && "$(items_of K)" == "keep" ]] \
    && kt_test_pass "rc 1 twice, target intact" \
    || kt_test_fail "rc1=$rc1 rc2=$rc2 count=$(K.count) items=$(items_of K)"

kt_test_start "AddStrings rejects a nonexistent source instead of returning 0 [G1-11]"
err="$(K.AddStrings no_such_list 2>&1)"; rc=$?
[[ $rc -eq 1 && -z "$err" && "$(K.count)" == "1" ]] \
    && kt_test_pass "rc 1, silent, list intact" \
    || kt_test_fail "rc=$rc stderr='$err' count=$(K.count)"
K.delete; S.delete; D.delete; PLAIN.delete

# --- G1-03 perf gate: 300 Adds < 10x TList ---------------------------------
kt_test_start "300 Adds on a TStringList cost < 10x the same Adds on a TList [G1-03]"
N=300
TList.new PL
t0=$(ms); for (( i = 0; i < N; i++ )); do PL.Add "item$i"; done; t1=$(ms)
base=$(( t1 - t0 )); (( base < 1 )) && base=1
PL.delete
TStringList.new SL
t0=$(ms); for (( i = 0; i < N; i++ )); do SL.Add "item$i"; done; t1=$(ms)
plain=$(( t1 - t0 ))
SL.delete
TStringList.new SS
SS.sorted = true
t0=$(ms); for (( i = 0; i < N; i++ )); do SS.Add "item$i"; done; t1=$(ms)
sortd=$(( t1 - t0 ))
SS.delete
if (( plain < base * 10 && sortd < base * 10 )); then
    kt_test_pass "TList ${base}ms; TStringList unsorted ${plain}ms sorted ${sortd}ms (limit $(( base * 10 ))ms)"
else
    kt_test_fail "TList ${base}ms; TStringList unsorted ${plain}ms sorted ${sortd}ms (limit $(( base * 10 ))ms)"
fi

kt_test_start "a sorted IndexOf is a binary search, not a linear scan [G1-03, FPC]"
TStringList.new SS
SS.sorted = true
for (( i = 0; i < 300; i++ )); do printf -v tag 'item%03d' "$i"; SS.Add "$tag"; done
# look the LAST 20 items up: a linear scan is then worst-case, a binary search
# is not (searching the first 20 would hide the difference).
t0=$(ms); for (( i = 280; i < 300; i++ )); do printf -v tag 'item%03d' "$i"; SS.IndexOf "$tag" >/dev/null; done; t1=$(ms)
io=$(( t1 - t0 ))
t0=$(ms); for (( i = 280; i < 300; i++ )); do printf -v tag 'item%03d' "$i"; SS.Find "$tag" >/dev/null; done; t1=$(ms)
fnd=$(( t1 - t0 )); (( fnd < 1 )) && fnd=1
SS.IndexOf item017; hit="$RESULT"
SS.IndexOf nothere;  miss="$RESULT"
if [[ "$hit" == "17" && "$miss" == "-1" ]] && (( io < fnd * 3 )); then
    kt_test_pass "IndexOf ${io}ms vs Find ${fnd}ms; hit 17, miss -1"
else
    kt_test_fail "IndexOf ${io}ms vs Find ${fnd}ms (limit $(( fnd * 3 ))ms); hit=$hit miss=$miss"
fi
SS.delete

kt_test_log "018_ReviewP2.sh completed"
