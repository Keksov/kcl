#!/bin/bash
# 025_LongOptionsEqualSign.sh - Long options with an equals sign.
#
# `--name=value` is the ONLY way a long option carries a value in FPC: the
# option NAME stops at the first '=' and the value is what follows it. Before
# P4 the whole token was the option name, so every test in this file had to
# search for `config=settings.ini` and the workaround `verbose=true` was
# enshrined as an option name (finding TCA-01).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

# Source tcustomapplication module
TCUSTOMAPPLICATION_DIR="$SCRIPT_DIR/.."
source "$TCUSTOMAPPLICATION_DIR/tcustomapplication.sh"

# Extract test name from filename
TEST_NAME="$(basename "$0" .sh)"
kt_test_init "$TEST_NAME" "$SCRIPT_DIR" "$@"

eq() {   # LABEL ACTUAL EXPECTED
    if [[ "$2" == "$3" ]]; then
        kt_test_pass "$1"
    else
        kt_test_fail "$1: got '$2', expected '$3'"
    fi
}

kt_test_section "025: TCustomApplication Long Options with Equals Sign"

kt_test_start "FindOptionIndex matches the name before the equals sign [TCA-01]"
TCustomApplication.new myapp
myapp.SetArgs --config=settings.ini file.txt
myapp.FindOptionIndex "" "config"
by_name=$RESULT
myapp.FindOptionIndex "" "config=settings.ini"
by_token=$RESULT
if [[ "$by_name" == "1" && "$by_token" == "-1" ]]; then
    kt_test_pass "the option is 'config'; the whole token is not a name"
else
    kt_test_fail "name=$by_name (expected 1), whole token=$by_token (expected -1)"
fi
myapp.delete

kt_test_start "GetOptionValue: equals carries the value, a space does not [TCA-01]"
TCustomApplication.new myapp1
myapp1.SetArgs --config settings.ini
myapp1.GetOptionValue "" "config"
val_separate=$RESULT
TCustomApplication.new myapp2
myapp2.SetArgs --config=settings.ini
myapp2.GetOptionValue "" "config"
val_equals=$RESULT
if [[ -z "$val_separate" && "$val_equals" == "settings.ini" ]]; then
    kt_test_pass "'--config settings.ini' has no value, '--config=settings.ini' has one"
else
    kt_test_fail "value extraction failed: separate='$val_separate', equals='$val_equals'"
fi
myapp1.delete
myapp2.delete

kt_test_start "CheckOptions accepts --name=value for a 'name:' long option"
TCustomApplication.new myapp
myapp.SetArgs --input=file.txt --output=result.txt
myapp.CheckOptions "" "input: output:"
eq "no error" "$RESULT" ""
myapp.delete

kt_test_start "CheckOptions rejects a value on a switch long option [TCA-02]"
TCustomApplication.new myapp
myapp.SetArgs --input=file.txt
myapp.CheckOptions "" "input"
eq "SErrNoOptionAllowed" "$RESULT" "Option at position 1 does not allow an argument: input"
myapp.delete

kt_test_start "HasOption with --name=value matches the name"
TCustomApplication.new myapp
myapp.SetArgs --verbose=true
if myapp.HasOption "" "verbose"; then
    myapp.GetOptionValue "" "verbose"
    eq "value of --verbose=true" "$RESULT" "true"
else
    kt_test_fail "HasOption did not find --verbose in '--verbose=true'"
fi
myapp.delete

kt_test_start "Mixed --name=value and --name value formats"
TCustomApplication.new myapp
myapp.SetArgs --config=settings.ini --output results.txt --verbose=true --debug
myapp.FindOptionIndex "" "config"
result1=$RESULT
myapp.FindOptionIndex "" "output"
result2=$RESULT
myapp.FindOptionIndex "" "verbose"
result3=$RESULT
myapp.FindOptionIndex "" "debug"
result4=$RESULT
if [[ "$result1" == "1" && "$result2" == "2" && "$result3" == "4" && "$result4" == "5" ]]; then
    kt_test_pass "all four long options are found at their ParamStr indices"
else
    kt_test_fail "mixed format test failed: $result1, $result2, $result3, $result4 (expected 1,2,4,5)"
fi
myapp.delete

kt_test_start "GetNonOptions with equals-format options"
TCustomApplication.new myapp
myapp.SetArgs --input=file.txt arg1 arg2 --output=result.txt arg3
declare -a non=()
myapp.GetNonOptions "" "input: output:" non
if [[ "$RESULT" == "3" && "${non[*]}" == "arg1 arg2 arg3" ]]; then
    kt_test_pass "the three plain arguments are the non-options"
else
    kt_test_fail "GetNonOptions with = format failed: count=$RESULT non=(${non[*]:-})"
fi
myapp.delete

