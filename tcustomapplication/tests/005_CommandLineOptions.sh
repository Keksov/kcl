#!/bin/bash
# 005_CommandLineOptions.sh - Test TCustomApplication command-line option methods

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

# Source tcustomapplication module
TCUSTOMAPPLICATION_DIR="$SCRIPT_DIR/.."
source "$TCUSTOMAPPLICATION_DIR/tcustomapplication.sh"

# Extract test name from filename
TEST_NAME="$(basename "$0" .sh)"
kt_test_init "$TEST_NAME" "$SCRIPT_DIR" "$@"

# ---------------------------------------------------------------------------
# FPC 3.2.2 custapp semantics (decision D4, phase P4). Argument indices are
# ParamStr indices: Params[0] is the executable name, so the first argument is
# index 1, and FindOptionIndex scans DOWNWARD (the LAST occurrence wins, R10).
# ---------------------------------------------------------------------------
eq() {   # LABEL ACTUAL EXPECTED
    if [[ "$2" == "$3" ]]; then
        kt_test_pass "$1"
    else
        kt_test_fail "$1: got '$2', expected '$3'"
    fi
}

kt_test_section "005: TCustomApplication Command Line Options"

kt_test_start "FindOptionIndex with short option [TCA-03]"
TCustomApplication.new myapp
myapp.SetArgs -v file.txt --verbose
myapp.FindOptionIndex "v" ""
eq "FindOptionIndex v (Params[1] is the first argument)" "$RESULT" "1"
myapp.delete

kt_test_start "FindOptionIndex with long option [TCA-03]"
TCustomApplication.new myapp
myapp.SetArgs -h file.txt --verbose data.txt
myapp.FindOptionIndex "" "verbose"
eq "FindOptionIndex --verbose" "$RESULT" "3"
myapp.delete

kt_test_start "FindOptionIndex scans downward: last occurrence wins [TCA-17, R10]"
TCustomApplication.new myapp
myapp.SetArgs -v file.txt -v data.txt
myapp.FindOptionIndex "v" ""
last_idx=$RESULT
myapp.FindOptionIndex "v" "" 2
below_idx=$RESULT
myapp.FindOptionIndex "v" "" 1
first_idx=$RESULT
myapp.FindOptionIndex "v" "" 0
none_idx=$RESULT
if [[ "$last_idx" == "3" && "$below_idx" == "1" && "$first_idx" == "1" && "$none_idx" == "-1" ]]; then
    kt_test_pass "default -1 -> 3, StartAt 2 -> 1, StartAt 1 -> 1, StartAt 0 -> -1"
else
    kt_test_fail "downward scan wrong: default=$last_idx at2=$below_idx at1=$first_idx at0=$none_idx (expected 3/1/1/-1)"
fi
myapp.delete

kt_test_start "FindOptionIndex returns -1 for non-existent option"
TCustomApplication.new myapp
myapp.SetArgs file.txt data.txt
myapp.FindOptionIndex "x" ""
eq "FindOptionIndex x" "$RESULT" "-1"
myapp.delete

kt_test_start "FindOptionIndex rejects a non-numeric StartAt [TCA-05, D1]"
TCustomApplication.new myapp
myapp.SetArgs -v file.txt
RESULT="untouched"
if myapp.FindOptionIndex "v" "" "abc"; then
    kt_test_fail "a non-numeric StartAt was accepted (RESULT='$RESULT')"
else
    eq "rc 1 and RESULT cleared" "$RESULT" ""
fi
myapp.delete

kt_test_start "GetOptionValue with short option"
TCustomApplication.new myapp
myapp.SetArgs -c config.ini file.txt
myapp.GetOptionValue "c" ""
eq "GetOptionValue -c" "$RESULT" "config.ini"
myapp.delete

kt_test_start "GetOptionValue long option: only --name=value carries a value [TCA-01]"
TCustomApplication.new myapp
myapp.SetArgs file.txt --config data.ini
myapp.GetOptionValue "" "config"
spaced=$RESULT
myapp.SetArgs file.txt --config=data.ini
myapp.GetOptionValue "" "config"
equalled=$RESULT
if [[ -z "$spaced" && "$equalled" == "data.ini" ]]; then
    kt_test_pass "long value only via '=' (FPC GetOptionAtIndex)"
else
    kt_test_fail "long option value wrong: spaced='$spaced' (expected empty), equals='$equalled' (expected data.ini)"
fi
myapp.delete

kt_test_start "GetOptionValue with char and string"
TCustomApplication.new myapp
myapp.SetArgs -c test.conf file.txt
myapp.GetOptionValue "c" "config"
eq "GetOptionValue -c/--config" "$RESULT" "test.conf"
myapp.delete

