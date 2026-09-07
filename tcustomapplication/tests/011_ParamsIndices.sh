#!/bin/bash
# 011_ParamsIndices.sh - Params[Index] over the stored argv.
#
# Every test here used to be wrapped in `if [[ $param_count -gt N ]]`, and
# ParamCount always answered 0 (finding TCA-03), so the real branch never ran.
# The application now gets a command line through SetArgs and the indices are
# FPC's ParamStr indices: 0 = executable name, 1..ParamCount = arguments.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

# Source tcustomapplication module
TCUSTOMAPPLICATION_DIR="$SCRIPT_DIR/.."
source "$TCUSTOMAPPLICATION_DIR/tcustomapplication.sh"

# Extract test name from filename
TEST_NAME="$(basename "$0" .sh)"
kt_test_init "$TEST_NAME" "$SCRIPT_DIR" "$@"

eq() {   # LABEL ACTUAL EXPECTED
    if [[ "$2" == "$3" ]]; then
        kt_test_pass "$1"
    else
        kt_test_fail "$1: got '$2', expected '$3'"
    fi
}

kt_test_section "011: TCustomApplication Params Property with Multiple Indices"

kt_test_start "Params with index 0 is the executable name"
TCustomApplication.new myapp
myapp.SetArgs alpha beta gamma
myapp.Params 0
p0=$RESULT
myapp.ExeName
exe=$RESULT
if [[ -n "$p0" && "$p0" == "$exe" ]]; then
    kt_test_pass "Params[0] == ExeName == $p0"
else
    kt_test_fail "Params[0]='$p0', ExeName='$exe'"
fi
myapp.delete

kt_test_start "Params with indices 1..3 are the arguments"
TCustomApplication.new myapp
myapp.SetArgs alpha beta gamma
myapp.ParamCount
count=$RESULT
myapp.Params 1
p1=$RESULT
myapp.Params 2
p2=$RESULT
myapp.Params 3
p3=$RESULT
if [[ "$count" == "3" && "$p1" == "alpha" && "$p2" == "beta" && "$p3" == "gamma" ]]; then
    kt_test_pass "ParamCount 3 and Params 1..3 in order"
else
    kt_test_fail "count=$count params=($p1 $p2 $p3)"
fi
myapp.delete

kt_test_start "Params preserves values that look like options and like echo flags"
TCustomApplication.new myapp
myapp.SetArgs -n -e '-neE' $'multi\nline' 'with spaces'
myapp.Params 1
p1=$RESULT
myapp.Params 3
p3=$RESULT
myapp.Params 4
p4=$RESULT
myapp.Params 5
p5=$RESULT
if [[ "$p1" == "-n" && "$p3" == "-neE" && "$p4" == $'multi\nline' && "$p5" == "with spaces" ]]; then
    kt_test_pass "values round-trip verbatim (printf, not echo)"
else
    kt_test_fail "Params round-trip: 1='$p1' 3='$p3' 4='$p4' 5='$p5'"
fi
myapp.delete

kt_test_start "Params with a negative index returns empty"
TCustomApplication.new myapp
myapp.SetArgs alpha beta
myapp.Params -1
eq "Params -1" "$RESULT" ""
myapp.delete

kt_test_start "Params one past the end returns empty"
TCustomApplication.new myapp
myapp.SetArgs alpha beta
myapp.ParamCount
count=$RESULT
myapp.Params $(( count + 1 ))
eq "Params ParamCount+1" "$RESULT" ""
myapp.delete

kt_test_start "Params with a large index returns empty"
TCustomApplication.new myapp
myapp.SetArgs alpha beta
myapp.Params 100
eq "Params 100" "$RESULT" ""
myapp.delete

kt_test_start "Params rejects a non-numeric index [TCA-05, D1]"
TCustomApplication.new myapp
myapp.SetArgs alpha beta
canary="$SCRIPT_DIR/.tmp_params_canary"
rm -f "$canary"
accepted=""
for bad in "abc" "1.5" "x[\$(touch '$canary')]" ""; do
    RESULT="untouched"
    if myapp.Params "$bad" 2>/dev/null; then
        accepted+="[$bad] "
    elif [[ -n "$RESULT" ]]; then
        accepted+="[$bad RESULT=$RESULT] "
    fi
done
if [[ -z "$accepted" && ! -e "$canary" ]]; then
    kt_test_pass "rc 1 for every malformed index, nothing executed"
else
    kt_test_fail "accepted: ${accepted:-none}; canary=$([[ -e "$canary" ]] && echo CREATED || echo absent)"
fi
rm -f "$canary"
myapp.delete

kt_test_start "walking Params 1..ParamCount reproduces the argument list"
TCustomApplication.new myapp
myapp.SetArgs one two three four
myapp.ParamCount
count=$RESULT
results=""
for ((i = 1; i <= count; i++)); do
    myapp.Params "$i"
    results+="${results:+ }$RESULT"
done
if [[ "$count" == "4" && "$results" == "one two three four" ]]; then
    kt_test_pass "Multiple Params calls work: $results"
else
    kt_test_fail "walk failed: count=$count results='$results'"
fi
myapp.delete

kt_test_log "011_ParamsIndices.sh completed"
