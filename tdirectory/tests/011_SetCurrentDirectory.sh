#!/bin/bash
# SetCurrentDirectory
# Auto-migrated to kktests framework

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KKTESTS_LIB_DIR="$SCRIPT_DIR/../../../kktests"
source "$KKTESTS_LIB_DIR/kk-test.sh"

kk_test_init "SetCurrentDirectory" "$SCRIPT_DIR" "$@"

# Source tdirectory if needed
TDIRECTORY_DIR="$SCRIPT_DIR/.."
[[ -f "$TDIRECTORY_DIR/tdirectory.sh" ]] && source "$TDIRECTORY_DIR/tdirectory.sh"


# Save original directory
original_dir=$(pwd)

# Test 1: Set current directory to existing directory
kk_test_start "SetCurrentDirectory - change to existing directory"
test_dir="$KK_TEST_TMPDIR/test_001"
tdirectory.createDirectory "$test_dir"
tdirectory.setCurrentDirectory "$test_dir"
current=$(tdirectory.getCurrentDirectory)
if [[ "$current" == "$test_dir" ]]; then
    kk_test_pass "SetCurrentDirectory - change to existing directory"
else
    kk_test_fail "SetCurrentDirectory - change to existing directory (expected: $test_dir, got: '$current')"
fi

# Test 2: SetCurrentDirectory updates pwd
kk_test_start "SetCurrentDirectory - updates pwd"
test_dir="$KK_TEST_TMPDIR/test_002"
tdirectory.createDirectory "$test_dir"
tdirectory.setCurrentDirectory "$test_dir"
current=$(pwd)
if [[ "$current" == "$test_dir" ]]; then
    kk_test_pass "SetCurrentDirectory - updates pwd"
else
    kk_test_fail "SetCurrentDirectory - updates pwd (expected: $test_dir, got: '$current')"
fi

# Test 3: Multiple SetCurrentDirectory calls
kk_test_start "SetCurrentDirectory - multiple calls"
dir1="$KK_TEST_TMPDIR/dir1"
dir2="$KK_TEST_TMPDIR/dir2"
dir3="$KK_TEST_TMPDIR/dir3"
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
    kk_test_pass "SetCurrentDirectory - multiple calls"
else
    kk_test_fail "SetCurrentDirectory - multiple calls (expected progression)"
fi

# Test 4: SetCurrentDirectory with absolute path
kk_test_start "SetCurrentDirectory - absolute path"
test_dir="$KK_TEST_TMPDIR/absolute_test"
tdirectory.createDirectory "$test_dir"
tdirectory.setCurrentDirectory "$test_dir"
current=$(pwd)
if [[ "$current" == "$test_dir" ]]; then
    kk_test_pass "SetCurrentDirectory - absolute path"
else
    kk_test_fail "SetCurrentDirectory - absolute path (expected: $test_dir, got: '$current')"
fi

# Test 5: SetCurrentDirectory with nested path
kk_test_start "SetCurrentDirectory - nested directory path"
test_dir="$KK_TEST_TMPDIR/a/b/c/d"
tdirectory.createDirectory "$test_dir"
tdirectory.setCurrentDirectory "$test_dir"
current=$(pwd)
if [[ "$current" == "$test_dir" ]]; then
    kk_test_pass "SetCurrentDirectory - nested directory path"
else
    kk_test_fail "SetCurrentDirectory - nested directory path (expected: $test_dir, got: '$current')"
fi

# Test 6: SetCurrentDirectory with spaces in path
kk_test_start "SetCurrentDirectory - path with spaces"
test_dir="$KK_TEST_TMPDIR/dir with spaces"
tdirectory.createDirectory "$test_dir"
tdirectory.setCurrentDirectory "$test_dir"
current=$(pwd)
if [[ "$current" == "$test_dir" ]]; then
    kk_test_pass "SetCurrentDirectory - path with spaces"
else
    kk_test_fail "SetCurrentDirectory - path with spaces (expected: $test_dir, got: '$current')"
fi

# Test 7: SetCurrentDirectory allows file operations
kk_test_start "SetCurrentDirectory - allows file operations"
test_dir="$KK_TEST_TMPDIR/file_ops"
tdirectory.createDirectory "$test_dir"
tdirectory.setCurrentDirectory "$test_dir"
echo "test content" > "test_file_in_new_dir.txt"
if [[ -f "./test_file_in_new_dir.txt" ]] || [[ -f "test_file_in_new_dir.txt" ]]; then
    kk_test_pass "SetCurrentDirectory - allows file operations"
else
    kk_test_fail "SetCurrentDirectory - allows file operations (expected file to be created)"
fi

# Test 8: SetCurrentDirectory affects subshell operations
kk_test_start "SetCurrentDirectory - affects directory operations"
test_dir="$KK_TEST_TMPDIR/ops_test"
tdirectory.createDirectory "$test_dir"
tdirectory.setCurrentDirectory "$test_dir"
tdirectory.createDirectory "subdir"
if [[ -d "subdir" ]]; then
    kk_test_pass "SetCurrentDirectory - affects directory operations"
else
    kk_test_fail "SetCurrentDirectory - affects directory operations (expected subdir to be created)"
fi

# Cleanup - restore original directory
cd "$original_dir" 2>/dev/null || true


