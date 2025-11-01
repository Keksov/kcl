#!/bin/bash
# 014_matches_pattern.sh - Test TPath.matchesPattern method

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
parse_args "$@"

# Test 1: Exact match
test_start "MatchesPattern with exact match"
result=$(tpath.matchesPattern "file.txt" "file.txt")
if [[ "$result" == "true" ]]; then
    test_pass "MatchesPattern with exact match"
else
    test_fail "MatchesPattern with exact match (expected: true, got: '$result')"
fi

# Test 2: Wildcard match
test_start "MatchesPattern with wildcard"
result=$(tpath.matchesPattern "file.txt" "file.*")
if [[ "$result" == "true" ]]; then
    test_pass "MatchesPattern with wildcard"
else
    test_fail "MatchesPattern with wildcard (expected: true, got: '$result')"
fi

# Test 3: No match
test_start "MatchesPattern with no match"
result=$(tpath.matchesPattern "file.txt" "other.*")
if [[ "$result" == "false" ]]; then
    test_pass "MatchesPattern with no match"
else
    test_fail "MatchesPattern with no match (expected: false, got: '$result')"
fi

# Test 4: Case insensitive match
test_start "MatchesPattern case insensitive"
result=$(tpath.matchesPattern "File.txt" "file.txt" "false")
if [[ "$result" == "true" ]]; then
    test_pass "MatchesPattern case insensitive"
else
    test_fail "MatchesPattern case insensitive (expected: true, got: '$result')"
fi

# Test 5: Case sensitive no match
test_start "MatchesPattern case sensitive no match"
result=$(tpath.matchesPattern "File.txt" "file.txt" "true")
if [[ "$result" == "false" ]]; then
    test_pass "MatchesPattern case sensitive no match"
else
    test_fail "MatchesPattern case sensitive no match (expected: false, got: '$result')"
fi

# Test 6: Empty parameters
test_start "MatchesPattern with empty filename"
result=$(tpath.matchesPattern "" "pattern")
if [[ "$result" == "false" ]]; then
    test_pass "MatchesPattern with empty filename"
else
    test_fail "MatchesPattern with empty filename (expected: false, got: '$result')"
fi

test_start "MatchesPattern with empty pattern"
result=$(tpath.matchesPattern "filename" "")
if [[ "$result" == "false" ]]; then
    test_pass "MatchesPattern with empty pattern"
else
    test_fail "MatchesPattern with empty pattern (expected: false, got: '$result')"
fi

# Test 7: Complex pattern
test_start "MatchesPattern with complex pattern"
result=$(tpath.matchesPattern "test123.txt" "test[0-9]*.txt")
if [[ "$result" == "true" ]]; then
    test_pass "MatchesPattern with complex pattern"
else
    test_fail "MatchesPattern with complex pattern (expected: true, got: '$result')"
fi
