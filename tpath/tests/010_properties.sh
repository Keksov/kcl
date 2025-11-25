#!/bin/bash
# Properties
# Auto-migrated to kktests framework

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KKTESTS_LIB_DIR="$SCRIPT_DIR/../../../kktests"
source "$KKTESTS_LIB_DIR/kk-test.sh"

kk_test_init "Properties" "$SCRIPT_DIR" "$@"

# Source tpath if needed
TPATH_DIR="$SCRIPT_DIR/.."
[[ -f "$TPATH_DIR/tpath.sh" ]] && source "$TPATH_DIR/tpath.sh"


# Test 1: DirectorySeparatorChar
kk_test_start "DirectorySeparatorChar property"
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
    kk_test_pass "DirectorySeparatorChar property"
else
    kk_test_fail "DirectorySeparatorChar property (expected: '$expected', got: '$result')"
fi

# Test 2: AltDirectorySeparatorChar
kk_test_start "AltDirectorySeparatorChar property"
result=$(tpath.getAltDirectorySeparatorChar | tr -d '\r\n')
if [[ "$result" == "/" ]]; then
    kk_test_pass "AltDirectorySeparatorChar property"
else
    kk_test_fail "AltDirectorySeparatorChar property (expected: '/', got: '$result')"
fi

# Test 3: ExtensionSeparatorChar
kk_test_start "ExtensionSeparatorChar property"
result=$(tpath.getExtensionSeparatorChar | tr -d '\r\n')
if [[ "$result" == "." ]]; then
    kk_test_pass "ExtensionSeparatorChar property"
else
    kk_test_fail "ExtensionSeparatorChar property (expected: '.', got: '$result')"
fi

# Test 4: PathSeparator
kk_test_start "PathSeparator property"
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
    kk_test_pass "PathSeparator property"
else
    kk_test_fail "PathSeparator property (expected: '$expected', got: '$result')"
fi

# Test 5: VolumeSeparatorChar
kk_test_start "VolumeSeparatorChar property"
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
    kk_test_pass "VolumeSeparatorChar property"
else
    kk_test_fail "VolumeSeparatorChar property (expected: '$expected', got: '$result')"
fi
