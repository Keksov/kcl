#!/bin/bash
# 005_create_sym_link.sh - Test TFile.CreateSymLink method

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
parse_args "$@"

# Test 1: Create symlink to existing file
test_start "Create symlink to existing file"
echo "target content" > test_target.tmp
result=$(tfile.createSymLink "test_link.tmp" "test_target.tmp")
if [[ $result == true ]]; then
test_pass "Create symlink to existing file"
else
test_fail "Create symlink to existing file"
fi

# Test 2: Create symlink to directory
test_start "Create symlink to directory"
mkdir -p test_dir
result=$(tfile.createSymLink "test_dir_link.tmp" "test_dir")
if [[ $result == true ]]; then
test_pass "Create symlink to directory"
else
test_fail "Create symlink to directory"
fi

# Test 3: Create symlink to non-existing target
test_start "Create symlink to non-existing target"
if [[ $(tfile.createSymLink "test_broken.tmp" "nonexist.tmp") == false ]]; then
    test_pass "Create symlink to non-existing target (correctly failed)"
else
    test_fail "Create symlink to non-existing target (should have failed)"
fi

# Test 4: Invalid link path
test_start "Create symlink with invalid link path"
if ! result=$(tfile.createSymLink "/invalid/path/link.tmp" "test_target.tmp" 2>&1); then
    test_pass "Create symlink with invalid link path (correctly failed)"
else
    test_fail "Create symlink with invalid link path (should have failed)"
fi
