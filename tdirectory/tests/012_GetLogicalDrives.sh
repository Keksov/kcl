#!/bin/bash
# GetLogicalDrives
#
# Rewritten for P3 (review 2026-09-06): Test 1 was
# `if [[ -n "$result" ]] || [[ -z "$result" ]]` — a tautology that passes for
# every possible answer, including a crash that produced nothing. The member
# also forked `$(uname -s)` on every call (G6-16); the platform is a load-time
# constant that tpath already computed.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

kt_test_init "GetLogicalDrives" "$SCRIPT_DIR" "$@"

# Source tdirectory if needed
TDIRECTORY_DIR="$SCRIPT_DIR/.."
[[ -f "$TDIRECTORY_DIR/tdirectory.sh" ]] && source "$TDIRECTORY_DIR/tdirectory.sh"

IS_WINDOWS=0
case "$(uname -s)" in
    MINGW*|CYGWIN*|MSYS*) IS_WINDOWS=1 ;;
esac

# Test 1: the answer names exactly the drives that are mounted
kt_test_start "GetLogicalDrives - lists exactly the mounted drives"
result=$(tdirectory.getLogicalDrives)
if (( IS_WINDOWS )); then
    expected=""
    for letter in {C..Z}; do
        if [[ -d "/${letter,}" ]]; then
            expected="${expected}${letter}: "
        fi
    done
    expected="${expected% }"
else
    expected="/"
fi
if [[ "$result" == "$expected" ]]; then
    kt_test_pass "GetLogicalDrives - lists exactly the mounted drives ('$result')"
else
    kt_test_fail "GetLogicalDrives - expected '$expected', got '$result'"
fi

# Test 2: on Windows every entry has the "X: " shape
kt_test_start "GetLogicalDrives - Windows drive format"
if (( IS_WINDOWS )); then
    result=$(tdirectory.getLogicalDrives)
    ok=1
    for entry in $result; do
        [[ "$entry" =~ ^[C-Z]:$ ]] || ok=0
    done
    if (( ok )) && [[ -n "$result" ]]; then
        kt_test_pass "GetLogicalDrives - Windows drive format ('$result')"
    else
        kt_test_fail "GetLogicalDrives - Windows drive format (got '$result')"
    fi
else
    result=$(tdirectory.getLogicalDrives)
    if [[ "$result" == "/" ]]; then
        kt_test_pass "GetLogicalDrives - POSIX answers the root"
    else
        kt_test_fail "GetLogicalDrives - POSIX answers the root (got '$result')"
    fi
fi

# Test 3: the C: drive is present on Windows, and nothing unmounted is
kt_test_start "GetLogicalDrives - contains C: and nothing unmounted"
if (( IS_WINDOWS )); then
    result=$(tdirectory.getLogicalDrives)
    missing=""
    for letter in Q R S T U V W X Y Z; do
        if [[ ! -d "/${letter,}" ]]; then missing="$letter"; break; fi
    done
    if [[ "$result" == *"C:"* ]] && { [[ -z "$missing" ]] || [[ "$result" != *"$missing:"* ]]; }; then
        kt_test_pass "GetLogicalDrives - contains C:, not $missing: ('$result')"
    else
        kt_test_fail "GetLogicalDrives - got '$result' (missing-letter probe: $missing)"
    fi
else
    kt_test_pass "GetLogicalDrives - drive letters are a Windows notion (skipped on POSIX)"
fi

# Test 4: the answer is stable
kt_test_start "GetLogicalDrives - consistent results"
result1=$(tdirectory.getLogicalDrives)
result2=$(tdirectory.getLogicalDrives)
if [[ "$result1" == "$result2" && -n "$result1" ]]; then
    kt_test_pass "GetLogicalDrives - consistent results"
else
    kt_test_fail "GetLogicalDrives - consistent results ('$result1' vs '$result2')"
fi

# Test 5: the direct call is silent and answers through RESULT (decision D3)
kt_test_start "GetLogicalDrives - direct call is silent and sets RESULT [D3]"
out_file="$_KT_TMPDIR/drives.out"
: > "$out_file"
tdirectory.getLogicalDrives > "$out_file"
printed="$(<"$out_file")"
if [[ -z "$printed" && -n "$RESULT" ]]; then
    kt_test_pass "GetLogicalDrives - RESULT='$RESULT', nothing printed"
else
    kt_test_fail "GetLogicalDrives - printed='$printed' RESULT='$RESULT'"
fi

# Cleanup
kt_fixture_teardown
