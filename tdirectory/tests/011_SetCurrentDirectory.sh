#!/bin/bash
# SetCurrentDirectory
# Auto-migrated to ktests framework

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

kt_test_init "SetCurrentDirectory" "$SCRIPT_DIR" "$@"

# Source tdirectory if needed
TDIRECTORY_DIR="$SCRIPT_DIR/.."
[[ -f "$TDIRECTORY_DIR/tdirectory.sh" ]] && source "$TDIRECTORY_DIR/tdirectory.sh"


# Save original directory
original_dir=$(pwd)

# Test 1: Set current directory to existing directory
kt_test_start "SetCurrentDirectory - change to existing directory"
test_dir="$_KT_TMPDIR/test_001"
tdirectory.createDirectory "$test_dir"
tdirectory.setCurrentDirectory "$test_dir"
current=$(tdirectory.getCurrentDirectory)
if [[ "$current" == "$test_dir" ]]; then
    kt_test_pass "SetCurrentDirectory - change to existing directory"
else
    kt_test_fail "SetCurrentDirectory - change to existing directory (expected: $test_dir, got: '$current')"
fi

# Test 2: SetCurrentDirectory updates pwd
kt_test_start "SetCurrentDirectory - updates pwd"
test_dir="$_KT_TMPDIR/test_002"
tdirectory.createDirectory "$test_dir"
tdirectory.setCurrentDirectory "$test_dir"
current=$(pwd)
if [[ "$current" == "$test_dir" ]]; then
    kt_test_pass "SetCurrentDirectory - updates pwd"
else
    kt_test_fail "SetCurrentDirectory - updates pwd (expected: $test_dir, got: '$current')"
fi

# Test 3: Multiple SetCurrentDirectory calls
kt_test_start "SetCurrentDirectory - multiple calls"
dir1="$_KT_TMPDIR/dir1"
dir2="$_KT_TMPDIR/dir2"
dir3="$_KT_TMPDIR/dir3"
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
    kt_test_pass "SetCurrentDirectory - multiple calls"
else
    kt_test_fail "SetCurrentDirectory - multiple calls (expected progression)"
fi

# Test 4: SetCurrentDirectory with absolute path
kt_test_start "SetCurrentDirectory - absolute path"
test_dir="$_KT_TMPDIR/absolute_test"
tdirectory.createDirectory "$test_dir"
tdirectory.setCurrentDirectory "$test_dir"
current=$(pwd)
if [[ "$current" == "$test_dir" ]]; then
    kt_test_pass "SetCurrentDirectory - absolute path"
else
    kt_test_fail "SetCurrentDirectory - absolute path (expected: $test_dir, got: '$current')"
fi

# Test 5: SetCurrentDirectory with nested path
kt_test_start "SetCurrentDirectory - nested directory path"
test_dir="$_KT_TMPDIR/a/b/c/d"
tdirectory.createDirectory "$test_dir"
tdirectory.setCurrentDirectory "$test_dir"
current=$(pwd)
if [[ "$current" == "$test_dir" ]]; then
    kt_test_pass "SetCurrentDirectory - nested directory path"
else
    kt_test_fail "SetCurrentDirectory - nested directory path (expected: $test_dir, got: '$current')"
fi

# Test 6: SetCurrentDirectory with spaces in path
kt_test_start "SetCurrentDirectory - path with spaces"
test_dir="$_KT_TMPDIR/dir with spaces"
tdirectory.createDirectory "$test_dir"
tdirectory.setCurrentDirectory "$test_dir"
current=$(pwd)
if [[ "$current" == "$test_dir" ]]; then
    kt_test_pass "SetCurrentDirectory - path with spaces"
else
    kt_test_fail "SetCurrentDirectory - path with spaces (expected: $test_dir, got: '$current')"
fi

# Test 7: SetCurrentDirectory allows file operations
kt_test_start "SetCurrentDirectory - allows file operations"
test_dir="$_KT_TMPDIR/file_ops"
tdirectory.createDirectory "$test_dir"
tdirectory.setCurrentDirectory "$test_dir"
echo "test content" > "test_file_in_new_dir.txt"
if [[ -f "./test_file_in_new_dir.txt" ]] || [[ -f "test_file_in_new_dir.txt" ]]; then
    kt_test_pass "SetCurrentDirectory - allows file operations"
else
    kt_test_fail "SetCurrentDirectory - allows file operations (expected file to be created)"
fi

# Test 8: SetCurrentDirectory affects subshell operations
kt_test_start "SetCurrentDirectory - affects directory operations"
test_dir="$_KT_TMPDIR/ops_test"
tdirectory.createDirectory "$test_dir"
tdirectory.setCurrentDirectory "$test_dir"
tdirectory.createDirectory "subdir"
if [[ -d "subdir" ]]; then
    kt_test_pass "SetCurrentDirectory - affects directory operations"
else
    kt_test_fail "SetCurrentDirectory - affects directory operations (expected subdir to be created)"
fi

# Cleanup\nkt_fixture_teardown - restore original directory
cd "$original_dir" 2>/dev/null || true


