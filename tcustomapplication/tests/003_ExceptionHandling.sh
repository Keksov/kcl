#!/bin/bash
# 003_ExceptionHandling.sh - HandleException / ShowException.
#
# The old version asserted `$? -eq 0` after every call, which every possible
# implementation satisfies (REVIEW.md section 3). These assert on what the two
# members actually do: the message on stderr, the handler that was called and
# the Terminated / EXITCODE state afterwards.

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

# A handler that records what it was given. It must NOT be run through $( ),
# or the record would be lost with the subshell.
declare -g HANDLER_CALLS=0
declare -g HANDLER_SENDER=""
declare -g HANDLER_MSG=""
recording_handler() {
    HANDLER_CALLS=$(( HANDLER_CALLS + 1 ))
    HANDLER_SENDER="$1"
    HANDLER_MSG="$2"
    return 0
}

kt_test_section "003: TCustomApplication Exception Handling"

kt_test_start "ShowException writes the message to stderr, not stdout"
TCustomApplication.new myapp
out="$(myapp.ShowException "Test exception" 2>"$ERRF")"
err="$(<"$ERRF")"
if [[ -z "$out" && "$err" == "Exception: Test exception" ]]; then
    kt_test_pass "stdout is empty, stderr carries the message"
else
    kt_test_fail "ShowException: stdout='$out' stderr='$err'"
fi
myapp.delete

kt_test_start "ShowException with an empty message prints nothing"
TCustomApplication.new myapp
myapp.ShowException "" 2>"$ERRF"
rc=$?
err="$(<"$ERRF")"
if [[ $rc -eq 0 && -z "$err" ]]; then
    kt_test_pass "no output for an empty message"
else
    kt_test_fail "ShowException '': rc=$rc stderr='$err'"
fi
myapp.delete

kt_test_start "ShowException passes a long message through unchanged"
TCustomApplication.new myapp
long_msg='This is a very long exception message with numbers 1234567890, special chars !@#$%^&*() and "quotes".'
myapp.ShowException "$long_msg" 2>"$ERRF"
err="$(<"$ERRF")"
if [[ "$err" == "Exception: $long_msg" ]]; then
    kt_test_pass "the message is not reformatted or truncated"
else
    kt_test_fail "long message mangled: '$err'"
fi
myapp.delete

kt_test_start "HandleException without a handler calls ShowException"
TCustomApplication.new myapp
myapp.property StopOnException = "false"
myapp.HandleException "mock_sender" "no handler set" 2>"$ERRF"
err="$(<"$ERRF")"
terminated=$(myapp.Terminated)
if [[ "$err" == "Exception: no handler set" && "$terminated" == "false" ]]; then
    kt_test_pass "ShowException ran and StopOnException=false left the app running"
else
    kt_test_fail "HandleException default path: stderr='$err' terminated=$terminated"
fi
myapp.delete

kt_test_start "HandleException calls OnException instead of ShowException"
TCustomApplication.new myapp
myapp.property StopOnException = "false"
myapp.property OnException = "recording_handler"
HANDLER_CALLS=0
HANDLER_SENDER=""
HANDLER_MSG=""
myapp.HandleException "the_sender" "the message" 2>"$ERRF"
err="$(<"$ERRF")"
if [[ "$HANDLER_CALLS" == "1" && "$HANDLER_SENDER" == "the_sender" && "$HANDLER_MSG" == "the message" && -z "$err" ]]; then
    kt_test_pass "the handler received sender and message, ShowException stayed quiet"
else
    kt_test_fail "OnException path: calls=$HANDLER_CALLS sender='$HANDLER_SENDER' msg='$HANDLER_MSG' stderr='$err'"
fi
myapp.delete

kt_test_start "HandleException terminates when StopOnException is true"
TCustomApplication.new myapp
myapp.property StopOnException = "true"
myapp.property ExceptionExitCode = 3
terminated_before=$(myapp.Terminated)
myapp.HandleException "mock_sender" "fatal" 2>"$ERRF"
terminated_after=$(myapp.Terminated)
if [[ "$terminated_before" == "false" && "$terminated_after" == "true" && "${EXITCODE:-}" == "3" ]]; then
    kt_test_pass "Terminated flipped and ExceptionExitCode reached EXITCODE"
else
    kt_test_fail "termination: before=$terminated_before after=$terminated_after exitcode=${EXITCODE:-}"
fi
myapp.delete

kt_test_start "Multiple HandleException calls each reach the handler"
TCustomApplication.new myapp
myapp.property StopOnException = "false"
myapp.property OnException = "recording_handler"
HANDLER_CALLS=0
myapp.HandleException "sender1" "exception1" 2>"$ERRF"
myapp.HandleException "sender2" "exception2" 2>"$ERRF"
myapp.HandleException "sender3" "exception3" 2>"$ERRF"
if [[ "$HANDLER_CALLS" == "3" && "$HANDLER_MSG" == "exception3" ]]; then
    kt_test_pass "three calls, the last message recorded"
else
    kt_test_fail "multiple calls: calls=$HANDLER_CALLS last='$HANDLER_MSG'"
fi
myapp.delete

rm -rf "$TMPD"

kt_test_log "003_ExceptionHandling.sh completed"
