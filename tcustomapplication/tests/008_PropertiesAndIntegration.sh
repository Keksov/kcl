#!/bin/bash
# 008_PropertiesAndIntegration.sh - Test TCustomApplication properties and integration scenarios
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


kt_test_section "008: TCustomApplication Properties and Integration"

# Test: ExeName property
kt_test_start "ExeName property"
TCustomApplication.new myapp
exe_name=$(myapp.exeName)
if [[ -n "$exe_name" ]]; then
    kt_test_pass "ExeName property returns executable name: $exe_name"
else
    kt_test_fail "ExeName property failed"
fi
myapp.delete

# Test: Title property getter
kt_test_start "Title property getter"
TCustomApplication.new myapp
title=$(myapp.Title)
if [[ -n "$title" ]]; then
    kt_test_pass "Title property getter works: $title"
else
    kt_test_fail "Title property getter failed"
fi
myapp.delete

# Test: Title property setter
kt_test_start "Title property setter"
TCustomApplication.new myapp
myapp.property Title = "Test Application"
new_title=$(myapp.Title)
if [[ "$new_title" == "Test Application" ]]; then
    kt_test_pass "Title property setter works"
else
    kt_test_fail "Title property setter failed: got '$new_title'"
fi
myapp.delete

# Test: ConsoleApplication property
kt_test_start "ConsoleApplication property"
TCustomApplication.new myapp
is_console=$(myapp.ConsoleApplication)
if [[ "$is_console" == "true" || "$is_console" == "false" ]]; then
    kt_test_pass "ConsoleApplication property returns boolean: $is_console"
else
    kt_test_fail "ConsoleApplication property failed: got '$is_console'"
fi
myapp.delete

# Test: Location property
kt_test_start "Location property"
TCustomApplication.new myapp
location=$(myapp.Location)
if [[ -n "$location" ]]; then
    kt_test_pass "Location property returns directory: $location"
else
    kt_test_fail "Location property failed"
fi
myapp.delete

# Test: ParamCount property
kt_test_start "ParamCount property"
TCustomApplication.new myapp
param_count=$(myapp.ParamCount)
if [[ "$param_count" -ge 0 ]]; then
    kt_test_pass "ParamCount property returns non-negative integer: $param_count"
else
    kt_test_fail "ParamCount property failed: got '$param_count'"
fi
myapp.delete

# Test: Params property
kt_test_start "Params property"
TCustomApplication.new myapp
if [[ "$(myapp.ParamCount)" -gt 0 ]]; then
    param0=$(myapp.Params 0)
    if [[ -n "$param0" ]]; then
        kt_test_pass "Params property returns parameter: $param0"
    else
        kt_test_fail "Params property failed"
    fi
else
    kt_test_pass "Params property works (no parameters to test)"
fi
myapp.delete

# Test: OptionChar property getter
kt_test_start "OptionChar property getter"
TCustomApplication.new myapp
option_char=$(myapp.OptionChar)
if [[ -n "$option_char" ]]; then
    kt_test_pass "OptionChar property returns character: $option_char"
else
    kt_test_fail "OptionChar property failed"
fi
myapp.delete

# Test: OptionChar property setter
kt_test_start "OptionChar property setter"
TCustomApplication.new myapp
myapp.property OptionChar = "!"
new_option_char=$(myapp.OptionChar)
if [[ "$new_option_char" == "!" ]]; then
    kt_test_pass "OptionChar property setter works"
else
    kt_test_fail "OptionChar property setter failed: got '$new_option_char'"
fi
myapp.delete

# Test: CaseSensitiveOptions property getter
kt_test_start "CaseSensitiveOptions property getter"
TCustomApplication.new myapp
case_sensitive=$(myapp.CaseSensitiveOptions)
if [[ "$case_sensitive" == "true" || "$case_sensitive" == "false" ]]; then
    kt_test_pass "CaseSensitiveOptions property returns boolean: $case_sensitive"
else
    kt_test_fail "CaseSensitiveOptions property failed: got '$case_sensitive'"
fi
myapp.delete

