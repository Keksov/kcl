#!/bin/bash
# 019_get_sym_link_target.sh - Test TFile.GetSymLinkTarget method

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
parse_args "$@"

# Test 1: Get target of valid symlink
test_start "Get target of valid symlink"
echo "target" > test_sym_target.tmp
ln -s test_sym_target.tmp test_sym.tmp
result=$(tfile.getSymLinkTarget "test_sym.tmp")
if [[ $result == true ]]; then
    test_pass "Get target of valid symlink"
else
    test_fail "Get target of valid symlink"
fi

# Test 2: Get target string of valid symlink
test_start "Get target string of valid symlink"
target=$(tfile.getSymLinkTarget "test_sym.tmp" "")
if [[ "$target" == "test_sym_target.tmp" ]]; then
    test_pass "Get target string of valid symlink"
else
    test_fail "Get target string of valid symlink (expected: test_sym_target.tmp, got: $target)"
fi

# Test 3: Get target of broken symlink
test_start "Get target of broken symlink"
ln -s nonexist.tmp test_broken_sym.tmp
result=$(tfile.getSymLinkTarget "test_broken_sym.tmp")
if [[ $result == false ]]; then
    test_pass "Get target of broken symlink"
else
    test_fail "Get target of broken symlink"
fi

# Test 4: Get target of regular file
test_start "Get target of regular file"
result=$(tfile.getSymLinkTarget "test_sym_target.tmp")
if [[ $result == false ]]; then
    test_pass "Get target of regular file"
else
    test_fail "Get target of regular file"
fi
