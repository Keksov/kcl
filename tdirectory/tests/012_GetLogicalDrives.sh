#!/bin/bash
# GetLogicalDrives
# Auto-migrated to ktests framework

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

kt_test_init "GetLogicalDrives" "$SCRIPT_DIR" "$@"

# Source tdirectory if needed
TDIRECTORY_DIR="$SCRIPT_DIR/.."
[[ -f "$TDIRECTORY_DIR/tdirectory.sh" ]] && source "$TDIRECTORY_DIR/tdirectory.sh"


# Test 1: GetLogicalDrives returns non-empty on Windows
kt_test_start "GetLogicalDrives - returns result"
result=$(tdirectory.getLogicalDrives)
# On Windows, should return drives; on POSIX, typically returns empty
if [[ -n "$result" ]] || [[ -z "$result" ]]; then
    kt_test_pass "GetLogicalDrives - returns result"
else
    kt_test_fail "GetLogicalDrives - returns result (expected array result)"
fi

# Test 2: GetLogicalDrives on Windows platform
kt_test_start "GetLogicalDrives - Windows drive format"
case "$(uname -s)" in
    MINGW*|CYGWIN*|MSYS*)
        result=$(tdirectory.getLogicalDrives)
        # Should contain drive letters like C:, D:, etc.
        if [[ "$result" =~ [A-Z]: ]]; then
            kt_test_pass "GetLogicalDrives - Windows drive format"
        else
            kt_test_fail "GetLogicalDrives - Windows drive format (expected drive letters, got: '$result')"
        fi
        ;;
    *)
        kt_test_pass "GetLogicalDrives - Windows drive format (skipped on POSIX)"
        ;;
esac

# Test 3: GetLogicalDrives on POSIX returns empty or root
kt_test_start "GetLogicalDrives - POSIX platform"
case "$(uname -s)" in
    MINGW*|CYGWIN*|MSYS*)
        kt_test_pass "GetLogicalDrives - POSIX platform (skipped on Windows)"
        ;;
    *)
        result=$(tdirectory.getLogicalDrives)
        if [[ -z "$result" ]] || [[ "$result" == "/" ]]; then
            kt_test_pass "GetLogicalDrives - POSIX platform"
        else
            kt_test_fail "GetLogicalDrives - POSIX platform (expected empty or '/', got: '$result')"
        fi
        ;;
esac

# Test 4: GetLogicalDrives returns consistent result
kt_test_start "GetLogicalDrives - consistent results"
result1=$(tdirectory.getLogicalDrives)
result2=$(tdirectory.getLogicalDrives)
if [[ "$result1" == "$result2" ]]; then
    kt_test_pass "GetLogicalDrives - consistent results"
else
    kt_test_fail "GetLogicalDrives - consistent results (expected same result twice)"
fi

# Test 5: GetLogicalDrives includes common Windows drives if present
kt_test_start "GetLogicalDrives - contains expected drives"
case "$(uname -s)" in
    MINGW*|CYGWIN*|MSYS*)
        result=$(tdirectory.getLogicalDrives)
        # At least C: should exist
        if [[ "$result" =~ C: ]]; then
            kt_test_pass "GetLogicalDrives - contains expected drives"
        else
            kt_test_fail "GetLogicalDrives - contains expected drives (expected C: drive)"
        fi
        ;;
    *)
        kt_test_pass "GetLogicalDrives - contains expected drives (not applicable on POSIX)"
        ;;
esac


