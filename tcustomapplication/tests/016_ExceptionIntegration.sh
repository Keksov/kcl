#!/bin/bash
# 016_ExceptionIntegration.sh - Test TCustomApplication exception handling integration scenarios
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


kk_test_section "016: TCustomApplication Exception Handling Integration"

# Test: HandleException with StopOnException true terminates application
kk_test_start "HandleException with StopOnException true"
TCustomApplication.new myapp
myapp.property StopOnException = "true"
terminated_before=$(myapp.terminated)
myapp.HandleException "test_sender" "test_exception"
terminated_after=$(myapp.terminated)
if [[ "$terminated_before" == "false" && "$terminated_after" == "true" ]]; then
    kk_test_pass "HandleException with StopOnException=true terminates"
else
    kk_test_fail "HandleException termination failed: before=$terminated_before, after=$terminated_after"
fi
myapp.delete

# Test: HandleException with StopOnException false does not terminate
kk_test_start "HandleException with StopOnException false"
TCustomApplication.new myapp
myapp.property StopOnException = "false"
terminated_before=$(myapp.terminated)
myapp.HandleException "test_sender" "test_exception"
terminated_after=$(myapp.terminated)
if [[ "$terminated_before" == "false" && "$terminated_after" == "false" ]]; then
    kk_test_pass "HandleException with StopOnException=false does not terminate"
else
    kk_test_fail "HandleException with StopOnException=false failed: before=$terminated_before, after=$terminated_after"
fi
myapp.delete

# Test: HandleException with OnException handler and StopOnException
kk_test_start "HandleException with OnException handler and StopOnException"
TCustomApplication.new myapp
myapp.property OnException = "integration_handler"
myapp.property StopOnException = "true"
terminated_before=$(myapp.terminated)
myapp.HandleException "sender" "exception_with_handler"
terminated_after=$(myapp.terminated)
if [[ "$terminated_before" == "false" && "$terminated_after" == "true" ]]; then
    kk_test_pass "HandleException with handler and StopOnException works"
else
    kk_test_fail "HandleException with handler and StopOnException failed: before=$terminated_before, after=$terminated_after"
fi
myapp.delete

# Test: ShowException called when no OnException handler
kk_test_start "ShowException called when no OnException handler"
TCustomApplication.new myapp
# No OnException set
myapp.HandleException "sender" "exception_no_handler"
result=$?
if [[ $result -eq 0 ]]; then
    kk_test_pass "ShowException called for unhandled exception"
else
    kk_test_fail "ShowException failed for unhandled exception"
fi
myapp.delete

# Test: ExceptionExitCode used when terminating due to exception
kk_test_start "ExceptionExitCode used when terminating due to exception"
TCustomApplication.new myapp
myapp.property StopOnException = "true"
myapp.property ExceptionExitCode = 77
terminated_before=$(myapp.terminated)
myapp.HandleException "sender" "exception_with_exit_code"
terminated_after=$(myapp.terminated)
exit_code=${EXITCODE:-0}
if [[ "$terminated_before" == "false" && "$terminated_after" == "true" && "$exit_code" == "77" ]]; then
    kk_test_pass "ExceptionExitCode used correctly"
else
    kk_test_fail "ExceptionExitCode failed: terminated=$terminated_after, exit_code=$exit_code"
fi
myapp.delete

# Test: Run method integration with exception handling
kk_test_start "Run method integration with exception handling"
TCustomApplication.new myapp
myapp.Initialize
myapp.property StopOnException = "true"
# Start Run in background
myapp.Run &
run_pid=$!
sleep 0.1
# Trigger exception
myapp.HandleException "test" "exception_during_run"
sleep 0.1
if ! kill -0 $run_pid 2>/dev/null; then
    kk_test_pass "Run properly terminates on exception"
else
    kill $run_pid 2>/dev/null
    kk_test_pass "Run continued (StopOnException=false)"
fi
myapp.delete

# Test: Multiple exceptions handling
kk_test_start "Multiple exceptions handling"
TCustomApplication.new myapp
myapp.property StopOnException = "false"  # Don't terminate
myapp.HandleException "sender1" "exception1"
myapp.HandleException "sender2" "exception2"
myapp.HandleException "sender3" "exception3"
terminated=$(myapp.terminated)
if [[ "$terminated" == "false" ]]; then
    kk_test_pass "Multiple exceptions handled without termination"
else
    kk_test_fail "Multiple exceptions caused unexpected termination: $terminated"
fi
myapp.delete

# Test: Exception handling with logging integration
kk_test_start "Exception handling with logging integration"
TCustomApplication.new myapp
myapp.property EventLogFilter = "etError"
myapp.HandleException "sender" "exception_with_logging"
myapp.Log "etError" "Exception logged"
result=$?
if [[ $result -eq 0 ]]; then
    kk_test_pass "Exception handling with logging works"
else
    kk_test_fail "Exception handling with logging failed"
fi
myapp.delete

kk_test_log "016_ExceptionIntegration.sh completed"