#!/bin/bash
# Kklass RESULT compatibility for TCustomApplication

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

TCUSTOMAPPLICATION_DIR="$SCRIPT_DIR/.."
source "$TCUSTOMAPPLICATION_DIR/tcustomapplication.sh"

TEST_NAME="$(basename "$0" .sh)"
kt_test_init "$TEST_NAME" "$SCRIPT_DIR" "$@"

kt_test_section "030: TCustomApplication kklass RESULT compatibility"

kt_test_start "TCustomApplication uses shared kklass silent call helper"
tcustomapplication._call_silent() { :; }
source "$TCUSTOMAPPLICATION_DIR/tcustomapplication.sh"

if declare -F kk.call_silent >/dev/null && ! declare -F tcustomapplication._call_silent >/dev/null; then
    kt_test_pass "TCustomApplication uses shared kklass silent call helper"
else
    kt_test_fail "TCustomApplication silent helper mismatch: kk.call_silent=$(declare -F kk.call_silent >/dev/null && echo yes || echo no), local_helper=$(declare -F tcustomapplication._call_silent >/dev/null && echo yes || echo no)"
fi

kt_test_start "TCustomApplication exposes expected kklass instance metadata"
expected_methods=(Initialize SetArgs FindOptionIndex GetOptionValue GetOptionValues HasOption CheckOptions GetNonOptions Terminate Run HandleException ShowException GetEnvironmentList Log ConsoleApplication Location ParamCount Params EnvironmentVariable)
expected_properties=(Terminated Title HelpFile OptionChar CaseSensitiveOptions StopOnException ExceptionExitCode OnException EventLogFilter ExeName)
missing_metadata=()

for expected_method in "${expected_methods[@]}"; do
    found=false
    for registered_method in "${TCustomApplication_class_methods[@]}"; do
        if [[ "$registered_method" == "$expected_method" ]]; then
            found=true
            break
        fi
    done
    [[ "$found" == "true" ]] || missing_metadata+=("method:$expected_method")
done

for expected_property in "${expected_properties[@]}"; do
    found=false
    for registered_property in "${TCustomApplication_class_properties[@]}"; do
        if [[ "$registered_property" == "$expected_property" ]]; then
            found=true
            break
        fi
    done
    [[ "$found" == "true" ]] || missing_metadata+=("property:$expected_property")
done

