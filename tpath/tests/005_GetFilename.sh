#!/bin/bash
# GetFilename
# Auto-migrated to kktests framework

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KKTESTS_LIB_DIR="$SCRIPT_DIR/../../../kktests"
source "$KKTESTS_LIB_DIR/kk-test.sh"

kk_test_init "GetFilename" "$SCRIPT_DIR" "$@"

# Source tpath if needed
TPATH_DIR="$SCRIPT_DIR/.."
[[ -f "$TPATH_DIR/tpath.sh" ]] && source "$TPATH_DIR/tpath.sh"


# Test 1: getFileName - simple path
kk_test_start "Get filename from simple path"
result=$(tpath.getFileName "/home/user/file.txt")
if [[ "$result" == "file.txt" ]]; then
    kk_test_pass "Get filename from simple path"
else
    kk_test_fail "Get filename from simple path (expected: file.txt, got: '$result')"
fi

# Test 2: getFileName - relative path
kk_test_start "Get filename from relative path"
result=$(tpath.getFileName "folder/file.txt")
if [[ "$result" == "file.txt" ]]; then
    kk_test_pass "Get filename from relative path"
else
    kk_test_fail "Get filename from relative path (expected: file.txt, got: '$result')"
fi

# Test 3: getFileName - filename only
kk_test_start "Get filename when only filename provided"
result=$(tpath.getFileName "file.txt")
if [[ "$result" == "file.txt" ]]; then
    kk_test_pass "Get filename when only filename provided"
else
    kk_test_fail "Get filename when only filename provided (expected: file.txt, got: '$result')"
fi

# Test 4: getFileName - empty path
kk_test_start "Get filename from empty path"
result=$(tpath.getFileName "")
if [[ "$result" == "" ]]; then
    kk_test_pass "Get filename from empty path"
else
    kk_test_fail "Get filename from empty path (expected: empty, got: '$result')"
fi

# Test 5: getFileNameWithoutExtension - simple case
kk_test_start "Get filename without extension"
result=$(tpath.getFileNameWithoutExtension "/home/user/file.txt")
if [[ "$result" == "file" ]]; then
    kk_test_pass "Get filename without extension"
else
    kk_test_fail "Get filename without extension (expected: file, got: '$result')"
fi

# Test 6: getFileNameWithoutExtension - no extension
kk_test_start "Get filename without extension when no extension"
result=$(tpath.getFileNameWithoutExtension "/home/user/file")
if [[ "$result" == "file" ]]; then
    kk_test_pass "Get filename without extension when no extension"
else
    kk_test_fail "Get filename without extension when no extension (expected: file, got: '$result')"
fi

# Test 7: getFileNameWithoutExtension - multiple dots
kk_test_start "Get filename without extension with multiple dots"
result=$(tpath.getFileNameWithoutExtension "file.tar.gz")
if [[ "$result" == "file.tar" ]]; then
    kk_test_pass "Get filename without extension with multiple dots"
else
    kk_test_fail "Get filename without extension with multiple dots (expected: file.tar, got: '$result')"
fi

# Test 8: getFileNameWithoutExtension - empty path
kk_test_start "Get filename without extension from empty path"
result=$(tpath.getFileNameWithoutExtension "")
if [[ "$result" == "" ]]; then
    kk_test_pass "Get filename without extension from empty path"
else
    kk_test_fail "Get filename without extension from empty path (expected: empty, got: '$result')"
fi
