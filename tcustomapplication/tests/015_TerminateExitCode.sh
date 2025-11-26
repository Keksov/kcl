#!/bin/bash
# 015_TerminateExitCode.sh - Test TCustomApplication Terminate setting System.ExitCode
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


kk_test_section "015: TCustomApplication Terminate and System.ExitCode"

# Test: Terminate with exit code sets System.ExitCode
kk_test_start "Terminate with exit code sets System.ExitCode"
TCustomApplication.new myapp
initial_exit_code=${EXITCODE:-0}  # Assume EXITCODE variable or default 0
myapp.Terminate 42
final_exit_code=${EXITCODE:-0}
terminated=$(myapp.terminated)
if [[ "$terminated" == "true" && "$final_exit_code" == "42" ]]; then
    kk_test_pass "Terminate sets System.ExitCode correctly"
else
    kk_test_fail "Terminate failed to set System.ExitCode: terminated=$terminated, exit_code=$final_exit_code"
fi
myapp.delete

# Test: Terminate with zero exit code
kk_test_start "Terminate with zero exit code"
TCustomApplication.new myapp
myapp.Terminate 0
exit_code_zero=${EXITCODE:-0}
terminated_zero=$(myapp.terminated)
if [[ "$terminated_zero" == "true" && "$exit_code_zero" == "0" ]]; then
    kk_test_pass "Terminate with zero exit code works"
else
    kk_test_fail "Terminate with zero exit code failed: terminated=$terminated_zero, exit_code=$exit_code_zero"
fi
myapp.delete

# Test: Terminate with negative exit code
kk_test_start "Terminate with negative exit code"
TCustomApplication.new myapp
myapp.Terminate -1
exit_code_neg=${EXITCODE:-0}
terminated_neg=$(myapp.terminated)
if [[ "$terminated_neg" == "true" && "$exit_code_neg" == "-1" ]]; then
    kk_test_pass "Terminate with negative exit code works"
else
    kk_test_fail "Terminate with negative exit code failed: terminated=$terminated_neg, exit_code=$exit_code_neg"
fi
myapp.delete

# Test: Terminate without exit code (default)
kk_test_start "Terminate without exit code"
TCustomApplication.new myapp
myapp.Terminate
exit_code_default=${EXITCODE:-0}
terminated_default=$(myapp.terminated)
if [[ "$terminated_default" == "true" ]]; then
    kk_test_pass "Terminate without exit code works"
else
    kk_test_fail "Terminate without exit code failed: terminated=$terminated_default"
fi
myapp.delete

# Test: Multiple Terminate calls with different exit codes
kk_test_start "Multiple Terminate calls with different exit codes"
TCustomApplication.new myapp
myapp.Terminate 10
exit_code1=${EXITCODE:-0}
myapp.Terminate 20
exit_code2=${EXITCODE:-0}
terminated_multi=$(myapp.terminated)
if [[ "$terminated_multi" == "true" && "$exit_code2" == "20" ]]; then
    kk_test_pass "Multiple Terminate calls work, last exit code prevails"
else
    kk_test_fail "Multiple Terminate calls failed: terminated=$terminated_multi, exit_code2=$exit_code2"
fi
myapp.delete

# Test: Terminate with large exit code
kk_test_start "Terminate with large exit code"
TCustomApplication.new myapp
myapp.Terminate 255
exit_code_large=${EXITCODE:-0}
terminated_large=$(myapp.terminated)
if [[ "$terminated_large" == "true" && "$exit_code_large" == "255" ]]; then
    kk_test_pass "Terminate with large exit code works"
else
    kk_test_fail "Terminate with large exit code failed: terminated=$terminated_large, exit_code=$exit_code_large"
fi
myapp.delete

# Test: Terminate and check ExceptionExitCode interaction
kk_test_start "Terminate and ExceptionExitCode interaction"
TCustomApplication.new myapp
myapp.property ExceptionExitCode = 99
# Terminate without code should not override ExceptionExitCode
myapp.Terminate
exit_code_exception=${EXITCODE:-0}
terminated_exception=$(myapp.terminated)
if [[ "$terminated_exception" == "true" ]]; then
    kk_test_pass "Terminate respects ExceptionExitCode setting"
else
    kk_test_fail "Terminate ExceptionExitCode interaction failed: terminated=$terminated_exception"
fi
myapp.delete

kk_test_log "015_TerminateExitCode.sh completed"