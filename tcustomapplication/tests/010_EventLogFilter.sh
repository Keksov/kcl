#!/bin/bash
# 010_EventLogFilter.sh - the EventLogFilter property and what it filters.
#
# FPC: `If (FEventLogFilter=[]) or (EventType in FEventLogFilter) then DoLog`.
# The filter is a SET, so membership is exact; the old build compared with
# `[[ $filter != *"$type"* ]]`, which let `etErr` through a filter of
# `etError` (finding TCA-16). The old tests only checked `$? -eq 0`.

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

logged() {   # INSTANCE TYPE MESSAGE -> the emitted line, or '' when filtered
    "$1".Log "$2" "$3" 2>"$ERRF"
    printf '%s' "$(<"$ERRF")"
}

kt_test_section "010: TCustomApplication EventLogFilter Property"

kt_test_start "EventLogFilter property getter default"
TCustomApplication.new myapp
event_filter_default=$(myapp.EventLogFilter)
if [[ -z "$event_filter_default" ]]; then
    kt_test_pass "EventLogFilter property defaults to empty (all events logged)"
else
    kt_test_fail "EventLogFilter property default unexpected: $event_filter_default"
fi
myapp.delete

kt_test_start "EventLogFilter property setter"
TCustomApplication.new myapp
myapp.property EventLogFilter = "etError etWarning"
event_filter_set=$(myapp.EventLogFilter)
if [[ "$event_filter_set" == "etError etWarning" ]]; then
    kt_test_pass "EventLogFilter property setter works"
else
    kt_test_fail "EventLogFilter property setter failed: got '$event_filter_set'"
fi
myapp.delete

kt_test_start "an event in the filter is logged"
TCustomApplication.new myapp
myapp.property EventLogFilter = "etInfo etWarning etError etDebug"
line="$(logged myapp etInfo "allowed info")"
if [[ "$line" == "etInfo: allowed info" ]]; then
    kt_test_pass "the event passes the filter and reaches stderr"
else
    kt_test_fail "allowed event was not logged: '$line'"
fi
myapp.delete

kt_test_start "an event NOT in the filter is dropped"
TCustomApplication.new myapp
myapp.property EventLogFilter = "etError etWarning"
line="$(logged myapp etInfo "excluded info")"
kept="$(logged myapp etError "kept error")"
if [[ -z "$line" && "$kept" == "etError: kept error" ]]; then
    kt_test_pass "etInfo produced nothing, etError still logged"
else
    kt_test_fail "filtering: excluded='$line' kept='$kept'"
fi
myapp.delete

kt_test_start "filter membership is exact, not a substring match [TCA-16]"
TCustomApplication.new myapp
myapp.property EventLogFilter = "etError"
partial="$(logged myapp etErr "substring of the filter")"
longer="$(logged myapp etErrorExtra "filter is a substring of this")"
exact="$(logged myapp etError "exact match")"
if [[ -z "$partial" && -z "$longer" && "$exact" == "etError: exact match" ]]; then
    kt_test_pass "etErr and etErrorExtra are dropped, etError passes"
else
    kt_test_fail "substring matching: etErr='$partial' etErrorExtra='$longer' etError='$exact'"
fi
myapp.delete

kt_test_start "an empty EventLogFilter logs every event"
TCustomApplication.new myapp
myapp.property EventLogFilter = ""
a="$(logged myapp etInfo "i")"
b="$(logged myapp etWarning "w")"
c="$(logged myapp etError "e")"
if [[ "$a" == "etInfo: i" && "$b" == "etWarning: w" && "$c" == "etError: e" ]]; then
    kt_test_pass "an empty filter is FPC's empty set: everything is logged"
else
    kt_test_fail "empty filter: '$a' / '$b' / '$c'"
fi
myapp.delete

kt_test_start "a comma-separated filter works like a space-separated one"
TCustomApplication.new myapp
myapp.property EventLogFilter = "etInfo,etDebug"
info="$(logged myapp etInfo "i")"
debug="$(logged myapp etDebug "d")"
warn="$(logged myapp etWarning "w")"
if [[ "$info" == "etInfo: i" && "$debug" == "etDebug: d" && -z "$warn" ]]; then
    kt_test_pass "EventLogFilter handles multiple types with either separator"
else
    kt_test_fail "comma filter: info='$info' debug='$debug' warning='$warn'"
fi
myapp.delete

rm -rf "$TMPD"

kt_test_log "010_EventLogFilter.sh completed"
