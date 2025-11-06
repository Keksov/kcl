#!/bin/bash
# 021_move.sh - Test TFile.Move method

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
parse_args "$@"

# Set up temp directory for this test
init_test_tmpdir "021"

# Test 1: Move existing file
test_start "Move existing file"
echo "content" > "$TEST_TMP_DIR/move_source.tmp"
result=$(tfile.move "$TEST_TMP_DIR/move_source.tmp" "$TEST_TMP_DIR/move_dest.tmp")
if [[ ! -f "$TEST_TMP_DIR/move_source.tmp" && -f "$TEST_TMP_DIR/move_dest.tmp" && "$(cat "$TEST_TMP_DIR"/move_dest.tmp)" == "content" ]]; then
    test_pass "Move existing file"
else
    test_fail "Move existing file"
fi

# Test 2: Move to existing destination
test_start "Move to existing destination"
echo "source2" > "$TEST_TMP_DIR/move_source2.tmp"
echo "dest2" > "$TEST_TMP_DIR/move_dest2.tmp"
if ! result=$(tfile.move "$TEST_TMP_DIR/move_source2.tmp" "$TEST_TMP_DIR/move_dest2.tmp" 2>&1); then
    test_pass "Move to existing destination (correctly failed)"
else
    test_fail "Move to existing destination (should have failed)"
fi

# Test 3: Move non-existing source
test_start "Move non-existing source"
if ! result=$(tfile.move "$TEST_TMP_DIR/nonexist.tmp" "$TEST_TMP_DIR/dest.tmp" 2>&1); then
    test_pass "Move non-existing source (correctly failed)"
else
    test_fail "Move non-existing source (should have failed)"
fi

# Test 4: Move to invalid path
test_start "Move to invalid path"
echo "source3" > "$TEST_TMP_DIR/move_source3.tmp"
if ! result=$(tfile.move "$TEST_TMP_DIR/move_source3.tmp" "/invalid/path/file.tmp" 2>&1); then
    test_pass "Move to invalid path (correctly failed)"
else
    test_fail "Move to invalid path (should have failed)"
fi
