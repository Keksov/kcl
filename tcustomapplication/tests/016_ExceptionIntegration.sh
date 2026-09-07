#!/bin/bash
# 016_ExceptionIntegration.sh - Test TCustomApplication exception handling integration scenarios
# Auto-generated for ktests framework

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

# Source tcustomapplication module
TCUSTOMAPPLICATION_DIR="$SCRIPT_DIR/.."
source "$TCUSTOMAPPLICATION_DIR/tcustomapplication.sh"

# Extract test name from filename
TEST_NAME="$(basename "$0" .sh)"
kt_test_init "$TEST_NAME" "$SCRIPT_DIR" "$@"

# Define exception handlers for tests
declare -g HANDLED=0
integration_handler() {
    # Handler for OnException tests
    HANDLED=$(( HANDLED + 1 ))
    return 0
}

kt_test_section "016: TCustomApplication Exception Handling Integration"

# Test: HandleException with StopOnException true terminates application
kt_test_start "HandleException with StopOnException true"
TCustomApplication.new myapp
myapp.property StopOnException = "true"
terminated_before=$(myapp.Terminated)
myapp.HandleException "test_sender" "test_exception" 2>/dev/null
terminated_after=$(myapp.Terminated)
if [[ "$terminated_before" == "false" && "$terminated_after" == "true" ]]; then
    kt_test_pass "HandleException with StopOnException=true terminates"
else
    kt_test_fail "HandleException termination failed: before=$terminated_before, after=$terminated_after"
fi
myapp.delete

# Test: HandleException with StopOnException false does not terminate
kt_test_start "HandleException with StopOnException false"
TCustomApplication.new myapp
myapp.property StopOnException = "false"
terminated_before=$(myapp.Terminated)
myapp.HandleException "test_sender" "test_exception" 2>/dev/null
terminated_after=$(myapp.Terminated)
if [[ "$terminated_before" == "false" && "$terminated_after" == "false" ]]; then
    kt_test_pass "HandleException with StopOnException=false does not terminate"
else
    kt_test_fail "HandleException with StopOnException=false failed: before=$terminated_before, after=$terminated_after"
fi
myapp.delete

# Test: HandleException with OnException handler and StopOnException
kt_test_start "HandleException with OnException handler and StopOnException"
TCustomApplication.new myapp
myapp.property OnException = "integration_handler"
myapp.property StopOnException = "true"
terminated_before=$(myapp.Terminated)
myapp.HandleException "sender" "exception_with_handler" 2>/dev/null
terminated_after=$(myapp.Terminated)
if [[ "$terminated_before" == "false" && "$terminated_after" == "true" ]]; then
    kt_test_pass "HandleException with handler and StopOnException works"
else
    kt_test_fail "HandleException with handler and StopOnException failed: before=$terminated_before, after=$terminated_after"
fi
myapp.delete

# Test: ShowException called when no OnException handler
kt_test_start "ShowException called when no OnException handler"
TMPD="$SCRIPT_DIR/.tmp/$(basename "${BASH_SOURCE[0]}" .sh)"
mkdir -p "$TMPD"
TCustomApplication.new myapp
myapp.property StopOnException = "false"
# No OnException set
myapp.HandleException "sender" "exception_no_handler" 2>"$TMPD/err.txt"
err="$(<"$TMPD/err.txt")"
if [[ "$err" == "Exception: exception_no_handler" ]]; then
    kt_test_pass "ShowException wrote the message to stderr"
else
    kt_test_fail "ShowException output: '$err'"
fi
myapp.delete

# Test: ExceptionExitCode used when terminating due to exception
kt_test_start "ExceptionExitCode used when terminating due to exception"
TCustomApplication.new myapp
myapp.property StopOnException = "true"
myapp.property ExceptionExitCode = 77
terminated_before=$(myapp.Terminated)
myapp.HandleException "sender" "exception_with_exit_code" 2>/dev/null
terminated_after=$(myapp.Terminated)
exit_code=${EXITCODE:-0}
if [[ "$terminated_before" == "false" && "$terminated_after" == "true" && "$exit_code" == "77" ]]; then
    kt_test_pass "ExceptionExitCode used correctly"
else
    kt_test_fail "ExceptionExitCode failed: terminated=$terminated_after, exit_code=$exit_code"
fi
myapp.delete

# Test: Run integration with exception handling.
# The old form started `Run &`, killed it and passed on BOTH branches, so it
# could not fail. Run is now an in-process loop (finding TCA-10), so the
# interaction is observable: a DoRun that fails once is handled and the loop
# carries on when StopOnException is false.
class TFlakyApp : TCustomApplication
    public
        override proc DoRun
end

TFlakyApp.DoRun() {
    TCA_PASSES=$(( TCA_PASSES + 1 ))
    if (( TCA_PASSES == 1 )); then
        return 1          # first pass "raises"
    fi
    $this.Terminate 0
    return 0
}

build TFlakyApp

kt_test_start "Run integration: a failing DoRun is handled and the loop continues"
mkdir -p "$TMPD"
TFlakyApp.new flaky
flaky.Initialize
flaky.property StopOnException = "false"
flaky.property OnException = "integration_handler"
declare -g TCA_PASSES=0
declare -g HANDLED=0
flaky.Run 2>"$TMPD/run.err"
rc=$?
terminated=$(flaky.Terminated)
if [[ $rc -eq 0 && "$TCA_PASSES" == "2" && "$HANDLED" == "1" && "$terminated" == "true" ]]; then
    kt_test_pass "two passes, one handled exception, then Terminate"
else
    kt_test_fail "Run integration: rc=$rc passes=$TCA_PASSES handled=$HANDLED terminated=$terminated"
fi
flaky.delete

# Test: Multiple exceptions handling
kt_test_start "Multiple exceptions handling"
TCustomApplication.new myapp
myapp.property StopOnException = "false"  # Don't terminate
myapp.HandleException "sender1" "exception1" 2>/dev/null
myapp.HandleException "sender2" "exception2" 2>/dev/null
myapp.HandleException "sender3" "exception3" 2>/dev/null
terminated=$(myapp.Terminated) 2>/dev/null
if [[ "$terminated" == "false" ]]; then
    kt_test_pass "Multiple exceptions handled without termination"
else
    kt_test_fail "Multiple exceptions caused unexpected termination: $terminated"
fi
myapp.delete

# Test: Exception handling with logging integration
kt_test_start "Exception handling with logging integration"
TCustomApplication.new myapp
myapp.property EventLogFilter = "etError"
myapp.property StopOnException = "false"
: > "$TMPD/err.txt"
myapp.HandleException "sender" "exception_with_logging" 2>>"$TMPD/err.txt"
myapp.Log "etInfo" "dropped by the filter" 2>>"$TMPD/err.txt"
myapp.Log "etError" "Exception logged" 2>>"$TMPD/err.txt"
mapfile -t lines < "$TMPD/err.txt"
if [[ ${#lines[@]} -eq 2 && "${lines[0]}" == "Exception: exception_with_logging" && "${lines[1]}" == "etError: Exception logged" ]]; then
    kt_test_pass "the exception and the etError line are logged, the etInfo line is not"
else
    kt_test_fail "exception + logging: $(declare -p lines)"
fi
myapp.delete
rm -rf "$TMPD"

kt_test_log "016_ExceptionIntegration.sh completed"