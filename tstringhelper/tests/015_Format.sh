#!/bin/bash
# Format
# Auto-migrated to ktests framework

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

kt_test_init "Format" "$SCRIPT_DIR" "$@"

# A directory of our own: the ktests fixture temp dir is named after $0, which
# is "bash" for every file the runner starts, and the runner runs files in
# PARALLEL — a neighbour's teardown deletes it while we are using it, and a
# redirect into a vanished directory means the member never runs at all
# (kcl_ledger.json, found_in_P4/P4-F2).
PRIVTMP="$SCRIPT_DIR/.tmp/$(basename "${BASH_SOURCE[0]}" .sh)"
mkdir -p "$PRIVTMP"

# Source tstringhelper if needed
TSTRINGHELPER_DIR="$SCRIPT_DIR/.."
[[ -f "$TSTRINGHELPER_DIR/tstringhelper.sh" ]] && source "$TSTRINGHELPER_DIR/tstringhelper.sh"


# Test 1: Simple string formatting
kt_test_start "Format - simple string substitution"
result=$(string.format "Hello %s" "World")
if [[ "$result" == "Hello World" ]]; then
    kt_test_pass "Format - simple string substitution"
else
    kt_test_fail "Format - simple string substitution (expected: 'Hello World', got: '$result')"
fi

# Test 2: Multiple string substitutions
kt_test_start "Format - multiple substitutions"
result=$(string.format "%s is %s" "This" "great")
if [[ "$result" == "This is great" ]]; then
    kt_test_pass "Format - multiple substitutions"
else
    kt_test_fail "Format - multiple substitutions (expected: 'This is great', got: '$result')"
fi

# Test 3: Integer substitution
kt_test_start "Format - integer substitution"
result=$(string.format "Number: %d" 42)
if [[ "$result" == "Number: 42" ]]; then
    kt_test_pass "Format - integer substitution"
else
    kt_test_fail "Format - integer substitution (expected: 'Number: 42', got: '$result')"
fi

# Test 4: Mixed substitutions
kt_test_start "Format - mixed types"
result=$(string.format "%s has %d apples" "John" 5)
if [[ "$result" == "John has 5 apples" ]]; then
    kt_test_pass "Format - mixed types"
else
    kt_test_fail "Format - mixed types (expected: 'John has 5 apples', got: '$result')"
fi

# Test 5: No substitutions
kt_test_start "Format - no placeholder"
result=$(string.format "Just a string")
if [[ "$result" == "Just a string" ]]; then
    kt_test_pass "Format - no placeholder"
else
    kt_test_fail "Format - no placeholder (expected: 'Just a string', got: '$result')"
fi

# Test 6: Empty format string
kt_test_start "Format - empty format string"
result=$(string.format "")
if [[ "$result" == "" ]]; then
    kt_test_pass "Format - empty format string"
else
    kt_test_fail "Format - empty format string (expected: '', got: '$result')"
fi

# Test 7: Escaped percent sign
kt_test_start "Format - escaped percent"
result=$(string.format "100%% complete")
if [[ "$result" == "100% complete" || "$result" == "100%% complete" ]]; then
    kt_test_pass "Format - escaped percent"
else
    kt_test_fail "Format - escaped percent (expected: '100% complete', got: '$result')"
fi

# Test 8: Three parameters
kt_test_start "Format - three parameters"
result=$(string.format "%s-%s-%s" "a" "b" "c")
if [[ "$result" == "a-b-c" ]]; then
    kt_test_pass "Format - three parameters"
else
    kt_test_fail "Format - three parameters (expected: 'a-b-c', got: '$result')"
fi

# Test 9: String with special characters
kt_test_start "Format - special characters in format"
result=$(string.format "Email: %s@%s" "user" "example.com")
if [[ "$result" == "Email: user@example.com" ]]; then
    kt_test_pass "Format - special characters in format"
else
    kt_test_fail "Format - special characters in format (expected: 'Email: user@example.com', got: '$result')"
fi

# Test 10: Numeric string parameter
kt_test_start "Format - numeric string parameter"
result=$(string.format "ID: %s" "12345")
if [[ "$result" == "ID: 12345" ]]; then
    kt_test_pass "Format - numeric string parameter"
else
    kt_test_fail "Format - numeric string parameter (expected: 'ID: 12345', got: '$result')"
fi

