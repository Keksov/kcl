#!/bin/bash
# 001_CreationAndDestruction.sh - TDictionary creation, computed count, Clear, destruction
# P0.1/P0.3 gate (tlist 001 analog), amended to API v2 (thin wrapper: the capacity
# family is NOT ported — owner decision 2026-07-12; the ctor's ACapacity argument is
# accepted for FPC signature compatibility and ignored).
# FPC refs: Create (generics.dictionaries.inc:72-87), Clear (:515), Destroy (:128).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

TDICT_DIR="$SCRIPT_DIR/.."
source "$TDICT_DIR/tdictionary.sh"

TEST_NAME="$(basename "$0" .sh)"
kt_test_init "$TEST_NAME" "$SCRIPT_DIR" "$@"

kt_test_section "001: TDictionary creation and destruction (API v2)"

# Test: default constructor
kt_test_start "Create: count is 0"
TDictionary.new d
if [[ "$(d.count)" == "0" ]]; then
    kt_test_pass "count is 0"
else
    kt_test_fail "count is '$(d.count)', expected 0"
fi

kt_test_start "Create: storage is an empty ASSOCIATIVE array"
decl="$(declare -p d_items 2>/dev/null)"
if [[ "$decl" == "declare -A"* && ${#d_items[@]} -eq 0 ]]; then
    kt_test_pass "d_items is declare -A and empty"
else
    kt_test_fail "unexpected storage: $decl"
fi

# Test: FPC-compat ctor argument is accepted and ignored (thin wrapper)
kt_test_start "Create(1000): ACapacity accepted for signature compat, ignored"
TDictionary.new dcap 1000
rc=$?
if [[ $rc -eq 0 && "$(dcap.count)" == "0" ]]; then
    kt_test_pass "ctor arg ignored, count 0, rc 0"
else
    kt_test_fail "rc=$rc count=$(dcap.count)"
fi

# Test: capacity is NOT part of the API (dropped family)
kt_test_start "capacity member does not exist (dropped with the capacity family)"
TRAP_ERRORS_ENABLED=false
dcap.capacity >/dev/null 2>&1
rc=$?
TRAP_ERRORS_ENABLED=true
if [[ $rc -ne 0 ]]; then
    kt_test_pass "capacity access fails (rc=$rc) — not ported"
else
    kt_test_fail "capacity unexpectedly callable"
fi

# Test: count is COMPUTED from storage (cannot drift)
kt_test_start "count reads straight from \${#items[@]}"
dcap_items["ka"]="1"
dcap_items["kb"]="2"
if [[ "$(dcap.count)" == "2" ]]; then
    kt_test_pass "seeded 2 entries -> count 2 (computed, no stored mirror)"
else
    kt_test_fail "count=$(dcap.count), expected 2"
fi

# Test: Clear semantics (FPC: removes every pair, Count -> 0)
kt_test_start "Clear: count 0, storage emptied"
dcap.Clear
if [[ "$(dcap.count)" == "0" && ${#dcap_items[@]} -eq 0 ]]; then
    kt_test_pass "Clear resets count and storage"
else
    kt_test_fail "after Clear: count=$(dcap.count) items=${#dcap_items[@]}"
fi

# Test: instances are independent
kt_test_start "Instances are independent"
TDictionary.new ind1
TDictionary.new ind2
ind1_items["kx"]="1"
if [[ "$(ind1.count)" == "1" && "$(ind2.count)" == "0" ]]; then
    kt_test_pass "counts kept per instance (1/0)"
else
    kt_test_fail "cross-talk: ind1=$(ind1.count) ind2=$(ind2.count)"
fi
ind1.delete; ind2.delete

# Test: destruction
kt_test_start "delete: instance destroyed"
TDictionary.new victim
victim.delete
result=$?
if [[ $result -eq 0 ]]; then
    kt_test_pass "victim.delete succeeded"
else
    kt_test_fail "victim.delete rc=$result"
fi

kt_test_start "delete: destroyed instance inaccessible"
TRAP_ERRORS_ENABLED=false
victim.count >/dev/null 2>&1
result=$?
TRAP_ERRORS_ENABLED=true
if [[ $result -ne 0 ]]; then
    kt_test_pass "destroyed instance properly inaccessible"
else
    kt_test_fail "destroyed instance still accessible"
fi

kt_test_start "delete: pair storage unset by destructor"
TDictionary.new victim2
victim2_items["kz"]="9"
victim2.delete
if ! declare -p victim2_items >/dev/null 2>&1; then
    kt_test_pass "victim2_items gone"
else
    kt_test_fail "victim2_items still declared"
fi

kt_test_start "Recreate under the same name after delete"
TDictionary.new phoenix
phoenix_items["kold"]="x"
phoenix.delete
TDictionary.new phoenix
if [[ "$(phoenix.count)" == "0" && ${#phoenix_items[@]} -eq 0 ]]; then
    kt_test_pass "phoenix recreated cleanly (fresh empty storage)"
else
    kt_test_fail "recreate failed: count=$(phoenix.count) items=${#phoenix_items[@]}"
fi
phoenix.delete

# cleanup
d.delete; dcap.delete

kt_test_log "001_CreationAndDestruction.sh completed"
