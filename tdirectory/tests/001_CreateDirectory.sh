#!/bin/bash
# CreateDirectory
# Auto-migrated to kktests framework

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KKTESTS_LIB_DIR="$SCRIPT_DIR/../../../kktests"
source "$KKTESTS_LIB_DIR/kk-test.sh"

kk_test_init "CreateDirectory" "$SCRIPT_DIR" "$@"

# Source tdirectory if needed
TDIRECTORY_DIR="$SCRIPT_DIR/.."
[[ -f "$TDIRECTORY_DIR/tdirectory.sh" ]] && source "$TDIRECTORY_DIR/tdirectory.sh"

# Test 1: Create single directory
kk_test_start "CreateDirectory - create single directory"
test_dir="$KK_TEST_TMPDIR/test_dir_001"
tdirectory.createDirectory "$test_dir"
if [[ -d "$test_dir" ]]; then
    kk_test_pass "CreateDirectory - create single directory"
else
    kk_test_fail "CreateDirectory - create single directory (expected directory to exist, got: '$test_dir')"
fi

# Test 2: Create nested directories
kk_test_start "CreateDirectory - create nested directories"
test_dir="$KK_TEST_TMPDIR/nested/path/to/dir"
tdirectory.createDirectory "$test_dir"
if [[ -d "$test_dir" ]]; then
    kk_test_pass "CreateDirectory - create nested directories"
else
    kk_test_fail "CreateDirectory - create nested directories (expected nested structure to exist)"
fi

# Test 3: Create directory with spaces
kk_test_start "CreateDirectory - create directory with spaces"
test_dir="$KK_TEST_TMPDIR/directory with spaces"
tdirectory.createDirectory "$test_dir"
if [[ -d "$test_dir" ]]; then
    kk_test_pass "CreateDirectory - create directory with spaces"
else
    kk_test_fail "CreateDirectory - create directory with spaces (expected directory with spaces to exist)"
fi

# Test 4: Create directory that already exists (should not fail)
kk_test_start "CreateDirectory - directory already exists"
test_dir="$KK_TEST_TMPDIR/existing_dir"
tdirectory.createDirectory "$test_dir"
tdirectory.createDirectory "$test_dir"  # Create again
if [[ -d "$test_dir" ]]; then
    kk_test_pass "CreateDirectory - directory already exists"
else
    kk_test_fail "CreateDirectory - directory already exists (expected to handle existing directory gracefully)"
fi

# Test 5: Create directory with special characters
kk_test_start "CreateDirectory - directory with special characters"
test_dir="$KK_TEST_TMPDIR/dir-with_special.chars"
tdirectory.createDirectory "$test_dir"
if [[ -d "$test_dir" ]]; then
    kk_test_pass "CreateDirectory - directory with special characters"
else
    kk_test_fail "CreateDirectory - directory with special characters (expected directory to exist)"
fi

# Test 6: Create multiple directories in sequence
kk_test_start "CreateDirectory - create multiple directories"
for i in {1..3}; do
    test_dir="$KK_TEST_TMPDIR/multi_$i"
    tdirectory.createDirectory "$test_dir"
done
if [[ -d "$KK_TEST_TMPDIR/multi_1" && -d "$KK_TEST_TMPDIR/multi_2" && -d "$KK_TEST_TMPDIR/multi_3" ]]; then
    kk_test_pass "CreateDirectory - create multiple directories"
else
    kk_test_fail "CreateDirectory - create multiple directories (expected all three directories to exist)"
fi

# Test 7: Create long path
kk_test_start "CreateDirectory - create long path"
test_dir="$KK_TEST_TMPDIR/a/b/c/d/e/f/g/h/i/j/k/l/m/n/o/p/q/r/s/t/u/v/w/x/y/z"
tdirectory.createDirectory "$test_dir"
if [[ -d "$test_dir" ]]; then
    kk_test_pass "CreateDirectory - create long path"
else
    kk_test_fail "CreateDirectory - create long path (expected long nested structure to exist)"
fi

# Cleanup


