#!/bin/bash
# CreateDirectory
# Auto-migrated to ktests framework

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

kt_test_init "CreateDirectory" "$SCRIPT_DIR" "$@"

# Source tdirectory if needed
TDIRECTORY_DIR="$SCRIPT_DIR/.."
[[ -f "$TDIRECTORY_DIR/tdirectory.sh" ]] && source "$TDIRECTORY_DIR/tdirectory.sh"

# Test 1: Create single directory
kt_test_start "CreateDirectory - create single directory"
test_dir="$_KT_TMPDIR/test_dir_001"
tdirectory.createDirectory "$test_dir"
if [[ -d "$test_dir" ]]; then
    kt_test_pass "CreateDirectory - create single directory"
else
    kt_test_fail "CreateDirectory - create single directory (expected directory to exist, got: '$test_dir')"
fi

# Test 2: Create nested directories
kt_test_start "CreateDirectory - create nested directories"
test_dir="$_KT_TMPDIR/nested/path/to/dir"
tdirectory.createDirectory "$test_dir"
if [[ -d "$test_dir" ]]; then
    kt_test_pass "CreateDirectory - create nested directories"
else
    kt_test_fail "CreateDirectory - create nested directories (expected nested structure to exist)"
fi

# Test 3: Create directory with spaces
kt_test_start "CreateDirectory - create directory with spaces"
test_dir="$_KT_TMPDIR/directory with spaces"
tdirectory.createDirectory "$test_dir"
if [[ -d "$test_dir" ]]; then
    kt_test_pass "CreateDirectory - create directory with spaces"
else
    kt_test_fail "CreateDirectory - create directory with spaces (expected directory with spaces to exist)"
fi

# Test 4: Create directory that already exists (should not fail)
kt_test_start "CreateDirectory - directory already exists"
test_dir="$_KT_TMPDIR/existing_dir"
tdirectory.createDirectory "$test_dir"
tdirectory.createDirectory "$test_dir"  # Create again
if [[ -d "$test_dir" ]]; then
    kt_test_pass "CreateDirectory - directory already exists"
else
    kt_test_fail "CreateDirectory - directory already exists (expected to handle existing directory gracefully)"
fi

# Test 5: Create directory with special characters
kt_test_start "CreateDirectory - directory with special characters"
test_dir="$_KT_TMPDIR/dir-with_special.chars"
tdirectory.createDirectory "$test_dir"
if [[ -d "$test_dir" ]]; then
    kt_test_pass "CreateDirectory - directory with special characters"
else
    kt_test_fail "CreateDirectory - directory with special characters (expected directory to exist)"
fi

# Test 6: Create multiple directories in sequence
kt_test_start "CreateDirectory - create multiple directories"
for i in {1..3}; do
    test_dir="$_KT_TMPDIR/multi_$i"
    tdirectory.createDirectory "$test_dir"
done
if [[ -d "$_KT_TMPDIR/multi_1" && -d "$_KT_TMPDIR/multi_2" && -d "$_KT_TMPDIR/multi_3" ]]; then
    kt_test_pass "CreateDirectory - create multiple directories"
else
    kt_test_fail "CreateDirectory - create multiple directories (expected all three directories to exist)"
fi

# Test 7: Create long path
kt_test_start "CreateDirectory - create long path"
test_dir="$_KT_TMPDIR/a/b/c/d/e/f/g/h/i/j/k/l/m/n/o/p/q/r/s/t/u/v/w/x/y/z"
tdirectory.createDirectory "$test_dir"
if [[ -d "$test_dir" ]]; then
    kt_test_pass "CreateDirectory - create long path"
else
    kt_test_fail "CreateDirectory - create long path (expected long nested structure to exist)"
fi
# Cleanup\nkt_fixture_teardown
kt_fixture_teardown
echo "DEBUG: Temporary directories created during test: $_KT_TMPDIR" >&2
echo "DEBUG: Checking if cleanup is needed..." >&2
if [[ -d "$_KT_TMPDIR" ]]; then
    echo "DEBUG: $_KT_TMPDIR still exists - cleanup missing!" >&2
else
    echo "DEBUG: $_KT_TMPDIR cleaned up properly" >&2
fi


