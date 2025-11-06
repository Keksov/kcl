#!/bin/bash
# 001_CreateDirectory.sh - Test TDirectory.CreateDirectory method

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
parse_args "$@"

# Setup temp directory for tests
init_test_tmpdir "001"
temp_base="$TEST_TMP_DIR"

# Test 1: Create single directory
test_start "CreateDirectory - create single directory"
test_dir="$temp_base/test_dir_001"
tdirectory.createDirectory "$test_dir"
if [[ -d "$test_dir" ]]; then
    test_pass "CreateDirectory - create single directory"
else
    test_fail "CreateDirectory - create single directory (expected directory to exist, got: '$test_dir')"
fi

# Test 2: Create nested directories
test_start "CreateDirectory - create nested directories"
test_dir="$temp_base/nested/path/to/dir"
tdirectory.createDirectory "$test_dir"
if [[ -d "$test_dir" ]]; then
    test_pass "CreateDirectory - create nested directories"
else
    test_fail "CreateDirectory - create nested directories (expected nested structure to exist)"
fi

# Test 3: Create directory with spaces
test_start "CreateDirectory - create directory with spaces"
test_dir="$temp_base/directory with spaces"
tdirectory.createDirectory "$test_dir"
if [[ -d "$test_dir" ]]; then
    test_pass "CreateDirectory - create directory with spaces"
else
    test_fail "CreateDirectory - create directory with spaces (expected directory with spaces to exist)"
fi

# Test 4: Create directory that already exists (should not fail)
test_start "CreateDirectory - directory already exists"
test_dir="$temp_base/existing_dir"
tdirectory.createDirectory "$test_dir"
tdirectory.createDirectory "$test_dir"  # Create again
if [[ -d "$test_dir" ]]; then
    test_pass "CreateDirectory - directory already exists"
else
    test_fail "CreateDirectory - directory already exists (expected to handle existing directory gracefully)"
fi

# Test 5: Create directory with special characters
test_start "CreateDirectory - directory with special characters"
test_dir="$temp_base/dir-with_special.chars"
tdirectory.createDirectory "$test_dir"
if [[ -d "$test_dir" ]]; then
    test_pass "CreateDirectory - directory with special characters"
else
    test_fail "CreateDirectory - directory with special characters (expected directory to exist)"
fi

# Test 6: Create multiple directories in sequence
test_start "CreateDirectory - create multiple directories"
for i in {1..3}; do
    test_dir="$temp_base/multi_$i"
    tdirectory.createDirectory "$test_dir"
done
if [[ -d "$temp_base/multi_1" && -d "$temp_base/multi_2" && -d "$temp_base/multi_3" ]]; then
    test_pass "CreateDirectory - create multiple directories"
else
    test_fail "CreateDirectory - create multiple directories (expected all three directories to exist)"
fi

# Test 7: Create long path
test_start "CreateDirectory - create long path"
test_dir="$temp_base/a/b/c/d/e/f/g/h/i/j/k/l/m/n/o/p/q/r/s/t/u/v/w/x/y/z"
tdirectory.createDirectory "$test_dir"
if [[ -d "$test_dir" ]]; then
    test_pass "CreateDirectory - create long path"
else
    test_fail "CreateDirectory - create long path (expected long nested structure to exist)"
fi

# Cleanup