# Test 11: Format string beginning with dash
kt_test_start "Format - leading dash literal"
result=$(string.format "-%s" "x" 2>/dev/null)
if [[ "$result" == "-x" ]]; then
    kt_test_pass "Format - leading dash literal"
else
    kt_test_fail "Format - leading dash literal (expected: '-x', got: '$result')"
fi

# --- P5: the format error contract (finding TSH-15) ------------------------
# `string.format "%d" abc` used to surface bash's own diagnostic —
# "kklass.sh: line 974: printf: abc: invalid number" — pointing at the
# FRAMEWORK's line number, and then answered "0" with rc 0. printf's stderr is
# now captured (rc 1 + empty RESULT, kcl/README.md 1.2) and only repeated
# under VERBOSE_KKLASS=debug, prefixed with the member's own name.
#
# What `format` is: Pascal's Format() semantics are NOT ported — this is bash
# printf, so the directives are printf's (%s %d %5.2f ...), Pascal's argument
# indices (%0:s) are unsupported, and printf's rule of REUSING the format
# while arguments remain applies. That is documented in the unit README.
kt_test_start "a bad numeric argument is rc 1 with an empty RESULT [TSH-15]"
RESULT="__unset__"
rc=0
# A DIRECT call, redirected into a file: `$( )` would run the member in a
# subshell, where the RESULT it sets could never reach this shell.
FMT_OUT="$PRIVTMP/stdout.txt"
: > "$FMT_OUT"
string.format "%d" abc > "$FMT_OUT" 2>&1 || rc=$?
printed="$(<"$FMT_OUT")"
if (( rc == 1 )) && [[ -z "$RESULT" && -z "$printed" ]]; then
    kt_test_pass "rc 1, RESULT empty, silent"
else
    kt_test_fail "rc=$rc RESULT='$RESULT' printed='$printed'"
fi

kt_test_start "no kklass line number ever reaches the caller [TSH-15]"
printed="$(string.format "%d" abc 2>&1)" || :
if [[ "$printed" != *kklass* && "$printed" != *"line "* ]]; then
    kt_test_pass "nothing leaked"
else
    kt_test_fail "leaked: '$printed'"
fi

kt_test_start "an invalid format directive is rc 1 [TSH-15]"
RESULT="__unset__"
rc=0
string.format "%q%Z" x >/dev/null 2>&1 || rc=$?
if (( rc == 1 )) && [[ -z "$RESULT" ]]; then
    kt_test_pass "rc 1"
else
    kt_test_fail "rc=$rc RESULT='$RESULT'"
fi

kt_test_start "the diagnostic appears on stderr under VERBOSE_KKLASS=debug [1.2]"
err="$(VERBOSE_KKLASS=debug string.format "%d" abc 2>&1 >/dev/null)" || :
if [[ "$err" == *format* || "$err" == *printf* ]]; then
    kt_test_pass "debug diagnostic present"
else
    kt_test_fail "no diagnostic under debug: '$err'"
fi

kt_test_start "a direct call is silent and answers in RESULT [D3]"
RESULT="__unset__"
printed="$(string.format "Hello %s" World 2>&1)"
if [[ "$printed" == "Hello World" ]]; then
    string.format "Hello %s" World >/dev/null 2>&1 || :
    if [[ "$RESULT" == "Hello World" ]]; then
        kt_test_pass "RESULT and \$( ) agree"
    else
        kt_test_fail "direct RESULT='$RESULT'"
    fi
else
    kt_test_fail "\$( ) gave '$printed'"
fi

kt_test_start "a trailing newline in the format survives (no \$( ) stripping) [D3]"
RESULT="__unset__"
string.format 'a\n' >/dev/null 2>&1 || :
if [[ "$RESULT" == $'a\n' ]]; then
    kt_test_pass "trailing newline kept in RESULT"
else
    kt_test_fail "RESULT=$(printf '%q' "$RESULT")"
fi

kt_test_start "printf reuses the format while arguments remain (documented) [TSH-15]"
RESULT="__unset__"
string.format "%s," a b c >/dev/null 2>&1 || :
if [[ "$RESULT" == "a,b,c," ]]; then
    kt_test_pass "a,b,c,"
else
    kt_test_fail "RESULT='$RESULT'"
fi

kt_test_start "a format that looks like an option is not eaten [X-ECHO]"
RESULT="__unset__"
string.format -- >/dev/null 2>&1 || :
if [[ "$RESULT" == "--" ]]; then
    kt_test_pass "-- is data"
else
    kt_test_fail "RESULT='$RESULT'"
fi
