#!/bin/bash
# 017_CommandLineOptionsExternal.sh - the option API as seen from a SEPARATE
# bash process: the unit must behave the same when it is sourced fresh, and the
# answers must not depend on anything this shell happens to have in scope.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

# Source tcustomapplication module
TCUSTOMAPPLICATION_DIR="$SCRIPT_DIR/.."
source "$TCUSTOMAPPLICATION_DIR/tcustomapplication.sh"

TEST_NAME="$(basename "$0" .sh)"
kt_test_init "$TEST_NAME" "$SCRIPT_DIR" "$@"

# Run SNIPPET in a fresh bash that has only the unit loaded, and echo what it
# printed. Every assertion below compares the local answer AND the external one
# against the same expected value — no "external check failed, pass anyway".
external() {   # SNIPPET
    UNIT="$TCUSTOMAPPLICATION_DIR/tcustomapplication.sh" bash -c '
        source "$UNIT"
        '"$1"'
    ' 2>&1
}

both() {   # LABEL LOCAL_VALUE EXTERNAL_VALUE EXPECTED
    if [[ "$2" == "$4" && "$3" == "$4" ]]; then
        kt_test_pass "$1"
    else
        kt_test_fail "$1: local='$2' external='$3', expected '$4'"
    fi
}

kt_test_section "017: TCustomApplication Command Line Options (External Script)"

kt_test_start "FindOptionIndex with short option (external)"
TCustomApplication.new myapp
myapp.SetArgs -v file.txt --verbose
myapp.FindOptionIndex "v" ""
both "short option is at ParamStr index 1" "$RESULT" \
    "$(external 'TCustomApplication.new e; e.SetArgs -v file.txt --verbose; e.FindOptionIndex "v" ""; printf "%s" "$RESULT"; e.delete')" \
    "1"
myapp.delete

kt_test_start "FindOptionIndex with long option (external)"
TCustomApplication.new myapp
myapp.SetArgs -h file.txt --verbose data.txt
myapp.FindOptionIndex "" "verbose"
both "long option is at ParamStr index 3" "$RESULT" \
    "$(external 'TCustomApplication.new e; e.SetArgs -h file.txt --verbose data.txt; e.FindOptionIndex "" "verbose"; printf "%s" "$RESULT"; e.delete')" \
    "3"
myapp.delete

kt_test_start "GetOptionValue (external)"
TCustomApplication.new myapp
myapp.SetArgs -c config.ini file.txt
myapp.GetOptionValue "c" ""
both "short option value" "$RESULT" \
    "$(external 'TCustomApplication.new e; e.SetArgs -c config.ini file.txt; e.GetOptionValue "c" ""; printf "%s" "$RESULT"; e.delete')" \
    "config.ini"
myapp.delete

kt_test_start "HasOption (external)"
TCustomApplication.new myapp
myapp.SetArgs -v file.txt
myapp.HasOption "v" "" && local_rc=0 || local_rc=$?
both "rc 0 for a present option" "$local_rc" \
    "$(external 'TCustomApplication.new e; e.SetArgs -v file.txt; e.HasOption "v" "" && printf 0 || printf $?; e.delete')" \
    "0"
myapp.delete

kt_test_start "CheckOptions (external)"
TCustomApplication.new myapp
myapp.SetArgs -h -v file.txt
myapp.CheckOptions "hv" "" "" "" "false"
both "no error for valid options" "$RESULT" \
    "$(external 'TCustomApplication.new e; e.SetArgs -h -v file.txt; e.CheckOptions "hv" "" "" "" "false"; printf "%s" "$RESULT"; e.delete')" \
    ""
myapp.delete

kt_test_start "argument storage persists across calls (external)"
TCustomApplication.new myapp
myapp.SetArgs -v -c config.ini --output file.txt
myapp.FindOptionIndex "v" ""
v_index=$RESULT
myapp.GetOptionValue "c" ""
config_value=$RESULT
myapp.FindOptionIndex "" "output"
output_index=$RESULT
ext="$(external 'TCustomApplication.new e; e.SetArgs -v -c config.ini --output file.txt
e.FindOptionIndex "v" ""; a=$RESULT
e.GetOptionValue "c" ""; b=$RESULT
e.FindOptionIndex "" "output"; c=$RESULT
printf "%s|%s|%s" "$a" "$b" "$c"; e.delete')"
both "-v at 1, -c value, --output at 4" "$v_index|$config_value|$output_index" "$ext" "1|config.ini|4"
myapp.delete

