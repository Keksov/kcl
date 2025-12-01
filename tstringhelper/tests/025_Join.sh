#!/bin/bash
# Join
# Auto-migrated to ktests framework

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

kt_test_init "Join" "$SCRIPT_DIR" "$@"

# Source tstringhelper if needed
TSTRINGHELPER_DIR="$SCRIPT_DIR/.."
[[ -f "$TSTRINGHELPER_DIR/tstringhelper.sh" ]] && source "$TSTRINGHELPER_DIR/tstringhelper.sh"


# Test 1: Join two strings
kt_test_start "Join - two strings"
result=$(string.join "," "hello" "world")
if [[ "$result" == "hello,world" ]]; then
    kt_test_pass "Join - two strings"
else
    kt_test_fail "Join - two strings (expected: 'hello,world', got: '$result')"
fi

# Test 2: Join three strings
kt_test_start "Join - three strings"
result=$(string.join "-" "a" "b" "c")
if [[ "$result" == "a-b-c" ]]; then
    kt_test_pass "Join - three strings"
else
    kt_test_fail "Join - three strings (expected: 'a-b-c', got: '$result')"
fi

# Test 3: Empty separator
kt_test_start "Join - empty separator"
result=$(string.join "" "hello" "world")
if [[ "$result" == "helloworld" ]]; then
    kt_test_pass "Join - empty separator"
else
    kt_test_fail "Join - empty separator (expected: 'helloworld', got: '$result')"
fi

# Test 4: Space separator
kt_test_start "Join - space separator"
result=$(string.join " " "hello" "world")
if [[ "$result" == "hello world" ]]; then
    kt_test_pass "Join - space separator"
else
    kt_test_fail "Join - space separator (expected: 'hello world', got: '$result')"
fi

# Test 5: Empty string in array
kt_test_start "Join - empty string in array"
result=$(string.join "," "hello" "" "world")
if [[ "$result" == "hello,,world" ]]; then
    kt_test_pass "Join - empty string in array"
else
    kt_test_fail "Join - empty string in array (expected: 'hello,,world', got: '$result')"
fi

# Test 6: Single string
kt_test_start "Join - single string"
result=$(string.join "," "hello")
if [[ "$result" == "hello" ]]; then
    kt_test_pass "Join - single string"
else
    kt_test_fail "Join - single string (expected: 'hello', got: '$result')"
fi

# Test 7: Numeric separator
kt_test_start "Join - numeric separator"
result=$(string.join "|" "one" "two" "three")
if [[ "$result" == "one|two|three" ]]; then
    kt_test_pass "Join - numeric separator"
else
    kt_test_fail "Join - numeric separator (expected: 'one|two|three', got: '$result')"
fi

# Test 8: Multiple character separator
kt_test_start "Join - multiple character separator"
result=$(string.join "::" "a" "b" "c")
if [[ "$result" == "a::b::c" ]]; then
    kt_test_pass "Join - multiple character separator"
else
    kt_test_fail "Join - multiple character separator (expected: 'a::b::c', got: '$result')"
fi

# Test 9: Join with numeric strings
kt_test_start "Join - numeric strings"
result=$(string.join "-" "1" "2" "3")
if [[ "$result" == "1-2-3" ]]; then
    kt_test_pass "Join - numeric strings"
else
    kt_test_fail "Join - numeric strings (expected: '1-2-3', got: '$result')"
fi

# Test 10: Join with special characters
kt_test_start "Join - special characters"
result=$(string.join "," "hello@" "world#" "test!")
if [[ "$result" == "hello@,world#,test!" ]]; then
    kt_test_pass "Join - special characters"
else
    kt_test_fail "Join - special characters (expected: 'hello@,world#,test!', got: '$result')"
fi

# Test 11: Join many strings
kt_test_start "Join - many strings"
result=$(string.join "," "a" "b" "c" "d" "e" "f")
if [[ "$result" == "a,b,c,d,e,f" ]]; then
    kt_test_pass "Join - many strings"
else
    kt_test_fail "Join - many strings (expected: 'a,b,c,d,e,f', got: '$result')"
fi

# Test 12: Separator with spaces
kt_test_start "Join - separator with spaces"
result=$(string.join " and " "hello" "world")
if [[ "$result" == "hello and world" ]]; then
    kt_test_pass "Join - separator with spaces"
else
    kt_test_fail "Join - separator with spaces (expected: 'hello and world', got: '$result')"
fi

# Test 13: No arguments (edge case)
kt_test_start "Join - no arguments"
result=$(string.join ",")
if [[ "$result" == "" ]]; then
    kt_test_pass "Join - no arguments"
