#!/bin/bash
# GetHashCode
# Auto-migrated to ktests framework

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

kt_test_init "GetHashCode" "$SCRIPT_DIR" "$@"

# Source tstringhelper if needed
TSTRINGHELPER_DIR="$SCRIPT_DIR/.."
[[ -f "$TSTRINGHELPER_DIR/tstringhelper.sh" ]] && source "$TSTRINGHELPER_DIR/tstringhelper.sh"


# Test 1: Get hash code for string
kt_test_start "GetHashCode - basic hash"
expected_hash=99100748
result=$(string.getHashCode "hello")
if [[ "$result" == "$expected_hash" ]]; then
    kt_test_pass "GetHashCode - basic hash"
else
    kt_test_fail "GetHashCode - basic hash (expected: $expected_hash, got: '$result')"
fi

# Test 2: Equal strings produce equal hash codes
kt_test_start "GetHashCode - equal strings same hash"
hash1=$(string.getHashCode "test")
hash2=$(string.getHashCode "test")
if [[ "$hash1" == "$hash2" ]]; then
    kt_test_pass "GetHashCode - equal strings same hash"
else
    kt_test_fail "GetHashCode - equal strings same hash (hash1: $hash1, hash2: $hash2)"
fi

# Test 3: Different strings may have different hash codes
kt_test_start "GetHashCode - different strings"
hash1=$(string.getHashCode "apple")
hash2=$(string.getHashCode "banana")
if [[ "$hash1" != "$hash2" ]]; then
    kt_test_pass "GetHashCode - different strings"
else
    kt_test_fail "GetHashCode - different strings (both: $hash1)"
fi

# Test 4: Empty string hash code
kt_test_start "GetHashCode - empty string"
expected_hash=0
result=$(string.getHashCode "")
if [[ "$result" == "$expected_hash" ]]; then
    kt_test_pass "GetHashCode - empty string"
else
    kt_test_fail "GetHashCode - empty string (expected: $expected_hash, got: '$result')"
fi

# Test 5: Case-sensitive hashing (different case should give different hash)
kt_test_start "GetHashCode - case sensitive"
hash1=$(string.getHashCode "Hello")
hash2=$(string.getHashCode "hello")
# In Sydney version, case-sensitive strings should have different hashes
if [[ "$hash1" != "$hash2" ]]; then
    kt_test_pass "GetHashCode - case sensitive"
else
    kt_test_fail "GetHashCode - case sensitive (both: $hash1)"
fi

# Test 6: String with spaces
kt_test_start "GetHashCode - with spaces"
expected_hash=1785210100
result=$(string.getHashCode "hello world")
if [[ "$result" == "$expected_hash" ]]; then
    kt_test_pass "GetHashCode - with spaces"
else
    kt_test_fail "GetHashCode - with spaces (expected: $expected_hash, got: '$result')"
fi

# Test 7: Numeric string
kt_test_start "GetHashCode - numeric string"
expected_hash=1387565185
result=$(string.getHashCode "123456")
if [[ "$result" == "$expected_hash" ]]; then
    kt_test_pass "GetHashCode - numeric string"
else
    kt_test_fail "GetHashCode - numeric string (expected: $expected_hash, got: '$result')"
fi

# Test 8: Special characters
kt_test_start "GetHashCode - special characters"
expected_hash=727658269
result=$(string.getHashCode "hello@world#123")
if [[ "$result" == "$expected_hash" ]]; then
    kt_test_pass "GetHashCode - special characters"
else
    kt_test_fail "GetHashCode - special characters (expected: $expected_hash, got: '$result')"
fi

# Test 9: Single character
kt_test_start "GetHashCode - single character"
expected_hash=97
result=$(string.getHashCode "a")
if [[ "$result" == "$expected_hash" ]]; then
    kt_test_pass "GetHashCode - single character"
else
    kt_test_fail "GetHashCode - single character (expected: $expected_hash, got: '$result')"
fi

# Test 10: Long string
kt_test_start "GetHashCode - long string"
expected_hash=73421106
result=$(string.getHashCode "This is a very long string with many characters to test the hash code function")
if [[ "$result" == "$expected_hash" ]]; then
    kt_test_pass "GetHashCode - long string"
else
    kt_test_fail "GetHashCode - long string (expected: $expected_hash, got: '$result')"
fi

# --- P5: exact values (finding TSH-19) -------------------------------------
# Every assertion above only checks "is an integer" or "two hashes differ", so
# the hash function was free to be anything at all. FPC's TStringHelper.GetHashCode
# is fphash (rtl/objpas/sysutils/syshelp.inc):
#
#     Result := 0;
#     while (p<pmax) do
#       Result := LongWord(LongInt(Result shl 5) - LongInt(Result)) xor LongWord(P^);
#
# i.e. h := int32((h*31) xor c), signed on overflow — NOT the (h+c)*31 the
# port used, which also grew without bound.
#
# TSH-19, documented deviation: FPC walks BYTES (PChar), this port walks CODE
# POINTS, so the two agree on ASCII and differ on anything else. The values
# below are the reference algorithm applied to the code points; for the ASCII
# inputs they are exactly FPC's.
hash_is() {   # EXPECTED INPUT
    kt_test_start "getHashCode $(printf '%q' "$2") -> $1 [TSH-19]"
    RESULT="__unset__"
    string.getHashCode "$2" >/dev/null 2>&1 || :
    if [[ "$RESULT" == "$1" ]]; then
        kt_test_pass "$1"
    else
        kt_test_fail "getHashCode $(printf '%q' "$2") gave '$RESULT', expected '$1'"
    fi
}

hash_is 0           ""
hash_is 97          "a"
hash_is 99100748    "hello"
hash_is 67577900    "Hello"
hash_is 90135784    "apple"
hash_is -1516474589 "banana"
hash_is 1785210100  "hello world"
hash_is 1387565185  "123456"

kt_test_start "the hash stays inside signed 32 bits, like FPC's Integer [TSH-19]"
RESULT="__unset__"
string.getHashCode "a string long enough that an unbounded accumulator would overflow int64" >/dev/null 2>&1 || :
h="$RESULT"
if [[ "$h" =~ ^-?[0-9]+$ ]] && (( h >= -2147483648 && h <= 2147483647 )); then
    kt_test_pass "$h"
else
    kt_test_fail "out of the Integer range: '$h'"
fi

kt_test_start "getHashCode does not fork per character [1.8]"
body="$(declare -f string.__static_getHashCode)"
body="${body//\$((/ARITH}"
if [[ "$body" != *'$('* && "$body" != *'`'* ]]; then
    kt_test_pass "no command substitution"
else
    kt_test_fail "the body forks"
fi
