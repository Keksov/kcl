#!/bin/bash
# 003_AddFamily.sh - Add / TryAdd / AddOrSetValue (P1.1)
# FPC seed: rtl-generics tests.generics.dictionary2.pas (TTestGenDictionary:
# TestAdd / TestTryAdd / TestAddOrSet / TestAddModify — the add-method matrix,
# including the duplicate-raises case). FPC impl refs: InternalDoAdd :399
# (EListError SDuplicatesNotAllowed), TryAdd :718, AddOrSetValue :729.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

TDICT_DIR="$SCRIPT_DIR/.."
source "$TDICT_DIR/tdictionary.sh"

TEST_NAME="$(basename "$0" .sh)"
kt_test_init "$TEST_NAME" "$SCRIPT_DIR" "$@"

kt_test_section "003: Add / TryAdd / AddOrSetValue"

TDictionary.new d

# dictionary2 DoRunTestAdd analog: add a batch, verify every pair and the count
kt_test_start "Add N pairs, all retrievable, count exact"
ok=1
for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
    d.Add "key$i" "value$i" || { ok=0; break; }
done
if [[ $ok -eq 1 && "$(d.count)" == "20" && ${#d_items[@]} -eq 20 ]]; then
    ok2=1
    for i in 5 13 20; do
        [[ "$(d.GetItem "key$i")" == "value$i" ]] || ok2=0
    done
    if [[ $ok2 -eq 1 ]]; then
        kt_test_pass "20 adds, count 20 (== storage), spot values exact"
    else
        kt_test_fail "a value came back wrong"
    fi
else
    kt_test_fail "add loop failed: count=$(d.count) storage=${#d_items[@]}"
fi

# duplicate Add: FPC raises EListError -> rc=1, dictionary NOT mutated
kt_test_start "Add duplicate: rc=1, value and count unchanged"
d.Add key5 CHANGED 2>/dev/null
rc=$?
if [[ $rc -eq 1 && "$(d.GetItem key5)" == "value5" && "$(d.count)" == "20" ]]; then
    kt_test_pass "duplicate rejected without mutation (rc=1)"
else
    kt_test_fail "rc=$rc value=$(d.GetItem key5) count=$(d.count)"
fi

# TryAdd: present -> rc=1 silent negative answer, no mutation
kt_test_start "TryAdd on present key: rc=1, silent, no mutation"
errf="${TMPDIR:-/tmp}/td003_err.$$"
d.TryAdd key5 OTHER 2>"$errf"   # direct call so the (non-)mutation happens in THIS shell
rc=$?
err="$(cat "$errf" 2>/dev/null)"; rm -f "$errf"
if [[ $rc -eq 1 && -z "$err" && "$(d.GetItem key5)" == "value5" ]]; then
    kt_test_pass "negative answer, no stderr even in normal mode"
else
    kt_test_fail "rc=$rc err=[$err] value=$(d.GetItem key5)"
fi

kt_test_start "TryAdd on absent key: rc=0, pair added"
d.TryAdd newkey newval
rc=$?
if [[ $rc -eq 0 && "$(d.GetItem newkey)" == "newval" && "$(d.count)" == "21" ]]; then
    kt_test_pass "added (count 21)"
else
    kt_test_fail "rc=$rc count=$(d.count)"
fi

# AddOrSetValue: insert branch and overwrite branch
kt_test_start "AddOrSetValue inserts when absent"
d.AddOrSetValue upsert1 first
if [[ "$(d.GetItem upsert1)" == "first" && "$(d.count)" == "22" ]]; then
    kt_test_pass "insert branch ok"
else
    kt_test_fail "value=$(d.GetItem upsert1) count=$(d.count)"
fi

kt_test_start "AddOrSetValue overwrites when present (count stable)"
d.AddOrSetValue upsert1 second
if [[ "$(d.GetItem upsert1)" == "second" && "$(d.count)" == "22" ]]; then
    kt_test_pass "overwrite branch ok, count unchanged"
else
    kt_test_fail "value=$(d.GetItem upsert1) count=$(d.count)"
fi

# boundary: the empty key is a valid FPC key (the reason the storage prefix exists)
kt_test_start "Add with EMPTY key"
d.Add "" "empty-key-value"
rc=$?
if [[ $rc -eq 0 && "$(d.GetItem "")" == "empty-key-value" && "$(d.count)" == "23" ]]; then
    kt_test_pass "'' is a first-class key"
else
    kt_test_fail "rc=$rc value=[$(d.GetItem "")] count=$(d.count)"
fi

kt_test_start "Add duplicate EMPTY key rejected"
d.Add "" other 2>/dev/null
rc=$?
if [[ $rc -eq 1 && "$(d.GetItem "")" == "empty-key-value" ]]; then
    kt_test_pass "duplicate '' rejected, value intact"
else
    kt_test_fail "rc=$rc value=[$(d.GetItem "")]"
fi

# boundary: empty VALUE stored and distinguishable from absence
kt_test_start "Add with empty VALUE"
d.Add emptyval ""
if d.ContainsKey emptyval && [[ "$(d.GetItem emptyval)" == "" ]]; then
    kt_test_pass "empty value stored, key exists"
else
    kt_test_fail "empty-value pair broken"
fi

# values with spaces and glob characters survive
kt_test_start "Values with spaces/globs stored byte-exact"
d.Add globval 'a * b ? [c] $(no)'
if [[ "$(d.GetItem globval)" == 'a * b ? [c] $(no)' ]]; then
    kt_test_pass "special-char value intact"
else
    kt_test_fail "got: $(d.GetItem globval)"
fi

d.delete

kt_test_log "003_AddFamily.sh completed"
