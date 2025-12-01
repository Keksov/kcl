#!/bin/bash
# IsEmpty
# Auto-migrated to ktests framework

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

kt_test_init "IsEmpty" "$SCRIPT_DIR" "$@"

# Source tdirectory if needed
TDIRECTORY_DIR="$SCRIPT_DIR/.."
[[ -f "$TDIRECTORY_DIR/tdirectory.sh" ]] && source "$TDIRECTORY_DIR/tdirectory.sh"


# Test 1: Empty directory
kt_test_start "IsEmpty - empty directory returns true"
test_dir="$_KT_TMPDIR/empty"
tdirectory.createDirectory "$test_dir"
result=$(tdirectory.isEmpty "$test_dir")
if [[ "$result" == "true" ]]; then
    kt_test_pass "IsEmpty - empty directory returns true"
else
    kt_test_fail "IsEmpty - empty directory returns true (expected: true, got: '$result')"
fi

# Test 2: Directory with files
kt_test_start "IsEmpty - directory with files returns false"
test_dir="$_KT_TMPDIR/with_files"
tdirectory.createDirectory "$test_dir"
echo "content" > "$test_dir/file.txt"
result=$(tdirectory.isEmpty "$test_dir")
if [[ "$result" == "false" ]]; then
    kt_test_pass "IsEmpty - directory with files returns false"
else
    kt_test_fail "IsEmpty - directory with files returns false (expected: false, got: '$result')"
fi

# Test 3: Directory with subdirectories
kt_test_start "IsEmpty - directory with subdirectories returns false"
test_dir="$_KT_TMPDIR/with_subdirs"
tdirectory.createDirectory "$test_dir/subdir"
result=$(tdirectory.isEmpty "$test_dir")
if [[ "$result" == "false" ]]; then
    kt_test_pass "IsEmpty - directory with subdirectories returns false"
else
    kt_test_fail "IsEmpty - directory with subdirectories returns false (expected: false, got: '$result')"
fi

# Test 4: Empty path returns false
kt_test_start "IsEmpty - empty path returns false"
result=$(tdirectory.isEmpty "")
if [[ "$result" == "false" ]]; then
    kt_test_pass "IsEmpty - empty path returns false"
else
    kt_test_fail "IsEmpty - empty path returns false (expected: false, got: '$result')"
fi

# Test 5: Directory with many files
kt_test_start "IsEmpty - directory with many files"
test_dir="$_KT_TMPDIR/many_files"
tdirectory.createDirectory "$test_dir"
for i in {1..10}; do
    echo "file" > "$test_dir/file_$i.txt"
done
result=$(tdirectory.isEmpty "$test_dir")
if [[ "$result" == "false" ]]; then
    kt_test_pass "IsEmpty - directory with many files"
else
    kt_test_fail "IsEmpty - directory with many files (expected: false, got: '$result')"
fi

# Test 6: Directory emptied becomes empty
kt_test_start "IsEmpty - directory becomes empty after file deletion"
test_dir="$_KT_TMPDIR/to_empty"
tdirectory.createDirectory "$test_dir"
echo "content" > "$test_dir/file.txt"
rm "$test_dir/file.txt"
result=$(tdirectory.isEmpty "$test_dir")
if [[ "$result" == "true" ]]; then
    kt_test_pass "IsEmpty - directory becomes empty after file deletion"
else
    kt_test_fail "IsEmpty - directory becomes empty after file deletion (expected: true after deletion)"
fi

# Test 7: Newly created directory is empty
kt_test_start "IsEmpty - newly created directory is empty"
test_dir="$_KT_TMPDIR/newly_created"
tdirectory.createDirectory "$test_dir"
result=$(tdirectory.isEmpty "$test_dir")
if [[ "$result" == "true" ]]; then
    kt_test_pass "IsEmpty - newly created directory is empty"
else
    kt_test_fail "IsEmpty - newly created directory is empty (expected: true, got: '$result')"
fi

# Test 8: Directory with nested empty subdirectories
kt_test_start "IsEmpty - directory with nested empty subdirectories returns false"
test_dir="$_KT_TMPDIR/nested_empty_subdirs"
tdirectory.createDirectory "$test_dir/sub1/sub2/sub3"
result=$(tdirectory.isEmpty "$test_dir")
if [[ "$result" == "false" ]]; then
    kt_test_pass "IsEmpty - directory with nested empty subdirectories returns false"
else
    kt_test_fail "IsEmpty - directory with nested empty subdirectories returns false (expected: false)"
fi

# Cleanup\nkt_fixture_teardown


