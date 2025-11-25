#!/bin/bash
# GetCurrentDirectory
# Auto-migrated to kktests framework

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KKTESTS_LIB_DIR="$SCRIPT_DIR/../../../kktests"
source "$KKTESTS_LIB_DIR/kk-test.sh"

kk_test_init "GetCurrentDirectory" "$SCRIPT_DIR" "$@"

# Source tdirectory if needed
TDIRECTORY_DIR="$SCRIPT_DIR/.."
[[ -f "$TDIRECTORY_DIR/tdirectory.sh" ]] && source "$TDIRECTORY_DIR/tdirectory.sh"


# Save original directory
original_dir=$(pwd)

# Test 1: GetCurrentDirectory returns non-empty
kk_test_start "GetCurrentDirectory - returns non-empty string"
result=$(tdirectory.getCurrentDirectory)
if [[ -n "$result" ]]; then
    kk_test_pass "GetCurrentDirectory - returns non-empty string"
else
    kk_test_fail "GetCurrentDirectory - returns non-empty string (expected: non-empty, got: '$result')"
fi

# Test 2: GetCurrentDirectory returns absolute path
kk_test_start "GetCurrentDirectory - returns absolute path"
result=$(tdirectory.getCurrentDirectory)
if [[ "$result" == /* ]] || [[ "$result" =~ ^[A-Za-z]: ]]; then
    kk_test_pass "GetCurrentDirectory - returns absolute path"
else
    kk_test_fail "GetCurrentDirectory - returns absolute path (expected absolute path, got: '$result')"
fi

# Test 3: GetCurrentDirectory is a directory
kk_test_start "GetCurrentDirectory - result is existing directory"
result=$(tdirectory.getCurrentDirectory)
if [[ -d "$result" ]]; then
    kk_test_pass "GetCurrentDirectory - result is existing directory"
else
    kk_test_fail "GetCurrentDirectory - result is existing directory (expected existing directory, got: '$result')"
fi

# Test 4: GetCurrentDirectory matches pwd
kk_test_start "GetCurrentDirectory - matches pwd output"
result=$(tdirectory.getCurrentDirectory)
pwd_result=$(pwd)
if [[ "$result" == "$pwd_result" ]]; then
    kk_test_pass "GetCurrentDirectory - matches pwd output"
else
    kk_test_fail "GetCurrentDirectory - matches pwd output (expected: $pwd_result, got: '$result')"
fi

# Test 5: GetCurrentDirectory returns consistent value
kk_test_start "GetCurrentDirectory - returns consistent value"
result1=$(tdirectory.getCurrentDirectory)
result2=$(tdirectory.getCurrentDirectory)
if [[ "$result1" == "$result2" ]]; then
    kk_test_pass "GetCurrentDirectory - returns consistent value"
else
    kk_test_fail "GetCurrentDirectory - returns consistent value (expected same, got: '$result1' vs '$result2')"
fi

# Test 6: GetCurrentDirectory with SetCurrentDirectory
kk_test_start "GetCurrentDirectory - reflects SetCurrentDirectory"
init_test_tmpdir "010"
temp_dir="$TEST_TMP_DIR"
tdirectory.setCurrentDirectory "$temp_dir"
result=$(tdirectory.getCurrentDirectory)
if [[ "$result" == "$temp_dir" ]]; then
    kk_test_pass "GetCurrentDirectory - reflects SetCurrentDirectory"
else
    kk_test_fail "GetCurrentDirectory - reflects SetCurrentDirectory (expected: $temp_dir, got: '$result')"
fi

# Test 7: GetCurrentDirectory returns no trailing slash
kk_test_start "GetCurrentDirectory - no trailing slash"
result=$(tdirectory.getCurrentDirectory)
if [[ ! "$result" =~ /$ ]]; then
    kk_test_pass "GetCurrentDirectory - no trailing slash"
else
    kk_test_fail "GetCurrentDirectory - no trailing slash (expected no trailing slash, got: '$result')"
fi

# Test 8: CurrentDirectory is readable
kk_test_start "GetCurrentDirectory - directory is readable"
if [[ -n "$result" ]]; then
kk_test_pass "GetCurrentDirectory - directory path returned"
else
kk_test_fail "GetCurrentDirectory - directory path returned (expected non-empty path)"
fi

# Cleanup - restore original directory
cd "$original_dir" 2>/dev/null || true


