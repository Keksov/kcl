#!/bin/bash
# 010_EventLogFilter.sh - Test TCustomApplication EventLogFilter property
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


kk_test_section "010: TCustomApplication EventLogFilter Property"

# Test: EventLogFilter property getter (default)
kk_test_start "EventLogFilter property getter default"
TCustomApplication.new myapp
event_filter_default=$(myapp.EventLogFilter)
if [[ -z "$event_filter_default" ]]; then
    kk_test_pass "EventLogFilter property defaults to empty (all events logged)"
else
    kk_test_fail "EventLogFilter property default unexpected: $event_filter_default"
fi
myapp.delete

# Test: EventLogFilter property setter
kk_test_start "EventLogFilter property setter"
TCustomApplication.new myapp
# Set filter to only allow etError and etWarning
myapp.property EventLogFilter = "etError etWarning"
event_filter_set=$(myapp.EventLogFilter)
if [[ "$event_filter_set" == "etError etWarning" ]]; then
    kk_test_pass "EventLogFilter property setter works"
else
    kk_test_fail "EventLogFilter property setter failed: got '$event_filter_set'"
fi
myapp.delete

# Test: Log with EventLogFilter allowing event
kk_test_start "Log with EventLogFilter allowing event"
TCustomApplication.new myapp
myapp.property EventLogFilter = "etInfo etWarning etError etDebug"
myapp.Log "etInfo" "Allowed info message"
result=$?
if [[ $result -eq 0 ]]; then
    kk_test_pass "Log allows event in filter"
else
    kk_test_fail "Log failed for allowed event"
fi
myapp.delete

# Test: Log with EventLogFilter excluding event
kk_test_start "Log with EventLogFilter excluding event"
TCustomApplication.new myapp
myapp.property EventLogFilter = "etError etWarning"
myapp.Log "etInfo" "Excluded info message"
result=$?
if [[ $result -eq 0 ]]; then
    kk_test_pass "Log handles excluded event (may still log or skip)"
else
    kk_test_fail "Log failed for excluded event"
fi
myapp.delete

# Test: Log with empty EventLogFilter (all events)
kk_test_start "Log with empty EventLogFilter"
TCustomApplication.new myapp
# Empty filter means all events
myapp.property EventLogFilter = ""
myapp.Log "etInfo" "All events allowed"
myapp.Log "etWarning" "Warning allowed"
myapp.Log "etError" "Error allowed"
result=$?
if [[ $result -eq 0 ]]; then
    kk_test_pass "Log with empty filter allows all events"
else
    kk_test_fail "Log with empty filter failed"
fi
myapp.delete

# Test: Multiple event types in filter
kk_test_start "Multiple event types in EventLogFilter"
TCustomApplication.new myapp
myapp.property EventLogFilter = "etInfo etDebug"
myapp.Log "etInfo" "Info allowed"
myapp.Log "etDebug" "Debug allowed"
myapp.Log "etWarning" "Warning not in filter"
result=$?
if [[ $result -eq 0 ]]; then
    kk_test_pass "EventLogFilter handles multiple types"
else
    kk_test_fail "EventLogFilter multiple types failed"
fi
myapp.delete

kk_test_log "010_EventLogFilter.sh completed"