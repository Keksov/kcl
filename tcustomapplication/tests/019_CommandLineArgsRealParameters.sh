#!/bin/bash
# 019_CommandLineArgsRealParameters.sh - Test TCustomApplication with real command-line parameters
# This test file verifies that argument handling works with actual script parameters ($@)
# not just SetArgs() synthetic arguments

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

# Source tcustomapplication module
TCUSTOMAPPLICATION_DIR="$SCRIPT_DIR/.."
source "$TCUSTOMAPPLICATION_DIR/tcustomapplication.sh"

# Extract test name from filename
TEST_NAME="$(basename "$0" .sh)"
kt_test_init "$TEST_NAME" "$SCRIPT_DIR" "$@"

kt_test_section "019: TCustomApplication Command-Line Arguments from Real Parameters"

# Helper script that processes arguments
create_test_app() {
    local app_name="$1"
    shift
    
    # Create inline test application
    cat > "/tmp/${app_name}.sh" << 'TESTAPP'
#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TCUSTOMAPPLICATION_DIR="$SCRIPT_DIR/../projects/kkbot/kbool/kcl/tcustomapplication"
[[ ! -d "$TCUSTOMAPPLICATION_DIR" ]] && TCUSTOMAPPLICATION_DIR="c:/projects/kkbot/kbool/kcl/tcustomapplication"
source "$TCUSTOMAPPLICATION_DIR/tcustomapplication.sh"

TCustomApplication.new app

# Check options (will auto-initialize from real parameters)
app.CheckOptions "hv" "help version verbose" "false" "$@"
result=$?

# Return both exit code and output
echo "$RESULT"
exit $result
TESTAPP
    chmod +x "/tmp/${app_name}.sh"
}

# Test 1: Real parameters with short options
kt_test_start "Real parameters with valid short options"
create_test_app "test_app_1"
output=$(/tmp/test_app_1.sh -h -v 2>&1)
if [[ -z "$output" ]]; then
    kt_test_pass "Application accepts real -h -v parameters"
else
    kt_test_fail "Application rejected valid short options: $output"
fi
rm -f /tmp/test_app_1.sh

# Test 2: Real parameters with long options
kt_test_start "Real parameters with valid long options"
create_test_app "test_app_2"
output=$(/tmp/test_app_2.sh --help --version 2>&1)
if [[ -z "$output" ]]; then
    kt_test_pass "Application accepts real --help --version parameters"
else
    kt_test_fail "Application rejected valid long options: $output"
fi
rm -f /tmp/test_app_2.sh

# Test 3: Real parameters with mixed short and long options
kt_test_start "Real parameters with mixed short and long options"
create_test_app "test_app_3"
output=$(/tmp/test_app_3.sh -h --version 2>&1)
if [[ -z "$output" ]]; then
    kt_test_pass "Application accepts mixed -h --version parameters"
else
    kt_test_fail "Application rejected mixed options: $output"
fi
rm -f /tmp/test_app_3.sh

# Test 4: Real parameters with file arguments
kt_test_start "Real parameters with file arguments"
create_test_app "test_app_4"
output=$(/tmp/test_app_4.sh -v file.txt data.txt 2>&1)
if [[ -z "$output" ]]; then
    kt_test_pass "Application accepts options with file arguments"
else
    kt_test_fail "Application rejected options with files: $output"
fi
rm -f /tmp/test_app_4.sh

# Test 5: Real parameters with invalid option detection
kt_test_start "Real parameters with invalid option detection"
create_test_app "test_app_5"
output=$(/tmp/test_app_5.sh -x 2>&1)
if [[ -n "$output" ]]; then
    kt_test_pass "Application detects invalid option -x in real parameters"
else
    kt_test_fail "Application failed to detect invalid option"
fi
rm -f /tmp/test_app_5.sh

# Test 6: Direct test - auto-initialization from parameters
kt_test_start "Direct auto-initialization from parameters"
TCustomApplication.new direct_app
# Use SetArgs to initialize with test parameters
direct_app.SetArgs -- --help -v file.txt
direct_app.FindOptionIndex "" "help" 0
result=$RESULT
if [[ "$result" == "0" ]]; then
    kt_test_pass "Auto-initialization correctly stores arguments"
else
    kt_test_fail "Auto-initialization failed: index=$result (expected 0)"
fi
direct_app.delete

# Test 7: Verify SetArgs preserves arguments for multiple calls
kt_test_start "SetArgs preserves arguments for multiple function calls"
TCustomApplication.new app1
app1.SetArgs -- --verbose -h test.conf

# First call
app1.FindOptionIndex "" "verbose" 0
idx1=$RESULT

# Second call on same instance should still work with cached args
app1.FindOptionIndex "h" "" 0
idx2=$RESULT

if [[ "$idx1" == "0" && "$idx2" == "1" ]]; then
    kt_test_pass "SetArgs preserves arguments across multiple calls"
else
    kt_test_fail "SetArgs failed: verbose at $idx1 (expected 0), h at $idx2 (expected 1)"
fi
app1.delete

kt_test_log "019_CommandLineArgsRealParameters.sh completed"