kt_test_start "GetOptionValue returns empty for option without value"
TCustomApplication.new myapp
myapp.SetArgs -v -h file.txt
myapp.GetOptionValue "v" ""
eq "next argument is another option" "$RESULT" ""
myapp.delete

kt_test_start "GetOptionAtIndex extracts the value for a known index [D4]"
TCustomApplication.new myapp
myapp.SetArgs -c config.ini --long=v1 --long
myapp.GetOptionAtIndex 1 false
short_val=$RESULT
myapp.GetOptionAtIndex 3 true
long_val=$RESULT
myapp.GetOptionAtIndex 4 true
bare_val=$RESULT
myapp.GetOptionAtIndex -1 false
none_val=$RESULT
if [[ "$short_val" == "config.ini" && "$long_val" == "v1" && -z "$bare_val" && -z "$none_val" ]]; then
    kt_test_pass "short=config.ini long=v1, a bare long option and index -1 give empty"
else
    kt_test_fail "GetOptionAtIndex wrong: short='$short_val' long='$long_val' bare='$bare_val' none='$none_val'"
fi
myapp.delete

kt_test_start "HasOption answers with the exit status [kcl README 1.3, R8]"
TCustomApplication.new myapp
myapp.SetArgs -v file.txt
if myapp.HasOption "v" ""; then
    eq "rc 0 and RESULT=true for -v" "$RESULT" "true"
else
    kt_test_fail "HasOption v returned rc 1 for '-v file.txt'"
fi
myapp.delete

kt_test_start "HasOption finds long option"
TCustomApplication.new myapp
myapp.SetArgs file.txt --verbose data.txt
if myapp.HasOption "" "verbose"; then
    eq "rc 0 and RESULT=true for --verbose" "$RESULT" "true"
else
    kt_test_fail "HasOption --verbose returned rc 1"
fi
myapp.delete

kt_test_start "HasOption returns rc 1 for non-existent option"
TCustomApplication.new myapp
myapp.SetArgs file.txt data.txt
if myapp.HasOption "x" ""; then
    kt_test_fail "HasOption x returned rc 0 with no -x present"
else
    eq "rc 1 and RESULT=false" "$RESULT" "false"
fi
myapp.delete

kt_test_start "HasOption with char and string"
TCustomApplication.new myapp
myapp.SetArgs -v file.txt
if myapp.HasOption "v" "verbose"; then
    eq "rc 0 and RESULT=true" "$RESULT" "true"
else
    kt_test_fail "HasOption v/verbose returned rc 1"
fi
myapp.delete

kt_test_start "CheckOptions with valid simple options"
TCustomApplication.new myapp
myapp.SetArgs -h -v file.txt
myapp.CheckOptions "hv" "" "" "" "false"
eq "no error for -h -v file.txt against 'hv'" "$RESULT" ""
myapp.delete

kt_test_start "CheckOptions rejects an invalid option with FPC text [TCA-18]"
TCustomApplication.new myapp
myapp.SetArgs -x invalid file.txt
myapp.CheckOptions "hv" "" "" "" "false"
eq "SErrInvalidOption" "$RESULT" 'Invalid option at position 1: "x"'
myapp.delete

kt_test_start "CheckOptions: x: needs an argument, x:: does not [TCA-02]"
TCustomApplication.new myapp
myapp.SetArgs -c
myapp.CheckOptions "c:" ""
required=$RESULT
myapp.CheckOptions "c::" ""
optional=$RESULT
myapp.SetArgs -c cfg.ini
myapp.CheckOptions "c:" ""
supplied=$RESULT
if [[ "$required" == "Option at position 1 needs an argument : c" && -z "$optional" && -z "$supplied" ]]; then
    kt_test_pass "SErrOptionNeeded for a lone -c, silence for c:: and for '-c cfg.ini'"
else
    kt_test_fail "colon handling wrong: required='$required' optional='$optional' supplied='$supplied'"
fi
myapp.delete

kt_test_start "CheckOptions: a value-taking option must be last in a cluster [TCA-02]"
TCustomApplication.new myapp
myapp.SetArgs -cv x
myapp.CheckOptions "c:v" ""
bad_cluster=$RESULT
myapp.SetArgs -vc x
myapp.CheckOptions "c:v" ""
good_cluster=$RESULT
if [[ "$bad_cluster" == "Option at position 1 needs an argument : c" && -z "$good_cluster" ]]; then
    kt_test_pass "'-cv x' errors, '-vc x' is accepted"