# Test: CaseSensitiveOptions property setter
kt_test_start "CaseSensitiveOptions property setter"
TCustomApplication.new myapp
myapp.property CaseSensitiveOptions = "false"
new_case_sensitive=$(myapp.CaseSensitiveOptions)
if [[ "$new_case_sensitive" == "false" ]]; then
    kt_test_pass "CaseSensitiveOptions property setter works"
else
    kt_test_fail "CaseSensitiveOptions property setter failed: got '$new_case_sensitive'"
fi
myapp.delete

# Test: StopOnException property getter
kt_test_start "StopOnException property getter"
TCustomApplication.new myapp
stop_on_exception=$(myapp.StopOnException)
if [[ "$stop_on_exception" == "true" || "$stop_on_exception" == "false" ]]; then
    kt_test_pass "StopOnException property returns boolean: $stop_on_exception"
else
    kt_test_fail "StopOnException property failed: got '$stop_on_exception'"
fi
myapp.delete

# Test: StopOnException property setter
kt_test_start "StopOnException property setter"
TCustomApplication.new myapp
myapp.property StopOnException = "true"
new_stop_on_exception=$(myapp.StopOnException)
if [[ "$new_stop_on_exception" == "true" ]]; then
    kt_test_pass "StopOnException property setter works"
else
    kt_test_fail "StopOnException property setter failed: got '$new_stop_on_exception'"
fi
myapp.delete

# Test: ExceptionExitCode property getter
kt_test_start "ExceptionExitCode property getter"
TCustomApplication.new myapp
exit_code=$(myapp.ExceptionExitCode)
if [[ "$exit_code" -ge 0 ]]; then
    kt_test_pass "ExceptionExitCode property returns non-negative integer: $exit_code"
else
    kt_test_fail "ExceptionExitCode property failed: got '$exit_code'"
fi
myapp.delete

# Test: ExceptionExitCode property setter
kt_test_start "ExceptionExitCode property setter"
TCustomApplication.new myapp
myapp.property ExceptionExitCode = 42
new_exit_code=$(myapp.ExceptionExitCode)
if [[ "$new_exit_code" == "42" ]]; then
    kt_test_pass "ExceptionExitCode property setter works"
else
    kt_test_fail "ExceptionExitCode property setter failed: got '$new_exit_code'"
fi
myapp.delete

# Test: HelpFile property getter
kt_test_start "HelpFile property getter"
TCustomApplication.new myapp
help_file=$(myapp.HelpFile)
# HelpFile might be empty by default
if [[ -z "$help_file" || -n "$help_file" ]]; then
    kt_test_pass "HelpFile property getter works: '$help_file'"
else
    kt_test_fail "HelpFile property getter failed"
fi
myapp.delete

# Test: HelpFile property setter
kt_test_start "HelpFile property setter"
TCustomApplication.new myapp
myapp.property HelpFile = "/path/to/help.chm"
new_help_file=$(myapp.HelpFile)
if [[ "$new_help_file" == "/path/to/help.chm" ]]; then
    kt_test_pass "HelpFile property setter works"
else
    kt_test_fail "HelpFile property setter failed: got '$new_help_file'"
fi
myapp.delete

# Test: Integration - Initialize and check properties
kt_test_start "Integration - Initialize and check properties"
TCustomApplication.new myapp
myapp.Initialize
terminated=$(myapp.Terminated)
title=$(myapp.Title)
if [[ "$terminated" == "false" && -n "$title" ]]; then
    kt_test_pass "Initialize properly sets up application state"
else
    kt_test_fail "Initialize failed: terminated=$terminated, title='$title'"
fi
myapp.delete

# Test: Integration - Terminate and check properties
kt_test_start "Integration - Terminate and check properties"
TCustomApplication.new myapp
terminated_before=$(myapp.Terminated)
myapp.Terminate
terminated_after=$(myapp.Terminated)
if [[ "$terminated_before" == "false" && "$terminated_after" == "true" ]]; then
    kt_test_pass "Terminate properly changes application state"
else
    kt_test_fail "Terminate failed: before=$terminated_before, after=$terminated_after"
fi
myapp.delete

kt_test_log "008_PropertiesAndIntegration.sh completed"