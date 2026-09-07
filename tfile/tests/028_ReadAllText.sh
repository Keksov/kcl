#!/bin/bash
# 028_read_all_text.sh - Test TFile.ReadAllText method
# Auto-migrated to ktests framework

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

# Source tfile module
TFILE_DIR="$SCRIPT_DIR/.."
source "$TFILE_DIR/tfile.sh"

# Extract test name from filename
TEST_NAME="$(basename "${BASH_SOURCE[0]}" .sh)"
kt_test_init "$TEST_NAME" "$SCRIPT_DIR" "$@"


# _KT_TMPDIR is already set by kt_test_init; re-assigning it (and then using
# it unquoted) hid the fact that the fixture is per-test.


# Test 1: Read text from existing file
kt_test_start "Read text from existing file"
printf '%s\n' "text content" > "$_KT_TMPDIR/readtext.tmp"
text=$(tfile.readAllText "$_KT_TMPDIR/readtext.tmp")
if [[ "$text" == "text content" ]]; then
    kt_test_pass "Read text from existing file"
else
    kt_test_fail "Read text from existing file (got: $text)"
fi

# Test 2: a trailing argument is IGNORED — this port has no TEncoding, and
# readAllText takes only the file name.
kt_test_start "Read text with encoding"
text=$(tfile.readAllText "$_KT_TMPDIR/readtext.tmp" "TEncoding.UTF8")
if [[ "$text" == "text content" ]]; then
    kt_test_pass "Read text with encoding"
else
    kt_test_fail "Read text with encoding"
fi

# Test 3: Read text from empty file
kt_test_start "Read text from empty file"
touch "$_KT_TMPDIR/empty_text.tmp"
text=$(tfile.readAllText "$_KT_TMPDIR/empty_text.tmp")
if [[ -z "$text" ]]; then
    kt_test_pass "Read text from empty file"
else
    kt_test_fail "Read text from empty file"
fi

# Test 4: Read text from non-existing file
kt_test_start "Read text from non-existing file"
if ! text=$(tfile.readAllText "$_KT_TMPDIR/nonexist.tmp" 2>&1); then
    kt_test_pass "Read text from non-existing file (correctly failed)"
else
    kt_test_fail "Read text from non-existing file (should have failed)"
fi
