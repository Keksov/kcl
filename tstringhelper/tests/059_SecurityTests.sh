#!/bin/bash
# SecurityTests - regression guard for P1.3: arithmetic-evaluation injection in
# string.toInteger / string.toInt64. Bash evaluates array subscripts inside
# $(( )), so unvalidated input like 'a[$(cmd)]' would execute cmd.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

kt_test_init "SecurityTests" "$SCRIPT_DIR" "$@"

TSTRINGHELPER_DIR="$SCRIPT_DIR/.."
[[ -f "$TSTRINGHELPER_DIR/tstringhelper.sh" ]] && source "$TSTRINGHELPER_DIR/tstringhelper.sh"

kt_test_start "string.toInteger does not execute an injected command"
_pwn="${TMPDIR:-/tmp}/.sh_int_pwn_$$"
rm -f "$_pwn"
string.toInteger 'a[$(touch '"$_pwn"')]' >/dev/null 2>&1
if [[ ! -f "$_pwn" ]]; then
    kt_test_pass "string.toInteger does not execute an injected command"
else
    rm -f "$_pwn"
    kt_test_fail "string.toInteger executed an injected command"
fi

kt_test_start "string.toInt64 does not execute an injected command"
_pwn2="${TMPDIR:-/tmp}/.sh_i64_pwn_$$"
rm -f "$_pwn2"
string.toInt64 'x[$(touch '"$_pwn2"')]' >/dev/null 2>&1
if [[ ! -f "$_pwn2" ]]; then
    kt_test_pass "string.toInt64 does not execute an injected command"
else
    rm -f "$_pwn2"
    kt_test_fail "string.toInt64 executed an injected command"
fi

# Functional contract must be preserved after the security fix.
kt_test_start "string.toInteger parses a valid integer"
_r=$(string.toInteger "123")
if [[ "$_r" == "123" ]]; then
    kt_test_pass "string.toInteger parses a valid integer"
else
    kt_test_fail "expected 123, got '$_r'"
fi

kt_test_start "string.toInteger strips the fractional part"
_r=$(string.toInteger "42.99")
if [[ "$_r" == "42" ]]; then
    kt_test_pass "string.toInteger strips the fractional part"
else
    kt_test_fail "expected 42, got '$_r'"
fi

kt_test_start "string.toInteger handles a negative integer"
_r=$(string.toInteger "-7")
if [[ "$_r" == "-7" ]]; then
    kt_test_pass "string.toInteger handles a negative integer"
else
    kt_test_fail "expected -7, got '$_r'"
fi

kt_test_start "string.toInteger returns 0 for non-numeric input"
_r=$(string.toInteger "hello")
if [[ "$_r" == "0" ]]; then
    kt_test_pass "string.toInteger returns 0 for non-numeric input"
else
    kt_test_fail "expected 0, got '$_r'"
fi
