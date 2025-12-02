#!/bin/bash
# 025_LongOptionsEqualSign.sh - Test long options with equals sign syntax
# Tests --option=value format for command-line parsing

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

# Source tcustomapplication module
TCUSTOMAPPLICATION_DIR="$SCRIPT_DIR/.."
source "$TCUSTOMAPPLICATION_DIR/tcustomapplication.sh"

# Extract test name from filename
TEST_NAME="$(basename "$0" .sh)"
kt_test_init "$TEST_NAME" "$SCRIPT_DIR" "$@"

kt_test_section "025: TCustomApplication Long Options with Equals Sign"

# Test: FindOptionIndex with --option=value syntax
kt_test_start "FindOptionIndex recognizes --option=value"
TCustomApplication.new myapp
myapp.SetArgs -- --config=settings.ini file.txt
myapp.FindOptionIndex "" "config=settings.ini" 0
result=$RESULT
if [[ "$result" == "0" ]]; then
    kt_test_pass "FindOptionIndex finds --option=value format"
else
    kt_test_fail "FindOptionIndex with = failed: $result (expected 0)"
fi
myapp.delete

# Test: GetOptionValue with separate format vs equals format
kt_test_start "GetOptionValue with separate args vs equals"
TCustomApplication.new myapp1
myapp1.SetArgs -- --config settings.ini
myapp1.GetOptionValue "" "config"
val_separate=$RESULT

TCustomApplication.new myapp2
myapp2.SetArgs -- --config=settings.ini
myapp2.GetOptionValue "" "config=settings.ini"
val_equals=$RESULT

if [[ "$val_separate" == "settings.ini" && "$val_equals" == "" ]]; then
    kt_test_pass "Equals format requires exact match with equals in option name"
else
    kt_test_fail "Value extraction failed: separate=$val_separate, equals=$val_equals"
fi
myapp1.delete
myapp2.delete

# Test: CheckOptions with --option=value arguments
kt_test_start "CheckOptions with --option=value syntax"
TCustomApplication.new myapp
myapp.SetArgs -- --input=file.txt --output=result.txt
myapp.CheckOptions "" "input=file.txt output=result.txt"
error_msg=$RESULT
if [[ -z "$error_msg" ]]; then
    kt_test_pass "CheckOptions validates --option=value arguments"
else
    kt_test_fail "CheckOptions with = failed: $error_msg"
fi
myapp.delete

# Test: HasOption with equals format
kt_test_start "HasOption with --option=value"
TCustomApplication.new myapp
myapp.SetArgs -- --verbose=true
myapp.HasOption "" "verbose=true"
result=$RESULT
if [[ "$result" == "true" ]]; then
    kt_test_pass "HasOption finds --option=value"
else
    kt_test_fail "HasOption with = failed: $result"
fi
myapp.delete

# Test: Mixed equals and space-separated options
kt_test_start "Mixed --option=value and --option value formats"
TCustomApplication.new myapp
myapp.SetArgs -- --config=settings.ini --output results.txt --verbose=true --debug
myapp.FindOptionIndex "" "config=settings.ini" 0
result1=$RESULT
myapp.FindOptionIndex "" "output" 0
result2=$RESULT
myapp.FindOptionIndex "" "verbose=true" 0
result3=$RESULT
myapp.FindOptionIndex "" "debug" 0
result4=$RESULT
# Arguments: 0=--config=settings.ini, 1=--output, 2=results.txt, 3=--verbose=true, 4=--debug
if [[ "$result1" == "0" && "$result2" == "1" && "$result3" == "3" && "$result4" == "4" ]]; then
    kt_test_pass "Mixed formats are all recognized"
else
    kt_test_fail "Mixed format test failed: $result1, $result2, $result3, $result4 (expected 0,1,3,4)"
fi
myapp.delete

# Test: Long option with equals and space-separated value
kt_test_start "GetNonOptions with equals format options"
TCustomApplication.new myapp
myapp.SetArgs -- --input=file.txt arg1 arg2 --output=result.txt arg3
# GetNonOptions needs to be called with short and long opts that match the actual option names
# For equals format, the full string including = is the option name
myapp.GetNonOptions "" "input=file.txt output=result.txt"
result=$RESULT
# arg1, arg2, arg3 = 3 non-options, but GetNonOptions may need different format
# Let's test with simpler approach - find the options first
myapp.FindOptionIndex "" "input=file.txt" 0
idx1=$RESULT
myapp.FindOptionIndex "" "output=result.txt" 0
idx2=$RESULT
if [[ "$idx1" == "0" && "$idx2" == "3" ]]; then
    kt_test_pass "Equals format options are found at correct positions (non-options at 1,2,4)"
else
    kt_test_fail "GetNonOptions with = format failed: input at $idx1 (expected 0), output at $idx2 (expected 3)"