kt_test_start "Long option with --name= (empty value)"
TCustomApplication.new myapp
myapp.SetArgs --empty=
myapp.FindOptionIndex "" "empty"
idx=$RESULT
myapp.GetOptionValue "" "empty"
value=$RESULT
myapp.CheckOptions "" "empty:"
err=$RESULT
if [[ "$idx" == "1" && -z "$value" && -z "$err" ]]; then
    kt_test_pass "--empty= is the option 'empty' with an empty value, and it satisfies 'empty:'"
else
    kt_test_fail "empty value option: idx=$idx value='$value' err='$err'"
fi
myapp.delete

kt_test_start "Long option with multiple equals signs"
TCustomApplication.new myapp
myapp.SetArgs --equation=a=b
myapp.FindOptionIndex "" "equation"
idx=$RESULT
myapp.GetOptionValue "" "equation"
value=$RESULT
if [[ "$idx" == "1" && "$value" == "a=b" ]]; then
    kt_test_pass "the name stops at the FIRST '=' and the rest is the value"
else
    kt_test_fail "multiple equals signs: idx=$idx value='$value' (expected 1 / a=b)"
fi
myapp.delete

kt_test_start "Long option with a URL value containing ="
TCustomApplication.new myapp
myapp.SetArgs --url=http://example.com?key=value
myapp.GetOptionValue "" "url"
eq "URL with a query string" "$RESULT" "http://example.com?key=value"
myapp.delete

kt_test_start "Long option with spaces in the value"
TCustomApplication.new myapp
myapp.SetArgs "--title=My Application Name" file.txt
myapp.FindOptionIndex "" "title"
idx=$RESULT
myapp.GetOptionValue "" "title"
value=$RESULT
if [[ "$idx" == "1" && "$value" == "My Application Name" ]]; then
    kt_test_pass "a quoted value with spaces survives whole"
else
    kt_test_fail "spaces in equals value: idx=$idx value='$value'"
fi
myapp.delete

kt_test_start "Multiple consecutive --name=value arguments"
TCustomApplication.new myapp
myapp.SetArgs --a=1 --b=2 --c=3 --d=4
missing=""
i=0
for opt in a b c d; do
    i=$((i + 1))
    myapp.FindOptionIndex "" "$opt"
    [[ "$RESULT" == "$i" ]] || missing+="$opt@$RESULT "
    myapp.GetOptionValue "" "$opt"
    [[ "$RESULT" == "$i" ]] || missing+="$opt=$RESULT "
done
if [[ -z "$missing" ]]; then
    kt_test_pass "a=1 b=2 c=3 d=4 all found at indices 1..4 with their values"
else
    kt_test_fail "consecutive equals options failed: $missing"
fi
myapp.delete

kt_test_start "GetOptionValues with repeated --name=value"
TCustomApplication.new myapp
myapp.SetArgs "--file=f1.txt" "--file=f2.txt" "--file=f3.txt"
declare -a vals=()
myapp.GetOptionValues "" "file" vals
if [[ "$RESULT" == "3" && "${vals[*]}" == "f3.txt f2.txt f1.txt" ]]; then
    kt_test_pass "three values collected (FPC order: last first)"
else
    kt_test_fail "GetOptionValues equals format: count=$RESULT values=(${vals[*]:-})"
fi
myapp.delete

kt_test_start "Long option with regex metacharacters in the value"
TCustomApplication.new myapp
myapp.SetArgs '--pattern=^[a-z]+@[a-z]+\.com$'
myapp.FindOptionIndex "" "pattern"
idx=$RESULT
myapp.GetOptionValue "" "pattern"
value=$RESULT
if [[ "$idx" == "1" && "$value" == '^[a-z]+@[a-z]+\.com$' ]]; then
    kt_test_pass "the value is matched literally, not as a pattern"
else
    kt_test_fail "special characters in equals value: idx=$idx value='$value'"
fi
myapp.delete

kt_test_start "--name=value and a bare --name are the SAME option [TCA-01, R10]"
TCustomApplication.new myapp
myapp.SetArgs --verbose=true --verbose false
myapp.FindOptionIndex "" "verbose"
last=$RESULT
myapp.FindOptionIndex "" "verbose" $((last - 1))
first=$RESULT
myapp.GetOptionValue "" "verbose"
value=$RESULT
# The last occurrence wins and it is the bare `--verbose`, which has no value.
if [[ "$last" == "2" && "$first" == "1" && -z "$value" ]]; then
    kt_test_pass "both occurrences are 'verbose'; the last one wins and carries no value"
else
    kt_test_fail "equals vs bare: last=$last (expected 2), first=$first (expected 1), value='$value' (expected empty)"
fi
myapp.delete

kt_test_log "025_LongOptionsEqualSign.sh completed"
