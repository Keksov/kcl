#!/bin/bash
# SystemPaths
# Auto-migrated to kktests framework

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KKTESTS_LIB_DIR="$SCRIPT_DIR/../../../kktests"
source "$KKTESTS_LIB_DIR/kk-test.sh"

kk_test_init "SystemPaths" "$SCRIPT_DIR" "$@"

# Source tpath if needed
TPATH_DIR="$SCRIPT_DIR/.."
[[ -f "$TPATH_DIR/tpath.sh" ]] && source "$TPATH_DIR/tpath.sh"


# Test 1: getTempPath returns non-empty
kk_test_start "getTempPath returns non-empty path"
result=$(tpath.getTempPath)
if [[ -n "$result" && -d "$result" ]]; then
    kk_test_pass "getTempPath returns non-empty path"
else
    kk_test_fail "getTempPath returns non-empty path (got: '$result')"
fi

# Test 2: getHomePath returns non-empty
kk_test_start "getHomePath returns non-empty path"
result=$(tpath.getHomePath)
if [[ -n "$result" && -d "$result" ]]; then
    kk_test_pass "getHomePath returns non-empty path"
else
    kk_test_fail "getHomePath returns non-empty path (got: '$result')"
fi

# Test 3: getDocumentsPath returns non-empty
kk_test_start "getDocumentsPath returns a path"
result=$(tpath.getDocumentsPath)
if [[ -n "$result" ]]; then
    kk_test_pass "getDocumentsPath returns a path"
else
    kk_test_fail "getDocumentsPath returns a path (got empty)"
fi

# Test 4: getDownloadsPath returns non-empty
kk_test_start "getDownloadsPath returns a path"
result=$(tpath.getDownloadsPath)
if [[ -n "$result" ]]; then
    kk_test_pass "getDownloadsPath returns a path"
else
    kk_test_fail "getDownloadsPath returns a path (got empty)"
fi

# Test 5: getTempFileName creates file
kk_test_start "getTempFileName creates a file"
result=$(tpath.getTempFileName)
if [[ -n "$result" && -f "$result" ]]; then
    kk_test_pass "getTempFileName creates a file"
    rm -f "$result"  # Cleanup
else
    kk_test_fail "getTempFileName creates a file (got: '$result')"
fi

# Test 6: getGUIDFileName returns non-empty
kk_test_start "getGUIDFileName returns non-empty string"
result=$(tpath.getGUIDFileName)
if [[ -n "$result" ]]; then
    kk_test_pass "getGUIDFileName returns non-empty string"
else
    kk_test_fail "getGUIDFileName returns non-empty string (got empty)"
fi

# Test 7: getGUIDFileName with separator
kk_test_start "getGUIDFileName with separator"
result=$(tpath.getGUIDFileName "true")
if [[ -n "$result" && "$result" == *"-"* ]]; then
    kk_test_pass "getGUIDFileName with separator"
else
    kk_test_fail "getGUIDFileName with separator (expected dashes, got: '$result')"
fi

# Test 8: getGUIDFileName without separator
kk_test_start "getGUIDFileName without separator"
result=$(tpath.getGUIDFileName "false")
if [[ -n "$result" && "$result" != *"-"* ]]; then
    kk_test_pass "getGUIDFileName without separator"
else
    kk_test_fail "getGUIDFileName without separator (got: '$result')"
fi

# Test 9: getRandomFileName returns non-empty
kk_test_start "getRandomFileName returns non-empty string"
result=$(tpath.getRandomFileName)
if [[ -n "$result" ]]; then
    kk_test_pass "getRandomFileName returns non-empty string"
else
    kk_test_fail "getRandomFileName returns non-empty string (got empty)"
fi

# Test 10: getTempPath is absolute
kk_test_start "getTempPath returns absolute path"
result=$(tpath.getTempPath)
if [[ "$result" == /* ]] || [[ "$result" =~ ^[A-Za-z]: ]]; then
    kk_test_pass "getTempPath returns absolute path"
else
    kk_test_fail "getTempPath returns absolute path (got: '$result')"
fi
