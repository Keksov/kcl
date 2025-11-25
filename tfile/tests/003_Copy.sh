#!/bin/bash
# 003_copy.sh - Test TFile.Copy method
# Auto-migrated to kktests framework

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KKTESTS_LIB_DIR="$SCRIPT_DIR/../../../kktests"
source "$KKTESTS_LIB_DIR/kk-test.sh"

# Source tfile module
TFILE_DIR="$SCRIPT_DIR/.."
source "$TFILE_DIR/tfile.sh"

# Extract test name from filename
TEST_NAME="$(basename "${BASH_SOURCE[0]}" .sh)"
kk_test_init "$TEST_NAME" "$SCRIPT_DIR" "$@"

# Test 1: Copy existing file
kk_test_start "Copy existing file"
printf "content" > "$KK_TEST_TMPDIR/source.tmp"
tfile.copy "$KK_TEST_TMPDIR/source.tmp" "$KK_TEST_TMPDIR/dest.tmp" >/dev/null 2>&1
if [[ -f "$KK_TEST_TMPDIR/dest.tmp" && "$(cat "$KK_TEST_TMPDIR/dest.tmp")" == "content" ]]; then
    kk_test_pass "Copy existing file"
else
    kk_test_fail "Copy existing file"
fi

# Test 2: Copy with overwrite=false (default)
kk_test_start "Copy with overwrite=false"
printf "dest" > "$KK_TEST_TMPDIR/dest2.tmp"
if tfile.copy "$KK_TEST_TMPDIR/source.tmp" "$KK_TEST_TMPDIR/dest2.tmp" >/dev/null 2>&1; then
    kk_test_fail "Copy with overwrite=false (should have failed)"
else
    kk_test_pass "Copy with overwrite=false (correctly failed)"
fi

# Test 3: Copy with overwrite=true
kk_test_start "Copy with overwrite=true"
tfile.copy "$KK_TEST_TMPDIR/source.tmp" "$KK_TEST_TMPDIR/dest2.tmp" true >/dev/null 2>&1
if [[ "$(cat "$KK_TEST_TMPDIR/dest2.tmp")" == "content" ]]; then
    kk_test_pass "Copy with overwrite=true"
else
    kk_test_fail "Copy with overwrite=true"
fi

# Test 4: Copy non-existing source
kk_test_start "Copy non-existing source"
if tfile.copy "$KK_TEST_TMPDIR/nonexist.tmp" "$KK_TEST_TMPDIR/dest.tmp" >/dev/null 2>&1; then
    kk_test_fail "Copy non-existing source (should have failed)"
else
    kk_test_pass "Copy non-existing source (correctly failed)"
fi

# Test 5: Copy to invalid destination path
kk_test_start "Copy to invalid path"
if tfile.copy "$KK_TEST_TMPDIR/source.tmp" "/invalid/path/file.tmp" >/dev/null 2>&1; then
    kk_test_fail "Copy to invalid path (should have failed)"
else
    kk_test_pass "Copy to invalid path (correctly failed)"
fi

# Test 6: Copy empty file
kk_test_start "Copy empty file"
touch "$KK_TEST_TMPDIR/empty.tmp"
tfile.copy "$KK_TEST_TMPDIR/empty.tmp" "$KK_TEST_TMPDIR/empty_dest.tmp" >/dev/null 2>&1
if [[ -f "$KK_TEST_TMPDIR/empty_dest.tmp" && ! -s "$KK_TEST_TMPDIR/empty_dest.tmp" ]]; then
    kk_test_pass "Copy empty file"
else
    kk_test_fail "Copy empty file"
fi
