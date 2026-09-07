#!/bin/bash
# 007_EnvironmentAndLogging.sh - GetEnvironmentList / EnvironmentVariable / Log.
#
# The old version asserted `$? -eq 0` after every call, so nothing here could
# fail. These check the three findings the review named:
#   TCA-15  GetEnvironmentList used `env | sort`, and a value containing a
#           newline became several bogus entries;
#   TCA-16  Log ignored its format arguments, matched the filter as a substring
#           and wrote to stdout;
#   TCA-05  EnvironmentVariable expanded ${!name} without validating the name.

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

kt_test_section "007: TCustomApplication Environment and Logging"

kt_test_start "GetEnvironmentList returns NAME=VALUE entries and their count"
TCustomApplication.new myapp
export TCA_ENV_PROBE="probe value"
declare -a env_list=()
myapp.GetEnvironmentList env_list "false"
count=$RESULT
found=""
for e in "${env_list[@]}"; do
    [[ "$e" == "TCA_ENV_PROBE=probe value" ]] && found=yes
done
if [[ "$count" == "${#env_list[@]}" && "$count" -gt 0 && "$found" == "yes" ]]; then
    kt_test_pass "$count entries, the probe among them with its value"
else
    kt_test_fail "GetEnvironmentList: RESULT=$count array=${#env_list[@]} probe found='$found'"
fi
myapp.delete

kt_test_start "GetEnvironmentList names only"
TCustomApplication.new myapp
declare -a env_names=()
myapp.GetEnvironmentList env_names "true"
count=$RESULT
found=""
has_value=""
for e in "${env_names[@]}"; do
    [[ "$e" == "TCA_ENV_PROBE" ]] && found=yes
    [[ "$e" == *=* ]] && has_value=yes
done
if [[ "$count" -gt 0 && "$found" == "yes" && -z "$has_value" ]]; then
    kt_test_pass "$count names, none of them carrying a value"
else
    kt_test_fail "names only: count=$count found='$found' contains '=': '$has_value'"
fi
myapp.delete

kt_test_start "GetEnvironmentList default is NAME=VALUE"
TCustomApplication.new myapp
declare -a env_default=()
myapp.GetEnvironmentList env_default
found=""
for e in "${env_default[@]}"; do
    [[ "$e" == "TCA_ENV_PROBE=probe value" ]] && found=yes
done
if [[ "$found" == "yes" ]]; then
    kt_test_pass "the second argument defaults to false"
else
    kt_test_fail "default GetEnvironmentList did not contain the probe entry"
fi
myapp.delete

kt_test_start "a value containing a newline stays ONE entry [TCA-15]"
TCustomApplication.new myapp
export TCA_NL_PROBE=$'line1\nline2'
declare -a env_nl=()
myapp.GetEnvironmentList env_nl "false"
bogus=0
whole=""
for e in "${env_nl[@]}"; do
    [[ "$e" == "line2" ]] && bogus=$(( bogus + 1 ))
    [[ "$e" == "TCA_NL_PROBE="$'line1\nline2' ]] && whole=yes
done
unset TCA_NL_PROBE
if [[ "$bogus" -eq 0 && "$whole" == "yes" ]]; then
    kt_test_pass "no 'line2' entry appeared; the value round-tripped whole"
else
    kt_test_fail "newline value split: bogus entries=$bogus, whole entry found='$whole'"
fi
myapp.delete

kt_test_start "GetEnvironmentList does not shell out to env or sort [TCA-15]"
# Canaries: if the member calls `env` or `sort`, these shadowing functions run
# and leave a file behind. External tools are the thing being ruled out here.
env() { : > "$TMPD/env_called"; }
sort() { : > "$TMPD/sort_called"; }
rm -f "$TMPD/env_called" "$TMPD/sort_called"
TCustomApplication.new myapp
declare -a env_probe=()
myapp.GetEnvironmentList env_probe "false"
count=$RESULT
myapp.delete
unset -f env sort
if [[ ! -e "$TMPD/env_called" && ! -e "$TMPD/sort_called" && "$count" -gt 0 ]]; then
    kt_test_pass "$count entries, built without env(1) or sort(1)"
else
    kt_test_fail "external tools used: env=$([[ -e "$TMPD/env_called" ]] && echo yes || echo no) sort=$([[ -e "$TMPD/sort_called" ]] && echo yes || echo no) count=$count"
fi

kt_test_start "GetEnvironmentList rejects a bad output-array name [README 1.7]"
TCustomApplication.new myapp
myapp.GetEnvironmentList "not a name"
rc_bad=$?
myapp.GetEnvironmentList RESULT
rc_reserved=$?
if [[ "$rc_bad" == "2" && "$rc_reserved" == "2" ]]; then
    kt_test_pass "rc 2 for a non-identifier and for a reserved name"
else
    kt_test_fail "output-name validation: bad=$rc_bad reserved=$rc_reserved (both expected 2)"
fi
myapp.delete