else
    kt_test_fail "cluster rule wrong: '-cv x'='$bad_cluster', '-vc x'='$good_cluster'"
fi
myapp.delete

kt_test_start "CheckOptions consumes a short option value [TCA-02]"
TCustomApplication.new myapp
myapp.SetArgs -c cfg.ini -v tail.txt
declare -a opts_out=() non_out=()
myapp.CheckOptions "c:v" "" opts_out non_out
err=$RESULT
if [[ -z "$err" && "${opts_out[*]}" == "c=cfg.ini" && "${non_out[*]}" == "tail.txt" ]]; then
    kt_test_pass "cfg.ini consumed by -c, only tail.txt is a non-option"
else
    kt_test_fail "consumption wrong: err='$err' opts='${opts_out[*]:-}' non='${non_out[*]:-}'"
fi
myapp.delete

kt_test_start "CheckOptions long options: = value, : and :: [TCA-01, TCA-02]"
TCustomApplication.new myapp
myapp.SetArgs --config=data.ini
myapp.CheckOptions "" "config:"
with_value=$RESULT
myapp.CheckOptions "" "config"
switch_only=$RESULT
myapp.SetArgs --config
myapp.CheckOptions "" "config:"
missing=$RESULT
myapp.CheckOptions "" "config::"
opt_missing=$RESULT
if [[ -z "$with_value" && "$switch_only" == "Option at position 1 does not allow an argument: config" && "$missing" == "Option at position 1 needs an argument : config" && -z "$opt_missing" ]]; then
    kt_test_pass "SErrNoOptionAllowed / SErrOptionNeeded / :: is silent"
else
    kt_test_fail "long colon handling wrong: value='$with_value' switch='$switch_only' missing='$missing' optional='$opt_missing'"
fi
myapp.delete

kt_test_start "CheckOptions AllErrors joins every message with a newline [TCA-09]"
TCustomApplication.new myapp
myapp.SetArgs -x -y
myapp.CheckOptions "v" "" "false"
first_only=$RESULT
myapp.CheckOptions "v" "" "true"
all_errors=$RESULT
expected=$'Invalid option at position 1: "x"\nInvalid option at position 2: "y"'
if [[ "$first_only" == 'Invalid option at position 1: "x"' && "$all_errors" == "$expected" ]]; then
    kt_test_pass "one message without AllErrors, both joined by a newline with it"
else
    kt_test_fail "AllErrors wrong: first='$first_only' all='$all_errors'"
fi
myapp.delete

kt_test_start "CheckOptions: a lone dash and a mid-argv double dash are invalid [TCA-13]"
TCustomApplication.new myapp
myapp.SetArgs - -- x
declare -a dash_opts=() dash_non=()
myapp.CheckOptions "v" "" dash_opts dash_non "true"
err=$RESULT
expected=$'Invalid option at position 1: "-"\nInvalid option at position 2: ""'
if [[ "$err" == "$expected" && "${dash_non[*]}" == "x" ]]; then
    kt_test_pass "both rejected, only x is a non-option"
else
    kt_test_fail "dash handling wrong: err='$err' non='${dash_non[*]:-}'"
fi
myapp.delete

kt_test_start "CheckOptions ignores case when CaseSensitiveOptions is false [TCA-06]"
TCustomApplication.new myapp
myapp.property CaseSensitiveOptions = "false"
myapp.SetArgs -V file --Verbose x
myapp.CheckOptions "v" "verbose"
insensitive=$RESULT
if myapp.HasOption "v" ""; then has_v=yes; else has_v=no; fi
if myapp.HasOption "" "verbose"; then has_long=yes; else has_long=no; fi
myapp.property CaseSensitiveOptions = "true"
myapp.CheckOptions "v" "verbose"
sensitive=$RESULT
if [[ -z "$insensitive" && "$has_v" == "yes" && "$has_long" == "yes" && -n "$sensitive" ]]; then
    kt_test_pass "-V/--Verbose accepted when case is ignored, rejected when it is not"
else
    kt_test_fail "case folding wrong: insensitive='$insensitive' has_v=$has_v has_long=$has_long sensitive='$sensitive'"
fi
myapp.delete

kt_test_start "CheckOptions rejects a reserved output-array name [kcl README 1.7]"
TCustomApplication.new myapp
myapp.SetArgs -v
myapp.CheckOptions "v" "" RESULT non_out
rc=$?
eq "rc 2 for an output array named RESULT" "$rc" "2"
myapp.delete

kt_test_log "005_CommandLineOptions.sh completed"
