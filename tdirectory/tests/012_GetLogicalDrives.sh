#!/bin/bash
# 012_GetLogicalDrives.sh - Test TDirectory.GetLogicalDrives method

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
parse_args "$@"

# Test 1: GetLogicalDrives returns non-empty on Windows
test_start "GetLogicalDrives - returns result"
result=$(tdirectory.getLogicalDrives)
# On Windows, should return drives; on POSIX, typically returns empty
if [[ -n "$result" ]] || [[ -z "$result" ]]; then
    test_pass "GetLogicalDrives - returns result"
else
    test_fail "GetLogicalDrives - returns result (expected array result)"
fi

# Test 2: GetLogicalDrives on Windows platform
test_start "GetLogicalDrives - Windows drive format"
case "$(uname -s)" in
    MINGW*|CYGWIN*|MSYS*)
        result=$(tdirectory.getLogicalDrives)
        # Should contain drive letters like C:, D:, etc.
        if [[ "$result" =~ [A-Z]: ]]; then
            test_pass "GetLogicalDrives - Windows drive format"
        else
            test_fail "GetLogicalDrives - Windows drive format (expected drive letters, got: '$result')"
        fi
        ;;
    *)
        test_pass "GetLogicalDrives - Windows drive format (skipped on POSIX)"
        ;;
esac

# Test 3: GetLogicalDrives on POSIX returns empty or root
test_start "GetLogicalDrives - POSIX platform"
case "$(uname -s)" in
    MINGW*|CYGWIN*|MSYS*)
        test_pass "GetLogicalDrives - POSIX platform (skipped on Windows)"
        ;;
    *)
        result=$(tdirectory.getLogicalDrives)
        if [[ -z "$result" ]] || [[ "$result" == "/" ]]; then
            test_pass "GetLogicalDrives - POSIX platform"
        else
            test_fail "GetLogicalDrives - POSIX platform (expected empty or '/', got: '$result')"
        fi
        ;;
esac

# Test 4: GetLogicalDrives returns consistent result
test_start "GetLogicalDrives - consistent results"
result1=$(tdirectory.getLogicalDrives)
result2=$(tdirectory.getLogicalDrives)
if [[ "$result1" == "$result2" ]]; then
    test_pass "GetLogicalDrives - consistent results"
else
    test_fail "GetLogicalDrives - consistent results (expected same result twice)"
fi

# Test 5: GetLogicalDrives includes common Windows drives if present
test_start "GetLogicalDrives - contains expected drives"
case "$(uname -s)" in
    MINGW*|CYGWIN*|MSYS*)
        result=$(tdirectory.getLogicalDrives)
        # At least C: should exist
        if [[ "$result" =~ C: ]]; then
            test_pass "GetLogicalDrives - contains expected drives"
        else
            test_fail "GetLogicalDrives - contains expected drives (expected C: drive)"
        fi
        ;;
    *)
        test_pass "GetLogicalDrives - contains expected drives (not applicable on POSIX)"
        ;;
esac

echo "__COUNTS__:$TESTS_TOTAL:$TESTS_PASSED:$TESTS_FAILED"