if (( ${#missing_metadata[@]} == 0 && ${#TCustomApplication_class_static_methods[@]} == 0 )); then
    kt_test_pass "TCustomApplication exposes expected kklass instance metadata"
else
    kt_test_fail "TCustomApplication metadata mismatch: missing=${missing_metadata[*]:-(none)}, static_count=${#TCustomApplication_class_static_methods[@]}"
fi

kt_test_start "FindOptionIndex preserves RESULT on found path"
TCustomApplication.new kklass_result_app
kklass_result_app.SetArgs -- -v input.txt --config settings.ini
kklass_result_app.FindOptionIndex "v" "" 0
short_index="$RESULT"
kklass_result_app.FindOptionIndex "" "config" 0
long_index="$RESULT"

if [[ "$short_index" == "0" && "$long_index" == "2" ]]; then
    kt_test_pass "FindOptionIndex preserves RESULT on found path"
else
    kt_test_fail "FindOptionIndex RESULT mismatch: short=$short_index, long=$long_index"
fi

kt_test_start "GetOptionValue preserves RESULT on found value path"
kklass_result_app.GetOptionValue "v" ""
short_value="$RESULT"
kklass_result_app.GetOptionValue "" "config"
long_value="$RESULT"

if [[ "$short_value" == "input.txt" && "$long_value" == "settings.ini" ]]; then
    kt_test_pass "GetOptionValue preserves RESULT on found value path"
else
    kt_test_fail "GetOptionValue RESULT mismatch: short=$short_value, long=$long_value"
fi

kt_test_start "Public option methods do not leak nested helper output"
get_value_output=$(kklass_result_app.GetOptionValue "v" "")
has_option_output=$(kklass_result_app.HasOption "v" "")
get_values_output=$(kklass_result_app.GetOptionValues "v" "")

if [[ "$get_value_output" == "input.txt" && "$has_option_output" == "true" && "$get_values_output" == "1:input.txt" ]]; then
    kt_test_pass "Public option methods do not leak nested helper output"
else
    kt_test_fail "Nested helper output leaked: GetOptionValue='$get_value_output', HasOption='$has_option_output', GetOptionValues='$get_values_output'"
fi

kt_test_start "CheckOptions preserves invalid option message"
kklass_result_app.SetArgs -- -x bad
kklass_result_app.CheckOptions "v" "config"
error_message="$RESULT"

if [[ "$error_message" == "Invalid option: -x" ]]; then
    kt_test_pass "CheckOptions preserves invalid option message"
else
    kt_test_fail "CheckOptions invalid option mismatch: '$error_message'"
fi

kt_test_start "CheckOptions command substitution emits only final error"
check_options_output=$(kklass_result_app.CheckOptions "v" "config")

if [[ "$check_options_output" == "Invalid option: -x" ]]; then
    kt_test_pass "CheckOptions command substitution emits only final error"
else
    kt_test_fail "CheckOptions command substitution leaked output: '$check_options_output'"
fi

kklass_result_app.delete

kt_test_start "TCustomApplication argument storage is isolated per instance"
TCustomApplication.new first_app
TCustomApplication.new second_app
first_app.SetArgs -- -c first.conf
second_app.SetArgs -- -c second.conf
first_app.GetOptionValue "c" ""
first_value="$RESULT"
second_app.GetOptionValue "c" ""
second_value="$RESULT"

if [[ "$first_value" == "first.conf" && "$second_value" == "second.conf" ]]; then
    kt_test_pass "TCustomApplication argument storage is isolated per instance"
else
    kt_test_fail "TCustomApplication argument storage leaked between instances: first=$first_value, second=$second_value"
fi

first_app.delete
second_app.delete

kt_test_start "TCustomApplication isolates complex argument values per instance"
TCustomApplication.new complex_first_app
TCustomApplication.new complex_second_app
first_complex_value='first value with spaces and "quotes"'
second_complex_value=$'second\tvalue\nline'
first_newline_value=$'first line\nnext line'
second_newline_value=$'second line\nother line'
complex_first_app.SetArgs -- -c "$first_complex_value" -n "$first_newline_value" --empty ""
complex_second_app.SetArgs -- -c "$second_complex_value" -n "$second_newline_value" --empty "not-empty"

complex_first_app.GetOptionValue "c" ""
first_complex_result="$RESULT"
complex_second_app.GetOptionValue "c" ""
second_complex_result="$RESULT"
complex_first_app.GetOptionValue "n" ""
first_newline_result="$RESULT"
complex_second_app.GetOptionValue "n" ""
second_newline_result="$RESULT"
complex_first_app.GetOptionValues "" "empty"
first_empty_values="$RESULT"
complex_second_app.GetOptionValues "" "empty"
second_empty_values="$RESULT"

if [[ "$first_complex_result" == "$first_complex_value" && "$second_complex_result" == "$second_complex_value" && "$first_newline_result" == "$first_newline_value" && "$second_newline_result" == "$second_newline_value" && "$first_empty_values" == "1:" && "$second_empty_values" == "1:not-empty" ]]; then
    kt_test_pass "TCustomApplication isolates complex argument values per instance"
else
    kt_test_fail "Complex argument isolation failed: first='$first_complex_result' second='$second_complex_result' first_newline='$first_newline_result' second_newline='$second_newline_result' first_empty='$first_empty_values' second_empty='$second_empty_values'"
fi

complex_first_app.delete
complex_second_app.delete

kt_test_log "030_KklassResultCompatibility.sh completed"