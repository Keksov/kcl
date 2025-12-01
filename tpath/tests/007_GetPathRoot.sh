#!/bin/bash
# GetPathRoot
# Auto-migrated to ktests framework

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

kt_test_init "GetPathRoot" "$SCRIPT_DIR" "$@"

# Source tpath if needed
TPATH_DIR="$SCRIPT_DIR/.."
[[ -f "$TPATH_DIR/tpath.sh" ]] && source "$TPATH_DIR/tpath.sh"


# Test 1: Unix absolute path
kt_test_start "Get root from Unix absolute path"
result=$(tpath.getPathRoot "/home/user/file.txt")
if [[ "$result" == "/" ]]; then
    kt_test_pass "Get root from Unix absolute path"
else
    kt_test_fail "Get root from Unix absolute path (expected: /, got: '$result')"
fi

# Test 2: Windows drive path
kt_test_start "Get root from Windows drive path"
result=$(tpath.getPathRoot "C:/Users/file.txt")
if [[ "$result" == "C:" ]]; then
    kt_test_pass "Get root from Windows drive path"
else
    kt_test_fail "Get root from Windows drive path (expected: C:, got: '$result')"
fi

# Test 3: UNC path
kt_test_start "Get root from UNC path"
result=$(tpath.getPathRoot "//server/share/file.txt")
expected="//server"
if [[ "$result" == "$expected" ]]; then
    kt_test_pass "Get root from UNC path"
else
    kt_test_fail "Get root from UNC path (expected: $expected, got: '$result')"
fi

# Test 4: Relative path
kt_test_start "Get root from relative path"
result=$(tpath.getPathRoot "folder/file.txt")
if [[ "$result" == "" ]]; then
    kt_test_pass "Get root from relative path"
else
    kt_test_fail "Get root from relative path (expected: empty, got: '$result')"
fi

# Test 5: Empty path
kt_test_start "Get root from empty path"
result=$(tpath.getPathRoot "")
if [[ "$result" == "" ]]; then
    kt_test_pass "Get root from empty path"
else
    kt_test_fail "Get root from empty path (expected: empty, got: '$result')"
fi

# Test 6: Root only
kt_test_start "Get root from root path"
result=$(tpath.getPathRoot "/")
if [[ "$result" == "/" ]]; then
    kt_test_pass "Get root from root path"
else
    kt_test_fail "Get root from root path (expected: /, got: '$result')"
fi
