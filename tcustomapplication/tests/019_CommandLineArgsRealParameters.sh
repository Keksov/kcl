#!/bin/bash
# 019_CommandLineArgsRealParameters.sh - a real script's own command line.
#
# The old version of this file wrote its helper apps into /tmp and guessed the
# repository path from the current directory; it also relied on the removed
# "auto-initialize from the method's parameters" behaviour (finding TCA-04).
# Helpers now live under the suite's temp dir and hand `"$@"` to SetArgs, which
# is the documented way to give an application its command line.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

TCUSTOMAPPLICATION_DIR="$SCRIPT_DIR/.."
source "$TCUSTOMAPPLICATION_DIR/tcustomapplication.sh"

TEST_NAME="$(basename "$0" .sh)"
kt_test_init "$TEST_NAME" "$SCRIPT_DIR" "$@"

# A directory of our own: the ktests fixture temp dir is named after $0, which
# is "bash" for every file the runner starts, and the runner runs files in
# parallel — a neighbour's teardown would delete our helper scripts.
TMPD="$SCRIPT_DIR/.tmp/$(basename "${BASH_SOURCE[0]}" .sh)"
mkdir -p "$TMPD"
UNIT="$TCUSTOMAPPLICATION_DIR/tcustomapplication.sh"

# An application that validates its own command line and prints the message.
APP="$TMPD/checkopts_app.sh"
{
    printf '%s\n' '#!/bin/bash'
    printf 'source %q\n' "$UNIT"
    printf '%s\n' 'TCustomApplication.new app'
    printf '%s\n' 'app.SetArgs "$@"'
    printf '%s\n' 'app.CheckOptions "hv" "help version verbose" "false"'
    printf '%s\n' 'printf "%s" "$RESULT"'
    printf '%s\n' 'app.delete'
} > "$APP"
chmod +x "$APP"

kt_test_section "019: TCustomApplication Command-Line Arguments from Real Parameters"

expect_app() {   # LABEL EXPECTED ARGS...
    local label="$1" expected="$2"
    shift 2
    local out
    out="$(bash "$APP" "$@" 2>&1)"
    if [[ "$out" == "$expected" ]]; then
        kt_test_pass "$label"
    else
        kt_test_fail "$label: got '$out', expected '$expected'"
    fi
}

kt_test_start "Real parameters with valid short options"
expect_app "-h -v accepted" "" -h -v

kt_test_start "Real parameters with valid long options"
expect_app "--help --version accepted" "" --help --version

kt_test_start "Real parameters with mixed short and long options"
expect_app "-h --version accepted" "" -h --version

kt_test_start "Real parameters with file arguments"
expect_app "options plus file arguments accepted" "" -v file.txt data.txt

kt_test_start "Real parameters with invalid option detection"
expect_app "-x rejected with the FPC message" 'Invalid option at position 1: "x"' -x

kt_test_start "Real parameters with an invalid long option"
expect_app "--nope rejected with the FPC message" 'Invalid option at position 1: "nope"' --nope

kt_test_start "A script that never calls SetArgs has no arguments [TCA-04]"
NOARGS="$TMPD/noargs_app.sh"
{
    printf '%s\n' '#!/bin/bash'
    printf 'source %q\n' "$UNIT"
    printf '%s\n' 'TCustomApplication.new app'
    printf '%s\n' 'app.ParamCount; printf "%s|" "$RESULT"'
    printf '%s\n' 'app.CheckOptions "hv" "help" "false"; printf "%s|" "$RESULT"'
    printf '%s\n' 'app.GetNonOptions "hv" "help" nn; printf "%s" "$RESULT"'
    printf '%s\n' 'app.delete'
} > "$NOARGS"
out="$(bash "$NOARGS" -h ignored.txt --whatever 2>&1)"
if [[ "$out" == "0||0" ]]; then
    kt_test_pass "the real command line is NOT captured behind the caller's back"
else
    kt_test_fail "fresh application saw arguments: '$out' (expected '0||0')"
fi

kt_test_start "Constructor argument forwarding: Create \"\$@\" [TCA-04]"
CTOR="$TMPD/ctor_app.sh"
{
    printf '%s\n' '#!/bin/bash'
    printf 'source %q\n' "$UNIT"
    printf '%s\n' 'TCustomApplication.new app "$@"'
    printf '%s\n' 'app.ParamCount; printf "%s|" "$RESULT"'
    printf '%s\n' 'app.Params 1; printf "%s|" "$RESULT"'
    printf '%s\n' 'app.FindOptionIndex "" "help"; printf "%s" "$RESULT"'
    printf '%s\n' 'app.delete'
} > "$CTOR"
out="$(bash "$CTOR" --help -v file.txt 2>&1)"
if [[ "$out" == "3|--help|1" ]]; then
    kt_test_pass "TCustomApplication.new app \"\$@\" stores the real command line"
else
    kt_test_fail "constructor forwarding failed: '$out' (expected '3|--help|1')"
fi

kt_test_start "SetArgs preserves arguments across calls"
TCustomApplication.new app1
app1.SetArgs --verbose -h test.conf
app1.FindOptionIndex "" "verbose"
idx1=$RESULT
app1.FindOptionIndex "h" ""
idx2=$RESULT
app1.Params 3
p3=$RESULT
if [[ "$idx1" == "1" && "$idx2" == "2" && "$p3" == "test.conf" ]]; then
    kt_test_pass "SetArgs preserves arguments across multiple calls"
else
    kt_test_fail "SetArgs failed: verbose at $idx1 (expected 1), h at $idx2 (expected 2), Params 3='$p3'"
fi
app1.delete

rm -rf "$TMPD"

kt_test_log "019_CommandLineArgsRealParameters.sh completed"
