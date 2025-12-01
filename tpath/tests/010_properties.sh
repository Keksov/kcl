#!/bin/bash
# Properties
# Auto-migrated to ktests framework

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

kt_test_init "Properties" "$SCRIPT_DIR" "$@"

# Source tpath if needed
TPATH_DIR="$SCRIPT_DIR/.."
[[ -f "$TPATH_DIR/tpath.sh" ]] && source "$TPATH_DIR/tpath.sh"


# Test 1: DirectorySeparatorChar
kt_test_start "DirectorySeparatorChar property"
result=$(tpath.getDirectorySeparatorChar | tr -d '\r\n')
case "$(uname -s)" in
    MINGW*|CYGWIN*|MSYS*)
        expected='\\'
        ;;
*)
expected="/"
        ;;
esac

if [[ "$result" == "$expected" ]]; then
    kt_test_pass "DirectorySeparatorChar property"
else
    kt_test_fail "DirectorySeparatorChar property (expected: '$expected', got: '$result')"
fi

# Test 2: AltDirectorySeparatorChar
kt_test_start "AltDirectorySeparatorChar property"
result=$(tpath.getAltDirectorySeparatorChar | tr -d '\r\n')
if [[ "$result" == "/" ]]; then
    kt_test_pass "AltDirectorySeparatorChar property"
else
    kt_test_fail "AltDirectorySeparatorChar property (expected: '/', got: '$result')"
fi

# Test 3: ExtensionSeparatorChar
kt_test_start "ExtensionSeparatorChar property"
result=$(tpath.getExtensionSeparatorChar | tr -d '\r\n')
if [[ "$result" == "." ]]; then
    kt_test_pass "ExtensionSeparatorChar property"
else
    kt_test_fail "ExtensionSeparatorChar property (expected: '.', got: '$result')"
fi

# Test 4: PathSeparator
kt_test_start "PathSeparator property"
result=$(tpath.getPathSeparator | tr -d '\r\n')
case "$(uname -s)" in
    MINGW*|CYGWIN*|MSYS*)
        expected=";"
        ;;
    *)
        expected=":"
        ;;
esac
if [[ "$result" == "$expected" ]]; then
    kt_test_pass "PathSeparator property"
else
    kt_test_fail "PathSeparator property (expected: '$expected', got: '$result')"
fi

# Test 5: VolumeSeparatorChar
kt_test_start "VolumeSeparatorChar property"
result=$(tpath.getVolumeSeparatorChar | tr -d '\r\n')
case "$(uname -s)" in
    MINGW*|CYGWIN*|MSYS*)
        expected=":"
        ;;
    *)
        expected="/"
        ;;
esac
if [[ "$result" == "$expected" ]]; then
    kt_test_pass "VolumeSeparatorChar property"
else
    kt_test_fail "VolumeSeparatorChar property (expected: '$expected', got: '$result')"
fi