else
    kt_test_fail "Join - no arguments (expected: '', got: '$result')"
fi

# Test 14: Single empty string
kt_test_start "Join - single empty string"
result=$(string.join "," "")
if [[ "$result" == "" ]]; then
    kt_test_pass "Join - single empty string"
else
    kt_test_fail "Join - single empty string (expected: '', got: '$result')"
fi

# Test 15: Many empty strings
kt_test_start "Join - many empty strings"
result=$(string.join "," "" "" "" "")
if [[ "$result" == ",,," ]]; then
    kt_test_pass "Join - many empty strings"
else
    kt_test_fail "Join - many empty strings (expected: ',,,', got: '$result')"
fi

# Test 16: Null handling
kt_test_start "Join - null string handling"
result=$(string.join "," "hello" "" "world")
if [[ "$result" == "hello,,world" ]]; then
    kt_test_pass "Join - null string handling"
else
    kt_test_fail "Join - null string handling (expected: 'hello,,world', got: '$result')"
fi

# Test 17: Very long separator
kt_test_start "Join - very long separator"
long_separator="--------------------------------------------------------"
result=$(string.join "$long_separator" "a" "b")
if [[ "$result" == "a$long_separator"b ]]; then
    kt_test_pass "Join - very long separator"
else
    kt_test_fail "Join - very long separator (expected: concatenated with long separator, got: '$result')"
fi

# Test 18: Many strings (stress test)
kt_test_start "Join - many strings stress test"
result=$(string.join "," "a" "b" "c" "d" "e" "f" "g" "h" "i" "j" "k" "l" "m" "n" "o" "p")
if [[ "$result" == "a,b,c,d,e,f,g,h,i,j,k,l,m,n,o,p" ]]; then
    kt_test_pass "Join - many strings stress test"
else
    kt_test_fail "Join - many strings stress test (expected: 16 elements joined, got: '$result')"
fi

# Test 19: Unicode strings
kt_test_start "Join - unicode strings"
result=$(string.join " " "Hello" "Мир" "世界")
if [[ "$result" == "Hello Мир 世界" ]]; then
    kt_test_pass "Join - unicode strings"
else
    kt_test_fail "Join - unicode strings (expected: 'Hello Мир 世界', got: '$result')"
fi

# Test 20: Special characters in strings
kt_test_start "Join - special characters in strings"
result=$(string.join "|" "hello@world" "test#123" "foo\$bar")
if [[ "$result" == "hello@world|test#123|foo\$bar" ]]; then
    kt_test_pass "Join - special characters in strings"
else
    kt_test_fail "Join - special characters in strings (expected: special chars preserved, got: '$result')"
fi

# Test 21: Newline characters
kt_test_start "Join - newline characters"
string1=$'line1
line2'
string2=$'line3
line4'
result=$(string.join "," "$string1" "$string2")
if [[ "$result" == *$'\nline2'* && "$result" == *$'\nline4'* ]]; then
    kt_test_pass "Join - newline characters"
else
    kt_test_fail "Join - newline characters (expected: newlines preserved, got: '$result')"
fi

# Test 22: Tab characters
kt_test_start "Join - tab characters"
result=$(string.join "," "field1	" "	 field2" "	")
if [[ "$result" == *"field1	"* && "$result" == *"	 field2"* ]]; then
    kt_test_pass "Join - tab characters"
else
    kt_test_fail "Join - tab characters (expected: tabs preserved, got: '$result')"
fi

# Test 23: Leading/trailing spaces in separator
kt_test_start "Join - separator with leading/trailing spaces"
result=$(string.join "  " "a" "b")
if [[ "$result" == "a  b" ]]; then
    kt_test_pass "Join - separator with leading/trailing spaces"
else
    kt_test_fail "Join - separator with leading/trailing spaces (expected: 'a  b', got: '$result')"
fi

# Test 24: Mixed content types
kt_test_start "Join - mixed content types"
result=$(string.join ";" "123" "" "abc" "456" "" "789")
if [[ "$result" == "123;;abc;456;;789" ]]; then
    kt_test_pass "Join - mixed content types"
else
    kt_test_fail "Join - mixed content types (expected: '123;;abc;456;;789', got: '$result')"
fi

# Test 25: Empty separator with multiple strings
kt_test_start "Join - empty separator multiple strings"
result=$(string.join "" "hello" "world" "test")
if [[ "$result" == "helloworldtest" ]]; then
    kt_test_pass "Join - empty separator multiple strings"
else
    kt_test_fail "Join - empty separator multiple strings (expected: 'helloworldtest', got: '$result')"
fi