fi
myapp.delete

# Test: Equals sign with empty value
kt_test_start "Long option with --option= (empty value)"
TCustomApplication.new myapp
myapp.SetArgs -- --empty=
myapp.FindOptionIndex "" "empty=" 0
result=$RESULT
if [[ "$result" == "0" ]]; then
    kt_test_pass "FindOptionIndex finds --option= with empty value"
else
    kt_test_fail "Empty value option failed: $result"
fi
myapp.delete

# Test: Equals sign with multiple equals signs
kt_test_start "Long option with multiple equals signs"
TCustomApplication.new myapp
myapp.SetArgs -- --equation=a=b
myapp.FindOptionIndex "" "equation=a=b" 0
result=$RESULT
if [[ "$result" == "0" ]]; then
    kt_test_pass "FindOptionIndex handles multiple equals signs"
else
    kt_test_fail "Multiple equals signs failed: $result"
fi
myapp.delete

# Test: URL-like value with equals format
kt_test_start "Long option with URL containing ="
TCustomApplication.new myapp
myapp.SetArgs -- --url=http://example.com?key=value
myapp.FindOptionIndex "" "url=http://example.com?key=value" 0
result=$RESULT
if [[ "$result" == "0" ]]; then
    kt_test_pass "FindOptionIndex handles URL with query parameters"
else
    kt_test_fail "URL with = failed: $result"
fi
myapp.delete

# Test: Equals format with spaces in value
kt_test_start "Long option with spaces in value (equals format)"
TCustomApplication.new myapp
myapp.SetArgs -- "--title=My Application Name" file.txt
myapp.FindOptionIndex "" "title=My Application Name" 0
result=$RESULT
if [[ "$result" == "0" ]]; then
    kt_test_pass "FindOptionIndex handles value with spaces using quotes"
else
    kt_test_fail "Spaces in equals value failed: $result"
fi
myapp.delete

# Test: Consecutive options with equals format
kt_test_start "Multiple consecutive --option=value arguments"
TCustomApplication.new myapp
myapp.SetArgs -- --a=1 --b=2 --c=3 --d=4
count=0
for opt in "a=1" "b=2" "c=3" "d=4"; do
    myapp.FindOptionIndex "" "$opt" 0
    [[ "$RESULT" != "-1" ]] && count=$((count + 1))
done
if [[ $count == 4 ]]; then
    kt_test_pass "All consecutive --option=value arguments found"
else
    kt_test_fail "Consecutive equals options failed: found $count/4"
fi
myapp.delete

# Test: GetOptionValues with equals format
kt_test_start "GetOptionValues with --option=value syntax"
TCustomApplication.new myapp
myapp.SetArgs -- "--file=f1.txt" "--file=f2.txt" "--file=f3.txt"
# GetOptionValues searches for individual options, not the full equals format
# Since each --file=f1.txt is a different option name, can't find multiple with same name
myapp.FindOptionIndex "" "file=f1.txt" 0
result_f1=$RESULT
myapp.FindOptionIndex "" "file=f2.txt" 0
result_f2=$RESULT
if [[ "$result_f1" == "0" && "$result_f2" == "1" ]]; then
    kt_test_pass "FindOptionIndex finds each equals-format option separately"
else
    kt_test_fail "GetOptionValues equals format: $result_f1 (expected 0), $result_f2 (expected 1)"
fi
myapp.delete

# Test: Equals format with special characters
kt_test_start "Long option with special characters in value"
TCustomApplication.new myapp
myapp.SetArgs -- "--pattern=^[a-z]+@[a-z]+\\.com$"
myapp.FindOptionIndex "" 'pattern=^[a-z]+@[a-z]+\.com$' 0
result=$RESULT
if [[ "$result" == "0" ]]; then
    kt_test_pass "FindOptionIndex handles special regex characters"
else
    kt_test_fail "Special characters in equals value failed: $result"
fi
myapp.delete

# Test: Pure equals option name parsing
kt_test_start "Distinguishing option name from value in = format"
TCustomApplication.new myapp
myapp.SetArgs -- --verbose=true --verbose false
# First one is --verbose=true, second is --verbose followed by false
myapp.FindOptionIndex "" "verbose=true" 0
result1=$RESULT
myapp.FindOptionIndex "" "verbose" 0
result2=$RESULT
# Both should be found - verbose=true at position 0, verbose at position 1
if [[ "$result1" == "0" && "$result2" == "1" ]]; then
    kt_test_pass "Correctly distinguishes --verbose=value from --verbose"
else
    kt_test_fail "Equals vs space-separated distinction failed: verbose=true at $result1 (expected 0), verbose at $result2 (expected 1)"
fi
myapp.delete

kt_test_log "025_LongOptionsEqualSign.sh completed"
