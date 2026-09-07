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
# Use BASH_SOURCE[0] instead of $0 for better reliability in threaded environments
TEST_NAME="$(basename "${BASH_SOURCE[0]}" .sh)"
kt_test_init "$TEST_NAME" "$SCRIPT_DIR" "$@"
# A directory of our own: the ktests fixture temp dir is named after $0, which
# is "bash" for every file the runner starts, and the runner runs files in
# parallel — a neighbour's teardown would delete our helper scripts.
TCA_TMPD="$SCRIPT_DIR/.tmp/$(basename "${BASH_SOURCE[0]}" .sh)"
mkdir -p "$TCA_TMPD"


# Helper script creator for testing specific functionality  
create_test_app() {
    local app_name="$1"
    local app_code="$2"
    
    # Verify TCA_TMPD is set and accessible
    if [[ -z "$TCA_TMPD" ]]; then
        kt_test_fail "Internal error: TCA_TMPD is not set"
        return 1
    fi
    
    # Create directory if it doesn't exist
    if ! mkdir -p "$TCA_TMPD" 2>/dev/null; then
        kt_test_fail "Internal error: Failed to create TCA_TMPD: $TCA_TMPD (errno: $?)"
        return 1
    fi
    
    if [[ ! -d "$TCA_TMPD" ]]; then
        kt_test_fail "Internal error: TCA_TMPD directory does not exist: $TCA_TMPD"
        return 1
    fi
    
    # Create inline test application
    # The unit is located relative to THIS test file, not guessed from a
    # hard-coded repository path (the old form pinned c:/projects/...).
    cat > "${TCA_TMPD}/${app_name}.sh" << TESTAPP
#!/bin/bash
source "${TCUSTOMAPPLICATION_DIR}/tcustomapplication.sh"

# Create app instance
TCustomApplication.new app

# Initialize arguments from real parameters
app.SetArgs "\$@"

# Execute app code
$app_code
TESTAPP
    
    # Verify file was created
    if [[ ! -f "${TCA_TMPD}/${app_name}.sh" ]]; then
        kt_test_fail "Internal error: Failed to create test app: ${TCA_TMPD}/${app_name}.sh"
        return 1
    fi
    
    # Make executable
    chmod +x "${TCA_TMPD}/${app_name}.sh" || {
        kt_test_fail "Internal error: Failed to make executable: ${TCA_TMPD}/${app_name}.sh"
        return 1
    }
    
    # Verify it's executable
    if [[ ! -x "${TCA_TMPD}/${app_name}.sh" ]]; then
        kt_test_fail "Internal error: File is not executable: ${TCA_TMPD}/${app_name}.sh"
        return 1
    fi
    

}

kt_test_section "021: TCustomApplication Command Line Options via External Scripts"

# Test 1: FindOptionIndex with short option
kt_test_start "FindOptionIndex with short option (external script)"
create_test_app "test_findopt_short" 'app.FindOptionIndex "v" ""
echo "$RESULT"'
output=$("${TCA_TMPD}/test_findopt_short.sh" -v file.txt --verbose 2>&1)
if [[ "$output" == "1" ]]; then
    kt_test_pass "FindOptionIndex correctly identifies short option"
else
    kt_test_fail "FindOptionIndex unexpected result: $output (expected 1)"
fi

# Test 2: FindOptionIndex with long option
kt_test_start "FindOptionIndex with long option (external script)"
create_test_app "test_findopt_long" 'app.FindOptionIndex "" "verbose"
echo "$RESULT"'
output=$("${TCA_TMPD}/test_findopt_long.sh" -h file.txt --verbose data.txt 2>&1)
if [[ "$output" == "3" ]]; then
    kt_test_pass "FindOptionIndex correctly identifies long option"
else
    kt_test_fail "FindOptionIndex unexpected result: $output (expected 3)"
fi

