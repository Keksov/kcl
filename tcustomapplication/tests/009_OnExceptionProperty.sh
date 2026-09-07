#!/bin/bash
# 009_OnExceptionProperty.sh - the OnException property and its validation.
#
# TCA-20: `OnException = "my handler"` used to be executed as a command, so the
# shell printed "my: command not found" and HandleException carried on as if a
# handler had run. The name is now checked with `declare -F` and anything that
# is not a defined function falls back to ShowException.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

# Source tcustomapplication module
TCUSTOMAPPLICATION_DIR="$SCRIPT_DIR/.."
source "$TCUSTOMAPPLICATION_DIR/tcustomapplication.sh"

# Extract test name from filename
TEST_NAME="$(basename "$0" .sh)"
kt_test_init "$TEST_NAME" "$SCRIPT_DIR" "$@"

TMPD="$SCRIPT_DIR/.tmp/$(basename "${BASH_SOURCE[0]}" .sh)"
mkdir -p "$TMPD"
ERRF="$TMPD/stderr.txt"

declare -g HANDLER_CALLS=0
mock_handler_function() {
    HANDLER_CALLS=$(( HANDLER_CALLS + 1 ))
    return 0
}

kt_test_section "009: TCustomApplication OnException Property"

kt_test_start "OnException property getter default"
TCustomApplication.new myapp
on_exception_default=$(myapp.OnException)
if [[ -z "$on_exception_default" ]]; then
    kt_test_pass "OnException property defaults to empty"
else
    kt_test_fail "OnException property default unexpected: $on_exception_default"
fi
myapp.delete

kt_test_start "OnException property setter"
TCustomApplication.new myapp
myapp.property OnException = "mock_handler_function"
on_exception_set=$(myapp.OnException)
if [[ "$on_exception_set" == "mock_handler_function" ]]; then
    kt_test_pass "OnException property setter works"
else
    kt_test_fail "OnException property setter failed: got '$on_exception_set'"
fi
myapp.delete

kt_test_start "HandleException calls the OnException handler exactly once"
TCustomApplication.new myapp
myapp.property StopOnException = "false"
myapp.property OnException = "mock_handler_function"
HANDLER_CALLS=0
myapp.HandleException "test_sender" "test_exception" 2>"$ERRF"
err="$(<"$ERRF")"
if [[ "$HANDLER_CALLS" == "1" && -z "$err" ]]; then
    kt_test_pass "the handler ran and ShowException did not"
else
    kt_test_fail "handler dispatch: calls=$HANDLER_CALLS stderr='$err'"
fi
myapp.delete

kt_test_start "HandleException without OnException falls back to ShowException"
TCustomApplication.new myapp
myapp.property StopOnException = "false"
HANDLER_CALLS=0
myapp.HandleException "test_sender" "no handler" 2>"$ERRF"
err="$(<"$ERRF")"
if [[ "$HANDLER_CALLS" == "0" && "$err" == "Exception: no handler" ]]; then
    kt_test_pass "the default path is ShowException"
else
    kt_test_fail "default path: calls=$HANDLER_CALLS stderr='$err'"
fi
myapp.delete

kt_test_start "OnException containing spaces is not executed [TCA-20]"
TCustomApplication.new myapp
myapp.property StopOnException = "false"
myapp.property OnException = "my handler"
myapp.HandleException "sender" "boom" 2>"$ERRF"
rc=$?
err="$(<"$ERRF")"
# The old build ran `my handler sender boom` and the shell answered
# "my: command not found"; now the value is rejected and ShowException runs.
if [[ $rc -eq 0 && "$err" == "Exception: boom" ]]; then
    kt_test_pass "the invalid handler name is ignored, ShowException takes over"
else
    kt_test_fail "invalid handler name: rc=$rc stderr='$err'"
fi
myapp.delete

kt_test_start "OnException naming a non-existent function is not executed [TCA-20]"
TCustomApplication.new myapp
myapp.property StopOnException = "false"
myapp.property OnException = "no_such_handler_12345"
myapp.HandleException "sender" "boom2" 2>"$ERRF"
rc=$?
err="$(<"$ERRF")"
if [[ $rc -eq 0 && "$err" == "Exception: boom2" ]]; then
    kt_test_pass "an undefined function name falls back to ShowException"
else
    kt_test_fail "undefined handler: rc=$rc stderr='$err'"
fi
myapp.delete

kt_test_start "an invalid OnException is reported under VERBOSE_KKLASS=debug"
TCustomApplication.new myapp
myapp.property StopOnException = "false"
myapp.property OnException = "my handler"
VERBOSE_KKLASS=debug myapp.HandleException "sender" "boom3" 2>"$ERRF"
err="$(<"$ERRF")"
if [[ "$err" == *"is not a function"* && "$err" == *"Exception: boom3"* ]]; then
    kt_test_pass "the diagnostic appears only under the debug switch"
else
    kt_test_fail "debug diagnostic missing: '$err'"
fi
myapp.delete

kt_test_start "a valid handler prevents termination when StopOnException is false"
TCustomApplication.new myapp
myapp.property StopOnException = "false"
myapp.property OnException = "mock_handler_function"
terminated_before=$(myapp.Terminated)
myapp.HandleException "sender" "exception_with_handler" 2>"$ERRF"
terminated_after=$(myapp.Terminated)
if [[ "$terminated_before" == "false" && "$terminated_after" == "false" ]]; then
    kt_test_pass "OnException handler integration works"
else
    kt_test_fail "OnException handler integration failed: before=$terminated_before after=$terminated_after"
fi
myapp.delete

rm -rf "$TMPD"

kt_test_log "009_OnExceptionProperty.sh completed"
