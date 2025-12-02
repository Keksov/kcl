#!/bin/bash
# 021_CommandLineOptionsExternalScript.sh - Test TCustomApplication with external scripts
# This test creates external scripts to verify all option methods work correctly
# when called from actual command-line invocations with real parameters

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

# Source tcustomapplication module
TCUSTOMAPPLICATION_DIR="$SCRIPT_DIR/.."
source "$TCUSTOMAPPLICATION_DIR/tcustomapplication.sh"

# Extract test name from filename
TEST_NAME="$(basename "$0" .sh)"
kt_test_init "$TEST_NAME" "$SCRIPT_DIR" "$@"

# Helper script creator for testing specific functionality  
create_test_app() {
    local app_name="$1"
    local app_code="$2"
    
    # Create inline test application
    cat > "${_KT_TMPDIR}/${app_name}.sh" << TESTAPP
#!/bin/bash
TCUSTOMAPPLICATION_DIR="c:/projects/kkbot/kbool/kcl/tcustomapplication"
[[ ! -d "\$TCUSTOMAPPLICATION_DIR" ]] && TCUSTOMAPPLICATION_DIR="c:/projects/kkbot/kbool/kcl/tcustomapplication"
source "\$TCUSTOMAPPLICATION_DIR/tcustomapplication.sh"

# Create app instance
TCustomApplication.new app

# Initialize arguments from real parameters
app.SetArgs -- "\$@"

# Execute app code
$app_code
TESTAPP
    
    chmod +x "${_KT_TMPDIR}/${app_name}.sh"
}

kt_test_section "021: TCustomApplication Command Line Options via External Scripts"

# Test 1: FindOptionIndex with short option
kt_test_start "FindOptionIndex with short option (external script)"
create_test_app "test_findopt_short" 'app.FindOptionIndex "v" "" 0
echo "$RESULT"'
output=$("${_KT_TMPDIR}/test_findopt_short.sh" -v file.txt --verbose 2>&1)
if [[ "$output" == "0" ]]; then
    kt_test_pass "FindOptionIndex correctly identifies short option"
else
    kt_test_fail "FindOptionIndex unexpected result: $output (expected 0)"
fi

# Test 2: FindOptionIndex with long option
kt_test_start "FindOptionIndex with long option (external script)"
create_test_app "test_findopt_long" 'app.FindOptionIndex "" "verbose" 0
echo "$RESULT"'
output=$("${_KT_TMPDIR}/test_findopt_long.sh" -h file.txt --verbose data.txt 2>&1)
if [[ "$output" == "2" ]]; then
    kt_test_pass "FindOptionIndex correctly identifies long option"
else
    kt_test_fail "FindOptionIndex unexpected result: $output (expected 2)"
fi

# Test 3: FindOptionIndex with StartAt parameter
kt_test_start "FindOptionIndex with StartAt parameter (external script)"
create_test_app "test_findopt_startat" 'app.FindOptionIndex "v" "" 1
echo "$RESULT"'
output=$("${_KT_TMPDIR}/test_findopt_startat.sh" -v file.txt -v data.txt 2>&1)
if [[ "$output" == "2" ]]; then
    kt_test_pass "FindOptionIndex with StartAt finds next occurrence"
else
    kt_test_fail "FindOptionIndex unexpected result: $output (expected 2)"
fi

# Test 4: FindOptionIndex returns -1 for non-existent option
kt_test_start "FindOptionIndex returns -1 for non-existent (external script)"
create_test_app "test_findopt_notfound" 'app.FindOptionIndex "x" "" 0
echo "$RESULT"'
output=$("${_KT_TMPDIR}/test_findopt_notfound.sh" file.txt data.txt 2>&1)
if [[ "$output" == "-1" ]]; then
    kt_test_pass "FindOptionIndex returns -1 for non-existent option"
else
    kt_test_fail "FindOptionIndex unexpected result: $output (expected -1)"
fi

# Test 5: GetOptionValue with short option
kt_test_start "GetOptionValue with short option (external script)"
create_test_app "test_getoptval_short" 'app.GetOptionValue "c" ""
echo "$RESULT"'
output=$("${_KT_TMPDIR}/test_getoptval_short.sh" -c config.ini file.txt 2>&1)
if [[ "$output" == "config.ini" ]]; then
    kt_test_pass "GetOptionValue returns correct value for short option"
else
    kt_test_fail "GetOptionValue unexpected result: $output (expected config.ini)"
fi

# Test 6: GetOptionValue with long option
kt_test_start "GetOptionValue with long option (external script)"
create_test_app "test_getoptval_long" 'app.GetOptionValue "" "config"
echo "$RESULT"'
output=$("${_KT_TMPDIR}/test_getoptval_long.sh" file.txt --config data.ini 2>&1)
if [[ "$output" == "data.ini" ]]; then
    kt_test_pass "GetOptionValue returns correct value for long option"
else
    kt_test_fail "GetOptionValue unexpected result: $output (expected data.ini)"
fi

# Test 7: GetOptionValue with both short and long forms
kt_test_start "GetOptionValue with char and string (external script)"
create_test_app "test_getoptval_both" 'app.GetOptionValue "c" "config"
echo "$RESULT"'
output=$("${_KT_TMPDIR}/test_getoptval_both.sh" -c test.conf file.txt 2>&1)
if [[ "$output" == "test.conf" ]]; then
    kt_test_pass "GetOptionValue with both forms returns value"
