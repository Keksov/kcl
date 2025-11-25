#!/bin/bash
# MatchesPattern
# Auto-migrated to kktests framework

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KKTESTS_LIB_DIR="$SCRIPT_DIR/../../../kktests"
source "$KKTESTS_LIB_DIR/kk-test.sh"

kk_test_init "MatchesPattern" "$SCRIPT_DIR" "$@"

# Source tpath if needed
TPATH_DIR="$SCRIPT_DIR/.."
[[ -f "$TPATH_DIR/tpath.sh" ]] && source "$TPATH_DIR/tpath.sh"


# Test 1: Exact match
kk_test_start "MatchesPattern with exact match"
result=$(tpath.matchesPattern "file.txt" "file.txt")
if [[ "$result" == "true" ]]; then
    kk_test_pass "MatchesPattern with exact match"
else
    kk_test_fail "MatchesPattern with exact match (expected: true, got: '$result')"
fi

# Test 2: Wildcard match
kk_test_start "MatchesPattern with wildcard"
result=$(tpath.matchesPattern "file.txt" "file.*")
if [[ "$result" == "true" ]]; then
    kk_test_pass "MatchesPattern with wildcard"
else
    kk_test_fail "MatchesPattern with wildcard (expected: true, got: '$result')"
fi

# Test 3: No match
kk_test_start "MatchesPattern with no match"
result=$(tpath.matchesPattern "file.txt" "other.*")
if [[ "$result" == "false" ]]; then
    kk_test_pass "MatchesPattern with no match"
else
    kk_test_fail "MatchesPattern with no match (expected: false, got: '$result')"
fi

# Test 4: Case insensitive match
kk_test_start "MatchesPattern case insensitive"
result=$(tpath.matchesPattern "File.txt" "file.txt" "false")
if [[ "$result" == "true" ]]; then
    kk_test_pass "MatchesPattern case insensitive"
else
    kk_test_fail "MatchesPattern case insensitive (expected: true, got: '$result')"
fi

# Test 5: Case sensitive no match
kk_test_start "MatchesPattern case sensitive no match"
result=$(tpath.matchesPattern "File.txt" "file.txt" "true")
if [[ "$result" == "false" ]]; then
    kk_test_pass "MatchesPattern case sensitive no match"
else
    kk_test_fail "MatchesPattern case sensitive no match (expected: false, got: '$result')"
fi

# Test 6: Empty parameters
kk_test_start "MatchesPattern with empty filename"
result=$(tpath.matchesPattern "" "pattern")
if [[ "$result" == "false" ]]; then
    kk_test_pass "MatchesPattern with empty filename"
else
    kk_test_fail "MatchesPattern with empty filename (expected: false, got: '$result')"
fi

kk_test_start "MatchesPattern with empty pattern"
result=$(tpath.matchesPattern "filename" "")
if [[ "$result" == "false" ]]; then
    kk_test_pass "MatchesPattern with empty pattern"
else
    kk_test_fail "MatchesPattern with empty pattern (expected: false, got: '$result')"
fi

# Test 7: Complex pattern
kk_test_start "MatchesPattern with complex pattern"
result=$(tpath.matchesPattern "test123.txt" "test[0-9]*.txt")
if [[ "$result" == "true" ]]; then
    kk_test_pass "MatchesPattern with complex pattern"
else
    kk_test_fail "MatchesPattern with complex pattern (expected: true, got: '$result')"
fi
