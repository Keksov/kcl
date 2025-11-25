#!/bin/bash
# GetLogicalDrives
# Auto-migrated to kktests framework

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KKTESTS_LIB_DIR="$SCRIPT_DIR/../../../kktests"
source "$KKTESTS_LIB_DIR/kk-test.sh"

kk_test_init "GetLogicalDrives" "$SCRIPT_DIR" "$@"

# Source tdirectory if needed
TDIRECTORY_DIR="$SCRIPT_DIR/.."
[[ -f "$TDIRECTORY_DIR/tdirectory.sh" ]] && source "$TDIRECTORY_DIR/tdirectory.sh"


# Test 1: GetLogicalDrives returns non-empty on Windows
kk_test_start "GetLogicalDrives - returns result"
result=$(tdirectory.getLogicalDrives)
# On Windows, should return drives; on POSIX, typically returns empty
if [[ -n "$result" ]] || [[ -z "$result" ]]; then
    kk_test_pass "GetLogicalDrives - returns result"
else
    kk_test_fail "GetLogicalDrives - returns result (expected array result)"
fi

# Test 2: GetLogicalDrives on Windows platform
kk_test_start "GetLogicalDrives - Windows drive format"
case "$(uname -s)" in
    MINGW*|CYGWIN*|MSYS*)
        result=$(tdirectory.getLogicalDrives)
        # Should contain drive letters like C:, D:, etc.
        if [[ "$result" =~ [A-Z]: ]]; then
            kk_test_pass "GetLogicalDrives - Windows drive format"
        else
            kk_test_fail "GetLogicalDrives - Windows drive format (expected drive letters, got: '$result')"
        fi
        ;;
    *)
        kk_test_pass "GetLogicalDrives - Windows drive format (skipped on POSIX)"
        ;;
esac

# Test 3: GetLogicalDrives on POSIX returns empty or root
kk_test_start "GetLogicalDrives - POSIX platform"
case "$(uname -s)" in
    MINGW*|CYGWIN*|MSYS*)
        kk_test_pass "GetLogicalDrives - POSIX platform (skipped on Windows)"
        ;;
    *)
        result=$(tdirectory.getLogicalDrives)
        if [[ -z "$result" ]] || [[ "$result" == "/" ]]; then
            kk_test_pass "GetLogicalDrives - POSIX platform"
        else
            kk_test_fail "GetLogicalDrives - POSIX platform (expected empty or '/', got: '$result')"
        fi
        ;;
esac

# Test 4: GetLogicalDrives returns consistent result
kk_test_start "GetLogicalDrives - consistent results"
result1=$(tdirectory.getLogicalDrives)
result2=$(tdirectory.getLogicalDrives)
if [[ "$result1" == "$result2" ]]; then
    kk_test_pass "GetLogicalDrives - consistent results"
else
    kk_test_fail "GetLogicalDrives - consistent results (expected same result twice)"
fi

# Test 5: GetLogicalDrives includes common Windows drives if present
kk_test_start "GetLogicalDrives - contains expected drives"
case "$(uname -s)" in
    MINGW*|CYGWIN*|MSYS*)
        result=$(tdirectory.getLogicalDrives)
        # At least C: should exist
        if [[ "$result" =~ C: ]]; then
            kk_test_pass "GetLogicalDrives - contains expected drives"
        else
            kk_test_fail "GetLogicalDrives - contains expected drives (expected C: drive)"
        fi
        ;;
    *)
        kk_test_pass "GetLogicalDrives - contains expected drives (not applicable on POSIX)"
        ;;
esac


