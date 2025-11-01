#!/bin/bash
# 010_properties.sh - Test TPath properties

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
parse_args "$@"

# Test 1: DirectorySeparatorChar
test_start "DirectorySeparatorChar property"
result=$(tpath.getDirectorySeparatorChar)
case "$(uname -s)" in
    MINGW*|CYGWIN*|MSYS*)
        expected="\\"
        ;;
    *)
        expected="/"
        ;;
esac
if [[ "$result" == "$expected" ]]; then
    test_pass "DirectorySeparatorChar property"
else
    test_fail "DirectorySeparatorChar property (expected: '$expected', got: '$result')"
fi

# Test 2: AltDirectorySeparatorChar
test_start "AltDirectorySeparatorChar property"
result=$(tpath.getAltDirectorySeparatorChar)
if [[ "$result" == "/" ]]; then
    test_pass "AltDirectorySeparatorChar property"
else
    test_fail "AltDirectorySeparatorChar property (expected: '/', got: '$result')"
fi

# Test 3: ExtensionSeparatorChar
test_start "ExtensionSeparatorChar property"
result=$(tpath.getExtensionSeparatorChar)
if [[ "$result" == "." ]]; then
    test_pass "ExtensionSeparatorChar property"
else
    test_fail "ExtensionSeparatorChar property (expected: '.', got: '$result')"
fi

# Test 4: PathSeparator
test_start "PathSeparator property"
result=$(tpath.getPathSeparator)
case "$(uname -s)" in
    MINGW*|CYGWIN*|MSYS*)
        expected=";"
        ;;
    *)
        expected=":"
        ;;
esac
if [[ "$result" == "$expected" ]]; then
    test_pass "PathSeparator property"
else
    test_fail "PathSeparator property (expected: '$expected', got: '$result')"
fi

# Test 5: VolumeSeparatorChar
test_start "VolumeSeparatorChar property"
result=$(tpath.getVolumeSeparatorChar)
case "$(uname -s)" in
    MINGW*|CYGWIN*|MSYS*)
        expected=":"
        ;;
    *)
        expected="/"
        ;;
esac
if [[ "$result" == "$expected" ]]; then
    test_pass "VolumeSeparatorChar property"
else
    test_fail "VolumeSeparatorChar property (expected: '$expected', got: '$result')"
fi