kt_test_start "EnvironmentVariable returns the value of a real variable"
TCustomApplication.new myapp
myapp.EnvironmentVariable "TCA_ENV_PROBE"
if [[ "$RESULT" == "probe value" ]]; then
    kt_test_pass "the exact value is returned in RESULT"
else
    kt_test_fail "EnvironmentVariable TCA_ENV_PROBE: '$RESULT'"
fi
myapp.delete

kt_test_start "EnvironmentVariable with a non-existent variable"
TCustomApplication.new myapp
myapp.EnvironmentVariable "NON_EXISTENT_VAR_12345"
rc=$?
if [[ $rc -eq 0 && -z "$RESULT" ]]; then
    kt_test_pass "an unset variable is an empty value, not an error"
else
    kt_test_fail "EnvironmentVariable unset: rc=$rc RESULT='$RESULT'"
fi
myapp.delete

kt_test_start "EnvironmentVariable rejects names that are not identifiers [TCA-05]"
TCustomApplication.new myapp
canary="$TMPD/pwn"
rm -f "$canary"
accepted=""
for bad in "" "not valid" "@" "*" "1abc" "a-b" "x[\$(touch '$canary')]"; do
    RESULT="untouched"
    if myapp.EnvironmentVariable "$bad" 2>/dev/null; then
        accepted+="[$bad] "
    elif [[ -n "$RESULT" ]]; then
        accepted+="[$bad RESULT=$RESULT] "
    fi
done
if [[ -z "$accepted" && ! -e "$canary" ]]; then
    kt_test_pass "seven malformed names refused with rc 1, nothing executed"
else
    kt_test_fail "accepted: ${accepted:-none}; canary=$([[ -e "$canary" ]] && echo CREATED || echo absent)"
fi
rm -f "$canary"
myapp.delete

kt_test_start "EnvironmentVariable handles special characters in the value"
TCustomApplication.new myapp
export TEST_VAR='value with spaces & special chars: !@#$%^&*()'
myapp.EnvironmentVariable "TEST_VAR"
if [[ "$RESULT" == 'value with spaces & special chars: !@#$%^&*()' ]]; then
    kt_test_pass "EnvironmentVariable handles special characters"
else
    kt_test_fail "EnvironmentVariable special chars issue: got '$RESULT'"
fi
unset TEST_VAR
myapp.delete

kt_test_start "Log writes TYPE: MESSAGE to stderr, not stdout [TCA-16]"
TCustomApplication.new myapp
out="$(myapp.Log "etInfo" "Test log message" 2>"$ERRF")"
err="$(<"$ERRF")"
if [[ -z "$out" && "$err" == "etInfo: Test log message" ]]; then
    kt_test_pass "stdout is untouched, the line goes to stderr"
else
    kt_test_fail "Log stream: stdout='$out' stderr='$err'"
fi
myapp.delete

kt_test_start "Log applies its format arguments [TCA-16]"
TCustomApplication.new myapp
myapp.Log "etWarning" "Test %s message with %d args" "formatted" 2 2>"$ERRF"
err="$(<"$ERRF")"
if [[ "$err" == "etWarning: Test formatted message with 2 args" ]]; then
    kt_test_pass "the arguments were substituted with printf -v"
else
    kt_test_fail "Log format arguments ignored: '$err'"
fi
myapp.delete

kt_test_start "Log reports a bad format instead of failing silently"
TCustomApplication.new myapp
myapp.Log "etInfo" "count=%d" "abc" 2>"$ERRF"
rc=$?
err="$(<"$ERRF")"
if [[ $rc -eq 0 && "$err" == 'etError: Error formatting message "count=%d" with 1 arguments' ]]; then
    kt_test_pass "the FPC-style formatting error is logged as etError"
else
    kt_test_fail "bad format: rc=$rc stderr='$err'"
fi
myapp.delete

kt_test_start "Log with an empty message still emits the type"
TCustomApplication.new myapp
myapp.Log "etInfo" "" 2>"$ERRF"
err="$(<"$ERRF")"
if [[ "$err" == "etInfo: " ]]; then
    kt_test_pass "an empty message is logged as an empty message"
else
    kt_test_fail "Log with empty message: '$err'"
fi
myapp.delete

kt_test_start "Multiple Log calls each emit one line"
TCustomApplication.new myapp
: > "$ERRF"
for i in 1 2 3 4 5; do
    myapp.Log "etInfo" "Log message %d" "$i" 2>>"$ERRF"
done
lines=0
while IFS= read -r _; do lines=$(( lines + 1 )); done < "$ERRF"
last="$(tail -n 1 "$ERRF")"
if [[ "$lines" == "5" && "$last" == "etInfo: Log message 5" ]]; then
    kt_test_pass "five lines, the last one formatted correctly"
else
    kt_test_fail "multiple Log calls: lines=$lines last='$last'"
fi
myapp.delete

unset TCA_ENV_PROBE
rm -rf "$TMPD"

kt_test_log "007_EnvironmentAndLogging.sh completed"
