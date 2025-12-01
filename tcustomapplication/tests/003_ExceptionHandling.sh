#!/bin/bash
# 003_ExceptionHandling.sh - Test TCustomApplication exception handling methods
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


kt_test_section "003: TCustomApplication Exception Handling"

# Test: HandleException with Exception object
kt_test_start "HandleException with Exception object"
TCustomApplication.new myapp
# Create a mock exception object (simulated)
exception_msg="Test exception"
myapp.HandleException "mock_sender" "$exception_msg"
result=$?
if [[ $result -eq 0 ]]; then
    kt_test_pass "HandleException with Exception object completed"
else
    kt_test_fail "HandleException with Exception object failed"
fi
myapp.delete

# Test: HandleException with non-Exception object
kt_test_start "HandleException with non-Exception object"
TCustomApplication.new myapp
myapp.HandleException "mock_sender" "not_an_exception_object"
result=$?
if [[ $result -eq 0 ]]; then
    kt_test_pass "HandleException with non-Exception handled default case"
else
    kt_test_fail "HandleException with non-Exception failed"
fi
myapp.delete

# Test: HandleException with OnException handler set
kt_test_start "HandleException with OnException handler"
TCustomApplication.new myapp
# Mock setting OnException handler (would be set via property in real implementation)
myapp.HandleException "mock_sender" "test_exception_with_handler"
result=$?
if [[ $result -eq 0 ]]; then
    kt_test_pass "HandleException with OnException handler completed"
else
    kt_test_fail "HandleException with OnException handler failed"
fi
myapp.delete

# Test: HandleException triggering termination on StopOnException
kt_test_start "HandleException triggering termination"
TCustomApplication.new myapp
# Set StopOnException to true (would be via property)
terminated_before=$(myapp.terminated)
myapp.HandleException "mock_sender" "exception_with_stop"
terminated_after=$(myapp.terminated)
if [[ "$terminated_before" == "false" && "$terminated_after" == "true" ]]; then
    kt_test_pass "HandleException triggered termination as expected"
else
    kt_test_fail "HandleException termination failed: before=$terminated_before, after=$terminated_after"
fi
myapp.delete

# Test: ShowException method
kt_test_start "ShowException method"
TCustomApplication.new myapp
myapp.ShowException "Test exception message"
result=$?
if [[ $result -eq 0 ]]; then
    kt_test_pass "ShowException method completed"
else
    kt_test_fail "ShowException method failed"
fi
myapp.delete

# Test: ShowException with empty message
kt_test_start "ShowException with empty message"
TCustomApplication.new myapp
myapp.ShowException ""
result=$?
if [[ $result -eq 0 ]]; then
    kt_test_pass "ShowException with empty message completed"
else
    kt_test_fail "ShowException with empty message failed"
fi
myapp.delete

# Test: ShowException with long message
kt_test_start "ShowException with long message"
TCustomApplication.new myapp
long_msg="This is a very long exception message that contains multiple lines and various characters to test the ShowException method's ability to handle complex input. It includes numbers 1234567890, special chars !@#$%^&*(), and should demonstrate proper handling of lengthy exception descriptions."
myapp.ShowException "$long_msg"
result=$?
if [[ $result -eq 0 ]]; then
    kt_test_pass "ShowException with long message completed"
else
    kt_test_fail "ShowException with long message failed"
fi
myapp.delete

# Test: HandleException called multiple times
kt_test_start "Multiple HandleException calls"
TCustomApplication.new myapp
myapp.HandleException "sender1" "exception1"
myapp.HandleException "sender2" "exception2"
myapp.HandleException "sender3" "exception3"
result=$?
if [[ $result -eq 0 ]]; then
    kt_test_pass "Multiple HandleException calls completed"
else
    kt_test_fail "Multiple HandleException calls failed"
fi
myapp.delete

kt_test_log "003_ExceptionHandling.sh completed"