#!/bin/bash
# GetFilename
# Auto-migrated to ktests framework

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

kt_test_init "GetFilename" "$SCRIPT_DIR" "$@"

# Source tpath if needed
TPATH_DIR="$SCRIPT_DIR/.."
[[ -f "$TPATH_DIR/tpath.sh" ]] && source "$TPATH_DIR/tpath.sh"


# Test 1: getFileName - simple path
kt_test_start "Get filename from simple path"
result=$(tpath.getFileName "/home/user/file.txt")
if [[ "$result" == "file.txt" ]]; then
    kt_test_pass "Get filename from simple path"
else
    kt_test_fail "Get filename from simple path (expected: file.txt, got: '$result')"
fi

# Test 2: getFileName - relative path
kt_test_start "Get filename from relative path"
result=$(tpath.getFileName "folder/file.txt")
if [[ "$result" == "file.txt" ]]; then
    kt_test_pass "Get filename from relative path"
else
    kt_test_fail "Get filename from relative path (expected: file.txt, got: '$result')"
fi

# Test 3: getFileName - filename only
kt_test_start "Get filename when only filename provided"
result=$(tpath.getFileName "file.txt")
if [[ "$result" == "file.txt" ]]; then
    kt_test_pass "Get filename when only filename provided"
else
    kt_test_fail "Get filename when only filename provided (expected: file.txt, got: '$result')"
fi

# Test 4: getFileName - empty path
kt_test_start "Get filename from empty path"
result=$(tpath.getFileName "")
if [[ "$result" == "" ]]; then
    kt_test_pass "Get filename from empty path"
else
    kt_test_fail "Get filename from empty path (expected: empty, got: '$result')"
fi

# Test 5: getFileNameWithoutExtension - simple case
kt_test_start "Get filename without extension"
result=$(tpath.getFileNameWithoutExtension "/home/user/file.txt")
if [[ "$result" == "file" ]]; then
    kt_test_pass "Get filename without extension"
else
    kt_test_fail "Get filename without extension (expected: file, got: '$result')"
fi

# Test 6: getFileNameWithoutExtension - no extension
kt_test_start "Get filename without extension when no extension"
result=$(tpath.getFileNameWithoutExtension "/home/user/file")
if [[ "$result" == "file" ]]; then
    kt_test_pass "Get filename without extension when no extension"
else
    kt_test_fail "Get filename without extension when no extension (expected: file, got: '$result')"
fi

# Test 7: getFileNameWithoutExtension - multiple dots
kt_test_start "Get filename without extension with multiple dots"
result=$(tpath.getFileNameWithoutExtension "file.tar.gz")
if [[ "$result" == "file.tar" ]]; then
    kt_test_pass "Get filename without extension with multiple dots"
else
    kt_test_fail "Get filename without extension with multiple dots (expected: file.tar, got: '$result')"
fi

# Test 8: getFileNameWithoutExtension - empty path
kt_test_start "Get filename without extension from empty path"
result=$(tpath.getFileNameWithoutExtension "")
if [[ "$result" == "" ]]; then
    kt_test_pass "Get filename without extension from empty path"
else
    kt_test_fail "Get filename without extension from empty path (expected: empty, got: '$result')"
fi