# Test 3: FindOptionIndex with StartAt parameter — FPC scans DOWNWARD, so the
# default (-1) is the LAST occurrence and StartAt walks back towards index 1.
kt_test_start "FindOptionIndex with StartAt parameter (external script)"
create_test_app "test_findopt_startat" 'app.FindOptionIndex "v" ""
last=$RESULT
app.FindOptionIndex "v" "" $((last - 1))
echo "$last:$RESULT"'
output=$("${TCA_TMPD}/test_findopt_startat.sh" -v file.txt -v data.txt 2>&1)
if [[ "$output" == "3:1" ]]; then
    kt_test_pass "FindOptionIndex with StartAt finds the previous occurrence"
else
    kt_test_fail "FindOptionIndex unexpected result: $output (expected 3:1)"
fi

# Test 4: FindOptionIndex returns -1 for non-existent option
kt_test_start "FindOptionIndex returns -1 for non-existent (external script)"
create_test_app "test_findopt_notfound" 'app.FindOptionIndex "x" ""
echo "$RESULT"'
output=$("${TCA_TMPD}/test_findopt_notfound.sh" file.txt data.txt 2>&1)
if [[ "$output" == "-1" ]]; then
    kt_test_pass "FindOptionIndex returns -1 for non-existent option"
else
    kt_test_fail "FindOptionIndex unexpected result: $output (expected -1)"
fi

# Test 5: GetOptionValue with short option
kt_test_start "GetOptionValue with short option (external script)"
create_test_app "test_getoptval_short" 'app.GetOptionValue "c" ""
echo "$RESULT"'
output=$("${TCA_TMPD}/test_getoptval_short.sh" -c config.ini file.txt 2>&1)
if [[ "$output" == "config.ini" ]]; then
    kt_test_pass "GetOptionValue returns correct value for short option"
else
    kt_test_fail "GetOptionValue unexpected result: $output (expected config.ini)"
fi

# Test 6: GetOptionValue with long option
kt_test_start "GetOptionValue with long option (external script)"
create_test_app "test_getoptval_long" 'app.GetOptionValue "" "config"
echo "$RESULT"'
# A long option carries its value only as --name=value (FPC GetOptionAtIndex).
output=$("${TCA_TMPD}/test_getoptval_long.sh" file.txt --config=data.ini 2>&1)
if [[ "$output" == "data.ini" ]]; then
    kt_test_pass "GetOptionValue returns correct value for long option"
else
    kt_test_fail "GetOptionValue unexpected result: $output (expected data.ini)"
fi

kt_test_start "GetOptionValue: a space-separated long value is NOT a value [TCA-01]"
output=$("${TCA_TMPD}/test_getoptval_long.sh" file.txt --config data.ini 2>&1)
if [[ -z "$output" ]]; then
    kt_test_pass "'--config data.ini' has no value"
else
    kt_test_fail "'--config data.ini' returned '$output', expected empty"
fi

# Test 7: GetOptionValue with both short and long forms
kt_test_start "GetOptionValue with char and string (external script)"
create_test_app "test_getoptval_both" 'app.GetOptionValue "c" "config"
echo "$RESULT"'
output=$("${TCA_TMPD}/test_getoptval_both.sh" -c test.conf file.txt 2>&1)
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
output=$("${TCA_TMPD}/test_getoptval_empty.sh" -v -h file.txt 2>&1)
if [[ "$output" == "EMPTY" ]]; then
    kt_test_pass "GetOptionValue returns empty when next arg is another option"
else
    kt_test_fail "GetOptionValue unexpected result: $output (expected EMPTY)"
fi

# Test 9: HasOption with short option - found
kt_test_start "HasOption finds short option (external script)"
create_test_app "test_hasopt_short" 'app.HasOption "v" ""
echo "$RESULT"'
output=$("${TCA_TMPD}/test_hasopt_short.sh" -v file.txt 2>&1)
if [[ "$output" == "true" ]]; then
    kt_test_pass "HasOption returns true for existing short option"
else
    kt_test_fail "HasOption unexpected result: $output (expected true)"
fi

# Test 10: HasOption with long option - found
kt_test_start "HasOption finds long option (external script)"
create_test_app "test_hasopt_long" 'app.HasOption "" "verbose"
echo "$RESULT"'
output=$("${TCA_TMPD}/test_hasopt_long.sh" file.txt --verbose data.txt 2>&1)
if [[ "$output" == "true" ]]; then
    kt_test_pass "HasOption returns true for existing long option"
