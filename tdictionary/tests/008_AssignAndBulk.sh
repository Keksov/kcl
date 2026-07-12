#!/bin/bash
# 008_AssignAndBulk.sh - Assign + AddPairs (P2.3)
# FPC ref: Create(ACollection) = Create + `for pair in collection do Add(pair)`
# (impl:106-114); a raise mid-loop aborts it — AddPairs mirrors that shape.
# Assign replaces content with a copy of another TDictionary's pairs.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

TDICT_DIR="$SCRIPT_DIR/.."
source "$TDICT_DIR/tdictionary.sh"

TEST_NAME="$(basename "$0" .sh)"
kt_test_init "$TEST_NAME" "$SCRIPT_DIR" "$@"

kt_test_section "008: Assign and AddPairs"

kt_test_start "Assign copies every pair byte-exact (incl. exotic keys/values)"
TDictionary.new src
src.Add plain "value"
src.Add "" "empty-key"
src.Add $'n\nl' $'multi\nline\n'
src.Add '*' 'glob *? [x]'
TDictionary.new dst
dst.Add stale "to-be-replaced"
dst.Assign src
rc=$?
ok=1
[[ $rc -eq 0 && "$(dst.count)" == "4" ]] || ok=0
dst.ContainsKey stale && ok=0
[[ "$(dst.GetItem plain)" == "value" ]] || ok=0
[[ "$(dst.GetItem "")" == "empty-key" ]] || ok=0
dst.GetItem $'n\nl' >/dev/null; [[ "$RESULT" == $'multi\nline\n' ]] || ok=0
[[ "$(dst.GetItem '*')" == 'glob *? [x]' ]] || ok=0
if [[ $ok -eq 1 ]]; then
    kt_test_pass "4 pairs copied, prior content replaced"
else
    kt_test_fail "rc=$rc count=$(dst.count)"
fi

kt_test_start "Assign leaves the SOURCE untouched"
if [[ "$(src.count)" == "4" && "$(src.GetItem plain)" == "value" ]]; then
    kt_test_pass "source intact"
else
    kt_test_fail "source mutated: count=$(src.count)"
fi

kt_test_start "Copies are independent after Assign"
dst.SetItem plain "changed-in-dst"
dst.Remove '*'
if [[ "$(src.GetItem plain)" == "value" && "$(src.count)" == "4" && "$(dst.count)" == "3" ]]; then
    kt_test_pass "mutating the copy does not touch the source"
else
    kt_test_fail "src=$(src.GetItem plain)/$(src.count) dst=$(dst.count)"
fi

kt_test_start "Assign from an EMPTY dictionary empties the destination"
TDictionary.new blank
dst.Assign blank
if [[ "$(dst.count)" == "0" && ${#dst_items[@]} -eq 0 ]]; then
    kt_test_pass "destination emptied"
else
    kt_test_fail "count=$(dst.count)"
fi
blank.delete

kt_test_start "Self-assign is a no-op"
src.Assign src
rc=$?
if [[ $rc -eq 0 && "$(src.count)" == "4" && "$(src.GetItem plain)" == "value" ]]; then
    kt_test_pass "content survives d.Assign d"
else
    kt_test_fail "rc=$rc count=$(src.count)"
fi

kt_test_start "Assign from a non-dictionary source: rc=1, destination untouched"
src.Assign no_such_instance 2>/dev/null
rc=$?
if [[ $rc -eq 1 && "$(src.count)" == "4" ]]; then
    kt_test_pass "invalid source rejected before any mutation"
else
    kt_test_fail "rc=$rc count=$(src.count)"
fi
src.delete; dst.delete

kt_test_start "AddPairs: N pairs in one call"
TDictionary.new bulk
bulk.AddPairs k1 v1 k2 "v 2" "" ev '*' gv
rc=$?
if [[ $rc -eq 0 && "$(bulk.count)" == "4" && "$(bulk.GetItem k2)" == "v 2" \
      && "$(bulk.GetItem "")" == "ev" && "$(bulk.GetItem '*')" == "gv" ]]; then
    kt_test_pass "4 pairs added incl. empty and glob keys"
else
    kt_test_fail "rc=$rc count=$(bulk.count)"
fi

kt_test_start "AddPairs: odd argument count rejected atomically"
bulk.AddPairs lone 2>/dev/null
rc=$?
if [[ $rc -eq 1 && "$(bulk.count)" == "4" ]] && ! bulk.ContainsKey lone; then
    kt_test_pass "nothing added on odd argc"
else
    kt_test_fail "rc=$rc count=$(bulk.count)"
fi

kt_test_start "AddPairs: duplicate aborts AT that pair (earlier stay, later not attempted)"
bulk.AddPairs n1 x k2 DUP n2 y 2>/dev/null
rc=$?
if [[ $rc -eq 1 && "$(bulk.count)" == "5" ]] && bulk.ContainsKey n1 \
   && ! bulk.ContainsKey n2 && [[ "$(bulk.GetItem k2)" == "v 2" ]]; then
    kt_test_pass "sequential-Add abort semantics (FPC Create(collection) shape)"
else
    kt_test_fail "rc=$rc count=$(bulk.count) n1=$(bulk.ContainsKey n1; echo $?) n2=$(bulk.ContainsKey n2; echo $?)"
fi

kt_test_start "AddPairs: duplicate WITHIN the batch aborts at its second occurrence"
TDictionary.new batch2
batch2.AddPairs a 1 b 2 a 3 c 4 2>/dev/null
rc=$?
if [[ $rc -eq 1 && "$(batch2.count)" == "2" && "$(batch2.GetItem a)" == "1" ]] \
   && ! batch2.ContainsKey c; then
    kt_test_pass "first occurrence wins; batch stops at the repeat"
else
    kt_test_fail "rc=$rc count=$(batch2.count) a=$(batch2.GetItem a)"
fi
batch2.delete
bulk.delete

kt_test_log "008_AssignAndBulk.sh completed"
