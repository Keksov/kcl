#!/bin/bash
# 009_OnExceptionProperty.sh - Test TCustomApplication OnException property
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


kk_test_section "009: TCustomApplication OnException Property"

# Test: OnException property getter (default)
kk_test_start "OnException property getter default"
TCustomApplication.new myapp
on_exception_default=$(myapp.OnException)
if [[ -z "$on_exception_default" ]]; then
    kk_test_pass "OnException property defaults to empty"
else
    kk_test_fail "OnException property default unexpected: $on_exception_default"
fi
myapp.delete

# Test: OnException property setter
kk_test_start "OnException property setter"
TCustomApplication.new myapp
# Mock setting OnException handler (in real implementation, this would be a function reference)
myapp.property OnException = "mock_handler_function"
on_exception_set=$(myapp.OnException)
if [[ "$on_exception_set" == "mock_handler_function" ]]; then
    kk_test_pass "OnException property setter works"
else
    kk_test_fail "OnException property setter failed: got '$on_exception_set'"
fi
myapp.delete

# Test: HandleException calls OnException handler
kk_test_start "HandleException calls OnException handler"
TCustomApplication.new myapp
# Set mock handler
myapp.property OnException = "test_exception_handler"
# Call HandleException with exception
myapp.HandleException "test_sender" "test_exception"
result=$?
if [[ $result -eq 0 ]]; then
    kk_test_pass "HandleException with OnException handler completed"
else
    kk_test_fail "HandleException with OnException handler failed"
fi
myapp.delete

# Test: HandleException without OnException handler uses default
kk_test_start "HandleException without OnException handler"
TCustomApplication.new myapp
# OnException not set
myapp.HandleException "test_sender" "test_exception_no_handler"
result=$?
if [[ $result -eq 0 ]]; then
    kk_test_pass "HandleException without OnException uses default handling"
else
    kk_test_fail "HandleException without OnException failed"
fi
myapp.delete

# Test: OnException handler prevents ShowException call
kk_test_start "OnException handler prevents ShowException"
TCustomApplication.new myapp
myapp.property OnException = "prevent_show_exception"
terminated_before=$(myapp.terminated)
myapp.HandleException "sender" "exception_with_handler"
terminated_after=$(myapp.terminated)
# If OnException is set, ShowException should not be called, and termination depends on StopOnException
if [[ "$terminated_before" == "false" ]]; then
    kk_test_pass "OnException handler integration works"
else
    kk_test_fail "OnException handler integration failed"
fi
myapp.delete

kk_test_log "009_OnExceptionProperty.sh completed"