kt_test_start "complex argument line (external)"
TCustomApplication.new myapp
myapp.SetArgs -v --verbose -c config.ini file1.txt file2.txt -h
myapp.FindOptionIndex "v" ""
find_result=$RESULT
myapp.GetOptionValue "c" ""
config_value=$RESULT
myapp.HasOption "h" "" && has_help=true || has_help=false
ext="$(external 'TCustomApplication.new e; e.SetArgs -v --verbose -c config.ini file1.txt file2.txt -h
e.FindOptionIndex "v" ""; a=$RESULT
e.GetOptionValue "c" ""; b=$RESULT
e.HasOption "h" "" && c=true || c=false
printf "%s|%s|%s" "$a" "$b" "$c"; e.delete')"
both "-v at 1, -c config.ini, -h present" "$find_result|$config_value|$has_help" "$ext" "1|config.ini|true"
myapp.delete

kt_test_start "SetArgs replaces the previous arguments (not merges)"
TCustomApplication.new myapp
myapp.SetArgs -a arg1 -b arg2 -c arg3
myapp.SetArgs -o output.txt --verbose file.txt
myapp.FindOptionIndex "o" ""
new_option_index=$RESULT
myapp.GetOptionValue "o" ""
output_value=$RESULT
myapp.HasOption "" "verbose" && has_verbose=true || has_verbose=false
myapp.HasOption "a" "" && has_old_a=true || has_old_a=false
if [[ "$new_option_index" == "1" && "$output_value" == "output.txt" && "$has_verbose" == "true" && "$has_old_a" == "false" ]]; then
    kt_test_pass "SetArgs correctly replaces previous arguments"
else
    kt_test_fail "SetArgs replacement failed: index=$new_option_index, value=$output_value, verbose=$has_verbose, old_a=$has_old_a"
fi
myapp.delete

kt_test_start "a real script hands its own \$@ to SetArgs [TCA-04]"
# The helper script is run with real parameters and calls SetArgs "$@" itself;
# nothing is auto-captured any more, so its argv is exactly what it was given.
external_setargs_output=$(TCUSTOMAPPLICATION_DIR="$TCUSTOMAPPLICATION_DIR" \
    bash "$SCRIPT_DIR/helper_external_app.sh" -x test1 -y test2)
original_count=""
new_option_index=""
output_value=""
has_verbose=""
while IFS='=' read -r key value; do
    case "$key" in
        original_count)    original_count="$value" ;;
        new_option_index)  new_option_index="$value" ;;
        output_value)      output_value="$value" ;;
        has_verbose)       has_verbose="$value" ;;
    esac
done <<< "$external_setargs_output"

if [[ "$original_count" == "4" && "$new_option_index" == "1" && "$output_value" == "output.txt" && "$has_verbose" == "true" ]]; then
    kt_test_pass "the script's four parameters were stored, then replaced by SetArgs"
else
    kt_test_fail "external script test failed: original=$original_count index=$new_option_index value=$output_value verbose=$has_verbose"
fi

kt_test_start "a fresh instance has no arguments at all [TCA-04]"
# The old build stored the FIRST OPTION METHOD's own parameters as the argv.
ext="$(external 'TCustomApplication.new e
e.GetNonOptions "" "" nn >/dev/null 2>&1; a=$?
e.ParamCount; b=$RESULT
e.CheckOptions "hv" "help" "false"; c=$RESULT
e.ParamCount; d=$RESULT
printf "%s|%s|%s|%s" "$a" "$b" "$c" "$d"; e.delete')"
if [[ "$ext" == "0|0||0" ]]; then
    kt_test_pass "GetNonOptions/CheckOptions on a fresh app see zero arguments"
else
    kt_test_fail "fresh instance captured its method arguments: '$ext' (expected '0|0||0')"
fi

kt_test_log "017_CommandLineOptionsExternal.sh completed"
