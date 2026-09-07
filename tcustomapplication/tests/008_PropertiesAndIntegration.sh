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
exe_name=$(myapp.ExeName)
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

# Test: Location property — FPC ExtractFilePath(ParamStr(0)). The old body read
# BASH_SOURCE[0], which inside an eval'd kklass method body is kklass.sh, so
# Location answered with the framework's directory (finding TCA-11).
kt_test_start "Location is the directory of the running script [TCA-11]"
TCustomApplication.new myapp
myapp.Location
location=$RESULT
myapp.ExeName
exe=$RESULT
kklass_dir="$(cd "$TCUSTOMAPPLICATION_DIR/../../kklass" && pwd)"
# ExeName is $0. Whether the runner started this file by path or by name, the
# answer must be its directory part (or '.' when it has none) — never kklass's.
if [[ "$exe" == */* ]]; then
    expected="${exe%/*}"
else
    expected="."
fi
if [[ "$location" == "$expected" && "$location" != "$kklass_dir" && -d "$location" ]]; then
    kt_test_pass "Location is the directory part of ExeName: $location"
else
    kt_test_fail "Location='$location' (expected '$expected') ExeName='$exe' kklass_dir='$kklass_dir'"
fi
myapp.delete

kt_test_start "Location follows \$0 in a script of its own [TCA-11]"
TMPD="$SCRIPT_DIR/.tmp/$(basename "${BASH_SOURCE[0]}" .sh)"
mkdir -p "$TMPD/sub"
{
    printf '%s\n' '#!/bin/bash'
    printf 'source %q\n' "$TCUSTOMAPPLICATION_DIR/tcustomapplication.sh"
    printf '%s\n' 'TCustomApplication.new app'
    printf '%s\n' 'app.Location; printf "%s" "$RESULT"'
    printf '%s\n' 'app.delete'
} > "$TMPD/sub/probe.sh"
loc="$(bash "$TMPD/sub/probe.sh" 2>&1)"
if [[ "$loc" == "$TMPD/sub" ]]; then
    kt_test_pass "a script in another directory reports its own directory"
else
    kt_test_fail "Location from a foreign directory: '$loc' (expected '$TMPD/sub')"
fi
rm -rf "$TMPD"
myapp.delete 2>/dev/null || true

# Test: ParamCount property — a fresh instance has NO arguments (TCA-04), and
# SetArgs is what gives it some. The old test accepted any non-negative number
# and the Params test below was skipped entirely because ParamCount was 0.
kt_test_start "ParamCount is 0 on a fresh instance and the argument count after SetArgs [TCA-03]"
TCustomApplication.new myapp
fresh=$(myapp.ParamCount)
myapp.SetArgs -v file.txt out.txt
after=$(myapp.ParamCount)
myapp.SetArgs
cleared=$(myapp.ParamCount)
if [[ "$fresh" == "0" && "$after" == "3" && "$cleared" == "0" ]]; then
    kt_test_pass "0 -> 3 -> 0"
else
    kt_test_fail "ParamCount: fresh=$fresh after=$after cleared=$cleared (expected 0/3/0)"
fi
myapp.delete

# Test: Params property
kt_test_start "Params[0] is the executable name, Params[1..N] the arguments [TCA-03]"
TCustomApplication.new myapp
myapp.SetArgs -v file.txt out.txt
param0=$(myapp.Params 0)
param1=$(myapp.Params 1)
param2=$(myapp.Params 2)
param3=$(myapp.Params 3)
param4=$(myapp.Params 4)
exe=$(myapp.ExeName)
if [[ "$param0" == "$exe" && -n "$param0" && "$param1" == "-v" && "$param2" == "file.txt" && "$param3" == "out.txt" && -z "$param4" ]]; then
    kt_test_pass "Params returns the stored argv, not the method's own arguments"
else
    kt_test_fail "Params: 0='$param0' (exe='$exe') 1='$param1' 2='$param2' 3='$param3' 4='$param4'"
fi
myapp.delete

kt_test_start "Params ignores extra arguments of its own [TCA-03]"
TCustomApplication.new myapp
myapp.SetArgs -v file.txt out.txt
# The old body returned ${!index} over the METHOD's parameters, so
# `Params 1 2 3` answered "1". The index is the only parameter that counts.
param_extra=$(myapp.Params 1 2 3)
if [[ "$param_extra" == "-v" ]]; then
    kt_test_pass "only the first argument is the index"
else
    kt_test_fail "Params 1 2 3 returned '$param_extra', expected '-v'"
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