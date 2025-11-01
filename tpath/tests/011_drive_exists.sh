#!/bin/bash
# 011_drive_exists.sh - Test TPath.driveExists method

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
parse_args "$@"

# Test 1: Empty path
test_start "DriveExists with empty path"
result=$(tpath.driveExists "")
if [[ "$result" == "false" ]]; then
    test_pass "DriveExists with empty path"
else
    test_fail "DriveExists with empty path (expected: false, got: '$result')"
fi

# Test 2: Invalid drive on POSIX
test_start "DriveExists with invalid drive on POSIX"
case "$(uname -s)" in
    MINGW*|CYGWIN*|MSYS*)
        # Skip on Windows
        test_pass "DriveExists with invalid drive on POSIX (skipped on Windows)"
        ;;
    *)
        result=$(tpath.driveExists "C:")
        if [[ "$result" == "false" ]]; then
            test_pass "DriveExists with invalid drive on POSIX"
        else
            test_fail "DriveExists with invalid drive on POSIX (expected: false, got: '$result')"
        fi
        ;;
esac

# Test 3: No drive letter
test_start "DriveExists with no drive letter"
result=$(tpath.driveExists "/path/to/file")
if [[ "$result" == "false" ]]; then
    test_pass "DriveExists with no drive letter"
else
    test_fail "DriveExists with no drive letter (expected: false, got: '$result')"
fi

# Test 4: Valid drive letter on Windows
case "$(uname -s)" in
    MINGW*|CYGWIN*|MSYS*)
        test_start "DriveExists with valid drive on Windows"
        # Try C: drive
        result=$(tpath.driveExists "C:")
        if [[ "$result" == "true" ]]; then
            test_pass "DriveExists with valid drive on Windows"
        else
            test_fail "DriveExists with valid drive on Windows (expected: true, got: '$result')"
        fi
        ;;
    *)
        # Skip on POSIX
        test_pass "DriveExists with valid drive on Windows (skipped on POSIX)"
        ;;
esac
