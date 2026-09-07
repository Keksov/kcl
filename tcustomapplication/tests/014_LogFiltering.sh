#!/bin/bash
# 014_LogFiltering.sh - Log with EventLogFilter, in the shapes a program uses.
#
# Like 010, but exercising a changing filter, formatted messages and long
# messages. The old version of this file asserted `$? -eq 0` after every call,
# so a Log that printed nothing at all would have passed.

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

start_log() { : > "$ERRF"; }
log_lines() {   # -> every line the app logged since start_log, joined by '|'
    local out="" line
    while IFS= read -r line; do
        out+="${out:+|}$line"
    done < "$ERRF"
    printf '%s' "$out"
}

kt_test_section "014: TCustomApplication Log with EventLogFilter"

kt_test_start "only the filtered types reach the log"
TCustomApplication.new myapp
myapp.property EventLogFilter = "etInfo etWarning"
start_log
myapp.Log "etInfo" "info logged" 2>>"$ERRF"
myapp.Log "etError" "error dropped" 2>>"$ERRF"
myapp.Log "etWarning" "warning logged" 2>>"$ERRF"
got="$(log_lines)"
if [[ "$got" == "etInfo: info logged|etWarning: warning logged" ]]; then
    kt_test_pass "two lines out of three"
else
    kt_test_fail "filtered log: '$got'"
fi
myapp.delete

kt_test_start "a filter naming one type drops all the others"
TCustomApplication.new myapp
myapp.property EventLogFilter = "etDebug"
start_log
myapp.Log "etInfo" "dropped" 2>>"$ERRF"
myapp.Log "etWarning" "dropped" 2>>"$ERRF"
myapp.Log "etError" "dropped" 2>>"$ERRF"
myapp.Log "etDebug" "kept" 2>>"$ERRF"
got="$(log_lines)"
if [[ "$got" == "etDebug: kept" ]]; then
    kt_test_pass "one line only"
else
    kt_test_fail "single-type filter: '$got'"
fi
myapp.delete

kt_test_start "an empty EventLogFilter logs all four types"
TCustomApplication.new myapp
myapp.property EventLogFilter = ""
start_log
myapp.Log "etInfo" "i" 2>>"$ERRF"
myapp.Log "etWarning" "w" 2>>"$ERRF"
myapp.Log "etError" "e" 2>>"$ERRF"
myapp.Log "etDebug" "d" 2>>"$ERRF"
got="$(log_lines)"
if [[ "$got" == "etInfo: i|etWarning: w|etError: e|etDebug: d" ]]; then
    kt_test_pass "four lines in order"
else
    kt_test_fail "empty filter: '$got'"
fi
myapp.delete

kt_test_start "changing EventLogFilter changes what is logged next"
TCustomApplication.new myapp
myapp.property EventLogFilter = "etInfo"
start_log
myapp.Log "etInfo" "before change" 2>>"$ERRF"
myapp.property EventLogFilter = "etWarning"
myapp.Log "etInfo" "after change" 2>>"$ERRF"
myapp.Log "etWarning" "warning" 2>>"$ERRF"
got="$(log_lines)"
if [[ "$got" == "etInfo: before change|etWarning: warning" ]]; then
    kt_test_pass "the filter is read on every call, not cached"
else
    kt_test_fail "changing filter: '$got'"
fi
myapp.delete

kt_test_start "formatted messages are filtered and formatted"
TCustomApplication.new myapp
myapp.property EventLogFilter = "etError etWarning"
start_log
myapp.Log "etError" "Error %s with code %d" "test" 42 2>>"$ERRF"
myapp.Log "etInfo" "Info %s - dropped" "filtered" 2>>"$ERRF"
myapp.Log "etWarning" "Warning %s occurred" "situation" 2>>"$ERRF"
got="$(log_lines)"
if [[ "$got" == "etError: Error test with code 42|etWarning: Warning situation occurred" ]]; then
    kt_test_pass "arguments substituted, the filtered line absent"
else
    kt_test_fail "formatted log: '$got'"
fi
myapp.delete

kt_test_start "a long message passes through the filter unchanged"
TCustomApplication.new myapp
myapp.property EventLogFilter = "etInfo"
long_msg='A long log message with numbers 1234567890, special chars !@#%^&*() and "quotes" in it.'
start_log
myapp.Log "etInfo" "%s" "$long_msg" 2>>"$ERRF"
myapp.Log "etWarning" "dropped" 2>>"$ERRF"
got="$(log_lines)"
if [[ "$got" == "etInfo: $long_msg" ]]; then
    kt_test_pass "the whole message survives, the filtered line is absent"
else
    kt_test_fail "long message: '$got'"
fi
myapp.delete

rm -rf "$TMPD"

kt_test_log "014_LogFiltering.sh completed"
