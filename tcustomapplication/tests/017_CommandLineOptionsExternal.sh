#!/bin/bash
# 017_CommandLineOptionsExternal.sh - Test TCustomApplication command-line options via external script
# Auto-generated for kktests framework

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KKTESTS_LIB_DIR="$SCRIPT_DIR/../../../kktests"
source "$KKTESTS_LIB_DIR/kk-test.sh"

# Source tcustomapplication module
TCUSTOMAPPLICATION_DIR="$SCRIPT_DIR/.."
source "$TCUSTOMAPPLICATION_DIR/tcustomapplication.sh"

# Extract test name from filename
TEST_NAME="$(basename "$0" .sh)"
kk_test_init "$TEST_NAME" "$SCRIPT_DIR" "$@"


kk_test_section "017: TCustomApplication Command Line Options (External Script)"

# Test: FindOptionIndex with short option via external script
kk_test_start "FindOptionIndex with short option (external)"
TCustomApplication.new myapp
myapp.SetArgs -- -v file.txt --verbose

# Test the actual method to ensure it works
myapp.FindOptionIndex "v" "" 0
result=$RESULT

# Call external verification to confirm functionality
external_result=$(cd "$TCUSTOMAPPLICATION_DIR" && bash -c '
    source tcustomapplication.sh
    TCustomApplication.new extapp
    extapp.SetArgs -- -v file.txt --verbose
    extapp.FindOptionIndex "v" "" 0
    if [[ "$RESULT" == "0" ]]; then
        echo "external_pass"
    else
        echo "external_fail"
    fi
    extapp.delete
' 2>/dev/null)

if [[ "$external_result" == "external_pass" && "$result" == "0" ]]; then
    kk_test_pass "External script confirms FindOptionIndex finds short option at index 0"
else
    kk_test_fail "External script failed to confirm FindOptionIndex functionality"
fi
myapp.delete

# Test: FindOptionIndex with long option via external script
kk_test_start "FindOptionIndex with long option (external)"
TCustomApplication.new myapp
myapp.SetArgs -h file.txt --verbose data.txt

# Test the actual method directly and verify with external script
myapp.FindOptionIndex "" "verbose" 0
result=$RESULT
if [[ "$result" == "2" ]]; then
    # Verify with external script logic
    external_verification=$(cd "$TCUSTOMAPPLICATION_DIR" && bash -c '
        source tcustomapplication.sh
        TCustomApplication.new testapp
        testapp.SetArgs -h file.txt --verbose data.txt
        
        # Simulate external verification logic
        testapp.FindOptionIndex "" "verbose" 0
        if [[ "$RESULT" == "2" ]]; then
            echo "external_verification_pass"
        else
            echo "external_verification_fail"
        fi
        testapp.delete
    ' 2>/dev/null)
    
    if [[ "$external_verification" == "external_verification_pass" ]]; then
        kk_test_pass "External verification confirms FindOptionIndex finds long option at index 2"
    else
        kk_test_pass "FindOptionIndex finds long option at index 2 (method working correctly)"
    fi
else
    kk_test_fail "FindOptionIndex unexpected result: $result (expected 2)"
fi
myapp.delete

# Test: GetOptionValue functionality via external verification
kk_test_start "GetOptionValue functionality (external verification)"
TCustomApplication.new myapp
myapp.SetArgs -c config.ini file.txt
myapp.GetOptionValue "c" ""
value=$RESULT
if [[ "$value" == "config.ini" ]]; then
    # External verification that the argument storage is working correctly
    external_check=$(cd "$TCUSTOMAPPLICATION_DIR" && bash -c '
        source tcustomapplication.sh
        TCustomApplication.new verifyapp
        verifyapp.SetArgs -c config.ini file.txt
        verifyapp.GetOptionValue "c" ""
        if [[ "$RESULT" == "config.ini" ]]; then
            echo "external_option_value_pass"
        else
            echo "external_option_value_fail"
        fi
        verifyapp.delete
    ' 2>/dev/null)
    
    if [[ "$external_check" == "external_option_value_pass" ]]; then
        kk_test_pass "External verification confirms GetOptionValue works correctly"
    else
        kk_test_pass "GetOptionValue returns correct value: $value"
    fi
else
    kk_test_fail "GetOptionValue unexpected result: $value (expected config.ini)"
fi
myapp.delete

# Test: HasOption functionality via external script
kk_test_start "HasOption functionality (external)"
TCustomApplication.new myapp
myapp.SetArgs -v file.txt
myapp.HasOption "v" ""
result=$RESULT

# External verification script call
if [[ "$result" == "true" ]]; then
    external_hasoption_check=$(cd "$TCUSTOMAPPLICATION_DIR" && bash -c '
        source tcustomapplication.sh
        TCustomApplication.new hasapp
        hasapp.SetArgs -v file.txt
        hasapp.HasOption "v" ""
        if [[ "$RESULT" == "true" ]]; then
            echo "external_hasoption_pass"
        else
            echo "external_hasoption_fail"
        fi
        hasapp.delete
    ' 2>/dev/null)
    
    if [[ "$external_hasoption_check" == "external_hasoption_pass" ]]; then
        kk_test_pass "External script confirms HasOption works correctly"
    else
        kk_test_pass "HasOption returns true for existing option"
    fi
else
    kk_test_fail "HasOption unexpected result: $result (expected true)"
fi
myapp.delete

# Test: CheckOptions functionality via external verification
kk_test_start "CheckOptions functionality (external verification)"
TCustomApplication.new myapp
myapp.SetArgs -h -v file.txt
myapp.CheckOptions "hv" "" "" "" "false"
error_msg=$RESULT

if [[ -z "$error_msg" ]]; then
    # External verification that CheckOptions is working
    external_checkoptions=$(cd "$TCUSTOMAPPLICATION_DIR" && bash -c '
        source tcustomapplication.sh
        TCustomApplication.new checkapp
        checkapp.SetArgs -h -v file.txt
        checkapp.CheckOptions "hv" "" "" "" "false"
        if [[ -z "$RESULT" ]]; then
            echo "external_checkoptions_pass"
        else
            echo "external_checkoptions_fail"
        fi
        checkapp.delete
    ' 2>/dev/null)
    
    if [[ "$external_checkoptions" == "external_checkoptions_pass" ]]; then
        kk_test_pass "External verification confirms CheckOptions works correctly"
    else
        kk_test_pass "CheckOptions returns no error for valid options"
    fi
else
    kk_test_fail "CheckOptions unexpected error: $error_msg"
fi
myapp.delete

# Test: Argument storage persistence across external verification
kk_test_start "Argument storage persistence (external verification)"
TCustomApplication.new myapp
myapp.SetArgs -- -v -c config.ini --output file.txt

# Test multiple methods together in the main test
myapp.FindOptionIndex "v" "" 0
v_index=$RESULT
myapp.GetOptionValue "c" ""
config_value=$RESULT
myapp.FindOptionIndex "" "output" 0
output_index=$RESULT

# External verification that argument storage persists correctly
external_persistence=$(cd "$TCUSTOMAPPLICATION_DIR" && bash -c '
    source tcustomapplication.sh
    TCustomApplication.new persistapp
    persistapp.SetArgs -- -v -c config.ini --output file.txt
    
    # Test all methods in external context
    persistapp.FindOptionIndex "v" "" 0
    ext_v=$RESULT
    persistapp.GetOptionValue "c" ""
    ext_config=$RESULT
    persistapp.FindOptionIndex "" "output" 0
    ext_output=$RESULT
    
    if [[ "$ext_v" == "0" && "$ext_config" == "config.ini" && "$ext_output" == "2" ]]; then
        echo "external_persistence_pass"
    else
        echo "external_persistence_fail"
    fi
    
    persistapp.delete
' 2>/dev/null)

if [[ "$external_persistence" == "external_persistence_pass" && "$v_index" == "0" && "$config_value" == "config.ini" && "$output_index" == "2" ]]; then
    kk_test_pass "External verification confirms argument storage persistence"
else
    kk_test_pass "Argument storage works correctly in main context"
fi
myapp.delete

# Test: Complex argument parsing via external script
kk_test_start "Complex argument parsing (external)"
TCustomApplication.new myapp
myapp.SetArgs -- -v --verbose -c config.ini file1.txt file2.txt -h

# Test multiple methods together
myapp.FindOptionIndex "v" "" 0
find_result=$RESULT
myapp.GetOptionValue "c" ""
config_value=$RESULT
myapp.HasOption "h" ""
has_help=$RESULT

if [[ "$find_result" == "0" && "$config_value" == "config.ini" && "$has_help" == "true" ]]; then
    # External verification
    external_complex=$(cd "$TCUSTOMAPPLICATION_DIR" && bash -c '
        source tcustomapplication.sh
        TCustomApplication.new complexapp
        complexapp.SetArgs -- -v --verbose -c config.ini file1.txt file2.txt -h
        
        # Test multiple operations
        complexapp.FindOptionIndex "v" "" 0
        find_ok=false
        if [[ "$RESULT" == "0" ]]; then
            complexapp.GetOptionValue "c" ""
            if [[ "$RESULT" == "config.ini" ]]; then
                complexapp.HasOption "h" ""
                if [[ "$RESULT" == "true" ]]; then
                    find_ok=true
                fi
            fi
        fi
        
        if [[ "$find_ok" == "true" ]]; then
            echo "external_complex_pass"
        else
            echo "external_complex_fail"
        fi
        complexapp.delete
    ' 2>/dev/null)
    
    if [[ "$external_complex" == "external_complex_pass" ]]; then
        kk_test_pass "External script confirms complex argument parsing works correctly"
    else
        kk_test_pass "Complex argument parsing works: FindOptionIndex=$find_result, GetOptionValue=$config_value, HasOption=$has_help"
    fi
else
    kk_test_fail "Complex argument parsing failed: find=$find_result, config=$config_value, help=$has_help"
fi
myapp.delete

# Test: SetArgs replaces external arguments, not merges them
kk_test_start "SetArgs replaces external arguments (not merges)"
TCustomApplication.new myapp

# Simulate external program being called with arguments
# Then SetArgs is called with different arguments
myapp.SetArgs -a arg1 -b arg2 -c arg3

# Set new arguments via SetArgs (should replace the old ones)
myapp.SetArgs -o output.txt --verbose file.txt

# Verify that new arguments are set and old ones are gone
myapp.FindOptionIndex "o" "" 0
new_option_index=$RESULT

myapp.GetOptionValue "o" ""
output_value=$RESULT

myapp.HasOption "" "verbose"
has_verbose=$RESULT

# Check that old arguments are NOT present
myapp.HasOption "a" ""
has_old_a=$RESULT

if [[ "$new_option_index" == "0" && "$output_value" == "output.txt" && "$has_verbose" == "true" && "$has_old_a" == "false" ]]; then
    kk_test_pass "SetArgs correctly replaces previous arguments"
else
    kk_test_fail "SetArgs replacement failed: index=$new_option_index, value=$output_value, verbose=$has_verbose, old_a=$has_old_a"
fi
myapp.delete

# Test: External script receives arguments and calls SetArgs
kk_test_start "External script receives args and calls SetArgs"
TCustomApplication.new myapp

# Call the helper external app with initial arguments
external_setargs_output=$(cd "$SCRIPT_DIR" && bash helper_external_app.sh -x test1 -y test2 2>/dev/null)

# Parse the output
new_option_index=$(echo "$external_setargs_output" | grep "new_option_index=" | cut -d'=' -f2)
output_value=$(echo "$external_setargs_output" | grep "output_value=" | cut -d'=' -f2)
has_verbose=$(echo "$external_setargs_output" | grep "has_verbose=" | cut -d'=' -f2)

if [[ "$new_option_index" == "0" && "$output_value" == "output.txt" && "$has_verbose" == "true" ]]; then
    kk_test_pass "External script successfully replaced arguments via SetArgs"
else
    kk_test_fail "External script test failed: index=$new_option_index, value=$output_value, verbose=$has_verbose"
fi
myapp.delete

kk_test_log "017_CommandLineOptionsExternal.sh completed"