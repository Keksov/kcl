#!/bin/bash
# 026_MixedShortOptions.sh - Test mixed/combined short options
# Tests handling of -abc format where it should be -a -b -c via CheckOptions

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

# Source tcustomapplication module
TCUSTOMAPPLICATION_DIR="$SCRIPT_DIR/.."
source "$TCUSTOMAPPLICATION_DIR/tcustomapplication.sh"

# Extract test name from filename
TEST_NAME="$(basename "$0" .sh)"
kt_test_init "$TEST_NAME" "$SCRIPT_DIR" "$@"

kt_test_section "026: TCustomApplication Mixed/Combined Short Options"

# Test: Single option -v
kt_test_start "Single short option -v"
TCustomApplication.new myapp
myapp.SetArgs -- -v file.txt
myapp.HasOption "v" ""
result=$RESULT
if [[ "$result" == "true" ]]; then
    kt_test_pass "Single option -v found"
else
    kt_test_fail "Single option -v failed: $result"
fi
myapp.delete

# Test: Combined options -vh without separate args (via CheckOptions)
kt_test_start "Combined short options -vh (two chars)"
TCustomApplication.new myapp
myapp.SetArgs -- -vh file.txt
# In standard processing, -vh is treated as one argument with multiple options
myapp.CheckOptions "vh" ""
error_msg=$RESULT
if [[ -z "$error_msg" ]]; then
    kt_test_pass "CheckOptions accepts -vh as valid options"
else
    kt_test_fail "CheckOptions with -vh failed: $error_msg"
fi
myapp.delete

# Test: Three combined options -vhd
kt_test_start "Combined short options -vhd (three chars)"
TCustomApplication.new myapp
myapp.SetArgs -- -vhd file.txt
myapp.CheckOptions "vhd" ""
error_msg=$RESULT
if [[ -z "$error_msg" ]]; then
    kt_test_pass "CheckOptions accepts -vhd as valid options"
else
    kt_test_fail "CheckOptions with -vhd failed: $error_msg"
fi
myapp.delete

# Test: Combined options with colons (options that take values)
kt_test_start "Combined options including those with values"
TCustomApplication.new myapp
myapp.SetArgs -- -hvc config.ini file.txt
# -h (no value), -v (no value), -c (takes value: config.ini)
myapp.CheckOptions "hvc:" ""
error_msg=$RESULT
if [[ -z "$error_msg" ]]; then
    kt_test_pass "CheckOptions handles combined options with value-taking options"
else
    kt_test_fail "CheckOptions combined with values failed: $error_msg"
fi
myapp.delete

# Test: Long option doesn't get treated as combined
kt_test_start "Long option -dash is not combined short options"
TCustomApplication.new myapp
myapp.SetArgs -- --verbose file.txt
# --verbose should be one long option, not "v" "e" "r" "b" "o" "s" "e"
myapp.FindOptionIndex "" "verbose" 0
result=$RESULT
if [[ "$result" == "0" ]]; then
    kt_test_pass "Long options correctly distinguished from combined short"
else
    kt_test_fail "Long option handling failed: $result"
fi
myapp.delete

# Test: GetNonOptions with combined options
kt_test_start "GetNonOptions excludes combined short options"
TCustomApplication.new myapp
myapp.SetArgs -- -vh file1.txt -a file2.txt
myapp.GetNonOptions "vha" ""
result=$RESULT
if [[ "$result" == "2" ]]; then
    kt_test_pass "GetNonOptions correctly counts files with combined options"
else
    kt_test_fail "GetNonOptions with combined failed: $result (expected 2)"
fi
myapp.delete

# Test: Multiple separate combined options
kt_test_start "Multiple separate combined short options"
TCustomApplication.new myapp
myapp.SetArgs -- -vh -ab -cd
myapp.CheckOptions "vhabcd" ""
error_msg=$RESULT
if [[ -z "$error_msg" ]]; then
    kt_test_pass "Multiple combined options all validated"
else
    kt_test_fail "Multiple combined options failed: $error_msg"
fi
myapp.delete

# Test: Combined with invalid char mixed in
kt_test_start "Combined option with one invalid char"
TCustomApplication.new myapp
myapp.SetArgs -- -vxh
myapp.CheckOptions "vh" ""
error_msg=$RESULT
if [[ -n "$error_msg" ]]; then
    kt_test_pass "CheckOptions detects invalid char in combined option"
else
    kt_test_fail "Should reject -vxh when x not allowed"
fi
myapp.delete

# Test: Single dash with multiple chars vs long option
kt_test_start "Distinguish -abc (combined) from --abc (long)"
TCustomApplication.new myapp
myapp.SetArgs -- -abc --abc
# -abc could be combined short, --abc is definitely long
myapp.CheckOptions "abc" "abc"
error_msg=$RESULT
if [[ -z "$error_msg" ]]; then
    kt_test_pass "Both combined short and long option forms accepted"
else
    kt_test_fail "CheckOptions both forms failed: $error_msg"
fi
myapp.delete

# Test: Empty combined option string
kt_test_start "Treat single dash as non-option"
TCustomApplication.new myapp
myapp.SetArgs -- - file.txt
myapp.GetNonOptions "vh" ""
result=$RESULT
# Single "-" should be treated as non-option (file argument)
if [[ "$result" == "2" ]]; then
    kt_test_pass "Single dash treated as non-option argument"
else
    kt_test_fail "Single dash test failed: $result"
fi
myapp.delete

# Test: Case sensitivity in combined options
kt_test_start "Combined options respect case sensitivity"
TCustomApplication.new myapp
myapp.SetArgs -- -VH
myapp.CheckOptions "vh" ""
error_msg=$RESULT
if [[ -n "$error_msg" ]]; then
    kt_test_pass "Case sensitivity applied to combined options"
else
    kt_test_fail "Should reject -VH when only lowercase allowed"
fi
myapp.delete

# Test: Individual chars in combined - CheckOptions extracts them
kt_test_start "CheckOptions identifies individual chars in combined -vh"
TCustomApplication.new myapp
myapp.SetArgs -- -vh
# CheckOptions should see this as -v and -h
myapp.CheckOptions "vh" ""
error_msg=$RESULT
if [[ -z "$error_msg" ]]; then
    kt_test_pass "CheckOptions recognizes combined options as valid"
else
    kt_test_fail "CheckOptions should accept -vh with vh spec: $error_msg"
fi
myapp.delete

# Test: Combined options at different positions
kt_test_start "Combined options at different positions"
TCustomApplication.new myapp
myapp.SetArgs -- file.txt -vhd -c config.ini
myapp.CheckOptions "vhdc:" ""
error_msg=$RESULT
if [[ -z "$error_msg" ]]; then
    kt_test_pass "Combined options at position 1 validated correctly"
else
    kt_test_fail "Combined at different position failed: $error_msg"
fi
myapp.delete

kt_test_log "026_MixedShortOptions.sh completed"
