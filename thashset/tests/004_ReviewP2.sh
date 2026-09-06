#!/bin/bash
# 004_ReviewP2.sh — regressions for the 2026-09-06 review, phase P2 (the G2
# items of this unit; the set algebra of thashset's own P2 is NOT touched here).
#
#   G2-02  ToArray had no output-name validation: `h.ToArray __ts_it` aliased
#          the unit's own nameref and appended the storage to itself (Count
#          2 -> 4), and an empty or malformed name printed a bash error, filled
#          a throwaway local and returned rc 0 with a count. A rejected output
#          name answers **rc 2** — a malformed CALL, not a value the caller may
#          legitimately try (kcl/README.md 1.2 and 1.7; owner decision
#          2026-09-07 over the rc 1 the review report had suggested).
#   G2-04  Assign accepted ANY instance owning an `_items` variable (decision
#          R5: the class decides). `A.Assign someQueue` rewrote the storage to
#          `([0]=1 [1]=1)` — keys without the `k` prefix, so Contains missed
#          everything the set now claimed to hold.
#   G2-05  ForEach did not validate its callback: one "command not found" per
#          element, rc 0.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

TS_DIR="$SCRIPT_DIR/.."
source "$TS_DIR/thashset.sh"
source "$TS_DIR/../tqueuestack/tqueuestack.sh"    # a non-set instance that has _items

TEST_NAME="$(basename "$0" .sh)"
kt_test_init "$TEST_NAME" "$SCRIPT_DIR" "$@"

kt_test_section "004: review 2026-09-06 P2 — ToArray names, Assign operand, ForEach callback"

# --- G2-02: ToArray output-name validation ---------------------------------
kt_test_start "ToArray refuses the unit's own local name and leaves the set alone [G2-02]"
THashSet.new S
S.Add a; S.Add b
S.ToArray __ts_it 2>/dev/null; rc=$?
S.Count; n=$RESULT
[[ $rc -eq 2 && "$n" == "2" ]] && kt_test_pass "rc 2, count still 2" \
    || kt_test_fail "rc=$rc count=$n (the storage was appended to itself)"

kt_test_start "ToArray refuses the instance's own storage name [G2-02]"
S.ToArray "S_items" 2>/dev/null; rc=$?
S.Count; n=$RESULT
[[ $rc -eq 2 && "$n" == "2" ]] && kt_test_pass "rc 2, count still 2" || kt_test_fail "rc=$rc count=$n"

kt_test_start "ToArray refuses an empty or malformed name, silently [G2-02]"
bad=""
for name in "" "bad name" "1abc" "a-b" "RESULT" "IFS" "__kk_x"; do
    err="$(S.ToArray "$name" 2>&1)"; rc=$?
    [[ $rc -eq 2 ]] || bad+="rc[$name]=$rc "
    [[ -z "$err" ]] || bad+="noise[$name] "
done
S.Count; n=$RESULT
[[ -z "$bad" && "$n" == "2" ]] && kt_test_pass "7 bad names rejected silently with rc 2" \
    || kt_test_fail "$bad count=$n"

kt_test_start "ToArray refuses an associative target [G2-02]"
declare -A assoc_target=()
S.ToArray assoc_target 2>/dev/null; rc=$?
[[ $rc -eq 2 && "${#assoc_target[@]}" == "0" ]] \
    && kt_test_pass "rc 2, target untouched" || kt_test_fail "rc=$rc keys='${!assoc_target[*]}'"

kt_test_start "ToArray still fills a normal array and returns the count [G2-02]"
declare -a out=(stale)
S.ToArray out; rc=$?
[[ $rc -eq 0 && "$RESULT" == "2" && "${#out[@]}" == "2" ]] \
    && kt_test_pass "rc 0, RESULT 2, 2 elements" || kt_test_fail "rc=$rc RESULT=$RESULT len=${#out[@]}"
S.delete

# --- G2-04 / R5: Assign checks the CLASS ------------------------------------
kt_test_start "Assign refuses a TQueue that merely has an _items array [G2-04, R5]"
THashSet.new A
A.Add keep
TQueue.new Q
Q.Enqueue 1; Q.Enqueue 2
A.Assign Q 2>/dev/null; rc=$?
A.Count; n=$RESULT
A.Contains keep; ck=$?
[[ $rc -eq 1 && "$n" == "1" && $ck -eq 0 ]] \
    && kt_test_pass "rc 1, set untouched" || kt_test_fail "rc=$rc count=$n contains-keep=$ck"
Q.delete

kt_test_start "Assign refuses a plain variable name that looks like an instance [G2-04, R5]"
declare -A fake_items=([kx]=1)
A.Assign fake 2>/dev/null; rc1=$?
A.Assign "" 2>/dev/null; rc2=$?
A.Count; n=$RESULT
[[ $rc1 -eq 1 && $rc2 -eq 1 && "$n" == "1" ]] \
    && kt_test_pass "rc 1 twice, set untouched" || kt_test_fail "rc1=$rc1 rc2=$rc2 count=$n"

kt_test_start "Assign still copies from a real THashSet [G2-04, R5]"
THashSet.new B
B.Add p; B.Add q
A.Assign B; rc=$?
A.Count; n=$RESULT
A.Contains p; cp=$?
A.Contains keep; ck=$?
[[ $rc -eq 0 && "$n" == "2" && $cp -eq 0 && $ck -eq 1 ]] \
    && kt_test_pass "rc 0, 2 copied, old gone" || kt_test_fail "rc=$rc n=$n cp=$cp ck=$ck"
A.delete; B.delete

# --- G2-05: ForEach validates its callback ----------------------------------
kt_test_start "ForEach refuses a dangling callback instead of failing per element [G2-05]"
THashSet.new F
F.Add 1; F.Add 2; F.Add 3
err="$(F.ForEach no_such_cb 2>&1)"; rc=$?
[[ $rc -eq 1 && -z "$err" ]] && kt_test_pass "rc 1, no stderr" || kt_test_fail "rc=$rc stderr='$err'"

kt_test_start "ForEach refuses an empty callback [G2-05]"
err="$(F.ForEach "" 2>&1)"; rc=$?
[[ $rc -eq 1 && -z "$err" ]] && kt_test_pass "rc 1, no stderr" || kt_test_fail "rc=$rc stderr='$err'"

kt_test_start "ForEach still visits every element with a real callback [G2-05]"
SEEN=(); cb() { SEEN+=("$1"); }
F.ForEach cb; rc=$?
IFS=$'\n' ss=($(printf '%s\n' "${SEEN[@]}" | LC_ALL=C sort)); unset IFS
[[ $rc -eq 0 && "${ss[*]}" == "1 2 3" ]] && kt_test_pass "1 2 3" || kt_test_fail "rc=$rc seen='${SEEN[*]}'"
F.delete

kt_test_log "004_ReviewP2.sh completed"
