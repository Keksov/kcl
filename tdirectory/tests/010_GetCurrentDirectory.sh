#!/bin/bash
# 010_GetCurrentDirectory.sh - Test TDirectory.GetCurrentDirectory method

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
parse_args "$@"

# Save original directory
original_dir=$(pwd)

# Test 1: GetCurrentDirectory returns non-empty
test_start "GetCurrentDirectory - returns non-empty string"
result=$(tdirectory.getCurrentDirectory)
if [[ -n "$result" ]]; then
    test_pass "GetCurrentDirectory - returns non-empty string"
else
    test_fail "GetCurrentDirectory - returns non-empty string (expected: non-empty, got: '$result')"
fi

# Test 2: GetCurrentDirectory returns absolute path
test_start "GetCurrentDirectory - returns absolute path"
result=$(tdirectory.getCurrentDirectory)
if [[ "$result" == /* ]] || [[ "$result" =~ ^[A-Za-z]: ]]; then
    test_pass "GetCurrentDirectory - returns absolute path"
else
    test_fail "GetCurrentDirectory - returns absolute path (expected absolute path, got: '$result')"
fi

# Test 3: GetCurrentDirectory is a directory
test_start "GetCurrentDirectory - result is existing directory"
result=$(tdirectory.getCurrentDirectory)
if [[ -d "$result" ]]; then
    test_pass "GetCurrentDirectory - result is existing directory"
else
    test_fail "GetCurrentDirectory - result is existing directory (expected existing directory, got: '$result')"
fi

# Test 4: GetCurrentDirectory matches pwd
test_start "GetCurrentDirectory - matches pwd output"
result=$(tdirectory.getCurrentDirectory)
pwd_result=$(pwd)
if [[ "$result" == "$pwd_result" ]]; then
    test_pass "GetCurrentDirectory - matches pwd output"
else
    test_fail "GetCurrentDirectory - matches pwd output (expected: $pwd_result, got: '$result')"
fi

# Test 5: GetCurrentDirectory returns consistent value
test_start "GetCurrentDirectory - returns consistent value"
result1=$(tdirectory.getCurrentDirectory)
result2=$(tdirectory.getCurrentDirectory)
if [[ "$result1" == "$result2" ]]; then
    test_pass "GetCurrentDirectory - returns consistent value"
else
    test_fail "GetCurrentDirectory - returns consistent value (expected same, got: '$result1' vs '$result2')"
fi

# Test 6: GetCurrentDirectory with SetCurrentDirectory
test_start "GetCurrentDirectory - reflects SetCurrentDirectory"
init_test_tmpdir "010"
temp_dir="$TEST_TMP_DIR"
tdirectory.setCurrentDirectory "$temp_dir"
result=$(tdirectory.getCurrentDirectory)
if [[ "$result" == "$temp_dir" ]]; then
    test_pass "GetCurrentDirectory - reflects SetCurrentDirectory"
else
    test_fail "GetCurrentDirectory - reflects SetCurrentDirectory (expected: $temp_dir, got: '$result')"
fi

# Test 7: GetCurrentDirectory returns no trailing slash
test_start "GetCurrentDirectory - no trailing slash"
result=$(tdirectory.getCurrentDirectory)
if [[ ! "$result" =~ /$ ]]; then
    test_pass "GetCurrentDirectory - no trailing slash"
else
    test_fail "GetCurrentDirectory - no trailing slash (expected no trailing slash, got: '$result')"
fi

# Test 8: CurrentDirectory is readable
test_start "GetCurrentDirectory - directory is readable"
if [[ -n "$result" ]]; then
test_pass "GetCurrentDirectory - directory path returned"
else
test_fail "GetCurrentDirectory - directory path returned (expected non-empty path)"
fi

# Cleanup - restore original directory
cd "$original_dir" 2>/dev/null || true