else
    kt_test_fail "GetOptionValue unexpected result: $output (expected test.conf)"
fi

# Test 8: GetOptionValue returns empty for option without value
kt_test_start "GetOptionValue without value (external script)"
create_test_app "test_getoptval_empty" 'app.GetOptionValue "v" ""
if [[ -z "$RESULT" ]]; then
    echo "EMPTY"
else
    echo "$RESULT"
fi'
output=$("${_KT_TMPDIR}/test_getoptval_empty.sh" -v -h file.txt 2>&1)
if [[ "$output" == "EMPTY" ]]; then
    kt_test_pass "GetOptionValue returns empty when next arg is another option"
else
    kt_test_fail "GetOptionValue unexpected result: $output (expected EMPTY)"
fi

# Test 9: HasOption with short option - found
kt_test_start "HasOption finds short option (external script)"
create_test_app "test_hasopt_short" 'app.HasOption "v" ""
echo "$RESULT"'
output=$("${_KT_TMPDIR}/test_hasopt_short.sh" -v file.txt 2>&1)
if [[ "$output" == "true" ]]; then
    kt_test_pass "HasOption returns true for existing short option"
else
    kt_test_fail "HasOption unexpected result: $output (expected true)"
fi

# Test 10: HasOption with long option - found
kt_test_start "HasOption finds long option (external script)"
create_test_app "test_hasopt_long" 'app.HasOption "" "verbose"
echo "$RESULT"'
output=$("${_KT_TMPDIR}/test_hasopt_long.sh" file.txt --verbose data.txt 2>&1)
if [[ "$output" == "true" ]]; then
    kt_test_pass "HasOption returns true for existing long option"
else
    kt_test_fail "HasOption unexpected result: $output (expected true)"
fi

# Test 11: HasOption returns false for non-existent option
kt_test_start "HasOption returns false for non-existent (external script)"
create_test_app "test_hasopt_notfound" 'app.HasOption "x" ""
echo "$RESULT"'
output=$("${_KT_TMPDIR}/test_hasopt_notfound.sh" file.txt data.txt 2>&1)
if [[ "$output" == "false" ]]; then
    kt_test_pass "HasOption returns false for non-existent option"
else
    kt_test_fail "HasOption unexpected result: $output (expected false)"
fi

# Test 12: HasOption with char and string
kt_test_start "HasOption with char and string (external script)"
create_test_app "test_hasopt_both" 'app.HasOption "v" "verbose"
echo "$RESULT"'
output=$("${_KT_TMPDIR}/test_hasopt_both.sh" -v file.txt 2>&1)
if [[ "$output" == "true" ]]; then
    kt_test_pass "HasOption with both forms returns true"
else
    kt_test_fail "HasOption unexpected result: $output (expected true)"
fi

# Test 13: CheckOptions with valid simple options
kt_test_start "CheckOptions with valid options (external script)"
create_test_app "test_checkopts_valid" 'app.CheckOptions "hv" "" "" "" "false"
if [[ -z "$RESULT" ]]; then
    echo "VALID"
else
    echo "ERROR: $RESULT"
fi'
output=$("${_KT_TMPDIR}/test_checkopts_valid.sh" -h -v file.txt 2>&1)
if [[ "$output" == "VALID" ]]; then
    kt_test_pass "CheckOptions returns no error for valid options"
else
    kt_test_fail "CheckOptions unexpected result: $output"
fi

# Test 14: CheckOptions with invalid option
kt_test_start "CheckOptions rejects invalid options (external script)"
create_test_app "test_checkopts_invalid" 'app.CheckOptions "hv" "" "" "" "false"
if [[ -n "$RESULT" ]]; then
    echo "INVALID"
else
    echo "VALID"
fi'
output=$("${_KT_TMPDIR}/test_checkopts_invalid.sh" -x invalid file.txt 2>&1)
if [[ "$output" == "INVALID" ]]; then
    kt_test_pass "CheckOptions detects invalid options"
else
    kt_test_fail "CheckOptions failed to detect invalid options"
fi

# Test 15: GetOptionValues with multiple occurrences
kt_test_start "GetOptionValues with multiple occurrences (external script)"
create_test_app "test_getoptvals_multi" 'app.GetOptionValues "i" ""
echo "$RESULT"'
output=$("${_KT_TMPDIR}/test_getoptvals_multi.sh" -i file1.txt -i file2.txt -i file3.txt 2>&1)
if [[ "$output" == "3:file1.txt file2.txt file3.txt" ]]; then
    kt_test_pass "GetOptionValues correctly returns multiple values"
else
    kt_test_fail "GetOptionValues unexpected result: $output"
fi

# Test 16: GetOptionValues returns empty array for non-existent option
kt_test_start "GetOptionValues for non-existent option (external script)"
create_test_app "test_getoptvals_notfound" 'app.GetOptionValues "x" ""
echo "$RESULT"'
output=$("${_KT_TMPDIR}/test_getoptvals_notfound.sh" file.txt data.txt 2>&1)
if [[ "$output" == "0:" ]]; then
    kt_test_pass "GetOptionValues returns empty array for non-existent option"
else
    kt_test_fail "GetOptionValues unexpected result: $output (expected 0:)"
fi

kt_test_log "021_CommandLineOptionsExternalScript.sh completed"
