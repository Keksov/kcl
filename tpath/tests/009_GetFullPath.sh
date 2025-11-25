#!/bin/bash
# GetFullPath
# Auto-migrated to kktests framework

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KKTESTS_LIB_DIR="$SCRIPT_DIR/../../../kktests"
source "$KKTESTS_LIB_DIR/kk-test.sh"

kk_test_init "GetFullPath" "$SCRIPT_DIR" "$@"

# Source tpath if needed
TPATH_DIR="$SCRIPT_DIR/.."
[[ -f "$TPATH_DIR/tpath.sh" ]] && source "$TPATH_DIR/tpath.sh"


# Test 1: Relative path to absolute
kk_test_start "Convert relative path to absolute"
result=$(tpath.getFullPath ".")
if [[ "$result" == /* ]] || [[ "$result" =~ ^[A-Za-z]: ]]; then
    kk_test_pass "Convert relative path to absolute"
else
    kk_test_fail "Convert relative path to absolute (expected absolute path, got: '$result')"
fi

# Test 2: Already absolute path
kk_test_start "Absolute path remains absolute"
result=$(tpath.getFullPath "/tmp")
if [[ "$result" == "/tmp" ]] || [[ "$result" =~ ^/.*tmp.* ]]; then
    kk_test_pass "Absolute path remains absolute"
else
    kk_test_fail "Absolute path remains absolute (got: '$result')"
fi

# Test 3: Empty path
kk_test_start "getFullPath with empty path"
result=$(tpath.getFullPath "")
if [[ "$result" == "" ]]; then
    kk_test_pass "getFullPath with empty path"
else
    kk_test_fail "getFullPath with empty path (expected empty, got: '$result')"
fi

# Test 4: Current directory
kk_test_start "getFullPath with current directory"
result=$(tpath.getFullPath ".")
if [[ -n "$result" && "$result" != "." ]]; then
    kk_test_pass "getFullPath with current directory"
else
    kk_test_fail "getFullPath with current directory (got: '$result')"
fi

# Test 5: Parent directory
kk_test_start "getFullPath with parent directory"
result=$(tpath.getFullPath "..")
if [[ -n "$result" && "$result" != ".." ]]; then
    kk_test_pass "getFullPath with parent directory"
else
    kk_test_fail "getFullPath with parent directory (got: '$result')"
fi