else
    kt_test_fail "HasOption unexpected result: $output (expected true)"
fi

# Test 11: HasOption returns false for non-existent option
kt_test_start "HasOption returns false for non-existent (external script)"
create_test_app "test_hasopt_notfound" 'app.HasOption "x" ""
echo "$RESULT"'
output=$("${TCA_TMPD}/test_hasopt_notfound.sh" file.txt data.txt 2>&1)
if [[ "$output" == "false" ]]; then
    kt_test_pass "HasOption returns false for non-existent option"
else
    kt_test_fail "HasOption unexpected result: $output (expected false)"
fi

# Test 12: HasOption with char and string
kt_test_start "HasOption with char and string (external script)"
create_test_app "test_hasopt_both" 'app.HasOption "v" "verbose"
echo "$RESULT"'
output=$("${TCA_TMPD}/test_hasopt_both.sh" -v file.txt 2>&1)
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
output=$("${TCA_TMPD}/test_checkopts_valid.sh" -h -v file.txt 2>&1)
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
output=$("${TCA_TMPD}/test_checkopts_invalid.sh" -x invalid file.txt 2>&1)
if [[ "$output" == "INVALID" ]]; then
    kt_test_pass "CheckOptions detects invalid options"
else
    kt_test_fail "CheckOptions failed to detect invalid options"
fi

# Test 15: GetOptionValues writes a caller array and returns the count (R10).
kt_test_start "GetOptionValues with multiple occurrences (external script)"
create_test_app "test_getoptvals_multi" 'declare -a vals=()
app.GetOptionValues "i" "" vals
printf "%s|" "$RESULT"
printf "%s," "${vals[@]}"'
output=$("${TCA_TMPD}/test_getoptvals_multi.sh" -i file1.txt -i file2.txt -i file3.txt 2>&1)
if [[ "$output" == "3|file3.txt,file2.txt,file1.txt," ]]; then
    kt_test_pass "GetOptionValues correctly returns multiple values (FPC order: last first)"
else
    kt_test_fail "GetOptionValues unexpected result: $output"
fi

kt_test_start "GetOptionValues keeps a value containing spaces whole [TCA-07]"
create_test_app "test_getoptvals_spaces" 'declare -a vals=()
app.GetOptionValues "f" "" vals
printf "%s|%s|%s" "$RESULT" "${vals[0]}" "${vals[1]}"'
output=$("${TCA_TMPD}/test_getoptvals_spaces.sh" -f "a b" -f c 2>&1)
if [[ "$output" == "2|c|a b" ]]; then
    kt_test_pass "two values, one of them with a space, are two array elements"
else
    kt_test_fail "GetOptionValues with spaces: '$output' (expected '2|c|a b')"
fi

kt_test_start "GetOptionValues rejects a bad output-array name [kcl README 1.7]"
create_test_app "test_getoptvals_badname" 'app.GetOptionValues "f" "" "not a name"
printf "%s" "$?"'
output=$("${TCA_TMPD}/test_getoptvals_badname.sh" -f x 2>&1)
if [[ "$output" == "2" ]]; then
    kt_test_pass "rc 2 for a malformed output-array name"
else
    kt_test_fail "expected rc 2 for a bad output-array name, got '$output'"
fi

# Test 16: GetOptionValues returns 0 for a non-existent option
kt_test_start "GetOptionValues for non-existent option (external script)"
create_test_app "test_getoptvals_notfound" 'app.GetOptionValues "x" ""
echo "$RESULT"'
output=$("${TCA_TMPD}/test_getoptvals_notfound.sh" file.txt data.txt 2>&1)
if [[ "$output" == "0" ]]; then
    kt_test_pass "GetOptionValues returns empty array for non-existent option"
else
    kt_test_fail "GetOptionValues unexpected result: $output (expected 0)"
fi

rm -rf "$TCA_TMPD"

kt_test_log "021_CommandLineOptionsExternalScript.sh completed"
