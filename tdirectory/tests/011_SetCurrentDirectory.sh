#!/bin/bash
# 011_SetCurrentDirectory.sh - Test TDirectory.SetCurrentDirectory method

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
parse_args "$@"

# Save original directory
original_dir=$(pwd)

# Setup temp directories for tests
init_test_tmpdir "011"
temp_base="$TEST_TMP_DIR"

# Test 1: Set current directory to existing directory
test_start "SetCurrentDirectory - change to existing directory"
test_dir="$temp_base/test_001"
tdirectory.createDirectory "$test_dir"
tdirectory.setCurrentDirectory "$test_dir"
current=$(tdirectory.getCurrentDirectory)
if [[ "$current" == "$test_dir" ]]; then
    test_pass "SetCurrentDirectory - change to existing directory"
else
    test_fail "SetCurrentDirectory - change to existing directory (expected: $test_dir, got: '$current')"
fi

# Test 2: SetCurrentDirectory updates pwd
test_start "SetCurrentDirectory - updates pwd"
test_dir="$temp_base/test_002"
tdirectory.createDirectory "$test_dir"
tdirectory.setCurrentDirectory "$test_dir"
current=$(pwd)
if [[ "$current" == "$test_dir" ]]; then
    test_pass "SetCurrentDirectory - updates pwd"
else
    test_fail "SetCurrentDirectory - updates pwd (expected: $test_dir, got: '$current')"
fi

# Test 3: Multiple SetCurrentDirectory calls
test_start "SetCurrentDirectory - multiple calls"
dir1="$temp_base/dir1"
dir2="$temp_base/dir2"
dir3="$temp_base/dir3"
tdirectory.createDirectory "$dir1"
tdirectory.createDirectory "$dir2"
tdirectory.createDirectory "$dir3"
tdirectory.setCurrentDirectory "$dir1"
curr1=$(pwd)
tdirectory.setCurrentDirectory "$dir2"
curr2=$(pwd)
tdirectory.setCurrentDirectory "$dir3"
curr3=$(pwd)
if [[ "$curr1" == "$dir1" && "$curr2" == "$dir2" && "$curr3" == "$dir3" ]]; then
    test_pass "SetCurrentDirectory - multiple calls"
else
    test_fail "SetCurrentDirectory - multiple calls (expected progression)"
fi

# Test 4: SetCurrentDirectory with absolute path
test_start "SetCurrentDirectory - absolute path"
test_dir="$temp_base/absolute_test"
tdirectory.createDirectory "$test_dir"
tdirectory.setCurrentDirectory "$test_dir"
current=$(pwd)
if [[ "$current" == "$test_dir" ]]; then
    test_pass "SetCurrentDirectory - absolute path"
else
    test_fail "SetCurrentDirectory - absolute path (expected: $test_dir, got: '$current')"
fi

# Test 5: SetCurrentDirectory with nested path
test_start "SetCurrentDirectory - nested directory path"
test_dir="$temp_base/a/b/c/d"
tdirectory.createDirectory "$test_dir"
tdirectory.setCurrentDirectory "$test_dir"
current=$(pwd)
if [[ "$current" == "$test_dir" ]]; then
    test_pass "SetCurrentDirectory - nested directory path"
else
    test_fail "SetCurrentDirectory - nested directory path (expected: $test_dir, got: '$current')"
fi

# Test 6: SetCurrentDirectory with spaces in path
test_start "SetCurrentDirectory - path with spaces"
test_dir="$temp_base/dir with spaces"
tdirectory.createDirectory "$test_dir"
tdirectory.setCurrentDirectory "$test_dir"
current=$(pwd)
if [[ "$current" == "$test_dir" ]]; then
    test_pass "SetCurrentDirectory - path with spaces"
else
    test_fail "SetCurrentDirectory - path with spaces (expected: $test_dir, got: '$current')"
fi

# Test 7: SetCurrentDirectory allows file operations
test_start "SetCurrentDirectory - allows file operations"
test_dir="$temp_base/file_ops"
tdirectory.createDirectory "$test_dir"
tdirectory.setCurrentDirectory "$test_dir"
echo "test content" > "test_file_in_new_dir.txt"
if [[ -f "./test_file_in_new_dir.txt" ]] || [[ -f "test_file_in_new_dir.txt" ]]; then
    test_pass "SetCurrentDirectory - allows file operations"
else
    test_fail "SetCurrentDirectory - allows file operations (expected file to be created)"
fi

# Test 8: SetCurrentDirectory affects subshell operations
test_start "SetCurrentDirectory - affects directory operations"
test_dir="$temp_base/ops_test"
tdirectory.createDirectory "$test_dir"
tdirectory.setCurrentDirectory "$test_dir"
tdirectory.createDirectory "subdir"
if [[ -d "subdir" ]]; then
    test_pass "SetCurrentDirectory - affects directory operations"
else
    test_fail "SetCurrentDirectory - affects directory operations (expected subdir to be created)"
fi

# Cleanup - restore original directory
cd "$original_dir" 2>/dev/null || true


