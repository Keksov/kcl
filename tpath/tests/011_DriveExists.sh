#!/bin/bash
# DriveExists
# Auto-migrated to kktests framework

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KKTESTS_LIB_DIR="$SCRIPT_DIR/../../../kktests"
source "$KKTESTS_LIB_DIR/kk-test.sh"

kk_test_init "DriveExists" "$SCRIPT_DIR" "$@"

# Source tpath if needed
TPATH_DIR="$SCRIPT_DIR/.."
[[ -f "$TPATH_DIR/tpath.sh" ]] && source "$TPATH_DIR/tpath.sh"


# Test 1: Empty path
kk_test_start "DriveExists with empty path"
result=$(tpath.driveExists "")
if [[ "$result" == "false" ]]; then
    kk_test_pass "DriveExists with empty path"
else
    kk_test_fail "DriveExists with empty path (expected: false, got: '$result')"
fi

# Test 2: Invalid drive on POSIX
kk_test_start "DriveExists with invalid drive on POSIX"
case "$(uname -s)" in
    MINGW*|CYGWIN*|MSYS*)
        # Skip on Windows
        kk_test_pass "DriveExists with invalid drive on POSIX (skipped on Windows)"
        ;;
    *)
        result=$(tpath.driveExists "C:")
        if [[ "$result" == "false" ]]; then
            kk_test_pass "DriveExists with invalid drive on POSIX"
        else
            kk_test_fail "DriveExists with invalid drive on POSIX (expected: false, got: '$result')"
        fi
        ;;
esac

# Test 3: No drive letter
kk_test_start "DriveExists with no drive letter"
result=$(tpath.driveExists "/path/to/file")
if [[ "$result" == "false" ]]; then
    kk_test_pass "DriveExists with no drive letter"
else
    kk_test_fail "DriveExists with no drive letter (expected: false, got: '$result')"
fi

# Test 4: Valid drive letter on Windows
case "$(uname -s)" in
    MINGW*|CYGWIN*|MSYS*)
        kk_test_start "DriveExists with valid drive on Windows"
        # Try C: drive
        result=$(tpath.driveExists "C:")
        if [[ "$result" == "true" ]]; then
            kk_test_pass "DriveExists with valid drive on Windows"
        else
            kk_test_fail "DriveExists with valid drive on Windows (expected: true, got: '$result')"
        fi
        ;;
    *)
        # Skip on POSIX
        kk_test_pass "DriveExists with valid drive on Windows (skipped on POSIX)"
        ;;
esac
